-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (model picker, Clear All, toggles, status).
-- Calls back into app.lua via the handlers you pass to build().

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function(_,_) end }
end

local utils     = getUtils()
local farm      = (function() local ok, m = pcall(function() return require(script.Parent.farm) end); return ok and m or nil end)()

local Players   = game:GetService("Players")
local StarterGui= game:GetService("StarterGui")

local Rayfield  = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local M = {}

function M.build(handlers)
  handlers = handlers or {}

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
  -- Targets: Search + Multi-select + Clear All
  --------------------------------------------------------------------------
  MainTab:CreateSection("Targets")

  local currentSearch = ""
  if farm and farm.getMonsterModels then pcall(function() farm.getMonsterModels() end) end

  local function filteredList()
    if not farm then return {} end
    local list = farm.filterMonsterModels(currentSearch or "")
    local out = {}
    for _, v in ipairs(list or {}) do
      if typeof(v) == "string" then table.insert(out, v) end
    end
    return out
  end

  local modelDropdown
  local suppressDropdown = false -- prevent recursion

  local function syncDropdownSelectionFromFarm()
    if not (modelDropdown and farm and farm.getSelected) then return end
    local sel = farm.getSelected() or {}
    suppressDropdown = true
    pcall(function() modelDropdown:Set(sel) end)
    suppressDropdown = false
  end

  local function forceRefresh(drop, options)
    -- Rayfield sometimes needs a collapse/expand dance to repaint options.
    local okRef = pcall(function() drop:Refresh(options, true) end)
    if not okRef then pcall(function() drop:Set(options) end) end
    -- poke the dropdown open/close if method exists (forks vary)
    pcall(function() if drop.Close then drop:Close() end end)
    pcall(function() if drop.Open  then drop:Open()  end end)
  end

  local function refreshDropdownOptions()
    if not modelDropdown then return end
    local options = filteredList()
    suppressDropdown = true
    forceRefresh(modelDropdown, options)
    syncDropdownSelectionFromFarm()
    suppressDropdown = false
  end

  modelDropdown = MainTab:CreateDropdown({
    Name = "Target Models (multi-select)",
    Options = filteredList(),
    CurrentOption = (farm and farm.getSelected and farm.getSelected()) or {},
    MultipleOptions = true,
    Flag = "woodz_models",
    Callback = function(selection)
      if not farm or suppressDropdown then return end
      local list = {}
      if typeof(selection) == "table" then
        for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(list, v) end end
      elseif typeof(selection) == "string" then
        table.insert(list, selection)
      end
      farm.setSelected(list)
    end,
  })

  MainTab:CreateInput({
    Name = "Search Models",
    PlaceholderText = "Type model names to filter…",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
      currentSearch = tostring(text or "")
      refreshDropdownOptions()
    end,
  })

  -- 👉 Single button directly under the dropdown
  MainTab:CreateButton({
    Name = "Clear All Selections",
    Callback = function()
      if handlers.onClearAll then handlers.onClearAll() end
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Cleared all selections.", 3)
    end,
  })

  --------------------------------------------------------------------------
  -- Farming toggles + current target
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
  -- Options: merchants / crates / AFK + extras
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

  OptionsTab:CreateButton({
    Name = "Private Server",
    Callback = function() if handlers.onPrivateServer then handlers.onPrivateServer() end end,
  })

  local rfFastLvl = OptionsTab:CreateToggle({
    Name = "Instant Level 70+ (Sahur only)",
    CurrentValue = false,
    Flag = "woodz_fastlevel",
    Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
  })

  --------------------------------------------------------------------------
  -- Expose minimal UI control to app.lua
  --------------------------------------------------------------------------
  local UI = {
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Current Target: None") end) end,
    setAutoFarm      = function(on)   pcall(function() rfAutoFarm:Set(on and true or false) end) end,
    setSmartFarm     = function(on)   pcall(function() rfSmartFarm:Set(on and true or false) end) end,
    setMerchant1     = function(on)   pcall(function() rfMerch1:Set(on and true or false) end) end,
    setMerchant2     = function(on)   pcall(function() rfMerch2:Set(on and true or false) end) end,
    setCrates        = function(on)   pcall(function() rfCrates:Set(on and true or false) end) end,
    setAntiAFK       = function(on)   pcall(function() rfAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on)   pcall(function() rfFastLvl:Set(on and true or false) end) end,

    refreshModelOptions = function() refreshDropdownOptions() end,
    syncModelSelection  = function() syncDropdownSelectionFromFarm() end,

    destroy          = function() pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
