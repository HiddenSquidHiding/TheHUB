-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (profile-aware).
-- Calls back into app.lua via the handlers you pass to build().

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function(_,_) end }
end

local utils     = getUtils()
local constants = require(script.Parent.constants)
local hud       = require(script.Parent.hud)
local farm      = script.Parent:FindFirstChild("farm") and require(script.Parent.farm) or nil

local Players   = game:GetService("Players")
local StarterGui= game:GetService("StarterGui")

local Rayfield  = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local M = {}

function M.build(handlers)
  handlers = handlers or {}
  local flags = handlers.uiFlags or {}

  local Window = Rayfield:CreateWindow({
    Name                = "🌲 WoodzHUB — Rayfield",
    LoadingTitle        = "WoodzHUB",
    LoadingSubtitle     = "Rayfield UI",
    ConfigurationSaving = { Enabled = false, FolderName = "WoodzHUB", FileName = "Rayfield" },
    KeySystem           = false,
  })

  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  --------------------------------------------------------------------------
  -- Targets: Search + Multi-select + Clear All (only if enabled)
  --------------------------------------------------------------------------
  local currentLabel = nil
  if flags.modelPicker and farm then
    MainTab:CreateSection("Targets")

    local currentSearch = ""
    pcall(function() if farm.getMonsterModels then farm.getMonsterModels() end end)

    local function filteredList()
      local list = (farm.filterMonsterModels and farm.filterMonsterModels(currentSearch or "")) or {}
      local out = {}
      for _, v in ipairs(list or {}) do
        if typeof(v) == "string" then table.insert(out, v) end
      end
      return out
    end

    local modelDropdown
    local suppressDropdown = false

    local function syncDropdownSelectionFromFarm()
      if not modelDropdown or not farm.getSelected then return end
      local sel = farm.getSelected() or {}
      suppressDropdown = true
      pcall(function() modelDropdown:Set(sel) end)
      suppressDropdown = false
    end

    local function refreshDropdownOptions()
      if not modelDropdown then return end
      local options = filteredList()
      suppressDropdown = true
      local ok = pcall(function() modelDropdown:Refresh(options, true) end)
      if not ok then
        pcall(function() modelDropdown:Set(options) end)
      end
      syncDropdownSelectionFromFarm()
      suppressDropdown = false
    end

    -- Search first (to avoid refresh timing issues)
    MainTab:CreateInput({
      Name = "Search Models",
      PlaceholderText = "Type model names to filter…",
      RemoveTextAfterFocusLost = false,
      Callback = function(text)
        currentSearch = tostring(text or "")
        refreshDropdownOptions()
      end,
    })

    modelDropdown = MainTab:CreateDropdown({
      Name = "Target Models (multi-select)",
      Options = filteredList(),
      CurrentOption = (farm.getSelected and farm.getSelected()) or {},
      MultipleOptions = true,
      Flag = "woodz_models",
      Callback = function(selection)
        if suppressDropdown or not farm.setSelected then return end
        local list = {}
        if typeof(selection) == "table" then
          for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(list, v) end end
        elseif typeof(selection) == "string" then
          table.insert(list, selection)
        end
        farm.setSelected(list)
      end,
    })

    MainTab:CreateButton({
      Name = "Clear All Selections",
      Callback = function()
        if handlers.onClearAll then handlers.onClearAll() end
        syncDropdownSelectionFromFarm()
        utils.notify("🌲 Preset", "Cleared all selections.", 3)
      end,
    })
  end

  --------------------------------------------------------------------------
  -- Farming toggles + current target (conditionally shown)
  --------------------------------------------------------------------------
  if flags.autoFarm or flags.smartFarm or flags.currentTarget then
    MainTab:CreateSection("Farming")
  end

  local rfAutoFarm, rfSmartFarm
  if flags.autoFarm then
    rfAutoFarm = MainTab:CreateToggle({
      Name = "Auto-Farm",
      CurrentValue = false,
      Flag = "woodz_auto_farm",
      Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
    })
  end

  if flags.smartFarm then
    rfSmartFarm = MainTab:CreateToggle({
      Name = "Smart Farm",
      CurrentValue = false,
      Flag = "woodz_smart_farm",
      Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
    })
  end

  if flags.currentTarget then
    currentLabel = MainTab:CreateLabel("Current Target: None")
  end

  --------------------------------------------------------------------------
  -- Options: merchants / crates / AFK + extras (conditionally)
  --------------------------------------------------------------------------
  OptionsTab:CreateSection("Options")

  local rfMerch1, rfMerch2, rfCrates, rfAFK, rfFastLvl

  if flags.merchants then
    rfMerch1 = OptionsTab:CreateToggle({
      Name = "Auto Buy Mythics (Chicleteiramania)",
      CurrentValue = false,
      Flag = "woodz_m1",
      Callback = function(v) if handlers.onToggleMerchant1 then handlers.onToggleMerchant1(v) end end,
    })
    rfMerch2 = OptionsTab:CreateToggle({
      Name = "Auto Buy Mythics (Bombardino Sewer)",
      CurrentValue = false,
      Flag = "woodz_m2",
      Callback = function(v) if handlers.onToggleMerchant2 then handlers.onToggleMerchant2(v) end end,
    })
  end

  if flags.crates then
    rfCrates = OptionsTab:CreateToggle({
      Name = "Auto Open Crates",
      CurrentValue = false,
      Flag = "woodz_crates",
      Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
    })
  end

  if flags.antiAFK then
    rfAFK = OptionsTab:CreateToggle({
      Name = "Anti-AFK",
      CurrentValue = false,
      Flag = "woodz_afk",
      Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
    })
  end

  if flags.redeemCodes then
    OptionsTab:CreateButton({
      Name = "Redeem Unredeemed Codes",
      Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end,
    })
  end

  if flags.privateServer then
    OptionsTab:CreateButton({
      Name = "Private Server",
      Callback = function() if handlers.onPrivateServer then handlers.onPrivateServer() end end,
    })
  end

  if flags.fastlevel then
    rfFastLvl = OptionsTab:CreateToggle({
      Name = "Instant Level 70+ (Sahur only)",
      CurrentValue = false,
      Flag = "woodz_fastlevel",
      Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
    })
  end

  --------------------------------------------------------------------------
  -- Optional: HUD auto-hide (same behavior you had before)
  --------------------------------------------------------------------------
  do
    local flagsHUD = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local h1 = hud and hud.findHUD and hud.findHUD(pg);         if h1 and hud.apply then hud.apply(h1, flagsHUD); if hud.watch then hud.watch(h1, flagsHUD) end end
    local h2 = hud and hud.findHUD and hud.findHUD(StarterGui); if h2 and hud.apply then hud.apply(h2, flagsHUD); if hud.watch then hud.watch(h2, flagsHUD) end end
  end

  --------------------------------------------------------------------------
  -- Expose minimal UI control to app.lua
  --------------------------------------------------------------------------
  local UI = {
    setCurrentTarget = function(text)
      if currentLabel then pcall(function() currentLabel:Set(text or "Current Target: None") end) end
    end,
    setAutoFarm  = function(on) if rfAutoFarm then pcall(function() rfAutoFarm:Set(on and true or false) end) end end,
    setSmartFarm = function(on) if rfSmartFarm then pcall(function() rfSmartFarm:Set(on and true or false) end) end end,
    setMerchant1 = function(on) if rfMerch1   then pcall(function() rfMerch1:Set(on and true or false) end) end end,
    setMerchant2 = function(on) if rfMerch2   then pcall(function() rfMerch2:Set(on and true or false) end) end end,
    setCrates    = function(on) if rfCrates   then pcall(function() rfCrates:Set(on and true or false) end) end end,
    setAntiAFK   = function(on) if rfAFK      then pcall(function() rfAFK:Set(on and true or false) end) end end,
    setFastLevel = function(on) if rfFastLvl  then pcall(function() rfFastLvl:Set(on and true or false) end) end end,
    destroy      = function() pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
