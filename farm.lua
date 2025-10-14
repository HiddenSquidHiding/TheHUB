-- farm.lua
-- Auto-farm with smooth follow.
-- Requirements from your requests:
--  • Weather models are always prioritized and will pre-empt current target.
--  • Skip a weather target if Estimated Time To Kill (ETTK) > 5 seconds.
--  • "Fast Level 70+" mode ignores the 3-second no-HP-change skip rule.
--  • If you die, teleport straight back to the monster and resume.

-- 🔐 UNIVERSAL SAFE HEADER (drop-in)
local function _safeUtils()
  -- 1) prefer an injected utils (from loader/app)
  local env = (getfenv and getfenv()) or _G
  if env and type(env.__WOODZ_UTILS) == "table" then return env.__WOODZ_UTILS end
  if _G and type(_G.__WOODZ_UTILS) == "table" then return _G.__WOODZ_UTILS end

  -- 2) last-resort shim that never errors
  local StarterGui = game:GetService("StarterGui")
  local Players    = game:GetService("Players")

  local function notify(title, msg, dur)
    dur = dur or 3
    pcall(function()
      StarterGui:SetCore("SendNotification", {
        Title = tostring(title or "WoodzHUB"),
        Text  = tostring(msg or ""),
        Duration = dur,
      })
    end)
    print(("[%s] %s"):format(tostring(title or "WoodzHUB"), tostring(msg or "")))
  end

  local function waitForCharacter()
    local plr = Players.LocalPlayer
    while plr
      and (not plr.Character
           or not plr.Character:FindFirstChild("HumanoidRootPart")
           or not plr.Character:FindFirstChildOfClass("Humanoid")) do
      plr.CharacterAdded:Wait()
      task.wait()
    end
    return plr and plr.Character
  end

  return { notify = notify, waitForCharacter = waitForCharacter }
end

local function getUtils() return _safeUtils() end
local utils = getUtils()

-- ✅ Safe sibling require helper (works even when script.Parent is nil)
-- Use this ONLY when you need to pull another local module; otherwise omit.
local function safeRequireSibling(name, defaultValue)
  -- 1) If loader provides a global hook, try it
  local env = (getfenv and getfenv()) or _G
  local hook = env and env.__WOODZ_REQUIRE
  if type(hook) == "function" then
    local ok, mod = pcall(hook, name)
    if ok and mod ~= nil then return mod end
  end
  -- 2) Try finding an actual ModuleScript already present in memory
  if getloadedmodules then
    for _, m in ipairs(getloadedmodules()) do
      if typeof(m) == "Instance" and m:IsA("ModuleScript") and m.Name == name then
        local ok, mod = pcall(require, m)
        if ok then return mod end
      end
    end
  end
  -- 3) Couldn’t load -> fall back
  return defaultValue
end

local data = safeRequireSibling("data_monsters", {
  weatherEventModels = {},
  toSahurModels = {},
  forcedMonsters = {},
})
local fastlevel = (function() local ok, m = pcall(function() return require(script.Parent.fastlevel) end); return ok and m or {isEnabled=function()return false end, getTargetLabel=function()return "" end} end)()

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
local WEATHER_TIMEOUT               = 30   -- seconds (hard cap safeguard for weather fights)
local NON_WEATHER_STALL_TIMEOUT     = 3    -- seconds without HP decreasing → skip (unless fastlevel)
local ABOVE_OFFSET                  = Vector3.new(0, 20, 0)
local ETTK_WEATHER_CUTOFF           = 5.0  -- seconds (skip weather if ETTK > this)

-- Constraint tuning (smooth, snappy follow)
local POS_RESPONSIVENESS            = 200
local POS_MAX_FORCE                 = 1e9
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
-- Force fastlevel override (from app toggle)
----------------------------------------------------------------------
local fastLevelFlag = false
function M.setFastLevelEnabled(on)
  fastLevelFlag = on and true or false
  if on then
    -- shrink selection to only the Sahur string
    local only = fastlevel.getTargetLabel()
    selectedMonsterModels = { only }
  end
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

  -- include forced names if you keep them
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
-- Enemy prioritization with weather pre-empt
----------------------------------------------------------------------
local function collectEnemiesBuckets()
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
  return weather, explicit, sahur
end

-- returned list has weather first (and will pre-empt within loop)
local function refreshEnemyList()
  local weather, explicit, sahur = collectEnemiesBuckets()
  local out = {}
  for _, e in ipairs(weather)  do table.insert(out, e) end
  for _, e in ipairs(explicit) do table.insert(out, e) end
  for _, e in ipairs(sahur)    do table.insert(out, e) end
  return out, (#weather > 0)
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
-- Smooth follow via constraints
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
-- ETTK estimator (simple rolling DPS over last few samples)
----------------------------------------------------------------------
local function makeETTK()
  local lastH, lastT = nil, nil
  local dps, samples = 0, 0

  return {
    reset = function() lastH, lastT, dps, samples = nil, nil, 0, 0 end,
    push  = function(hp)
      local t = tick()
      if lastH and lastT and hp <= lastH then
        local dh = (lastH - hp)
        local dt = math.max(1e-3, t - lastT)
        local inst = dh / dt
        -- EMA towards last 6 samples
        local alpha = 0.25
        dps = (samples == 0) and inst or (dps * (1-alpha) + inst * alpha)
        samples = math.min(6, samples + 1)
      end
      lastH, lastT = hp, t
      return (dps > 0) and (hp / dps) or math.huge
    end,
  }
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

  local lastEnemy -- to support immediate return after death

  while flagGetter() do
    local character = utils.waitForCharacter()
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
      label("Current Target: None")
      task.wait(0.05)
      continue
    end

    -- if we just respawned and lastEnemy still alive, jump back immediately
    if lastEnemy and lastEnemy.Parent then
      local part = findBasePart(lastEnemy)
      if part then hardTeleport(part.CFrame * CFrame.new(ABOVE_OFFSET)) end
    end

    local enemies, hasWeather = refreshEnemyList()
    if #enemies == 0 then
      label("Current Target: None")
      task.wait(0.1)
      continue
    end

    -- Weather pre-empt: we iterate but keep checking for *new* weather during fight
    for _, enemy in ipairs(enemies) do
      if not flagGetter() then break end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

      local eh = enemy:FindFirstChildOfClass("Humanoid")
      if not eh or eh.Health <= 0 then continue end

      -- Skip non-selected unless fastlevel locked to Sahur
      if fastLevelFlag then
        if string.lower(enemy.Name) ~= string.lower(fastlevel.getTargetLabel()) then
          continue
        end
      end

      -- initial hop
      local okPivot, pcf = pcall(function() return enemy:GetPivot() end)
      local targetCF = (okPivot and isValidCFrame(pcf)) and (pcf * CFrame.new(ABOVE_OFFSET)) or nil
      if not targetCF then continue end
      hardTeleport(targetCF)

      -- reacquire bits after hop
      character = player.Character
      hum = character and character:FindFirstChildOfClass("Humanoid")
      hrp = character and character:FindFirstChild("HumanoidRootPart")
      if not character or not hum or not hrp then continue end

      local oldPS = hum.PlatformStand
      hum.PlatformStand = true
      zeroVel(hrp)

      local ctl = makeSmoothFollow(hrp)

      -- target base part resolution (with short wait)
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

      lastEnemy = enemy
      label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

      -- stall + weather timers + ETTK
      local isWeather   = isWeatherName(enemy.Name)
      local lastHealth  = eh.Health
      local lastDropAt  = tick()
      local startedAt   = tick()
      local ettk        = makeETTK()
      ettk.reset()

      local hcConn = eh.HealthChanged:Connect(function(h)
        label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
        if h < lastHealth then lastDropAt = tick() end
        lastHealth = h
      end)

      -- fight loop
      while flagGetter() and enemy.Parent and eh.Health > 0 do
        -- Pre-empt check: if ANY weather shows up in the world and this is not weather, break immediately
        if not isWeather then
          local _, newHasWeather = refreshEnemyList()
          if newHasWeather then
            utils.notify("🌲 Auto-Farm", "Weather appeared — switching target.", 3)
            break
          end
        end

        -- desired pose above enemy (smooth via constraints)
        local partNow = findBasePart(enemy) or targetPart
        if not partNow then break end
        local desired = partNow.CFrame * CFrame.new(ABOVE_OFFSET)
        ctl:setGoal(desired)

        -- attack
        local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
        if hrpTarget and autoAttackRemote then
          pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
        end

        -- Weather-only: ETTK cut-off (skip if too tanky >5s)
        if isWeather then
          local tEst = ettk.push(eh.Health)
          if tEst and tEst > ETTK_WEATHER_CUTOFF then
            utils.notify("🌲 Auto-Farm", ("Skipping %s (ETTK %.1fs > %.1fs)"):format(enemy.Name, tEst, ETTK_WEATHER_CUTOFF), 3)
            break
          end
        end

        -- Weather hard timeout (safety valve)
        if isWeather and (tick() - startedAt) > WEATHER_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Weather timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT), 3)
          break
        end

        -- Non-weather stall detection (ignored in fastlevel mode)
        if (not isWeather) and (not fastLevelFlag) and (tick() - lastDropAt) > NON_WEATHER_STALL_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(enemy.Name, NON_WEATHER_STALL_TIMEOUT), 3)
          break
        end

        -- If we died, immediately re-TP back to enemy
        if hum.Health <= 0 then
          local part = findBasePart(enemy)
          if part then
            -- Wait for respawn
            utils.waitForCharacter()
            local ch = player.Character
            local myH = ch and ch:FindFirstChildOfClass("Humanoid")
            local myHRP = ch and ch:FindFirstChild("HumanoidRootPart")
            if myH and myHRP and myH.Health > 0 then
              hardTeleport(part.CFrame * CFrame.new(ABOVE_OFFSET))
              -- refresh locals to the new humanoid/HRP
              hum = myH; hrp = myHRP
            end
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
