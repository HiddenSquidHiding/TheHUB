-- smart_target.lua
-- Smart-targets mobs you can safely kill using MonsterInfo + REAL player stats.
-- Adds robust, multi-source stat detection and console prints for validation.

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
-- Debug helpers
----------------------------------------------------------------------

local function isDebug(opts)
  if opts and opts.debug ~= nil then return opts.debug end
  return _G.WOODZHUB_DEBUG == true
end

local function dprint(flag, ...)
  if flag then
    print("[WOODZHUB/SMART]", ...)
  end
end

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
  local s = (v:gsub("[%s,]", ""))
  local n = tonumber(s) -- handles integers and scientific notation
  if n then return n end
  local num, suf = s:match("^([%+%-]?%d+%.?%d*)(%a+)$")
  if num and suf then
    local base = tonumber(num)
    local mult = SUFFIXES[suf]
    if base and mult then return base * mult end
  end
  local digits = s:match("^(%d+)$")
  if digits then return tonumber(digits) end
  return nil
end

-- Deep search for a stat by key preference list
local function deepFindNumber(tbl, keys, maxDepth)
  maxDepth = maxDepth or 6
  local best, bestKey = nil, nil

  local function try(k, v)
    local n = parseNumber(v)
    if n then
      if not best or n > best then
        best, bestKey = n, k
      end
    end
  end

  local function walk(t, depth)
    if type(t) ~= "table" or depth > maxDepth then return end
    -- Prioritize matching keys on this level
    for k, v in pairs(t) do
      if type(k) == "string" then
        local kl = k:lower()
        for _, want in ipairs(keys) do
          if kl == want or kl:find(want, 1, true) then
            try(k, v)
          end
        end
      end
    end
    -- Recurse
    for _, v in pairs(t) do
      if type(v) == "table" then walk(v, depth + 1) end
    end
  end

  walk(tbl, 0)
  return best, bestKey
end

-- Extract number-like from Roblox Value objects
local function valueObjectToNumber(obj)
  if not obj or not obj:IsA("ValueBase") then return nil end
  if obj:IsA("NumberValue") then return obj.Value end
  if obj:IsA("IntValue") or obj:IsA("DoubleConstrainedValue") then return obj.Value end
  if obj:IsA("StringValue") then return parseNumber(obj.Value) end
  if obj:IsA("ObjectValue") then return nil end
  local v = rawget(obj, "Value")
  return parseNumber(v)
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

----------------------------------------------------------------------
-- Robust player stats extraction (handles huge numbers & many sources)
----------------------------------------------------------------------

local function getAttributesNumber(inst, names)
  if not inst or not inst.GetAttribute then return nil end
  for _, key in ipairs(names) do
    local v = inst:GetAttribute(key)
    local n = parseNumber(v)
    if n then return n, "Attribute:"..key end
  end
  return nil
end

local damageKeys = { "damage","attack","atk","power","dps","strength","str","atkpower","attackpower","sword","weapon","hit" }
local healthKeys = { "maxhealth","health","hp","life","hearts","vitality" }

local function extractFromFolder(folder, wantDamage)
  if not folder then return nil end
  local best, source = nil, nil
  -- 1) Value objects by name
  for _, v in ipairs(folder:GetDescendants()) do
    if v:IsA("ValueBase") then
      if wantDamage then
        for _, key in ipairs(damageKeys) do
          if v.Name:lower():find(key, 1, true) then
            local n = valueObjectToNumber(v)
            if n and (not best or n > best) then best, source = n, folder:GetFullName().."."..v.Name end
          end
        end
      else
        for _, key in ipairs(healthKeys) do
          if v.Name:lower():find(key, 1, true) then
            local n = valueObjectToNumber(v)
            if n and (not best or n > best) then best, source = n, folder:GetFullName().."."..v.Name end
          end
        end
      end
    end
  end
  -- 2) As table-like (Strings/Numbers in nested tables)
  local n2, key2 = deepFindNumber(folder, wantDamage and damageKeys or healthKeys)
  if n2 and (not best or n2 > best) then best, source = n2, folder:GetFullName()..".<table>:"..tostring(key2) end
  return best, source
end

local function getPlayerStats(debugFlag)
  local player = Players.LocalPlayer
  local character = player.Character or player.CharacterAdded:Wait()

  local sources = {}

  local function record(name, n, where)
    if n and n > 0 then sources[name] = { value = n, where = where } end
  end

  -- Humanoid health baseline
  local humanoid = character:FindFirstChildOfClass("Humanoid")
  if humanoid then
    record("HumanoidMaxHealth", (humanoid.MaxHealth and humanoid.MaxHealth > 0) and humanoid.MaxHealth or nil, "Humanoid.MaxHealth")
    record("HumanoidHealth", humanoid.Health, "Humanoid.Health")
  end

  -- Knit LookupService.RF.GetPlayerData
  local GetPlayerData
  local okRF, rf = pcall(function()
    return ReplicatedStorage.Packages.Knit.Services.LookupService.RF.GetPlayerData
  end)
  if okRF and rf and rf:IsA("RemoteFunction") then
    GetPlayerData = rf
    local ok, stats = pcall(function() return GetPlayerData:InvokeServer() end)
    if ok and type(stats) == "table" then
      local dmg, dkey = deepFindNumber(stats, damageKeys)
      local hp, hkey  = deepFindNumber(stats, healthKeys)
      record("ServerDamage", dmg, "LookupService:"..tostring(dkey))
      record("ServerHealth", hp,  "LookupService:"..tostring(hkey))
    end
  end

  -- leaderstats
  local ls = player:FindFirstChild("leaderstats")
  if ls then
    local dmg, dsrc = extractFromFolder(ls, true);  record("LS_Damage", dmg, dsrc)
    local hp,  hsrc = extractFromFolder(ls, false); record("LS_Health", hp,  hsrc)
  end

  -- common folders on Player
  for _, name in ipairs({ "Stats","PlayerStats","PlayerData","Data","Attributes","Info" }) do
    local n = player:FindFirstChild(name)
    if n then
      local dmg, dsrc = extractFromFolder(n, true);  record("P_"..name.."_Damage", dmg, dsrc)
      local hp,  hsrc = extractFromFolder(n, false); record("P_"..name.."_Health", hp,  hsrc)
    end
  end

  -- attributes on Player and Character
  local admg, asrc = getAttributesNumber(player, damageKeys); record("Attr_Damage_Player", admg, asrc)
  local ahp,  asrc2= getAttributesNumber(player, healthKeys); record("Attr_Health_Player", ahp, asrc2)
  local cdm,  csrc = getAttributesNumber(character, damageKeys); record("Attr_Damage_Char", cdm, csrc)
  local chp,  csrc2= getAttributesNumber(character, healthKeys); record("Attr_Health_Char", chp, csrc2)

  -- Choose best values
  local damage, damageWhere, health, healthWhere = nil, "n/a", nil, "n/a"
  for k, v in pairs(sources) do
    if k:lower():find("damage") then
      if not damage or v.value > damage then damage, damageWhere = v.value, v.where end
    end
  end
  for k, v in pairs(sources) do
    if k:lower():find("health") then
      if not health or v.value > health then health, healthWhere = v.value, v.where end
    end
  end

  -- fallbacks
  if not damage or damage <= 0 then damage, damageWhere = 100, "fallback:100" end
  if not health or health <= 0 then
    local hh = humanoid and (humanoid.MaxHealth > 0 and humanoid.MaxHealth or humanoid.Health) or 1000
    health, healthWhere = hh, "humanoidFallback"
  end

  -- Debug dump (prints once every call, but caller throttles)
  dprint(debugFlag, ("Player Stats | DAMAGE: %s  (from %s) | HEALTH: %s  (from %s)")
    :format(tostring(damage), tostring(damageWhere), tostring(health), tostring(healthWhere)))
  if debugFlag then
    dprint(true, "All detected sources (non-zero):")
    for k, v in pairs(sources) do
      dprint(true, ("  %s = %s  @ %s"):format(k, tostring(v.value), tostring(v.where)))
    end
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
    local h = entry.Health or entry.health or entry.MaxHealth or entry.maxhealth
    local a = entry.Attack or entry.attack or entry.Damage or entry.damage
    mHealth = parseNumber(h) or mHealth
    mAttack = parseNumber(a) or mAttack
  elseif type(entry) == "string" or type(entry) == "number" then
    mHealth = parseNumber(entry) or mHealth
  end
  if humanoid and humanoid.Health and humanoid.Health > mHealth then
    mHealth = humanoid.Health
  end
  return mHealth, mAttack
end

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
    task.wait(0.05)
  end

  if hcConn then hcConn:Disconnect() end
  hoverBP:Destroy()
  if onText then onText("Current Target: None") end
end

----------------------------------------------------------------------
-- Public: run smart farm
--   opts = { module = <ModuleScript>, safetyBuffer = 0.8, refreshInterval = 0.05, debug = false }
----------------------------------------------------------------------

function M.runSmartFarm(getEnabled, setTargetText, opts)
  opts = opts or {}
  local debugFlag = isDebug(opts)
  local player = Players.LocalPlayer
  if not ensureAttackRemote() then return end

  local monsterInfo, loadErr = M.loadMonsterInfo(opts.module)
  if not monsterInfo then
    utils.notify("🌲 Smart Target", "MonsterInfo load error: " .. tostring(loadErr), 6)
    return
  end

  -- throttle debug stat prints (once every few seconds)
  local lastStatPrint = 0

  while getEnabled() do
    local character = utils.waitForCharacter()
    if not character or not character:FindFirstChild("HumanoidRootPart") then
      task.wait(0.05)
      continue
    end

    -- Real, large numbers supported here; prints periodically if debug
    local pDmg, pHP = getPlayerStats(debugFlag and (tick() - lastStatPrint > 3))
    if debugFlag and (tick() - lastStatPrint > 3) then
      lastStatPrint = tick()
    end

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

    -- Prioritize fastest kills: lowest live HP first (simple & effective at huge DPS)
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
