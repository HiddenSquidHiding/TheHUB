-- farm.lua
-- Handles auto-farming logic for WoodzHUB

local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local RunService = game:GetService('RunService')

-- 🔧 Use injected utils directly (don’t require nil)
local function getUtils()
    local p = script and script.Parent
    if p and p._deps and p._deps.utils then
        return p._deps.utils
    end
    if rawget(getfenv(), "__WOODZ_UTILS") then
        return __WOODZ_UTILS
    end
    error("[farm.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading farm.lua")
end

local utils = getUtils()

-- Bring in monster data (this module is a plain table, safe to require)
local data = require(script.Parent.data_monsters)

-- State
local autoFarmEnabled = false
local autoAttackRemote = nil
local currentTargetLabel = nil
local spawnConnections = {}

-- Helpers
local function waitForCharacter(player)
    while not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") do
        player.CharacterAdded:Wait()
        task.wait(0.1)
    end
    return player.Character
end

local function isValidCFrame(cf)
    if not cf then return false end
    local p = cf.Position
    return p.X == p.X and p.Y == p.Y and p.Z == p.Z
end

local function findBasePart(model)
    if not model then return nil end
    local candidates = {"HumanoidRootPart","PrimaryPart","Body","Hitbox","Root","Main"}
    for _, n in ipairs(candidates) do
        local part = model:FindFirstChild(n)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    for _, d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

-- Remote setup
local function setupAutoAttackRemote()
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
        utils.notify("🌲 Auto Attack", "RequestAttack RemoteFunction found.", 5)
    else
        utils.notify("🌲 Error", "RequestAttack RemoteFunction not found. Farming may not work.", 5)
    end
end

-- Enemy scanning
local function refreshEnemyList(selectedMonsterModels, weatherEventModels, toSahurModels)
    local wantWeather = table.find(selectedMonsterModels, "Weather Events") ~= nil
    local wantSahur = table.find(selectedMonsterModels, "To Sahur") ~= nil

    local weatherEnemies, otherEnemies, sahurEnemies = {}, {}, {}
    local explicitSet = {}
    for _, name in ipairs(selectedMonsterModels) do
        if name ~= "Weather Events" and name ~= "To Sahur" then
            explicitSet[name:lower()] = true
        end
    end

    local function isIn(list, lname)
        for _, n in ipairs(list) do
            if lname == n:lower() then return true end
        end
        return false
    end

    for _, node in ipairs(Workspace:GetDescendants()) do
        if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
            local h = node:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                local lname = node.Name:lower()
                local isWeather = wantWeather and isIn(weatherEventModels, lname)
                local isExplicit = explicitSet[lname] == true
                local isSahur = wantSahur and isIn(toSahurModels, lname)
                if isWeather then
                    table.insert(weatherEnemies, node)
                elseif isExplicit then
                    table.insert(otherEnemies, node)
                elseif isSahur then
                    table.insert(sahurEnemies, node)
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

-- Farming loop
local function autoFarmLoop(player, selectedMonsterModels, weatherEventModels, toSahurModels)
    if not autoAttackRemote then
        utils.notify("🌲 Error", "RequestAttack RemoteFunction not set.", 5)
        return
    end

    while autoFarmEnabled do
        local character = waitForCharacter(player)
        if not character or not character:FindFirstChild("HumanoidRootPart") then
            task.wait(1)
            continue
        end

        local enemies = refreshEnemyList(selectedMonsterModels, weatherEventModels, toSahurModels)
        if #enemies == 0 then
            if currentTargetLabel then currentTargetLabel.Text = "Current Target: None" end
            task.wait(0.5)
            continue
        end

        for _, enemy in ipairs(enemies) do
            if not autoFarmEnabled then
                if currentTargetLabel then currentTargetLabel.Text = "Current Target: None" end
                return
            end
            local humanoid = enemy:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then continue end

            -- Teleport near enemy
            local targetPart = findBasePart(enemy)
            if not targetPart then continue end
            local targetCF = targetPart.CFrame * CFrame.new(0, 20, 0)
            if not isValidCFrame(targetCF) then continue end

            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then hrp.CFrame = targetCF end

            if currentTargetLabel then
                currentTargetLabel.Text = "Current Target: " .. enemy.Name
            end

            -- Attack loop
            while autoFarmEnabled and enemy.Parent and humanoid and humanoid.Health > 0 do
                local hrp = enemy:FindFirstChild("HumanoidRootPart")
                if hrp then
                    autoAttackRemote:InvokeServer(hrp.CFrame)
                end
                task.wait(0.1)
            end

            if currentTargetLabel then
                currentTargetLabel.Text = "Current Target: None"
            end
        end
        task.wait(0.5)
    end
end

-- Public API
local M = {}

function M.setTargetLabel(label)
    currentTargetLabel = label
end

function M.toggleFarm(flag, player, selectedMonsterModels, weatherEventModels, toSahurModels)
    autoFarmEnabled = flag
    if autoFarmEnabled then
        utils.notify("🌲 Auto-Farm", "Enabled", 4)
        setupAutoAttackRemote()
        task.spawn(function()
            autoFarmLoop(player, selectedMonsterModels, weatherEventModels, toSahurModels)
        end)
    else
        utils.notify("🌲 Auto-Farm", "Disabled", 4)
        for _, c in ipairs(spawnConnections) do
            if c then c:Disconnect() end
        end
        table.clear(spawnConnections)
    end
end

return M
