-- farm.lua
local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local VirtualUser = game:GetService('VirtualUser')

local utils = require(script.Parent._deps.utils)
local data = require(script.Parent.data_monsters)

local M = { autoAttackRemote = nil }

local selectedMonsterModels = { 'Weather Events' }
local allMonsterModels, filteredMonsterModels = {}, {}

function M.getSelected() return selectedMonsterModels end
function M.setSelected(t) selectedMonsterModels = t end
function M.getFiltered() return filteredMonsterModels end

local function getMonsterModels()
  local valid = {}
  local function pushUnique(name)
    if not table.find(valid,name) and not table.find(data.toSahurModels, name) and not table.find(data.weatherEventModels, name) then
      table.insert(valid, name)
    end
  end
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA('Model') and not Players:GetPlayerFromCharacter(node) then
      local hum = node:FindFirstChildOfClass('Humanoid'); if hum and hum.Health>0 then pushUnique(node.Name) end
    end
  end
  for _, nm in ipairs(data.forcedMonsters) do pushUnique(nm) end
  table.insert(valid,'To Sahur'); table.insert(valid,'Weather Events')
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
  if text=='' then filtered = allMonsterModels else
    for _, model in ipairs(allMonsterModels) do
      if model=='Weather Events' then if matchesAny(data.weatherEventModels) then table.insert(filtered, model) end
      elseif model=='To Sahur' then if matchesAny(data.toSahurModels) then table.insert(filtered, model) end
      elseif string.find(model:lower(), text, 1, true) then table.insert(filtered, model) end
    end
  end
  table.sort(filtered); if #filtered==0 then filtered = allMonsterModels end
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
  for _, name in ipairs(selectedMonsterModels) do if name~='Weather Events' and name~='To Sahur' then explicitSet[name:lower()] = true end end
  local function isIn(list, lname) for _,n in ipairs(list) do if lname==n:lower() then return true end end return false end
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA('Model') and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass('Humanoid')
      if h and h.Health>0 then
        local lname = node.Name:lower()
        local isWeather = wantWeather and isIn(data.weatherEventModels, lname)
        local isExplicit = explicitSet[lname]==true
        local isSahur = wantSahur and isIn(data.toSahurModels, lname)
        if isWeather then table.insert(weatherEnemies,node) elseif isExplicit then table.insert(otherEnemies,node) elseif isSahur then table.insert(sahurEnemies,node) end
      end
    end
  end
  local enemies = {}
  for _,e in ipairs(weatherEnemies) do table.insert(enemies,e) end
  for _,e in ipairs(otherEnemies) do table.insert(enemies,e) end
  for _,e in ipairs(sahurEnemies) do table.insert(enemies,e) end
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

function M.runAutoFarm(getEnabled, setTargetText)
  if not M.autoAttackRemote then return end
  local GetPlayerData = nil
  do
    local ok, res = pcall(function() return ReplicatedStorage.Packages.Knit.Services.LookupService.RF.GetPlayerData end)
    if ok and res and res:IsA('RemoteFunction') then GetPlayerData = res end
  end
  while getEnabled() do
    local character = utils.waitForCharacter(); if not character or not character:FindFirstChild('HumanoidRootPart') then task.wait(1); continue end
    local enemies = refreshEnemyList(); if #enemies==0 then setTargetText('Current Target: None'); task.wait(0.5); continue end
    for _, enemy in ipairs(enemies) do
      if not getEnabled() then setTargetText('Current Target: None'); return end
