-- merchants.lua
-- Merchant Mythic auto-buy logic

-- 🔧 Safe utils access
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[merchants.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading merchants.lua")
end

local utils = getUtils()
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
      setBtnText('(remote?)')
      utils.notify('🌲 Merchant', serviceName .. ': MerchentBuy remote not found. Retrying...', 3)
      task.wait(1.5)
    else
      local ok, res = pcall(function() return remote:InvokeServer(sku) end)
      if not ok then
        consecutiveFails += 1
        setBtnText('(fail)')
        task.wait(math.clamp(merchantCooldown * (1 + consecutiveFails * 0.5), 0.2, 3))
      else
        local good = merchantResultOK(res)
        if good then
          consecutiveFails = 0
          setBtnText('(ok)')
          task.wait(merchantCooldown)
        else
          consecutiveFails += 1
          local msg = typeof(res) == 'table' and 'table' or tostring(res)
          setBtnText('(fail)')
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
