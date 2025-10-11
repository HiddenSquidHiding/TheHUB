-- farm.lua
-- Auto-farm with smooth constraint-based follow (no glide, no judder).
-- Uses local data from data_monsters.lua (Weather / To Sahur / Forced).
-- Weather Events: 30s timeout. Non-weather: skip if HP doesn't drop for 3s.
-- 🔸 Weather preemption: if "Weather Events" is selected, immediately switch
-- to a weather mob the moment one appears, even if you're mid-fight.

-- 🔧 Utils + data
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[farm.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading farm.lua")
end

local utils  = getUtils()
local data   = require(script.Parent.data_monsters) -- <-- using your local data

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
local WEATHER_TIMEOUT               = 30   -- seconds (Weather Events only)
local NON_WEATHER_STALL_TIMEOUT     = 3    -- seconds without HP decreasing → skip
local ABOVE_OFFSET                  = Vector3.new(0, 20, 0)

-- Constraint tuning (adjust if you ever want snappier/slower follow)
local POS_RESPONSIVENESS            = 200     -- higher = snappier
local POS_MAX_FORCE                 = 1e9     -- plenty
local ORI_RESPONSIVENESS            = 200
local ORI_MAX_TORQUE                = 1e9

----------------------------------------------------------------------
-- Selection/filter
----------------------------------------------------------------------
local allMonsterModels = {}
local filteredMonsterModels = {}
local selectedMonsterModels = { "Weather Events" }

local WEATHER_NAMES = (data and data.weatherEventModels) or {}
local SAHUR_NAMES   = (data and data.toSahurModels)     or {}

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

-- 🔸 Weather preemption helpers
local function isWeatherSelected()
  return table.find(selectedMonsterModels, "Weather Events") ~= nil
end

local function anyAliveWeather()
  if not isWeatherSelected() then return false end
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 and isWeatherName(node.Name) then
        return true
      end
    end
  end
  return false
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

  -- include any locally forced names from data
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

function M.getFiltered()
  return filteredMonsterModels
end

function M.filterMonsterModels(text)
  text = tostring(text or ""):lower()
  local filtered = {}
  local function matchesAny(list)
    for _, n in ipairs(list) do
      if string.find(n:lower(), text, 1, true) then return true end
    end
    return false
  end

  if text == "" then
    filtered = allMonsterModels
  else
    for _, model in ipairs(allMonsterModels) do
      if model == "Weather Events" then
        if matchesAny(WEATHER_NAMES) then table.insert(filtered, model) end
      elseif model == "To Sahur" then
        if matchesAny(SAHUR_NAMES) then table.insert(filtered, model) end
      elseif string.find(model:lower(), text, 1, true) then
        table.insert(filtered, model)
      end
    end
  end

  table.sort(filtered)
  if #filtered == 0 then
    utils.notify("🌲 Search", "No models found; showing all.", 3)
    filtered = allMonsterModels
  end
  filteredMonsterModels = filtered
  return filtered
end

----------------------------------------------------------------------
-- Enemy prioritization
----------------------------------------------------------------------
local function refreshEnemyList()
  local wantWeather = table.find(selectedMonsterModels, "Weather Events") ~= nil
  local wantSahur   = table.find(selectedMonsterModels, "To Sahur") ~= nil

  local explicitSet = {}
  for _, n in ipairs(selectedMonsterModels) do
    if n ~= "Weather Events" and n ~= "To Sahur" then explicitSet[n:lower()] = true end
  end

  local weather, explicit, sahur = {}, {}, {}
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 then
        local lname = node.Name:lower()
        if wantWeather and isWeatherName(lname) then
          table.insert(weather, node)
        elseif explicitSet[lname] then
          table.insert(explicit, node)
        elseif wantSahur and isSahurName(lname) then
          table.insert(sahur, node)
        end
      end
    end
  end

  local out = {}
  for _, e in ipairs(weather)  do table.insert(out, e) end
  for _, e in ipairs(explicit) do table.insert(out, e) end
  for _, e in ipairs(sahur)    do table.insert(out, e) end
  return out
end

----------------------------------------------------------------------
-- Remote
----------------------------------------------------------------------
local autoAttackRemote = nil
function M.setupAutoAttackRemote()
  autoAttackRemote = nil
  local ok, remote = pcall(function()
    return ReplicatedStorage:WaitForChild("Packages")
      :WaitForChild("Knit")
      :WaitForChild("Services")
      :WaitForChild("MonsterService")
      :WaitForChild("RF")
      :WaitForChild("RequestAttack")
  end)
  if ok and remote and remote:IsA("RemoteFunction") then
    autoAttackRemote = remote
    utils.notify("🌲 Auto Attack", "RequestAttack ready.", 3)
  else
    utils.notify("🌲 Auto Attack", "RequestAttack NOT found; farming may fail.", 5)
  end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function isValidCFrame(cf)
  if not cf then return false end
  local p = cf.Position
  return p.X == p.X and p.Y == p.Y and p.Z == p.Z
     and math.abs(p.X) < 10000 and math.abs(p.Y) < 10000 and math.abs(p.Z) < 10000
end

local function findBasePart(model)
  if not model then return nil end
  local names = { "HumanoidRootPart","PrimaryPart","Body","Hitbox","Root","Main" }
  for _, n in ipairs(names) do
    local part = model:FindFirstChild(n)
    if part and part:IsA("BasePart") then return part end
  end
  for _, d in ipairs(model:GetDescendants()) do
    if d:IsA("BasePart") then return d end
  end
  return nil
end

local function zeroVel(hrp)
  pcall(function()
    hrp.AssemblyLinearVelocity  = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
  end)
end

-- Single, glide-free hop with replication
local function hardTeleport(cf)
  local char = player.Character
  if not char then return end
  local hum = char:FindFirstChildOfClass("Humanoid")
  local hrp = char:FindFirstChild("HumanoidRootPart")
  if not hum or not hrp then return end
  zeroVel(hrp)
  local oldPS = hum.PlatformStand
  hum.PlatformStand = true
  char:PivotTo(cf)
  RunService.Heartbeat:Wait()
  hum.PlatformStand = oldPS
end

----------------------------------------------------------------------
-- Smooth follow via constraints (created once per fight, cleaned each time)
----------------------------------------------------------------------
local function makeSmoothFollow(hrp)
  -- attachments
  local a0 = Instance.new("Attachment")
  a0.Name = "WoodzHub_A0"
  a0.Parent = hrp

  -- AlignPosition
  local ap = Instance.new("AlignPosition")
  ap.Name = "WoodzHub_AP"
  ap.Mode = Enum.PositionAlignmentMode.OneAttachment
  ap.Attachment0 = a0
  ap.ApplyAtCenterOfMass = true
  ap.MaxForce = POS_MAX_FORCE
  ap.Responsiveness = POS_RESPONSIVENESS
  ap.RigidityEnabled = false
  ap.Parent = hrp

  -- AlignOrientation
  local ao = Instance.new("AlignOrientation")
  ao.Name = "WoodzHub_AO"
  ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
  ao.Attachment0 = a0
  ao.MaxTorque = ORI_MAX_TORQUE
  ao.Responsiveness = ORI_RESPONSIVENESS
  ao.RigidityEnabled = false
  ao.Parent = hrp

  -- controller API
  local ctl = {}
  function ctl:setGoal(cf)
    ap.Position = cf.Position
    ao.CFrame  = cf.Rotation
  end
  function ctl:destroy()
    ap:Destroy()
    ao:Destroy()
    a0:Destroy()
  end
  return ctl
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

  while flagGetter() do
    local character = utils.waitForCharacter()
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
      label("Current Target: None")
      task.wait(0.05)
      continue
    end

    local enemies = refreshEnemyList()
    if #enemies == 0 then
      label("Current Target: None")
      task.wait(0.1)
      continue
    end

    for _, enemy in ipairs(enemies) do
      if not flagGetter() then break end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

      local eh = enemy:FindFirstChildOfClass("Humanoid")
      if not eh or eh.Health <= 0 then continue end

      -- plan initial hop position
      local okPivot, pcf = pcall(function() return enemy:GetPivot() end)
      local targetCF = (okPivot and isValidCFrame(pcf)) and (pcf * CFrame.new(ABOVE_OFFSET)) or nil
      if not targetCF then continue end

      -- instant hop (replicated) — prevents glide
      hardTeleport(targetCF)

      -- reacquire bits after hop
      character = player.Character
      hum = character and character:FindFirstChildOfClass("Humanoid")
      hrp = character and character:FindFirstChild("HumanoidRootPart")
      if not character or not hum or not hrp then continue end

      -- calm physics but keep replication
      local oldPS = hum.PlatformStand
      hum.PlatformStand = true
      zeroVel(hrp)

      -- constraint controller for smooth lock above target
      local ctl = makeSmoothFollow(hrp)

      -- resolve a concrete part to follow
      local targetPart = findBasePart(enemy)
      if not targetPart then
        local t0 = tick()
        repeat
          RunService.Heartbeat:Wait()
          targetPart = findBasePart(enemy)
        until targetPart or (tick() - t0) > 2 or not enemy.Parent or eh.Health <= 0
      end
      if not targetPart then
        hum.PlatformStand = oldPS
        ctl:destroy()
        continue
      end

      label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

      -- timers for weather + stall
      local isWeather   = isWeatherName(enemy.Name)
      local lastHealth  = eh.Health
      local lastDropAt  = tick()
      local startedAt   = tick()

      local hcConn = eh.HealthChanged:Connect(function(h)
        label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
        if h < lastHealth then lastDropAt = tick() end
        lastHealth = h
      end)

      -- attack loop with weather preemption
      local lastWeatherPoll = 0
      while flagGetter() and enemy.Parent and eh.Health > 0 do
        local partNow = findBasePart(enemy) or targetPart
        if not partNow then break end

        -- desired pose above enemy (smooth via constraints; no judder)
        local desired = partNow.CFrame * CFrame.new(ABOVE_OFFSET)
        ctl:setGoal(desired)

        -- attack
        local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
        if hrpTarget and autoAttackRemote then
          pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
        end

        -- Weather-only timeout
        local now = tick()
        if isWeather and (now - startedAt) > WEATHER_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Weather Event timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT), 3)
          break
        end

        -- Non-weather stall detection
        if not isWeather and (now - lastDropAt) > NON_WEATHER_STALL_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(enemy.Name, NON_WEATHER_STALL_TIMEOUT), 3)
          break
        end

        -- 🔸 Weather preemption:
        -- if Weather is selected and any weather mob is alive,
        -- and we're NOT already on a weather mob, immediately switch.
        if not isWeather and (now - lastWeatherPoll) >= 0.1 then
          lastWeatherPoll = now
          if anyAliveWeather() then
            utils.notify("🌲 Auto-Farm", "Weather target detected — switching immediately.", 2)
            break
          end
        end

        RunService.Heartbeat:Wait()
      end

      if hcConn then hcConn:Disconnect() end
      label("Current Target: None")

      -- cleanup + restore
      ctl:destroy()
      if hum and hum.Parent then
        hum.PlatformStand = oldPS
        zeroVel(hrp)
      end

      RunService.Heartbeat:Wait()
    end

    RunService.Heartbeat:Wait()
  end
end

return M
