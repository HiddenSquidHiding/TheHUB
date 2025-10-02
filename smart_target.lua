-- smart_target.lua
-- Smart-targets mobs you can safely kill using MonsterInfo + REAL player stats.
-- Handles StreamingEnabled (pivot → approach → basepart), instant hops, and huge number parsing.

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
-- Number parsing (handles trillions+ and formatted strings)
----------------------------------------------------------------------

local SUFFIXES = {
  k = 1e3,  K = 1e3,
  m = 1e6,  M = 1e6,
  b = 1e9,  B = 1e9,
  t = 1e12, T = 1e12,
  qa = 1e15, QA = 1e15, Qa = 1e15,
  qi = 1e18, QI = 1e18, Qi = 1e18,
  sx = 1e21, SX = 1e21, Sx = 1e21,
  sp = 1e24, SP = 1e24, Sp = 1e24,
  oc = 1e27, OC = 1e27, Oc = 1e27,
  no = 1e30, NO = 1e30, No = 1e30,
  de = 1e33, DE = 1e33, De = 1e33,
}

local function parseNumber(v)
  local tv = typeof(v)
  if tv == "number" then return v end
  if tv ~= "string" then return nil end

  -- remove commas/spaces
  local s = (v:gsub("[%s,]", ""))

  -- scientific notation?
  local n = tonumber(s)
  if n then return n end

  -- suffix pattern: 123.45T / 999Qa / 1.2qi, etc.
  local num, suf = s:match("^([%+%-]?%d+%.?%d*)(%a+)$")
  if num and suf then
    local base = tonumber(num)
    local mult = SUFFIXES[suf]
    if base and mult then return base * mult end
  end

  -- bare digits as last resort
  local digits = s:match("^(%d+)$")
  if digits then return tonumber(digits) end

  return nil
end

-- Deep search for a stat by key preference list
local function deepFindNumber(tbl, keys)
  local best = nil
  local function try(v)
    local n = parseNumber(v)
    if n then
      if not best or n > best then best = n end
    end
  end
  local function walk(t, depth)
    if type(t) ~= "table" or depth > 5 then return end
    -- direct keys first (exact / contains)
    for k,v in pairs(t) do
      if type(k) == "string" then
        local kl = k:lower()
        for _, want in ipairs(keys) do
          if kl == want or kl:find(want, 1, true) then try(v) end
        end
      end
    end
    -- then recurse
    for _, v in pairs(t) do
      if type(v) == "table" then walk(v, depth+1) end
    end
  end
  walk(tbl, 0)
  return best
end

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
  -- require first
  do
    local ok, ret = pcall(function() return require(mod) end)
    if ok and type(ret) == "table" then
      utils.notify("🌲 Smart Target", "Loaded MonsterInfo via require()", 3)
      return ret, nil
    end
  end
  -- decompile fallback
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

----------------------------------------------------------------------
-- Robust player stats extraction (handles huge numbers & multiple sources)
----------------------------------------------------------------------

local function getPlayerStats()
  local player = Players.LocalPlayer
  local character = player.Character or player.CharacterAdded:Wait()

  -- Start with Humanoid health (often set to your true MaxHealth client-side)
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  local health = (humanoid and (humanoid.MaxHealth > 0 and humanoid.MaxHealth or humanoid.Health)) or 1000
  local damage = 100 -- will upgrade as we find better values

  -- 1) Knit LookupService.RF.GetPlayerData (server authoritative)
  local GetPlayerData
  local okRF, rf = pcall(function()
    return ReplicatedStorage.Packages.Knit.Services.LookupService.RF.GetPlayerData
  end)
  if okRF and rf and rf:IsA("RemoteFunction") then
    GetPlayerData = rf
    local ok, stats = pcall(function() return GetPlayerData:InvokeServer() end)
    if ok and type(stats) == "table" then
      local dmg = deepFindNumber(stats, { "damage","attack","power","dps","strength" })
      local hp  = deepFindNumber(stats, { "maxhealth","health","hp" })
      if dmg then damage = dmg end
      if hp  then health = hp end
    end
  end

  -- 2) leaderstats (common)
  local ls = player:FindFirstChild("leaderstats")
  if ls then
    local dmgLS = deepFindNumber(ls, { "damage","attack","power","dps","strength" })
    local hpLS  = deepFindNumber(ls, { "maxhealth","health","hp" })
    if dmgLS and dmgLS > damage then damage = dmgLS end
    if hpLS  and hpLS  > health then health = hpLS  end
  end

  -- 3) generic Stats/PlayerData folders
  for _, name in ipairs({ "Stats","PlayerStats","PlayerData","Data","Attributes" }) do
    local n = player:FindFirstChild(name)
    if n then
      local dmgN = deepFindNumber(n, { "damage","attack","power","dps","strength" })
      local hpN  = deepFindNumber(n, { "maxhealth","health","hp" })
      if dmgN and dmgN > damage then damage = dmgN end
      if hpN  and hpN  > health then health = hpN  end
    end
  end

  -- 4) Humanoid again (in case it updated after calls)
  if humanoid then
    if humanoid.MaxHealth and humanoid.MaxHealth > health then health = humanoid.MaxHealth end
    if humanoid.Health and humanoid.Health > health then health = humanoid.Health end
  end

  -- Sanity: ensure positive numbers
  if not damage or damage <= 0 then damage = 100 end
  if not health or health <= 0 then health = 1000 end

  return damage, health
end

----------------------------------------------------------------------
-- Targeting logic
----------------------------------------------------------------------

-- Read monster stats from MonsterInfo entry or live Humanoid
local function readMobStats(monsterInfo, name, humanoid)
  local entry = monsterInfo and monsterInfo[name]
  local mHealth = (humanoid and humanoid.Health) or 0
  local mAttack = 10
  if type(entry) == "table" then
    local h = entry.Health or entry.health or entry.MaxHealth or entry.maxhealth
    local a = entry.Attack or entry.attack or entry.Damage or entry.damage
    mHealth = parseNumber(h) or mHealth
    mAttack = parseNumber(a) or mAttack
  elseif type(entry) == "string" or type(entry) == "number" then
    -- Some games store just a number as HP
    mHealth = parseNumber(entry) or mHealth
  end
  -- If live humanoid has bigger health (e.g., scaled bosses), prefer that
  if humanoid and humanoid.Health and humanoid.Health > mHealth then
    mHealth = humanoid.Health
  end
  return mHealth, mAttack
end

-- Decide if the player can kill safely
-- safetyBuffer: fraction of player HP that we're willing to spend (default 0.8)
local function canKill(playerDamage, playerHealth, mobHealth, mobAttack, safetyBuffer)
  safetyBuffer = safetyBuffer or 0.8
  local dmg = playerDamage > 0 and playerDamage or 1
  local hitsToKill = math.ceil((mobHealth > 0 and mobHealth or 1) / dmg)
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

  if onText then onText(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(humanoid.Health))) end

  local hoverBP = Instance.new("BodyPosition")
  hoverBP.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
  hoverBP.D = 1000; hoverBP.P = 10000
  hoverBP.Position = cf.Position
  hoverBP.Name = "WoodzHub_SmartHover"
  local character = player.Character
  if not (character and character:FindFirstChild("HumanoidRootPart")) then hoverBP:Destroy(); return end
  hoverBP.Parent = character.HumanoidRootPart

  local hcConn = humanoid.HealthChanged:Connect(function(h)
    if onText then onText(("Current Target: %s (Health: %s)"):format(enemy.Name, math.floor(h))) end
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
    task.wait(0.05) -- a bit faster cadence since you’re high damage
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

    -- ✅ Real, large numbers supported here
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

    -- Prioritize fastest kills: lowest (mHealth / pDmg) first; tie-break by current humanoid health
    table.sort(candidates, function(a,b)
      local ha = (a:FindFirstChildOfClass("Humanoid") and a.Humanoid.Health) or math.huge
      local hb = (b:FindFirstChildOfClass("Humanoid") and b.Humanoid.Health) or math.huge
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
