-- app.lua — executor/table-sibling safe bootstrap (no top-level require)
-- It never calls require(), so your loader won't assert if siblings aren't ready.

-- Double-boot guard
if _G.__WOODZHUB_BOOTED then return end
_G.__WOODZHUB_BOOTED = true

-- Minimal utils (fallback)
local function getUtils()
  local p = script and script.Parent
  if p and type(p) == "table" and p._deps and p._deps.utils then
    return p._deps.utils
  end
  if rawget(getfenv(), "__WOODZ_UTILS") then
    return __WOODZ_UTILS
  end
  return {
    notify = function(title, msg) print(("[%s] %s"):format(title, msg)) end,
    waitForCharacter = function()
      local Players = game:GetService("Players")
      local plr = Players.LocalPlayer
      while not plr.Character
        or not plr.Character:FindFirstChild("HumanoidRootPart")
        or not plr.Character:FindFirstChildOfClass("Humanoid") do
        plr.CharacterAdded:Wait()
        task.wait(0.05)
      end
      return plr.Character
    end,
  }
end
local utils = getUtils()

-- Soft sibling resolver (NO require)
local function getSibling(name)
  local parent = script and script.Parent
  if not parent or type(parent) ~= "table" then return nil end

  -- exact key
  local v = rawget(parent, name)
  if v ~= nil then return v end

  -- try case-insensitive
  local lname = string.lower(name)
  for k, val in pairs(parent) do
    if type(k) == "string" and string.lower(k) == lname then
      return val
    end
  end
  return nil
end

-- Wait briefly for loader to inject siblings into script.Parent (table)
local function waitFor(keys, timeout)
  timeout = timeout or 2.0
  local t0 = tick()
  while (tick() - t0) < timeout do
    local ok = true
    for _, k in ipairs(keys) do
      if getSibling(k) == nil then ok = false break end
    end
    if ok then return true end
    task.wait(0.05)
  end
  return false
end

-- Ask (politely) for common siblings but don't fail if missing
waitFor({ "games", "ui_rayfield", "farm", "smart_target", "anti_afk", "merchants", "crates", "redeem_unredeemed_codes", "fastlevel" }, 1.25)

-- Pull whatever is available (tables/functions your loader provided)
local games                 = getSibling("games")                      -- table expected
local uiRF                  = getSibling("ui_rayfield")                -- module table with .build
local farm                  = getSibling("farm")
local smartFarm             = getSibling("smart_target")
local antiAFK               = getSibling("anti_afk")
local merchants             = getSibling("merchants")
local crates                = getSibling("crates")
local redeem                = getSibling("redeem_unredeemed_codes")
local fastlevel             = getSibling("fastlevel")
local constants             = getSibling("constants")                  -- optional

-- Choose profile (place:<placeId>, gameId, or default)
local placeKey = "place:" .. tostring(game.PlaceId)
local uniKey   = tostring(game.GameId)

if type(games) ~= "table" then
  utils.notify("app.lua", "games.lua missing or invalid; using default", 3)
  games = {
    default = {
      name = "Generic",
      modules = { "anti_afk" },
      ui = {
        modelPicker=false, currentTarget=false,
        autoFarm=false, smartFarm=false,
        merchants=false, crates=false, antiAFK=true,
        redeemCodes=false, fastlevel=false, privateServer=false,
      },
    }
  }
end

local profile  = games[placeKey] or games[uniKey] or games.default or games["default"] or {}
local profileKey = games[placeKey] and placeKey or (games[uniKey] and uniKey or "default")
print(("[app.lua] profile: %s (key=%s)"):format(profile.name or "?", profileKey))

-- Quick “want” set from profile.modules (strings only)
local want = {}
do
  local list = profile.modules
  if type(list) == "table" then
    for _, n in ipairs(list) do if type(n) == "string" then want[n] = true end end
  end
end

-- State + Rayfield bridge
if _G.__WOODZHUB_RF and type(_G.__WOODZHUB_RF.destroy) == "function" then
  pcall(function() _G.__WOODZHUB_RF.destroy() end)
end
local RF = nil
_G.__WOODZHUB_RF = nil

local autoFarmEnabled, smartFarmEnabled = false, false
local autoBuyM1Enabled, autoBuyM2Enabled = false, false
local autoOpenCratesEnabled, antiAfkEnabled = false, false

local suppressRF = false
local function rfSet(fn)
  if RF and fn then
    suppressRF = true
    pcall(fn)
    suppressRF = false
  end
end

-- Light label throttle for Rayfield
local lastLabelText, lastLabelAt = nil, 0
local function setCurrentTarget(text)
  text = text or "Current Target: None"
  local now = tick()
  if text == lastLabelText and (now - lastLabelAt) < 0.15 then return end
  lastLabelText, lastLabelAt = text, now
  if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(text) end) end
end

local function notifyToggle(name, on, extra)
  extra = extra or ""
  local msg = on and (name .. " enabled" .. extra) or (name .. " disabled")
  utils.notify("🌲 " .. name, msg, 3.5)
end

-- SmartFarm needs MonsterInfo
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local function resolveMonsterInfo()
  local RS = ReplicatedStorage
  local paths = {
    {"GameInfo","MonsterInfo"}, {"MonsterInfo"},
    {"Shared","MonsterInfo"}, {"Modules","MonsterInfo"}, {"Configs","MonsterInfo"},
  }
  for _, path in ipairs(paths) do
    local node = RS
    local ok = true
    for _, part in ipairs(path) do
      node = node:FindFirstChild(part) or node:WaitForChild(part, 0.5)
      if not node then ok = false break end
    end
    if ok and node and node:IsA("ModuleScript") then return node end
  end
  for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then return d end
  end
  return nil
end

-- Handlers (only bind if the module exists AND the profile wants it)
local handlers = {}

handlers.onClearAll = function()
  if not (type(farm)=="table" and want["farm"] and type(farm.setSelected)=="function") then return end
  farm.setSelected({})
  if RF and RF.syncModelSelection then RF.syncModelSelection() end
  utils.notify("🌲 Preset", "Cleared all selections.", 3)
end

handlers.onAutoFarmToggle = function(v)
  if not (type(farm)=="table" and want["farm"] and type(farm.runAutoFarm)=="function") then
    utils.notify("🌲 Auto-Farm", "Farm module not available.", 3)
    return
  end
  if suppressRF then return end
  local newState = (v ~= nil) and v or (not autoFarmEnabled)
  if newState and smartFarmEnabled then
    smartFarmEnabled = false
    rfSet(function() if RF and RF.setSmartFarm then RF.setSmartFarm(false) end end)
    notifyToggle("Smart Farm", false)
  end
  autoFarmEnabled = newState
  if autoFarmEnabled then
    pcall(function() if type(farm.setupAutoAttackRemote)=="function" then farm.setupAutoAttackRemote() end end)
    task.spawn(function()
      farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
    end)
    notifyToggle("Auto-Farm", true)
  else
    setCurrentTarget("Current Target: None")
    notifyToggle("Auto-Farm", false)
  end
end

handlers.onSmartFarmToggle = function(v)
  if not (type(smartFarm)=="table" and want["smart_target"] and type(smartFarm.runSmartFarm)=="function") then
    utils.notify("🌲 Smart Farm", "Smart-target module not available.", 3)
    return
  end
  if suppressRF then return end
  local newState = (v ~= nil) and v or (not smartFarmEnabled)
  if newState and autoFarmEnabled then
    autoFarmEnabled = false
    rfSet(function() if RF and RF.setAutoFarm then RF.setAutoFarm(false) end end)
    notifyToggle("Auto-Farm", false)
  end
  smartFarmEnabled = newState
  if smartFarmEnabled then
    local mod = resolveMonsterInfo()
    if mod then
      task.spawn(function()
        smartFarm.runSmartFarm(function() return smartFarmEnabled end, setCurrentTarget, { module = mod, safetyBuffer = 0.8, refreshInterval = 0.05 })
      end)
      notifyToggle("Smart Farm", true, " — MonsterInfo found")
    else
      smartFarmEnabled = false
      rfSet(function() if RF and RF.setSmartFarm then RF.setSmartFarm(false) end end)
      utils.notify("🌲 Smart Farm", "MonsterInfo not found.", 4)
    end
  else
    setCurrentTarget("Current Target: None")
    notifyToggle("Smart Farm", false)
  end
end

handlers.onToggleAntiAFK = function(v)
  if not (type(antiAFK)=="table" and want["anti_afk"]) then
    utils.notify("🌲 Anti-AFK", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  local en = (v ~= nil) and v or (not antiAfkEnabled)
  antiAfkEnabled = en
  if type(antiAFK.enable)=="function" and type(antiAFK.disable)=="function" then
    if en then antiAFK.enable() else antiAFK.disable() end
  end
  notifyToggle("Anti-AFK", en)
end

handlers.onToggleMerchant1 = function(v)
  if not (type(merchants)=="table" and want["merchants"] and type(merchants.autoBuyLoop)=="function") then
    utils.notify("🌲 Merchant", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  autoBuyM1Enabled = (v ~= nil) and v or (not autoBuyM1Enabled)
  if autoBuyM1Enabled then
    notifyToggle("Merchant — Chicleteiramania", true)
    task.spawn(function()
      merchants.autoBuyLoop("SmelterMerchantService", function() return autoBuyM1Enabled end, function() end)
    end)
  else
    notifyToggle("Merchant — Chicleteiramania", false)
  end
end

handlers.onToggleMerchant2 = function(v)
  if not (type(merchants)=="table" and want["merchants"] and type(merchants.autoBuyLoop)=="function") then
    utils.notify("🌲 Merchant", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  autoBuyM2Enabled = (v ~= nil) and v or (not autoBuyM2Enabled)
  if autoBuyM2Enabled then
    notifyToggle("Merchant — Bombardino Sewer", true)
    task.spawn(function()
      merchants.autoBuyLoop("SmelterMerchantService2", function() return autoBuyM2Enabled end, function() end)
    end)
  else
    notifyToggle("Merchant — Bombardino Sewer", false)
  end
end

handlers.onToggleCrates = function(v)
  if not (type(crates)=="table" and want["crates"] and type(crates.autoOpenCratesEnabledLoop)=="function") then
    utils.notify("🌲 Crates", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  autoOpenCratesEnabled = (v ~= nil) and v or (not autoOpenCratesEnabled)
  if autoOpenCratesEnabled then
    pcall(function() if type(crates.refreshCrateInventory)=="function" then crates.refreshCrateInventory(true) end end)
    local delay = (type(constants)=="table" and constants.crateOpenDelay) and tostring(constants.crateOpenDelay) or "1"
    notifyToggle("Crates", true, " (1 every "..delay.."s)")
    task.spawn(function()
      crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end)
    end)
  else
    notifyToggle("Crates", false)
  end
end

handlers.onRedeemCodes = function()
  if not (type(redeem)=="table" and want["redeem_unredeemed_codes"] and type(redeem.run)=="function") then
    utils.notify("Codes", "Module not available.", 3)
    return
  end
  task.spawn(function()
    local ok, err = pcall(function()
      redeem.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
    end)
    if not ok then utils.notify("Codes", "Redeem failed: "..tostring(err), 4) end
  end)
end

handlers.onFastLevelToggle = function(v)
  if not (type(fastlevel)=="table" and want["fastlevel"]) then
    utils.notify("🌲 Instant Level 70+", "Module not available.", 3)
    return
  end
  if suppressRF then return end

  local isOn = type(fastlevel.isEnabled)=="function" and fastlevel.isEnabled() or false
  local enable = (v ~= nil) and v or (not isOn)

  if enable then
    if smartFarmEnabled then
      smartFarmEnabled = false
      rfSet(function() if RF and RF.setSmartFarm then RF.setSmartFarm(false) end end)
      notifyToggle("Smart Farm", false)
    end
    if type(fastlevel.enable)=="function" then fastlevel.enable() end
    notifyToggle("Instant Level 70+", true, " — targeting Sahur only")

    if type(farm)=="table" and want["farm"] and type(farm.runAutoFarm)=="function" then
      if not autoFarmEnabled then
        autoFarmEnabled = true
        rfSet(function() if RF and RF.setAutoFarm then RF.setAutoFarm(true) end end)
        pcall(function() if type(farm.setupAutoAttackRemote)=="function" then farm.setupAutoAttackRemote() end end)
        task.spawn(function()
          farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
        end)
        notifyToggle("Auto-Farm", true)
      end
      if type(farm.setFastLevelEnabled)=="function" then pcall(function() farm.setFastLevelEnabled(true) end) end
    end
  else
    if type(fastlevel.disable)=="function" then fastlevel.disable() end
    notifyToggle("Instant Level 70+", false)
    if type(farm)=="table" and type(farm.setFastLevelEnabled)=="function" then pcall(function() farm.setFastLevelEnabled(false) end) end
    if autoFarmEnabled then
      autoFarmEnabled = false
      rfSet(function() if RF and RF.setAutoFarm then RF.setAutoFarm(false) end end)
      notifyToggle("Auto-Farm", false)
    end
  end
end

handlers.onPrivateServer = function()
  task.spawn(function()
    if type(_G.TeleportToPrivateServer) ~= "function" then
      utils.notify("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
      return
    end
    local ok, err = pcall(_G.TeleportToPrivateServer)
    if ok then utils.notify("🌲 Private Server", "Teleport initiated to private server!", 3)
    else utils.notify("🌲 Private Server", "Failed to teleport: "..tostring(err), 5) end
  end)
end

-- Boot: build Rayfield UI if available and requested by profile
local function boot()
  local uiCfg = profile.ui or {}
  if type(uiRF) ~= "table" or type(uiRF.build) ~= "function" then
    print("[app.lua] ui_rayfield.lua missing - UI not loaded. Core still running.")
  else
    RF = uiRF.build({
      onClearAll        = uiCfg.modelPicker   and handlers.onClearAll or nil,
      onAutoFarmToggle  = uiCfg.autoFarm      and handlers.onAutoFarmToggle or nil,
      onSmartFarmToggle = uiCfg.smartFarm     and handlers.onSmartFarmToggle or nil,
      onToggleAntiAFK   = uiCfg.antiAFK       and handlers.onToggleAntiAFK or nil,
      onToggleMerchant1 = uiCfg.merchants     and handlers.onToggleMerchant1 or nil,
      onToggleMerchant2 = uiCfg.merchants     and handlers.onToggleMerchant2 or nil,
      onToggleCrates    = uiCfg.crates        and handlers.onToggleCrates or nil,
      onRedeemCodes     = uiCfg.redeemCodes   and handlers.onRedeemCodes or nil,
      onFastLevelToggle = uiCfg.fastlevel     and handlers.onFastLevelToggle or nil,
      onPrivateServer   = uiCfg.privateServer and handlers.onPrivateServer or nil,
    })
    _G.__WOODZHUB_RF = RF
  end
  utils.notify("🌲 WoodzHUB", "Loaded successfully.", 3)
end

boot()
