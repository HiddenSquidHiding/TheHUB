-- brainrot_dungeon_rayfield.lua
-- WoodzHUB • Brainrot Evolutions Dungeons (Place ID locked) + Rayfield controls
-- No auto-start. Use toggles in the Rayfield tab.

local TARGET_PLACE_ID = 90608986169653  -- ✅ your dungeon place id

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

-- Bail if wrong place
if game.PlaceId ~= TARGET_PLACE_ID then
  warn(("[WoodzHUB/Dungeon] Wrong place (%s) — expecting %s. Not loading."):format(game.PlaceId, TARGET_PLACE_ID))
  return
end

-- ========= Small helpers =========
local function waitForLocalPlayer(timeoutSec)
  local t0 = tick()
  local lp = Players.LocalPlayer
  if lp then return lp end
  repeat
    task.wait(0.05)
    lp = Players.LocalPlayer
    if timeoutSec and tick() - t0 > timeoutSec then return nil end
  until lp
  return lp
end

local function waitChild(parent, name, timeout)
  if not parent then return nil end
  local t0 = tick()
  local obj = parent:FindFirstChild(name)
  while not obj do
    if timeout and (tick() - t0) >= timeout then return nil end
    task.wait(0.05)
    if not parent or typeof(parent) ~= "Instance" then return nil end
    obj = parent:FindFirstChild(name)
  end
  return obj
end

local function chainFind(parent, names, timeoutEach)
  local cur = parent
  for _, n in ipairs(names) do
    cur = waitChild(cur, n, timeoutEach)
    if not cur then return nil end
  end
  return cur
end

local function isValidCFrame(cf)
  if not cf then return false end
  local p = cf.Position
  return p.X == p.X and p.Y == p.Y and p.Z == p.Z
     and math.abs(p.X) < 10000 and math.abs(p.Y) < 10000 and math.abs(p.Z) < 10000
end

local function findBasePart(model)
  if not model then return nil end
  for _, n in ipairs({"HumanoidRootPart","PrimaryPart","Body","Hitbox","Root","Main"}) do
    local part = model:FindFirstChild(n)
    if part and part:IsA("BasePart") then return part end
  end
  for _, d in ipairs(model:GetDescendants()) do
    if d:IsA("BasePart") then return d end
  end
  return nil
end

local function waitForCharacter(plr)
  plr = plr or Players.LocalPlayer
  while not plr.Character
    or not plr.Character:FindFirstChild("HumanoidRootPart")
    or not plr.Character:FindFirstChildOfClass("Humanoid") do
    plr.CharacterAdded:Wait()
    task.wait(0.05)
  end
  return plr.Character
end

-- ========= Dungeon discovery / remotes =========
local player = waitForLocalPlayer(30)
if not player then
  warn("[WoodzHUB/Dungeon] No LocalPlayer — aborting.")
  return
end

local function findRoomsFolder()
  local function scan(node)
    if node:IsA("Folder") and node.Name == "Rooms" then return node end
    for _, c in ipairs(node:GetChildren()) do
      local r = scan(c)
      if r then return r end
    end
    return nil
  end
  return scan(Workspace)
end

local autoAttackRF -- MonsterService.RF.RequestAttack
local function setupAutoAttackRemote()
  autoAttackRF = nil
  local rf = chainFind(ReplicatedStorage, {"Packages","Knit","Services","MonsterService","RF","RequestAttack"}, 8)
  if rf and rf:IsA("RemoteFunction") then autoAttackRF = rf end
end

local displayResultsRE
local playAgainRF
local function setupDungeonRemotes()
  displayResultsRE = chainFind(ReplicatedStorage, {"Packages","Knit","Services","DungeonService","RE","DisplayResults"}, 8)
  playAgainRF      = chainFind(ReplicatedStorage, {"Packages","Knit","Services","DungeonService","RF","PlayAgainPressed"}, 8)
end

-- ========= Core logic (no GUI; UI will call into this) =========
local state = {
  running = true,
  autoAttack = false,
  autoReplay = false,
  displayTriggered = false,
}

local function getEnemiesInRoom(roomsFolder, roomNumber)
  local t = {}
  if not roomsFolder then return t end
  local room = roomsFolder:FindFirstChild(tostring(roomNumber))
  local enemiesFolder = room and room:FindFirstChild("Enemies")
  if enemiesFolder then
    for _, m in ipairs(enemiesFolder:GetChildren()) do
      if m:IsA("Model") and not Players:GetPlayerFromCharacter(m) then
        local h = m:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 then table.insert(t, m) end
      end
    end
  end
  return t
end

local function waitDoorOpens(roomsFolder)
  if not roomsFolder then return false end
  local room1 = roomsFolder:FindFirstChild("1")
  local door  = room1 and room1:FindFirstChild("Door")
  if not door then return true end
  local t0 = tick()
  while door and door.Parent and state.running and state.autoAttack and (tick() - t0) < 30 do
    door = room1:FindFirstChild("Door")
    task.wait(0.4)
  end
  return (door == nil) or (not door.Parent)
end

local function areAllRoomsClear(roomsFolder)
  for i = 1, 6 do
    if #getEnemiesInRoom(roomsFolder, i) > 0 then return false end
  end
  return true
end

-- Attack loop (room-by-room)
local function runAutoDungeon()
  setupAutoAttackRemote()
  setupDungeonRemotes()
  local rooms = findRoomsFolder()
  if not rooms or not autoAttackRF then
    warn("[WoodzHUB/Dungeon] rooms or RequestAttack not found yet.")
    return
  end

  -- listen to DisplayResults once per run
  if displayResultsRE and not displayResultsRE.__woodz_conn then
    displayResultsRE.__woodz_conn = displayResultsRE.OnClientEvent:Connect(function()
      state.displayTriggered = true
      if state.autoAttack and state.autoReplay and playAgainRF then
        pcall(function() playAgainRF:InvokeServer() end)
      end
    end)
  end

  while state.running and state.autoAttack do
    if not waitDoorOpens(rooms) then break end

    state.displayTriggered = false
    local character = waitForCharacter(player)
    local hrp = character:FindFirstChild("HumanoidRootPart")

    for roomNum = 1, 6 do
      if not state.running or not state.autoAttack then break end
      local enemies = getEnemiesInRoom(rooms, roomNum)
      if #enemies == 0 then continue end

      for _, enemy in ipairs(enemies) do
        if not state.running or not state.autoAttack then break end
        if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

        local hum = enemy:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end

        -- Initial hop above pivot
        local okPivot, pivot = pcall(function() return enemy:GetPivot() end)
        if not okPivot or not isValidCFrame(pivot) then continue end
        local hoverCF = pivot * CFrame.new(0, 20, 0)

        for _ = 1, 3 do
          local ok = pcall(function()
            local ch = player.Character
            if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") and ch.Humanoid.Health > 0 then
              ch.HumanoidRootPart.CFrame = hoverCF
            end
          end)
          if ok then break end
          task.wait(0.25)
        end

        task.wait(0.15)

        local bp = Instance.new("BodyPosition")
        bp.Name = "WoodzHub_DungeonHover"
        bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bp.D = 1000; bp.P = 10000
        bp.Parent = (player.Character and player.Character:FindFirstChild("HumanoidRootPart")) or hrp

        while state.running and state.autoAttack and enemy.Parent and hum and hum.Health > 0 do
          -- keep hovering above its current part
          local base = findBasePart(enemy)
          if not base then break end
          local cf = base.CFrame * CFrame.new(0, 20, 0)
          if not isValidCFrame(cf) then break end
          bp.Position = cf.Position

          local eHRP = enemy:FindFirstChild("HumanoidRootPart")
          if eHRP and autoAttackRF then
            pcall(function() autoAttackRF:InvokeServer(eHRP.CFrame) end)
          end

          task.wait(0.05)
        end

        if bp then bp:Destroy() end
      end
    end

    if state.running and state.autoAttack and state.autoReplay then
      -- If all rooms clear and DisplayResults fired, we'll loop again automatically via PlayAgainPressed in the RE listener.
      -- Small settle wait:
      task.wait(0.2)
    end
  end
end

-- ========= Rayfield UI =========
local Rayfield = nil
do
  local ok, rf = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
  end)
  if ok and rf then Rayfield = rf else warn("[WoodzHUB/Dungeon] Rayfield failed to load.") end
end
if not Rayfield then return end

-- Try to reuse an existing main window if you keep one in a global; else create one
local Window = rawget(_G, "WOODZHUB_RAYFIELD_WINDOW")
if not Window then
  Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — Rayfield",
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Dungeon Module",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
  })
  _G.WOODZHUB_RAYFIELD_WINDOW = Window
end

local Tab = Window:CreateTab("Dungeon")

Tab:CreateParagraph({ Title = "Brainrot Dungeons", Content = "Auto-attack + Auto Replay.\nPlace-locked: "..tostring(TARGET_PLACE_ID) })

local statusLabel = Tab:CreateLabel("Status: Idle")

local function setStatus(txt)
  pcall(function() statusLabel:Set(txt) end)
end

local toggleAuto = Tab:CreateToggle({
  Name = "Auto-Attack Dungeons",
  CurrentValue = false,
  Flag = "woodz_dungeon_auto",
  Callback = function(on)
    state.autoAttack = on and true or false
    if state.autoAttack then
      setStatus("Running…")
      task.spawn(function()
        -- protect loop; show end status if it finishes
        local ok, err = pcall(runAutoDungeon)
        if not ok then warn("[WoodzHUB/Dungeon] loop error:", err) end
        if state.autoAttack == false then
          setStatus("Stopped")
        else
          setStatus("Idle (loop ended)")
        end
      end)
    else
      setStatus("Stopped")
    end
  end,
})

local toggleReplay = Tab:CreateToggle({
  Name = "Auto “Play Again” at Results",
  CurrentValue = false,
  Flag = "woodz_dungeon_replay",
  Callback = function(on)
    state.autoReplay = on and true or false
  end,
})

-- quick tools
Tab:CreateButton({
  Name = "Re-Detect Dungeon Remotes",
  Callback = function()
    setupAutoAttackRemote()
    setupDungeonRemotes()
    local ok = autoAttackRF and displayResultsRE
    setStatus(ok and "Remotes ready" or "Remotes not found yet")
  end
})

-- Cleanup on character respawn / exit
player.CharacterAdded:Connect(function()
  if state.autoAttack then
    -- small delay to let character load
    task.wait(1.0)
    setStatus("Rejoining loop…")
    task.spawn(runAutoDungeon)
  end
end)

-- Try prime remotes once for user feedback
setupAutoAttackRemote()
setupDungeonRemotes()
setStatus((autoAttackRF and displayResultsRE) and "Ready" or "Waiting for remotes…")
