-- merchants.lua
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local constants = require(script.Parent.constants)
local utils = require(script.Parent._deps.utils)

local M = {}

local function getMerchentBuyRemoteByService(serviceName)
  local packages = ReplicatedStorage:FindFirstChild('Packages') or ReplicatedStorage:WaitForChild('Packages',5)
  local knit     = packages and (packages:FindFirstChild('Knit') or packages:WaitForChild('Knit',5))
  local services = knit and (knit:FindFirstChild('Services') or knit:WaitForChild('Services',5))
  local svc      = services and (services:FindFirstChild(serviceName) or services:WaitForChild(serviceName,5))
  local rfFolder = svc and (svc:FindFirstChild('RF') or svc:WaitForChild('RF',5))
  local remote   = rfFolder and (rfFolder:FindFirstChild('MerchentBuy') or rfFolder:WaitForChild('MerchentBuy',5))
  if remote and remote:IsA('RemoteFunction') then return remote end
  return nil
end

local function merchantResultOK(res)
  local t = typeof(res)
  if t=='boolean' then return res end
  if t=='string' then local s=res:lower(); return s:find('ok') or s:find('success') or s=='true' end
  if t=='table' then return (res.ok==true) or (res.success==true) or (res.Success==true) or (res[1]==true) end
  return false
end

function M.autoBuyLoop(serviceName, getEnabled, setBtnText)
  local idx, fails = 1, 0
  while getEnabled() do
    local sku = constants.mythicSkus[idx]; idx = (idx % #constants.mythicSkus)+1
    local remote = getMerchentBuyRemoteByService(serviceName)
    if not remote then setBtnText('(remote?)'); utils.notify('🌲 Merchant',serviceName..': MerchentBuy remote not found. Retrying...',3); task.wait(1.5)
    else
      local ok, res = pcall(function() return remote:InvokeServer(sku) end)
      if not ok then
        fails += 1; setBtnText('(fail)')
        task.wait(math.clamp(constants.merchantCooldown * (1 + fails * 0.5), 0.2, 3))
      else
        local good = merchantResultOK(res)
        if good then fails=0; setBtnText('(ok)'); task.wait(constants.merchantCooldown)
        else
          fails += 1; local msg = typeof(res)=='table' and 'table' or tostring(res); setBtnText('(fail')
          msg = tostring(msg):lower()
          local extra = (msg:find('cooldown') or msg:find('too fast')) and 0.4 or (msg:find('insufficient') or msg:find('not enough')) and 0.6 or 0
          task.wait(constants.merchantCooldown + extra)
        end
      end
    end
  end
end

return M
