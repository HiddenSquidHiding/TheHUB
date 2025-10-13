-- app.lua — Rayfield hub bootstrap (table-sibling loader compatible)

----------------------------------------------------------------------
-- 0) Double-boot guard (executors sometimes run twice)
----------------------------------------------------------------------
if _G.__WOODZHUB_BOOTED then
  return
end
_G.__WOODZHUB_BOOTED = true

----------------------------------------------------------------------
-- 1) Safe utils
----------------------------------------------------------------------
local function getUtils()
  local p = script and script.Parent
  if p and type(p) == "table" and p._deps and p._deps.utils then
    return p._deps.utils
  end
  if rawget(getfenv(), "__WOODZ_UTILS") then
    return __WOODZ_UTILS
  end
  -- ultra-minimal fallback
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

----------------------------------------------------------------------
-- 2) Tiny sibling require that works with your table-based loader
----------------------------------------------------------------------
local function tryRequireSibling(name)
  local parent = script and script.Parent
  if not parent or type(parent) ~= "table" then
    return nil, "no parent table"
  end
  local handle = rawget(parent, name)
  if not handle then
    return nil, "missing"
  end
  local ok, mod = pcall(function() return require(handle) end)
  if ok then return mod end
  return nil, tostring(mod)
end

local function optional(name)
  local m, err = tryRequireSibling(name)
  if not m then
    print(("[app.lua] optional module '%s' not available%s"):format(name, err and (": "..err) or ""))
  end
  return m
end

----------------------------------------------------------------------
-- 3) Load modules (optional) & services used inside handlers
----------------------------------------------------------------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- These are optional; profile decides which ones we actually use
local constants = optional("constants")
local uiRF      = optional("ui_rayfield")
local farm      = optional("farm")
local smartFarm = optional("smart_target")
local merchants = optional("merchants")
local crates    = optional("crates")
local antiAFK   = optional("anti_afk")
local redeem    = optional("redeem_unredeemed_codes")
local fastlevel = optional("fastlevel")
local hud       = optional("hud") -- only used internally by ui_rayfield

-- fallbacks for constants
local COLOR = {
  BG = Color3.fromRGB(40,40,40),
  WHITE = Color3.new(1,1,1)
}
if constants then
  pcall(function()
    COLOR.BG = constants.COLOR_BG or COLOR.BG
    COLOR.WHITE = constants.COLOR_WHITE or COLOR.WHITE
  end)
end

----------------------------------------------------------------------
-- 4) Games profile (place:<id> or gameId or default)
----------------------------------------------------------------------
local games, gamesErr = tryRequireSibling("games")
if not games or type(games) ~= "table" then
  print("[app.lua] games.lua missing or invalid; falling back to default")
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

local placeKey = "place:" .. tostring(game.PlaceId)
local uniKey   = tostring(game.GameId)
local profile  = games[placeKey] or games[uniKey] or games.default or games["default"]
local profileKey = games[placeKey] and placeKey or (games[uniKey] and uniKey or "default")
print(("[app.lua] profile: %s (key=%s)"):format(profile and (profile.name or "?") or "?", profileKey))

-- Thin allow-list check for modules requested by profile (silently ignore missing)
local want = {}
do
  for _, n in ipairs(profile.modules or {}) do
    want[n] = true
  end
end

----------------------------------------------------------------------
-- 5) State + Rayfield bridge
----------------------------------------------------------------------
local RF = nil -- Rayfield handle (exposes setters)
-- Reuse/cleanup old window if something tries to boot twice anyway
if _G.__WOODZHUB_RF and type(_G.__WOODZHUB_RF.destroy) == "function" then
  pcall(function() _G.__WOODZHUB_RF.destroy() end)
end

local autoFarmEnabled       = false
local smartFarmEnabled      = false
local autoBuyM1Enabled      = false
local autoBuyM2Enabled      = false
local autoOpenCratesEnabled = false
local antiAfkEnabled        = false

-- prevent feedback loops (UI -> app -> UI)
local suppressRF = false
local function rfSet(setterFn)
  if RF and setterFn then
    suppressRF = true
    pcall(setterFn)
    suppressRF = false
  end
end

-- Throttled target label
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

-- MonsterInfo resolver for smart farm
local function resolveMonsterInfo()
  local RS = ReplicatedStorage
  local candidatePaths = {
    {"GameInfo", "MonsterInfo"},
    {"MonsterInfo"},
    {"Shared", "MonsterInfo"},
    {"Modules", "MonsterInfo"},
    {"Configs", "MonsterInfo"},
  }
  for _, path in ipairs(candidatePaths) do
    local node = RS
    local ok = true
    for _, name in ipairs(path) do
      node = node:FindFirstChild(name) or node:WaitForChild(name, 1)
      if not node then ok=false; break end
    end
    if ok and node and node:IsA("ModuleScript") then
      return node
    end
  end
  for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then
      return d
    end
  end
  return nil
end

----------------------------------------------------------------------
-- 6) Build UI (Rayfield) only if requested & available
----------------------------------------------------------------------
local uiCfg = profile.ui or {}

local handlers = {}

-- Model picker helpers (safe if farm missing)
handlers.onClearAll = function()
  if not farm then return end
  farm.setSelected({})
  if RF and RF.syncModelSelection then RF.syncModelSelection() end
  utils.notify("🌲 Preset", "Cleared all selections.", 3)
end

-- Auto-Farm toggle (mutually exclusive with Smart Farm)
handlers.onAutoFarmToggle = function(v)
  if not farm or not want["farm"] then
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
    pcall(function() farm.setupAutoAttackRemote() end)
    local sel = pcall(function() return farm.getSelected() end) and farm.getSelected() or {}
    local extra = (sel and #sel > 0) and (" for: " .. table.concat(sel, ", ")) or ""
    notifyToggle("Auto-Farm", true, extra)

    task.spawn(function()
      farm.runAutoFarm(
        function() return autoFarmEnabled end,
        setCurrentTarget
      )
    end)
  else
    setCurrentTarget("Current Target: None")
    notifyToggle("Auto-Farm", false)
  end
end

-- Smart Farm toggle (mutually exclusive with Auto-Farm)
handlers.onSmartFarmToggle = function(v)
  if not smartFarm or not want["smart_target"] then
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
    local module = resolveMonsterInfo()
    notifyToggle("Smart Farm", true, module and (" — using " .. module:GetFullName()) or " (MonsterInfo not found; will stop)")

    if module then
      task.spawn(function()
        smartFarm.runSmartFarm(
          function() return smartFarmEnabled end,
          setCurrentTarget,
          { module = module, safetyBuffer = 0.8, refreshInterval = 0.05 }
        )
      end)
    else
      smartFarmEnabled = false
      rfSet(function() if RF and RF.setSmartFarm then RF.setSmartFarm(false) end end)
    end
  else
    setCurrentTarget("Current Target: None")
    notifyToggle("Smart Farm", false)
  end
end

-- Anti-AFK
handlers.onToggleAntiAFK = function(v)
  if not antiAFK or not want["anti_afk"] then
    utils.notify("🌲 Anti-AFK", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  antiAfkEnabled = (v ~= nil) and v or (not antiAfkEnabled)
  if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
  notifyToggle("Anti-AFK", antiAfkEnabled)
end

-- Merchants
handlers.onToggleMerchant1 = function(v)
  if not merchants or not want["merchants"] then
    utils.notify("🌲 Merchant", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  autoBuyM1Enabled = (v ~= nil) and v or (not autoBuyM1Enabled)
  if autoBuyM1Enabled then
    notifyToggle("Merchant — Chicleteiramania", true)
    task.spawn(function()
      merchants.autoBuyLoop(
        "SmelterMerchantService",
        function() return autoBuyM1Enabled end,
        function(_) end
      )
    end)
  else
    notifyToggle("Merchant — Chicleteiramania", false)
  end
end

handlers.onToggleMerchant2 = function(v)
  if not merchants or not want["merchants"] then
    utils.notify("🌲 Merchant", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  autoBuyM2Enabled = (v ~= nil) and v or (not autoBuyM2Enabled)
  if autoBuyM2Enabled then
    notifyToggle("Merchant — Bombardino Sewer", true)
    task.spawn(function()
      merchants.autoBuyLoop(
        "SmelterMerchantService2",
        function() return autoBuyM2Enabled end,
        function(_) end
      )
    end)
  else
    notifyToggle("Merchant — Bombardino Sewer", false)
  end
end

-- Crates
handlers.onToggleCrates = function(v)
  if not crates or not want["crates"] then
    utils.notify("🌲 Crates", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  autoOpenCratesEnabled = (v ~= nil) and v or (not autoOpenCratesEnabled)
  if autoOpenCratesEnabled then
    pcall(function() crates.refreshCrateInventory(true) end)
    local delayText = tostring((constants and constants.crateOpenDelay) or 1)
    notifyToggle("Crates", true, " (1 every " .. delayText .. "s)")
    task.spawn(function()
      crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end)
    end)
  else
    notifyToggle("Crates", false)
  end
end

-- Codes
handlers.onRedeemCodes = function()
  if not redeem or not want["redeem_unredeemed_codes"] then
    utils.notify("Codes", "Module not available.", 3)
    return
  end
  task.spawn(function()
    local ok, err = pcall(function()
      redeem.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
    end)
    if not ok then utils.notify("Codes", "Redeem failed: " .. tostring(err), 4) end
  end)
end

-- Instant Level 70+
handlers.onFastLevelToggle = function(v)
  if not fastlevel or not want["fastlevel"] then
    utils.notify("🌲 Instant Level 70+", "Module not available.", 3)
    return
  end
  if suppressRF then return end
  local enableNow = (v ~= nil) and v or (not (fastlevel.isEnabled and fastlevel.isEnabled() or false))
  if enableNow then
    if smartFarmEnabled then
      smartFarmEnabled = false
      rfSet(function() if RF and RF.setSmartFarm then RF.setSmartFarm(false) end end)
      notifyToggle("Smart Farm", false)
    end
    if fastlevel.enable then fastlevel.enable() end
    notifyToggle("Instant Level 70+", true, " — targeting Sahur only")

    if farm and want["farm"] then
      -- ensure auto-farm is on
      if not autoFarmEnabled then
        autoFarmEnabled = true
        rfSet(function() if RF and RF.setAutoFarm then RF.setAutoFarm(true) end end)
        pcall(function() farm.setupAutoAttackRemote() end)
        task.spawn(function()
          farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
        end)
        notifyToggle("Auto-Farm", true)
      end
      if farm.setFastLevelEnabled then pcall(function() farm.setFastLevelEnabled(true) end) end
    end
  else
    if fastlevel.disable then fastlevel.disable() end
    notifyToggle("Instant Level 70+", false)
    if farm and farm.setFastLevelEnabled then pcall(function() farm.setFastLevelEnabled(false) end) end
    -- also toggle Auto-Farm off as requested
    if autoFarmEnabled then
      autoFarmEnabled = false
      rfSet(function() if RF and RF.setAutoFarm then RF.setAutoFarm(false) end end)
      notifyToggle("Auto-Farm", false)
    end
  end
end

-- Private Server button expects _G.TeleportToPrivateServer (from your solo.lua)
handlers.onPrivateServer = function()
  task.spawn(function()
    if type(_G.TeleportToPrivateServer) ~= "function" then
      utils.notify("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
      return
    end
    local ok, err = pcall(_G.TeleportToPrivateServer)
    if ok then
      utils.notify("🌲 Private Server", "Teleport initiated to private server!", 3)
    else
      utils.notify("🌲 Private Server", "Failed to teleport: " .. tostring(err), 5)
    end
  end)
end

----------------------------------------------------------------------
-- 7) Boot
----------------------------------------------------------------------
local function boot()
  -- Build Rayfield only if available + profile asks for it
  if not uiRF then
    print("[app.lua] ui_rayfield.lua missing - UI not loaded. Core still running.")
  else
    -- Build with only the features this profile wants
    RF = uiRF.build({
      onClearAll       = uiCfg.modelPicker and handlers.onClearAll or nil,
      onAutoFarmToggle = uiCfg.autoFarm    and handlers.onAutoFarmToggle or nil,
      onSmartFarmToggle= uiCfg.smartFarm   and handlers.onSmartFarmToggle or nil,
      onToggleAntiAFK  = uiCfg.antiAFK     and handlers.onToggleAntiAFK or nil,
      onToggleMerchant1= uiCfg.merchants   and handlers.onToggleMerchant1 or nil,
      onToggleMerchant2= uiCfg.merchants   and handlers.onToggleMerchant2 or nil,
      onToggleCrates   = uiCfg.crates      and handlers.onToggleCrates or nil,
      onRedeemCodes    = uiCfg.redeemCodes and handlers.onRedeemCodes or nil,
      onFastLevelToggle= uiCfg.fastlevel   and handlers.onFastLevelToggle or nil,
      onPrivateServer  = uiCfg.privateServer and handlers.onPrivateServer or nil,
    })
    _G.__WOODZHUB_RF = RF
  end

  utils.notify("🌲 WoodzHUB", "Loaded successfully.", 3)
end

-- Auto-boot for executor usage
boot()
