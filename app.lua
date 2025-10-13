-- app.lua (GitHub loader version)
-- Loads sibling Lua files from your GitHub repo via game:HttpGet (raw URLs),
-- then wires Rayfield UI & per-game profiles from games.lua.

-------------------------------------------------------------
-- 0) Configure your GitHub raw base URL (folder with files)
-------------------------------------------------------------
-- Example: https://raw.githubusercontent.com/<USER>/<REPO>/<BRANCH>/WoodzHUB/
local GITHUB_RAW_BASE = _G.WOODZHUB_BASE or "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"

-- Optional: cache-buster query (e.g. set _G.WOODZHUB_VER = os.time() when you update)
local CACHE_BUSTER = _G.WOODZHUB_VER and ("?v=" .. tostring(_G.WOODZHUB_VER)) or ""

-------------------------------------------------------------
-- 1) Minimal utils (global so other modules can use them)
-------------------------------------------------------------
_G.__WOODZ_UTILS = _G.__WOODZ_UTILS or {
  notify = function(title, msg, dur)
    dur = dur or 3
    print(("[%s] %s"):format(title, tostring(msg)))
  end,
  waitForCharacter = function()
    local Players = game:GetService("Players")
    local plr = Players.LocalPlayer
    while true do
      local ch = plr and plr.Character
      if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
        return ch
      end
      if plr then plr.CharacterAdded:Wait() end
      task.wait(0.05)
    end
  end,
}

-------------------------------------------------------------
-- 2) GitHub "require" helper: requireNet("name") -> module table
-------------------------------------------------------------
local HttpService = game:GetService("HttpService")

local __NET_CACHE = {}

local function buildUrl(name)
  -- name like "games" -> {BASE}/games.lua
  return (GITHUB_RAW_BASE .. name .. ".lua" .. CACHE_BUSTER)
end

local function requireNet(name, required)
  if __NET_CACHE[name] ~= nil then return __NET_CACHE[name] end
  local url = buildUrl(name)

  local src
  local ok, err = pcall(function()
    src = game:HttpGet(url)
  end)
  if not ok or type(src) ~= "string" or #src == 0 then
    warn(("[app.lua] %sload failed: %s"):format(required and "required " or "optional ", tostring(url)))
    __NET_CACHE[name] = nil
    return nil
  end

  local chunk, cerr = loadstring(src, "="..url)
  if not chunk then
    warn(("[app.lua] compile error %s: %s"):format(url, tostring(cerr)))
    __NET_CACHE[name] = nil
    return nil
  end

  -- sandbox that exposes __WOODZ_UTILS and 'exports'
  local env = setmetatable({
    __WOODZ_UTILS = _G.__WOODZ_UTILS,
    exports = {},
  }, { __index = getfenv() })
  setfenv(chunk, env)

  local ok2, ret = pcall(chunk)
  if not ok2 then
    warn(("[app.lua] runtime error in %s: %s"):format(url, tostring(ret)))
    __NET_CACHE[name] = nil
    return nil
  end

  local mod = ret
  if mod == nil then
    mod = env.exports
    if next(mod) == nil then
      mod = rawget(_G, name)
    end
  end

  if mod == nil then
    warn(("[app.lua] %s returned nothing; continuing"):format(url))
  end

  __NET_CACHE[name] = mod
  return mod
end

-------------------------------------------------------------
-- 3) Load games.lua (profile map by place/universe)
-------------------------------------------------------------
local function loadGamesConfig()
  local games = requireNet("games", false)
  if type(games) ~= "table" then
    warn("[app.lua] games.lua missing or invalid; falling back to default")
    games = {
      default = {
        name = "Generic",
        modules = { "anti_afk" },
        ui = {
          modelPicker=false, currentTarget=false,
          autoFarm=false, smartFarm=false,
          merchants=false, crates=false, antiAFK=true,
          redeemCodes=false, fastlevel=false, privateServer=false,
          dungeon=false,
        },
      }
    }
  end
  return games
end

local function chooseProfile(games)
  local placeKey = "place:" .. tostring(game.PlaceId)
  local uniKey   = tostring(game.GameId)
  local profile  = games[placeKey] or games[uniKey] or games.default
  local picked   = games[placeKey] and placeKey or (games[uniKey] and uniKey or "default")
  print(("[app.lua] profile: %s (key=%s)"):format(tostring(profile and profile.name or "unnamed"), picked))
  return profile
end

-------------------------------------------------------------
-- 4) Boot per profile + Rayfield UI wiring (if present)
-------------------------------------------------------------
local function boot()
  local games   = loadGamesConfig()
  local profile = chooseProfile(games)
  local uiFlags = profile.ui or {}

  -- Load requested modules (from GitHub)
  local loaded = {}
  for _, modName in ipairs(profile.modules or {}) do
    local m = requireNet(modName, false)
    if m ~= nil then
      loaded[modName] = m
      print(("[app.lua] loaded: %s"):format(modName))
    else
      warn(("[app.lua] module unavailable (skipped): %s"):format(modName))
    end
  end

  -- Optional Rayfield UI (executor fetch happens inside ui_rayfield.lua)
  local uiRF = nil
  if uiFlags and (
      uiFlags.modelPicker or uiFlags.currentTarget or uiFlags.autoFarm or
      uiFlags.smartFarm or uiFlags.merchants or uiFlags.crates or
      uiFlags.antiAFK or uiFlags.redeemCodes or uiFlags.fastlevel or
      uiFlags.privateServer or uiFlags.dungeon
    ) then
    uiRF = requireNet("ui_rayfield", false)
    if not uiRF then
      warn("[app.lua] ui_rayfield.lua missing - UI not loaded. Core still running.")
    end
  end

  -- Build UI + wire callbacks
  local RF = nil
  if uiRF and type(uiRF.build) == "function" then
    RF = uiRF.build({
      onAutoFarmToggle = (uiFlags.autoFarm and loaded.farm) and function(v)
        if v then
          if loaded.farm.setupAutoAttackRemote then loaded.farm.setupAutoAttackRemote() end
          task.spawn(function()
            loaded.farm.runAutoFarm(function() return true end, function(txt)
              if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(txt) end) end
            end)
          end)
        else
          if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget("Current Target: None") end) end
        end
      end or nil,

      onSmartFarmToggle = (uiFlags.smartFarm and loaded.smart_target) and function(v)
        if v then
          task.spawn(function()
            loaded.smart_target.runSmartFarm(function() return true end, function(txt)
              if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(txt) end) end
            end, { safetyBuffer = 0.8, refreshInterval = 0.05 })
          end)
        else
          if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget("Current Target: None") end) end
        end
      end or nil,

      onToggleMerchant1 = (uiFlags.merchants and loaded.merchants) and function(v)
        if v then task.spawn(function()
          loaded.merchants.autoBuyLoop("SmelterMerchantService", function() return true end, function() end)
        end) end
      end or nil,

      onToggleMerchant2 = (uiFlags.merchants and loaded.merchants) and function(v)
        if v then task.spawn(function()
          loaded.merchants.autoBuyLoop("SmelterMerchantService2", function() return true end, function() end)
        end) end
      end or nil,

      onToggleCrates = (uiFlags.crates and loaded.crates) and function(v)
        if v then
          if loaded.crates.refreshCrateInventory then loaded.crates.refreshCrateInventory(true) end
          task.spawn(function() loaded.crates.autoOpenCratesEnabledLoop(function() return true end) end)
        end
      end or nil,

      onToggleAntiAFK = (uiFlags.antiAFK and loaded.anti_afk) and function(v)
        if v then loaded.anti_afk.enable() else loaded.anti_afk.disable() end
      end or nil,

      onRedeemCodes = (uiFlags.redeemCodes and loaded.redeem_unredeemed_codes) and function()
        task.spawn(function()
          pcall(function() loaded.redeem_unredeemed_codes.run({ dryRun=false, concurrent=true, delayBetween=0.25 }) end)
        end)
      end or nil,

      onFastLevelToggle = (uiFlags.fastlevel and loaded.fastlevel and loaded.farm) and function(v)
        if v then
          if loaded.fastlevel.enable then loaded.fastlevel.enable() end
          if loaded.farm.setFastLevelEnabled then loaded.farm.setFastLevelEnabled(true) end
          if loaded.farm.setupAutoAttackRemote then loaded.farm.setupAutoAttackRemote() end
          task.spawn(function()
            loaded.farm.runAutoFarm(function() return true end, function(txt)
              if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(txt) end) end
            end)
          end)
        else
          if loaded.fastlevel.disable then loaded.fastlevel.disable() end
          if loaded.farm.setFastLevelEnabled then loaded.farm.setFastLevelEnabled(false) end
          if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget("Current Target: None") end) end
        end
      end or nil,
    })
  end

  -- Dungeon one-shot (if you host a dedicated module like dungeon_be.lua)
  if uiFlags.dungeon and loaded.dungeon_be then
    local d = loaded.dungeon_be
    if type(d.start) == "function" then pcall(d.start)
    elseif type(d.run) == "function" then pcall(d.run)
    end
  end

  _G.__WOODZ_UTILS.notify("🌲 WoodzHUB", "Loaded profile: "..tostring(profile.name or "Unknown"), 4)
end

boot()
return { start = boot }
