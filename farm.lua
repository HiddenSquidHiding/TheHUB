-- farm.lua
-- Auto-farm with Weather/To Sahur groups from data_monsters.lua (fallback to constants.lua).
-- Loader-safe (script may be a table). Self-contained utils fallback for toasts + waitForCharacter.

-- ========= Services =========
local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local player            = Players.LocalPlayer

-- ========= Utils (injected or fallback) =========
local function buildUtilsFallback()
  local COLOR_BG_DARK = Color3.fromRGB(30,30,30)
  local COLOR_BG_MED  = Color3.fromRGB(50,50,50)
  local COLOR_WHITE   = Color3.fromRGB(255,255,255)

  local function safePlayerGui()
    local ok, pg = pcall(function() return player:WaitForChild("PlayerGui", 5) end)
    return ok and pg or nil
  end

  local function notify(title, content, duration)
    local pg = safePlayerGui()
    if not pg then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "WoodzNotify"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 2_000_000_000
    gui.Parent = pg

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 100)
    frame.Position = UDim2.new(1, -310, 0, 10)
    frame.BackgroundColor3 = COLOR_BG_DARK
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, 0, 0, 30)
    titleLbl.BackgroundColor3 = COLOR_BG_MED
    titleLbl.BorderSizePixel = 0
    titleLbl.TextColor3 = COLOR_WHITE
    titleLbl.Text = tostring(title or "")
    titleLbl.TextSize = 14
    titleLbl.Font = Enum.Font.SourceSansBold
    titleLbl.Parent = frame

    local bodyLbl = Instance.new("TextLabel")
    bodyLbl.Size = UDim2.new(1, -10, 0, 60)
    bodyLbl.Position = UDim2.new(0, 5, 0, 35)
    bodyLbl.BackgroundTransparency = 1
    bodyLbl.TextColor3 = COLOR_WHITE
    bodyLbl.TextWrapped = true
    bodyLbl.Text = tostring(content or "")
    bodyLbl.TextSize = 14
    bodyLbl.Font = Enum.Font.SourceSans
    bodyLbl.Parent = frame

    task.spawn(function()
      task.wait(tonumber(duration) or 3)
      if gui then gui:Destroy() end
    end)
  end

  local function waitForCharacter()
    while true do
      local ch = player.Character
      if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
        return ch
      end
      player.CharacterAdded:Wait()
      task.wait(0.05)
    end
  end

  return { notify = notify, waitForCharacter = waitForCharacter }
end

local function getInjectedUtils()
  local s = rawget(getfenv(), "script")
  -- script as plain table with _deps
  if type(s) == "table" and s._deps and s._deps.utils then
    return s._deps.utils
  end
  -- script as Instance with Parent._deps (ModuleScript or table)
  if typeof(s) == "Instance" and s.Parent then
    local ok, depsFolder = pcall(function() return s.Parent:FindFirstChild("_deps") end)
    if ok and typeof(depsFolder) == "Instance" then
      local ms = depsFolder:FindFirstChild("utils")
      if ms then local ok2, mod = pcall(require, ms); if ok2 then return mod end end
    end
    if type(s.Parent._deps) == "table" and s.Parent._deps.utils then
      return s.Parent._deps.utils
    end
  end
  -- global injection
  if rawget(getfenv(), "__WOODZ_UTILS") then
    return __WOODZ_UTILS
  end
  return nil
end

local utils = getInjectedUtils() or buildUtilsFallback()

-- ========= Safe require helper =========
local function tryRequire(name)
  local s = rawget(getfenv(), "script")
  -- script as table with _deps
  if type(s) == "table" and s._deps and s._deps[name] then
    return s._deps[name]
  end
  -- global deps table
  local DEPS = rawget(getfenv(), "__WOODZ_DEPS")
  if type(DEPS) == "table" and DEPS[name] then
    return DEPS[name]
  end
  -- script Instance paths
  if typeof(s) == "Instance" and s.Parent then
    local ok, depsFolder = pcall(function() return s.Parent:FindFirstChild("_deps") end)
    if ok and typeof(depsFolder) == "Instance" then
      local depMS = depsFolder:FindFirstChild(name)
      if depMS then local okr, mod = pcall(require, depMS); if okr then return mod end end
    end
    local child = s.Parent:FindFirstChild(name)
    if child then local okr, mod = pcall(require, child); if okr then return mod end end
    if type(s.Parent._deps) == "table" and s.Parent._deps[name] then
      return s.Parent._deps[name]
    end
  end
  -- globals like __WOODZ_DATA_MONSTERS
  local g = rawget(getfenv(), "__WOODZ_" .. string.upper(name))
  if g then return g end
  return nil
end

-- prefer data_monsters from GitHub; fallback to constants
local DATA = tryRequire("data_monsters")
local CONST = tryRequire("constants")
if not DATA and not CONST then
  utils.notify("🌲 WoodzHUB Error", "No data_monsters.lua or constants.lua found for groups.", 5)
end

-- ========= Config =========
local WEATHER_TIMEOUT            = 30   -- seconds (Weather Events only)
local NON_WEATHER_STALL_TIMEOUT  = 3    -- seconds without HP drop → skip
local ABOVE_OFFSET               = Vector3.new(0, 20, 0)

-- Smooth follow constraints (smoother, no “glide down”)
local POS_RESPONSIVENESS         = 200
local POS_MAX_FORCE              = 1e9
local ORI_RESPONSIVENESS         = 200
local ORI_MAX_TORQUE             = 1e9

-- ========= Lists from data =========
local function getWeatherList()
  return (DATA and DATA.weatherEventModels)
      or (CONST and CONST.weatherEventModels)
      or {}
end
local function getSahurList()
  return (DATA and DATA.toSahurModels)
      or (CONST and CONST.toSahurModels)
      or {}
end
local function getForcedList()
  return (DATA and DATA.forcedMonsters)
      or (CONST and CONST.forcedMonsters)
      or {}
end

local WEATHER_NAMES = table.clone(getWeatherList())
local SAHUR_NAMES   = table.clone(getSahurList())
local FORCED_NAMES  = table.clone(getForcedList())

-- ========= Selection / Filter state =========
local M = {}

local allMonsterModels      = {}
local filteredMonsterModels = {}
local selectedMonsterModels = { "Weather Events" }

local function norm(s)
  s = tostring(s or ""):lower()
  s = s:gsub("[%s%p]+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end
local function matchInList(list, name)
  local ln = norm(name)
  for _, v in ipairs(list) do
    local lv = norm(v)
    if ln == lv then return true end
    if #lv >= 3 and ln:find(lv, 1, true) then return true end
  end
  return false
end
local function isWeatherName(name) return matchInList(WEATHER_NAMES, name) end
local function isSahurName(name)   return matchInList(SAHUR_NAMES,   name) end

function M.getSelected() return selectedMonsterModels end
function M.setSelected(list)
  selectedMonsterModels = {}
  for _, n in ipairs(list or {}) do table.insert(selectedMonsterModels, n) end
end
function M.toggleSelect(name)
  local i = table.find(selectedMonsterModels, name)
  if i then table.remove(selectedMonsterModels, i) else table.insert(selectedMonsterModels, name) end
end
function M.isSelected(name) return table.find(selectedMonsterModels, name) ~= nil end

-- UI nudge so presets trigger immediate retarget
local _retargetFlag = 0
function M.forceRetarget() _retargetFlag = tick() end

-- ========= Discovery / Filtering =========
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
      if hum and hum.Health > 0 then pushUnique(valid, node.Name) end
    end
  end
  for _, nm in ipairs(FORCED_NAMES) do pushUnique(valid, nm) end
  table.insert(valid, "To Sahur")
  table.insert(valid, "Weather Events")
  table.sort(valid)
  allMonsterModels      = valid
  filteredMonsterModels = table.clone(valid)
  return valid
end

function M.getFiltered() return filteredMonsterModels end

function M.filterMonsterModels(text)
  text = tostring(text or ""):lower()
  local filtered = {}
  local function matchesAny(list)
    for _, n in ipairs(list) do if n:lower():find(text, 1, true) then return true end end
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
      elseif model:lower():find(text, 1, true) then
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

-- ========= Group counters (for UI feedback) =========
function M.countWeatherEnemies()
  local c = 0
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 and isWeatherName(node.Name) then c += 1 end
    end
  end
  return c
end

function M.countSahurEnemies()
  local c = 0
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 and isSahurName(node.Name) then c += 1 end
    end
  end
  return c
end

-- ========= Helpers =========
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

local function makeSmoothFollow(hrp)
  local a0 = Instance.new("Attachment");     a0.Name = "WoodzHub_A0"; a0.Parent = hrp

  local ap = Instance.new("AlignPosition");   ap.Name = "WoodzHub_AP"
  ap.Mode = Enum.PositionAlignmentMode.OneAttachment
  ap.Attachment0 = a0
  ap.ApplyAtCenterOfMass = true
  ap.MaxForce = POS_MAX_FORCE
  ap.Responsiveness = POS_RESPONSIVENESS
  ap.RigidityEnabled = false
  ap.Parent = hrp

  local ao = Instance.new("AlignOrientation"); ao.Name = "WoodzHub_AO"
  ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
  ao.Attachment0 = a0
  ao.MaxTorque = ORI_MAX_TORQUE
  ao.Responsiveness = ORI_RESPONSIVENESS
  ao.RigidityEnabled = false
  ao.Parent = hrp

  local ctl = {}
  function ctl:setGoal(cf) ap.Position = cf.Position; ao.CFrame = cf.Rotation end
  function ctl:destroy() ap:Destroy(); ao:Destroy(); a0:Destroy() end
  return ctl
end

-- ========= Remote =========
local autoAttackRemote
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

-- ========= Main loop =========
function M.runAutoFarm(flagGetter, setTargetText)
  if not autoAttackRemote then
    utils.notify("🌲 Auto-Farm", "RequestAttack RemoteFunction not found.", 5)
    return
  end
  local function label(t) if setTargetText then setTargetText(t) end end
  local lastRetargetSeen = _retargetFlag

  while flagGetter() do
    local character = utils.waitForCharacter()
    local hum = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hum or hum.Health <= 0 or not hrp then
      label("Current Target: None"); task.wait(0.05); continue
    end

    -- Build prioritized list each cycle
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
          local nm = node.Name
          if wantWeather and isWeatherName(nm) then
            table.insert(weather, node)
          elseif explicitSet[nm:lower()] then
            table.insert(explicit, node)
          elseif wantSahur and isSahurName(nm) then
            table.insert(sahur, node)
          end
        end
      end
    end
    local enemies = {}
    for _, e in ipairs(weather)  do table.insert(enemies, e) end
    for _, e in ipairs(explicit) do table.insert(enemies, e) end
    for _, e in ipairs(sahur)    do table.insert(enemies, e) end

    if #enemies == 0 then
      label("Current Target: None"); task.wait(0.1); continue
    end

    for _, enemy in ipairs(enemies) do
      if not flagGetter() then break end
      if _retargetFlag ~= lastRetargetSeen then lastRetargetSeen = _retargetFlag; break end
      if not enemy or not enemy.Parent or Players:GetPlayerFromCharacter(enemy) then continue end

      local eh = enemy:FindFirstChildOfClass("Humanoid")
      if not eh or eh.Health <= 0 then continue end

      local okPivot, pcf = pcall(function() return enemy:GetPivot() end)
      local targetCF = (okPivot and isValidCFrame(pcf)) and (pcf * CFrame.new(ABOVE_OFFSET)) or nil
      if not targetCF then continue end

      -- jump to target (no glide)
      hardTeleport(targetCF)

      -- re-validate character
      character = player.Character
      hum = character and character:FindFirstChildOfClass("Humanoid")
      hrp = character and character:FindFirstChild("HumanoidRootPart")
      if not character or not hum or not hrp then continue end

      local oldPS = hum.PlatformStand
      hum.PlatformStand = true
      zeroVel(hrp)
      local ctl = makeSmoothFollow(hrp)

      -- Find a base part to follow
      local targetPart = findBasePart(enemy)
      if not targetPart then
        local t0 = tick()
        repeat
          RunService.Heartbeat:Wait()
          targetPart = findBasePart(enemy)
        until targetPart or (tick() - t0) > 2 or not enemy.Parent or eh.Health <= 0
      end
      if not targetPart then hum.PlatformStand = oldPS; ctl:destroy(); continue end

      label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(eh.Health)))

      local isWeather = isWeatherName(enemy.Name)
      local lastHealth = eh.Health
      local lastDropAt = tick()
      local startedAt  = tick()

      local hcConn = eh.HealthChanged:Connect(function(h)
        label(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h)))
        if h < lastHealth then lastDropAt = tick() end
        lastHealth = h
      end)

      while flagGetter() and enemy.Parent and eh.Health > 0 do
        if _retargetFlag ~= lastRetargetSeen then lastRetargetSeen = _retargetFlag; break end

        local partNow = findBasePart(enemy) or targetPart
        if not partNow then break end

        ctl:setGoal(partNow.CFrame * CFrame.new(ABOVE_OFFSET))

        local hrpTarget = enemy:FindFirstChild("HumanoidRootPart")
        if hrpTarget and autoAttackRemote then
          pcall(function() autoAttackRemote:InvokeServer(hrpTarget.CFrame) end)
        end

        local now = tick()
        if isWeather and (now - startedAt) > WEATHER_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Weather timeout on %s after %ds."):format(enemy.Name, WEATHER_TIMEOUT), 3)
          break
        end
        if (not isWeather) and (now - lastDropAt) > NON_WEATHER_STALL_TIMEOUT then
          utils.notify("🌲 Auto-Farm", ("Skipping %s (no HP change for %0.1fs)"):format(enemy.Name, NON_WEATHER_STALL_TIMEOUT), 3)
          break
        end

        RunService.Heartbeat:Wait()
      end

      if hcConn then hcConn:Disconnect() end
      label("Current Target: None")
      ctl:destroy()
      if hum and hum.Parent then hum.PlatformStand = oldPS; zeroVel(hrp) end
      RunService.Heartbeat:Wait()
    end

    RunService.Heartbeat:Wait()
  end
end

return M
