-- server_hopper.lua — Hop to a different public server each time, avoiding the current one.

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local placeId = game.PlaceId
local currentJobId = game.JobId

local function hopToDifferentServer()
  local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
  local success, response = pcall(function()
    return HttpService:JSONDecode(game:HttpGet(url))
  end)

  if not success or not response.data or #response.data == 0 then
    warn("[Server Hopper] Failed to fetch public servers. Retrying in 5s...")
    task.wait(5)
    hopToDifferentServer()  -- Retry
    return
  end

  local availableJobIds = {}
  for _, server in ipairs(response.data) do
    if server.id ~= currentJobId and server.playing < server.maxPlayers then  -- Exclude current, prefer non-full
      table.insert(availableJobIds, server.id)
    end
  end

  if #availableJobIds == 0 then
    warn("[Server Hopper] No other public servers found. Retrying in 5s...")
    task.wait(5)
    hopToDifferentServer()  -- Retry
    return
  end

  -- Pick a random server
  local randomIndex = math.random(1, #availableJobIds)
  local selectedJobId = availableJobIds[randomIndex]

  local ok, err = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, placeId, selectedJobId, player)
  if not ok then
    warn("[Server Hopper] Teleport failed: " .. tostring(err) .. ". Retrying in 5s...")
    task.wait(5)
    hopToDifferentServer()  -- Retry on failure
  else
    print("[Server Hopper] Successfully teleported to new server: " .. selectedJobId)
  end
end

-- Execute the hop (can be triggered manually or via UI button)
hopToDifferentServer()
