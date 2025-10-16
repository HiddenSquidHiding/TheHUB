-- sahur_hopper.lua
-- Merged controller that:
-- 1) Evaluates lobby quality for Sahur farming
-- 2) Farms when lobby is good
-- 3) Calls server_hopper.hopToDifferentServer() when lobby is bad, or on demand

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Your hub's require shim, falling back to plain require if not present:
local function r(name)
    local ok, mod = pcall(function()
        return require(script.Parent[name])
    end)
    if ok then return mod end
    -- if your project has a global r() shim, try it:
    if typeof(_G) == "table" and typeof(_G.r) == "function" then
        local ok2, mod2 = pcall(_G.r, name)
        if ok2 then return mod2 end
    end
    return nil
end

-- Notifications helper (optional; no-op if not available)
local function note(title, text, dur)
    -- If your project has a notifier, call it here. Otherwise fallback to print.
    if _G and _G.note then
        pcall(_G.note, title, text, dur)
    else
        print(string.format("[HUB NOTE] %s: %s", tostring(title), tostring(text)))
    end
end

-- Import farm logic (optional) and the dedicated server hopper (required)
local farm = r("farm") -- should expose run()/start()/stop() or similar; we handle fallbacks below.
local serverHopper = r("server_hopper") -- must expose hopToDifferentServer()

local M = {}

---------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------
M.levelThreshold = 120          -- Players at/above this level make the lobby "bad"
M.recheckInterval = 4           -- Seconds between checks while idle
M.postHopCooldown = 7           -- Seconds to wait after a hop succeeds
M.maxFarmBurstSeconds = 60      -- Safety cap if farm.run() yields too long

-- If your game uses a different way to read level, adjust this function.
local function getPlayerLevel(player: Player): number?
    -- Common patterns: leaderstats.Level IntValue, Attributes.Level, or Data.Level
    local ls = player:FindFirstChild("leaderstats")
    if ls then
        local lv = ls:FindFirstChild("Level")
        if lv and lv:IsA("IntValue") then
            return lv.Value
        end
    end
    local attrLevel = player:GetAttribute("Level") or player:GetAttribute("level")
    if typeof(attrLevel) == "number" then
        return attrLevel
    end
    local data = player:FindFirstChild("Data")
    if data and data:IsA("Folder") then
        local lv2 = data:FindFirstChild("Level")
        if lv2 and (lv2:IsA("IntValue") or lv2:IsA("NumberValue")) then
            return lv2.Value
        end
    end
    return nil
end

-- Decide if the lobby is bad for Sahur farming
function M.isBadLobby()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local lv = getPlayerLevel(plr)
            if lv and lv >= M.levelThreshold then
                return true, ("Found high-level player: %s (Lv %d)"):format(plr.Name, lv)
            end
        end
    end
    return false, "No high-level players detected"
end

---------------------------------------------------------------------
-- Control loop
---------------------------------------------------------------------
local running = false

local function safeFarmBurst()
    if not farm then
        note("Sahur", "Farm module not found; skipping farm step.", 4)
        return
    end

    -- Try common entry points without breaking if absent
    local started = false
    local t0 = os.clock()

    -- Prefer a non-blocking start/stop API if your farm exposes it
    if type(farm.start) == "function" then
        started = true
        local ok, err = pcall(farm.start)
        if not ok then
            note("Sahur", "farm.start failed: " .. tostring(err), 5)
        end
        -- Run for a capped burst to avoid permanent yield
        while running and (os.clock() - t0) < M.maxFarmBurstSeconds do
            task.wait(0.5)
        end
        if type(farm.stop) == "function" then
            pcall(farm.stop)
        end
        return
    end

    -- Otherwise, call run() once inside pcall and cap duration
    if type(farm.run) == "function" then
        started = true
        local finished = false
        task.spawn(function()
            local ok, err = pcall(farm.run)
            if not ok then
                note("Sahur", "farm.run error: " .. tostring(err), 6)
            end
            finished = true
        end)
        while running and not finished and (os.clock() - t0) < M.maxFarmBurstSeconds do
            task.wait(0.5)
        end
        return
    end

    if not started then
        note("Sahur", "farm module has no start()/run(); nothing to do.", 4)
    end
end

local function doHop(reason: string?)
    if not serverHopper or type(serverHopper.hopToDifferentServer) ~= "function" then
        note("Sahur", "server_hopper module missing or invalid.", 6)
        return
    end
    note("Sahur", "Hopping server" .. (reason and (" (" .. reason .. ")") or "") .. "...", 4)
    local ok, err = pcall(serverHopper.hopToDifferentServer)
    if not ok then
        note("Sahur", "Hop failed: " .. tostring(err), 6)
        return
    end
    task.wait(M.postHopCooldown)
end

local function loop()
    while running do
        -- 1) Check lobby
        local bad, why = M.isBadLobby()
        if bad then
            doHop(why)
            -- After a hop call returns, the client is likely teleporting; we still guard with a small wait
            task.wait(M.recheckInterval)
        else
            -- 2) Farm a bit, then re-evaluate
            safeFarmBurst()
            task.wait(M.recheckInterval)
        end
    end
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------
function M.enable()
    if running then return end
    running = true
    note("Sahur", "Auto Sahur: ENABLED", 3)
    task.spawn(loop)
end

function M.disable()
    if not running then return end
    running = false
    note("Sahur", "Auto Sahur: DISABLED", 3)
    -- If your farm has a stop() call, make sure it’s stopped
    if farm and type(farm.stop) == "function" then
        pcall(farm.stop)
    end
end

function M.isRunning()
    return running
end

-- One-shot hop you can wire to a button; delegates to server_hopper.
function M.hopNow()
    doHop("manual")
end

-- Optional runtime config
function M.configure(opts)
    if typeof(opts) ~= "table" then return end
    for k, v in pairs(opts) do
        if M[k] ~= nil then
            M[k] = v
        end
    end
end

return M
