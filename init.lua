-- init.lua — robust HTTP loader for WoodzHUB (one file)
-- Loads all hub files from your GitHub, wires a sibling-style `require`,
-- injects utils so modules that call getUtils() don't crash, then runs app.

local BASE = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"

-- What we *might* load. Missing ones are OK (marked optional).
local WANT = {
  "app.lua",
  "ui_rayfield.lua",
  "games.lua",
  -- feature modules (optional; load if present)
  "farm.lua",
  "smart_target.lua",
  "merchants.lua",
  "crates.lua",
  "fastlevel.lua",
  "redeem_unredeemed_codes.lua",
  "dungeon_be.lua",
  "anti_afk.lua",
  "hud.lua",
  "constants.lua",
  "data_monsters.lua",
  "solo.lua",
  "sahur_hopper.lua",
  "server_hopper.lua",  -- NEW: For server hop button
}

----------------------------------------------------------------------
-- Utils injected for every module (satisfies getUtils() fallbacks)
----------------------------------------------------------------------
local function notify(title, msg, dur)
  dur = dur or 3
  print(("🌲 %s | %s"):format(tostring(title), tostring(msg)))
end

local utils = {
  notify = notify,
  waitForCharacter = function()
    local Players = game:GetService("Players")
    local p = Players.LocalPlayer
    while not p.Character
      or not p.Character:FindFirstChild("HumanoidRootPart")
      or not p.Character:FindFirstChildOfClass("Humanoid") do
      p.CharacterAdded:Wait()
      task.wait()
    end
    return p.Character
  end,
}

-- Make modules that look for __WOODZ_UTILS happy
getfenv(0).__WOODZ_UTILS = utils

----------------------------------------------------------------------
-- Fetch all files we care about
----------------------------------------------------------------------
local httpGet = function(url)
  return game:HttpGet(url)
end

local sources = {}   -- name -> source string
for _, fname in ipairs(WANT) do
  local url = BASE .. fname
  local ok, src = pcall(httpGet, url)
  if ok and type(src) == "string" and #src > 0 then
    sources[fname] = src
  else
    warn(("[loader] Failed to fetch %s from %s"):format(fname, url))
  end
end

----------------------------------------------------------------------
-- Sibling-style require shim
----------------------------------------------------------------------
local moduleCache = {} -- name -> module table/function result

local function normalize(name)
  -- allow "ui_rayfield" or "ui_rayfield.lua"
  if sources[name] then return name end
  local withLua = name .. ".lua"
  if sources[withLua] then return withLua end
  return nil
end

local function makeEnv(name, requireFn, siblingsTable)
  -- Provide a `script` with Parent->_deps.utils like ModuleScripts expect
  local env = {}
  env.script = { Parent = siblingsTable }
  setmetatable(env, { __index = getfenv(0) })
  return env
end

local siblings = {
  _deps = { utils = utils },
}

local function shimRequire(name)
  local key = normalize(name)
  if not key then
    warn(("[loader] require(%s) not found (missing from sources)"):format(tostring(name)))
    return nil
  end
  if moduleCache[key] ~= nil then return moduleCache[key] end

  local chunkSrc = sources[key]
  local chunk, err = loadstring(chunkSrc, "=" .. key)
  if not chunk then
    warn(("[loader] compile failed for %s: %s"):format(key, tostring(err)))
    return nil
  end

  local function localRequire(childName) return shimRequire(childName) end
  local env = makeEnv(key, localRequire, siblings)
  env.require = localRequire
  env.__WOODZ_UTILS = utils
  setfenv(chunk, env)

  local ok, ret = pcall(chunk)
  if not ok then
    warn(("[loader] runtime error for %s: %s"):format(key, tostring(ret)))
    return nil
  end

  moduleCache[key] = ret
  siblings[key:gsub("%.lua$","")] = ret -- allow script.Parent.ui_rayfield style
  return ret
end

-- 🔹 FIX: Expose the shim as global so app.lua's r() works
_G.__WOODZ_REQUIRE = shimRequire

-- 🔹 NEW: Set globals for farm.lua (preload data_monsters + base URL)
_G.WOODZ_BASE_URL = BASE
local dataMonstersMod = shimRequire("data_monsters")
if dataMonstersMod and type(dataMonstersMod) == "table" then
  _G.WOODZ_DATA_MONSTERS = dataMonstersMod
  print("[loader] Preloaded data_monsters.lua successfully.")
else
  warn("[loader] data_monsters.lua missing or invalid; farm.lua may fetch it directly.")
end

----------------------------------------------------------------------
-- Boot app.lua
----------------------------------------------------------------------
local appMod = sources["app.lua"] and shimRequire("app") or nil
if not appMod then
  warn("[WoodzHUB] app.lua missing on GitHub URL; nothing to run.")
  return
end

-- app.lua might `return { start=function() ... end }` OR return a function.
if type(appMod) == "table" and type(appMod.start) == "function" then
  appMod.start()
elseif type(appMod) == "function" then
  appMod() -- legacy form
else
  warn("[WoodzHUB] app.lua returned an unexpected value; expected table with start() or a function.")
end

print("🌲 WoodzHUB Loaded successfully.")
