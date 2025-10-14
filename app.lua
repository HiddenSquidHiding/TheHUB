-- app.lua — HTTP/Executor-friendly module that exports start()
-- Requires your init.lua to set _G.__WOODZ_REQUIRE(name) to fetch/load sibling files by name.

-----------------------------------------------------------------------
-- tiny safe utils (no hard dependency on script.Parent)
-----------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local function notify(title, msg, dur)
  dur = dur or 3
  pcall(function()
    StarterGui:SetCore("SendNotification", { Title = tostring(title or "WoodzHUB"); Text = tostring(msg or ""); Duration = dur })
  end)
  print(("[%s] %s"):format(tostring(title or "WoodzHUB"), tostring(msg or "")))
end

local function waitForCharacter()
  local Players = game:GetService("Players")
  local plr = Players.LocalPlayer
  while plr
    and (not plr.Character
         or not plr.Character:FindFirstChild("HumanoidRootPart")
         or not plr.Character:FindFirstChildOfClass("Humanoid")) do
    plr.CharacterAdded:Wait()
    task.wait()
  end
  return plr and plr.Character
end

-- convenience getter for optional siblings loaded by init.lua
local function requireSibling(name)
  local hook = rawget(_G, "__WOODZ_REQUIRE")
  if type(hook) ~= "function" then return nil end
  local ok, mod = pcall(hook, name)
  if ok then return mod end
  return nil
end

-----------------------------------------------------------------------
-- cache optional modules (never error if missing)
-----------------------------------------------------------------------
local UI        = requireSibling("ui_rayfield")
local gamesCfg  = requireSibling("games")
local farm      = requireSibling("farm")
local smart     = requireSibling("smart_target")
local merchants = requireSibling("merchants")
local crates    = requireSibling("crates")
local antiAFK   = requireSibling("anti_afk")
local redeem    = requireSibling("redeem_unredeemed_codes")
local fastlevel = requireSibling("fastlevel")
local dungeonBE = requireSibling("dungeon_be")

-----------------------------------------------------------------------
-- helpers: choose profile from games.lua (placeId first, then universeId, else default)
-----------------------------------------------------------------------
local function pickProfile()
  local keyPlace    = "place:" .. tostring(game.PlaceId)
  local keyUniverse = tostring(game.GameId)

  local defaultProfile = {
    name = "Generic",
    modules = {}, -- optional
    ui = {
      modelPicker=false, currentTarget=true,
      autoFarm=false, smartFarm=false,
      merchants=false, crates=false, antiAFK=true,
      redeemCodes=true, fastlevel=false, privateServer=false,
      dungeonAuto=false, dungeonReplay=false,
    },
  }

  if type(gamesCfg) ~= "table" then
    notify("[app.lua]", "games.lua missing or invalid; using default", 4)
    return defaultProfile, "default"
  end

  local prof = gamesCfg[keyPlace] or gamesCfg[keyUniverse] or gamesCfg.default or defaultProfile
  return prof, (gamesCfg[keyPlace] and keyPlace) or (gamesCfg[keyUniverse] and keyUniverse) or "default"
end

-----------------------------------------------------------------------
-- export
-----------------------------------------------------------------------
local App = {}

function App.start()
  if _G.__WOODZ_APP_STARTED then return end
  _G.__WOODZ_APP_STARTED = true

  local profile, key = pickProfile()
  notify("[app.lua]", ("profile: %s (key=%s)"):format(profile.name or "?", key), 3)

  if not UI or type(UI.build) ~= "function" then
    notify("[ui_rayfield]", "Rayfield failed to load (ui_rayfield.lua missing or build() not found).", 6)
    return
  end

  -- current target label throttler for Rayfield
  local lastLabel, lastAt = nil, 0
  local function setCurrentTarget(text)
    text = text or "Current Target: None"
    local now = tick()
    if text == lastLabel and (now - lastAt) < 0.15 then return end
    lastLabel, lastAt = text, now
    if App.UI and App.UI.setCurrentTarget then pcall(App.UI.setCurrentTarget, text) end
  end

  -- state flags
  local autoFarmOn   = false
  local smartFarmOn  = false
  local fastLevelOn  = false
  local dungeonOn    = false
  local dungeonReplay= false

  -- build Rayfield with handlers (only wire features the profile enables)
  App.UI = UI.build({
    ------------------------------------------------------------------
    -- Main farming
    ------------------------------------------------------------------
    onAutoFarmToggle = (profile.ui.autoFarm and function(v)
      autoFarmOn = (v ~= nil) and v or (not autoFarmOn)
      if autoFarmOn then
        if farm and type(farm.setupAutoAttackRemote) == "function" then pcall(farm.setupAutoAttackRemote) end
        notify("Auto-Farm", "enabled", 3)
        if farm and type(farm.runAutoFarm) == "function" then
          task.spawn(function()
            farm.runAutoFarm(function() return autoFarmOn end, setCurrentTarget)
          end)
        else
          notify("Auto-Farm", "farm.lua missing; toggle will do nothing.", 5)
        end
      else
        setCurrentTarget("Current Target: None")
        notify("Auto-Farm", "disabled", 3)
      end
    end) or nil,

    onSmartFarmToggle = (profile.ui.smartFarm and function(v)
      smartFarmOn = (v ~= nil) and v or (not smartFarmOn)
      if smartFarmOn then
        notify("Smart Farm", "enabled", 3)
        if smart and type(smart.runSmartFarm) == "function" then
          task.spawn(function()
            smart.runSmartFarm(function() return smartFarmOn end, setCurrentTarget, { safetyBuffer = 0.8, refreshInterval = 0.05 })
          end)
        else
          notify("Smart Farm", "smart_target.lua missing; toggle will do nothing.", 5)
        end
      else
        setCurrentTarget("Current Target: None")
        notify("Smart Farm", "disabled", 3)
      end
    end) or nil,

    ------------------------------------------------------------------
    -- Options
    ------------------------------------------------------------------
    onToggleAntiAFK = (profile.ui.antiAFK and function(v)
      local on = (v ~= nil) and v or false
      if antiAFK and type(antiAFK.enable) == "function" and type(antiAFK.disable) == "function" then
        if on then antiAFK.enable() else antiAFK.disable() end
        notify("Anti-AFK", on and "enabled" or "disabled", 3)
      else
        notify("Anti-AFK", "anti_afk.lua missing", 4)
      end
    end) or nil,

    onToggleMerchant1 = (profile.ui.merchants and function(v)
      local on = (v ~= nil) and v or false
      if merchants and type(merchants.autoBuyLoop) == "function" and on then
        task.spawn(function()
          merchants.autoBuyLoop("SmelterMerchantService", function() return on end, function() end)
        end)
      end
      notify("Merchant — Chicleteiramania", on and "enabled" or "disabled", 3)
    end) or nil,

    onToggleMerchant2 = (profile.ui.merchants and function(v)
      local on = (v ~= nil) and v or false
      if merchants and type(merchants.autoBuyLoop) == "function" and on then
        task.spawn(function()
          merchants.autoBuyLoop("SmelterMerchantService2", function() return on end, function() end)
        end)
      end
      notify("Merchant — Bombardino Sewer", on and "enabled" or "disabled", 3)
    end) or nil,

    onToggleCrates = (profile.ui.crates and function(v)
      local on = (v ~= nil) and v or false
      if crates and type(crates.autoOpenCratesEnabledLoop) == "function" then
        task.spawn(function()
          crates.autoOpenCratesEnabledLoop(function() return on end)
        end)
        notify("Crates", on and "enabled" or "disabled", 3)
      else
        notify("Crates", "crates.lua missing", 4)
      end
    end) or nil,

    onRedeemCodes = (profile.ui.redeemCodes and function()
      if redeem and type(redeem.run) == "function" then
        task.spawn(function()
          local ok, err = pcall(function() redeem.run({ dryRun=false, concurrent=true, delayBetween=0.25 }) end)
          if not ok then notify("Codes", "Redeem failed: "..tostring(err), 5) end
        end)
      else
        notify("Codes", "redeem_unredeemed_codes.lua missing", 4)
      end
    end) or nil,

    onFastLevelToggle = (profile.ui.fastlevel and function(v)
      fastLevelOn = (v ~= nil) and v or (not fastLevelOn)
      if fastLevelOn then
        if fastlevel and type(fastlevel.enable) == "function" then pcall(fastlevel.enable) end
        notify("Instant Level 70+", "enabled", 3)
        -- ensure Auto-Farm is running if available
        if farm and type(farm.setupAutoAttackRemote) == "function" then pcall(farm.setupAutoAttackRemote) end
        if farm and type(farm.runAutoFarm) == "function" then
          autoFarmOn = true
          if App.UI and App.UI.setAutoFarm then pcall(App.UI.setAutoFarm, true) end
          task.spawn(function()
            farm.runAutoFarm(function() return autoFarmOn end, setCurrentTarget)
          end)
        end
      else
        if fastlevel and type(fastlevel.disable) == "function" then pcall(fastlevel.disable) end
        autoFarmOn = false
        if App.UI and App.UI.setAutoFarm then pcall(App.UI.setAutoFarm, false) end
        notify("Instant Level 70+", "disabled", 3)
      end
    end) or nil,

    -- Brainrot Dungeon helpers
    onDungeonAutoToggle = (profile.ui.dungeonAuto and function(v)
      dungeonOn = (v ~= nil) and v or (not dungeonOn)
      if dungeonBE and type(dungeonBE.init) == "function" and type(dungeonBE.setAuto) == "function" then
        pcall(dungeonBE.init)
        pcall(dungeonBE.setAuto, dungeonOn)
        notify("Dungeon Auto-Attack", dungeonOn and "enabled" or "disabled", 3)
      else
        notify("Dungeon", "dungeon_be.lua missing", 4)
      end
    end) or nil,

    onDungeonReplayToggle = (profile.ui.dungeonReplay and function(v)
      dungeonReplay = (v ~= nil) and v or (not dungeonReplay)
      if dungeonBE and type(dungeonBE.init) == "function" and type(dungeonBE.setReplay) == "function" then
        pcall(dungeonBE.init)
        pcall(dungeonBE.setReplay, dungeonReplay)
        notify("Dungeon Auto-Replay", dungeonReplay and "enabled" or "disabled", 3)
      else
        notify("Dungeon", "dungeon_be.lua missing", 4)
      end
    end) or nil,
  })

  notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
end

return App
