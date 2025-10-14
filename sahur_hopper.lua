-- sahur_hopper.lua — Auto-hop servers for low-level Sahur farms.
-- Checks for players > L84 (excl. self). If clear, farms Sahur boss; else hops.
-- Integrates with farm.lua for targeting. Requires TeleportService for hops.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local farm = nil  -- Loaded via require if available

local M = { _enabled = false, running = false }

-- Load farm module if sibling (fallback to global shim)
local function getFarm()
  if farm then return farm end
  local ok, mod = pcall(function()
    return _G.__WOODZ_REQUIRE("farm")
  end)
  if ok and mod then farm = mod end
  return farm
end

-- Get my level from leaderstats
local function getMyLevel()
  local ls = player:FindFirstChild("leaderstats")
  if ls then
    local lvl = ls:FindFirstChild("Level")
    return lvl and lvl.Value or 0
  end
  return 0
end

-- Check if any other player > L84
local function hasHighLevelPlayers()
  for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= player then
      local ls = plr:FindFirstChild("leaderstats")
      if ls then
        local lvl = ls:FindFirstChild("Level")
        if lvl and lvl.Value > 84 then
          return true
        end
      end
    end
  end
  return false
end

-- Hop to new server (random public)
local function hopServer()
  local placeId = game.PlaceId
  local ok, err = pcall(TeleportService.Teleport, TeleportService, placeId, player)
  if not ok then
    warn("[Sahur Hopper] Teleport failed:", err)
  end
end

-- Farm Sahur boss (using farm module)
local function farmSahur()
  local f = getFarm()
  if not f then
    warn("[Sahur Hopper] farm.lua not available; skipping Sahur farm.")
    return false
  end

  -- 🔹 FIX: Setup remote before farming
  pcall(f.setupAutoAttackRemote)

  -- Set target to Sahur
  local sahurName = "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur"
  f.setSelected({sahurName})
  f.setFastLevelEnabled(true)  -- Enable FastLevel for boss

  -- Start auto-farm (stop on kill)
  local bossKilled = false
  local startTime = tick()
  task.spawn(function()
    f.runAutoFarm(function() return not bossKilled and (tick() - startTime < 300) end, function(text)
      if string.find(text or "", "Current Target: None") then
        bossKilled = true
      end
    end)
  end)

  -- Wait for kill (timeout 5min)
  repeat
    RunService.Heartbeat:Wait()
  until bossKilled or (tick() - startTime > 300)

  f.setFastLevelEnabled(false)
  return bossKilled
end

-- Main hopper loop
local function loop()
  if M.running then return end
  M.running = true
  task.spawn(function()
    while M._enabled do
      if hasHighLevelPlayers() then
        -- High levels: Wait 5s, hop
        task.wait(5)
        hopServer()
        task.wait(5)  -- Settle after hop
      else
        -- Clear: Farm Sahur
        local killed = farmSahur()
        if killed then
          task.wait(5)
          hopServer()
          task.wait(5)
        else
          task.wait(10)  -- Retry
        end
      end
    end
    M.running = false
  end)
end

function M.enable()
  M._enabled = true
  loop()
end

function M.disable()
  M._enabled = false
end

return M
