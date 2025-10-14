-- merchants.lua
-- Merchant Mythic auto-buy logic

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

local ReplicatedStorage = game:GetService('ReplicatedStorage')

local mythicSkus = { 'Mythic1', 'Mythic2', 'Mythic3', 'Mythic4' }
local merchantCooldown = 0.1

local function getMerchentBuyRemoteByService(serviceName)
  local packages = ReplicatedStorage:FindFirstChild('Packages') or ReplicatedStorage:WaitForChild('Packages', 5)
  local knit = packages and (packages:FindFirstChild('Knit') or packages:WaitForChild('Knit', 5))
  local services = knit and (knit:FindFirstChild('Services') or knit:WaitForChild('Services', 5))
  local svc = services and (services:FindFirstChild(serviceName) or services:WaitForChild(serviceName, 5))
  local rf = svc and (svc:FindFirstChild('RF') or svc:WaitForChild('RF', 5))
  local remote = rf and (rf:FindFirstChild('MerchentBuy') or rf:WaitForChild('MerchentBuy', 5))
  if remote and remote:IsA('RemoteFunction') then return remote end
  return nil
end

local function merchantResultOK(res)
  local t = typeof(res)
  if t == 'boolean' then return res end
  if t == 'string' then
    local s = res:lower()
    return s:find('ok') or s:find('success') or s == 'true'
  end
  if t == 'table' then
    return (res.ok == true) or (res.success == true) or (res.Success == true) or (res[1] == true)
  end
  return false
end

local M = {}

function M.autoBuyLoop(serviceName, getEnabled, setBtnText)
  local idx, consecutiveFails = 1, 0
  while getEnabled() do
    local sku = mythicSkus[idx]
    idx = (idx % #mythicSkus) + 1

    local remote = getMerchentBuyRemoteByService(serviceName)
    if not remote then
      if setBtnText then setBtnText('(remote?)') end
      utils.notify('🌲 Merchant', serviceName .. ': MerchentBuy remote not found. Retrying...', 3)
      task.wait(1.5)
    else
      local ok, res = pcall(function() return remote:InvokeServer(sku) end)
      if not ok then
        consecutiveFails += 1
        if setBtnText then setBtnText('(fail)') end
        task.wait(math.clamp(merchantCooldown * (1 + consecutiveFails * 0.5), 0.2, 3))
      else
        local good = merchantResultOK(res)
        if good then
          consecutiveFails = 0
          if setBtnText then setBtnText('(ok)') end
          task.wait(merchantCooldown)
        else
          consecutiveFails += 1
          local msg = typeof(res) == 'table' and 'table' or tostring(res)
          if setBtnText then setBtnText('(fail)') end
          msg = tostring(msg):lower()
          local extra = (msg:find('cooldown') or msg:find('too fast')) and 0.4
                     or (msg:find('insufficient') or msg:find('not enough')) and 0.6
                     or 0
          task.wait(merchantCooldown + extra)
        end
      end
    end
  end
end

return M
