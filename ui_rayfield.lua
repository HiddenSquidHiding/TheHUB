-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (multi-select model picker, presets, toggles, status).
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
local farm      = require(script.Parent.farm)   -- 👈 used for model picker

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

  --------------------------------------------------------------------------
  -- Model Picker (Search + Multi-select Dropdown)
  --------------------------------------------------------------------------
  MainTab:CreateSection("Targets")

  -- Keep a local copy of search text for filtering
  local currentSearch = ""

  -- Ensure farm has scanned once (app.start also does this; safe to call again)
  pcall(function() farm.getMonsterModels() end)

  local function filteredList()
    -- farm.filterMonsterModels returns and updates internal filtered list
    local list = farm.filterMonsterModels(currentSearch or "")
    -- Defensive: ensure it's a flat list of strings
    local out = {}
    for _, v in ipairs(list or {}) do
      if typeof(v) == "string" then table.insert(out, v) end
    end
    return out
  end

  -- forward declarations so helpers can reference them
  local modelDropdown

  local function syncDropdownSelectionFromFarm()
    local sel = farm.getSelected() or {}
    -- Rayfield dropdown supports setting a table when MultipleOptions = true
    pcall(function() modelDropdown:Set(sel) end)
  end

  local function refreshDropdownOptions()
    local options = filteredList()
    -- Try Rayfield's Refresh API (options, keep_current_selection?)
    local ok = pcall(function() modelDropdown:Refresh(options, true) end)
    if not ok then
      -- Fallback: attempt Set on options (some builds accept table for choices)
      pcall(function() modelDropdown:Set(options) end)
    end
    -- Re-apply current selection after options change
    syncDropdownSelectionFromFarm()
  end

  local searchInput = MainTab:CreateInput({
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
    CurrentOption = farm.getSelected() or {},
    MultipleOptions = true,
    Flag = "woodz_models",
    Callback = function(selection)
      -- selection may be a string (single) or table (multi) depending on Rayfield build
      local list = {}
      if typeof(selection) == "table" then
        for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(list, v) end end
      elseif typeof(selection) == "string" then
        table.insert(list, selection)
      end
      farm.setSelected(list)
      -- Keep dropdown selection in sync (guards against library quirks)
      syncDropdownSelectionFromFarm()
    end,
  })

  -- First-time ensure options/selection are aligned
  refreshDropdownOptions()

  --------------------------------------------------------------------------
  -- Presets
  --------------------------------------------------------------------------
  MainTab:CreateSection("Presets")

  MainTab:CreateButton({
    Name = "Select To Sahur",
    Callback = function()
      if handlers.onSelectSahur then handlers.onSelectSahur() end
      -- reflect external changes in picker
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Selected all To Sahur models.", 3)
    end,
  })

  MainTab:CreateButton({
    Name = "Select Weather",
    Callback = function()
      if handlers.onSelectWeather then handlers.onSelectWeather() end
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Selected all Weather Events models.", 3)
    end,
  })

  MainTab:CreateButton({
    Name = "Select All",
    Callback = function()
      if handlers.onSelectAll then handlers.onSelectAll() end
      refreshDropdownOptions()
      utils.notify("🌲 Preset", "Selected all models.", 3)
    end,
  })

  MainTab:CreateButton({
    Name = "Clear All",
    Callback = function()
      if handlers.onClearAll then handlers.onClearAll() end
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Cleared all selections.", 3)
    end,
  })

  --------------------------------------------------------------------------
  -- Toggles (farming)
  --------------------------------------------------------------------------
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

  --------------------------------------------------------------------------
  -- Options
  --------------------------------------------------------------------------
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

  -- Optional: apply HUD hiding like old UI
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
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Current Target: None") end) end,
    setAutoFarm      = function(on)   pcall(function() rfAutoFarm:Set(on and true or false) end) end,
    setSmartFarm     = function(on)   pcall(function() rfSmartFarm:Set(on and true or false) end) end,
    setMerchant1     = function(on)   pcall(function() rfMerch1:Set(on and true or false) end) end,
    setMerchant2     = function(on)   pcall(function() rfMerch2:Set(on and true or false) end) end,
    setCrates        = function(on)   pcall(function() rfCrates:Set(on and true or false) end) end,
    setAntiAFK       = function(on)   pcall(function() rfAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on)   pcall(function() rfFastLvl:Set(on and true or false) end) end,

    -- Optional helpers if you ever want to sync picker externally
    refreshModelOptions = function()
      refreshDropdownOptions()
    end,
    syncModelSelection = function()
      syncDropdownSelectionFromFarm()
    end,

    destroy          = function()      pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
