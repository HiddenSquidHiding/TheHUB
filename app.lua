-- app.lua — WoodzHUB bootstrap (executor-friendly, loader-friendly)
-- - Loads modules from your GitHub repo
-- - Injects utils so sibling requires work
-- - Uses games.lua to pick the right profile
-- - Exports app.start for loaders AND auto-starts when run directly
-- - Strong double-boot guard

----------------------------------------------------------------------
-- 0) Double-boot guard
----------------------------------------------------------------------
if _G.__WOODZHUB_RUNNING then
  warn("[WoodzHUB] app.lua already running; skipping second boot.")
  return
end
_G.__WOODZHUB_RUNNING = true

----------------------------------------------------------------------
-- 1) HTTP base
----------------------------------------------------------------------
local URLS_BASE = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"
local URLS = { } -- per-file overrides if ever needed

local function url_for(fname)
  local u = (URLS[fname] or (URLS_BASE .. fname))
  u = u:gsub("//+", "/"):gsub("^https:/", "https://")
  return u
end

local function fetch_source(fname)
  local url = url_for(fname)
  local ok, body = pcall(game.HttpGet, game, url)
  if not ok or type(body) ~= "string" or #body == 0 then
    return nil, ("HTTP get failed for %s (%s)"):format(fname, url)
  end
  return body
end

----------------------------------------------------------------------
-- 2) Minimal utils (matches your modules’ expectations)
----------------------------------------------------------------------
local Players, RunService = game:GetService("Players"), game:GetService("RunService")

local utils = {
  notify = function(title, msg, dur)
    print(("[%s] %s"):format(title, msg))
  end,
  new = function(className, props, parent)
    local inst = Instance.new(className)
    if props then for k,v in pairs(props) do inst[k]=v end end
    if parent then inst.Parent = parent end
    return inst
  end,
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
-- 3) Fake script/Parent so require(script.Parent.x) works in executor context
----------------------------------------------------------------------
local source_cache, module_cache = {}, {}

local function makeFakeChild(name, parent)
  local t = { __is_fake = true, __name = name, Parent = parent }
  function t:IsA(_) return true end
  function t:FindFirstChild(_) return nil end
  function t:WaitForChild(_,__) return nil end
  return t
end

local function makeFakeParent()
  local parent = { _deps = { utils = utils } }
  function parent:FindFirstChild(n) return makeFakeChild(n, parent) end
  function parent:WaitForChild(n,_) return makeFakeChild(n, parent) end
  return parent
end

local function build_env(fname)
  local env = getfenv()
  local fakeParent = makeFakeParent()
  local fakeScript = { Name = fname:gsub("%.lua$",""), Parent = fakeParent }
  local e = { script = fakeScript, __WOODZ_UTILS = utils, require = nil }
  setmetatable(e, { __index = env })
  return e
end

local function resolve_fname_from_require(arg)
  if type(arg) == "string" then
    return arg:match("%.lua$") and arg or (arg .. ".lua")
  elseif type(arg) == "table" and arg.__is_fake and arg.__name then
    return arg.__name:match("%.lua$") and arg.__name or (arg.__name .. ".lua")
  end
  return nil
end

local function load_module(fname)
  if module_cache[fname] ~= nil then return module_cache[fname] end

  local src = source_cache[fname]
  if not src then
    local body, err = fetch_source(fname)
    if not body then error(("[loader] %s"):format(err)) end
    source_cache[fname] = body
    src = body
  end

  local chunk, cerr = loadstring(src, "=" .. fname)
  if not chunk then error(("[loader] compile failed for %s: %s"):format(fname, tostring(cerr))) end

  local env = build_env(fname)
  env.require = function(arg)
    local child = resolve_fname_from_require(arg)
    if not child then error(("[loader] require(%s) unsupported in %s"):format(typeof(arg), fname)) end
    return load_module(child)
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
  if not ok then return nil, mod end
  return mod
end

----------------------------------------------------------------------
-- 4) games.lua (routing)
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
  local placeKey = "place:" .. tostring(game.PlaceId)
  if games[placeKey] then return games[placeKey], placeKey end
  local uniKey = tostring(game.GameId)
  if games[uniKey] then return games[uniKey], uniKey end
  return games.default, "default"
end

----------------------------------------------------------------------
-- 5) App object (exported) + start()
----------------------------------------------------------------------
local app = {}

function app.start()
  local games = load_games_config()
  local profile, key = resolve_profile(games)
  print(("[WoodzHUB] profile: %s (key=%s)"):format(profile.name or "?", key))

  -- Preload requested modules so they’re available to each other
  for _, name in ipairs(profile.modules or {}) do
    local _ = require_optional(name) -- no warning spam; optional
  end

  -- Optional modules we may hook
  local ui           = require_optional("ui_rayfield")
  local farm         = require_optional("farm")
  local smart        = require_optional("smart_target")
  local crates       = require_optional("crates")
  local merchants    = require_optional("merchants")
  local anti_afk     = require_optional("anti_afk")
  local redeemCodes  = require_optional("redeem_unredeemed_codes")
  local fastlevel    = require_optional("fastlevel")
  local dungeon_be   = require_optional("dungeon_be")

  -- If dungeon helper is part of this profile, init it (no GUI)
  if dungeon_be and table.find(profile.modules or {}, "dungeon_be") then
    pcall(function() if dungeon_be.init then dungeon_be.init() end end)
  end

  -- Build Rayfield UI if present in profile + module fetched
  if ui and ui.build then
    if _G.__WOODZHUB_RF then
      -- already built elsewhere (e.g., external loader required app.lua and called start())
      return
    end

    local RF = ui.build({
      onClearAll = function() if farm and farm.setSelected then farm.setSelected({}) end end,

      onAutoFarmToggle = function(on)
        if not farm or not farm.runAutoFarm or not farm.setupAutoAttackRemote then return end
        if on then
          farm.setupAutoAttackRemote()
          task.spawn(function()
            farm.runAutoFarm(function() return true end, function(text)
              pcall(function() if RF and RF.setCurrentTarget then RF.setCurrentTarget(text) end end)
            end)
          end)
        end
      end,

      onSmartFarmToggle = function(on)
        if not smart or not smart.runSmartFarm then return end
        if on then
          task.spawn(function()
            smart.runSmartFarm(function() return true end, function(text)
              pcall(function() if RF and RF.setCurrentTarget then RF.setCurrentTarget(text) end end)
            end, { safetyBuffer = 0.8, refreshInterval = 0.05 })
          end)
        end
      end,

      onToggleAntiAFK = function(on)
        if not anti_afk then return end
        if on and anti_afk.enable then anti_afk.enable()
        elseif anti_afk.disable then anti_afk.disable() end
      end,

      onToggleCrates = function(on)
        if not crates or not crates.autoOpenCratesEnabledLoop then return end
        if on then task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return true end) end) end
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
-- 6) Export AND (conditionally) auto-start
-- If some external loader requires('app.lua'), it gets { start = ... } and will
-- call app.start itself. When you run this file directly in an executor,
-- it auto-starts once.
----------------------------------------------------------------------
local running_as_required = (debug and debug.getinfo and debug.getinfo(2, "S")) and true or false
-- The above is a crude hint; we still protect with the global flag.

-- If an external loader explicitly set this flag, we won't auto-start.
if not _G.__WOODZHUB_EXTERNAL_BOOT then
  local ok, err = pcall(app.start)
  if not ok then warn("[WoodzHUB] app.start() error: " .. tostring(err)) end
end

return app
