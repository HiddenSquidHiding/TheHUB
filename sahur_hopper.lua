-- sahur_hopper.lua
-- Auto-evaluates lobby quality for Sahur farming and hops using server_hopper.hopToDifferentServer()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ------------------------------------------------------------------
-- robust local require that mirrors app.lua's loader
local function r(name)
  -- 1) Use the global HTTP loader if present (same as app.lua)
  local hook = rawget(_G, "__WOODZ_REQUIRE")
  if type(hook) == "function" then
    local ok, mod = pcall(hook, name)
    if ok and mod then return mod end
  end

  -- 2) Try sibling ModuleScripts
  local parent = script and script.Parent
  if parent and parent:FindFirstChild(name) then
    local ok, mod = pcall(require, parent[name])
    if ok and mod then return mod end
  end

  -- 3) Fallback to ReplicatedStorage/Modules if you keep modules there
  local RS = game:GetService("ReplicatedStorage")
  local folders = { RS:FindFirstChild("Modules"), RS }
  for _, folder in ipairs(folders) do
    if folder and folder:FindFirstChild(name) then
      local ok, mod = pcall(require, folder[name])
      if ok and mod then return mod end
    end
  end

  return nil
end
-- ------------------------------------------------------------------

-- Optional notify helper
local function note(title, text, dur)
  if _G and _G.__WOODZ_UTILS and type(_G.__WOODZ_UTILS.notify) == "function" then
    _G.__WOODZ_UTILS.notify(title, text, dur or 3)
  else
    print(string.format("[HUB NOTE] %s: %s", tostring(title), tostring(text)))
  end
end

-- Import farm logic + dedicated server hopper
local farm         = r("farm")               -- may be nil in some games
local serverHopper = r("server_hopper")      -- must expose hopToDifferentServer()

local M = {}

---------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------
M.levelThreshold       = 120     -- lobbies with anyone >= this level are considered "bad"
M.recheckInterval      = 4       -- seconds between loop iterations
M.postHopCooldown      = 7       -- wait after hop is triggered
M.maxFarmBurstSeconds  = 60      -- cap for a single farm burst

-- Find a player's level; tweak this for your game’s data model if needed
local function getPlayerLevel(player: Player): number?
  local ls = player:FindFirstChild("leaderstats")
  if ls then
    local lv = ls:FindFirstChild("Level")
    if lv and lv:IsA("IntValue") then return lv.Value end
  end
  local attr = player:GetAttribute("Level") or player:GetAttribute("level")
  if typeof(attr) == "number" then return attr end
  local data = player:FindFirstChild("Data")
  if data and data:IsA("Folder") then
    local lv2 = data:FindFirstChild("Level")
    if lv2 and (lv2:IsA("IntValue") or lv2:IsA("NumberValue")) then return lv2.Value end
  end
  return nil
end

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
local warnedNoFarm = false

local function safeFarmBurst()
  if not farm then
    if not warnedNoFarm then
      warnedNoFarm = true
      note("Sahur", "Farm module not found; skipping farm step.", 4)
    end
    return
  end

  local t0 = os.clock()

  -- Prefer start()/stop() pattern
  if type(farm.start) == "function" and type(farm.stop) == "function" then
    local okStart, err = pcall(farm.start)
    if not okStart then
      note("Sahur", "farm.start failed: " .. tostring(err), 5)
      return
    end
    while running and (os.clock() - t0) < M.maxFarmBurstSeconds do
      task.wait(0.5)
    end
    pcall(farm.stop)
    return
  end

  -- Fallback: run() once inside spawn; cap time
  if type(farm.run) == "function" then
    local finished = false
    task.spawn(function()
      local okRun, errRun = pcall(farm.run)
      if not okRun then
        note("Sahur", "farm.run error: " .. tostring(errRun), 6)
      end
      finished = true
    end)
    while running and not finished and (os.clock() - t0) < M.maxFarmBurstSeconds do
      task.wait(0.5)
    end
    return
  end

  if not warnedNoFarm then
    warnedNoFarm = true
    note("Sahur", "farm module has no start()/run(); nothing to do.", 4)
  end
end

local function doHop(reason: string?)
  if not serverHopper or type(serverHopper.hopToDifferentServer) ~= "function" then
    note("Sahur", "server_hopper module missing or invalid.", 5)
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
    local bad, why = M.isBadLobby()
    if bad then
      doHop(why)
      task.wait(M.recheckInterval)
    else
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
  warnedNoFarm = false
  note("Sahur", "Auto Sahur: ENABLED", 3)
  task.spawn(loop)
end

function M.disable()
  if not running then return end
  running = false
  note("Sahur", "Auto Sahur: DISABLED", 3)
  if farm and type(farm.stop) == "function" then
    pcall(farm.stop)
  end
end

function M.isRunning()
  return running
end

-- Manual hop (for a button)
function M.hopNow()
  doHop("manual")
end

-- Optional runtime config
function M.configure(opts)
  if typeof(opts) ~= "table" then return end
  for k, v in pairs(opts) do
    if M[k] ~= nil then M[k] = v end
  end
end

return M
