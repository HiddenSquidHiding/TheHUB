-- sahur_hopper.lua — Auto-hop servers for low-level Sahur farms.
-- Checks for players > L84 (excl. self). If clear, farms Sahur boss; else hops.
-- Integrates with farm.lua for targeting. Requires TeleportService for hops.

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local farm = nil  -- Loaded via require if available

local M = { _enabled = false, running = false }

-- Load farm module if sibling
local function getFarm()
  if farm then return farm end
  local p = script and script.Parent
  if p then
    local ok, mod = pcall(require, p.farm)
    if ok then farm = mod end
  end
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
  local myLvl = getMyLevel()
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

-- Hop to new server (random public or private if available)
local function hopServer()
  local placeId = game.PlaceId
  local ok, err = pcall(function()
    TeleportService:Teleport(placeId, player)
  end)
  if not ok then
    warn("[Sahur Hopper] Teleport failed:", err)
  end
end

-- Farm Sahur boss (using farm module)
local function farmSahur()
  local f = getFarm()
  if not f then
    warn("[Sahur Hopper] farm.lua not loaded; skipping Sahur farm.")
    return false
  end

  -- Set target to Sahur
  local sahurName = "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur"
  f.setSelected({sahurName})
  f.setFastLevelEnabled(true)  -- Enable FastLevel for boss

  -- Start auto-farm loop (flag always true until killed)
  local bossKilled = false
  local connection
  connection = f.runAutoFarm(function() return not bossKilled end, function(text)
    if string.find(text or "", "Current Target: None") then
      bossKilled = true
      connection:Disconnect()  -- Stop loop
    end
  end)

  -- Wait for kill (timeout 5min)
  local startTime = tick()
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
        task.wait(5)  -- Check after hop settles
      else
        -- Clear server: Farm Sahur
        local killed = farmSahur()
        if killed then
          task.wait(5)
          hopServer()
          task.wait(5)
        else
          task.wait(10)  -- Retry if failed
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
