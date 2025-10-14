-- farm.lua (Weather-priority, fuzzy match, 5s TTK guard, death return, fastlevel-safe)
-- Works with/without data_monsters.lua

-- 🔧 Utils
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return {
    notify = function(_,_) end,
    waitForCharacter = function()
      local Players = game:GetService("Players")
      local plr = Players.LocalPlayer
      while true do
        local ch = plr.Character
        if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
          return ch
        end
        plr.CharacterAdded:Wait()
        task.wait()
      end
    end
  }
end

local utils  = getUtils()

-- Services
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

-- Optional data_monsters.lua (safe)
local WEATHER_NAMES, SAHUR_NAMES, FORCED_LIST = {}, {}, {}
do
  local ok, data = pcall(function() return require(script.Parent.data_monsters) end)
  if ok and type(data)=="table" then
    WEATHER_NAMES = (data.weatherEventModels or WEATHER_NAMES)
    SAHUR_NAMES   = (data.toSahurModels or SAHUR_NAMES)
    FORCED_LIST   = (data.forcedMonsters or FORCED_LIST)
  end
end

-- Strong defaults if data module missing/empty (won't crash if they don’t exist in-game)
if #WEATHER_NAMES == 0 then
  WEATHER_NAMES = {
    "Chicleteira","YONII","Coccodrillo","Chachech","Dragoni","MEDUS","Supermakretino",
    "Market Crate","BOSS","Malame","Las Vaquitas","Trippi","Octossini","Blueberrinni",
    "Crocodillitos","Kiwi","Orco"
  }
end
if #SAHUR_NAMES == 0 then
  SAHUR_NAMES = { "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur" }
end

-- Public module
local M = {}

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local WEATHER_TIMEOUT_S            = 30        -- hard cap guard
local NON_WEATHER_STALL_TIMEOUT_S  = 3         -- skip if HP unchanged for 3s
local WEATHER_MAX_TTK_S            = 5         -- ⬅ Your request: ignore weather mob if projected > 5s to kill
local ABOVE_OFFSET                 = Vector3.new(0, 20, 0)

local POS_RESPONSIVENESS           = 200
local POS_MAX_FORCE                = 1e9
local ORI_RESPONSIVENESS           = 200
local ORI_MAX_TORQUE               = 1e9

----------------------------------------------------------------------
-- Selection state
----------------------------------------------------------------------
local allMonsterModels = {}
local filteredMonsterModels = {}
local selectedMonsterModels = { "Weather Events" }

function M.getSelected() return selectedMonsterModels end
function M.setSelected(list)
  selectedMonsterModels = {}
  for _, n in ipairs(list or {}) do table.insert(selectedMonsterModels, n) end
end
function M.toggleSelect(name)
  local i = table.find(selectedMonsterModels, name)
  if i then table.remove(selectedMonsterModels, i) else table.insert(selectedMonsterModels, name) end
end
function M.isSelected(name)
  return table.find(selectedMonsterModels, name) ~= nil
end

----------------------------------------------------------------------
-- Name helpers (fuzzy)
----------------------------------------------------------------------
local function norm(s)
  s = tostring(s or ""):lower()
  s = s:gsub("[%p_]+"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
  return s
end

local function listContainsFuzzy(name, list)
  local ln = norm(name)
  for _, token in ipairs(list or {}) do
    local t = norm(token)
    if #t >= 3 then
      -- match either direction to be forgiving
      if ln:find(t, 1, true) or t:find(ln, 1, true) then return true end
    else
      if ln == t then return true end
    end
  end
  return false
end

local function isWeatherName(name) return listContainsFuzzy(name, WEATHER_NAMES) end
local function isSahurName(name)   return listContainsFuzzy(name, SAHUR_NAMES) end

----------------------------------------------------------------------
-- Discovery / filtering
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
  for _, nm in ipairs(FORCED_LIST) do pushUnique(valid, nm) end
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
      if n:lower():find(text, 1, true) then return true end
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
      elseif model:lower():find(text, 1, true) then
        table.insert(filtered, model)
      end
    end
  end

  table.sort(filtered)
  if #filtered == 0 then
    filtered = allMonsterModels
  end
  filteredMonsterModels = filtered
  return filtered
end

----------------------------------------------------------------------
-- Enemy prioritization (Weather first)
----------------------------------------------------------------------
local function refreshEnemyList()
  local wantWeather = table.find(selectedMonsterModels, "Weather Events") ~= nil
  local wantSahur   = table.find(selectedMonsterModels, "To Sahur") ~= nil

  local explicitSet = {}
  for _, n in ipairs(selectedMonsterModels) do
    if n ~= "Weather Events" and n ~= "To Sahur" then explicitSet[norm(n)] = true end
  end

  local weather, explicit, sahur = {}, {}, {}
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 then
        local lname = node.Name
        if wantWeather and isWeatherName(lname) then
          table.insert(weather, node)
        elseif explicitSet[norm(lname)] then
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

local function makeSmoothFollow(hrp)
  local a0 = Instance.new("Attachment"); a0.Name="WoodzHub_A0"; a0.Parent=hrp
  local ap = Instance.new("AlignPosition")
  ap.Name="WoodzHub_AP"; ap.Mode=Enum.PositionAlignmentMode.OneAttachment
  ap.Attachment0=a0; ap.ApplyAtCenterOfMass=true; ap.MaxForce=POS_MAX_FORCE
  ap.Responsiveness=POS_RESPONSIVENESS; ap.RigidityEnabled=false; ap.Parent=hrp
  local ao = Instance.new("AlignOrientation")
  ao.Name="WoodzHub_AO"; ao.Mode=Enum.OrientationAlignmentMode.OneAttachment
  ao.Attachment0=a0; ao.MaxTorque=ORI_MAX_TORQUE; ao.Responsiveness=ORI_RESPONSIVENESS
  ao.RigidityEnabled=false; ao.Parent=hrp

  local ctl={}
  function ctl:setGoal(cf) ap.Position=cf.Position; ao.CFrame=cf.Rotation end
  function ctl:destroy() ap:Destroy(); ao:Destroy(); a0:Destroy() end
  return ctl
end

----------------------------------------------------------------------
-- FastLevel toggle (external)
----------------------------------------------------------------------
local FASTLEVEL_ON = false
function M.setFastLevelEnabled(on) FASTLEVEL_ON = on and true or false end

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

  local lastDeathCheckAt = 0
  local lastEnemyCF = nil

  while flagGetter() do
    local character = utils.waitForCharacter()
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
      label("Current Target: None")
      task.wait(0.05)
      continue
    end

    -- If we died recently and have a last target CF, snap back to the fight
    if tick() - lastDeathCheckAt > 0.2 then
      lastDeathCheckAt = tick()
      if hum.Health <= 0 and lastEnemyCF and isValidCFrame(lastEnemyCF) then
        hardTeleport(lastEnemyCF)
      end
    end

    local enemies = refreshEnemyList()
    if #enemies == 0 then
      label("Current Target: None")
      task.wait(0.1)
      continue
    end

    -- Weather gets priority: already first in refreshEnemyList() output

    for _, enemy in ipairs(enemies) do
      if not flagGetter() then break end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

      local eh = enemy:FindFirstChildOfClass("Humanoid")
      if not eh or eh.Health <= 0 then continue end

      local okPivot, pcf = pcall(function() return enemy:GetPivot() end)
      local targetCF = (okPivot and isValidCFrame(pcf)) and (pcf * CFrame.new(ABOVE_OFFSET)) or nil
      if not targetCF then continue end

      -- Pre-hop & begin
      hardTeleport(targetCF)

      -- reacquire
      character = player.Character
      hum = character and character:FindFirstChildOfClass("Humanoid")
      hrp = character and character:FindFirstChild("HumanoidRootPart")
      if not character or not hum or not hrp then continue end

      local oldPS = hum.PlatformStand
      hum.PlatformStand = true
      zeroVel(hrp)

      local ctl = makeSmoothFollow(hrp)

      local part = findBasePart(enemy)
      if not part then
        local t0 = tick()
        repeat
          RunService.Heartbeat:Wait()
          part = findBasePart(enemy)
        until part or (tick()-t0)>2 or not enemy.Parent or eh.Health<=0
      end
      if not part then
        hum.PlatformStand = oldPS
        ctl:destroy()
        continue
      end

      label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

      local isWeather   = isWeatherName(enemy.Name)
      local lastHealth  = eh.Health
      local lastDropAt  = tick()
      local startedAt   = tick()

      -- quick DPS estimate after first drop to gate 5s weather cap
      local firstDropSeen, dps = false, nil

      local hcConn = eh.HealthChanged:Connect(function(h)
        label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
        if h < lastHealth then
          if not firstDropSeen then
            -- Estimate DPS from first drop window (avoid huge spikes)
            local dt = math.max(0.05, tick() - startedAt)
            dps = math.max(1, (lastHealth - h) / dt)
            firstDropSeen = true
          end
          lastDropAt = tick()
        end
        lastHealth = h
      end)

      while flagGetter() and enemy.Parent and eh.Health > 0 do
        local partNow = findBasePart(enemy) or part
        if not partNow then break end

        local desired = partNow.CFrame * CFrame.new(ABOVE_OFFSET)
        ctl:setGoal(desired)
        lastEnemyCF = desired  -- remember for post-death return

        local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
        if hrpTarget and autoAttackRemote then
          pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
        end

        local now = tick()

        -- Weather-only: TTK <= 5s check. If projected >5s, skip.
        if isWeather then
          if (now - startedAt) > WEATHER_TIMEOUT_S then
            utils.notify("🌲 Auto-Farm", ("Weather timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT_S), 3)
            break
          end
          if firstDropSeen and dps then
            local projected = eh.Health / math.max(1, dps)
            if projected > WEATHER_MAX_TTK_S then
              utils.notify("🌲 Auto-Farm", ("Skipping %s (TTK ~%0.1fs > %0.1fs)"):format(enemy.Name, projected, WEATHER_MAX_TTK_S), 3)
              break
            end
          end
        end

        -- Non-weather stall detection (disabled when FastLevel is on)
        if not isWeather and not FASTLEVEL_ON and (now - lastDropAt) > NON_WEATHER_STALL_TIMEOUT_S then
          utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(
            enemy.Name, NON_WEATHER_STALL_TIMEOUT_S), 3)
          break
        end

        RunService.Heartbeat:Wait()
      end

      if hcConn then hcConn:Disconnect() end
      label("Current Target: None")

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
