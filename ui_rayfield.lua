-- ui_rayfield.lua — minimal Rayfield wrapper with safe fallbacks
local Players = game:GetService("Players")

local ok, Rayfield = pcall(function()
  return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not ok then
  return { build = function() warn("[ui_rayfield] Rayfield failed to fetch"); return {
    setCurrentTarget=function()end, setAutoFarm=function()end, setSmartFarm=function()end, destroy=function()end
  } end }
end

local M = {}

function M.build(h)
  h = h or {}
  local Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — Rayfield",
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
  })

  local Main    = Window:CreateTab("Main")
  local Options = Window:CreateTab("Options")

  Main:CreateSection("Farming")
  local lbl = Main:CreateLabel("Current Target: None")

  if h.onAutoFarmToggle then
    local tog = Main:CreateToggle({ Name="Auto-Farm", CurrentValue=false, Callback=function(v) h.onAutoFarmToggle(v) end })
    M.setAutoFarm = function(v) pcall(function() tog:Set(v and true or false) end) end
  end
  if h.onSmartFarmToggle then
    local tog = Main:CreateToggle({ Name="Smart Farm", CurrentValue=false, Callback=function(v) h.onSmartFarmToggle(v) end })
    M.setSmartFarm = function(v) pcall(function() tog:Set(v and true or false) end) end
  end

  Options:CreateSection("General")
  if h.onToggleAntiAFK then
    Options:CreateToggle({ Name="Anti-AFK", CurrentValue=false, Callback=function(v) h.onToggleAntiAFK(v) end })
  end
  if h.onToggleMerchant1 then
    Options:CreateToggle({ Name="Auto Buy Mythics (Chicleteiramania)", CurrentValue=false, Callback=function(v) h.onToggleMerchant1(v) end })
  end
  if h.onToggleMerchant2 then
    Options:CreateToggle({ Name="Auto Buy Mythics (Bombardino Sewer)", CurrentValue=false, Callback=function(v) h.onToggleMerchant2(v) end })
  end
  if h.onToggleCrates then
    Options:CreateToggle({ Name="Auto Open Crates", CurrentValue=false, Callback=function(v) h.onToggleCrates(v) end })
  end
  if h.onRedeemCodes then
    Options:CreateButton({ Name="Redeem Unredeemed Codes", Callback=function() h.onRedeemCodes() end })
  end
  if h.onFastLevelToggle then
    Options:CreateToggle({ Name="Instant Level 70+ (Sahur only)", CurrentValue=false, Callback=function(v) h.onFastLevelToggle(v) end })
  end
  if h.onDungeonAutoToggle then
    Options:CreateToggle({ Name="Dungeon Auto-Attack", CurrentValue=false, Callback=function(v) h.onDungeonAutoToggle(v) end })
  end
  if h.onDungeonReplayToggle then
    Options:CreateToggle({ Name="Dungeon Auto-Replay", CurrentValue=false, Callback=function(v) h.onDungeonReplayToggle(v) end })
  end

  M.setCurrentTarget = function(text) pcall(function() lbl:Set(text or "Current Target: None") end) end
  M.destroy = function() pcall(function() Rayfield:Destroy() end) end

  return M
end

return M
