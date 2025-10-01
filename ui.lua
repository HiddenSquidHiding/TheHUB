-- ui.lua
-- Builds the entire GUI and returns references used by app.lua
-- Includes tab switching + minimize/maximize behavior.

-- 🔧 Safe utils access
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[ui.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading ui.lua")
end

local utils     = getUtils()
local constants = require(script.Parent.constants)
local hud       = require(script.Parent.hud)

local Players = game:GetService('Players')
local StarterGui = game:GetService('StarterGui')
local UserInputService = game:GetService('UserInputService')

local M = {}

function M.build()
  local player    = Players.LocalPlayer
  local PlayerGui = player:WaitForChild('PlayerGui')

  local UI = {}

  -- Root
  local ScreenGui = utils.new('ScreenGui', {
    Name='WoodzHUB', ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    DisplayOrder=999999999, Enabled=true, IgnoreGuiInset=false
  }, PlayerGui)
  UI.ScreenGui = ScreenGui

  local MainFrame = utils.new('Frame', {
    Size=constants.SIZE_MAIN, Position=UDim2.new(0.5,-200,0.5,-270),
    BackgroundColor3=constants.COLOR_BG_DARK, BorderSizePixel=0
  }, ScreenGui)
  UI.MainFrame = MainFrame

  UI.TitleLabel = utils.new('TextLabel', {
    Size=UDim2.new(1,-60,0,50),
    BackgroundColor3=constants.COLOR_BG_MED,
    Text='🌲 WoodzHUB - Brainrot Evolution',
    TextColor3=constants.COLOR_WHITE, TextSize=14, Font=Enum.Font.SourceSansBold
  }, MainFrame)

  local FrameBar = utils.new('Frame', {
    Size=UDim2.new(0,60,0,50), Position=UDim2.new(1,-60,0,0),
    BackgroundColor3=constants.COLOR_BG_MED
  }, MainFrame)

  UI.MinimizeButton = utils.new('TextButton', {
    Size=UDim2.new(0.333,0,1,0), BackgroundColor3=constants.COLOR_BTN,
    TextColor3=constants.COLOR_WHITE, Text='-', TextSize=14, Font=Enum.Font.SourceSans
  }, FrameBar)

  UI.MaximizeButton = utils.new('TextButton', {
    Size=UDim2.new(0.333,0,1,0), Position=UDim2.new(0.333,0,0,0),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='□', TextSize=14, Font=Enum.Font.SourceSans, Visible=false
  }, FrameBar)

  UI.CloseButton = utils.new('TextButton', {
    Size=UDim2.new(0.333,0,1,0), Position=UDim2.new(0.666,0,0,0),
    BackgroundColor3=Color3.fromRGB(200,50,50), TextColor3=constants.COLOR_WHITE,
    Text='X', TextSize=14, Font=Enum.Font.SourceSans
  }, FrameBar)

  -- Tabs
  local TabFrame = utils.new('Frame', {
    Size=UDim2.new(1,0,0,30), Position=UDim2.new(0,0,0,50),
    BackgroundColor3=constants.COLOR_BG
  }, MainFrame)

  UI.MainTabButton = utils.new('TextButton', {
    Size=UDim2.new(0.5,0,1,0), Text='Main', TextColor3=constants.COLOR_WHITE,
    BackgroundColor3=constants.COLOR_BTN, TextSize=14, Font=Enum.Font.SourceSans
  }, TabFrame)

  UI.LoggingTabButton = utils.new('TextButton', {
    Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0.5,0,0,0), Text='Options',
    TextColor3=constants.COLOR_WHITE, BackgroundColor3=constants.COLOR_BG,
    TextSize=14, Font=Enum.Font.SourceSans
  }, TabFrame)

  UI.MainTabFrame = utils.new('Frame', {
    Size=UDim2.new(1,0,1,-80), Position=UDim2.new(0,0,0,80), BackgroundTransparency=1
  }, MainFrame)

  UI.LoggingTabFrame = utils.new('Frame', {
    Size=UDim2.new(1,0,1,-80), Position=UDim2.new(0,0,0,80),
    BackgroundTransparency=1, Visible=false
  }, MainFrame)

  -- Main tab controls
  UI.SearchTextBox = utils.new('TextBox', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,10),
    BackgroundColor3=constants.COLOR_BG_MED, TextColor3=constants.COLOR_WHITE,
    PlaceholderText='Enter model names to search...', TextSize=14,
    Font=Enum.Font.SourceSans, Text='', ClearTextOnFocus=false
  }, UI.MainTabFrame)

  UI.ModelScrollFrame = utils.new('ScrollingFrame', {
    Size=UDim2.new(1,-20,0,150), Position=UDim2.new(0,10,0,50),
    BackgroundColor3=constants.COLOR_BG_MED, CanvasSize=UDim2.new(0,0,0,0),
    ScrollBarThickness=8
  }, UI.MainTabFrame)
  utils.new('UIListLayout', {SortOrder=Enum.SortOrder.LayoutOrder}, UI.ModelScrollFrame)

  local PresetButtonsFrame = utils.new('Frame', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,210), BackgroundTransparency=1
  }, UI.MainTabFrame)

  UI.SelectSahurButton = utils.new('TextButton', {
    Size=UDim2.new(0.25,0,1,0), BackgroundColor3=constants.COLOR_BTN,
    TextColor3=constants.COLOR_WHITE, Text='Select To Sahur', TextSize=14,
    Font=Enum.Font.SourceSans
  }, PresetButtonsFrame)

  UI.SelectWeatherButton = utils.new('TextButton', {
    Size=UDim2.new(0.25,0,1,0), Position=UDim2.new(0.25,0,0,0),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Select Weather', TextSize=14, Font=Enum.Font.SourceSans
  }, PresetButtonsFrame)

  UI.SelectAllButton = utils.new('TextButton', {
    Size=UDim2.new(0.25,0,1,0), Position=UDim2.new(0.50,0,0,0),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Select All', TextSize=14, Font=Enum.Font.SourceSans
  }, PresetButtonsFrame)

  UI.ClearAllButton = utils.new('TextButton', {
    Size=UDim2.new(0.25,0,1,0), Position=UDim2.new(0.75,0,0,0),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Clear All', TextSize=14, Font=Enum.Font.SourceSans
  }, PresetButtonsFrame)

  UI.AutoFarmToggle = utils.new('TextButton', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,250),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Auto-Farm: OFF', TextSize=14, Font=Enum.Font.SourceSans
  }, UI.MainTabFrame)

  UI.CurrentTargetLabel = utils.new('TextLabel', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,290),
    BackgroundColor3=constants.COLOR_BG_MED, TextColor3=constants.COLOR_WHITE,
    Text='Current Target: None', TextSize=14, Font=Enum.Font.SourceSans
  }, UI.MainTabFrame)

  -- Options tab toggles
  UI.ToggleMerchant1Button = utils.new('TextButton', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,10),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Auto Buy Mythics (Chicleteiramania): OFF', TextSize=14, Font=Enum.Font.SourceSans
  }, UI.LoggingTabFrame)

  UI.ToggleMerchant2Button = utils.new('TextButton', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,50),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Auto Buy Mythics (Bombardino Sewer): OFF', TextSize=14, Font=Enum.Font.SourceSans
  }, UI.LoggingTabFrame)

  UI.ToggleAutoCratesButton = utils.new('TextButton', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,90),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Auto Open Crates: OFF', TextSize=14, Font=Enum.Font.SourceSans
  }, UI.LoggingTabFrame)

  UI.ToggleAntiAFKButton = utils.new('TextButton', {
    Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,130),
    BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE,
    Text='Anti-AFK: OFF', TextSize=14, Font=Enum.Font.SourceSans
  }, UI.LoggingTabFrame)

  --------------------------------------------------------------------------
  -- Behavior: dragging + min/max + tab switching
  --------------------------------------------------------------------------
  local isMinimized = false

  -- Dragging
  do
    local dragging, dragStart, startPos = false, nil, nil
    local function begin(input)
      if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, input.Position, MainFrame.Position
      end
    end
    local function finish(input)
      if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end
    local function update(input)
      if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
      end
    end
    utils.track(UI.TitleLabel.InputBegan:Connect(begin))
    utils.track(UI.TitleLabel.InputEnded:Connect(finish))
    utils.track(FrameBar.InputBegan:Connect(begin))
    utils.track(FrameBar.InputEnded:Connect(finish))
    utils.track(UserInputService.InputChanged:Connect(update))
  end

  -- Tab switching helpers
  local function switchToMain()
    if isMinimized then return end
    UI.MainTabFrame.Visible = true
    UI.LoggingTabFrame.Visible = false
    UI.MainTabButton.BackgroundColor3 = constants.COLOR_BTN
    UI.LoggingTabButton.BackgroundColor3 = constants.COLOR_BG
  end

  local function switchToOptions()
    if isMinimized then return end
    UI.MainTabFrame.Visible = false
    UI.LoggingTabFrame.Visible = true
    UI.MainTabButton.BackgroundColor3 = constants.COLOR_BG
    UI.LoggingTabButton.BackgroundColor3 = constants.COLOR_BTN
  end

  utils.track(UI.MainTabButton.MouseButton1Click:Connect(switchToMain))
  utils.track(UI.LoggingTabButton.MouseButton1Click:Connect(switchToOptions))

  -- Min/Max
  local function minimize()
    isMinimized = true
    MainFrame.Size = constants.SIZE_MIN
    UI.MainTabFrame.Visible = false
    UI.LoggingTabFrame.Visible = false
    UI.MinimizeButton.Visible = false
    UI.MaximizeButton.Visible = true
  end
  local function maximize()
    isMinimized = false
    MainFrame.Size = constants.SIZE_MAIN
    -- Keep whichever tab is currently active by button color
    if UI.MainTabButton.BackgroundColor3 == constants.COLOR_BTN then
      switchToMain()
    else
      switchToOptions()
    end
    UI.MinimizeButton.Visible = true
    UI.MaximizeButton.Visible = false
  end
  utils.track(UI.MinimizeButton.MouseButton1Click:Connect(minimize))
  utils.track(UI.MaximizeButton.MouseButton1Click:Connect(maximize))

  -- HUD auto-apply + watch
  do
    local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local h1 = hud.findHUD(PlayerGui); if h1 then hud.apply(h1, flags); utils.track(hud.watch(h1, flags)) end
    local h2 = hud.findHUD(StarterGui); if h2 then hud.apply(h2, flags); utils.track(hud.watch(h2, flags)) end
  end

  return UI
end

return M
