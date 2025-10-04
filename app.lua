-- app.lua
-- Self-contained UI (fallback utils if none injected).
-- Wires to farm.lua, merchants.lua (plural), anti_afk.lua, crates.lua (optional).

-- ===== Services =====
local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player    = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

-- ===== utils (injected or fallback) =====
local function buildUtilsFallback()
  local COLOR_BG_DARK = Color3.fromRGB(30,30,30)
  local COLOR_BG_MED  = Color3.fromRGB(50,50,50)
  local COLOR_WHITE   = Color3.fromRGB(255,255,255)

  local function notify(title, content, duration)
    local ok, pg = pcall(function() return player:WaitForChild("PlayerGui", 5) end)
    if not ok or not pg then return end
    local gui = Instance.new("ScreenGui")
    gui.Name = "WoodzNotify_app"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 2_000_000_000
    gui.Parent = pg

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 100)
    frame.Position = UDim2.new(1, -310, 0, 10)
    frame.BackgroundColor3 = COLOR_BG_DARK
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, 0, 0, 30)
    titleLbl.BackgroundColor3 = COLOR_BG_MED
    titleLbl.BorderSizePixel = 0
    titleLbl.TextColor3 = COLOR_WHITE
    titleLbl.Text = tostring(title or "")
    titleLbl.TextSize = 14
    titleLbl.Font = Enum.Font.SourceSansBold
    titleLbl.Parent = frame

    local bodyLbl = Instance.new("TextLabel")
    bodyLbl.Size = UDim2.new(1, -10, 0, 60)
    bodyLbl.Position = UDim2.new(0, 5, 0, 35)
    bodyLbl.BackgroundTransparency = 1
    bodyLbl.TextColor3 = COLOR_WHITE
    bodyLbl.TextWrapped = true
    bodyLbl.Text = tostring(content or "")
    bodyLbl.TextSize = 14
    bodyLbl.Font = Enum.Font.SourceSans
    bodyLbl.Parent = frame

    task.spawn(function()
      task.wait(tonumber(duration) or 3)
      if gui then gui:Destroy() end
    end)
  end

  local function waitForCharacter()
    while true do
      local ch = player.Character
      if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
        return ch
      end
      player.CharacterAdded:Wait()
      task.wait(0.05)
    end
  end

  return { notify = notify, waitForCharacter = waitForCharacter }
end

local function getInjectedUtils()
  local s = rawget(getfenv(), "script")
  if type(s) == "table" and s._deps and s._deps.utils then return s._deps.utils end
  if typeof(s) == "Instance" and s.Parent then
    local ok, depsFolder = pcall(function() return s.Parent:FindFirstChild("_deps") end)
    if ok and typeof(depsFolder) == "Instance" then
      local ms = depsFolder:FindFirstChild("utils")
      if ms then local ok2, mod = pcall(require, ms); if ok2 then return mod end end
    end
    if type(s.Parent._deps) == "table" and s.Parent._deps.utils then
      return s.Parent._deps.utils
    end
  end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return nil
end

local utils = getInjectedUtils() or buildUtilsFallback()

-- ===== loader-safe tryRequire =====
local function tryRequire(name)
  local s = rawget(getfenv(), "script")

  -- a) script as table with _deps
  if type(s) == "table" and s._deps and s._deps[name] then
    return s._deps[name]
  end

  -- b) global deps table
  local DEPS = rawget(getfenv(), "__WOODZ_DEPS")
  if type(DEPS) == "table" and DEPS[name] then
    return DEPS[name]
  end

  -- c) script Instance → Parent._deps ModuleScript or child ModuleScript or table _deps
  if typeof(s) == "Instance" and s.Parent then
    local ok, depsFolder = pcall(function() return s.Parent:FindFirstChild("_deps") end)
    if ok and typeof(depsFolder) == "Instance" then
      local depMS = depsFolder:FindFirstChild(name)
      if depMS then local okr, mod = pcall(require, depMS); if okr then return mod end end
    end
    local child = s.Parent:FindFirstChild(name)
    if child then local okr, mod = pcall(require, child); if okr then return mod end end
    if type(s.Parent._deps) == "table" and s.Parent._deps[name] then
      return s.Parent._deps[name]
    end
  end

  -- d) globals like __WOODZ_FARM
  local g = rawget(getfenv(), "__WOODZ_" .. string.upper(name))
  if g then return g end

  return nil
end

-- ===== require farm/other modules =====
local farm = tryRequire("farm")
if not farm then utils.notify("🌲 WoodzHUB Error", "farm.lua missing or failed to load.", 5); return end

local merchants = tryRequire("merchants") -- YOUR existing file (plural)
local antiAFK   = tryRequire("anti_afk")
local crates    = tryRequire("crates")    -- optional

-- ===== UI helpers =====
local function new(t, props, parent)
  local i = Instance.new(t)
  if props then for k, v in pairs(props) do i[k] = v end end
  if parent then i.Parent = parent end
  return i
end
local uiConns = {}
local function track(c) table.insert(uiConns, c); return c end

-- Colors/sizing
local COLOR_BG_DARK     = Color3.fromRGB(30,30,30)
local COLOR_BG          = Color3.fromRGB(40,40,40)
local COLOR_BG_MED      = Color3.fromRGB(50,50,50)
local COLOR_BTN         = Color3.fromRGB(60,60,60)
local COLOR_BTN_ACTIVE  = Color3.fromRGB(80,80,80)
local COLOR_WHITE       = Color3.fromRGB(255,255,255)
local SIZE_MAIN         = UDim2.new(0,400,0,570)
local SIZE_MIN          = UDim2.new(0,400,0,50)

-- ===== Root GUI =====
local ScreenGui = new("ScreenGui", {
  Name = "WoodzHUB",
  ResetOnSpawn = false,
  ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
  DisplayOrder = 999999999,
  Enabled = true,
}, PlayerGui)

local MainFrame = new("Frame", {
  Size = SIZE_MAIN,
  Position = UDim2.new(0.5,-200,0.5,-285),
  BackgroundColor3 = COLOR_BG_DARK,
  BorderSizePixel = 0,
}, ScreenGui)

local TitleLabel = new("TextLabel", {
  Size = UDim2.new(1,-60,0,50),
  BackgroundColor3 = COLOR_BG_MED,
  Text = "🌲 WoodzHUB",
  TextColor3 = COLOR_WHITE,
  TextSize = 14,
  Font = Enum.Font.SourceSansBold,
}, MainFrame)

local FrameBar = new("Frame", {
  Size = UDim2.new(0,60,0,50),
  Position = UDim2.new(1,-60,0,0),
  BackgroundColor3 = COLOR_BG_MED,
}, MainFrame)

local MinimizeButton = new("TextButton", { Size = UDim2.new(0.333,0,1,0), BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE, Text = "-", TextSize = 14, Font = Enum.Font.SourceSans }, FrameBar)
local MaximizeButton = new("TextButton", { Size = UDim2.new(0.333,0,1,0), Position = UDim2.new(0.333,0,0,0), BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE, Text = "□", TextSize = 14, Font = Enum.Font.SourceSans, Visible = false }, FrameBar)
local CloseButton    = new("TextButton", { Size = UDim2.new(0.333,0,1,0), Position = UDim2.new(0.666,0,0,0), BackgroundColor3 = Color3.fromRGB(200,50,50), TextColor3 = COLOR_WHITE, Text = "X", TextSize = 14, Font = Enum.Font.SourceSans }, FrameBar)

local TabFrame = new("Frame", { Size = UDim2.new(1,0,0,30), Position = UDim2.new(0,0,0,50), BackgroundColor3 = COLOR_BG }, MainFrame)
local MainTabButton    = new("TextButton", { Size = UDim2.new(0.5,0,1,0), Text = "Main", TextColor3 = COLOR_WHITE, BackgroundColor3 = COLOR_BTN, TextSize = 14, Font = Enum.Font.SourceSans }, TabFrame)
local OptionsTabButton = new("TextButton", { Size = UDim2.new(0.5,0,1,0), Position = UDim2.new(0.5,0,0,0), Text = "Options", TextColor3 = COLOR_WHITE, BackgroundColor3 = COLOR_BG, TextSize = 14, Font = Enum.Font.SourceSans }, TabFrame)

local MainTabFrame    = new("Frame", { Size = UDim2.new(1,0,1,-80), Position = UDim2.new(0,0,0,80), BackgroundTransparency = 1 }, MainFrame)
local OptionsTabFrame = new("Frame", { Size = UDim2.new(1,0,1,-80), Position = UDim2.new(0,0,0,80), BackgroundTransparency = 1, Visible = false }, MainFrame)

-- drag
do
  local dragging, startMouse, startPos = false, nil, nil
  local function begin(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = true; startMouse = input.Position; startPos = MainFrame.Position
    end
  end
  local function finish(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging = false; startMouse = nil; startPos = nil
    end
  end
  local function update(input)
    if not dragging or not startMouse or not startPos then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local d = input.Position - startMouse
    MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
  end
  track(TitleLabel.InputBegan:Connect(begin))
  track(TitleLabel.InputEnded:Connect(finish))
  track(FrameBar.InputBegan:Connect(begin))
  track(FrameBar.InputEnded:Connect(finish))
  track(UserInputService.InputChanged:Connect(update))
end

-- min/max/close
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
  MainTabFrame.Visible  = MainTabButton.BackgroundColor3 == COLOR_BTN
  OptionsTabFrame.Visible = OptionsTabButton.BackgroundColor3 == COLOR_BTN
  MinimizeButton.Visible = true
  MaximizeButton.Visible = false
end
track(MinimizeButton.MouseButton1Click:Connect(minimize))
track(MaximizeButton.MouseButton1Click:Connect(maximize))
track(CloseButton.MouseButton1Click:Connect(function() ScreenGui:Destroy() end))

local function gotoMain()
  if isMinimized then return end
  MainTabButton.BackgroundColor3 = COLOR_BTN
  OptionsTabButton.BackgroundColor3 = COLOR_BG
  MainTabFrame.Visible, OptionsTabFrame.Visible = true, false
end
local function gotoOptions()
  if isMinimized then return end
  MainTabButton.BackgroundColor3 = COLOR_BG
  OptionsTabButton.BackgroundColor3 = COLOR_BTN
  MainTabFrame.Visible, OptionsTabFrame.Visible = false, true
end
track(MainTabButton.MouseButton1Click:Connect(gotoMain))
track(OptionsTabButton.MouseButton1Click:Connect(gotoOptions))

-- ===== MAIN tab controls =====
local SearchTextBox = new("TextBox", {
  Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,10),
  BackgroundColor3 = COLOR_BG_MED, TextColor3 = COLOR_WHITE,
  PlaceholderText = "Enter model names to search...", TextSize = 14,
  Font = Enum.Font.SourceSans, Text = "", ClearTextOnFocus = false,
}, MainTabFrame)

local ModelScrollFrame = new("ScrollingFrame", {
  Size = UDim2.new(1,-20,0,150), Position = UDim2.new(0,10,0,50),
  BackgroundColor3 = COLOR_BG_MED, CanvasSize = UDim2.new(0,0,0,0),
  ScrollBarThickness = 8,
}, MainTabFrame)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, ModelScrollFrame)

local PresetButtonsFrame = new("Frame", { Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,210), BackgroundTransparency = 1 }, MainTabFrame)

local SelectSahurButton   = new("TextButton", { Size = UDim2.new(0.25,0,1,0), BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE, Text = "Select To Sahur", TextSize = 14, Font = Enum.Font.SourceSans }, PresetButtonsFrame)
local SelectWeatherButton = new("TextButton", { Size = UDim2.new(0.25,0,1,0), Position = UDim2.new(0.25,0,0,0), BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE, Text = "Select Weather", TextSize = 14, Font = Enum.Font.SourceSans }, PresetButtonsFrame)
local SelectAllButton     = new("TextButton", { Size = UDim2.new(0.25,0,1,0), Position = UDim2.new(0.50,0,0,0), BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE, Text = "Select All", TextSize = 14, Font = Enum.Font.SourceSans }, PresetButtonsFrame)
local ClearAllButton      = new("TextButton", { Size = UDim2.new(0.25,0,1,0), Position = UDim2.new(0.75,0,0,0), BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE, Text = "Clear All", TextSize = 14, Font = Enum.Font.SourceSans }, PresetButtonsFrame)

local AutoFarmToggle = new("TextButton", {
  Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,250),
  BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE,
  Text = "Auto-Farm: OFF", TextSize = 14, Font = Enum.Font.SourceSans
}, MainTabFrame)

local CurrentTargetLabel = new("TextLabel", {
  Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,290),
  BackgroundColor3 = COLOR_BG_MED, TextColor3 = COLOR_WHITE,
  Text = "Current Target: None", TextSize = 14, Font = Enum.Font.SourceSans
}, MainTabFrame)

-- ===== OPTIONS tab controls =====
local ToggleMerchant1Button = new("TextButton", {
  Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,10),
  BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE,
  Text = "Auto Buy Mythics (Chicleteiramania): OFF", TextSize = 14, Font = Enum.Font.SourceSans
}, OptionsTabFrame)

local ToggleMerchant2Button = new("TextButton", {
  Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,50),
  BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE,
  Text = "Auto Buy Mythics (Bombardino Sewer): OFF", TextSize = 14, Font = Enum.Font.SourceSans
}, OptionsTabFrame)

local ToggleAutoCratesButton = new("TextButton", {
  Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,90),
  BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE,
  Text = "Auto Open Crates: OFF", TextSize = 14, Font = Enum.Font.SourceSans
}, OptionsTabFrame)

local ToggleAntiAFKButton = new("TextButton", {
  Size = UDim2.new(1,-20,0,30), Position = UDim2.new(0,10,0,130),
  BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE,
  Text = "Anti-AFK: OFF", TextSize = 14, Font = Enum.Font.SourceSans
}, OptionsTabFrame)

-- ===== List helpers =====
local function applyButtonColor(btn, isSelected)
  btn.BackgroundColor3 = isSelected and COLOR_BTN_ACTIVE or COLOR_BTN
end

local function rebuildList()
  for _, ch in ipairs(ModelScrollFrame:GetChildren()) do
    if ch:IsA("TextButton") then ch:Destroy() end
  end
  local items = farm.getFiltered()
  local y = 0
  for i, name in ipairs(items) do
    local btn = new("TextButton", {
      Size = UDim2.new(1,-10,0,30),
      BackgroundColor3 = COLOR_BTN, TextColor3 = COLOR_WHITE,
      Text = name, TextSize = 14, Font = Enum.Font.SourceSans, LayoutOrder = i
    }, ModelScrollFrame)
    applyButtonColor(btn, farm.isSelected(name))
    track(btn.MouseButton1Click:Connect(function()
      farm.toggleSelect(name)
      applyButtonColor(btn, farm.isSelected(name))
      if autoFarmEnabled then farm.forceRetarget() end
    end))
    y += 30
  end
  ModelScrollFrame.CanvasSize = UDim2.new(0,0,0,y)
end

-- init list
farm.getMonsterModels()
rebuildList()
track(SearchTextBox:GetPropertyChangedSignal("Text"):Connect(function()
  farm.filterMonsterModels(SearchTextBox and SearchTextBox.Text or "")
  rebuildList()
end))

-- presets
local function ensureSelected(name)
  if not farm.isSelected(name) then farm.toggleSelect(name) end
end
track(SelectWeatherButton.MouseButton1Click:Connect(function()
  ensureSelected("Weather Events")
  utils.notify("🌲 Preset", "Weather Events selected.", 3)
  farm.filterMonsterModels(SearchTextBox and SearchTextBox.Text or ""); rebuildList()
  if autoFarmEnabled then
    local c = farm.countWeatherEnemies and farm.countWeatherEnemies() or -1
    if c and c >= 0 then utils.notify("🌲 Auto-Farm", "Weather targets found: "..tostring(c), 3) end
    farm.forceRetarget()
  end
end))
track(SelectSahurButton.MouseButton1Click:Connect(function()
  ensureSelected("To Sahur")
  utils.notify("🌲 Preset", "To Sahur selected.", 3)
  farm.filterMonsterModels(SearchTextBox and SearchTextBox.Text or ""); rebuildList()
  if autoFarmEnabled then
    local c = farm.countSahurEnemies and farm.countSahurEnemies() or -1
    if c and c >= 0 then utils.notify("🌲 Auto-Farm", "To Sahur targets found: "..tostring(c), 3) end
    farm.forceRetarget()
  end
end))
track(SelectAllButton.MouseButton1Click:Connect(function()
  local all = {}; for _, n in ipairs(farm.getMonsterModels()) do table.insert(all, n) end
  farm.setSelected(all); utils.notify("🌲 Preset","Selected all models.",3)
  farm.filterMonsterModels(SearchTextBox and SearchTextBox.Text or ""); rebuildList()
  if autoFarmEnabled then farm.forceRetarget() end
end))
track(ClearAllButton.MouseButton1Click:Connect(function()
  farm.setSelected({}); utils.notify("🌲 Preset","Cleared all selections.",3)
  farm.filterMonsterModels(SearchTextBox and SearchTextBox.Text or ""); rebuildList()
  if autoFarmEnabled then farm.forceRetarget() end
end))

-- ===== Auto-farm toggle =====
autoFarmEnabled = false
if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end

track(AutoFarmToggle.MouseButton1Click:Connect(function()
  autoFarmEnabled = not autoFarmEnabled
  AutoFarmToggle.Text = "Auto-Farm: " .. (autoFarmEnabled and "ON" or "OFF")
  AutoFarmToggle.BackgroundColor3 = autoFarmEnabled and COLOR_BTN_ACTIVE or COLOR_BTN
  if autoFarmEnabled then
    utils.notify("🌲 Auto-Farm", "Enabled. Weather Events prioritized.", 3)
    task.spawn(function()
      farm.runAutoFarm(function() return autoFarmEnabled end, function(txt)
        CurrentTargetLabel.Text = txt or "Current Target: None"
      end)
      -- when farm loop exits, normalize toggle
      AutoFarmToggle.Text = "Auto-Farm: OFF"
      AutoFarmToggle.BackgroundColor3 = COLOR_BTN
      autoFarmEnabled = false
    end)
    farm.forceRetarget()
  else
    utils.notify("🌲 Auto-Farm", "Disabled.", 3)
  end
end))

-- ===== Options toggles =====
local m1Enabled, m2Enabled, cratesEnabled, afkEnabled = false, false, false, false
local function setBtn(btn, on, label) btn.Text = label .. (on and "ON" or "OFF"); btn.BackgroundColor3 = on and COLOR_BTN_ACTIVE or COLOR_BTN end

-- Merchants via your merchants.lua
track(ToggleMerchant1Button.MouseButton1Click:Connect(function()
  m1Enabled = not m1Enabled
  local ok = false
  if merchants and merchants.autoBuyLoop then
    ok = true
    if m1Enabled then
      task.spawn(function()
        merchants.autoBuyLoop("SmelterMerchantService", function() return m1Enabled end, function(sfx)
          ToggleMerchant1Button.Text = "Auto Buy Mythics (Chicleteiramania): ON " .. (sfx or "")
        end)
      end)
    end
  end
  if not ok then utils.notify("🌲 Merchant", "merchants.lua missing or failed (SmelterMerchantService).", 4) end
  setBtn(ToggleMerchant1Button, m1Enabled, "Auto Buy Mythics (Chicleteiramania): ")
end))

track(ToggleMerchant2Button.MouseButton1Click:Connect(function()
  m2Enabled = not m2Enabled
  local ok = false
  if merchants and merchants.autoBuyLoop then
    ok = true
    if m2Enabled then
      task.spawn(function()
        merchants.autoBuyLoop("SmelterMerchantService2", function() return m2Enabled end, function(sfx)
          ToggleMerchant2Button.Text = "Auto Buy Mythics (Bombardino Sewer): ON " .. (sfx or "")
        end)
      end)
    end
  end
  if not ok then utils.notify("🌲 Merchant", "merchants.lua missing or failed (SmelterMerchantService2).", 4) end
  setBtn(ToggleMerchant2Button, m2Enabled, "Auto Buy Mythics (Bombardino Sewer): ")
end))

-- Auto Crates (optional module)
track(ToggleAutoCratesButton.MouseButton1Click:Connect(function()
  cratesEnabled = not cratesEnabled
  local ok = false
  if crates and crates.setEnabled then
    ok = pcall(function() crates.setEnabled(cratesEnabled) end)
  end
  if not ok then utils.notify("🎁 Crates", "crates.lua missing or failed.", 4) end
  setBtn(ToggleAutoCratesButton, cratesEnabled, "Auto Open Crates: ")
end))

-- Anti-AFK
track(ToggleAntiAFKButton.MouseButton1Click:Connect(function()
  afkEnabled = not afkEnabled
  local ok = false
  if antiAFK and antiAFK.setEnabled then ok = pcall(function() antiAFK.setEnabled(afkEnabled) end) end
  if not ok then utils.notify("🌲 Anti-AFK", "anti_afk.lua missing or failed.", 4) end
  setBtn(ToggleAntiAFKButton, afkEnabled, "Anti-AFK: ")
end))

utils.notify("🌲 WoodzHUB", "UI ready. Weather/Sahur presets nudge farm. Options wired.", 4)
