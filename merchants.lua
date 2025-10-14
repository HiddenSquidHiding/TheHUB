-- merchants.lua — Auto-buy mythics from merchants.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local M = {}

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = warn }
end

local utils = getUtils()

local merchantRemote = nil
local function setupRemote(serviceName)
  local ok, remote = pcall(function()
    return ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild(serviceName):WaitForChild("RF"):WaitForChild("MerchantBuy")
  end)
  if ok and remote then
    merchantRemote = remote
    return true
  end
  utils.notify("Merchants", serviceName .. ": MerchantBuy remote not found.", 5)
  return false
end

function M.autoBuyLoop(serviceName, flagGetter, onBuy)
  if not setupRemote(serviceName) then return end
  task.spawn(function()
    while flagGetter() do
      pcall(function()
        merchantRemote:InvokeServer("Mythic")  -- Assume "Mythic" arg; adjust if needed
        if onBuy then onBuy() end
      end)
      task.wait(1)  -- Buy delay
    end
  end)
end

return M
