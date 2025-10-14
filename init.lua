-- init.lua — Remote loader for WoodzHUB (safe utils injection + lazy require)
-- Base repo folder (must end with /)
local BASE = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"

----------------------------------------------------------------------
-- Small log helpers
----------------------------------------------------------------------
local PREFIX = "[WoodzHUB]"
local function log(...) print(PREFIX, ...) end
local function warnf(...) warn(PREFIX, ...) end

----------------------------------------------------------------------
-- Minimal utils shim (injected into every module)
----------------------------------------------------------------------
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")

local Utils = {}

function Utils.notify(title, msg, dur)
  dur = dur or 3
  pcall(function()
    StarterGui:SetCore("SendNotification", {
      Title = tostring(title or "WoodzHUB"),
      Text = tostring(msg or ""),
      Duration = dur,
    })
  end)
  print(("[%s] %s"):format(tostring(title or "WoodzHUB"), tostring(msg or "")))
end

function Utils.waitForCharacter()
  local plr = Players.LocalPlayer
  while plr and (not plr.Character
    or not plr.Character:FindFirstChild("HumanoidRootPart")
    or not plr.Character:FindFirstChildOfClass("Humanoid")) do
    plr.CharacterAdded:Wait()
    task.wait()
  end
  return plr and plr.Character
end

----------------------------------------------------------------------
-- HTTP fetch + source cache
----------------------------------------------------------------------
local function http_get(path)
  return game:HttpGet(path, true)
end

local function norm(name)
  -- accept "farm", "farm.lua", "/farm.lua"
  name = tostring(name or ""):gsub("^/*", "")
  if not name:lower():match("%.lua$") then name = name .. ".lua" end
  return name
end

local Source = {}   -- map: "farm.lua" -> source string
local Loaded = {}   -- map: "farm.lua" -> module exports
local Siblings = {  -- fake script.Parent with _deps.utils for modules that expect it
  _deps = { utils = Utils },
}

-- optional prefetch list (only fetch, DO NOT execute)
local Prefetch = {
  "ui_rayfield.lua",
  "games.lua",
  "farm.lua",
  "smart_target.lua",
  "merchants.lua",
  "crates.lua",
  "fastlevel.lua",
  "redeem_unredeemed_codes.lua",
  "dungeon_be.lua",
  "hud.lua",
  "constants.lua",
  "data_monsters.lua",
}

local function fetch_source(name)
  name = norm(name)
  if Source[name] then return true end
  local url = BASE .. name
  local ok, body = pcall(http_get, url)
  if not ok or type(body) ~= "string" or #body == 0 then
    return false, ("HTTP fetch failed for %s"):format(name)
  end
  Source[name] = body
  return true
end

-- soft prefetch (errors are fine; modules are optional)
for _, file in ipairs(Prefetch) do
  fetch_source(file) -- ignore result; it's optional
end

----------------------------------------------------------------------
-- Lazy require (per-module env with utils + fake script)
----------------------------------------------------------------------
local function load_with_env(name)
  name = norm(name)
  if Loaded[name] ~= nil then
    return Loaded[name]
  end
  if not Source[name] then
    local okFetch, why = fetch_source(name)
    if not okFetch then
      error(("[loader] %s"):format(why))
    end
  end

  local chunk, err = loadstring(Source[name], "=" .. name)
  if not chunk then
    error(("[loader] compile failed for %s: %s"):format(name, tostring(err)))
  end

  local env = setmetatable({
    __WOODZ_UTILS = Utils,
    script = { Name = name, Parent = Siblings, _deps = { utils = Utils } },
    require = function(reqName)
      -- allow `require(script.Parent.farm)` style or plain string
      if typeof(reqName) == "Instance" then
        reqName = reqName.Name
      end
      return load_with_env(reqName)
    end,
  }, { __index = getfenv() })
  setfenv(chunk, env)

  local okRun, ret = pcall(chunk)
  if not okRun then
    error(("[loader] runtime error for %s: %s"):format(name, tostring(ret)))
  end

  -- If module returns something, cache it; otherwise use true sentinel
  Loaded[name] = (ret == nil) and true or ret
  -- also expose as sibling for modules that scan script.Parent
  local key = name:gsub("%.lua$", "")
  Siblings[key] = Loaded[name]
  return Loaded[name]
end

----------------------------------------------------------------------
-- Boot app.lua (module)
----------------------------------------------------------------------
local function boot()
  -- Make sure app.lua source exists
  local ok, why = fetch_source("app.lua")
  if not ok then
    warnf("app.lua not found: %s", tostring(why))
    return
  end

  local app = nil
  local okLoad, res = pcall(function() return load_with_env("app.lua") end)
  if okLoad then app = res else
    warnf("Failed to load app.lua: %s", tostring(res))
    return
  end

  if type(app) == "table" and type(app.start) == "function" then
    local okStart, err = pcall(app.start)
    if not okStart then
      warnf("app.start() error: %s", tostring(err))
    end
  else
    warnf("app.lua missing start()")
  end
end

log("Ready")
boot()
