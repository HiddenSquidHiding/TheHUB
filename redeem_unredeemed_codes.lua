-- redeem_unredeemed_codes.lua
-- Fetches CodesRedeemed for LocalPlayer, compares to GameSettings.ActiveCodes,
-- and (optionally) redeems only the codes you haven't redeemed yet via ShopService.RF.SubmitCode.

-- 🔧 Safe utils access
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  -- minimal fallbacks
  return {
    notify = function(title, msg) print(("[%s] %s"):format(title, msg)) end,
  }
end

local utils = getUtils()

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local M = {}

----------------------------------------------------------------------
-- Internals
----------------------------------------------------------------------

local function safeRequire(mod)
  local ok, res = pcall(function() return require(mod) end)
  if not ok then return nil, res end
  return res
end

local function findService(servicesFolder, names)
  for _, n in ipairs(names) do
    local s = servicesFolder:FindFirstChild(n)
    if s then return s end
  end
  return nil
end

local function getLookupRF()
  -- Service name could be "LookupService" or "LookUpService"
  local pkg = ReplicatedStorage:FindFirstChild("Packages")
  local knit = pkg and pkg:FindFirstChild("Knit")
  local services = knit and knit:FindFirstChild("Services")
  if not services then return nil end
  local lookup = findService(services, {"LookupService","LookUpService"})
  local rf = lookup and lookup:FindFirstChild("RF")
  local getPD = rf and rf:FindFirstChild("GetPlayerData")
  return getPD
end

local function getSubmitCodeRemote()
  -- Expected: ReplicatedStorage.Packages.Knit.Services.ShopService.RF.SubmitCode
  local pkg = ReplicatedStorage:FindFirstChild("Packages")
  local knit = pkg and pkg:FindFirstChild("Knit")
  local services = knit and knit:FindFirstChild("Services")
  local shop = services and services:FindFirstChild("ShopService")
  local rf = shop and shop:FindFirstChild("RF")
  local remote = rf and rf:FindFirstChild("SubmitCode")
  if remote then return remote end

  -- Fallback search
  for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
    if v.Name == "SubmitCode" and (v:IsA("RemoteFunction") or v:IsA("RemoteEvent")) then
      return v
    end
  end
  return nil
end

local function toListFromMaybeDict(t)
  local out = {}
  if type(t) ~= "table" then return out end
  local isArray = rawget(t, 1) ~= nil
  if isArray then
    for _, v in ipairs(t) do
      if type(v) == "string" then table.insert(out, v) end
    end
  else
    for k, _ in pairs(t) do
      if type(k) == "string" then table.insert(out, k) end
    end
  end
  table.sort(out, function(a,b) return a:lower() < b:lower() end)
  return out
end

local function toSetLower(listLike)
  local set = {}
  for _, v in ipairs(listLike) do
    if type(v) == "string" then set[v:lower()] = true end
  end
  return set
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Returns:
--  redeemedList: array of strings
--  allCodes:     array of strings (ActiveCodes)
--  toRedeem:     array of strings (Active - Redeemed)
function M.computeUnredeemed()
  local localUserId = Players.LocalPlayer.UserId

  -- 1) Get redeemed list
  local lookupRF = getLookupRF()
  if not lookupRF then
    return nil, nil, nil, "[Codes] LookupService RF GetPlayerData not found"
  end

  local okPD, playerData = pcall(function()
    return lookupRF:InvokeServer(localUserId)
  end)
  if not okPD then
    return nil, nil, nil, "[Codes] GetPlayerData failed: " .. tostring(playerData)
  end

  local redeemedRaw = type(playerData) == "table" and playerData.CodesRedeemed or nil
  local redeemedList = toListFromMaybeDict(redeemedRaw)
  local redeemedSet = toSetLower(redeemedList)

  -- 2) Load ActiveCodes
  local gsMod = ReplicatedStorage:FindFirstChild("GameSettings")
  if not gsMod or not gsMod:IsA("ModuleScript") then
    return redeemedList, nil, nil, "[Codes] GameSettings ModuleScript not found"
  end

  local gs, errGS = safeRequire(gsMod)
  if not gs then
    return redeemedList, nil, nil, "[Codes] require(GameSettings) failed: " .. tostring(errGS)
  end

  local activeCodesTbl = (type(gs)=="table" and (gs.ActiveCodes or (gs.module_upvr and gs.module_upvr.ActiveCodes))) or nil
  if type(activeCodesTbl) ~= "table" then
    return redeemedList, nil, nil, "[Codes] ActiveCodes table not found in GameSettings"
  end

  local allCodes = {}
  for codeName, _ in pairs(activeCodesTbl) do
    if type(codeName) == "string" then table.insert(allCodes, codeName) end
  end
  table.sort(allCodes, function(a,b) return a:lower() < b:lower() end)

  local toRedeem = {}
  for _, code in ipairs(allCodes) do
    if not redeemedSet[code:lower()] then
      table.insert(toRedeem, code)
    end
  end

  return redeemedList, allCodes, toRedeem, nil
end

-- Redeem a list of codes. Options:
--   opts.concurrent (bool, default true)
--   opts.delayBetween (number, default 0.25 when concurrent=false)
-- Returns successCount, failCount
function M.redeemList(codes, opts)
  opts = opts or {}
  local concurrent   = (opts.concurrent ~= false)
  local delayBetween = opts.delayBetween or 0.25

  local submitRemote = getSubmitCodeRemote()
  if not submitRemote then
    utils.notify("Codes", "SubmitCode remote not found")
    return 0, #codes
  end

  local okCount, errCount = 0, 0

  local function redeemOne(code)
    if submitRemote:IsA("RemoteFunction") then
      local ok, res = pcall(function() return submitRemote:InvokeServer(code) end)
      if ok then
        okCount += 1
        print(("[Codes] OK %s -> %s"):format(code, tostring(res)))
      else
        errCount += 1
        warn(("[Codes] ERR %s -> %s"):format(code, tostring(res)))
      end
    else
      local ok, err = pcall(function() submitRemote:FireServer(code) end)
      if ok then
        okCount += 1
        print(("[Codes] OK %s -> fired"):format(code))
      else
        errCount += 1
        warn(("[Codes] ERR %s -> %s"):format(code, tostring(err)))
      end
    end
  end

  if concurrent then
    for _, code in ipairs(codes) do
      task.spawn(redeemOne, code)
    end
    task.wait(0.3 + math.min(#codes * 0.01, 1))
  else
    for _, code in ipairs(codes) do
      redeemOne(code)
      task.wait(delayBetween)
    end
  end

  return okCount, errCount
end

-- One-shot helper that does compute + (optional) redeem.
-- opts:
--   dryRun (bool) -> if true, do not redeem; just show a preview
--   concurrent, delayBetween -> pass to redeemList when not dryRun
function M.run(opts)
  opts = opts or {}
  local redeemed, allCodes, toRedeem, err = M.computeUnredeemed()
  if err then
    utils.notify("Codes", err)
    return false
  end

  utils.notify("Codes", ("Active:%d | Already:%d | Missing:%d"):format(#allCodes, #redeemed, #toRedeem))

  if opts.dryRun then
    print("[Codes] --- Preview: Unredeemed codes ---")
    for i, c in ipairs(toRedeem) do print(string.format("[%03d] %s", i, c)) end
    return true
  end

  if #toRedeem == 0 then
    utils.notify("Codes", "Nothing to redeem — you're up to date!")
    return true
  end

  local okC, errC = M.redeemList(toRedeem, { concurrent = opts.concurrent, delayBetween = opts.delayBetween })
  utils.notify("Codes", ("Redeem finished. OK:%d ERR:%d"):format(okC, errC))
  return okC > 0
end

return M
