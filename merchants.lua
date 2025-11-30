-- merchants.lua – Auto‑buy mythics from merchants.
-- Updated for clarity, safety, and to fix the syntax error.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local M = {}

-- --------------------------------------------------------------------
-- Utilities
-- --------------------------------------------------------------------
local function getUtils()
    local p = script and script.Parent
    if p and p._deps and p._deps.utils then
        return p._deps.utils
    end
    if rawget(getfenv(), "__WOODZ_UTILS") then
        return __WOODZ_UTILS
    end
    return { notify = warn }  -- fallback if nothing else is available
end

local utils = getUtils()

-- --------------------------------------------------------------------
-- Remote lookup
-- --------------------------------------------------------------------
local merchantRemote = nil

-- Helper to build the expected path
local function buildRemotePath(serviceName)
    return {
        "Packages",      -- 1
        "Knit",          -- 2
        "Services",      -- 3
        serviceName,     -- 4 – passed in
        "RF",            -- 5
        "MerchentBuy"    -- 6
    }
end

local function setupRemote(serviceName)
    if type(serviceName) ~= "string" or serviceName == "" then
        utils.notify("Merchants", "Invalid service name supplied.", 5)
        return false
    end

    local ok, err = pcall(function()
        local parent = ReplicatedStorage
        for _, childName in ipairs(buildRemotePath(serviceName)) do
            parent = parent:WaitForChild(childName, 1)  -- 1‑second timeout
            if not parent then
                error("Missing child: " .. childName)
            end
        end
        merchantRemote = parent
    end)

    if not ok then
        utils.notify("Merchants", "Failed to find MerchantBuy remote: " .. tostring(err), 5)
        merchantRemote = nil
        return false
    end

    utils.notify("Merchants", "MerchantBuy remote ready for " .. serviceName, 3)
    return true
end

-- --------------------------------------------------------------------
-- Auto‑buy loop
-- --------------------------------------------------------------------
function M.autoBuyLoop(serviceName, flagGetter, onBuy)
    -- Ensure we have a valid remote before starting the loop
    if not setupRemote(serviceName) then
        return
    end

    task.spawn(function()
        while flagGetter() do
            pcall(function()
                -- RemoteFunction or RemoteEvent – be defensive
                if merchantRemote and merchantRemote:IsA("RemoteFunction") then
                    merchantRemote:InvokeServer("Mythic")  -- Replace "Mythic" if needed
                elseif merchantRemote and merchantRemote:IsA("RemoteEvent") then
                    merchantRemote:FireServer("Mythic")
                else
                    utils.notify("Merchants", "MerchantBuy remote is not a RemoteFunction/RemoteEvent", 5)
                end
                if onBuy then onBuy() end
            end)
            task.wait(1)  -- Purchase every 1 second
        end
    end)
end

return M