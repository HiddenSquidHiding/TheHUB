-- app.lua — WoodzHUB bootstrap (executor-friendly)
-- Loads sibling modules from your GitHub repo, injects utils, honors games.lua,
-- and starts the right UI/logic for the current place.

----------------------------------------------------------------------
-- 0) Guard against double-boot
----------------------------------------------------------------------
if _G.__WOODZHUB_RUNNING then
  warn("[WoodzHUB] app.lua already running; skipping second boot.")
  return
end
_G.__WOODZHUB_RUNNING = true

----------------------------------------------------------------------
-- 1) HTTP config — set base once; all files fetched as BASE .. filename
----------------------------------------------------------------------
local URLS_BASE = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"

-- Optional per-file overrides (leave empty to use URLS_BASE for all)
local URLS = {
  -- ["ui_rayfield.lua"] = URLS_BASE .. "alt/path/ui_rayfield.lua",
}

local function url_for(fname)
  if URLS[fname] and URLS[fname] ~= "" then return URLS[fname] end
  -- normalize // → / but keep https://
  local u = (URLS_BASE .. fname):gsub("//+", "/"):gsub("^https:/", "https://")
  return u
end

local function fetch_source(fname)
  local url = url_for(fname)
  local ok, body = pcall(game.HttpGet, game, url)
  if not ok then
    warn(("[WoodzHUB] [load] %s → HTTP failed: %s  (%s)"):format(fname, tostring(body), url))
    return nil, "http failed: " .. tostring(body)
  end
  if type(body) ~= "string" or #body == 0 then
    warn(("[WoodzHUB] [load] %s → empty body (%s)"):format(fname, url))
    return nil, "empty body"
  end
  return body
end

----------------------------------------------------------------------
-- 2) Minimal utils injected for all modules (matches your modules’ needs)
----------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local utils = {
  notify = function(title, msg, dur)
    dur = dur or 3
    print(("[%s] %s"):format(title, msg))
    -- You can swap-in your on-screen notifier here if desired.
  end,

  -- Tiny constructor used across modules
  new = function(className, props, parent)
    local inst = Instance.new(className)
    if props then for k,v in pairs(props) do inst[k] = v end end
    if parent then inst.Parent = parent end
    return inst
  end,

  track = function(conn) return conn end, -- placeholder

  waitForCharacter = function()
    local plr = Players.LocalPlayer
    while true do
      local ch = plr.Character
      if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
        return ch
      end
      plr.CharacterAdded:Wait()
      RunService.Heartbeat:Wait()
    end
  end,
}

----------------------------------------------------------------------
-- 3) Fake “script/Parent” so `require(script.Parent.X)` keeps working
--    in non-ModuleScript, executor-loaded code.
----------------------------------------------------------------------
local source_cache = {}  -- fname -> source string
local module_cache = {}  -- fname -> returned module value

local function makeFakeChild(name, parent)
  local child = {
    __is_fake = true,
    __name = name,
    Parent = parent,
  }
  function child:IsA(_) return true end
  function child:FindFirstChild(n) return nil end
  function child:WaitForChild(n, _) return nil end
  return child
end

local function makeFakeParent()
  local parent = { _deps = { utils = utils } }
  function parent:FindFirstChild(n) return makeFakeChild(n, parent) end
  function parent:WaitForChild(n, _) return makeFakeChild(n, parent) end
  return parent
end

local function build_env(fname)
  local env = getfenv()
  local fakeParent = makeFakeParent()
  local fakeScript = {
    Name = fname:gsub("%.lua$", ""),
    Parent = fakeParent
  }
  local e = {
    script = fakeScript,
    __WOODZ_UTILS = utils,
    require = nil,  -- filled below
  }
  setmetatable(e, { __index = env })
  return e
end

-- shim require that understands:
--   require("name")            -> loads "name.lua"
--   require(script.Parent.name)-> loads "name.lua"
local function resolve_fname_from_require(arg)
  if type(arg) == "string" then
    local n = arg
    if not n:match("%.lua$") then n = n .. ".lua" end
    return n
  elseif type(arg) == "table" and arg.__is_fake and arg.__name then
    local n = arg.__name
    if not n:match("%.lua$") then n = n .. ".lua" end
    return n
  end
  return nil
end

local function load_module(fname)
  -- serve from cache
  if module_cache[fname] ~= nil then return module_cache[fname] end

  -- fetch code
  local src = source_cache[fname]
  if not src then
    local body, err = fetch_source(fname)
    if not body then error(("[loader] failed to fetch %s: %s"):format(fname, tostring(err))) end
    source_cache[fname] = body
    src = body
  end

  local chunk, cerr = loadstring(src, "=" .. fname)
  if not chunk then error(("[loader] compile failed for %s: %s"):format(fname, tostring(cerr))) end

  local env = build_env(fname)
  -- wire require now that env exists
  env.require = function(arg)
    local child_fname = resolve_fname_from_require(arg)
    if not child_fname then
      error(("[loader] require(%s) unsupported in %s"):format(typeof(arg), fname))
    end
    return load_module(child_fname)
  end
  setfenv(chunk, env)

  local ok, ret = pcall(chunk)
  if not ok then error(("[loader] error running %s: %s"):format(fname, tostring(ret))) end

  module_cache[fname] = ret
  return ret
end

local function require_optional(fname_wo_ext)
  local fname = fname_wo_ext:match("%.lua$") and fname_wo_ext or (fname_wo_ext .. ".lua")
  local ok, mod = pcall(load_module, fname)
  if not ok then
    warn(("[WoodzHUB] optional module '%s' not available: %s"):format(fname_wo_ext, tostring(mod)))
    return nil, mod
  end
  return mod
end

----------------------------------------------------------------------
-- 4) Load games.lua profile (universe/place router)
----------------------------------------------------------------------
local function load_games_config()
  local ok, tbl = pcall(load_module, "games.lua")
  if not ok or type(tbl) ~= "table" then
    warn("[WoodzHUB] games.lua missing or invalid; falling back to default")
    return {
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
  return tbl
end

local function resolve_profile(games)
  local universeKey = tostring(game.GameId)
  local placeKey    = "place:" .. tostring(game.PlaceId)

  if games[placeKey] then return games[placeKey], placeKey end
  if games[universeKey] then return games[universeKey], universeKey end
  return games.default, "default"
end

----------------------------------------------------------------------
-- 5) App.start() — build UI and wire handlers according to profile
----------------------------------------------------------------------
local app = {}

function app.start()
  local games = load_games_config()
  local profile, key = resolve_profile(games)
  if not profile then
    warn("[WoodzHUB] profile not found in games.lua; aborting")
    return
  end

  print(("[WoodzHUB] profile: %s (key=%s)"):format(profile.name or "?", key))

  -- Preload requested modules (they’ll be accessible to others via our shim)
  for _, name in ipairs(profile.modules or {}) do
    local m, err = require_optional(name)
    if not m then
      warn(("[WoodzHUB] module unavailable (skipped): %s"):format(name))
    end
  end

  -- Try to load Rayfield UI (optional)
  local ui = require_optional("ui_rayfield")
  if not ui then
    warn("[ui_rayfield] Rayfield failed to load")
  end

  -- Pull optional modules we may need to wire
  local farm        = require_optional("farm")
  local smart       = require_optional("smart_target")
  local crates      = require_optional("crates")
  local merchants   = require_optional("merchants")
  local anti_afk    = require_optional("anti_afk")
  local redeemCodes = require_optional("redeem_unredeemed_codes")
  local fastlevel   = require_optional("fastlevel")
  local dungeon_be  = require_optional("dungeon_be") -- for dungeon profile

  -- If there’s a dungeon module and this profile wants it, init it now (no UI).
  if dungeon_be and table.find(profile.modules or {}, "dungeon_be") then
    pcall(function() if dungeon_be.init then dungeon_be.init() end end)
  end

  --------------------------------------------------------------------
  -- Build Rayfield UI if available + profile enables it
  --------------------------------------------------------------------
  if ui and ui.build then
    -- Prevent double window creation
    if _G.__WOODZHUB_RF then
      warn("[WoodzHUB] Rayfield window already exists; skipping UI rebuild.")
      return
    end

    local RF = ui.build({
      -- Search/picker events
      onClearAll = function() if farm and farm.setSelected then farm.setSelected({}) end end,

      -- Auto-Farm
      onAutoFarmToggle = function(on)
        if not farm or not farm.runAutoFarm or not farm.setupAutoAttackRemote then return end
        if on then
          farm.setupAutoAttackRemote()
          task.spawn(function()
            farm.runAutoFarm(function() return true end, function(text)
              pcall(function() if RF and RF.setCurrentTarget then RF.setCurrentTarget(text) end end)
            end)
          end)
        else
          -- farm loop uses the getter to stop; no action needed here
        end
      end,

      -- Smart Farm
      onSmartFarmToggle = function(on)
        if not smart or not smart.runSmartFarm then return end
        if on then
          -- try to locate MonsterInfo automatically inside smart_target
          task.spawn(function()
            smart.runSmartFarm(function() return true end, function(text)
              pcall(function() if RF and RF.setCurrentTarget then RF.setCurrentTarget(text) end end)
            end, { safetyBuffer = 0.8, refreshInterval = 0.05 })
          end)
        end
      end,

      -- Options
      onToggleAntiAFK = function(on)
        if not anti_afk then return end
        if on and anti_afk.enable then anti_afk.enable()
        elseif anti_afk.disable then anti_afk.disable() end
      end,

      onToggleCrates = function(on)
        if not crates or not crates.autoOpenCratesEnabledLoop then return end
        if on then
          task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return true end) end)
        end
      end,

      onToggleMerchant1 = function(on)
        if not merchants or not merchants.autoBuyLoop then return end
        if on then task.spawn(function()
          merchants.autoBuyLoop("SmelterMerchantService", function() return true end, function() end)
        end) end
      end,
      onToggleMerchant2 = function(on)
        if not merchants or not merchants.autoBuyLoop then return end
        if on then task.spawn(function()
          merchants.autoBuyLoop("SmelterMerchantService2", function() return true end, function() end)
        end) end
      end,

      onRedeemCodes = function()
        if not redeemCodes or not redeemCodes.run then return end
        task.spawn(function() redeemCodes.run({ dryRun=false, concurrent=true, delayBetween=0.25 }) end)
      end,

      onFastLevelToggle = function(on)
        if not fastlevel then return end
        if on and fastlevel.enable then fastlevel.enable()
        elseif fastlevel.disable then fastlevel.disable() end
      end,
    })

    _G.__WOODZHUB_RF = RF
    utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  else
    print("[WoodzHUB] Ready")
  end
end

----------------------------------------------------------------------
-- 6) Kick it off
----------------------------------------------------------------------
local ok, err = pcall(app.start)
if not ok then
  warn("[WoodzHUB] app.lua start() error: " .. tostring(err))
end
