-- sahur_hopper.lua
-- Farm Sahur and hop automatically using server_hopper.hopToDifferentServer()
-- Adds boss-death detection: hop right after Sahur dies.

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- -------- robust require (same as app.lua) ----------
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
-- ----------------------------------------------------

local function note(title, text, dur)
  if _G and _G.__WOODZ_UTILS and type(_G.__WOODZ_UTILS.notify) == "function" then
    _G.__WOODZ_UTILS.notify(title, text, dur or 3)
  else
    print(string.format("[HUB NOTE] %s: %s", tostring(title), tostring(text)))
  end
end

local farm         = r("farm")               -- expects runAutoFarm, setupAutoAttackRemote, setSelected
local serverHopper = r("server_hopper")      -- expects hopToDifferentServer()

local M = {}

-- ===================== Config ======================
M.levelThreshold       = 120
M.recheckInterval      = 3
M.postHopCooldown      = 6
M.maxFarmBurstSeconds  = 120     -- allow enough time for a kill
M.sahurModelName       = "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur"

-- Optional: override to find Sahur more reliably (return the Model)
-- function M.sahurFinder() return workspace:FindFirstChild("...") end
-- ===================================================

-- Find player level (adjust if your game stores differently)
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

-- ====== Sahur NPC detection & death watcher =======
local function defaultFindSahur()
  -- 1) exact name
  local m = workspace:FindFirstChild(M.sahurModelName, true)
  if m and m:IsA("Model") then return m end
  -- 2) fuzzy contains "Sahur"/"Sarur" as fallback
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

-- Wait until the current Sahur dies or the model disappears, or timeout
local function waitForSahurDeath(timeoutSeconds)
  local deadline = os.clock() + (timeoutSeconds or 60)
  local target = findSahur()
  if not target then return false, "no target found" end

  local hum = target:FindFirstChildOfClass("Humanoid")
  local killed = false
  local gone = false

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
-- ==================================================

-- ================= Main loop pieces ===============
local running = false
local warnedNoFarm = false
local farmSetupDone = false

local function safeFarmBurstAndWatch()
  -- No farm? skip; we'll still hop if watcher sees kill
  if not farm or type(farm.runAutoFarm) ~= "function" then
    if not warnedNoFarm then
      warnedNoFarm = true
      note("Sahur", "farm.runAutoFarm not found; skipping farm step.", 4)
    end
  end

  -- Set Sahur selection so the farm aims correctly
  if type(farm) == "table" and type(farm.setSelected) == "function" and M.sahurModelName then
    pcall(function() farm.setSelected({ M.sahurModelName }) end)
  end

  -- one-time remote setup
  if not farmSetupDone and type(farm) == "table" and type(farm.setupAutoAttackRemote) == "function" then
    pcall(farm.setupAutoAttackRemote)
    farmSetupDone = true
  end

  local hopRequested = false
  -- Start watcher waiting for Sahur to die or vanish
  local watcher = task.spawn(function()
    local ok, why = waitForSahurDeath(M.maxFarmBurstSeconds or 60)
    if ok then
      hopRequested = true
      note("Sahur", "Boss " .. tostring(why) .. "; hopping...", 3)
    end
  end)

  -- Run the farm burst in parallel (if present)
  local deadline = os.clock() + (M.maxFarmBurstSeconds or 60)
  if farm and type(farm.runAutoFarm) == "function" then
    local function shouldContinue()
      return running and not hopRequested and os.clock() < deadline
    end
    pcall(function() farm.runAutoFarm(shouldContinue, nil) end)
  else
    -- No farm loop: just idle while watcher waits
    while running and not hopRequested and os.clock() < deadline do
      task.wait(0.25)
    end
  end

  -- If watcher asked for hop, do it now
  if hopRequested then
    return true
  end
  return false
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
    -- If lobby is bad, hop immediately
    local bad, why = M.isBadLobby()
    if bad then
      doHop(why)
      task.wait(M.recheckInterval)
      continue
    end

    -- Otherwise, farm & watch boss; hop when dead
    local shouldHop = safeFarmBurstAndWatch()
    if shouldHop then
      doHop("Sahur killed")
    end

    task.wait(M.recheckInterval)
  end
end
-- ================================================

-- ================= Public API ====================
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
