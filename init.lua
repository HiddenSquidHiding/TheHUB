-- init.lua — minimal bootstrap (no sibling loader, no assertions)
-- Set your base once, then fetch app.lua and call start()

if _G.WOODZHUB_RUNNING then return end
_G.WOODZHUB_RUNNING = true

_G.WOODZHUB_BASE = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"  -- <-- trailing slash required

local function fetch(path)
    local ok, res = pcall(game.HttpGet, game, _G.WOODZHUB_BASE .. path, true)
    if not ok then error("HTTP GET failed for " .. path .. ": " .. tostring(res)) end
    return res
end

local function loadRemote(path)
    local src = fetch(path)
    local chunk, err = loadstring(src, "=" .. path)
    if not chunk then error("loadstring failed for " .. path .. ": " .. tostring(err)) end
    return chunk()
end

-- pull in the app and run it
local ok, appOrErr = pcall(loadRemote, "app.lua")
if not ok then
    warn("[WoodzHUB] failed to fetch app.lua: ", appOrErr)
    return
end

local app = appOrErr
if type(app) == "table" and type(app.start) == "function" then
    local ok2, err2 = pcall(app.start)
    if not ok2 then
        warn("[WoodzHUB] app.start error: ", err2)
    end
else
    warn("[WoodzHUB] app.lua missing start()")
end
