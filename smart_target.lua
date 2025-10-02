-- smart_target.lua
-- Loads/decompiles a MonsterInfo ModuleScript and smart-targets mobs you can safely kill
-- Uses StreamingEnabled-friendly approach (pivot → approach → basepart) and instant hop.

-- 🔧 Safe utils access
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[smart_target.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading this module")
end

local utils = getUtils()

local Players = game:GetService('Players')
local Workspace = game:GetService('Workspace')
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local M = {}

----------------------------------------------------------------------
-- Load / Decompile MonsterInfo
----------------------------------------------------------------------

local function evalModuleSource(src, chunkName)
  local chunk = loadstring(src, chunkName or "=MonsterInfo")
  if not chunk then return nil, "loadstring failed" end
  local baseEnv = getfenv()
  local sandbox = setmetatable({
    script = {},
    require = function() return {} end,
  }, { __index = baseEnv })
  setfenv(chunk, sandbox)
  local ok, ret = pcall(chunk)
  if not ok then return nil, ret end
  if type(ret) == "table" then return ret, nil end
  return nil, "module did not return a table"
end

local function tryDecompile(mod)
  local fn = rawget(_G, "decompile") or rawget(getfenv(), "decompile") or rawget(_G, "DECOMPILE")
  if type(fn) == "function" then
    local ok, src = pcall(fn, mod)
    if ok and type(src) == "string" and #src > 0 then
      return src
    end
  end
  return nil
end

function M.loadMonsterInfo(mod)
  if typeof(mod) ~= "Instance" or not mod:IsA("ModuleScript") then
    return nil, "[smart] expected a ModuleScript"
  end
  do
    local ok, ret = pcall(function() return require(mod) end)
    if ok and type(ret) == "table" then
      utils.notify("🌲 Smart Target", "Loaded MonsterInfo via require()", 3)
      return ret, nil
    end
  end
  local src = tryDecompile(mod)
  if src then
    local tbl, err = evalModuleSource(src, "=" .. mod:GetFullName())
    if tbl then
      utils.notify("🌲 Smart Target", "Loaded MonsterInfo via decompile()", 3)
      return tbl, nil
    else
      return nil, "[smart] eval error: " .. tostring(err)
    end
  end
  return nil, "[smart] could not load MonsterInfo (require failed; no decompiler available)"
end

----------------------------------------------------------------------
-- Player + Enemy scanning
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

local function listAllEnemies()
  local enemies = {}
  for _, node in ipairs(Workspace:GetDescendants()) do
    if node:IsA("Model") and not Players:GetPlayerFromCharacter(node) then
      local h = node:FindFirstChildOfClass("Humanoid")
      if h and h.Health > 0 then
        table.insert(enemies, node)
      end
    end
  end
  return enemies
end

local function getPlayerStats()
  local GetPlayerData
  local ok, rf = pcall(function()
    return ReplicatedStorage.Packages.Knit.Services.LookupService.RF.GetPlayerData
  end)
  if ok and rf and rf:IsA("RemoteFunction") then
    GetPlayerData = rf
  end
  local damage, health = 100, 1000
  local ok2, stats = pcall(function()
    return GetPlayerData and GetPlayerData:InvokeServer()
  end)
  if ok2 and type(stats) == "table" then
    damage = stats.Damage or stats.AttackPower or stats.Power or damage
    health = stats.MaxHealth or stats.Health or health
  end
  return damage, health
end

----------------------------------------------------------------------
-- Targeting logic
----------------------------------------------------------------------

local function readMobStats(monsterInfo, name, humanoid)
  local entry = monsterInfo and monsterInfo[name]
  local mHealth = (humanoid and humanoid.Health) or 0
  local mAttack = 10
  if type(entry) == "table" then
    mHealth = entry.Health or entry.health or entry.MaxHealth or mHealth
    mAttack = entry.Attack or entry.Damage or entry.attack or entry.damage or mAttack
  end
  return mHealth, mAttack
end

local function canKill(playerDamage, playerHealth, mobHealth, mobAttack, safetyBuffer)
  safetyBuffer = safetyBuffer or 0.8
  if playerDamage <= 0 then return false end
  local hitsToKill = math.ceil((mobHealth > 0 and mobHealth or 1) / playerDamage)
  local estDamageTaken = hitsToKill * (mobAttack > 0 and mobAttack or 0)
  return estDamageTaken < (playerHealth * safetyBuffer)
end

----------------------------------------------------------------------
-- Attack driver (StreamingEnabled friendly; instant hop)
----------------------------------------------------------------------

local autoAttackRemote = nil
local function ensureAttackRemote()
  if autoAttackRemote and autoAttackRemote.Parent then return true end
  local ok, remote = pcall(function()
    return ReplicatedStorage:WaitForChild('Packages'):WaitForChild('Knit')
      :WaitForChild('Services'):WaitForChild('MonsterService')
      :WaitForChild('RF'):WaitForChild('RequestAttack')
  end)
  if ok and remote and remote:IsA('RemoteFunction') then
    autoAttackRemote = remote
    utils.notify("🌲 Smart Target", "RequestAttack remote ready.", 3)
    return true
  end
  utils.notify("🌲 Smart Target", "RequestAttack remote NOT found.", 4)
  return false
end

local function attackEnemy(player, enemy, onText)
  local humanoid = enemy:FindFirstChildOfClass("Humanoid")
  if not humanoid or humanoid.Health <= 0 then return end

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
  if not targetCF or not isValidCFrame(targetCF) then return end

  pcall(function()
    local ch = player.Character
    if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") and ch.Humanoid.Health > 0 then
      ch.HumanoidRootPart.CFrame = targetCF
    end
  end)

  local t0 = tick()
  local APPROACH_TIMEOUT = 3
  repeat
    task.wait(0.05)
    targetPart = findBasePart(enemy)
  until targetPart or (tick()-t0) > APPROACH_TIMEOUT or not enemy.Parent or (humanoid and humanoid.Health <= 0)
  if not targetPart then return end

  local cf = targetPart.CFrame * CFrame.new(0, 20, 0)
  if not isValidCFrame(cf) then return end

  if onText then onText(("Current Target: %s (Health: %d)"):format(enemy.Name, math.floor(humanoid.Health))) end

  local hoverBP = Instance.new("BodyPosition")
  hoverBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
  hoverBP.D = 1000; hoverBP.P = 10000
  hoverBP.Position = cf.Position
  hoverBP.Name = "WoodzHub_SmartHover"
  local character = player.Character
  if not (character and character:FindFirstChild("HumanoidRootPart")) then hoverBP:Destroy(); return end
  hoverBP.Parent = character.HumanoidRootPart

  local hcConn = humanoid.HealthChanged:Connect(function(h)
    if onText then onText(("Current Target: %s (Health: %d)"):format(enemy.Name, math.floor(h))) end
  end)

  local start = tick()
  local TARGET_TIMEOUT = 30
  while enemy.Parent and humanoid and humanoid.Health > 0 do
    if (tick() - start) > TARGET_TIMEOUT then break end
    local partNow = findBasePart(enemy) or targetPart
    local cfNow = partNow and (partNow.CFrame * CFrame.new(0, 20, 0))
    if cfNow and isValidCFrame(cfNow) then
      hoverBP.Position = cfNow.Position
    end
    local hrp = enemy:FindFirstChild("HumanoidRootPart")
    if hrp and autoAttackRemote then
      pcall(function() autoAttackRemote:InvokeServer(hrp.CFrame) end)
    end
    task.wait(0.1)
  end

  if hcConn then hcConn:Disconnect() end
  hoverBP:Destroy()
  if onText then onText("Current Target: None") end
end

----------------------------------------------------------------------
-- Public: run smart farm
--   opts = { module = <ModuleScript>, safetyBuffer = 0.8, refreshInterval = 0.05 }
----------------------------------------------------------------------

function M.runSmartFarm(getEnabled, setTargetText, opts)
  opts = opts or {}
  local player = Players.LocalPlayer
  if not ensureAttackRemote() then return end

  local monsterInfo, loadErr = M.loadMonsterInfo(opts.module)
  if not monsterInfo then
    utils.notify("🌲 Smart Target", "MonsterInfo load error: " .. tostring(loadErr), 6)
    return
  end

  while getEnabled() do
    local character = utils.waitForCharacter()
    if not character or not character:FindFirstChild("HumanoidRootPart") then
      task.wait(0.05)
      continue
    end

    local pDmg, pHP = getPlayerStats()
    local enemies = listAllEnemies()

    local candidates = {}
    for _, enemy in ipairs(enemies) do
      local hum = enemy:FindFirstChildOfClass("Humanoid")
      if hum and hum.Health > 0 then
        local mHealth, mAttack = readMobStats(monsterInfo, enemy.Name, hum)
        if canKill(pDmg, pHP, mHealth, mAttack, opts.safetyBuffer or 0.8) then
          table.insert(candidates, enemy)
        end
      end
    end

    if #candidates == 0 then
      if setTargetText then setTargetText("Current Target: None") end
      task.wait(opts.refreshInterval or 0.05)
      continue
    end

    table.sort(candidates, function(a,b)
      local ha = (a:FindFirstChildOfClass("Humanoid") and a.Humanoid.Health) or math.huge
      local hb = (b:FindFirstChildOfClass("Humanoid") and b.Humanoid.Health) or math.huge
      if ha == hb then return tostring(a.Name) < tostring(b.Name) end
      return ha < hb
    end)

    for _, enemy in ipairs(candidates) do
      if not getEnabled() then if setTargetText then setTargetText("Current Target: None") end return end
      attackEnemy(player, enemy, setTargetText)
    end
    task.wait(0.01)
  end
end

return M
