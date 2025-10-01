-- farm.lua
-- Handles auto-farming logic for WoodzHUB, plus model selection & filtering
-- Updated: instant hop to next target (no inter-target delay) + StreamingEnabled pivot approach

local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- 🔧 Use injected utils directly (no require(nil))
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[farm.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading farm.lua")
end
local utils = getUtils()

-- Data tables (groups, forced monsters)
local data = require(script.Parent.data_monsters)

-- State ---------------------------------------------------------
local M = {}
local autoAttackRemote = nil

-- Selection/filtering state
local selectedMonsterModels = { 'Weather Events' }
local allMonsterModels, filteredMonsterModels = {}, {}

function M.getSelected() return selectedMonsterModels end
function M.setSelected(t) selectedMonsterModels = t or {} end
function M.getFiltered() return filteredMonsterModels end
function M.isSelected(name) return table.find(selectedMonsterModels, name) ~= nil end
function M.toggleSelect(name)
  local idx = table.find(selectedMonsterModels, name)
  if idx then table.remove(selectedMonsterModels, idx) else table.insert(selectedMonsterModels, name) end
end

-- Helpers -------------------------------------------------------
local function pushUnique(valid, name)
  if not table.find(valid, name)
     and not table.find(data.toSahurModels, name)
     and not table.find(data.weatherEventModels, name) then
    table.insert(valid, name)
  end
end

-- Index monsters present in Workspace + add forced ones + group entries
function M.getMonsterModels()
  local valid = {}

  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA('Model') and not Players:GetPlayerFromCharacter(node) then
      local hum = node:FindFirstChildOfClass('Humanoid')
      if hum and hum.Health > 0 then pushUnique(valid, node.Name) end
    end
  end

  for _, nm in ipairs(data.forcedMonsters) do pushUnique(valid, nm) end

  table.insert(valid, 'To Sahur')
  table.insert(valid, 'Weather Events')

  table.sort(valid)
  allMonsterModels = valid
  filteredMonsterModels = table.clone(valid)
  return valid
end

-- Filter list by text (keeps groups if any member matches)
function M.filterMonsterModels(text)
  text = tostring(text or ''):lower()
  local filtered = {}
  local function matchesAny(list)
    for _, n in ipairs(list) do if string.find(n:lower(), text, 1, true) then return true end end
    return false
  end
  if text == '' then
    filtered = allMonsterModels
  else
    for _, model in ipairs(allMonsterModels) do
      if model == 'Weather Events' then
        if matchesAny(data.weatherEventModels) then table.insert(filtered, model) end
      elseif model == 'To Sahur' then
        if matchesAny(data.toSahurModels) then table.insert(filtered, model) end
      elseif string.find(model:lower(), text, 1, true) then
        table.insert(filtered, model)
      end
    end
  end
  table.sort(filtered)
  if #filtered == 0 then filtered = allMonsterModels end
  filteredMonsterModels = filtered
  return filtered
end

-- Enemy refresh with priority: Weather > Explicit > Sahur ------------------
local function listEnemies()
  local wantWeather = table.find(selectedMonsterModels, 'Weather Events') ~= nil
  local wantSahur   = table.find(selectedMonsterModels, 'To Sahur') ~= nil

  local weatherEnemies, otherEnemies, sahurEnemies = {}, {}, {}

  local explicit = {}
  for _, name in ipairs(selectedMonsterModels) do
    if name ~= 'Weather Events' and name ~= 'To Sahur' then
      explicit[name:lower()] = true
    end
  end

  local function isIn(list, lname)
    for _, n in ipairs(list) do if lname == n:lower() then return true end end
    return false
  end

  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA('Model') and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass('Humanoid')
      if h and h.Health > 0 then
        local lname = node.Name:lower()
        local isWeather  = wantWeather and isIn(data.weatherEventModels, lname)
        local isExplicit = explicit[lname] == true
        local isSahur    = wantSahur and isIn(data.toSahurModels, lname)
        if isWeather then table.insert(weatherEnemies, node)
        elseif isExplicit then table.insert(otherEnemies, node)
        elseif isSahur then table.insert(sahurEnemies, node) end
      end
    end
  end

  local enemies = {}
  for _, e in ipairs(weatherEnemies) do table.insert(enemies, e) end
  for _, e in ipairs(otherEnemies) do table.insert(enemies, e) end
  for _, e in ipairs(sahurEnemies) do table.insert(enemies, e) end
  return enemies
end

-- Locals -------------------------------------------------------------------
local function isValidCFrame(cf)
  if not cf then return false end
  local p = cf.Position
  return p.X == p.X and p.Y == p.Y and p.Z == p.Z
     and math.abs(p.X) < 10000 and math.abs(p.Y) < 10000 and math.abs(p.Z) < 10000
end

local function findBasePart(model)
  if not model then return nil end
  local candidates = { 'HumanoidRootPart','PrimaryPart','Body','Hitbox','Root','Main' }
  for _, n in ipairs(candidates) do
    local part = model:FindFirstChild(n)
    if part and part:IsA('BasePart') then return part end
  end
  for _, d in ipairs(model:GetDescendants()) do
    if d:IsA('BasePart') then return d end
  end
  return nil
end

-- Remotes ------------------------------------------------------------------
function M.setupAutoAttackRemote()
  autoAttackRemote = nil
  local ok, remote = pcall(function()
    return ReplicatedStorage:WaitForChild('Packages'):WaitForChild('Knit')
      :WaitForChild('Services'):WaitForChild('MonsterService')
      :WaitForChild('RF'):WaitForChild('RequestAttack')
  end)
  if ok and remote and remote:IsA('RemoteFunction') then
    autoAttackRemote = remote
    utils.notify('🌲 Auto Attack', 'RequestAttack RemoteFunction found.', 3)
  else
    utils.notify('🌲 Error', 'RequestAttack RemoteFunction not found. Farming may not work.', 5)
  end
end

-- Main auto-farm loop (pivot-first; teleports to stream in remote mobs) ----
function M.runAutoFarm(getEnabled, setTargetText)
  if not autoAttackRemote then return end
  local player = Players.LocalPlayer

  local function setLabel(txt) if setTargetText then setTargetText(txt) end end

  while getEnabled() do
    local character = utils.waitForCharacter()
    if not character or not character:FindFirstChild('HumanoidRootPart') then
      task.wait(0.05)  -- quick retry if character not ready
      continue
    end

    local enemies = listEnemies()
    if #enemies == 0 then
      setLabel('Current Target: None')
      task.wait(0.05)  -- tight polling so we hop ASAP when something spawns
      continue
    end

    -- iterate current snapshot immediately; no inter-target sleeps
    for _, enemy in ipairs(enemies) do
      if not getEnabled() then setLabel('Current Target: None'); return end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

      local humanoid = enemy:FindFirstChildOfClass('Humanoid')
      if not humanoid or humanoid.Health <= 0 then continue end

      -- Phase 1: try basepart; otherwise use pivot to approach
      local targetPart = findBasePart(enemy)
      local targetCF

      if targetPart then
        targetCF = targetPart.CFrame * CFrame.new(0, 20, 0)
      else
        local okPivot, pivotCF = pcall(function() return enemy:GetPivot() end)
        if okPivot and isValidCFrame(pivotCF) then
          targetCF = pivotCF * CFrame.new(0, 20, 0)
        end
      end

      if not targetCF or not isValidCFrame(targetCF) then
        task.wait(0.05)
        local okPivot2, pivotCF2 = pcall(function() return enemy:GetPivot() end)
        if okPivot2 and isValidCFrame(pivotCF2) then
          targetCF = pivotCF2 * CFrame.new(0, 20, 0)
        end
      end

      if not targetCF or not isValidCFrame(targetCF) then
        continue
      end

      -- Teleport near target to stream in parts
      local okTeleport = pcall(function()
        local ch = player.Character
        if ch and ch:FindFirstChild('HumanoidRootPart') and ch:FindFirstChildOfClass('Humanoid') and ch.Humanoid.Health > 0 then
          ch.HumanoidRootPart.CFrame = targetCF
        end
      end)
      if not okTeleport then continue end

      -- Resolve a real base part with a short timeout
      local APPROACH_TIMEOUT = 3.0
      local t0 = tick()
      repeat
        task.wait(0.05)
        targetPart = findBasePart(enemy)
      until targetPart or (tick() - t0) > APPROACH_TIMEOUT or not enemy.Parent or (humanoid and humanoid.Health <= 0)

      if not targetPart then continue end

      -- Now attack with live tracking
      local cf = targetPart.CFrame * CFrame.new(0, 20, 0)
      if not isValidCFrame(cf) then continue end

      setLabel(('Current Target: %s (Health: %d)'):format(enemy.Name, math.floor(humanoid.Health)))

      local hoverBP = Instance.new('BodyPosition')
      hoverBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
      hoverBP.D = 1000; hoverBP.P = 10000
      hoverBP.Position = cf.Position
      hoverBP.Name = "WoodzHub_AttackHover"
      hoverBP.Parent = character.HumanoidRootPart

      local hcConn = humanoid.HealthChanged:Connect(function(h)
        setLabel(('Current Target: %s (Health: %d)'):format(enemy.Name, math.floor(h)))
      end)

      -- Attack loop; no sleeps beyond attack cadence; re-resolve part if needed
      local TARGET_TIMEOUT = 30
      local start = tick()
      while getEnabled() and enemy.Parent and humanoid and humanoid.Health > 0 do
        if (tick() - start) > TARGET_TIMEOUT then break end
        local partNow = findBasePart(enemy) or targetPart
        local cfNow = partNow and (partNow.CFrame * CFrame.new(0, 20, 0))
        if cfNow and isValidCFrame(cfNow) then
          hoverBP.Position = cfNow.Position
        end

        local hrp = enemy:FindFirstChild('HumanoidRootPart')
        if hrp then pcall(function() autoAttackRemote:InvokeServer(hrp.CFrame) end) end
        task.wait(0.1) -- attack cadence
      end

      if hcConn then hcConn:Disconnect() end
      if hoverBP then hoverBP:Destroy() end
      setLabel('Current Target: None')

      if not getEnabled() then return end
      -- ⬆️ immediately proceed to next enemy in this snapshot (no delay)
    end

    -- Immediately loop to rescan for anything new (no inter-iteration delay)
    -- (Tiny 0.01 to yield; prevents hard lockup without impacting hop speed)
    task.wait(0.01)
  end
end

return M
