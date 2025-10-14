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
local sahurHopper = r("sahur_hopper")

-- 🔹 NEW: load solo.lua at boot so the Private Server button can call it later.
local solo = r("solo")  -- ignore return; side-effect only

-- Pick a profile from games.lua
local function profileFromGames()
  local default = {
    name = "Generic",
    ui = {
      modelPicker = true, currentTarget = true,
      autoFarm = true, smartFarm = false,
      merchants = false, crates = false, antiAFK = true,
      redeemCodes = true, fastlevel = true, privateServer = true,
      sahurHopper = true,
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

-- Shared state for farm loops (fixed: immediate cancel + UI sync)
local autoFarmOn = false
local autoFarmThread = nil

local function stopAutoFarm()
  autoFarmOn = false
  if autoFarmThread then
    -- Cancel thread by flag; UI sync
    task.cancel(autoFarmThread)  -- Immediate kill if supported
    autoFarmThread = nil
  end
  if App.UI and App.UI.setAutoFarm then
    pcall(App.UI.setAutoFarm, false)
  end
  print("[app.lua] Auto-Farm stopped")
end

function App.start()
  if _G.__WOODZ_APP_STARTED then return end
  _G.__WOODZ_APP_STARTED = true

  local profile, key = profileFromGames()
  note("[app.lua]", ("profile: %s (key=%s)"):format(profile.name or "?", key), 3)

  if not UI or type(UI.build) ~= "function" then
    note("[ui_rayfield]", "Rayfield failed to load", 5)
    return
  end

  -- Build UI with hooks
  local h = {
    -- Picker hooks
    picker_getOptions = (farm and farm.getMonsterModels) or (smart and smart.getOptions),
    picker_getSelected = (farm and farm.getSelected) or (smart and smart.getSelected),
    picker_setSelected = (farm and farm.setSelected) or (smart and smart.setSelected),
    picker_clear = (farm and function() farm.setSelected({}) end) or (smart and smart.clear),

    -- Farm toggles (fixed: task.cancel for immediate stop, sync UI)
    onAutoFarmToggle = (profile.ui.autoFarm and function(v)
      local newOn = (v ~= nil) and v or not autoFarmOn
      print("[app.lua] Auto-Farm toggle to:", newOn)
      if newOn then
        stopAutoFarm()  -- Clean previous
        if farm and farm.setupAutoAttackRemote then pcall(farm.setupAutoAttackRemote) end
        if farm and farm.runAutoFarm then
          autoFarmThread = task.spawn(function()
            farm.runAutoFarm(function() return autoFarmOn end, App.UI and App.UI.setCurrentTarget)
          end)
        end
        if App.UI and App.UI.setAutoFarm then pcall(App.UI.setAutoFarm, true) end
      else
        stopAutoFarm()
      end
    end) or nil,

    onSmartFarmToggle = (profile.ui.smartFarm and function(v)
      local on = (v ~= nil) and v or false
      if smart and smart.toggle then pcall(smart.toggle, on) end
    end) or nil,

    -- Anti-AFK
    onToggleAntiAFK = (profile.ui.antiAFK and function(v)
      local on = (v ~= nil) and v or false
      if antiAFK and antiAFK.enable then
        if on then antiAFK.enable() else antiAFK.disable() end
      end
    end) or nil,

    -- Merchants
    onToggleMerchant1 = (profile.ui.merchants and function(v)
      local on = (v ~= nil) and v or false
      if on and merchants and merchants.autoBuyLoop then
        pcall(merchants.autoBuyLoop, "SmelterMerchantService1", function() return on end, function() end)
      end
    end) or nil,

    onToggleMerchant2 = (profile.ui.merchants and function(v)
      local on = (v ~= nil) and v or false
      if on and merchants and merchants.autoBuyLoop then
        pcall(merchants.autoBuyLoop, "SmelterMerchantService2", function() return on end, function() end)
      end
    end) or nil,

    -- Crates
    onToggleCrates = (profile.ui.crates and function(v)
      local on = (v ~= nil) and v or false
      if crates and crates.autoOpenCratesEnabledLoop and on then
        task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return on end) end)
      end
    end) or nil,

    -- Redeem
    onRedeemCodes = (profile.ui.redeemCodes and function()
      if redeem and redeem.run then task.spawn(function() redeem.run({dryRun=false,concurrent=true,delayBetween=0.25}) end)
      else note("Codes","redeem_unredeemed_codes.lua missing
