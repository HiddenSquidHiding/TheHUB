-- farm.lua
-- Auto-farm with hard-lock hover (no glide).
-- Weather Events: 30s timeout. Non-weather: skip if HP doesn't drop for 3s.

-- 🔧 Utils + constants
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[farm.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading farm.lua")
end

local utils      = getUtils()
local constants  = require(script.Parent.constants)

local Players            = game:GetService("Players")
local Workspace          = game:GetService("Workspace")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")

local player = Players.LocalPlayer

local M = {}

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local WEATHER_TIMEOUT = 30               -- seconds (Weather Events only)
local NON_WEATHER_STALL_TIMEOUT = 3      -- seconds without HP decreasing → skip

----------------------------------------------------------------------
-- Selection/filter
----------------------------------------------------------------------
local allMonsterModels = {}
local filteredMonsterModels = {}
local selectedMonsterModels = { "Weather Events" }

local WEATHER_NAMES = constants.weatherEventModels or {}
local SAHUR_NAMES   = constants.toSahurModels or {}

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
  for _, s in ipairs(SAHUR_NAMES) do if s == name then return end end
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

  if constants.forcedMonsters then
    for _, nm in ipairs(constants.forcedMonsters) do pushUnique(valid, nm) end
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
-- Helpers (no BodyPosition; we hard-lock with Anchored + CFrame)
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
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
  end)
end

-- Glide-free hop to cf: zero vel, PlatformStand snap, then resume
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
-- Public: run auto farm (Weather timeout + Non-weather stall skip + no glide)
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

      -- Plan a target position first
      local okPivot, pcf = pcall(function() return enemy:GetPivot() end)
      local targetCF = (okPivot and isValidCFrame(pcf)) and (pcf * CFrame.new(0, 20, 0)) or nil
      if not targetCF then continue end

      -- Instant hop (no glide)
      hardTeleport(targetCF)

      -- Reacquire after hop (in case of morph/streaming)
      character = player.Character
      hum = character and character:FindFirstChildOfClass("Humanoid")
      hrp = character and character:FindFirstChild("HumanoidRootPart")
      if not character or not hum or not hrp then continue end

      -- Anchor to kill any residual drift while attacking
      local prevAnchored = hrp.Anchored
      hrp.Anchored = true
      zeroVel(hrp)

      -- Resolve a concrete part to follow
      local targetPart = findBasePart(enemy)
      if not targetPart then
        local t0 = tick()
        repeat
          task.wait(0.02)
          targetPart = findBasePart(enemy)
        until targetPart or (tick() - t0) > 2 or not enemy.Parent or eh.Health <= 0
      end
      if not targetPart then
        hrp.Anchored = prevAnchored
        continue
      end

      label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

      -- Health tracking for stall detection
      local isWeather = isWeatherName(enemy.Name)
      local lastHealth = eh.Health
      local lastDropAt = tick()
      local startedAt = tick()

      local hcConn = eh.HealthChanged:Connect(function(h)
        label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
        if h < lastHealth then lastDropAt = tick() end
        lastHealth = h
      end)

      while flagGetter() and enemy.Parent and eh.Health > 0 do
        -- follow above the target without physics
        local partNow = findBasePart(enemy) or targetPart
        if partNow then
          local cfNow = partNow.CFrame * CFrame.new(0, 20, 0)
          if isValidCFrame(cfNow) then
            -- Directly set HRP CFrame while Anchored → zero glide
            pcall(function()
              -- re-acquire HRP if morph replaced it
              local curHRP = character:FindFirstChild("HumanoidRootPart")
              if curHRP ~= hrp and curHRP then
                hrp = curHRP
                hrp.Anchored = true
                zeroVel(hrp)
              end
              hrp.CFrame = cfNow
            end)
          end
        end

        -- attack
        local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
        if hrpTarget and autoAttackRemote then
          pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
        end

        -- Weather-only timeout
        if isWeather and (tick() - startedAt) > WEATHER_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Weather Event timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT), 3)
          break
        end

        -- Non-weather stall detection
        if not isWeather and (tick() - lastDropAt) > NON_WEATHER_STALL_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(enemy.Name, NON_WEATHER_STALL_TIMEOUT), 3)
          break
        end

        task.wait(0.06)
      end

      if hcConn then hcConn:Disconnect() end
      label("Current Target: None")

      -- Unanchor to return control between targets
      if hrp and hrp.Parent then
        hrp.Anchored = prevAnchored
        zeroVel(hrp)
      end

      task.wait(0.03)
    end

    task.wait(0.06)
  end
end

return M
