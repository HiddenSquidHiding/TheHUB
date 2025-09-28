-- utils.lua
local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')

local M = { uiConnections = {} }

function M.track(conn)
  table.insert(M.uiConnections, conn)
  return conn
end

function M.disconnectAll(list)
  for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
  table.clear(list)
end

function M.new(t, props, parent)
  local i = Instance.new(t)
  if props then for k,v in pairs(props) do i[k]=v end end
  if parent then i.Parent = parent end
  return i
end

function M.notify(title, content, duration)
  local player = Players.LocalPlayer
  local PlayerGui = player:WaitForChild('PlayerGui')
  local ScreenGui = M.new('ScreenGui', {ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=2e9}, PlayerGui)
  local frame = M.new('Frame', {Size=UDim2.new(0,300,0,100), Position=UDim2.new(1,-310,0,10), BackgroundColor3=Color3.fromRGB(30,30,30)}, ScreenGui)
  M.new('TextLabel', {Size=UDim2.new(1,0,0,30), BackgroundColor3=Color3.fromRGB(50,50,50), TextColor3=Color3.new(1,1,1), Text=title, TextSize=14, Font=Enum.Font.SourceSansBold}, frame)
  M.new('TextLabel', {Size=UDim2.new(1,-10,0,60), Position=UDim2.new(0,5,0,35), BackgroundTransparency=1, TextColor3=Color3.new(1,1,1), Text=content, TextWrapped=true, TextSize=14, Font=Enum.Font.SourceSans}, frame)
  task.spawn(function() task.wait(duration or 5) ScreenGui:Destroy() end)
end

function M.waitForCharacter()
  local player = Players.LocalPlayer
  while not player.Character or not player.Character:FindFirstChild('HumanoidRootPart') or not player.Character:FindFirstChild('Humanoid') do
    player.CharacterAdded:Wait(); task.wait(0.1)
  end
  return player.Character
end

function M.isValidCFrame(cf)
  if not cf then return false end
  local p = cf.Position
  return p.X==p.X and p.Y==p.Y and p.Z==p.Z and math.abs(p.X)<10000 and math.abs(p.Y)<10000 and math.abs(p.Z)<10000
end

function M.findBasePart(model)
  if not model then return nil end
  local names={'HumanoidRootPart','PrimaryPart','Body','Hitbox','Root','Main'}
  for _,n in ipairs(names) do local part=model:FindFirstChild(n); if part and part:IsA('BasePart') then return part end end
  for _,d in ipairs(model:GetDescendants()) do if d:IsA('BasePart') then return d end end
  return nil
end

function M.searchFoldersList()
  local folders = { Workspace }
  for _, d in ipairs(Workspace:GetDescendants()) do if d:IsA('Folder') then table.insert(folders,d) end end
  return folders
end

return M
