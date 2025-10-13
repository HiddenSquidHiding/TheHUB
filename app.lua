-- app.lua
-- Profile router + feature wiring. Chooses a profile from games.lua and shows only that UI.

----------------------------------------------------------------------
-- Safe utils
----------------------------------------------------------------------
local function getUtils()
  local parent = script and script.Parent
  if parent and parent._deps and parent._deps.utils then return parent._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return {
    notify = function(_,_) end,
    waitForCharacter = function()
      local Players = game:GetService("Players")
      local plr = Players.LocalPlayer
      while true do
        local ch = plr.Character
        if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
          return ch
        end
        plr.CharacterAdded:Wait()
        task.wait()
      end
    end,
  }
end
local utils = getUtils()

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function safeRequire(modName)
  local ok, mod = pcall(function() return require(script.Parent[modName]) end)
  if not ok then
    warn(("-- [app.lua] optional module '%s' not available: %s"):format(modName, tostring(mod)))
    return nil
  end
  return mod
end

local function pickProfile()
  local ok, profiles = pcall(function() return require(script.Parent.games) end)
  if not ok or type(profiles) ~= "table" then
    warn("[app.lua] games.lua missing or invalid; falling back to default")
    profiles = { default = { name = "Generic", modules={"anti_afk"}, ui={ antiAFK=true } } }
  end

  local placeKey = "place:" .. tostring(game.PlaceId)
  local uniKey   = tostring(game.GameId)

  local profile = profiles[placeKey] or profiles[uniKey] or profiles.default
  if not profile then
    profile = { name="Generic", modules={"anti_afk"}, ui={ antiAFK=true } }
  end

  print(("[WoodzHUB] Profile: %s (key=%s / %s)"):format(profile.name or "?", placeKey, uniKey))
  return profile
end

----------------------------------------------------------------------
-- Wire per-profile
----------------------------------------------------------------------
local profile = pickProfile()

-- Load requested modules (optional)
local farm        = table.find(profile.modules or {}, "farm")                    and safeRequire("farm") or nil
local smartFarm   = table.find(profile.modules or {}, "smart_target")           and safeRequire("smart_target") or nil
local merchants   = table.find(profile.modules or {}, "merchants")              and safeRequire("merchants") or nil
local crates      = table.find(profile.modules or {}, "crates")                 and safeRequire("crates") or nil
local antiAFK     = table.find(profile.modules or {}, "anti_afk")               and safeRequire("anti_afk") or nil
local redeemCodes = table.find(profile.modules or {}, "redeem_unredeemed_codes")and safeRequire("redeem_unredeemed_codes") or nil
local fastlevel   = table.find(profile.modules or {}, "fastlevel")              and safeRequire("fastlevel") or nil
local dungeonBE   = table.find(profile.modules or {}, "dungeon_be")             and safeRequire("dungeon_be") or nil

-- Always try Rayfield UI (but render only what profile.ui asks for)
local uiRF = safeRequire("ui_rayfield")

-- Track feature state (only those we may use)
local state = {
  autoFarm       = false,
  smartFarm      = false,
  antiAFK        = false,
  crates         = false,
  merch1         = false,
  merch2         = false,
  fastlevel      = false,
  dungeonAuto    = false,
  dungeonReplay  = false,
}

-- Exposed to Rayfield label
local RF = nil
local lastLabel, lastAt = nil, 0
local function setCurrentTarget(text)
  text = text or "Current Target: None"
  local now = tick()
  if text == lastLabel and (now - lastAt) < 0.15 then return end
  lastLabel, lastAt = text, now
  if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(text) end) end
end

-- Farm helpers
local function startAutoFarm()
  if not farm then return end
  farm.setupAutoAttackRemote()
  task.spawn(function()
    farm.runAutoFarm(function() return state.autoFarm end, setCurrentTarget)
  end)
end
local function stopAutoFarm()
  state.autoFarm = false
  setCurrentTarget("Current Target: None")
end

local function startSmartFarm()
  if not smartFarm then return end
  local function resolveMonsterInfo()
    local RS = ReplicatedStorage
    for _, path in ipairs({
      {"GameInfo","MonsterInfo"},{"MonsterInfo"},{"Shared","MonsterInfo"},
      {"Modules","MonsterInfo"},{"Configs","MonsterInfo"},
    }) do
      local node = RS
      local ok = true
      for _, name in ipairs(path) do node = node:FindFirstChild(name); if not node then ok=false; break end end
      if ok and node and node:IsA("ModuleScript") then return node end
    end
    for _, d in ipairs(RS:GetDescendants()) do
      if d:IsA("ModuleScript") and d.Name=="MonsterInfo" then return d end
    end
    return nil
  end
  local module = resolveMonsterInfo()
  if not module then
    utils.notify("🌲 Smart Farm", "MonsterInfo not found in ReplicatedStorage.", 4)
    return
  end
  task.spawn(function()
    smartFarm.runSmartFarm(function() return state.smartFarm end, setCurrentTarget, { module = module, safetyBuffer = 0.8, refreshInterval = 0.05 })
  end)
end
local function stopSmartFarm()
  state.smartFarm = false
  setCurrentTarget("Current Target: None")
end

-- Crates loop
local function startCrates()
  if not crates then return end
  crates.sniffCrateEvents()
  task.spawn(function()
    crates.autoOpenCratesEnabledLoop(function() return state.crates end)
  end)
end

-- Merchants loops
local function startMerch1()
  if not merchants then return end
  task.spawn(function()
    merchants.autoBuyLoop("SmelterMerchantService", function() return state.merch1 end, function() end)
  end)
end
local function startMerch2()
  if not merchants then return end
  task.spawn(function()
    merchants.autoBuyLoop("SmelterMerchantService2", function() return state.merch2 end, function() end)
  end)
end

-- Fast level piggybacks on Auto-Farm
local function startFastLevel()
  if not fastlevel then return end
  fastlevel.enable()
  if not state.autoFarm and farm then
    state.autoFarm = true
    if RF and RF.setAutoFarm then RF.setAutoFarm(true) end
    startAutoFarm()
  end
end
local function stopFastLevel()
  if fastlevel then fastlevel.disable() end
  -- also turn off auto farm per your last request
  if state.autoFarm then
    stopAutoFarm()
    if RF and RF.setAutoFarm then RF.setAutoFarm(false) end
  end
end

-- Dungeon (Brainrot Evolutions Dungeon) module
local function startDungeon()
  if not dungeonBE then return end
  dungeonBE.init() -- idempotent
  dungeonBE.setAuto(true)
  dungeonBE.setReplay(state.dungeonReplay)
end
local function stopDungeon()
  if not dungeonBE then return end
  dungeonBE.setAuto(false)
end

----------------------------------------------------------------------
-- Build Rayfield (conditionally rendered) & wire handlers
----------------------------------------------------------------------
if uiRF then
  RF = uiRF.build({
    ui = profile.ui or {},

    -- Model picker helpers (if present)
    onModelSearch = function(q)
      if farm and farm.filterMonsterModels then return farm.filterMonsterModels(q) end
      return {}
    end,
    onModelSet = function(list)
      if farm and farm.setSelected then farm.setSelected(list) end
    end,
    onClearAll = function()
      if farm and farm.setSelected then farm.setSelected({}) end
    end,

    -- Farm toggles
    onAutoFarmToggle = function(v)
      if not farm then return end
      local want = (v ~= nil) and v or (not state.autoFarm)
      if want then
        if state.smartFarm then state.smartFarm=false; if RF and RF.setSmartFarm then RF.setSmartFarm(false) end; stopSmartFarm() end
        state.autoFarm = true; startAutoFarm()
      else
        stopAutoFarm()
      end
    end,
    onSmartFarmToggle = function(v)
      if not smartFarm then return end
      local want = (v ~= nil) and v or (not state.smartFarm)
      if want then
        if state.autoFarm then state.autoFarm=false; if RF and RF.setAutoFarm then RF.setAutoFarm(false) end; stopAutoFarm() end
        state.smartFarm = true; startSmartFarm()
      else
        stopSmartFarm()
      end
    end,

    -- Options
    onToggleAntiAFK = function(v)
      if not antiAFK then return end
      state.antiAFK = (v ~= nil) and v or (not state.antiAFK)
      if state.antiAFK then antiAFK.enable() else antiAFK.disable() end
    end,
    onToggleCrates = function(v)
      if not crates then return end
      local want = (v ~= nil) and v or (not state.crates)
      state.crates = want
      if want then startCrates() end
    end,
    onToggleMerchant1 = function(v)
      if not merchants then return end
      state.merch1 = (v ~= nil) and v or (not state.merch1)
      if state.merch1 then startMerch1() end
    end,
    onToggleMerchant2 = function(v)
      if not merchants then return end
      state.merch2 = (v ~= nil) and v or (not state.merch2)
      if state.merch2 then startMerch2() end
    end,
    onRedeemCodes = function()
      if not redeemCodes then return end
      task.spawn(function()
        local ok, err = pcall(function()
          redeemCodes.run({ dryRun=false, concurrent=true, delayBetween=0.25 })
        end)
        if not ok then utils.notify("Codes", "Redeem failed: "..tostring(err), 4) end
      end)
    end,
    onFastLevelToggle = function(v)
      if not fastlevel or not farm then return end
      local want = (v ~= nil) and v or (not state.fastlevel)
      state.fastlevel = want
      if want then startFastLevel() else stopFastLevel() end
    end,

    -- Dungeon (Brainrot Dungeon) controls
    onDungeonAutoToggle = function(v)
      if not dungeonBE then return end
      local want = (v ~= nil) and v or (not state.dungeonAuto)
      state.dungeonAuto = want
      if want then startDungeon() else stopDungeon() end
    end,
    onDungeonReplayToggle = function(v)
      if not dungeonBE then return end
      local want = (v ~= nil) and v or (not state.dungeonReplay)
      state.dungeonReplay = want
      dungeonBE.setReplay(want)
    end,
  })
end

utils.notify("🌲 WoodzHUB", "Loaded profile: "..(profile.name or "?"), 4)
