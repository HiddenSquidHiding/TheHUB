-- farm.lua (auto-farm with noclip-through-objects EXCEPT floor, active only while auto-farm is ON)
local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')
local VirtualUser = game:GetService('VirtualUser')

local utils = require(script.Parent._deps.utils)
local data = require(script.Parent.data_monsters)

local M = { autoAttackRemote = nil }

----------------------------------------------------------------
-- GHOST (noclip except floor) — ENABLED ONLY DURING AUTOFARM --
----------------------------------------------------------------
local Ghost = {
  _enabled = false,
  _conn = nil,
  _bp = nil,            -- BodyPosition used to stick to floor
  _rayParams = nil,
  _cacheCollide = {},   -- part -> original CanCollide
  _stickOffset = 0,     -- HipHeight + half HRP height
  _suspendStick = false -- when hovering over target, pause floor stick
}

local function ghostGetChar()
  local p = Players.LocalPlayer
  while not p.Character or not p.Character:FindFirstChild('HumanoidRootPart') or not p.Character:FindFirstChildOfClass('Humanoid') do
    p.CharacterAdded:Wait()
    task.wait()
  end
  return p.Character
end

local function ghostSetupStickOffset(char)
  local hum = char:FindFirstChildOfClass('Humanoid')
  local hrp = char:FindFirstChild('HumanoidRootPart')
  if not (hum and hrp) then return end
  Ghost._stickOffset = (hum.HipHeight or 2) + (hrp.Size.Y / 2)
end

local function ghostMakeRayParams(char)
  local rp = RaycastParams.new()
  rp.FilterType = Enum.RaycastFilterType.Exclude
  rp.FilterDescendantsInstances = { char }
  rp.RespectCanCollide = false
  Ghost._rayParams = rp
end

local function ghostSetCharacterNoclip(char, noclip)
  for _, d in ipairs(char:GetDescendants()) do
    if d:IsA('BasePart') then
      if noclip then
        if Ghost._cacheCollide[d] == nil then
          Ghost._cacheCollide[d] = d.CanCollide
        end
        d.CanCollide = false
      else
        local orig = Ghost._cacheCollide[d]
        if orig ~= nil then
          d.CanCollide = orig
        else
          d.CanCollide = true
        end
      end
    end
  end
  if not noclip then
    Ghost._cacheCollide = {}
  end
end

local function ghostEnsureFloorPin(char)
  local hrp = char:FindFirstChild('HumanoidRootPart')
  if not hrp then return end
  if Ghost._bp == nil or Ghost._bp.Parent ~= hrp then
    local bp = Instance.new('BodyPosition')
    bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bp.D = 1000
    bp.P = 10000
    bp.Position = hrp.Position
    bp.Parent = hrp
    Ghost._bp = bp
  end
end

local function ghostRemoveFloorPin()
  if Ghost._bp then
    Ghost._bp:Destroy()
    Ghost._bp = nil
  end
end

local function ghostStep()
  if not Ghost._enabled or Ghost._suspendStick then return end
  local char = Players.LocalPlayer.Character
  if not char then return end
  local hrp = char:FindFirstChild('HumanoidRootPart')
  if not hrp then return end

  local origin = hrp.Position
  local hit = Workspace:Raycast(origin + Vector3.new(0, 2, 0), Vector3.new(0, -200, 0), Ghost._rayParams)
  if hit then
    local targetY = hit.Position.Y + (Ghost._stickOffset or 3)
    local pos = hrp.Position
    if Ghost._bp then
      Ghost._bp.Position = Vector3.new(pos.X, targetY, pos.Z)
    end
  else
    -- no floor under us; keep previous position (bp already set) to avoid dropping
    if Ghost._bp then Ghost._bp.Position = hrp.Position end
  end
end

local function ghostEnable()
  if Ghost._enabled then return end
  Ghost._enabled = true
  local char = ghostGetChar()
  ghostSetupStickOffset(char)
  ghostMakeRayParams(char)
  ghostSetCharacterNoclip(char, true)
  ghostEnsureFloorPin(char)
  Ghost._conn = RunService.Stepped:Connect(ghostStep)
end

local function ghostDisable()
  if not Ghost._enabled then return end
  Ghost._enabled = false
  if Ghost._conn then Ghost._conn:Disconnect(); Ghost._conn = nil end
  ghostRemoveFloorPin()
  local char = Players.LocalPlayer.Character
  if char then ghostSetCharacterNoclip(char, false) end
end

-- Expose suspend control to farm hover logic:
local function ghostSuspendFloorStick(suspend) Ghost._suspendStick = suspend and true or false end

----------------------------------------------------------
-- Existing farm selection/filtering & remote setup code --
----------------------------------------------------------

local selectedMonsterModels = { 'Weather Events' }
local allMonsterModels, filteredMonsterModels = {}, {}

function M.getSelected() return selectedMonsterModels end
function M.setSelected(t) selectedMonsterModels = t end
function M.getFiltered() return filteredMonsterModels end

local function getMonsterModels()
  local valid = {}
  local function pushUnique(name)
    if not table.find(valid, name)
      and not table.find(data.toSahurModels, name)
      and not table.find(data.weatherEventModels, name)
    then
      table.insert(valid, name)
    end
  end
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA('Model') and not Players:GetPlayerFromCharacter(node) then
      local hum = node:FindFirstChildOfClass('Humanoid')
      if hum and hum.Health > 0 then
        pushUnique(node.Name)
      end
    end
  end
  for _, nm in ipairs(data.forcedMonsters) do pushUnique(nm) end
  table.insert(valid, 'To Sahur'); table.insert(valid, 'Weather Events')
  table.sort(valid); allMonsterModels = valid; filteredMonsterModels = table.clone(valid); return valid
end
M.getMonsterModels = getMonsterModels

function M.filterMonsterModels(text)
  text = tostring(text or ''):lower()
  local filtered = {}
  local function matchesAny(list)
    for _, n in ipairs(list) do if string.find(n:lower(), text, 1, true) then return true end end
    return false
  end
  if text == '' then filtered = allMonsterModels else
    for _, model in ipairs(allMonsterModels) do
      if model == 'Weather Events' then if matchesAny(data.weatherEventModels) then table.insert(filtered, model) end
      elseif model == 'To Sahur' then if matchesAny(data.toSahurModels) then table.insert(filtered, model) end
      elseif string.find(model:lower(), text, 1, true) then table.insert(filtered, model) end
    end
  end
  table.sort(filtered); if #filtered == 0 then filtered = allMonsterModels end
  filteredMonsterModels = filtered; return filtered
end

local function setupAutoAttackRemote()
  M.autoAttackRemote = nil
  local ok, remote = pcall(function()
    return ReplicatedStorage:WaitForChild('Packages'):WaitForChild('Knit'):WaitForChild('Services'):WaitForChild('MonsterService'):WaitForChild('RF'):WaitForChild('RequestAttack')
  end)
  if ok and remote and remote:IsA('RemoteFunction') then M.autoAttackRemote = remote end
end
M.setupAutoAttackRemote = setupAutoAttackRemote

local function refreshEnemyList()
  local wantWeather = table.find(selectedMonsterModels, 'Weather Events') ~= nil
  local wantSahur   = table.find(selectedMonsterModels, 'To Sahur') ~= nil
  local weatherEnemies, otherEnemies, sahurEnemies = {}, {}, {}
  local explicitSet = {}
  for _, name in ipairs(selectedMonsterModels) do
    if name ~= 'Weather Events' and name ~= 'To Sahur' then explicitSet[name:lower()] = true end
  end
  local function isIn(list, lname) for _, n in ipairs(list) do if lname == n:lower() then return true end end return false end
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA('Model') and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass('Humanoid')
      if h and h.Health > 0 then
        local lname = node.Name:lower()
        local isWeather = wantWeather and isIn(data.weatherEventModels, lname)
        local isExplicit = explicitSet[lname] == true
        local isSahur = wantSahur and isIn(data.toSahurModels, lname)
        if isWeather then table.insert(weatherEnemies, node)
        elseif isExplicit then table.insert(otherEnemies, node)
        elseif isSahur then table.insert(sahurEnemies, node)
        end
      end
    end
  end
  local enemies = {}
  for _, e in ipairs(weatherEnemies) do table.insert(enemies, e) end
  for _, e in ipairs(otherEnemies) do table.insert(enemies, e) end
  for _, e in ipairs(sahurEnemies) do table.insert(enemies, e) end
  return enemies
end

local function preventAFK(flagGetter)
  task.spawn(function()
    while flagGetter() do
      pcall(function() VirtualUser:CaptureController(); VirtualUser:SetKeyDown('W'); task.wait(0.1); VirtualUser:SetKeyUp('W'); task.wait(0.1); VirtualUser:MoveMouse(Vector2.new(10,0)) end)
      task.wait(60)
    end
  end)
end
M.preventAFK = preventAFK

-------------------------------------------------
-- Main farm loop (now auto-enables Ghost here) --
-------------------------------------------------
function M.runAutoFarm(getEnabled, setTargetText)
  if not M.autoAttackRemote then return end

  -- enable noclip + floor stick for the whole autofarm session
  ghostEnable()

  local GetPlayerData = nil
  do
    local ok, res = pcall(function() return ReplicatedStorage.Packages.Knit.Services.LookupService.RF.GetPlayerData end)
    if ok and res and res:IsA('RemoteFunction') then GetPlayerData = res end
  end

  local function finish()
    setTargetText('Current Target: None')
    ghostDisable() -- always restore at the end
  end

  while getEnabled() do
    local character = utils.waitForCharacter()
    if not character or not character:FindFirstChild('HumanoidRootPart') then
      task.wait(1); continue
    end

    local enemies = refreshEnemyList()
    if #enemies == 0 then
      setTargetText('Current Target: None')
      task.wait(0.5)
      continue
    end

    for _, enemy in ipairs(enemies) do
      if not getEnabled() then finish(); return end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

      local humanoid = enemy:FindFirstChildOfClass('Humanoid')
      if not humanoid or humanoid.Health <= 0 then continue end

      local playerHumanoid = character:FindFirstChildOfClass('Humanoid')
      local playerHealth = playerHumanoid and playerHumanoid.Health or 100
      local playerAttackPower = 100
      if GetPlayerData then
        local ok2, stats = pcall(function() return GetPlayerData:InvokeServer() end)
        if ok2 and type(stats) == 'table' then
          playerAttackPower = stats.Damage or stats.AttackPower or stats.Power or playerAttackPower
        end
      end

      local mobHealth = humanoid.Health
      local mobAttackPower = 10
      local pivotCF = enemy:GetPivot()
      if not utils.isValidCFrame(pivotCF) then continue end

      local estimatedHitsToKill = math.ceil(mobHealth / playerAttackPower)
      local estimatedDamageReceived = estimatedHitsToKill * mobAttackPower
      local safetyThreshold = playerHealth * 0.8
      if estimatedDamageReceived >= safetyThreshold then
        -- skip unfair fights
        continue
      end

      -- initial proximity teleport (noclip already on)
      local tempTargetCF = pivotCF * CFrame.new(0, 20, 0)
      local teleported = false
      for i = 1, 3 do
        local ok = pcall(function()
          local p = Players.LocalPlayer
          local ch = p.Character
          if ch and ch:FindFirstChild('HumanoidRootPart') and ch:FindFirstChildOfClass('Humanoid') and ch.Humanoid.Health > 0 then
            ch.HumanoidRootPart.CFrame = tempTargetCF
            task.wait(0.1)
          end
        end)
        if ok then teleported = true; break end
        task.wait(1)
      end
      if not teleported then continue end

      task.wait(0.5)

      local targetPart = utils.findBasePart(enemy)
      if not targetPart then continue end
      local targetCF = targetPart.CFrame * CFrame.new(0, 20, 0)
      if not utils.isValidCFrame(targetCF) then continue end

      -- Hover above target while attacking — suspend floor stick to avoid BP conflict
      ghostSuspendFloorStick(true)

      local hoverBP = Instance.new('BodyPosition')
      hoverBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
      hoverBP.Position = targetCF.Position
      hoverBP.D = 1000
      hoverBP.P = 10000
      hoverBP.Name = "WoodzHub_AttackHover"
      hoverBP.Parent = character.HumanoidRootPart

      local hc = humanoid.HealthChanged:Connect(function(h)
        setTargetText(('Current Target: %s (Health: %d)'):format(enemy.Name, h))
      end)

      local start = tick()
      local isWeather = table.find(data.weatherEventModels, enemy.Name:lower()) ~= nil

      while getEnabled() and enemy.Parent and humanoid and humanoid.Health > 0 do
        if isWeather and (tick() - start) > 30 then break end
        local ok = pcall(function()
          local partNow = utils.findBasePart(enemy)
          if partNow then
            targetCF = partNow.CFrame * CFrame.new(0, 20, 0)
            if not utils.isValidCFrame(targetCF) then return end
            hoverBP.Position = targetCF.Position
          else
            return
          end
          local hrp = enemy:FindFirstChild('HumanoidRootPart')
          if hrp then M.autoAttackRemote:InvokeServer(hrp.CFrame) end
        end)
        if not ok then break end
        task.wait(0.1)
      end

      if hc then hc:Disconnect() end
      if hoverBP then hoverBP:Destroy() end

      -- resume floor sticking once we’re done hovering this enemy
      ghostSuspendFloorStick(false)

      setTargetText('Current Target: None')
      if not getEnabled() then finish(); return end
    end

    task.wait(0.5)
  end

  finish()
end

return M
