-- farm.lua
-- Auto-farm with smooth constraint-based follow (no glide, no judder).
-- Uses data from data_monsters.lua (Weather / To Sahur / Forced) loaded via HTTP or preloaded global.
-- Features:
--  • Weather preemption with TTK (≤ 5s) — switch mid-fight if quick to kill.
--  • FastLevel mode — ignores 3s stall rule.
--  • Death recovery — on death, respawn and teleport right back to the same mob.

-- 🔧 Utils
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[farm.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading farm.lua")
end

local utils = getUtils()

-- ⚠️ data_monsters.lua loader (no ModuleScript require; executor-friendly)
-- It will first use _G.WOODZ_DATA_MONSTERS if your init preloaded it,
-- otherwise it fetches https://.../data_monsters.lua using _G.WOODZ_BASE_URL
local data
do
  if _G.WOODZ_DATA_MONSTERS and type(_G.WOODZ_DATA_MONSTERS) == "table" then
    data = _G.WOODZ_DATA_MONSTERS
  end

  if not data then
    local base = _G.WOODZ_BASE_URL
    if type(base) == "string" and #base > 0 then
      local ok, src = pcall(function()
        return game:HttpGet((base:sub(-1) == "/" and base or (base .. "/")) .. "data_monsters.lua")
      end)
      if ok and type(src) == "string" and #src > 0 then
        local chunk, err = loadstring(src, "=data_monsters.lua")
        if chunk then
          local ok2, ret = pcall(chunk)
          if ok2 and type(ret) == "table" then
            data = ret
            _G.WOODZ_DATA_MONSTERS = data -- cache globally
          else
            error("[farm.lua] evaluating data_monsters.lua failed: " .. tostring(ret))
          end
        else
          error("[farm.lua] loadstring(data_monsters.lua) failed: " .. tostring(err))
        end
      else
        error("[farm.lua] HttpGet data_monsters.lua failed (check _G.WOODZ_BASE_URL)")
      end
    else
      error("[farm.lua] _G.WOODZ_BASE_URL missing; cannot fetch data_monsters.lua")
    end
  end
end

assert(
  data and type(data.weatherEventModels) == "table" and type(data.toSahurModels) == "table",
  "[farm.lua] data_monsters.lua missing or invalid (weather/toSahur lists required)"
)

-- Services
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

local M = {}

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local WEATHER_TIMEOUT               = 30    -- seconds (Weather Events only)
local NON_WEATHER_STALL_TIMEOUT     = 3     -- seconds without HP decreasing → skip (disabled in FastLevel)
local ABOVE_OFFSET                  = Vector3.new(0, 20, 0)

-- Weather preemption config
local WEATHER_TTK_LIMIT             = 5.0   -- seconds — only switch if estimated TTK ≤ this
local WEATHER_PROBE_TIME            = 0.35  -- seconds to sample DPS on a weather mob (quick)
local WEATHER_PREEMPT_POLL          = 0.2   -- seconds between preemption checks during a fight

-- Constraint tuning
local POS_RESPONSIVENESS            = 200
local POS_MAX_FORCE                 = 1e9
local ORI_RESPONSIVENESS            = 200
local ORI_MAX_TORQUE                = 1e9

----------------------------------------------------------------------
-- Selection/filter
----------------------------------------------------------------------
local allMonsterModels = {}
local filteredMonsterModels = {}
local selectedMonsterModels = { "Weather Events" }

local WEATHER_NAMES = data.weatherEventModels or {}
local SAHUR_NAMES   = data.toSahurModels     or {}

local function isWeatherName(name)
  local lname = string.lower(name or "")
  for _, w in ipairs(WEATHER_NAMES) do
    if lname == string.lower(w) then return true end
  end
  return false
end

local function isSahurName(name)
  local lname = string.lower(name or "")
  for _, s in ipairs(SAHUR_NAMES) do
    if lname == string.lower(s) then return true end
  end
  return false
end

-- 🔸 Weather helpers
local function isWeatherSelected()
  return table.find(selectedMonsterModels, "Weather Events") ~= nil
end

local function findWeatherEnemies()
  if not isWeatherSelected() then return {} end
  local out = {}
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 and isWeatherName(node.Name) then
        table.insert(out, node)
      end
    end
  end
  return out
end

local function pickLowestHPWeather()
  local list = findWeatherEnemies()
  local best, bestHP = nil, math.huge
  for _, m in ipairs(list) do
    local h = m:FindFirstChildOfClass("Humanoid")
    if h and h.Health > 0 and h.Health < bestHP then
      best, bestHP = m, h.Health
    end
  end
  return best
end

-- 🔸 FastLevel mode flag (set from app/fastlevel toggle)
local FASTLEVEL_MODE = false
function M.setFastLevelEnabled(on)
  FASTLEVEL_MODE = on and true or false
end

function M.getSelected() return selectedMonsterModels end
function M.setSelected(list)
  selectedMonsterModels = {}
  for _, n in ipairs(list or {}) do table.insert(selectedMonsterModels, n) end
end
function M.toggleSelect(name)
  local i = table.find(selectedMonsterModels, name)
  if i then table.remove(selectedMonsterModels, i)
  else table.insert(selectedMonsterModels, name) end
end
function M.isSelected(name)
  return table.find(selectedMonsterModels, name) ~= nil
end

----------------------------------------------------------------------
-- Monster discovery / filtering
----------------------------------------------------------------------
local function pushUnique(valid, name)
  if not name then return end
  for _, v in ipairs(valid) do if v == name then return end end
  for _, s in ipairs(SAHUR_NAMES)   do if s == name then return end end
  for _, w in ipairs(WEATHER_NAMES) do if w == name then return end end
  table.insert(valid, name)
end

function M.getMonsterModels()
  local valid = {}
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local hum = node:FindFirstChildOfClass("Humanoid")
      if hum and hum.Health > 0 then
        pushUnique(valid, node.Name)
      end
    end
  end

  if data and data.forcedMonsters then
    for _, nm in ipairs(data.forcedMonsters) do pushUnique(valid, nm) end
  end

  table.insert(valid, "To Sahur")
  table.insert(valid, "Weather Events")

  table.sort(valid)
  allMonsterModels = valid
  filteredMonsterModels = table.clone(valid)
  return valid
end

function M.filterMonsterModels(search)
  local text = tostring(search or ""):lower()
  if text == "" then
    filteredMonsterModels = table.clone(allMonsterModels)
    return filteredMonsterModels
  end

  local out = {}
  for _, v in ipairs(allMonsterModels) do
    if v:lower():find(text, 1, true) then
      table.insert(out, v)
    end
  end
  filteredMonsterModels = out
  return out
end

----------------------------------------------------------------------
-- Auto-attack remote setup
----------------------------------------------------------------------
local autoAttackRemote
function M.setupAutoAttackRemote()
  local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
  if not remotes then
    utils.notify("🌲 Auto-Farm", "Remotes folder not found.", 5)
    return
  end
  autoAttackRemote = remotes:WaitForChild("RequestAttack", 5)
  if not autoAttackRemote then
    utils.notify("🌲 Auto-Farm", "RequestAttack RemoteFunction not found.", 5)
  end
end

----------------------------------------------------------------------
-- Teleport / velocity helpers
----------------------------------------------------------------------
local function hardTeleport(cf)
  local character = player.Character
  if not character then return end
  local hrp = character:FindFirstChild("HumanoidRootPart")
  if hrp then
    hrp.CFrame = cf
  end
end

local function zeroVel(part)
  if part and part:IsA("BasePart") then
    part.Velocity = Vector3.new()
    part.RotVelocity = Vector3.new()
    part.AssemblyLinearVelocity = Vector3.new()
    part.AssemblyAngularVelocity = Vector3.new()
  end
end

local function isValidCFrame(cf)
  return cf and cf:IsA("CFrame") and cf.Position.Magnitude < math.huge
end

local function findBasePart(model)
  local part = model:FindFirstChild("HumanoidRootPart")
  if part then return part end
  for _, p in ipairs(model:GetChildren()) do
    if p:IsA("BasePart") then return p end
  end
  return nil
end

----------------------------------------------------------------------
-- Smooth follow constraint maker
----------------------------------------------------------------------
local function makeSmoothFollow(targetPart)
  local character = player.Character
  if not character or not targetPart then return nil end
  local hrp = character:FindFirstChild("HumanoidRootPart")
  if not hrp then return nil end

  local att0 = Instance.new("Attachment")
  att0.Parent = hrp
  local att1 = Instance.new("Attachment")
  att1.Parent = targetPart  -- wait, no: for follow, att1 on a dummy or something? Wait, standard is AlignPosition + AlignOrientation between two attachments.

  -- For player follow: Attachment on HRP, and a dummy target attachment that we update.
  local dummyAtt = Instance.new("Attachment")
  dummyAtt.Parent = hrp.Parent  -- in character

  local posConstraint = Instance.new("AlignPosition")
  posConstraint.Attachment0 = att0
  posConstraint.Attachment1 = dummyAtt
  posConstraint.RigidityEnabled = false
  posConstraint.MaxForce = POS_MAX_FORCE
  posConstraint.Responsiveness = POS_RESPONSIVENESS
  posConstraint.Parent = hrp

  local oriConstraint = Instance.new("AlignOrientation")
  oriConstraint.Attachment0 = att0
  oriConstraint.Attachment1 = dummyAtt
  oriConstraint.RigidityEnabled = false
  oriConstraint.MaxTorque = ORI_MAX_TORQUE
  oriConstraint.Responsiveness = ORI_RESPONSIVENESS
  oriConstraint.Parent = hrp

  local function setGoal(cf)
    if dummyAtt and isValidCFrame(cf) then
      dummyAtt.CFrame = cf
    end
  end

  local function destroy()
    pcall(function()
      posConstraint:Destroy()
      oriConstraint:Destroy()
      att0:Destroy()
      dummyAtt:Destroy()
    end)
  end

  return { setGoal = setGoal, destroy = destroy }
end

----------------------------------------------------------------------
-- TTK estimator (probe DPS briefly)
----------------------------------------------------------------------
local function estimateTTK(enemy, probeTime)
  local hum = enemy:FindFirstChildOfClass("Humanoid")
  if not hum or hum.Health <= 0 then return math.huge end
  local part = enemy:FindFirstChild("HumanoidRootPart") or findBasePart(enemy)
  if not part or not autoAttackRemote then return math.huge end

  local h0 = hum.Health
  local t0 = tick()
  local tEnd = t0 + (probeTime or WEATHER_PROBE_TIME)

  while tick() < tEnd and enemy.Parent and hum.Health > 0 do
    pcall(function() autoAttackRemote:InvokeServer(part.CFrame) end)
    RunService.Heartbeat:Wait()
  end

  local elapsed = math.max(0.05, tick() - t0)
  local h1 = hum.Health
  local dps = (h0 - h1) / elapsed
  if dps <= 0 then return math.huge end

  local ttk = h1 / dps
  return ttk
end

----------------------------------------------------------------------
-- Engagement (enter/restore) helpers
----------------------------------------------------------------------
local function calcHoverCF(enemy)
  local part = enemy:FindFirstChild("HumanoidRootPart") or findBasePart(enemy)
  if part then return part.CFrame * CFrame.new(ABOVE_OFFSET) end
  local okPivot, pcf = pcall(function() return enemy:GetPivot() end)
  return (okPivot and isValidCFrame(pcf)) and (pcf * CFrame.new(ABOVE_OFFSET)) or nil
end

local function beginEngagement(enemy)
  local targetCF = calcHoverCF(enemy)
  if not targetCF then return nil, nil, nil end
  hardTeleport(targetCF)

  local character = player.Character
  local hum = character and character:FindFirstChildOfClass("Humanoid")
  local hrp = character and character:FindFirstChild("HumanoidRootPart")
  if not character or not hum or not hrp then return nil, nil, nil end

  local oldPS = hum.PlatformStand
  hum.PlatformStand = true
  zeroVel(hrp)
  local ctl = makeSmoothFollow(hrp)
  return ctl, hum, oldPS
end

----------------------------------------------------------------------
-- Public: run auto farm
----------------------------------------------------------------------
function M.runAutoFarm(flagGetter, setTargetText)
  if not autoAttackRemote then
    utils.notify("🌲 Auto-Farm", "RequestAttack RemoteFunction not found.", 5)
    return
  end

  local function label(text)
    if setTargetText then setTargetText(text) end
  end

  -- Initial scan for enemies
  local function refreshEnemyList()
    local enemies = {}
    for _, name in ipairs(selectedMonsterModels) do
      if name == "Weather Events" then
        local we = findWeatherEnemies()
        for _, e in ipairs(we) do table.insert(enemies, e) end
      elseif name == "To Sahur" then
        for _, node in ipairs(Workspace:GetDescendants()) do
          if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
            local h = node:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 and isSahurName(node.Name) then
              table.insert(enemies, node)
            end
          end
        end
      else
        -- Regular monster by name
        for _, node in ipairs(Workspace:GetDescendants()) do
          if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) and node.Name == name then
            local h = node:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
              table.insert(enemies, node)
            end
          end
        end
      end
    end
    -- Prioritize lowest HP
    table.sort(enemies, function(a, b)
      local ha = (a:FindFirstChildOfClass("Humanoid") and a:FindFirstChildOfClass("Humanoid").Health) or math.huge
      local hb = (b:FindFirstChildOfClass("Humanoid") and b:FindFirstChildOfClass("Humanoid").Health) or math.huge
      return ha < hb
    end)
    return enemies
  end

  while flagGetter() do
    local character = utils.waitForCharacter()
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
      label("Current Target: None")
      task.wait(0.05)
      goto continue
    end

    local enemies = refreshEnemyList()
    if #enemies == 0 then
      label("Current Target: None")
      task.wait(0.1)
      goto continue
    end

    for _, enemy in ipairs(enemies) do
      if not flagGetter() then break end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then goto nextEnemy end

      local eh = enemy:FindFirstChildOfClass("Humanoid")
      if not eh or eh.Health <= 0 then goto nextEnemy end

      -- enter engagement (teleport + constraints)
      local ctl, humSelf, oldPS = beginEngagement(enemy)
      if not ctl then goto nextEnemy end

      label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

      -- timers/state
      local isWeather   = isWeatherName(enemy.Name)
      local lastHealth  = eh.Health
      local lastDropAt  = tick()
      local startedAt   = tick()

      local hcConn = eh.HealthChanged:Connect(function(h)
        label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
        if h < lastHealth then lastDropAt = tick() end
        lastHealth = h
      end)

      -- attack loop (with weather preemption + FastLevel stall override + death recovery)
      local lastWeatherPoll = 0

      while flagGetter() and enemy.Parent and eh.Health > 0 do
        -- death recovery: if we died or HRP missing, respawn + return to same enemy
        local ch = player.Character
        local myHum = ch and ch:FindFirstChildOfClass("Humanoid")
        local myHRP = ch and ch:FindFirstChild("HumanoidRootPart")

        if (not ch) or (not myHum) or (myHum.Health <= 0) or (not myHRP) then
          if ctl then pcall(function() ctl:destroy() end) end
          label(("Respawning… returning to %s"):format(enemy.Name))
          local newChar = utils.waitForCharacter()
          if not enemy.Parent or eh.Health <= 0 then break end
          ctl, humSelf, oldPS = beginEngagement(enemy)
          if not ctl then break end
        end

        -- normal follow/attack
        local partNow = findBasePart(enemy)
        if not partNow then
          local t0 = tick()
          repeat
            RunService.Heartbeat:Wait()
            partNow = findBasePart(enemy)
          until partNow or (tick() - t0) > 1 or not enemy.Parent or eh.Health <= 0
          if not partNow then break end
        end

        local desired = partNow.CFrame * CFrame.new(ABOVE_OFFSET)
        ctl:setGoal(desired)

        local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
        if hrpTarget and autoAttackRemote then
          pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
        end

        local now = tick()

        -- Weather timeout (always applies for weather)
        if isWeather and (now - startedAt) > WEATHER_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Weather Event timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT), 3)
          break
        end

        -- Stall detection (disabled in FastLevel mode for non-weather)
        if (not isWeather) and (not FASTLEVEL_MODE) and ((now - lastDropAt) > NON_WEATHER_STALL_TIMEOUT) then
          utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(enemy.Name, NON_WEATHER_STALL_TIMEOUT), 3)
          break
        end

        -- Weather preemption with TTK (only if not already on weather)
        if not isWeather and (now - lastWeatherPoll) >= WEATHER_PREEMPT_POLL and isWeatherSelected() then
          lastWeatherPoll = now
          local candidate = pickLowestHPWeather()
          if candidate and candidate ~= enemy then
            local ttk = estimateTTK(candidate, WEATHER_PROBE_TIME)
            if ttk <= WEATHER_TTK_LIMIT then
              utils.notify("🌲 Auto-Farm", ("Weather target detected (TTK≈%0.1fs) — switching."):format(ttk), 2)
              break
            end
          end
        end

        RunService.Heartbeat:Wait()
      end

      if hcConn then hcConn:Disconnect() end
      label("Current Target: None")

      -- cleanup + restore
      if ctl then pcall(function() ctl:destroy() end) end
      local curChar = player.Character
      local curHum  = curChar and curChar:FindFirstChildOfClass("Humanoid")
      local curHRP  = curChar and curChar:FindFirstChild("HumanoidRootPart")
      if curHum and curHRP and curHum.Parent then
        curHum.PlatformStand = false
        zeroVel(curHRP)
      end

      ::nextEnemy::

      RunService.Heartbeat:Wait()
    end

    ::continue::

    RunService.Heartbeat:Wait()
  end
end

return M
