-- ui.lua
local Players = game:GetService('Players')
local StarterGui = game:GetService('StarterGui')
local UserInputService = game:GetService('UserInputService')

local utils     = require(script.Parent._deps.utils)
local hud       = require(script.Parent.hud)
local constants = require(script.Parent.constants)

local M = {}

function M.build()
  local player = Players.LocalPlayer
  local PlayerGui = player:WaitForChild('PlayerGui')
  local ui = {}

  local ScreenGui = utils.new('ScreenGui', {Name='WoodzHUB', ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, DisplayOrder=999999999, Enabled=true, IgnoreGuiInset=false}, PlayerGui)
  ui.ScreenGui = ScreenGui

  local MainFrame = utils.new('Frame', {Size=constants.SIZE_MAIN, Position=UDim2.new(0.5,-200,0.5,-270), BackgroundColor3=constants.COLOR_BG_DARK, BorderSizePixel=0}, ScreenGui)
  ui.MainFrame = MainFrame

  ui.TitleLabel = utils.new('TextLabel', {Size=UDim2.new(1,-60,0,50), BackgroundColor3=constants.COLOR_BG_MED, Text='🌲 WoodzHUB - Brainrot Evolution', TextColor3=constants.COLOR_WHITE, TextSize=14, Font=Enum.Font.SourceSansBold}, MainFrame)

  local FrameBar = utils.new('Frame', {Size=UDim2.new(0,60,0,50), Position=UDim2.new(1,-60,0,0), BackgroundColor3=constants.COLOR_BG_MED}, MainFrame)
  ui.MinimizeButton = utils.new('TextButton', {Size=UDim2.new(0.333,0,1,0), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='-', TextSize=14, Font=Enum.Font.SourceSans}, FrameBar)
  ui.MaximizeButton = utils.new('TextButton', {Size=UDim2.new(0.333,0,1,0), Position=UDim2.new(0.333,0,0,0), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='□', TextSize=14, Font=Enum.Font.SourceSans, Visible=false}, FrameBar)
  ui.CloseButton = utils.new('TextButton', {Size=UDim2.new(0.333,0,1,0), Position=UDim2.new(0.666,0,0,0), BackgroundColor3=Color3.fromRGB(200,50,50), TextColor3=constants.COLOR_WHITE, Text='X', TextSize=14, Font=Enum.Font.SourceSans}, FrameBar)

  local TabFrame = utils.new('Frame', {Size=UDim2.new(1,0,0,30), Position=UDim2.new(0,0,0,50), BackgroundColor3=constants.COLOR_BG}, MainFrame)
  ui.MainTabButton = utils.new('TextButton', {Size=UDim2.new(0.5,0,1,0), Text='Main', TextColor3=constants.COLOR_WHITE, BackgroundColor3=constants.COLOR_BTN, TextSize=14, Font=Enum.Font.SourceSans}, TabFrame)
  ui.LoggingTabButton = utils.new('TextButton', {Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0.5,0,0,0), Text='Options', TextColor3=constants.COLOR_WHITE, BackgroundColor3=constants.COLOR_BG, TextSize=14, Font=Enum.Font.SourceSans}, TabFrame)

  ui.MainTabFrame = utils.new('Frame', {Size=UDim2.new(1,0,1,-80), Position=UDim2.new(0,0,0,80), BackgroundTransparency=1}, MainFrame)
  ui.LoggingTabFrame = utils.new('Frame', {Size=UDim2.new(1,0,1,-80), Position=UDim2.new(0,0,0,80), BackgroundTransparency=1, Visible=false}, MainFrame)

  ui.SearchTextBox = utils.new('TextBox', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,10), BackgroundColor3=constants.COLOR_BG_MED, TextColor3=constants.COLOR_WHITE, PlaceholderText='Enter model names to search...', TextSize=14, Font=Enum.Font.SourceSans, Text='', ClearTextOnFocus=false}, ui.MainTabFrame)
  ui.ModelScrollFrame = utils.new('ScrollingFrame', {Size=UDim2.new(1,-20,0,150), Position=UDim2.new(0,10,0,50), BackgroundColor3=constants.COLOR_BG_MED, CanvasSize=UDim2.new(0,0,0,0), ScrollBarThickness=8}, ui.MainTabFrame)
  utils.new('UIListLayout', {SortOrder=Enum.SortOrder.LayoutOrder}, ui.ModelScrollFrame)

  local PresetButtonsFrame = utils.new('Frame', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,210), BackgroundTransparency=1}, ui.MainTabFrame)
  ui.SelectSahurButton   = utils.new('TextButton',{Size=UDim2.new(0.25,0,1,0), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Select To Sahur', TextSize=14, Font=Enum.Font.SourceSans}, PresetButtonsFrame)
  ui.SelectWeatherButton = utils.new('TextButton',{Size=UDim2.new(0.25,0,1,0), Position=UDim2.new(0.25,0,0,0), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Select Weather', TextSize=14, Font=Enum.Font.SourceSans}, PresetButtonsFrame)
  ui.SelectAllButton     = utils.new('TextButton',{Size=UDim2.new(0.25,0,1,0), Position=UDim2.new(0.50,0,0,0), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Select All', TextSize=14, Font=Enum.Font.SourceSans}, PresetButtonsFrame)
  ui.ClearAllButton      = utils.new('TextButton',{Size=UDim2.new(0.25,0,1,0), Position=UDim2.new(0.75,0,0,0), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Clear All', TextSize=14, Font=Enum.Font.SourceSans}, PresetButtonsFrame)

  ui.AutoFarmToggle = utils.new('TextButton', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,250), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Auto-Farm: OFF', TextSize=14, Font=Enum.Font.SourceSans}, ui.MainTabFrame)
  ui.CurrentTargetLabel = utils.new('TextLabel', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,290), BackgroundColor3=constants.COLOR_BG_MED, TextColor3=constants.COLOR_WHITE, Text='Current Target: None', TextSize=14, Font=Enum.Font.SourceSans}, ui.MainTabFrame)

  -- Options tab toggles
  ui.ToggleMerchant1Button = utils.new('TextButton', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,10), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Auto Buy Mythics (Chicleteiramania): OFF', TextSize=14, Font=Enum.Font.SourceSans}, ui.LoggingTabFrame)
  ui.ToggleMerchant2Button = utils.new('TextButton', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,50), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Auto Buy Mythics (Bombardino Sewer): OFF', TextSize=14, Font=Enum.Font.SourceSans}, ui.LoggingTabFrame)
  ui.ToggleAutoCratesButton = utils.new('TextButton', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,90), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Auto Open Crates: OFF', TextSize=14, Font=Enum.Font.SourceSans}, ui.LoggingTabFrame)
  -- NEW: Anti-AFK toggle
  ui.ToggleAntiAFKButton  = utils.new('TextButton', {Size=UDim2.new(1,-20,0,30), Position=UDim2.new(0,10,0,130), BackgroundColor3=constants.COLOR_BTN, TextColor3=constants.COLOR_WHITE, Text='Anti-AFK: OFF', TextSize=14, Font=Enum.Font.SourceSans}, ui.LoggingTabFrame)

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
    utils.track(ui.TitleLabel.InputBegan:Connect(begin))
    utils.track(ui.TitleLabel.InputEnded:Connect(finish))
    utils.track(UserInputService.InputChanged:Connect(update))
  end

  -- HUD auto-apply + watch
  do
    local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local h1 = hud.findHUD(PlayerGui); if h1 then hud.apply(h1, flags); utils.track(hud.watch(h1, flags)) end
    local h2 = hud.findHUD(StarterGui); if h2 then hud.apply(h2, flags); utils.track(hud.watch(h2, flags)) end
  end

  return ui
end

return M
