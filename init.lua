-- init.lua — single-file HTTP bootstrap that loads siblings by name from your repo
-- Usage: loadstring(game:HttpGet('https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/init.lua'))()

local BASE = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"

local src = game:HttpGet(_G.WOODZ_BASE_URL .. "data_monsters.lua")
local f = loadstring(src); _G.WOODZ_DATA_MONSTERS = f()

-- Simple fetch with retry
local function fetch(url)
  local ok, res = pcall(game.HttpGet, game, url)
  if ok and type(res) == "string" and #res > 0 then return res end
  task.wait(0.25)
  ok, res = pcall(game.HttpGet, game, url)
  return ok and res or nil
end

-- Loader cache so we only compile once
local cache = {}

-- Global require-by-name used by app.lua
_G.__WOODZ_REQUIRE = function(name)
  assert(type(name) == "string" and name:match("%.lua$")==nil, "pass bare filename without .lua")
  local fname = name .. ".lua"
  if cache[fname] then return cache[fname] end

  local url = BASE .. fname
  local src = fetch(url)
  if not src then error("[init] failed to fetch "..fname) end

  local chunk, err = loadstring(src, "="..fname)
  if not chunk then error("[init] compile error for "..fname..": "..tostring(err)) end
  local ok, mod = pcall(chunk)
  if not ok then error("[init] runtime error for "..fname..": "..tostring(mod)) end
  cache[fname] = mod
  return mod
end

-- Guard against double-start
if _G.__WOODZ_BOOTED then
  warn("[WoodzHUB] already booted")
  return
end
_G.__WOODZ_BOOTED = true

-- Load app.lua as a module and call start()
local ok, app = pcall(_G.__WOODZ_REQUIRE, "app")
if not ok or type(app) ~= "table" or type(app.start) ~= "function" then
  warn("[WoodzHUB] app.lua missing start()")
  return
end

app.start()
print("[WoodzHUB] Ready")
