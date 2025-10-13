-- app.lua
-- Robust profile-driven boot for executor environments (GitHub / memory / ModuleScript).
-- Exposes app.start(), and also self-boots once if executed directly.

----------------------------------------------------------------------
-- one-time guard
----------------------------------------------------------------------
if _G.WOODZHUB_APP_RUNNING then
  return _G.WOODZHUB_APP_EXPORT or { start = function() end }
end

----------------------------------------------------------------------
-- tiny logger
----------------------------------------------------------------------
local function log(...) print("[WoodzHUB]", ...) end
local function warnf(...) warn("[WoodzHUB]", ...) end

----------------------------------------------------------------------
-- utils (minimal)
----------------------------------------------------------------------
local utils = {
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

----------------------------------------------------------------------
-- loader: tries memory -> GitHub base -> plain require
-- Memory format: _G.WOODZHUB_FS["file.lua"] = "<source>"
-- GitHub base:   _G.WOODZHUB_BASE = "https://raw.githubusercontent.com/you/repo/branch/folder"
----------------------------------------------------------------------
local function load_from_memory(name)
  local FS = rawget(_G, "WOODZHUB_FS")
  if not FS then return nil, "no FS" end
  local src = FS[name] or FS[name .. ".lua"]
  if type(src) ~= "string" then return nil, "not found" end
  local chunk, err = loadstring(src, "=" .. name)
  if not chunk then return nil, "compile:" .. tostring(err) end
  local ok, ret = pcall(chunk)
  if not ok then return nil, "runtime:" .. tostring(ret) end
  return ret, nil
end

local function load_from_github(name)
  local BASE = rawget(_G, "WOODZHUB_BASE")
  if not BASE or type(BASE) ~= "string" then return nil, "no base" end
  local function fetch(path)
    local ok, src = pcall(game.HttpGet, game, (BASE:sub(-1) == "/" and (BASE .. path) or (BASE .. "/" .. path)))
    if not ok or type(src) ~= "string" or src == "" then return nil end
    local chunk, err = loadstring(src, "=" .. path)
    if not chunk then return nil end
    local ok2, ret = pcall(chunk)
    if not ok2 then return nil end
    return ret
  end
  return fetch(name) or fetch(name .. ".lua"), nil
end

local function load_plain_require(name)
  local ok, ret = pcall(function() return require(name) end)
  if ok then return ret, nil end
  return nil, "require failed"
end

local function loadMod(name)
  -- try memory
  local mod, err = load_from_memory(name)
  if mod then return mod end
  -- try github
  mod = select(1, load_from_github(name))
  if mod then return mod end
  -- try plain require (name and name.lua)
  mod = select(1, load_plain_require(name))
  if mod then return mod end
  mod = select(1, load_plain_require(name .. ".lua"))
  if mod then return mod end
  return nil
end

----------------------------------------------------------------------
-- profile (games.lua)
----------------------------------------------------------------------
local games = loadMod("games") or loadMod("games.lua")
local placeKey    = ("place:%s"):format(tostring(game.PlaceId))
local universeKey = ("universe:%s"):format(tostring(game.GameId))

local profile = (games and (games[placeKey] or games[universeKey] or games.default))
  or { name = "Generic", modules = {}, ui = {} }

log(("profile: %s (key=%s)"):format(
  tostring(profile.name or "Generic"),
  (games and (games[placeKey] and placeKey or games[universeKey] and universeKey or "default") or "default")
))

----------------------------------------------------------------------
-- optional modules (only loaded if configured)
----------------------------------------------------------------------
local farm, smart, merch, crates, afk, redeem, fastlevel, dungeon = nil,nil,nil,nil,nil,nil,nil,nil

for _, m in ipairs(profile.modules or {}) do
  if m == "farm"                     then farm      = loadMod("farm") end
  if m == "smart_target"             then smart     = loadMod("smart_target") end
  if m == "merchants"                then merch     = loadMod("merchants") end
  if m == "crates"                   then crates    = loadMod("crates") end
  if m == "anti_afk"                 then afk       = loadMod("anti_afk") end
  if m == "redeem_unredeemed_codes"  then redeem    = loadMod("redeem_unredeemed_codes") end
  if m == "fastlevel"                then fastlevel = loadMod("fastlevel") end
  if m == "dungeon_be"               then dungeon   = loadMod("dungeon_be") end
end

----------------------------------------------------------------------
-- Rayfield UI module (required)
----------------------------------------------------------------------
local ui_rf = loadMod("ui_rayfield") or loadMod("ui_rayfield.lua")
if not (ui_rf and ui_rf.build) then
  warnf("ui_rayfield.lua missing - UI not loaded. Core still running.")
  -- Export a minimal start to satisfy environments that expect .start()
  local export = { start = function() end }
  _G.WOODZHUB_APP_EXPORT  = export
  _G.WOODZHUB_APP_RUNNING = true
  return export
end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local UI = nil
local autoFarmEnabled  = false
local smartFarmEnabled = false
local lastLabelText, lastLabelAt = nil, 0

local function setCurrentTarget(text)
  if not UI or not UI.setCurrentTarget then return end
  text = text or "Ready."
  local now = tick()
  if text == lastLabelText and (now - lastLabelAt) < 0.15 then return end
  lastLabelText, lastLabelAt = text, now
  pcall(function() UI.setCurrentTarget(text) end)
end

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

----------------------------------------------------------------------
-- Handlers wired to UI
----------------------------------------------------------------------
local handlers = {
  -- Auto-Farm (mutually exclusive with Smart Farm)
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
        farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
      end)
    else
      setCurrentTarget("Ready.")
      utils.notify("🌲 Auto-Farm", "disabled", 3)
    end
  end,

  -- Smart Farm (mutually exclusive with Auto-Farm)
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
            setCurrentTarget,
            { module = module, safetyBuffer = 0.8, refreshInterval = 0.05 }
          )
        end)
      else
        smartFarmEnabled = false
        if UI and UI.setSmartFarm then UI.setSmartFarm(false) end
      end
    else
      setCurrentTarget("Ready.")
      utils.notify("🌲 Smart Farm", "disabled", 3)
    end
  end,

  -- Anti-AFK
  onToggleAntiAFK = function(v)
    if not afk then return end
    local on = (v ~= nil) and v or true
    if on and afk.enable then afk.enable() elseif afk.disable then afk.disable() end
    utils.notify("🌲 Anti-AFK", on and "enabled" or "disabled", 3)
  end,

  -- Merchants
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

  -- Crates
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

  -- Codes
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
    local enabled = (v == true)
    if enabled then
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
          farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
        end)
      else
        if farm and farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
      end
    else
      if fastlevel.disable then fastlevel.disable() end
      utils.notify("🌲 Instant Level 70+", "disabled", 3)
      if farm and farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end
      -- also turn off Auto-Farm when FastLevel is turned off (requested)
      if autoFarmEnabled then
        autoFarmEnabled = false
        if UI and UI.setAutoFarm then UI.setAutoFarm(false) end
        utils.notify("🌲 Auto-Farm", "disabled", 3)
      end
    end
  end,

  -- Dungeon
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

----------------------------------------------------------------------
-- start()
----------------------------------------------------------------------
local app = {}

function app.start()
  if UI then return end -- already built
  UI = ui_rf.build(handlers, profile.ui or {})
  -- If dungeon present, init once
  if dungeon and dungeon.init then
    dungeon.init()
    if UI.setDungeonAuto   then UI.setDungeonAuto(false)   end
    if UI.setDungeonReplay then UI.setDungeonReplay(false) end
  end
end

----------------------------------------------------------------------
-- export + optional self-boot
----------------------------------------------------------------------
_G.WOODZHUB_APP_EXPORT  = app
_G.WOODZHUB_APP_RUNNING = true

-- auto-start exactly once if run directly
local already = rawget(_G, "WOODZHUB_APP_AUTOBOOTED")
if not already then
  _G.WOODZHUB_APP_AUTOBOOTED = true
  local ok, err = pcall(app.start)
  if not ok then warnf("start() error: " .. tostring(err)) end
end

return app
