-- crates.lua
-- Crates inventory + auto-open loop

-- 🔧 Safe utils access
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[crates.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading crates.lua")
end

local utils = getUtils()
local ReplicatedStorage = game:GetService('ReplicatedStorage')

-- Internal state
local cratesRF_Use = nil
local cratesRE_UnlockFinish = nil
_G.unlockIdQueue = _G.unlockIdQueue or {}
local seenUnlockIds = {}
local crateCounts = {}
local lastInvFetch = 0
local INV_REFRESH_COOLDOWN = 5

-- Known crate names (order to try). We will skip those with 0 in inventory.
local crateNames = {
  'Bronze Crate','Silver Crate','Golden Crate','Demon Crate','Sahur Crate','Void Crate','Vault Crate',
  'Lime Crate','Chairchachi Crate','To To To Crate','Market Crate','Gummy Crate','Yoni Crate',
  'Grapefruit Crate','Bus Crate','Cheese Crate','Graipus Crate','Pasta Crate','Te Te Te Te Crate',
}

-- Helpers -----------------------------------------------------
local function looksLikeId(s)
  if typeof(s) ~= 'string' then return false end
  if (#s >= 20 and #s <= 64) and s:match('^[0-9a-fA-F%-]+$') then return true end
  if s:match('^%d+$') and #s >= 6 then return true end
  return false
end

local KNOWN_ID_KEYS = {'id','Id','ID','unlockId','unlock_id','UnlockId','ticket','Ticket','crateId','CrateId','resultId','ResultId','uid','UUID','Uuid'}

local function scanForIds(x, out)
  out = out or {}
  local t = typeof(x)
  if t == 'string' and looksLikeId(x) then
    table.insert(out, x)
  elseif t == 'table' then
    for k, v in pairs(x) do
      if type(k) == 'string' then
        for _, key in ipairs(KNOWN_ID_KEYS) do
          if k == key and typeof(v) == 'string' and looksLikeId(v) then
            table.insert(out, v)
          end
        end
      end
      scanForIds(v, out)
    end
  end
  return out
end

-- Sniffer -----------------------------------------------------
local function dumpCrateEvent(_, ...)
  local args = {...}
  local ids = {}
  for i=1,#args do scanForIds(args[i], ids) end
  for _, id in ipairs(ids) do table.insert(_G.unlockIdQueue, id) end
end

local function getCratesUseRF()
  if cratesRF_Use and cratesRF_Use.Parent then return cratesRF_Use end
  local pkg = ReplicatedStorage:FindFirstChild('Packages') or ReplicatedStorage:WaitForChild('Packages')
  local knit = pkg:FindFirstChild('Knit') or pkg:WaitForChild('Knit')
  local svcs = knit:FindFirstChild('Services') or knit:WaitForChild('Services')
  local svc  = svcs:FindFirstChild('CratesService') or svcs:WaitForChild('CratesService')
  local RF   = svc:FindFirstChild('RF') or svc:WaitForChild('RF')
  local rf   = RF:FindFirstChild('UseCrateItem') or RF:WaitForChild('UseCrateItem')
  if rf and rf:IsA('RemoteFunction') then cratesRF_Use = rf return rf end
  return nil
end

local M = {}

function M.sniffCrateEvents()
  local pkg = ReplicatedStorage:WaitForChild('Packages')
  local knit = pkg:WaitForChild('Knit')
  local svcs = knit:WaitForChild('Services')
  local svc  = svcs:WaitForChild('CratesService')
  local RE   = svc:WaitForChild('RE')

  for _, ch in ipairs(RE:GetChildren()) do
    if ch:IsA('RemoteEvent') then
      ch.OnClientEvent:Connect(function(...) dumpCrateEvent(ch.Name, ...) end)
    end
  end
  RE.ChildAdded:Connect(function(ch)
    if ch:IsA('RemoteEvent') then
      ch.OnClientEvent:Connect(function(...) dumpCrateEvent(ch.Name, ...) end)
    end
  end)

  cratesRE_UnlockFinish = RE:FindFirstChild('UnlockCratesFinished')
end

-- Unlock worker (reads _G.unlockIdQueue)
function M.unlockWorker()
  while true do
    local id = table.remove(_G.unlockIdQueue, 1)
    if id then
      if not seenUnlockIds[id] then
        seenUnlockIds[id] = true
        pcall(function()
          if cratesRE_UnlockFinish and cratesRE_UnlockFinish:IsA('RemoteEvent') then
            cratesRE_UnlockFinish:FireServer(id)
          end
        end)
      end
    else
      task.wait(0.05)
    end
  end
end

-- Inventory ---------------------------------------------------
local function addCrateCount(map, name, count)
  if typeof(name)~='string' then return end
  if not name:lower():find('crate') then return end
  local n = tonumber(count) or 0
  if n<=0 then return end
  map[name] = (map[name] or 0) + n
end

local function parseInventoryResult(res, out)
  out = out or {}
  if typeof(res) ~= 'table' then return out end

  if #res > 0 then
    for i=1,#res do
      local it = res[i]
      if typeof(it) == 'table' then
        local n = it.Name or it.name or it.DisplayName or it.ItemName or it.crateName or it.CrateName
        local c = it.Count or it.count or it.Amount or it.amount or it.qty or it.Qty or it.quantity or it.Quantity or it.Owned or it.owned
        if n and c then addCrateCount(out, n, c) end
      end
    end
  end

  for k,v in pairs(res) do
    if typeof(k)=='string' and (typeof(v)=='number' or typeof(v)=='string') then
      if k:lower():find('crate') then addCrateCount(out, k, v) end
    end
  end
  return out
end

local function fetchCrateInventory()
  local counts = {}
  local useRF = getCratesUseRF()
  local rfFolder = useRF and useRF.Parent
  if not rfFolder then return counts end

  local candidates = {'GetOwnedCrates','GetCrates','GetInventory'}
  for _, nm in ipairs(candidates) do
    local rf = rfFolder:FindFirstChild(nm)
    if rf and rf:IsA('RemoteFunction') then
      local ok, res = pcall(function() return rf:InvokeServer() end)
      if ok and res then parseInventoryResult(res, counts); break end
    end
  end
  return counts
end

local function refreshCrateInventory(forceRefresh)
  if not forceRefresh and (tick() - lastInvFetch) < INV_REFRESH_COOLDOWN then
    return crateCounts
  end
  local newCounts = fetchCrateInventory()
  if next(newCounts) ~= nil then
    crateCounts = newCounts
    lastInvFetch = tick()
  end
  return crateCounts
end
M.refreshCrateInventory = refreshCrateInventory

-- Auto open ---------------------------------------------------
local function tryUnlockFromReturn(ret)
  if ret == nil then return end
  local ids = (function() local t = {}; scanForIds(ret, t); return t end)()
  for _, id in ipairs(ids) do table.insert(_G.unlockIdQueue, id) end
end

function M.autoOpenCratesEnabledLoop(getEnabled)
  while getEnabled() do
    local rf = getCratesUseRF()
    if not rf then
      utils.notify('🎁 Crates', 'UseCrateItem RF not found, retrying...', 3)
      task.wait(1)
    else
      refreshCrateInventory(false)
      for _, crate in ipairs(crateNames) do
        if not getEnabled() then break end
        local have = crateCounts[crate] or 0
        if have > 0 then
          local ok, ret = pcall(function() return rf:InvokeServer(crate, 1) end)
          if not ok then
            refreshCrateInventory(true)
          else
            crateCounts[crate] = math.max(0, (crateCounts[crate] or 0) - 1)
            tryUnlockFromReturn(ret)
            if typeof(ret) == 'string' then
              local s = ret:lower()
              if s:find('no') and s:find('crate') then refreshCrateInventory(true) end
            end
          end
          task.wait((require(script.Parent.constants).crateOpenDelay) or 1)
        end
      end
    end
  end
end

return M
