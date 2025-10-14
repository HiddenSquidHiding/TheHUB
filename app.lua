-- app.lua — HTTP-friendly hub core (exports start()).

local StarterGui = game:GetService("StarterGui")
_G.__WOODZ_UTILS = _G.__WOODZ_UTILS or {
  notify = function(title, msg, dur)
    dur = dur or 3
    pcall(StarterGui.SetCore, StarterGui, "SendNotification", {
      Title = tostring(title), Text = tostring(msg), Duration = dur
    })
    print(("[%s] %s"):format(tostring(title), tostring(msg)))
  end,
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
local function note(t, m, d) _G.__WOODZ_UTILS.notify(t, m, d or 3) end

-- Small fetcher your init.lua should have set as _G.__WOODZ_REQUIRE (HTTP loader).
local function r(name)
  local hook = rawget(_G, "__WOODZ_REQUIRE")
  if type(hook) ~= "function" then return nil end
  local ok, mod = pcall(hook, name)
  return ok and mod or nil
end

-- Optional modules (loaded if present)
local UI        = r("ui_rayfield")
local gamesCfg  = r("games")
local farm      = r("farm")
local smart     = r("smart_target")
local merchants = r("merchants")
local crates    = r("crates")
local antiAFK   = r("anti_afk")
local redeem    = r("redeem_unredeemed_codes")
local fastlevel = r("fastlevel")
local dungeonBE = r("dungeon_be")

-- 🔹 NEW: load solo.lua at boot so the Private Server button can call it later.
-- IMPORTANT: your solo.lua must NOT teleport on load; it should only define _G.TeleportToPrivateServer.
local solo = r("solo")  -- ignore return; we just want its side-effect (define the function)

-- Pick a profile from games.lua
local function profileFromGames()
  local default = {
    name = "Generic",
    ui = {
      modelPicker = true, currentTarget = true,
      autoFarm = true, smartFarm = false,
      merchants = false, crates = false, antiAFK = true,
      redeemCodes = true, fastlevel = true, privateServer = true, -- keep on
      dungeonAuto = false, dungeonReplay = false,
    },
  }
  if type(gamesCfg) ~= "table" then
    note("[app.lua]", "games.lua missing or invalid; using default", 4)
    return default, "default"
  end
  local keyPlace = "place:" .. tostring(game.PlaceId)
  local keyUni   = tostring(game.GameId)
  local p = gamesCfg[keyPlace] or gamesCfg[keyUni] or gamesCfg.default or default
  local k = (gamesCfg[keyPlace] and keyPlace) or (gamesCfg[keyUni] and keyUni) or "default"
  return p, k
end

local App = {}

function App.start()
  if _G.__WOODZ_APP_STARTED then return end
  _G.__WOODZ_APP_STARTED = true

  local profile, key = profileFromGames()
  note("[app.lua]", ("profile: %s (key=%s)"):format(profile.name or "?", key), 3)

  if not UI or type(UI.build) ~= "function" then
    note("[ui_rayfield]", "Rayfield failed to load (ui_rayfield.lua missing or build() not found).", 6)
    return
  end

  pcall(function() if farm and farm.getMonsterModels then farm.getMonsterModels() end end)

  local autoFarmOn, smartOn, fastOn = false, false, false

  local lastLbl, lastAt = nil, 0
  local function setCurrentTarget(s)
    s = s or "Current Target: None"
    local now = tick()
    if s==lastLbl and now-lastAt<0.15 then return end
    lastLbl, lastAt = s, now
    if App.UI and App.UI.setCurrentTarget then pcall(App.UI.setCurrentTarget, s) end
  end

  -- Picker adapters for UI
  local function picker_fetch(searchText)
    if not farm then return {} end
    if type(farm.filterMonsterModels) == "function" then
      local ok, list = pcall(farm.filterMonsterModels, searchText or "")
      if ok and type(list) == "table" then
        local out = {}
        for _, v in ipairs(list) do if typeof(v) == "string" then table.insert(out, v) end end
        return out
      end
    elseif type(farm.getMonsterModels) == "function" then
      local ok, list = pcall(farm.getMonsterModels)
      if ok and type(list) == "table" then
        local out = {}
        local text = tostring(searchText or ""):lower()
        for _, v in ipairs(list) do
          if typeof(v) == "string" and (text=="" or v:lower():find(text, 1, true)) then
            table.insert(out, v)
          end
        end
        return out
      end
    end
    return {}
  end
  local function picker_getSelected()
    if farm and type(farm.getSelected) == "function" then
      local ok, sel = pcall(farm.getSelected)
      if ok and type(sel) == "table" then return sel end
    end
    return {}
  end
  local function picker_setSelected(list)
    if farm and type(farm.setSelected) == "function" then pcall(farm.setSelected, list or {}) end
  end
  local function picker_clear() picker_setSelected({}) end

  local function startAutoFarmLoop()
    if not farm or type(farm.runAutoFarm) ~= "function" then
      note("Auto-Farm", "farm.lua missing", 4); return
    end
    if type(farm.setupAutoAttackRemote) == "function" then pcall(farm.setupAutoAttackRemote) end
    task.spawn(function()
      farm.runAutoFarm(function() return autoFarmOn end, setCurrentTarget)
    end)
  end

  -- Build UI
  App.UI = UI.build({
    picker_getOptions = picker_fetch,
    picker_getSelected = picker_getSelected,
    picker_setSelected = picker_setSelected,
    picker_clear = picker_clear,

    onAutoFarmToggle = (profile.ui.autoFarm and function(v)
      autoFarmOn = (v ~= nil) and v or (not autoFarmOn)
      if autoFarmOn then startAutoFarmLoop() else setCurrentTarget("Current Target: None") end
    end) or nil,

    onSmartFarmToggle = (profile.ui.smartFarm and function(v)
      smartOn = (v ~= nil) and v or (not smartOn)
      if smartOn then
        if smart and type(smart.runSmartFarm) == "function" then
          task.spawn(function()
            smart.runSmartFarm(function() return smartOn end, setCurrentTarget, { safetyBuffer=0.8, refreshInterval=0.05 })
          end)
        else note("Smart Farm","smart_target.lua missing",4) end
      else setCurrentTarget("Current Target: None") end
    end) or nil,

    onToggleAntiAFK = (profile.ui.antiAFK and function(v)
      local on = (v ~= nil) and v or false
      if antiAFK and antiAFK.enable and antiAFK.disable then
        if on then antiAFK.enable() else antiAFK.disable() end
      else note("Anti-AFK","anti_afk.lua missing",4) end
    end) or nil,

    onToggleMerchant1 = (profile.ui.merchants and function(v)
      local on = (v ~= nil) and v or false
      if merchants and merchants.autoBuyLoop and on then
        task.spawn(function() merchants.autoBuyLoop("SmelterMerchantService", function() return on end, function() end) end)
      end
    end) or nil,
    onToggleMerchant2 = (profile.ui.merchants and function(v)
      local on = (v ~= nil) and v or false
      if merchants and merchants.autoBuyLoop and on then
        task.spawn(function() merchants.autoBuyLoop("SmelterMerchantService2", function() return on end, function() end) end)
      end
    end) or nil,

    onToggleCrates = (profile.ui.crates and function(v)
      local on = (v ~= nil) and v or false
      if crates and crates.autoOpenCratesEnabledLoop and on then
        task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return on end) end)
      end
    end) or nil,

    onRedeemCodes = (profile.ui.redeemCodes and function()
      if redeem and redeem.run then task.spawn(function() redeem.run({dryRun=false,concurrent=true,delayBetween=0.25}) end)
      else note("Codes","redeem_unredeemed_codes.lua missing",4) end
    end) or nil,

    onFastLevelToggle = (profile.ui.fastlevel and function(v)
      fastOn = (v ~= nil) and v or (not fastOn)
      if fastOn then
        local sahurName = "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur"
        local list = { sahurName }
        pcall(function() if farm and farm.setSelected then farm.setSelected(list) end end)
        pcall(function() if farm and farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end end)
        autoFarmOn = true
        if App.UI and App.UI.setAutoFarm then pcall(App.UI.setAutoFarm, true) end
        startAutoFarmLoop()
      else
        pcall(function() if farm and farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end end)
        autoFarmOn = false
        if App.UI and App.UI.setAutoFarm then pcall(App.UI.setAutoFarm, false) end
      end
    end) or nil,

    -- 🔹 Private Server button — calls function defined by solo.lua
    onPrivateServer = (profile.ui.privateServer and function()
      task.spawn(function()
        local f = rawget(_G, "TeleportToPrivateServer")
        if type(f) ~= "function" then
          note("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
          return
        end
        local ok, err = pcall(f)
        if ok then
          note("🌲 Private Server", "Teleport initiated to private server!", 3)
        else
          note("🌲 Private Server", "Failed to teleport: " .. tostring(err), 5)
        end
      end)
    end) or nil,

    -- (optional) Dungeon hooks
    onDungeonAutoToggle = (profile.ui.dungeonAuto and function(v)
      local on = (v ~= nil) and v or false
      if dungeonBE and dungeonBE.init and dungeonBE.setAuto then
        dungeonBE.init(); dungeonBE.setAuto(on)
      end
    end) or nil,
    onDungeonReplayToggle = (profile.ui.dungeonReplay and function(v)
      local on = (v ~= nil) and v or false
      if dungeonBE and dungeonBE.init and dungeonBE.setReplay then
        dungeonBE.init(); dungeonBE.setReplay(on)
      end
    end) or nil,
  })

  note("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
end

return App
