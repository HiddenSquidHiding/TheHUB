-- sahur_hopper.lua
-- Auto-hops using server_hopper.hopToDifferentServer() when:
-- 1) lobby has anyone > level threshold (except you),
-- 2) Sahur model isn't present,
-- 3) Sahur dies (killed/removed).
-- Also farms Sahur between checks using your farm.runAutoFarm().

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------------
-- Robust require (mirrors app.lua _G.__WOODZ_REQUIRE fallback chain)
local function r(name)
  local hook = rawget(_G, "__WOODZ_REQUIRE")
  if type(hook) == "function" then
    local ok, mod = pcall(hook, name)
    if ok and mod then return mod end
  end
  local parent = script and script.Parent
  if parent and parent:FindFirstChild(name) then
    local ok, mod = pcall(require, parent[name])
    if ok and mod then return mod end
  end
  for _, folder in ipairs({ RS:FindFirstChild("Modules"), RS }) do
    if folder and folder:FindFirstChild(name) then
      local ok, mod = pcall(require, folder[name])
      if ok and mod then return mod end
    end
  end
  return nil
end
----------------------------------------------------------------------

local function note(title, text, dur)
  if _G and _G.__WOODZ_UTILS and type(_G.__WOODZ_UTILS.notify) == "function" then
    _G.__WOODZ_UTILS.notify(title, text, dur or 3)
  else
    print(string.format("[HUB NOTE] %s: %s", tostring(title), tostring(text)))
  end
end

-- Modules
local farm         = r("farm")               -- expects runAutoFarm, setupAutoAttackRemote, setSelected
local serverHopper = r("server_hopper")      -- expects hopToDifferentServer()

local M = {}

-- ===================== Config ======================
M.levelThreshold        = 84          -- hop if ANYONE > 84 (except you)
M.recheckInterval       = 3
M.postHopCooldown       = 6
M.maxFarmBurstSeconds   = 120
M.sahurModelName        = "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur"
M.maxCleanLobbyAttempts = 10          -- how many hop attempts to find a clean lobby
M.settleAfterHopSeconds = 2.5         -- let players list populate before re-check
M.debug                 = true        -- show lobby level reads in notifications

-- Optional: custom reader if your game stores level somewhere unique.
-- Set this to a function(player) -> number?
-- M.levelReader = function(player) ... end
-- ===================================================

-- ---------- Level helpers ----------
local function getPlayerLevel(player)
  -- 0) Custom hook (if provided)
  if type(M.levelReader) == "function" then
    local ok, n = pcall(M.levelReader, player)
    if ok and typeof(n) == "number" then return n end
  end

  -- 1) leaderstats (common)
  local ls = player:FindFirstChild("leaderstats")
  if ls then
    local cand = ls:FindFirstChild("Level") or ls:FindFirstChild("LV") or ls:FindFirstChild("Lvl") or ls:FindFirstChild("Rank")
    if cand then
      if cand:IsA("IntValue") or cand:IsA("NumberValue") then
        return cand.Value
      elseif cand:IsA("StringValue") then
        local n = tonumber((cand.Value or ""):match("%d+"))
        if n then return n end
      end
    end
    -- fallback: any number-like child under leaderstats
    for _, v in ipairs(ls:GetChildren()) do
      if v:IsA("IntValue") or v:IsA("NumberValue") then return v.Value end
      if v:IsA("StringValue") then
        local n = tonumber((v.Value or ""):match("%d+"))
        if n then return n end
      end
    end
  end

  -- 2) Attributes
  local a = player:GetAttribute("Level") or player:GetAttribute("level") or player:GetAttribute("Lvl")
  if typeof(a) == "number" then return a end
  if typeof(a) == "string" then
    local n = tonumber(a:match("%d+"))
    if n then return n end
  end

  -- 3) Common custom folders
  for _, folderName in ipairs({ "Stats", "Data", "Profile" }) do
    local f = player:FindFirstChild(folderName)
    if f then
      local k = f:FindFirstChild("Level") or f:FindFirstChild("Lvl") or f:FindFirstChild("Rank")
      if k then
        if k:IsA("IntValue") or k:IsA("NumberValue") then return k.Value end
        if k:IsA("StringValue") then
          local n = tonumber((k.Value or ""):match("%d+"))
          if n then return n end
        end
      end
    end
  end

  return nil -- unknown
end

local function lobbyHasHighLevel(threshold)
  threshold = threshold or M.levelThreshold
  local offenders, seen = {}, {}

  for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then
      local lv = getPlayerLevel(plr)
      table.insert(seen, { name = plr.Name, level = lv })
      if lv and lv > threshold then
        table.insert(offenders, { name = plr.Name, level = lv })
      end
    end
  end

  if M.debug then
    local parts = {}
    for _, s in ipairs(seen) do
      table.insert(parts, (s.name .. ":" .. tostring(s.level or "nil")))
    end
    note("Sahur-Debug", "Lobby levels → " .. table.concat(parts, ", "), 5)
  end

  return #offenders > 0, offenders
end
-- -----------------------------------

-- ---------- Sahur detection ----------
local function defaultFindSahur()
  -- exact name anywhere
  local m = workspace:FindFirstChild(M.sahurModelName, true)
  if m and m:IsA("Model") then return m end
  -- fuzzy contains
  for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("Model") then
      local n = string.lower(d.Name)
      if string.find(n, "sahur") or string.find(n, "sarur") then
        return d
      end
    end
  end
  return nil
end

local function findSahur()
  if type(M.sahurFinder) == "function" then
    local ok, model = pcall(M.sahurFinder)
    if ok and typeof(model) == "Instance" and model:IsA("Model") then return model end
  end
  return defaultFindSahur()
end
-- -------------------------------------

-- wait until Sahur dies/removed or timeout
local function waitForSahurDeath(timeoutSeconds)
  local deadline = os.clock() + (timeoutSeconds or 60)
  local target = findSahur()
  if not target then return false, "no target found" end

  local hum = target:FindFirstChildOfClass("Humanoid")
  local killed, gone = false, false

  local con1, con2
  if hum then
    con1 = hum.Died:Connect(function() killed = true end)
  end
  con2 = target.AncestryChanged:Connect(function(_, parent)
    if parent == nil then gone = true end
  end)

  while os.clock() < deadline and not killed and not gone do
    task.wait(0.25)
  end

  if con1 then con1:Disconnect() end
  if con2 then con2:Disconnect() end

  return killed or gone, (killed and "killed") or (gone and "removed") or "timeout"
end

-- ---------- Hop wrapper ----------
local function doHop(reason)
  if not serverHopper or type(serverHopper.hopToDifferentServer) ~= "function" then
    note("Sahur", "server_hopper module missing or invalid.", 5)
    return false
  end
  note("Sahur", "Hopping server" .. (reason and (" (" .. reason .. ")") or "") .. "...", 3)
  local ok, err = pcall(serverHopper.hopToDifferentServer)
  if not ok then
    note("Sahur", "Hop failed: " .. tostring(err), 6)
    return false
  end
  task.wait(M.postHopCooldown)
  return true
end
-- ----------------------------------

-- Ensure lobby is clean AND Sahur exists before farming.
local function ensureReadyLobby()
  for attempt = 1, (M.maxCleanLobbyAttempts or 8) do
    -- allow player list to populate after a join/hop
    task.wait(M.settleAfterHopSeconds or 2)

    local bad, offenders = lobbyHasHighLevel(M.levelThreshold)
    if bad then
      local parts = {}
      for _, o in ipairs(offenders) do
        table.insert(parts, o.name .. " (Lv " .. tostring(o.level) .. ")")
      end
      note("Sahur", "High-level present: " .. table.concat(parts, ", "), 4)
      doHop("high-level in lobby")
    else
      local target = findSahur()
      if not target then
        note("Sahur", "No Sahur model found in this server; hopping...", 3)
        doHop("Sahur missing")
      else
        -- clean lobby + sahur present = ready
        return true
      end
    end
  end
  note("Sahur", "Could not find a clean Sahur lobby after multiple tries.", 5)
  return false
end

-- ====== Farming burst + boss-death watch ======
local running = false
local warnedNoFarm = false
local farmSetupDone = false

local function safeFarmBurstAndWatch()
  -- Make sure Sahur is still present; if gone, hop.
  local target = findSahur()
  if not target then
    note("Sahur", "Sahur not present anymore; hopping...", 3)
    return true
  end

  -- aim at Sahur
  if type(farm) == "table" and type(farm.setSelected) == "function" and M.sahurModelName then
    pcall(function() farm.setSelected({ M.sahurModelName }) end)
  end

  -- one-time setup
  if not farmSetupDone and type(farm) == "table" and type(farm.setupAutoAttackRemote) == "function" then
    pcall(farm.setupAutoAttackRemote)
    farmSetupDone = true
  end

  local hopRequested = false
  task.spawn(function()
    local ok, why = waitForSahurDeath(M.maxFarmBurstSeconds or 60)
    if ok then
      hopRequested = true
      note("Sahur", "Boss " .. tostring(why) .. "; hopping...", 3)
    end
  end)

  local deadline = os.clock() + (M.maxFarmBurstSeconds or 60)
  if farm and type(farm.runAutoFarm) == "function" then
    local function shouldContinue()
      return running and not hopRequested and os.clock() < deadline
    end
    local ok, err = pcall(function() farm.runAutoFarm(shouldContinue, nil) end)
    if not ok and not warnedNoFarm then
      warnedNoFarm = true
      note("Sahur", "farm.runAutoFarm error: " .. tostring(err), 6)
    end
  else
    if not warnedNoFarm then
      warnedNoFarm = true
      note("Sahur", "farm.runAutoFarm not found; watching only.", 4)
    end
    while running and not hopRequested and os.clock() < deadline do
      task.wait(0.25)
    end
  end

  return hopRequested
end

-- ================= Main loop ==================
local function loop()
  while running do
    -- 0) HARD GUARANTEE: Only proceed if clean lobby + Sahur present
    if not ensureReadyLobby() then
      -- couldn't prepare; wait and try again
      task.wait(M.recheckInterval)
    else
      -- 1) Farm & watch; hop on death or if Sahur missing
      local shouldHop = safeFarmBurstAndWatch()
      if shouldHop then
        doHop("Sahur killed or missing")
        -- after hop, loop will re-run ensureReadyLobby()
      end
      task.wait(M.recheckInterval)
    end
  end
end
-- ==============================================

-- ================= Public API =================
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

function M.isRunning() return running end
function M.hopNow() doHop("manual") end

function M.configure(opts)
  if typeof(opts) ~= "table" then return end
  for k, v in pairs(opts) do
    if M[k] ~= nil then M[k] = v end
  end
end

return M
