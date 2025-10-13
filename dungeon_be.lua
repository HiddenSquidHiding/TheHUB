-- dungeon_be.lua
-- Brainrot Evolutions Dungeon helper (no GUI). Controlled by setters.

local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

local M = {}

local autoAttackEnabled = false
local playAgainEnabled  = false
local inited = false
local autoAttackRemote = nil
local listeners = {}

local function track(conn) table.insert(listeners, conn); return conn end

local function waitCharacter(plr)
  while not plr.Character or not plr.Character:FindFirstChild('HumanoidRootPart') or not plr.Character:FindFirstChildOfClass('Humanoid') do
    plr.CharacterAdded:Wait(); task.wait()
  end
  return plr.Character
end

local function isValidCFrame(cf)
  if not cf then return false end
  local p = cf.Position
  return p.X == p.X and p.Y == p.Y and p.Z == p.Z
     and math.abs(p.X) < 10000 and math.abs(p.Y) < 10000 and math.abs(p.Z) < 10000
end

local function findBasePart(model)
  if not model then return nil end
  for _, n in ipairs({'HumanoidRootPart','PrimaryPart','Body','Hitbox','Root','Main'}) do
    local part = model:FindFirstChild(n)
    if part and part:IsA('BasePart') then return part end
  end
  for _, d in ipairs(model:GetDescendants()) do
    if d:IsA('BasePart') then return d end
  end
  return nil
end

local function chainFind(parent, names, timeoutEach)
  local cur = parent
  for _, name in ipairs(names) do
    local t0 = tick()
    local obj = cur:FindFirstChild(name)
    while not obj and (tick()-t0) < (timeoutEach or 5) do task.wait(0.05); obj = cur:FindFirstChild(name) end
    if not obj then return nil end
    cur = obj
  end
  return cur
end

local function findRoomsFolder()
  local function search(node)
    if node.Name == 'Rooms' and node:IsA('Folder') then return node end
    for _, child in ipairs(node:GetChildren()) do
      local r = search(child); if r then return r end
    end
    return nil
  end
  return search(Workspace)
end

local function waitForDoor(roomsFolder)
  if not roomsFolder then return false end
  local room1 = roomsFolder:FindFirstChild('1'); if not room1 then return false end
  local door = room1:FindFirstChild('Door'); if not door then return true end
  local timeout, startTime = 30, tick()
  while door and door.Parent and autoAttackEnabled and (tick() - startTime < timeout) do
    door = room1:FindFirstChild('Door'); task.wait(0.5)
  end
  if not autoAttackEnabled then return false end
  return true
end

local function getEnemiesInRoom(roomsFolder, roomNumber)
  local enemies = {}
  local room = roomsFolder:FindFirstChild(tostring(roomNumber))
  if room and room:FindFirstChild('Enemies') then
    for _, enemy in ipairs(room.Enemies:GetChildren()) do
      if enemy:IsA('Model') and not Players:GetPlayerFromCharacter(enemy) then
        local h = enemy:FindFirstChildOfClass('Humanoid')
        if h and h.Health > 0 then table.insert(enemies, enemy) end
      end
    end
  end
  return enemies
end

local function areAllRoomsClear(roomsFolder)
  for i=1,6 do if #getEnemiesInRoom(roomsFolder, i) > 0 then return false end end
  return true
end

local function setupAutoAttackRemote()
  autoAttackRemote = chainFind(ReplicatedStorage, {'Packages','Knit','Services','MonsterService','RF','RequestAttack'}, 5)
end

local function setupDisplayResultsListener()
  local re = chainFind(ReplicatedStorage, {'Packages','Knit','Services','DungeonService','RE','DisplayResults'}, 5)
  if re and re:IsA('RemoteEvent') then
    track(re.OnClientEvent:Connect(function()
      if playAgainEnabled and autoAttackEnabled then
        local rf = chainFind(ReplicatedStorage, {'Packages','Knit','Services','DungeonService','RF','PlayAgainPressed'}, 5)
        if rf and rf.InvokeServer then pcall(function() rf:InvokeServer() end) end
      end
    end))
  end
end

local function autoAttack()
  if not autoAttackRemote then return end
  local roomsFolder = findRoomsFolder(); if not roomsFolder then return end
  local player = Players.LocalPlayer

  while autoAttackEnabled do
    if not waitForDoor(roomsFolder) then break end

    local character = waitCharacter(player)
    if not character or not character:FindFirstChild('HumanoidRootPart') then task.wait(0.5); continue end

    for roomNumber=1,6 do
      if not autoAttackEnabled then break end
      local enemies = getEnemiesInRoom(roomsFolder, roomNumber)
      for _, enemy in ipairs(enemies) do
        if not autoAttackEnabled then break end
        local humanoid = enemy:FindFirstChildOfClass('Humanoid')
        if not humanoid or humanoid.Health <= 0 then continue end

        local pivot = enemy:GetPivot(); if not isValidCFrame(pivot) then continue end
        local targetCF = pivot * CFrame.new(0,20,0)
        for _=1,3 do
          pcall(function()
            local ch = player.Character
            if ch and ch:FindFirstChild('HumanoidRootPart') and ch:FindFirstChildOfClass('Humanoid') and ch.Humanoid.Health > 0 then
              ch.HumanoidRootPart.CFrame = targetCF
            end
          end)
          task.wait(0.06)
        end

        local part = findBasePart(enemy); if not part then continue end
        local hover = Instance.new('BodyPosition'); hover.MaxForce = Vector3.new(math.huge,math.huge,math.huge)
        hover.D = 1000; hover.P = 10000; hover.Position = (part.CFrame * CFrame.new(0,20,0)).Position
        local ch = player.Character; if not ch or not ch:FindFirstChild('HumanoidRootPart') then hover:Destroy(); continue end
        hover.Parent = ch.HumanoidRootPart

        while autoAttackEnabled and enemy.Parent and humanoid.Health > 0 do
          local cur = findBasePart(enemy) or part
          if cur then
            local cf = cur.CFrame * CFrame.new(0,20,0)
            if isValidCFrame(cf) then hover.Position = cf.Position end
          end
          local hrp = enemy:FindFirstChild('HumanoidRootPart')
          if hrp and autoAttackRemote then pcall(function() autoAttackRemote:InvokeServer(hrp.CFrame) end) end
          task.wait(0.05)
        end

        hover:Destroy()
      end
    end

    task.wait(0.2)
  end
end

function M.init()
  if inited then return end
  inited = true
  setupAutoAttackRemote()
  setupDisplayResultsListener()
end

function M.setAuto(on)
  on = on and true or false
  if on == autoAttackEnabled then return end
  autoAttackEnabled = on
  if on then task.spawn(autoAttack) end
end

function M.setReplay(on)
  playAgainEnabled = on and true or false
end

return M
