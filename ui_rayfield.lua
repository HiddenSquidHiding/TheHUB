-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (model picker, 3-button row presets, toggles, status).
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
local farm      = require(script.Parent.farm)   -- used for model picker

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

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

  local currentSearch = ""
  pcall(function() farm.getMonsterModels() end)

  local function filteredList()
    local list = farm.filterMonsterModels(currentSearch or "")
    local out = {}
    for _, v in ipairs(list or {}) do
      if typeof(v) == "string" then table.insert(out, v) end
    end
    return out
  end

  local modelDropdown

  local function syncDropdownSelectionFromFarm()
    local sel = farm.getSelected() or {}
    pcall(function() modelDropdown:Set(sel) end)
  end

  local function refreshDropdownOptions()
    local options = filteredList()
    local ok = pcall(function() modelDropdown:Refresh(options, true) end)
    if not ok then
      pcall(function() modelDropdown:Set(options) end)
    end
    syncDropdownSelectionFromFarm()
  end

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
    CurrentOption = farm.getSelected() or {},
    MultipleOptions = true,
    Flag = "woodz_models",
    Callback = function(selection)
      local list = {}
      if typeof(selection) == "table" then
        for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(list, v) end end
      elseif typeof(selection) == "string" then
        table.insert(list, selection)
      end
      farm.setSelected(list)
      syncDropdownSelectionFromFarm()
    end,
  })

  refreshDropdownOptions()

  --------------------------------------------------------------------------
  -- Presets (custom 3-button horizontal row)
  --------------------------------------------------------------------------
  MainTab:CreateSection("Presets")

  -- Robust helper: find Rayfield ScreenGui root
  local function findRayfieldRoot()
    -- Try CoreGui first
    for _, name in ipairs({"Rayfield Interface", "Rayfield", "RayfieldInterface"}) do
      local g = CoreGui:FindFirstChild(name)
      if g then return g end
    end
    -- Fallback to PlayerGui
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
      for _, name in ipairs({"Rayfield Interface", "Rayfield", "RayfieldInterface"}) do
        local g = pg:FindFirstChild(name)
        if g then return g end
      end
    end
    return nil
  end

  local function norm(s)
    s = tostring(s or "")
    s = s:gsub("%s+", " "):lower()
    return s
  end

  -- Find the container that holds the "Presets" section contents
  local function findPresetsContainer()
    local root = findRayfieldRoot()
    if not root then return nil end

    -- Look for a TextLabel whose text contains "presets" (case/spacing insensitive)
    local header
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("TextLabel") then
        local txt = norm(d.Text)
        if txt:find("presets", 1, true) then
          header = d
          break
        end
      end
    end
    if not header then return nil end

    -- Rayfield's hierarchy usually: SectionContainer -> HeaderLabel
    -- In most themes, adding our row under header.Parent works; if not, try one level up.
    local p = header.Parent
    if p and p:IsA("Frame") then return p end
    if p and p.Parent and p.Parent:IsA("Frame") then return p.Parent end
    return header.Parent
  end

  local function injectThreeButtonRow()
    -- Wait until Rayfield finishes laying out the section
    for _=1,80 do -- up to ~16s (80 * 0.2)
      local container = findPresetsContainer()
      if container and not container:FindFirstChild("Woodz_PresetsRow") then
        local row = Instance.new("Frame")
        row.Name = "Woodz_PresetsRow"
        row.BackgroundTransparency = 1
        row.Size = UDim2.new(1, 0, 0, 40)
        row.Parent = container

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Horizontal
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment = Enum.VerticalAlignment.Center
        layout.Padding = UDim.new(0, 8)
        layout.Parent = row

        local function mkBtn(text, cb)
          local btn = Instance.new("TextButton")
          btn.AutoButtonColor = true
          btn.Text = text
          btn.Font = Enum.Font.SourceSans
          btn.TextSize = 14
          btn.TextColor3 = Color3.fromRGB(235,235,235)
          btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
          btn.Size = UDim2.new(1/3, -8, 1, 0) -- 3 buttons across with padding
          btn.Parent = row

          local corner = Instance.new("UICorner")
          corner.CornerRadius = UDim.new(0, 6)
          corner.Parent = btn

          local stroke = Instance.new("UIStroke")
          stroke.Thickness = 1
          stroke.Transparency = 0.3
          stroke.Color = Color3.fromRGB(90, 90, 90)
          stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
          stroke.Parent = btn

          btn.MouseButton1Click:Connect(function()
            task.spawn(function()
              pcall(cb)
            end)
          end)
        end

        mkBtn("Select To Sahur", function()
          if handlers.onSelectSahur then handlers.onSelectSahur() end
          syncDropdownSelectionFromFarm()
          utils.notify("🌲 Preset", "Selected all To Sahur models.", 3)
        end)

        mkBtn("Select Weather", function()
          if handlers.onSelectWeather then handlers.onSelectWeather() end
          syncDropdownSelectionFromFarm()
          utils.notify("🌲 Preset", "Selected all Weather Events models.", 3)
        end)

        mkBtn("Clear All", function()
          if handlers.onClearAll then handlers.onClearAll() end
          syncDropdownSelectionFromFarm()
          utils.notify("🌲 Preset", "Cleared all selections.", 3)
        end)

        return true
      end
      task.wait(0.2)
    end
    return false
  end

  task.spawn(injectThreeButtonRow)

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
    local StarterGui = game:GetService("StarterGui")
    local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local h1 = hud.findHUD(pg);          if h1 then hud.apply(h1, flags); hud.watch(h1, flags) end
    local h2 = hud.findHUD(StarterGui);  if h2 then hud.apply(h2, flags); hud.watch(h2, flags) end
  end

  -- Exposed controls back to app.lua
  local UI = {
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Current Target: None") end) end,
    setAutoFarm      = function(on)   pcall(function() rfAutoFarm:Set(on and true or false) end) end,
    setSmartFarm     = function(on)   pcall(function() rfSmartFarm:Set(on and true or false) end) end,
    setMerchant1     = function(on)   pcall(function() rfMerch1:Set(on and true or false) end) end,
    setMerchant2     = function(on)   pcall(function() rfMerch2:Set(on and true or false) end) end,
    setCrates        = function(on)   pcall(function() rfCrates:Set(on and true or false) end) end,
    setAntiAFK       = function(on)   pcall(function() rfAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on)   pcall(function() rfFastLvl:Set(on and true or false) end) end,

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
