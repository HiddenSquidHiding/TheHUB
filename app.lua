-- app.lua — HTTP friendly app module. Exports start()

local StarterGui = game:GetService("StarterGui")
local function note(t, m, d)
  d = d or 3
  pcall(StarterGui.SetCore, StarterGui, "SendNotification", {Title=tostring(t),Text=tostring(m),Duration=d})
  print(("[%s] %s"):format(tostring(t), tostring(m)))
end

local function r(name)
  local hook = rawget(_G, "__WOODZ_REQUIRE")
  if type(hook) ~= "function" then return nil end
  local ok, mod = pcall(hook, name)
  return ok and mod or nil
end

-- Optional modules (never crash if missing)
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

local function profileFromGames()
  local default = {
    name = "Generic",
    ui = {
      modelPicker=false, currentTarget=true,
      autoFarm=false, smartFarm=false,
      merchants=false, crates=false, antiAFK=true,
      redeemCodes=true, fastlevel=false, privateServer=false,
      dungeonAuto=false, dungeonReplay=false,
    }
  }
  if type(gamesCfg) ~= "table" then
    note("[app.lua]","games.lua missing or invalid; using default",4)
    return default, "default"
  end
  local keyPlace = "place:"..tostring(game.PlaceId)
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

  local autoFarmOn, smartOn, fastOn, dungAuto, dungReplay = false,false,false,false,false
  local lastLbl, lastAt = nil, 0
  local function setCurrent(s)
    s = s or "Current Target: None"
    local now = tick()
    if s==lastLbl and now-lastAt<0.15 then return end
    lastLbl, lastAt = s, now
    if App.UI and App.UI.setCurrentTarget then pcall(App.UI.setCurrentTarget, s) end
  end

  App.UI = UI.build({
    -- FARM
    onAutoFarmToggle = (profile.ui.autoFarm and function(v)
      autoFarmOn = (v ~= nil) and v or (not autoFarmOn)
      if autoFarmOn then
        if farm and farm.setupAutoAttackRemote then pcall(farm.setupAutoAttackRemote) end
        if farm and farm.runAutoFarm then
          task.spawn(function() farm.runAutoFarm(function() return autoFarmOn end, setCurrent) end)
        else note("Auto-Farm","farm.lua missing",4) end
      else setCurrent("Current Target: None") end
    end) or nil,

    onSmartFarmToggle = (profile.ui.smartFarm and function(v)
      smartOn = (v ~= nil) and v or (not smartOn)
      if smartOn then
        if smart and smart.runSmartFarm then
          task.spawn(function() smart.runSmartFarm(function() return smartOn end, setCurrent, {safetyBuffer=0.8,refreshInterval=0.05}) end)
        else note("Smart Farm","smart_target.lua missing",4) end
      else setCurrent("Current Target: None") end
    end) or nil,

    -- OPTIONS
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
      if crates and crates.autoOpenCratesEnabledLoop then
        task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return on end) end)
      else note("Crates","crates.lua missing",4) end
    end) or nil,

    onRedeemCodes = (profile.ui.redeemCodes and function()
      if redeem and redeem.run then task.spawn(function() redeem.run({dryRun=false,concurrent=true,delayBetween=0.25}) end)
      else note("Codes","redeem_unredeemed_codes.lua missing",4) end
    end) or nil,

    onFastLevelToggle = (profile.ui.fastlevel and function(v)
      fastOn = (v ~= nil) and v or (not fastOn)
      if fastOn then
        if fastlevel and fastlevel.enable then pcall(fastlevel.enable) end
        if farm and farm.setupAutoAttackRemote then pcall(farm.setupAutoAttackRemote) end
        if farm and farm.runAutoFarm then
          autoFarmOn = true
          if App.UI and App.UI.setAutoFarm then pcall(App.UI.setAutoFarm, true) end
          task.spawn(function() farm.runAutoFarm(function() return autoFarmOn end, setCurrent) end)
        end
      else
        if fastlevel and fastlevel.disable then pcall(fastlevel.disable) end
        autoFarmOn = false
        if App.UI and App.UI.setAutoFarm then pcall(App.UI.setAutoFarm, false) end
      end
    end) or nil,

    onDungeonAutoToggle = (profile.ui.dungeonAuto and function(v)
      dungAuto = (v ~= nil) and v or (not dungAuto)
      if dungeonBE and dungeonBE.init and dungeonBE.setAuto then
        pcall(dungeonBE.init); pcall(dungeonBE.setAuto, dungAuto)
      else note("Dungeon","dungeon_be.lua missing",4) end
    end) or nil,

    onDungeonReplayToggle = (profile.ui.dungeonReplay and function(v)
      dungReplay = (v ~= nil) and v or (not dungReplay)
      if dungeonBE and dungeonBE.init and dungeonBE.setReplay then
        pcall(dungeonBE.init); pcall(dungeonBE.setReplay, dungReplay)
      else note("Dungeon","dungeon_be.lua missing",4) end
    end) or nil,
  })

  note("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
end

return App
