-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (toggles, options, presets, status label).
-- It calls back into app.lua via the handlers you pass to build().

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function(_,_) end }
end

local utils     = getUtils()
local constants = require(script.Parent.constants)
local hud       = require(script.Parent.hud)

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local M = {}

function M.build(handlers)
  handlers = handlers or {}

  local Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — Rayfield",
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = {
      Enabled = false,
      FolderName = "WoodzHUB",
      FileName = "Rayfield",
    },
    KeySystem = false,
  })

  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  -- Presets
  MainTab:CreateSection("Presets")
  MainTab:CreateButton({
    Name = "Select To Sahur",
    Callback = function() if handlers.onSelectSahur then handlers.onSelectSahur() end end,
  })
  MainTab:CreateButton({
    Name = "Select Weather",
    Callback = function() if handlers.onSelectWeather then handlers.onSelectWeather() end end,
  })
  MainTab:CreateButton({
    Name = "Select All",
    Callback = function() if handlers.onSelectAll then handlers.onSelectAll() end end,
  })
  MainTab:CreateButton({
    Name = "Clear All",
    Callback = function() if handlers.onClearAll then handlers.onClearAll() end end,
  })

  -- Toggles
  MainTab:CreateSection("Farming")
  local rfAutoFarm = MainTab:CreateToggle({
    Name = "Auto-Farm",
    CurrentValue = false,
    Flag = "woodz_auto_farm",
    Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
  })
  local rfSmartFarm = MainTab:CreateToggle({
    Name = "Smart Farm",
    CurrentValue = false,
    Flag = "woodz_smart_farm",
    Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
  })

  local currentLabel = MainTab:CreateLabel("Current Target: None")

  OptionsTab:CreateSection("Merchants / Crates / AFK")
  local rfMerch1 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Chicleteiramania)",
    CurrentValue = false,
    Flag = "woodz_m1",
    Callback = function(v) if handlers.onToggleMerchant1 then handlers.onToggleMerchant1(v) end end,
  })
  local rfMerch2 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Bombardino Sewer)",
    CurrentValue = false,
    Flag = "woodz_m2",
    Callback = function(v) if handlers.onToggleMerchant2 then handlers.onToggleMerchant2(v) end end,
  })
  local rfCrates = OptionsTab:CreateToggle({
    Name = "Auto Open Crates",
    CurrentValue = false,
    Flag = "woodz_crates",
    Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
  })
  local rfAFK = OptionsTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Flag = "woodz_afk",
    Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
  })

  OptionsTab:CreateSection("Extras")
  OptionsTab:CreateButton({
    Name = "Redeem Unredeemed Codes",
    Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end,
  })
  local rfFastLvl = OptionsTab:CreateToggle({
    Name = "Instant Level 70+ (Sahur only)",
    CurrentValue = false,
    Flag = "woodz_fastlevel",
    Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
  })

  -- Apply HUD hiding just like the old UI did (optional)
  do
    local Players = game:GetService("Players")
    local StarterGui = game:GetService("StarterGui")
    local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local h1 = hud.findHUD(pg);          if h1 then hud.apply(h1, flags); hud.watch(h1, flags) end
    local h2 = hud.findHUD(StarterGui);  if h2 then hud.apply(h2, flags); hud.watch(h2, flags) end
  end

  -- What the app can control after build:
  local UI = {
    setCurrentTarget = function(text) currentLabel:Set(text or "Current Target: None") end,
    setAutoFarm      = function(on)   pcall(function() rfAutoFarm:Set(on and true or false) end) end,
    setSmartFarm     = function(on)   pcall(function() rfSmartFarm:Set(on and true or false) end) end,
    setMerchant1     = function(on)   pcall(function() rfMerch1:Set(on and true or false) end) end,
    setMerchant2     = function(on)   pcall(function() rfMerch2:Set(on and true or false) end) end,
    setCrates        = function(on)   pcall(function() rfCrates:Set(on and true or false) end) end,
    setAntiAFK       = function(on)   pcall(function() rfAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on)   pcall(function() rfFastLvl:Set(on and true or false) end) end,
    destroy          = function()      pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
