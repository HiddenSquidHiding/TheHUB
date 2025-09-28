-- crates.lua
local ReplicatedStorage = game:GetService('ReplicatedStorage')

local constants = require(script.Parent.constants)
local utils = require(script.Parent._deps.utils)

local M = {
  cratesRF_Use = nil,
  cratesRE_UnlockFinish = nil,
  unlockIdQueue = _G.unlockIdQueue or {},
  seenUnlockIds = {},
  crateCounts = {},
  lastInvFetch = 0,
}

local KNOWN_ID_KEYS = {'id','Id','ID','unlockId','unlock_id','UnlockId','ticket','Ticket','crateId','CrateId','resultId','ResultId','uid','UUID','Uuid'}

local function looksLikeId(s)
  if typeof(s)~='string' then return false end
  if (#s>=20 and #s<=64) and s:match('^[0-9a-fA-F%-]+$') then return true end
  if s:match('^%d+$') and #s>=6 then return true end
  return false
end

local function scanForIds(x, out)
  out = out or {}
  local t = typeof(x)
  if t=='string' and looksLikeId(x) then table.insert(out,x)
  elseif t=='table' then
    for k,v in pairs(x) do
      if type(k)=='string' then for _,key in ipairs(KNOWN_ID_KEYS) do if k==key and typeof(v)=='string' and looksLikeId(v) then table.insert(out,v) end end end
      scanForIds(v,out)
    end
  end
  return out
end

function M.sniffCrateEvents()
  local pkg = ReplicatedStorage:WaitForChild('Packages')
  local knit = pkg:WaitForChild('Knit')
  local svcs = knit:WaitForChild('Services')
  local svc = svcs:WaitForChild('CratesService')
  local RE = svc:WaitForChild('RE')
  for _, ch in ipairs(RE:GetChildren()) do if ch:IsA('RemoteEvent') then ch.OnClientEvent:Connect(function(...) local ids=scanForIds({...}); for _,id in ipairs(ids) do table.insert(M.unlockIdQueue,id) end end) end end
  RE.ChildAdded:Connect(function(ch) if ch:IsA('RemoteEvent') then ch.OnClientEvent:Connect(function(...) local ids=scanForIds({...}); for _,id in ipairs(ids) do table.insert(M.unlockIdQueue,id) end end) end end)
  M.cratesRE_UnlockFinish = RE:FindFirstChild('UnlockCratesFinished')
end

local function getCratesUseRF()
  if M.cratesRF_Use and M.cratesRF_Use.Parent then return M.cratesRF_Use end
  local pkg = ReplicatedStorage:FindFirstChild('Packages') or ReplicatedStorage:WaitForChild('Packages')
  local knit = pkg:FindFirstChild('Knit') or pkg:WaitForChild('Knit')
  local svcs = knit:FindFirstChild('Services') or knit:WaitForChild('Services')
  local svc = svcs:FindFirstChild('CratesService') or svcs:WaitForChild('CratesService')
  local RF  = svc:FindFirstChild('RF') or svc:WaitForChild('RF')
  local rf  = RF:FindFirstChild('UseCrateItem') or RF:WaitForChild('UseCrateItem')
  if rf and rf:IsA('RemoteFunction') then M.cratesRF_Use = rf end
  return M.cratesRF_Use
end

local function addCrateCount(map, name, count)
  if typeof(name)~='string' then return end
  if not name:lower():find('crate') then return end
  local n = tonumber(count) or 0
  if n<=0 then return end
  map[name] = (map[name] or 0) + n
end

local function parseInventoryResult(res, out)
  out = out or {}
  if typeof(res)~='table' then return out end
  if #res>0 then for i=1,#res do local it=res[i]; if typeof(it)=='table' then local n=it.Name or it.name or it.DisplayName or it.ItemName or it.crateName or it.CrateName; local c=it.Count or it.count or it.Amount or it.amount or it.qty or it.Qty or it.quantity or it.Quantity or it.Owned or it.owned; if n and c then addCrateCount(out,n,c) end end end end
  for k,v in pairs(res) do if typeof(k)=='string' and (typeof(v)=='number' or typeof(v)=='string') then if k:lower():find('crate') then addCrateCount(out,k,v) end end end
  return out
end

local function fetchCrateInventory()
  local counts={}
  local useRF = getCratesUseRF(); local rfFolder = useRF and useRF.Parent; if not rfFolder then return counts end
  local candidates={'GetOwnedCrates','GetCrates','GetInventory'}
  for _,nm in ipairs(candidates) do
    local rf = rfFolder:FindFirstChild(nm)
    if rf and rf:IsA('RemoteFunction') then local ok,res = pcall(function() return rf:InvokeServer() end); if ok and res then parseInventoryResult(res, counts); break end end
  end
  return counts
end

function M.refreshCrateInventory(force)
  if not force and (tick()-M.lastInvFetch) < constants.INV_REFRESH_COOLDOWN then return M.crateCounts end
  local newCounts = fetchCrateInventory()
  if next(newCounts) ~= nil then M.crateCounts = newCounts; M.lastInvFetch = tick() end
  return M.crateCounts
end

local function tryUnlockFromReturn(ret)
  if ret==nil then return end
  local ids = scanForIds(ret)
  for _, id in ipairs(ids) do table.insert(M.unlockIdQueue, id) end
end

function M.unlockWorker()
  while true do
    if M.cratesRE_UnlockFinish==nil or not M.cratesRE_UnlockFinish.Parent then
      local pkg=ReplicatedStorage:FindFirstChild('Packages') or ReplicatedStorage:WaitForChild('Packages')
      local knit=pkg:FindFirstChild('Knit') or pkg:WaitForChild('Knit')
      local svcs=knit:FindFirstChild('Services') or knit:WaitForChild('Services')
      local svc=svcs:FindFirstChild('CratesService') or svcs:WaitForChild('CratesService')
      local RE=svc:FindFirstChild('RE') or svc:WaitForChild('RE')
      M.cratesRE_UnlockFinish = RE:FindFirstChild('UnlockCratesFinished') or RE:WaitForChild('UnlockCratesFinished')
    end
    local id = table.remove(M.unlockIdQueue, 1)
    if id then if not M.seenUnlockIds[id] then M.seenUnlockIds[id]=true; pcall(function() if M.cratesRE_UnlockFinish and M.cratesRE_UnlockFinish:IsA('RemoteEvent') then M.cratesRE_UnlockFinish:FireServer(id) end end) end else task.wait(0.05) end
  end
end

function M.autoOpenCratesEnabledLoop(flagGetter)
  while flagGetter() do
    local rf = getCratesUseRF()
    if not rf then utils.notify('🎁 Crates','UseCrateItem RF not found, retrying...',3); task.wait(1)
    else
      M.refreshCrateInventory(false)
      for _, crate in ipairs(constants.crateNames) do
        if not flagGetter() then break end
        local have = M.crateCounts[crate] or 0
        if have>0 then
          local ok, ret = pcall(function() return rf:InvokeServer(crate,1) end)
          if not ok then M.refreshCrateInventory(true) else M.crateCounts[crate]=math.max(0,(M.crateCounts[crate] or 0)-1); tryUnlockFromReturn(ret); if typeof(ret)=='string' then local s=ret:lower(); if s:find('no') and s:find('crate') then M.refreshCrateInventory(true) end end end
          task.wait(constants.crateOpenDelay)
        end
      end
    end
  end
end

return M
