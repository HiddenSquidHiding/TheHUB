-- app.lua
-- Profile-driven boot: picks features from games.lua, builds Rayfield UI, wires handlers.

----------------------------------------------------------------------
-- Double-boot guard
----------------------------------------------------------------------
if _G.WOODZHUB_BOOT then return end
_G.WOODZHUB_BOOT = true

----------------------------------------------------------------------
-- Safe utils
----------------------------------------------------------------------
local function getUtils()
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return {
    notify = function(title, msg) print(("[%s] %s"):format(title, msg)) end,
    waitForCharacter = function()
      local Players = game:GetService("Players")
      local plr = Players.LocalPlayer
      while true do
        local ch = plr and plr.Character
        if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
          return ch
        end
        if plr then plr.CharacterAdded:Wait() end
        task.wait()
      end
    end,
  }
end
local utils = getUtils()

----------------------------------------------------------------------
-- Try-require helper (executor-friendly)
----------------------------------------------------------------------
local function tryRequire(name)
  local ok, mod = pcall(function() return require(name) end)
  if ok then return mod end
  return nil
end

----------------------------------------------------------------------
-- Load games profile
----------------------------------------------------------------------
local games = tryRequire("games")
local placeKey    = ("place:%s"):format(tostring(game.PlaceId))
local universeKey = ("universe:%s"):format(tostring(game.GameId))
local profile = (games and (games[placeKey] or games[universeKey] or games.default))
                or { name = "Generic", modules = {}, ui = {} }

print(("[app.lua] profile: %s (key=%s%s)"):format(
  tostring(profile.name or "Generic"),
  (games and (games[placeKey] and placeKey or games[universeKey] and universeKey or "default") or "default"),
  ""
))

----------------------------------------------------------------------
-- Load optional modules advertised by the profile
----------------------------------------------------------------------
local farm, smart, merch, crates, afk, redeem, fastlevel, dungeon = nil,nil,nil,nil,nil,nil,nil,nil

for _, m in ipairs(profile.modules or {}) do
  if m == "farm"                     then farm     = tryRequire("farm") end
  if m == "smart_target"             then smart    = tryRequire("smart_target") end
  if m == "merchants"                then merch    = tryRequire("merchants") end
  if m == "crates"                   then crates   = tryRequire("crates") end
  if m == "anti_afk"                 then afk      = tryRequire("anti_afk") end
  if m == "redeem_unredeemed_codes"  then redeem   = tryRequire("redeem_unredeemed_codes") end
  if m == "fastlevel"                then fastlevel= tryRequire("fastlevel") end
  if m == "dungeon_be"               then dungeon  = tryRequire("dungeon_be") end
end

----------------------------------------------------------------------
-- Build Rayfield UI with flags
----------------------------------------------------------------------
local ui_rf = tryRequire("ui_rayfield")
if not (ui_rf and ui_rf.build) then
  warn("[app.lua] ui_rayfield.lua missing - UI not loaded. Core still running.")
  return
end

-- Helper: throttled label updates
local lastLabelText, lastLabelAt = nil, 0
local function setCurrentTarget(text, UI)
  text = text or "Ready."
  local now = tick()
  if text == lastLabelText and (now - lastLabelAt) < 0.15 then return end
  lastLabelText, lastLabelAt = text, now
  if UI and UI.setCurrentTarget then pcall(function() UI.setCurrentTarget(text) end) end
end

-- Resolve MonsterInfo for smart_target (optional)
local function resolveMonsterInfo()
  local RS = game:GetService("ReplicatedStorage")
  local candidates = {
    {"GameInfo","MonsterInfo"}, {"MonsterInfo"}, {"Shared","MonsterInfo"},
    {"Modules","MonsterInfo"}, {"Configs","MonsterInfo"},
  }
  for _, path in ipairs(candidates) do
    local node = RS
    local ok = true
    for _, name in ipairs(path) do
      node = node:FindFirstChild(name)
      if not node then ok=false; break end
    end
    if ok and node and node:IsA("ModuleScript") then return node end
  end
  for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then return d end
  end
  return nil
end

-- UI Handlers (only call into modules that are present)
local autoFarmEnabled  = false
local smartFarmEnabled = false

local handlers = {
  -- FARM
  onAutoFarmToggle = function(v)
    if not farm or not farm.runAutoFarm then return end
    local newState = (v ~= nil) and v or (not autoFarmEnabled)

    if newState and smartFarmEnabled then
      smartFarmEnabled = false
      if UI and UI.setSmartFarm then UI.setSmartFarm(false) end
      utils.notify("🌲 Smart Farm", "disabled", 3)
    end

    autoFarmEnabled = newState
    if autoFarmEnabled then
      if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
      utils.notify("🌲 Auto-Farm", "enabled", 3)
      task.spawn(function()
        farm.runAutoFarm(function() return autoFarmEnabled end, function(t) setCurrentTarget(t, UI) end)
      end)
    else
      setCurrentTarget("Ready.", UI)
      utils.notify("🌲 Auto-Farm", "disabled", 3)
    end
  end,

  -- SMART FARM
  onSmartFarmToggle = function(v)
    if not smart or not smart.runSmartFarm then return end
    local newState = (v ~= nil) and v or (not smartFarmEnabled)

    if newState and autoFarmEnabled then
      autoFarmEnabled = false
      if UI and UI.setAutoFarm then UI.setAutoFarm(false) end
      utils.notify("🌲 Auto-Farm", "disabled", 3)
    end

    smartFarmEnabled = newState
    if smartFarmEnabled then
      local module = resolveMonsterInfo()
      utils.notify("🌲 Smart Farm", module and "enabled" or "MonsterInfo not found, stopping", 4)
      if module then
        task.spawn(function()
          smart.runSmartFarm(
            function() return smartFarmEnabled end,
            function(t) setCurrentTarget(t, UI) end,
            { module = module, safetyBuffer = 0.8, refreshInterval = 0.05 }
          )
        end)
      else
        smartFarmEnabled = false
        if UI and UI.setSmartFarm then UI.setSmartFarm(false) end
      end
    else
      setCurrentTarget("Ready.", UI)
      utils.notify("🌲 Smart Farm", "disabled", 3)
    end
  end,

  -- ANTI-AFK
  onToggleAntiAFK = function(v)
    if not afk then return end
    local on = (v ~= nil) and v or true
    if on and afk.enable then afk.enable()
    elseif afk.disable then afk.disable() end
    utils.notify("🌲 Anti-AFK", on and "enabled" or "disabled", 3)
  end,

  -- MERCHANTS
  onToggleMerchant1 = function(v)
    if not merch or not merch.autoBuyLoop then return end
    local enabled = (v == true)
    if enabled then
      utils.notify("🌲 Merchant — Chicleteiramania", "enabled", 3)
      task.spawn(function()
        merch.autoBuyLoop("SmelterMerchantService", function() return enabled end, function(_) end)
      end)
    else
      utils.notify("🌲 Merchant — Chicleteiramania", "disabled", 3)
    end
  end,

  onToggleMerchant2 = function(v)
    if not merch or not merch.autoBuyLoop then return end
    local enabled = (v == true)
    if enabled then
      utils.notify("🌲 Merchant — Bombardino Sewer", "enabled", 3)
      task.spawn(function()
        merch.autoBuyLoop("SmelterMerchantService2", function() return enabled end, function(_) end)
      end)
    else
      utils.notify("🌲 Merchant — Bombardino Sewer", "disabled", 3)
    end
  end,

  -- CRATES
  onToggleCrates = function(v)
    if not crates or not crates.autoOpenCratesEnabledLoop then return end
    local on = (v == true)
    if on and crates.refreshCrateInventory then crates.refreshCrateInventory(true) end
    utils.notify("🌲 Crates", on and "enabled" or "disabled", 3)
    if on then
      task.spawn(function()
        crates.autoOpenCratesEnabledLoop(function() return on end)
      end)
    end
  end,

  -- CODES
  onRedeemCodes = function()
    if not redeem or not redeem.run then return end
    task.spawn(function()
      local ok, err = pcall(function()
        redeem.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
      end)
      if not ok then utils.notify("Codes", "Redeem failed: " .. tostring(err), 4) end
    end)
  end,

  -- Fast Level 70+
  onFastLevelToggle = function(v)
    if not fastlevel then return end
    local want = (v ~= nil) and v or (not (fastlevel.isEnabled and fastlevel.isEnabled()))
    if want then
      if smartFarmEnabled then
        smartFarmEnabled = false
        if UI and UI.setSmartFarm then UI.setSmartFarm(false) end
        utils.notify("🌲 Smart Farm", "disabled", 3)
      end
      if fastlevel.enable then fastlevel.enable() end
      utils.notify("🌲 Instant Level 70+", "enabled — targeting Sahur only", 4)
      if not autoFarmEnabled and farm and farm.runAutoFarm then
        autoFarmEnabled = true
        if UI and UI.setAutoFarm then UI.setAutoFarm(true) end
        if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
        if farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
        utils.notify("🌲 Auto-Farm", "enabled", 3)
        task.spawn(function()
          farm.runAutoFarm(function() return autoFarmEnabled end, function(t) setCurrentTarget(t, UI) end)
        end)
      else
        if farm and farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
      end
    else
      if fastlevel.disable then fastlevel.disable() end
      utils.notify("🌲 Instant Level 70+", "disabled", 3)
      if farm and farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end
      -- Also toggle Auto-Farm off when FastLevel is turned off (as you requested)
      if autoFarmEnabled then
        autoFarmEnabled = false
        if UI and UI.setAutoFarm then UI.setAutoFarm(false) end
        utils.notify("🌲 Auto-Farm", "disabled", 3)
      end
    end
  end,

  ------------------------------------------------------------------
  -- DUNGEON
  ------------------------------------------------------------------
  onDungeonAuto = function(v)
    if not dungeon then return end
    if dungeon.init then dungeon.init() end
    if dungeon.setAuto then dungeon.setAuto(v == true) end
    utils.notify("🌲 Dungeon", (v and "Auto-Attack ON" or "Auto-Attack OFF"), 3)
  end,

  onDungeonReplay = function(v)
    if not dungeon then return end
    if dungeon.init then dungeon.init() end
    if dungeon.setReplay then dungeon.setReplay(v == true) end
    utils.notify("🌲 Dungeon", (v and "Auto Replay ON" or "Auto Replay OFF"), 3)
  end,
}

-- Build Rayfield
UI = ui_rf.build(handlers, profile.ui or {})
utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)

-- If dungeon is present, init once (leave toggles OFF by default)
if dungeon and dungeon.init then
  dungeon.init()
  if UI.setDungeonAuto   then UI.setDungeonAuto(false)   end
  if UI.setDungeonReplay then UI.setDungeonReplay(false) end
end
