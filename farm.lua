-- farm.lua — AutoFarm + Instant Level 70+ behavior
-- - Teleports back to the target after death when FastLevel is enabled
-- - Restores movement after the target is killed/despawns
-- - Minimal, executor-friendly, no assumptions about remotes

local Players       = game:GetService("Players")
local RS            = game:GetService("ReplicatedStorage")
local TweenService  = game:GetService("TweenService")
local RunService    = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local M = {}

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local selectedTargets = {}            -- { "TargetName", ... }
local fastLevelEnabled = false        -- toggled by app.lua setFastLevelEnabled(true/false)
local savedMovement = nil             -- {WalkSpeed, JumpPower, AutoRotate}
local movementLocked = false
local playerConns = {}                -- character/respawn watchers
local targetConns = {}                -- target death watchers
local attackLoopConn = nil

---------------------------------------------------------------------
-- Utils
---------------------------------------------------------------------
local function note(title, text, dur)
  local ok, utils = pcall(function() return _G.__WOODZ_UTILS end)
  if ok and utils and type(utils.notify) == "function" then
    utils.notify(title, text, dur or 3)
  else
    print(string.format("[FARM] %s: %s", tostring(title), tostring(text)))
  end
end

local function getCharacter()
  return LocalPlayer and LocalPlayer.Character
end

local function getHRP()
  local ch = getCharacter()
  return ch and ch:FindFirstChild("HumanoidRootPart") or nil
end

local function getHumanoid()
  local ch = getCharacter()
  return ch and ch:FindFirstChildOfClass("Humanoid") or nil
end

local function disconnectAll(list)
  for _, c in ipairs(list) do
    if c and typeof(c) == "RBXScriptConnection" then
      pcall(function() c:Disconnect() end)
    end
  end
  table.clear(list)
end

---------------------------------------------------------------------
-- Movement lock / restore  (FASTLEVEL / MOVEMENT)
---------------------------------------------------------------------
local function lockMovement()
  if movementLocked then return end
  local hum = getHumanoid()
  if not hum then return end
  savedMovement = {
    WalkSpeed  = hum.WalkSpeed,
    JumpPower  = (hum:FindFirstChild("JumpPower") and hum.JumpPower) or 50,
    AutoRotate = hum.AutoRotate,
  }
  hum.WalkSpeed  = 0
  if hum:FindFirstChild("JumpPower") then
    hum.JumpPower  = 0
  end
  hum.AutoRotate = false
  movementLocked = true
end

local function restoreMovement()
  if not movementLocked then return end
  movementLocked = false
  local hum = getHumanoid()
  if not hum then return end
  if savedMovement then
    hum.WalkSpeed  = savedMovement.WalkSpeed or 16
    if hum:FindFirstChild("JumpPower") then
      hum.JumpPower  = savedMovement.JumpPower or 50
    end
    hum.AutoRotate = (savedMovement.AutoRotate ~= nil) and savedMovement.AutoRotate or true
  else
    hum.WalkSpeed  = 16
    if hum:FindFirstChild("JumpPower") then
      hum.JumpPower  = 50
    end
    hum.AutoRotate = true
  end
  savedMovement = nil
end

---------------------------------------------------------------------
-- Target finding
---------------------------------------------------------------------
local function currentTargetName()
  return selectedTargets[1]
end

local function findTargetModelByName(name)
  if not name or name == "" then return nil end
  -- exact, anywhere
  local m = workspace:FindFirstChild(name, true)
  if m and m:IsA("Model") then return m end
  -- fuzzy contains
  local ln = string.lower(name)
  for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("Model") then
      local dn = string.lower(d.Name)
      if string.find(dn, ln, 1, true) then
        return d
      end
    end
  end
  return nil
end

local function findTargetModel()
  local nm = currentTargetName()
  if not nm then return nil end
  return findTargetModelByName(nm)
end

---------------------------------------------------------------------
-- Teleport / move-to helpers
---------------------------------------------------------------------
local function tpToCFrame(cf)
  local hrp = getHRP()
  if not hrp then return false end
  local ok, err = pcall(function()
    hrp.CFrame = cf
  end)
  return ok
end

local function tweenToPosition(pos, timeSec)
  local hrp = getHRP()
  if not hrp then return false end
  local root = hrp
  local tween = TweenService:Create(root, TweenInfo.new(timeSec or 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = CFrame.new(pos) })
  tween:Play()
  tween.Completed:Wait()
  return true
end

local function tpNearTarget(model)
  if not model then return false end
  local pivot = (model.GetPivot and model:GetPivot()) or model.PrimaryPart and model.PrimaryPart.CFrame or nil
  if not pivot then
    -- fallback: center of model bounds
    local cf = model:GetBoundingBox()
    pivot = cf
  end
  if not pivot then return false end
  -- offset back a little so we're not inside the model
  local targetCF = pivot * CFrame.new(0, 0, 6)
  return tpToCFrame(targetCF)
end

---------------------------------------------------------------------
-- Watchers: target death & player death (FASTLEVEL)
---------------------------------------------------------------------
local function connectTargetDeath(model, onGone)
  disconnectAll(targetConns)
  if not model then return end
  -- model removed from workspace
  table.insert(targetConns, model.AncestryChanged:Connect(function(_, parent)
    if parent == nil then
      onGone("removed")
    end
  end))
  -- humanoid died
  local hum = model:FindFirstChildOfClass("Humanoid")
  if hum then
    table.insert(targetConns, hum.Died:Connect(function()
      onGone("killed")
    end))
  end
end

local function ensureRespawnTeleport()
  -- when FastLevel is ON: after death/respawn, tp right back to target
  disconnectAll(playerConns)
  table.insert(playerConns, LocalPlayer.CharacterAdded:Connect(function(ch)
    -- wait for HRP
    ch:WaitForChild("HumanoidRootPart", 10)
    task.wait(0.1)
    local model = findTargetModel()
    if model then
      tpNearTarget(model)
      lockMovement() -- keep you in place to resume attack
    end
  end))
  local hum = getHumanoid()
  if hum then
    table.insert(playerConns, hum.Died:Connect(function()
      -- nothing to do here; CharacterAdded handler will TP on spawn
    end))
  end
end

---------------------------------------------------------------------
-- Public API expected by app.lua
---------------------------------------------------------------------
function M.getMonsterModels() -- used for the picker
  -- If you already have a real pool, return that instead.
  -- This generic default scrapes a few model names that look enemy-like.
  local names, seen = {}, {}
  for _, inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("Model") then
      local n = inst.Name
      if n and #n >= 3 then
        local ln = string.lower(n)
        if (string.find(ln, "boss") or string.find(ln, "mob") or string.find(ln, "sahur") or string.find(ln, "sarur"))
        and not seen[n] then
          table.insert(names, n)
          seen[n] = true
        end
      end
    end
  end
  table.sort(names)
  return names
end

function M.getSelected()
  return table.clone(selectedTargets)
end

function M.setSelected(list)
  selectedTargets = {}
  if type(list) == "table" then
    for _, v in ipairs(list) do
      if typeof(v) == "string" and #v > 0 then
        table.insert(selectedTargets, v)
      end
    end
  end
  if #selectedTargets > 0 then
    note("Farm", "Target set: " .. selectedTargets[1], 2)
  end
end

function M.setFastLevelEnabled(on)
  fastLevelEnabled = on and true or false
  if fastLevelEnabled then
    note("FastLevel", "Instant Level 70+ ENABLED — will auto-TP back after death.", 3)
    ensureRespawnTeleport()
    -- lock now so you don't drift when we start
    lockMovement()
  else
    note("FastLevel", "Instant Level 70+ DISABLED.", 3)
    disconnectAll(playerConns)
    restoreMovement()
  end
end

-- If your game needs a specific remote to “prime” auto attack, wire it here.
function M.setupAutoAttackRemote()
  -- no-op placeholder; keep for compatibility
end

---------------------------------------------------------------------
-- Attack action (replace this if you have a specific hit remote)
---------------------------------------------------------------------
local function genericAttackTick(targetModel)
  -- If you have a Knit/Remote, call it here.
  -- This noop keeps the loop running without assumptions.
  -- Example (pseudo):
  -- local remote = RS:WaitForChild("Remotes"):WaitForChild("Attack")
  -- remote:FireServer(targetModel)
end

---------------------------------------------------------------------
-- Main AutoFarm loop
---------------------------------------------------------------------
function M.runAutoFarm(shouldContinue, setCurrentTargetFn)
  shouldContinue = shouldContinue or function() return true end

  -- soft attack loop runner
  local function attackLoop(targetModel)
    -- stand near & “attack”
    tpNearTarget(targetModel)
    lockMovement()

    local start = os.clock()
    local lastPing = 0

    while shouldContinue() do
      -- current target may have despawned
      if not targetModel or not targetModel.Parent then break end

      -- keep UI label updated
      if setCurrentTargetFn and (os.clock() - lastPing > 0.25) then
        lastPing = os.clock()
        pcall(setCurrentTargetFn, "Current Target: " .. targetModel.Name)
      end

      -- do a tick of attack
      genericAttackTick(targetModel)

      -- stay very close
      local hrp = getHRP()
      if hrp then
        local pivot = (targetModel.GetPivot and targetModel:GetPivot()) or (targetModel.PrimaryPart and targetModel.PrimaryPart.CFrame)
        if pivot then
          local dist = (hrp.Position - pivot.Position).Magnitude
          if dist > 9 then
            tpNearTarget(targetModel)
          end
        end
      end

      RunService.Heartbeat:Wait()
    end
  end

  while shouldContinue() do
    local targetName = currentTargetName()
    if not targetName then
      task.wait(0.25)
      continue
    end

    local model = findTargetModel()
    if not model then
      -- no model right now; free player if fastlevel isn’t forcing a lock
      restoreMovement()
      task.wait(0.25)
      continue
    end

    -- Watch for target death/despawn to restore movement (IMPORTANT)
    connectTargetDeath(model, function(reason)
      -- Reason "killed"/"removed" → free player so they can move
      restoreMovement()
    end)

    -- If FastLevel is ON, ensure we auto-TP back on respawn
    if fastLevelEnabled then
      ensureRespawnTeleport()
    end

    -- Run the attack loop until shouldContinue() fails or model is gone
    attackLoop(model)

    -- After a cycle, in case we were locked:
    restoreMovement()

    -- small pause before next iteration to prevent tight spin
    task.wait(0.1)
  end

  -- safety cleanup
  disconnectAll(targetConns)
  if not fastLevelEnabled then
    disconnectAll(playerConns)
  end
  restoreMovement()
end

return M
