-- sahur_hopper.lua
-- Auto-evaluates lobby quality for Sahur farming and hops using server_hopper.hopToDifferentServer()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- =========================
-- robust local require (matches app.lua behavior)
local function r(name)
  -- 1) Try global HTTP loader (_G.__WOODZ_REQUIRE)
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

  -- 3) Optional: ReplicatedStorage/Modules fallback
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
-- =========================

-- notify helper
local function note(title, text, dur)
  if _G and _G.__WOODZ_UTILS and type(_G.__WOODZ_UTILS.notify) == "function" then
    _G.__WOODZ_UTILS.notify(title, text, dur or 3)
  else
    print(string.format("[HUB NOTE] %s: %s", tostring(title), tostring(text)))
  end
end

-- modules
local farm         = r("farm")               -- your farm module (runAutoFarm, setupAutoAttackRemote, setSelected)
local serverHopper = r("server_hopper")      -- must expose hopToDifferentServer()

local M = {}

---------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------
M.levelThreshold       = 120     -- lobbies with anyone >= this level are "bad"
M.recheckInterval      = 4       -- seconds between loop iterations
M.postHopCooldown      = 7       -- wait after hop is triggered
M.maxFarmBurstSeconds  = 60      -- cap for a single farm burst
M.sahurModelName       = "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur" -- what your farm expects

-- get a player's level (tweak if your game stores it elsewhere)
local function getPlayerLevel(player)
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
local farmSetupDone = false

-- run a short burst of your hub's farm.runAutoFarm
local function safeFarmBurst()
  if not farm or type(farm.runAutoFarm) ~= "function" then
    if not warnedNoFarm then
      warnedNoFarm = true
      note("Sahur", "farm.runAutoFarm not found; skipping farm step.", 4)
    end
    return
  end

  -- one-time remote setup (your farm expects this)
  if not farmSetupDone and type(farm.setupAutoAttackRemote) == "function" then
    pcall(farm.setupAutoAttackRemote)
    farmSetupDone = true
  end

  -- ensure Sahur is the selected target so farm aims at it
  if type(farm.setSelected) == "function" and M.sahurModelName then
    pcall(function() farm.setSelected({ M.sahurModelName }) end)
  end

  local deadline = os.clock() + (M.maxFarmBurstSeconds or 60)
  local function keepRunning()
    return running and os.clock() < deadline
  end

  local ok, err = pcall(function()
    -- signature: farm.runAutoFarm(shouldContinueFn, setCurrentTargetFn?)
    farm.runAutoFarm(keepRunning, nil)
  end)
  if not ok then
    note("Sahur", "farm.runAutoFarm error: " .. tostring(err), 6)
  end
end

local function doHop(reason)
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
