-- farm.lua
-- Auto-farm with smooth constraint-based follow.
-- Robust to missing utils/data modules; safe fallbacks included.

----------------------------------------------------------------------
-- Safe utils
----------------------------------------------------------------------
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  -- Fallbacks
  local Players = game:GetService("Players")
  return {
    notify = function(title, msg) print(("[%s] %s"):format(title, msg)) end,
    waitForCharacter = function()
      local plr = Players.LocalPlayer
      while true do
        local ch = plr.Character
        if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
          return ch
        end
        plr.CharacterAdded:Wait()
        task.wait()
      end
    end,
  }
end
local utils = getUtils()

-----------------------------------------------------------------------
-- Optional data (robust loader + logging)
----------------------------------------------------------------------
local function tryLoadDataMonsters()
  -- 1) Sibling require (works if your loader virtualizes siblings)
  local ok1, tbl1 = pcall(function() return require(script.Parent.data_monsters) end)
  if ok1 and type(tbl1) == "table" then return tbl1, "require(script.Parent.data_monsters)" end

  -- 2) Global (let init.lua set _G.WOODZ_DATA_MONSTERS)
  if type(rawget(_G, "WOODZ_DATA_MONSTERS")) == "table" then
    return _G.WOODZ_DATA_MONSTERS, "_G.WOODZ_DATA_MONSTERS"
  end

  -- 3) HTTP fallback via base URL (let init.lua set _G.WOODZ_BASE_URL)
  local base = rawget(_G, "WOODZ_BASE_URL")
  if type(base) == "string" and base ~= "" then
    local url = (base:sub(-1) == "/") and (base .. "data_monsters.lua") or (base .. "/data_monsters.lua")
    local ok2, src = pcall(game.HttpGet, game, url)
    if ok2 and type(src) == "string" and #src > 0 then
      local fn = loadstring(src, "=data_monsters.lua")
      if fn then
        local ok3, tbl3 = pcall(fn)
        if ok3 and type(tbl3) == "table" then return tbl3, "http:" .. url end
      end
    end
  end

  -- 4) Nothing found
  return nil, nil
end

local data, dataSource = tryLoadDataMonsters()
local WEATHER_NAMES = (data and data.weatherEventModels) or {}
local SAHUR_NAMES   = (data and data.toSahurModels)     or {}

-- Log what we actually have (so you can see counts in console)
pcall(function()
  local w = #WEATHER_NAMES
  local s = #SAHUR_NAMES
  local src = dataSource or "none"
  utils.notify("🌲 Data", ("data_monsters: weather=%d, sahur=%d (via %s)"):format(w, s, src), 4)
end)


----------------------------------------------------------------------
-- Services & locals
----------------------------------------------------------------------
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player = Players.LocalPlayer

local M = {}

----------------------------------------------------------------------
-- Config
----------------------------------------------------------------------
local WEATHER_TIMEOUT               = 30    -- seconds (Weather Events only)
local NON_WEATHER_STALL_TIMEOUT     = 3     -- seconds without HP decreasing → skip (disabled in FastLevel)
local ABOVE_OFFSET                  = Vector3.new(0, 20, 0)

-- Weather preemption config
local WEATHER_TTK_LIMIT             = 5.0   -- seconds — only switch if estimated TTK ≤ this
local WEATHER_PROBE_TIME            = 0.35  -- seconds to sample DPS on a weather mob
local WEATHER_PREEMPT_POLL          = 0.2   -- seconds between preemption checks during a fight

-- Constraint tuning
local POS_RESPONSIVENESS            = 200
local POS_MAX_FORCE                 = 1e9
local ORI_RESPONSIVENESS            = 200
local ORI_MAX_TORQUE                = 1e9

----------------------------------------------------------------------
-- Selection state
----------------------------------------------------------------------
local allMonsterModels = {}
local filteredMonsterModels = {}
local selectedMonsterModels = {}  -- start empty; UI controls it

local function inListInsensitive(list, name)
  if not name then return false end
  local lname = string.lower(name)
  for _, n in ipairs(list) do
    if string.lower(n) == lname then return true end
  end
  return false
end

local function isWeatherName(name) return inListInsensitive(WEATHER_NAMES, name) end
local function isSahurName(name)   return inListInsensitive(SAHUR_NAMES, name)   end

local function isWeatherSelected()
  return table.find(selectedMonsterModels, "Weather Events") ~= nil
end

-- API for UI
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
-- Monster discovery / filtering
----------------------------------------------------------------------
local function pushUnique(valid, name)
  if not name then return end
  for _, v in ipairs(valid) do if v == name then return end end
  -- Don't inject raw weather/sahur names directly into the explicit list
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

  -- Optional extras from data.forcedMonsters
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
-- Enemy prioritization (ONLY what you selected)
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
        local lname = string.lower(node.Name)
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
-- Remotes
----------------------------------------------------------------------
local autoAttackRemote = nil
function M.setupAutoAttackRemote()
  autoAttackRemote = nil
  -- Try standard Knit path
  local ok, remote = pcall(function()
    local pkg = ReplicatedStorage:FindFirstChild("Packages")
    local knit = pkg and pkg:FindFirstChild("Knit")
    local svc  = knit and knit:FindFirstChild("Services")
    local mon  = svc and svc:FindFirstChild("MonsterService")
    local rf   = mon and mon:FindFirstChild("RF")
    return rf and rf:FindFirstChild("RequestAttack")
  end)
  if ok and remote and remote:IsA("RemoteFunction") then
    autoAttackRemote = remote
    utils.notify("🌲 Auto Attack", "RequestAttack ready.", 3)
    return
  end
  -- Fallback scan
  for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
    if d:IsA("RemoteFunction") and d.Name == "RequestAttack" then
      autoAttackRemote = d
      utils.notify("🌲 Auto Attack", "RequestAttack found (fallback).", 3)
      return
    end
  end
  utils.notify("🌲 Auto Attack", "RequestAttack NOT found; will still move but cannot attack.", 5)
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
  for _, n in ipairs({ "HumanoidRootPart","PrimaryPart","Body","Hitbox","Root","Main" }) do
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
  local ch = player.Character
  if not ch then return end
  local hum = ch:FindFirstChildOfClass("Humanoid")
  local hrp = ch:FindFirstChild("HumanoidRootPart")
  if not hum or not hrp then return end
  zeroVel(hrp)
  local oldPS = hum.PlatformStand
  hum.PlatformStand = true
  ch:PivotTo(cf)
  RunService.Heartbeat:Wait()
  hum.PlatformStand = oldPS
end

----------------------------------------------------------------------
-- Smooth follow via constraints (per fight)
----------------------------------------------------------------------
local function makeSmoothFollow(hrp)
  local a0 = Instance.new("Attachment")
  a0.Name = "WoodzHub_A0"
  a0.Parent = hrp

  local ap = Instance.new("AlignPosition")
  ap.Name = "WoodzHub_AP"
  ap.Mode = Enum.PositionAlignmentMode.OneAttachment
  ap.Attachment0 = a0
  ap.ApplyAtCenterOfMass = true
  ap.MaxForce = POS_MAX_FORCE
  ap.Responsiveness = POS_RESPONSIVENESS
  ap.RigidityEnabled = false
  ap.Parent = hrp

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
    ap:Destroy(); ao:Destroy(); a0:Destroy()
  end
  return ctl
end

----------------------------------------------------------------------
-- Weather helpers
----------------------------------------------------------------------
local function findWeatherEnemies()
  if not isWeatherSelected() then return {} end
  local out = {}
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 and isWeatherName(node.Name) then
        table.insert(out, node)
      end
    end
  end
  return out
end

local function pickLowestHPWeather()
  local list = findWeatherEnemies()
  local best, bestHP = nil, math.huge
  for _, m in ipairs(list) do
    local h = m:FindFirstChildOfClass("Humanoid")
    if h and h.Health > 0 and h.Health < bestHP then
      best, bestHP = m, h.Health
    end
  end
  return best
end

-- Weather TTK estimator
local function estimateTTK(enemy, probeTime)
  if not enemy or not enemy.Parent then return math.huge end
  local hum = enemy:FindFirstChildOfClass("Humanoid")
  if not hum or hum.Health <= 0 then return math.huge end
  local part = enemy:FindFirstChild("HumanoidRootPart") or findBasePart(enemy)
  if not part or not autoAttackRemote then return math.huge end

  local h0 = hum.Health
  local t0 = tick()
  local tEnd = t0 + (probeTime or WEATHER_PROBE_TIME)

  while tick() < tEnd and enemy.Parent and hum.Health > 0 do
    pcall(function() autoAttackRemote:InvokeServer(part.CFrame) end)
    RunService.Heartbeat:Wait()
  end

  local elapsed = math.max(0.05, tick() - t0)
  local h1 = hum.Health
  local dps = (h0 - h1) / elapsed
  if dps <= 0 then return math.huge end

  return h1 / dps
end

----------------------------------------------------------------------
-- FastLevel flag (set by app.lua)
----------------------------------------------------------------------
local FASTLEVEL_MODE = false
function M.setFastLevelEnabled(on) FASTLEVEL_MODE = on and true or false end

----------------------------------------------------------------------
-- Engagement helpers
----------------------------------------------------------------------
local function calcHoverCF(enemy)
  local part = enemy:FindFirstChild("HumanoidRootPart") or findBasePart(enemy)
  if part then return part.CFrame * CFrame.new(ABOVE_OFFSET) end
  local okPivot, pcf = pcall(function() return enemy:GetPivot() end)
  return (okPivot and isValidCFrame(pcf)) and (pcf * CFrame.new(ABOVE_OFFSET)) or nil
end

local function beginEngagement(enemy)
  local targetCF = calcHoverCF(enemy)
  if not targetCF then return nil, nil end
  hardTeleport(targetCF)

  local character = player.Character
  local hum = character and character:FindFirstChildOfClass("Humanoid")
  local hrp = character and character:FindFirstChild("HumanoidRootPart")
  if not character or not hum or not hrp then return nil, nil end

  local oldPS = hum.PlatformStand
  hum.PlatformStand = true
  zeroVel(hrp)
  local ctl = makeSmoothFollow(hrp)
  return ctl, oldPS
end

----------------------------------------------------------------------
-- Public: run auto farm
----------------------------------------------------------------------
function M.runAutoFarm(getEnabled, setTargetText)
  local function label(text)
    if setTargetText then pcall(function() setTargetText(text) end) end
  end

  while getEnabled() do
    local character = utils.waitForCharacter()
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
      label("Current Target: None")
      task.wait(0.05)
      continue
    end

    -- Build target list strictly from what the user selected
    local enemies = refreshEnemyList()
    if #enemies == 0 then
      label("Current Target: None")
      task.wait(0.1)
      continue
    end

    for _, enemy in ipairs(enemies) do
      if not getEnabled() then break end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

      local eh = enemy:FindFirstChildOfClass("Humanoid")
      if not eh or eh.Health <= 0 then continue end

      -- Enter engagement (teleport + constraints)
      local ctl, oldPS = beginEngagement(enemy)
      if not ctl then continue end

      label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

      -- Timers/state
      local isWeather   = isWeatherName(enemy.Name)
      local lastHealth  = eh.Health
      local lastDropAt  = tick()
      local startedAt   = tick()
      local lastWeatherPoll = 0

      local hcConn = eh.HealthChanged:Connect(function(h)
        label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
        if h < lastHealth then lastDropAt = tick() end
        lastHealth = h
      end)

      -- Fight loop
      while getEnabled() and enemy.Parent and eh.Health > 0 do
        -- Death recovery -> re-engage SAME enemy
        local ch = player.Character
        local myHum = ch and ch:FindFirstChildOfClass("Humanoid")
        local myHRP = ch and ch:FindFirstChild("HumanoidRootPart")
        if (not ch) or (not myHum) or (myHum.Health <= 0) or (not myHRP) then
          if ctl then pcall(function() ctl:destroy() end) end
          label(("Respawning… returning to %s"):format(enemy.Name))
          utils.waitForCharacter()
          if not enemy.Parent or eh.Health <= 0 then break end
          ctl, oldPS = beginEngagement(enemy)
          if not ctl then break end
        end

        -- Follow & attack
        local partNow = findBasePart(enemy)
        if not partNow then
          local t0 = tick()
          repeat
            RunService.Heartbeat:Wait()
            partNow = findBasePart(enemy)
          until partNow or (tick() - t0) > 1 or not enemy.Parent or eh.Health <= 0
          if not partNow then break end
        end
        local desired = partNow.CFrame * CFrame.new(ABOVE_OFFSET)
        ctl:setGoal(desired)

        local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
        if hrpTarget and autoAttackRemote then
          pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
        end

        local now = tick()

        -- Weather timeout
        if isWeather and (now - startedAt) > WEATHER_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Weather Event timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT), 3)
          break
        end

        -- Stall detection (disabled for FastLevel on non-weather)
        if (not isWeather) and (not FASTLEVEL_MODE) and ((now - lastDropAt) > NON_WEATHER_STALL_TIMEOUT) then
          utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(enemy.Name, NON_WEATHER_STALL_TIMEOUT), 3)
          break
        end

        -- Weather preemption (respect 5s TTK cap). Only triggers if you selected Weather.
        if not isWeather and (now - lastWeatherPoll) >= WEATHER_PREEMPT_POLL and isWeatherSelected() then
          lastWeatherPoll = now
          local candidate = pickLowestHPWeather()
          if candidate and candidate ~= enemy then
            local ttk = estimateTTK(candidate, WEATHER_PROBE_TIME)
            if ttk <= WEATHER_TTK_LIMIT then
              utils.notify("🌲 Auto-Farm", ("Weather target detected (TTK≈%0.1fs) — switching."):format(ttk), 2)
              break
            end
          end
        end

        RunService.Heartbeat:Wait()
      end

      if hcConn then hcConn:Disconnect() end
      label("Current Target: None")

      -- Cleanup + restore
      if ctl then pcall(function() ctl:destroy() end) end
      local curChar = player.Character
      local curHum  = curChar and curChar:FindFirstChildOfClass("Humanoid")
      local curHRP  = curChar and curChar:FindFirstChild("HumanoidRootPart")
      if curHum and curHRP and curHum.Parent then
        curHum.PlatformStand = false
        zeroVel(curHRP)
      end

      RunService.Heartbeat:Wait()
    end

    RunService.Heartbeat:Wait()
  end
end

return M
