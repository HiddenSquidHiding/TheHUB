-- app.lua
-- Minimal app that wires preset buttons (Weather / To Sahur), selection list,
-- search filter, and Auto-Farm with live target label.

-- Sibling deps
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[app.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading app.lua")
end

local utils      = getUtils()
local constants  = require(script.Parent.constants)
local farm       = require(script.Parent.farm)

-- Roblox services
local Players    = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player     = Players.LocalPlayer
local PlayerGui  = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- Colors / layout (match your previous style)
----------------------------------------------------------------------
local COLOR_BG_DARK     = Color3.fromRGB(30, 30, 30)
local COLOR_BG          = Color3.fromRGB(40, 40, 40)
local COLOR_BG_MED      = Color3.fromRGB(50, 50, 50)
local COLOR_BTN         = Color3.fromRGB(60, 60, 60)
local COLOR_BTN_ACTIVE  = Color3.fromRGB(80, 80, 80)
local COLOR_WHITE       = Color3.fromRGB(255, 255, 255)

local SIZE_MAIN = UDim2.new(0, 400, 0, 540)
local SIZE_MIN  = UDim2.new(0, 400, 0, 50)

local function new(t, props, parent)
  local i = Instance.new(t)
  if props then
    for k, v in pairs(props) do
      i[k] = v
    end
  end
  if parent then
    i.Parent = parent
  end
  return i
end

local uiConns = {}
local function track(conn)
  table.insert(uiConns, conn)
  return conn
end

----------------------------------------------------------------------
-- Root GUI
----------------------------------------------------------------------
local ScreenGui = new("ScreenGui", {
  Name = "WoodzHUB",
  ResetOnSpawn = false,
  ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
  DisplayOrder = 999999999,
  Enabled = true,
}, PlayerGui)

local MainFrame = new("Frame", {
  Size = SIZE_MAIN,
  Position = UDim2.new(0.5, -200, 0.5, -270),
  BackgroundColor3 = COLOR_BG_DARK,
  BorderSizePixel = 0,
}, ScreenGui)

local TitleLabel = new("TextLabel", {
  Size = UDim2.new(1, -60, 0, 50),
  BackgroundColor3 = COLOR_BG_MED,
  Text = "🌲 WoodzHUB",
  TextColor3 = COLOR_WHITE,
  TextSize = 14,
  Font = Enum.Font.SourceSansBold,
}, MainFrame)

local FrameBar = new("Frame", {
  Size = UDim2.new(0, 60, 0, 50),
  Position = UDim2.new(1, -60, 0, 0),
  BackgroundColor3 = COLOR_BG_MED,
}, MainFrame)

local MinimizeButton = new("TextButton", {
  Size = UDim2.new(0.333, 0, 1, 0),
  BackgroundColor3 = COLOR_BTN,
  TextColor3 = COLOR_WHITE,
  Text = "-",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, FrameBar)

local MaximizeButton = new("TextButton", {
  Size = UDim2.new(0.333, 0, 1, 0),
  Position = UDim2.new(0.333, 0, 0, 0),
  BackgroundColor3 = COLOR_BTN,
  TextColor3 = COLOR_WHITE,
  Text = "□",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
  Visible = false,
}, FrameBar)

local CloseButton = new("TextButton", {
  Size = UDim2.new(0.333, 0, 1, 0),
  Position = UDim2.new(0.666, 0, 0, 0),
  BackgroundColor3 = Color3.fromRGB(200, 50, 50),
  TextColor3 = COLOR_WHITE,
  Text = "X",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, FrameBar)

local TabFrame = new("Frame", {
  Size = UDim2.new(1, 0, 0, 30),
  Position = UDim2.new(0, 0, 0, 50),
  BackgroundColor3 = COLOR_BG,
}, MainFrame)

local MainTabButton = new("TextButton", {
  Size = UDim2.new(0.5, 0, 1, 0),
  Text = "Main",
  TextColor3 = COLOR_WHITE,
  BackgroundColor3 = COLOR_BTN,
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, TabFrame)

local OptionsTabButton = new("TextButton", {
  Size = UDim2.new(0.5, 0, 1, 0),
  Position = UDim2.new(0.5, 0, 0, 0),
  Text = "Options",
  TextColor3 = COLOR_WHITE,
  BackgroundColor3 = COLOR_BG,
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, TabFrame)

local MainTabFrame = new("Frame", {
  Size = UDim2.new(1, 0, 1, -80),
  Position = UDim2.new(0, 0, 0, 80),
  BackgroundTransparency = 1,
}, MainFrame)

local OptionsTabFrame = new("Frame", {
  Size = UDim2.new(1, 0, 1, -80),
  Position = UDim2.new(0, 0, 0, 80),
  BackgroundTransparency = 1,
  Visible = false,
}, MainFrame)

----------------------------------------------------------------------
-- Dragging
----------------------------------------------------------------------
do
  local dragging, dragStart, startPos = false, nil, nil
  local function begin(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging, dragStart, startPos = true, input.Position, MainFrame.Position
    end
  end
  local function finish(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = false
    end
  end
  local function update(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
      local delta = input.Position - dragStart
      MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
  end
  track(TitleLabel.InputBegan:Connect(begin))
  track(TitleLabel.InputEnded:Connect(finish))
  track(FrameBar.InputBegan:Connect(begin))
  track(FrameBar.InputEnded:Connect(finish))
  track(UserInputService.InputChanged:Connect(update))
end

----------------------------------------------------------------------
-- Min/Max/Close
----------------------------------------------------------------------
local isMinimized = false
local function minimize()
  isMinimized = true
  MainFrame.Size = SIZE_MIN
  TabFrame.Visible = false
  MainTabFrame.Visible = false
  OptionsTabFrame.Visible = false
  MinimizeButton.Visible = false
  MaximizeButton.Visible = true
end
local function maximize()
  isMinimized = false
  MainFrame.Size = SIZE_MAIN
  TabFrame.Visible = true
  -- restore whichever tab is active
  MainTabFrame.Visible = MainTabButton.BackgroundColor3 == COLOR_BTN
  OptionsTabFrame.Visible = OptionsTabButton.BackgroundColor3 == COLOR_BTN
  MinimizeButton.Visible = true
  MaximizeButton.Visible = false
end
track(MinimizeButton.MouseButton1Click:Connect(minimize))
track(MaximizeButton.MouseButton1Click:Connect(maximize))
track(CloseButton.MouseButton1Click:Connect(function()
  ScreenGui:Destroy()
end))

----------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------
local function gotoMain()
  if isMinimized then return end
  MainTabButton.BackgroundColor3 = COLOR_BTN
  OptionsTabButton.BackgroundColor3 = COLOR_BG
  MainTabFrame.Visible = true
  OptionsTabFrame.Visible = false
end
local function gotoOptions()
  if isMinimized then return end
  MainTabButton.BackgroundColor3 = COLOR_BG
  OptionsTabButton.BackgroundColor3 = COLOR_BTN
  MainTabFrame.Visible = false
  OptionsTabFrame.Visible = true
end
track(MainTabButton.MouseButton1Click:Connect(gotoMain))
track(OptionsTabButton.MouseButton1Click:Connect(gotoOptions))

----------------------------------------------------------------------
-- MAIN TAB UI
----------------------------------------------------------------------
local SearchTextBox = new("TextBox", {
  Size = UDim2.new(1, -20, 0, 30),
  Position = UDim2.new(0, 10, 0, 10),
  BackgroundColor3 = COLOR_BG_MED,
  TextColor3 = COLOR_WHITE,
  PlaceholderText = "Enter model names to search...",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
  Text = "",
  ClearTextOnFocus = false,
}, MainTabFrame)

local ModelScrollFrame = new("ScrollingFrame", {
  Size = UDim2.new(1, -20, 0, 150),
  Position = UDim2.new(0, 10, 0, 50),
  BackgroundColor3 = COLOR_BG_MED,
  CanvasSize = UDim2.new(0, 0, 0, 0),
  ScrollBarThickness = 8,
}, MainTabFrame)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, ModelScrollFrame)

local PresetButtonsFrame = new("Frame", {
  Size = UDim2.new(1, -20, 0, 30),
  Position = UDim2.new(0, 10, 0, 210),
  BackgroundTransparency = 1,
}, MainTabFrame)

local SelectSahurButton = new("TextButton", {
  Size = UDim2.new(0.25, 0, 1, 0),
  BackgroundColor3 = COLOR_BTN,
  TextColor3 = COLOR_WHITE,
  Text = "Select To Sahur",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, PresetButtonsFrame)

local SelectWeatherButton = new("TextButton", {
  Size = UDim2.new(0.25, 0, 1, 0),
  Position = UDim2.new(0.25, 0, 0, 0),
  BackgroundColor3 = COLOR_BTN,
  TextColor3 = COLOR_WHITE,
  Text = "Select Weather",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, PresetButtonsFrame)

local SelectAllButton = new("TextButton", {
  Size = UDim2.new(0.25, 0, 1, 0),
  Position = UDim2.new(0.50, 0, 0, 0),
  BackgroundColor3 = COLOR_BTN,
  TextColor3 = COLOR_WHITE,
  Text = "Select All",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, PresetButtonsFrame)

local ClearAllButton = new("TextButton", {
  Size = UDim2.new(0.25, 0, 1, 0),
  Position = UDim2.new(0.75, 0, 0, 0),
  BackgroundColor3 = COLOR_BTN,
  TextColor3 = COLOR_WHITE,
  Text = "Clear All",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, PresetButtonsFrame)

local AutoFarmToggle = new("TextButton", {
  Size = UDim2.new(1, -20, 0, 30),
  Position = UDim2.new(0, 10, 0, 250),
  BackgroundColor3 = COLOR_BTN,
  TextColor3 = COLOR_WHITE,
  Text = "Auto-Farm: OFF",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, MainTabFrame)

local CurrentTargetLabel = new("TextLabel", {
  Size = UDim2.new(1, -20, 0, 30),
  Position = UDim2.new(0, 10, 0, 290),
  BackgroundColor3 = COLOR_BG_MED,
  TextColor3 = COLOR_WHITE,
  Text = "Current Target: None",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
}, MainTabFrame)

----------------------------------------------------------------------
-- OPTIONS TAB UI (placeholder for your other toggles)
----------------------------------------------------------------------
new("TextLabel", {
  Size = UDim2.new(1, -20, 0, 30),
  Position = UDim2.new(0, 10, 0, 10),
  BackgroundTransparency = 1,
  TextColor3 = COLOR_WHITE,
  Text = "Options coming soon…",
  TextSize = 14,
  Font = Enum.Font.SourceSans,
  TextXAlignment = Enum.TextXAlignment.Left,
}, OptionsTabFrame)

----------------------------------------------------------------------
-- Data + List binding
----------------------------------------------------------------------
local function applyButtonColor(btn, isSelected)
  btn.BackgroundColor3 = isSelected and COLOR_BTN_ACTIVE or COLOR_BTN
end

local function rebuildList()
  -- clear old
  for _, ch in ipairs(ModelScrollFrame:GetChildren()) do
    if ch:IsA("TextButton") then ch:Destroy() end
  end

  local items = farm.getFiltered()
  local y = 0
  for idx, name in ipairs(items) do
    local btn = new("TextButton", {
      Size = UDim2.new(1, -10, 0, 30),
      BackgroundColor3 = COLOR_BTN,
      TextColor3 = COLOR_WHITE,
      Text = name,
      TextSize = 14,
      Font = Enum.Font.SourceSans,
      LayoutOrder = idx,
    }, ModelScrollFrame)

    applyButtonColor(btn, farm.isSelected(name))

    track(btn.MouseButton1Click:Connect(function()
      farm.toggleSelect(name)
      applyButtonColor(btn, farm.isSelected(name))
    end))

    y += 30
  end
  ModelScrollFrame.CanvasSize = UDim2.new(0, 0, 0, y)
end

-- initial populate
farm.getMonsterModels()
rebuildList()

-- search binding
track(SearchTextBox:GetPropertyChangedSignal("Text"):Connect(function()
  farm.filterMonsterModels(SearchTextBox.Text)
  rebuildList()
end))

----------------------------------------------------------------------
-- Presets wiring (this is what was missing)
----------------------------------------------------------------------
track(SelectWeatherButton.MouseButton1Click:Connect(function()
  if not farm.isSelected("Weather Events") then
    local selected = farm.getSelected()
    table.insert(selected, "Weather Events")
    farm.setSelected(selected)
    utils.notify("🌲 Preset", "Selected all Weather Events models.", 3)
    rebuildList()
  else
    utils.notify("🌲 Preset", "Weather Events already selected.", 3)
  end
end))

track(SelectSahurButton.MouseButton1Click:Connect(function()
  if not farm.isSelected("To Sahur") then
    local selected = farm.getSelected()
    table.insert(selected, "To Sahur")
    farm.setSelected(selected)
    utils.notify("🌲 Preset", "Selected all To Sahur models.", 3)
    rebuildList()
  else
    utils.notify("🌲 Preset", "To Sahur already selected.", 3)
  end
end))

track(SelectAllButton.MouseButton1Click:Connect(function()
  local all = {}
  for _, n in ipairs(farm.getMonsterModels()) do table.insert(all, n) end
  farm.setSelected(all)
  utils.notify("🌲 Preset", "Selected all models.", 3)
  rebuildList()
end))

track(ClearAllButton.MouseButton1Click:Connect(function()
  farm.setSelected({})
  utils.notify("🌲 Preset", "Cleared all selections.", 3)
  rebuildList()
end))

----------------------------------------------------------------------
-- Auto-Farm toggle
----------------------------------------------------------------------
local autoFarmEnabled = false

-- give farm its RemoteFunction
farm.setupAutoAttackRemote()

track(AutoFarmToggle.MouseButton1Click:Connect(function()
  autoFarmEnabled = not autoFarmEnabled
  AutoFarmToggle.Text = "Auto-Farm: " .. (autoFarmEnabled and "ON" or "OFF")
  AutoFarmToggle.BackgroundColor3 = autoFarmEnabled and COLOR_BTN_ACTIVE or COLOR_BTN

  if autoFarmEnabled then
    utils.notify("🌲 Auto-Farm", "Enabled. Weather Events prioritized.", 3)
    task.spawn(function()
      farm.runAutoFarm(function() return autoFarmEnabled end, function(txt)
        -- live target updates
        CurrentTargetLabel.Text = txt or "Current Target: None"
      end)
      -- when it exits, normalize the toggle if the loop stopped for any reason
      AutoFarmToggle.Text = "Auto-Farm: OFF"
      AutoFarmToggle.BackgroundColor3 = COLOR_BTN
      autoFarmEnabled = false
    end)
  else
    utils.notify("🌲 Auto-Farm", "Disabled.", 3)
  end
end))

----------------------------------------------------------------------
-- Done
----------------------------------------------------------------------
utils.notify("🌲 WoodzHUB", "UI ready. Preset buttons now wired.", 4)
