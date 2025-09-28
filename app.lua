-- app.lua
local Players = game:GetService('Players')
local StarterGui = game:GetService('StarterGui')

local constants = require(script.Parent.constants)
local utils     = require(script.Parent._deps.utils)
local uiMod     = require(script.Parent.ui)
local farm      = require(script.Parent.farm)
local crates    = require(script.Parent.crates)
local merchants = require(script.Parent.merchants)
local hud       = require(script.Parent.hud)

local App = {}

function App.start()
  local player = Players.LocalPlayer
  local PlayerGui = player:WaitForChild('PlayerGui')

  local ui = uiMod.build()
  local isMinimized=false
  local autoFarmEnabled=false
  local autoBuyM1Enabled=false
  local autoBuyM2Enabled=false
  local autoOpenCratesEnabled=false

  local function ensureTopDisplayOrder()
    local ScreenGui = ui.ScreenGui
    local maxOrder = ScreenGui.DisplayOrder
    for _, sg in ipairs(PlayerGui:GetChildren()) do
      if sg:IsA('ScreenGui') and sg ~= ScreenGui and sg.DisplayOrder >= maxOrder then
        maxOrder = sg.DisplayOrder + 1
      end
    end
    ScreenGui.DisplayOrder = math.max(ScreenGui.DisplayOrder, maxOrder)
  end

  utils.track(PlayerGui.ChildAdded:Connect(function(inst)
    if inst:IsA('ScreenGui') then
      ensureTopDisplayOrder()
      if inst.Name=='HUD' then
        task.defer(function()
          local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
          hud.apply(inst, flags); utils.track(hud.watch(inst, flags))
        end)
      end
    end
  end))

  -- Min/Max/Close
  local function minimizeFrame()
    isMinimized=true
    ui.MainFrame.Size = constants.SIZE_MIN
    ui.MainTabFrame.Visible=false; ui.LoggingTabFrame.Visible=false
    ui.MinimizeButton.Visible=false; ui.MaximizeButton.Visible=true
  end
  local function maximizeFrame()
    isMinimized=false
    ui.MainFrame.Size = constants.SIZE_MAIN
    ui.MainTabFrame.Visible = ui.MainTabButton.BackgroundColor3==constants.COLOR_BTN
    ui.LoggingTabFrame.Visible = ui.LoggingTabButton.BackgroundColor3==constants.COLOR_BTN
    ui.MinimizeButton.Visible=true; ui.MaximizeButton.Visible=false
  end
  utils.track(ui.MinimizeButton.MouseButton1Click:Connect(minimizeFrame))
  utils.track(ui.MaximizeButton.MouseButton1Click:Connect(maximizeFrame))
  utils.track(ui.CloseButton.MouseButton1Click:Connect(function()
    autoFarmEnabled=false; autoBuyM1Enabled=false; autoBuyM2Enabled=false; autoOpenCratesEnabled=false
    ui.ScreenGui:Destroy()
  end))

  -- Tabs
  local function switchToMainTab()
    if isMinimized then return end
    ui.MainTabFrame.Visible=true; ui.LoggingTabFrame.Visible=false
    ui.MainTabButton.BackgroundColor3=constants.COLOR_BTN
    ui.LoggingTabButton.BackgroundColor3=constants.COLOR_BG
  end
  local function switchToLoggingTab()
    if isMinimized then return end
    ui.MainTabFrame.Visible=false; ui.LoggingTabFrame.Visible=true
    ui.MainTabButton.BackgroundColor3=constants.COLOR_BG
    ui.LoggingTabButton.BackgroundColor3=constants.COLOR_BTN
  end
  utils.track(ui.MainTabButton.MouseButton1Click:Connect(switchToMainTab))
  utils.track(ui.LoggingTabButton.MouseButton1Click:Connect(switchToLoggingTab))

  -- Model list
  local function updateDropdown()
    for _, ch in ipairs(ui.ModelScrollFrame:GetChildren()) do if ch:IsA('TextButton') then ch:Destroy() end end
    local count=0
    for _, model in ipairs(farm.getFiltered()) do
      local btn = utils.new('TextButton', {
        Size=UDim2.new(1,-10,0,30), BackgroundColor3 = table.find(farm.getSelected(), model) and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN,
        TextColor3=constants.COLOR_WHITE, Text=model, TextSize=14, Font=Enum.Font.SourceSans, LayoutOrder=count
      }, ui.ModelScrollFrame)
      utils.track(btn.MouseButton1Click:Connect(function()
        local sel = table.clone(farm.getSelected())
        local idx = table.find(sel, model)
        if idx then table.remove(sel, idx) else table.insert(sel, model) end
        farm.setSelected(sel)
        updateDropdown()
      end))
      count += 1
    end
    ui.ModelScrollFrame.CanvasSize = UDim2.new(0,0,0,count*30)
  end

  farm.getMonsterModels(); updateDropdown()
  utils.track(ui.SearchTextBox:GetPropertyChangedSignal('Text'):Connect(function()
    farm.filterMonsterModels(ui.SearchTextBox.Text); updateDropdown()
  end))

  -- Presets
  utils.track(ui.SelectSahurButton.MouseButton1Click:Connect(function()
    local sel = farm.getSelected(); if not table.find(sel,'To Sahur') then sel = table.clone(sel); table.insert(sel,'To Sahur'); farm.setSelected(sel); updateDropdown() end
  end))
  utils.track(ui.SelectWeatherButton.MouseButton1Click:Connect(function()
    local sel = farm.getSelected(); if not table.find(sel,'Weather Events') then sel = table.clone(sel); table.insert(sel,'Weather Events'); farm.setSelected(sel); updateDropdown() end
  end))
  utils.track(ui.SelectAllButton.MouseButton1Click:Connect(function()
    farm.setSelected(table.clone(farm.getMonsterModels())); updateDropdown()
  end))
  utils.track(ui.ClearAllButton.MouseButton1Click:Connect(function()
    farm.setSelected({}); updateDropdown()
  end))

  -- Auto farm
  utils.track(ui.AutoFarmToggle.MouseButton1Click:Connect(function()
    autoFarmEnabled = not autoFarmEnabled
    ui.AutoFarmToggle.Text = 'Auto-Farm: '..(autoFarmEnabled and 'ON' or 'OFF')
    ui.AutoFarmToggle.BackgroundColor3 = autoFarmEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoFarmEnabled then
      farm.setupAutoAttackRemote()
      farm.preventAFK(function() return autoFarmEnabled end)
      task.spawn(function() farm.runAutoFarm(function() return autoFarmEnabled end, function(t) ui.CurrentTargetLabel.Text = t end) end)
    else
      ui.CurrentTargetLabel.Text = 'Current Target: None'
    end
  end))

  -- Merchants
  utils.track(ui.ToggleMerchant1Button.MouseButton1Click:Connect(function()
    autoBuyM1Enabled = not autoBuyM1Enabled
    ui.ToggleMerchant1Button.Text = 'Auto Buy Mythics (Chicleteiramania): '..(autoBuyM1Enabled and 'ON' or 'OFF')
    ui.ToggleMerchant1Button.BackgroundColor3 = autoBuyM1Enabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoBuyM1Enabled then task.spawn(function() merchants.autoBuyLoop('SmelterMerchantService', function() return autoBuyM1Enabled end, function(sfx) ui.ToggleMerchant1Button.Text='Auto Buy Mythics (Chicleteiramania): ON '..sfx end) end) end
  end))
  utils.track(ui.ToggleMerchant2Button.MouseButton1Click:Connect(function()
    autoBuyM2Enabled = not autoBuyM2Enabled
    ui.ToggleMerchant2Button.Text = 'Auto Buy Mythics (Bombardino Sewer): '..(autoBuyM2Enabled and 'ON' or 'OFF')
    ui.ToggleMerchant2Button.BackgroundColor3 = autoBuyM2Enabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoBuyM2Enabled then task.spawn(function() merchants.autoBuyLoop('SmelterMerchantService2', function() return autoBuyM2Enabled end, function(sfx) ui.ToggleMerchant2Button.Text='Auto Buy Mythics (Bombardino Sewer): ON '..sfx end) end) end
  end))

  -- Crates
  crates.sniffCrateEvents(); task.spawn(function() crates.unlockWorker() end)
  utils.track(ui.ToggleAutoCratesButton.MouseButton1Click:Connect(function()
    autoOpenCratesEnabled = not autoOpenCratesEnabled
    ui.ToggleAutoCratesButton.Text = 'Auto Open Crates: '..(autoOpenCratesEnabled and 'ON' or 'OFF')
    ui.ToggleAutoCratesButton.BackgroundColor3 = autoOpenCratesEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoOpenCratesEnabled then crates.refreshCrateInventory(true); task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end) end) end
  end))

  utils.notify('🌲 WoodzHUB', 'Welcome to WoodzHUB (clean build)! Weather-priority farming, folder-wide spawn scan, dual merchants, and Auto Crates with reward sniffer.', 6.5)
end

return App
