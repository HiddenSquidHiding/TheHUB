-- smart_target.lua
-- Smart-targets mobs you can safely kill using MonsterInfo + REAL player stats.
-- Robust stat resolver: tries Knit RFs, leaderstats, folders, attributes, tools, UI/Replicated values.
-- Console debug prints (_G.WOODZHUB_DEBUG=true) show which sources were used.

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
  k=1e3,K=1e3, m=1e6,M=1e6, b=1e9,B=1e9, t=1e12,T=1e12,
  qa=1e15,Qa=1e15,QA=1e15, qi=1e18,Qi=1e18,QI=1e18,
  sx=1e21,Sx=1e21,SX=1e21, sp=1e24,Sp=1e24,SP=1e24,
  oc=1e27,Oc=1e27,OC=1e27, no=1e30,No=1e30,NO=1e30,
  de=1e33,De=1e33,DE=1e33,
}
local function parseNumber(v)
  local tv = typeof(v)
  if tv == "number" then return v end
  if tv ~= "string" then return nil end
  local s = (v:gsub("[%s,]", ""))
  local n = tonumber(s)
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

local damageKeys = { "damage","attack","atk","power","dps","strength","str","atkpower","attackpower","weapon","sword","hit" }
local healthKeys = { "maxhealth","health","hp","life","hearts","vitality" }

-- Deep search a table-ish structure
local function deepFindNumber(tbl, keys, maxDepth)
  maxDepth = maxDepth or 6
  local best, bestKey = nil, nil
  local function try(k, v)
    local n = parseNumber(v)
    if n and (not best or n > best) then best, bestKey = n, k end
  end
  local function walk(t, depth)
    if type(t) ~= "table" or depth > maxDepth then return end
    for k,v in pairs(t) do
      if type(k) == "string" then
        local kl = k:lower()
        for _, want in ipairs(keys) do
          if kl == want or kl:find(want, 1, true) then try(k, v) end
        end
      end
    end
    for _, v in pairs(t) do
      if type(v) == "table" then walk(v, depth+1) end
    end
  end
  walk(tbl, 0)
  return best, bestKey
end

-- Roblox ValueBase → number
local function valueObjectToNumber(obj)
  if not obj or not obj:IsA("ValueBase") then return nil end
  if obj:IsA("NumberValue") or obj:IsA("IntValue") then return obj.Value end
  if obj:IsA("StringValue") then return parseNumber(obj.Value) end
  local v = rawget(obj, "Value")
  return parseNumber(v)
end

----------------------------------------------------------------------
-- MonsterInfo loader (require → decompile)
----------------------------------------------------------------------
local function evalModuleSource(src, chunkName)
  local chunk = loadstring(src, chunkName or "=MonsterInfo")
  if not chunk then return nil, "loadstring failed" end
  local baseEnv = getfenv()
  local sandbox = setmetatable({ script = {}, require = function() return {} end }, { __index = baseEnv })
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
    if ok and type(src) == "string" and #src > 0 then return src end
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
-- World helpers
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
      if h and h.Health > 0 then table.insert(enemies, node) end
    end
  end
  return enemies
end

----------------------------------------------------------------------
-- Aggressive player stats resolver
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

local function extractFromFolder(folder, wantDamage)
  if not folder then return nil end
  local best, source = nil, nil
  for _, v in ipairs(folder:GetDescendants()) do
    if v:IsA("ValueBase") then
      for _, key in ipairs(wantDamage and damageKeys or healthKeys) do
        if v.Name:lower():find(key, 1, true) then
          local n = valueObjectToNumber(v)
          if n and (not best or n > best) then best, source = n, v:GetFullName() end
        end
      end
    elseif v:IsA("ModuleScript") then
      local ok, tbl = pcall(function() return require(v) end)
      if ok and type(tbl) == "table" then
        local n, k = deepFindNumber(tbl, wantDamage and damageKeys or healthKeys)
        if n and (not best or n > best) then best, source = n, v:GetFullName()..":table("..tostring(k)..")" end
      end
    elseif v:IsA("Folder") then
      -- also check Attributes in folders
      local nAttr, where = getAttributesNumber(v, wantDamage and damageKeys or healthKeys)
      if nAttr and (not best or nAttr > best) then best, source = nAttr, v:GetFullName().."@"..where end
    end
  end
  return best, source
end

-- Probe common Knit services & methods for player stats
local function probeKnitRemotes()
  local out = {}
  local okKnit, knit = pcall(function() return ReplicatedStorage.Packages.Knit end)
  if not okKnit or not knit then return out end
  local okServices, services = pcall(function() return knit.Services end)
  if not okServices or not services then return out end

  local candidateServices = { "LookupService","StatsService","CombatService","PlayerService","DamageService" }
  local candidateMethods  = { "GetPlayerData","GetStats","GetPlayerStats","GetInfo","GetDamage","GetPower" }

  for _, svcName in ipairs(candidateServices) do
    local svc = services:FindFirstChild(svcName)
    if svc then
      local RF = svc:FindFirstChild("RF")
      if RF then
        for _, m in ipairs(candidateMethods) do
          local rf = RF:FindFirstChild(m)
          if rf and rf:IsA("RemoteFunction") then
            local ok, res = pcall(function() return rf:InvokeServer() end)
            if ok and res ~= nil then
              out[svcName.."."..m] = res
            end
          end
        end
      end
    end
  end
  return out
end

-- Scan tools (Character + Backpack) for configs/values/attributes
local function probeTools(player)
  local results = {}
  local function scanContainer(cont)
    if not cont then return end
    for _, tool in ipairs(cont:GetChildren()) do
      if tool:IsA("Tool") or tool:IsA("Accessory") then
        -- Attributes on tool
        local nd, wd = getAttributesNumber(tool, damageKeys); if nd then results[tool:GetFullName()..".AttrDamage"] = nd end
        local nh, wh = getAttributesNumber(tool, healthKeys); if nh then results[tool:GetFullName()..".AttrHealth"] = nh end
        -- Value objects
        for _, v in ipairs(tool:GetDescendants()) do
          if v:IsA("ValueBase") then
            local nl = v.Name:lower()
            for _, key in ipairs(damageKeys) do
              if nl:find(key, 1, true) then
                local n = valueObjectToNumber(v); if n then results[v:GetFullName()] = n end
              end
            end
            for _, key in ipairs(healthKeys) do
              if nl:find(key, 1, true) then
                local n = valueObjectToNumber(v); if n then results[v:GetFullName()] = n end
              end
            end
          elseif v:IsA("ModuleScript") then
            local ok, tbl = pcall(function() return require(v) end)
            if ok and type(tbl) == "table" then
              local nd2 = deepFindNumber(tbl, damageKeys)
              local nh2 = deepFindNumber(tbl, healthKeys)
              if nd2 then results[v:GetFullName()..":tableDamage"] = nd2 end
              if nh2 then results[v:GetFullName()..":tableHealth"] = nh2 end
            end
          end
        end
      end
    end
  end
  scanContainer(player.Character)
  scanContainer(player:FindFirstChild("Backpack"))
  return results
end

-- Scan PlayerGui / ReplicatedStorage for ValueBase named like damage
local function probeReplicated(player)
  local results = {}
  local function scan(root)
    if not root then return end
    for _, v in ipairs(root:GetDescendants()) do
      if v:IsA("ValueBase") then
        local nl = v.Name:lower()
        for _, key in ipairs(damageKeys) do
          if nl:find(key, 1, true) then
            local n = valueObjectToNumber(v); if n then results[v:GetFullName()] = n end
          end
        end
        for _, key in ipairs(healthKeys) do
          if nl:find(key, 1, true) then
            local n = valueObjectToNumber(v); if n then results[v:GetFullName()] = n end
          end
        end
      end
    end
  end
  scan(player:FindFirstChild("PlayerGui"))
  scan(ReplicatedStorage)
  return results
end

local function getPlayerStats(debugNow)
  -- Global overrides / hook (for quick testing)
  if type(_G.WOODZHUB_STAT_HOOK) == "function" then
    local ok, d, h = pcall(_G.WOODZHUB_STAT_HOOK)
    if ok and tonumber(d) and tonumber(h) then
      dprint(debugNow, "Hook override DAMAGE=", d, " HEALTH=", h)
      return d, h
    end
  end
  local forcedD = _G.WOODZHUB_FORCE_DAMAGE and parseNumber(_G.WOODZHUB_FORCE_DAMAGE)
  local forcedH = _G.WOODZHUB_FORCE_HEALTH and parseNumber(_G.WOODZHUB_FORCE_HEALTH)
  if forcedD or forcedH then
    dprint(debugNow, "Forced override(s): DAMAGE=", tostring(forcedD), " HEALTH=", tostring(forcedH))
  end

  local player = Players.LocalPlayer
  local character = player.Character or player.CharacterAdded:Wait()
  local humanoid = character:FindFirstChildOfClass("Humanoid")

  -- collect candidate sources
  local sources = {}

  local function record(tag, n, where)
    if n and n > 0 then sources[tag] = { value = n, where = where } end
  end

  -- Humanoid health baseline
  if humanoid then
    local hMax = humanoid.MaxHealth and humanoid.MaxHealth > 0 and humanoid.MaxHealth or nil
    record("HumanoidMaxHealth", hMax, "Humanoid.MaxHealth")
    record("HumanoidHealth", humanoid.Health, "Humanoid.Health")
  end

  -- Knit remotes probing
  local knitRes = probeKnitRemotes()
  for k, payload in pairs(knitRes) do
    if type(payload) == "table" then
      local d, dk = deepFindNumber(payload, damageKeys)
      local h, hk = deepFindNumber(payload, healthKeys)
      record("KnitRF_Damage_"..k, d, k..":"..tostring(dk))
      record("KnitRF_Health_"..k, h, k..":"..tostring(hk))
    else
      -- simple numeric return?
      local d = parseNumber(payload)
      if d then record("KnitRF_Number_"..k, d, k) end
    end
  end

  -- leaderstats
  local ls = player:FindFirstChild("leaderstats")
  if ls then
    local d1, s1 = extractFromFolder(ls, true);  record("LS_Damage", d1, s1)
    local h1, s2 = extractFromFolder(ls, false); record("LS_Health", h1, s2)
  end

  -- Player folders
  for _, name in ipairs({ "Stats","PlayerStats","PlayerData","Data","Attributes","Info" }) do
    local n = player:FindFirstChild(name)
    if n then
      local d2, sd2 = extractFromFolder(n, true);  record("P_"..name.."_Damage", d2, sd2)
      local h2, sh2 = extractFromFolder(n, false); record("P_"..name.."_Health", h2, sh2)
      local ad, asr = getAttributesNumber(n, damageKeys); if ad then record("P_"..name.."_AttrDamage", ad, asr) end
      local ah, asr2= getAttributesNumber(n, healthKeys); if ah then record("P_"..name.."_AttrHealth", ah, asr2) end
    end
  end

  -- Attributes on Player / Character
  do
    local ad, asr = getAttributesNumber(player, damageKeys); if ad then record("Attr_Damage_Player", ad, asr) end
    local ah, asr2= getAttributesNumber(player, healthKeys); if ah then record("Attr_Health_Player", ah, asr2) end
    local cd, csr = getAttributesNumber(character, damageKeys); if cd then record("Attr_Damage_Char", cd, csr) end
    local ch, csr2= getAttributesNumber(character, healthKeys); if ch then record("Attr_Health_Char", ch, csr2) end
  end

  -- Tools (Backpack + Character)
  local toolFinds = probeTools(player)
  for k,v in pairs(toolFinds) do record("Tool_"..k, v, k) end

  -- Replicated ValueBases (PlayerGui + ReplicatedStorage)
  local repFinds = probeReplicated(player)
  for k,v in pairs(repFinds) do record("Rep_"..k, v, k) end

  -- Choose winners (or forced overrides)
  local damage, damageWhere = forcedD or nil, forcedD and "forced" or "n/a"
  local health, healthWhere = forcedH or nil, forcedH and "forced" or "n/a"

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

  -- Debug dump
  dprint(debugNow, ("Player Stats | DAMAGE: %s  (from %s) |  HEALTH: %s (from %s)")
    :format(tostring(damage), tostring(damageWhere), tostring(health), tostring(healthWhere)))
  if debugNow then
    dprint(true, "All detected sources (non-zero):")
    local keys = {}
    for k in pairs(sources) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = sources[k]
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

  local lastStatPrint = 0
  while getEnabled() do
    local character = utils.waitForCharacter()
    if not character or not character:FindFirstChild("HumanoidRootPart") then
      task.wait(0.05)
      continue
    end

    local doPrint = debugFlag and (tick() - lastStatPrint > 3)
    local pDmg, pHP = getPlayerStats(doPrint)
    if doPrint then lastStatPrint = tick() end

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
