-- smart_target.lua
-- Smart-targets mobs you can safely kill using MonsterInfo + REAL player stats.
-- Super-robust stat resolver with deep probes and detailed console prints.

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

----------------------------------------------------------------------
-- Table & Instance scanners
----------------------------------------------------------------------
local function deepFindNumber(tbl, keys, maxDepth)
  maxDepth = maxDepth or 7
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

local function valueObjectToNumber(obj)
  if not obj or not obj:IsA("ValueBase") then return nil end
  if obj:IsA("NumberValue") or obj:IsA("IntValue") then return obj.Value end
  if obj:IsA("StringValue") then return parseNumber(obj.Value) end
  local v = rawget(obj, "Value")
  return parseNumber(v)
end

local function textToNumber(label)
  if not label or not label:IsA("TextLabel") then return nil end
  local txt = tostring(label.Text or "")
  -- grab the biggest number looking substring
  local candidate = txt:match("([%d%.,]+%a?)") or txt:match("([%d%.,]+)")
  return candidate and parseNumber(candidate) or nil
end

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
      local nl = v.Name:lower()
      for _, key in ipairs(wantDamage and damageKeys or healthKeys) do
        if nl:find(key, 1, true) then
          local n = valueObjectToNumber(v)
          if n and (not best or n > best) then best, source = n, v:GetFullName() end
        end
      end
    elseif v:IsA("TextLabel") and wantDamage then
      local n = textToNumber(v)
      if n and (not best or n > best) then best, source = n, v:GetFullName()..":Text" end
    elseif v:IsA("ModuleScript") then
      local ok, tbl = pcall(function() return require(v) end)
      if ok and type(tbl) == "table" then
        local n, k = deepFindNumber(tbl, wantDamage and damageKeys or healthKeys)
        if n and (not best or n > best) then best, source = n, v:GetFullName()..":table("..tostring(k)..")" end
      end
    end
  end
  local nAttr, where = getAttributesNumber(folder, wantDamage and damageKeys or healthKeys)
  if nAttr and (not best or nAttr > best) then best, source = nAttr, folder:GetFullName().."@"..where end
  return best, source
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
local function probeKnitRemotes()
  local out = {}
  local okKnit, knit = pcall(function() return ReplicatedStorage.Packages.Knit end)
  if not okKnit or not knit then return out end
  local okServices, services = pcall(function() return knit.Services end)
  if not okServices or not services then return out end

  local candidateServices = { "LookupService","StatsService","CombatService","PlayerService","DamageService","ProfileService" }
  local candidateMethods  = { "GetPlayerData","GetStats","GetPlayerStats","GetInfo","GetDamage","GetPower","GetProfile" }

  for _, svcName in ipairs(candidateServices) do
    local svc = services:FindFirstChild(svcName)
    if svc then
      local RF = svc:FindChild("RF") or svc:FindFirstChild("RF")
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

-- Careful brute-force: only RFs with promising names; invoke without args
local function probeReplicatedRFs()
  local found = {}
  local function promising(name)
    local n = name:lower()
    return n:find("damage",1,true) or n:find("power",1,true) or n:find("stat",1,true)
        or n:find("info",1,true) or n:find("data",1,true) or n:find("profile",1,true)
  end
  for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
    if d:IsA("RemoteFunction") and promising(d.Name) then
      local ok, res = pcall(function() return d:InvokeServer() end)
      if ok and res ~= nil then
        found[d:GetFullName()] = res
      end
    end
  end
  return found
end

-- Per-player data folders in ReplicatedStorage commonly used by games
local function probePerPlayerData(player)
  local candidates = {
    {"PlayerData", tostring(player.UserId)},
    {"PlayersData", tostring(player.UserId)},
    {"Profiles", tostring(player.UserId)},
    {"Profiles"},
    {"DataStore","Players", tostring(player.UserId)},
    {"GameData","Players", tostring(player.UserId)},
  }
  local results = {}
  for _, path in ipairs(candidates) do
    local node = ReplicatedStorage
    local ok = true
    for _, name in ipairs(path) do
      node = node:FindFirstChild(name)
      if not node then ok=false; break end
    end
    if ok and node then
      if node:IsA("ModuleScript") then
        local ok2, tbl = pcall(function() return require(node) end)
        if ok2 and type(tbl) == "table" then results[node:GetFullName()] = tbl end
      elseif #node:GetChildren() > 0 then
        results[node:GetFullName()] = node
      end
    end
  end
  return results
end

-- Tools (Backpack + Character)
local function probeTools(player)
  local results = {}
  local function scanContainer(cont)
    if not cont then return end
    for _, tool in ipairs(cont:GetChildren()) do
      if tool:IsA("Tool") or tool:IsA("Accessory") then
        local nd, wd = getAttributesNumber(tool, damageKeys); if nd then results[tool:GetFullName()..".AttrDamage"] = nd end
        local nh, wh = getAttributesNumber(tool, healthKeys); if nh then results[tool:GetFullName()..".AttrHealth"] = nh end
        for _, v in ipairs(tool:GetDescendants()) do
          if v:IsA("ValueBase") then
            local nl = v.Name:lower()
            for _, key in ipairs(damageKeys) do
              if nl:find(key,1,true) then local n=valueObjectToNumber(v); if n then results[v:GetFullName()] = n end end
            end
            for _, key in ipairs(healthKeys) do
              if nl:find(key,1,true) then local n=valueObjectToNumber(v); if n then results[v:GetFullName()] = n end end
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

-- PlayerGui & Humanoid scans
local function probeUIAndHumanoid(player)
  local results = {}
  local gui = player:FindFirstChild("PlayerGui")
  if gui then
    local d, src = extractFromFolder(gui, true);  if d then results[src or (gui:GetFullName()..":UI_Damage")] = d end
    local h, src2= extractFromFolder(gui, false); if h then results[src2 or (gui:GetFullName()..":UI_Health")] = h end
  end
  local char = player.Character
  if char then
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
      local ad, as = getAttributesNumber(hum, damageKeys); if ad then results["Humanoid@"..(as or "Attr")] = ad end
      local ah, as2= getAttributesNumber(hum, healthKeys); if ah then results["Humanoid@"..(as2 or "Attr")] = ah end
      for _, v in ipairs(hum:GetChildren()) do
        if v:IsA("ValueBase") then
          local nl = v.Name:lower()
          for _, key in ipairs(damageKeys) do if nl:find(key,1,true) then local n=valueObjectToNumber(v); if n then results[v:GetFullName()] = n end end end
          for _, key in ipairs(healthKeys) do if nl:find(key,1,true) then local n=valueObjectToNumber(v); if n then results[v:GetFullName()] = n end end end
        end
      end
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
      local ad, as = getAttributesNumber(hrp, damageKeys); if ad then results["HRP@"..(as or "Attr")] = ad end
      local ah, as2= getAttributesNumber(hrp, healthKeys); if ah then results["HRP@"..(as2 or "Attr")] = ah end
    end
  end
  return results
end

local function getPlayerStats(debugNow)
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

  local sources = {}
  local function record(tag, n, where)
    if n and n > 0 then sources[tag] = { value = n, where = where } end
  end

  if humanoid then
    local hMax = humanoid.MaxHealth and humanoid.MaxHealth > 0 and humanoid.MaxHealth or nil
    record("HumanoidMaxHealth", hMax, "Humanoid.MaxHealth")
    record("HumanoidHealth", humanoid.Health, "Humanoid.Health")
  end

  local knitRes = probeKnitRemotes()
  for k, payload in pairs(knitRes) do
    if type(payload) == "table" then
      local d, dk = deepFindNumber(payload, damageKeys)
      local h, hk = deepFindNumber(payload, healthKeys)
      record("KnitRF_Damage_"..k, d, k..":"..tostring(dk))
      record("KnitRF_Health_"..k, h, k..":"..tostring(hk))
    else
      local n = parseNumber(payload)
      if n then record("KnitRF_Number_"..k, n, k) end
    end
  end

  local rfPayloads = probeReplicatedRFs()
  for k, payload in pairs(rfPayloads) do
    if type(payload) == "table" then
      local d, dk = deepFindNumber(payload, damageKeys)
      local h, hk = deepFindNumber(payload, healthKeys)
      record("RF_Damage_"..k, d, k..":"..tostring(dk))
      record("RF_Health_"..k, h, k..":"..tostring(hk))
    else
      local n = parseNumber(payload)
      if n then record("RF_Number_"..k, n, k) end
    end
  end

  local ls = player:FindFirstChild("leaderstats")
  if ls then
    local d1, s1 = extractFromFolder(ls, true);  record("LS_Damage", d1, s1)
    local h1, s2 = extractFromFolder(ls, false); record("LS_Health", h1, s2)
  end

  for _, name in ipairs({ "Stats","PlayerStats","PlayerData","Data","Attributes","Info" }) do
    local n = player:FindFirstChild(name)
    if n then
      local d2, sd2 = extractFromFolder(n, true);  record("P_"..name.."_Damage", d2, sd2)
      local h2, sh2 = extractFromFolder(n, false); record("P_"..name.."_Health", h2, sh2)
      local ad, as  = getAttributesNumber(n, damageKeys); if ad then record("P_"..name.."_AttrDamage", ad, as) end
      local ah, as2 = getAttributesNumber(n, healthKeys); if ah then record("P_"..name.."_AttrHealth", ah, as2) end
    end
  end

  local perPlayer = probePerPlayerData(player)
  for k, payload in pairs(perPlayer) do
    if typeof(payload) == "Instance" then
      local d3, sd3 = extractFromFolder(payload, true);  record("RS_PlayerData_Damage@"..k, d3, k)
      local h3, sh3 = extractFromFolder(payload, false); record("RS_PlayerData_Health@"..k, h3, k)
    elseif type(payload) == "table" then
      local d4, dk4 = deepFindNumber(payload, damageKeys); record("RS_PlayerTable_Damage@"..k, d4, k..":"..tostring(dk4))
      local h4, hk4 = deepFindNumber(payload, healthKeys); record("RS_PlayerTable_Health@"..k, h4, k..":"..tostring(hk4))
    end
  end

  for k,v in pairs(probeTools(player)) do record("Tool@"..k, v, k) end
  for k,v in pairs(probeUIAndHumanoid(player)) do record("UIHum@"..k, v, k) end

  do
    local ad, as = getAttributesNumber(player, damageKeys); if ad then record("Attr_Damage_Player", ad, as) end
    local ah, as2= getAttributesNumber(player, healthKeys); if ah then record("Attr_Health_Player", ah, as2) end
    local cd, cs = getAttributesNumber(character, damageKeys); if cd then record("Attr_Damage_Char", cd, cs) end
    local ch, cs2= getAttributesNumber(character, healthKeys); if ch then record("Attr_Health_Char", ch, cs2) end
  end

  local damage, damageWhere = forcedD or nil, forcedD and "forced" or "n/a"
  local health, healthWhere = forcedH or nil, forcedH and "forced" or "n/a"

  for k, v in pairs(sources) do
    if k:lower():find("damage") or k:lower():find("power") or k:lower():find("attack") then
      if not damage or v.value > damage then damage, damageWhere = v.value, v.where end
    end
  end
  for k, v in pairs(sources) do
    if k:lower():find("health") or k:lower():find("hp") then
      if not health or v.value > health then health, healthWhere = v.value, v.where end
    end
  end

  if not damage or damage <= 0 then damage, damageWhere = 100, "fallback:100" end
  if not health or health <= 0 then
    local hh = humanoid and (humanoid.MaxHealth > 0 and humanoid.MaxHealth or humanoid.Health) or 1000
    health, healthWhere = hh, "humanoidFallback"
  end

  if debugNow then
    local items = {}
    for k,v in pairs(sources) do table.insert(items, {k=k, v=v}) end
    table.sort(items, function(a,b) return a.v.value > b.v.value end)
    dprint(true, ("Player Stats | DAMAGE: %s  (from %s) | HEALTH: %s (from %s)")
      :format(tostring(damage), tostring(damageWhere), tostring(health), tostring(healthWhere)))
    dprint(true, "Top detected sources (non-zero):")
    for i=1, math.min(#items, 20) do
      local it = items[i]
      dprint(true, ("  [%2d] %-90s = %-24s @ %s"):format(i, it.k, tostring(it.v.value), tostring(it.v.where)))
    end
  end

  return damage, health
end

----------------------------------------------------------------------
-- Targeting logic / driver
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

local function attackEnemy(player, enemy, onText, autoAttackRemote)
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

function M.runSmartFarm(getEnabled, setTargetText, opts)
  opts = opts or {}
  local debugFlag = isDebug(opts)
  local player = Players.LocalPlayer

  local ok, remote = pcall(function()
    return ReplicatedStorage:WaitForChild('Packages'):WaitForChild('Knit')
      :WaitForChild('Services'):WaitForChild('MonsterService')
      :WaitForChild('RF'):WaitForChild('RequestAttack')
  end)
  if not (ok and remote and remote:IsA('RemoteFunction')) then
    utils.notify("🌲 Smart Target", "RequestAttack remote NOT found.", 4)
    return
  end
  local autoAttackRemote = remote

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
        local entry = monsterInfo[enemy.Name]
        local mHealth = hum.Health
        local mAttack = 10
        if type(entry) == "table" then
          local h = entry.Health or entry.health or entry.MaxHealth or entry.maxhealth
          local a = entry.Attack or entry.attack or entry.Damage or entry.damage
          mHealth = parseNumber(h) or mHealth
          mAttack = parseNumber(a) or mAttack
        elseif type(entry) == "string" or type(entry) == "number" then
          mHealth = parseNumber(entry) or mHealth
        end

        local dmg = pDmg > 0 and pDmg or 1
        local hitsToKill = math.ceil((mHealth > 0 and mHealth or 1) / dmg)
        local estDamageTaken = hitsToKill * (mAttack > 0 and mAttack or 0)
        local can = estDamageTaken < (pHP * (opts.safetyBuffer or 0.8))
        if can then table.insert(candidates, enemy) end
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
      attackEnemy(player, enemy, setTargetText, autoAttackRemote)
    end

    task.wait(0.01)
  end
end

return M
