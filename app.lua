-- app.lua
-- Top-level wiring for UI <-> features

-- 🔧 Safer access to injected utils (no require(nil))
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[app.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading app.lua")
end

local utils      = getUtils()
local constants  = require(script.Parent.constants)
local uiModule   = require(script.Parent.ui)
local farm       = require(script.Parent.farm)
local merchants  = require(script.Parent.merchants)
local crates     = require(script.Parent.crates)
local antiAFK    = require(script.Parent.anti_afk)
local smartFarm  = require(script.Parent.smart_target)

-- ✅ Needed for MonsterInfo lookup
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Players = game:GetService('Players')

local app = {}

-- State flags
local autoFarmEnabled       = false
local smartFarmEnabled      = false
local autoBuyM1Enabled      = false
local autoBuyM2Enabled      = false
local autoOpenCratesEnabled = false
local antiAfkEnabled        = false

-- UI refs (populated in start)
local UI = nil

local function notifyToggle(name, on, extra)
  extra = extra or ''
  local msg = on and (name .. ' enabled' .. extra) or (name .. ' disabled')
  utils.notify('🌲 ' .. name, msg, 3.5)
end

local function setAutoFarmUI(on)
  UI.AutoFarmToggle.Text = 'Auto-Farm: '..(on and 'ON' or 'OFF')
  UI.AutoFarmToggle.BackgroundColor3 = on and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
end
local function setSmartFarmUI(on)
  UI.SmartFarmToggle.Text = 'Smart Farm: '..(on and 'ON' or 'OFF')
  UI.SmartFarmToggle.BackgroundColor3 = on and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
end

-- 🔍 Resolve ReplicatedStorage MonsterInfo in several common locations
local function resolveMonsterInfo()
  local RS = ReplicatedStorage
  local candidatePaths = {
    {"GameInfo","MonsterInfo"},     -- << your path
    {"MonsterInfo"},
    {"Shared","MonsterInfo"},
    {"Modules","MonsterInfo"},
    {"Configs","MonsterInfo"},
  }

  for _, path in ipairs(candidatePaths) do
    local node = RS
    local ok = true
    for _, name in ipairs(path) do
      node = node:FindFirstChild(name) or node:WaitForChild(name, 1)
      if not node then ok = false; break end
    end
    if ok and node and node:IsA("ModuleScript") then
      return node
    end
  end

  for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then
      return d
    end
  end
  return nil
end

-- =========================
-- CODES BUTTONS INJECTION
-- =========================

local function deepFind(root, wanted)
  if not root then return nil end
  if root.Name == wanted then return root end
  for _, d in ipairs(root:GetDescendants()) do
    if d.Name == wanted then return d end
  end
  return nil
end

local function findOptionsContainer(UIRef)
  -- Prefer explicit exposed frame
  if UIRef and UIRef.LoggingTabFrame then return UIRef.LoggingTabFrame end
  -- Fallback: search inside ScreenGui
  if UIRef and UIRef.ScreenGui then
    return deepFind(UIRef.ScreenGui, "LoggingTabFrame")
        or deepFind(UIRef.ScreenGui, "OptionsFrame")
        or deepFind(UIRef.ScreenGui, "OptionsTab")
  end
  -- Last resort: search PlayerGui
  local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
  if not pg then return nil end
  local hub = pg:FindFirstChild("WoodzHUB")
  if hub then
    return deepFind(hub, "LoggingTabFrame")
        or deepFind(hub, "OptionsFrame")
        or deepFind(hub, "OptionsTab")
  end
  for _, sg in ipairs(pg:GetChildren()) do
    if sg:IsA("ScreenGui") then
      local hit = deepFind(sg, "LoggingTabFrame")
              or deepFind(sg, "OptionsFrame")
              or deepFind(sg, "OptionsTab")
      if hit then return hit end
    end
  end
  return nil
end

local function injectCodesButtons(container)
  if not container then
    utils.notify("Codes", "Options tab not found; cannot inject codes buttons", 4)
    return
  end

  -- Require logic module
  local codesLogic
  do
    local ok, mod = pcall(function() return require(script.Parent.redeem_unredeemed_codes) end)
    if not ok or type(mod) ~= "table" or type(mod.run) ~= "function" then
      utils.notify("Codes", "redeem_unredeemed_codes.lua missing or invalid; cannot add buttons", 4)
      return
    end
    codesLogic = mod
  end

  -- Avoid duplicates
  if container:FindFirstChild("Woodz_CodesRow") then
    return
  end

  local row = utils.new("Frame", {
    Name = "Woodz_CodesRow",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -20, 0, 36),
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.new(0, 10, 1, -46),
  }, container)

  utils.new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 10),
  }, row)

  local function mkBtn(text)
    return utils.new("TextButton", {
      BackgroundColor3 = constants.COLOR_BTN,
      TextColor3       = constants.COLOR_WHITE,
      Font             = Enum.Font.SourceSans,
      TextSize         = 14,
      Size             = UDim2.new(0, 200, 0, 32),
      AutoButtonColor  = true,
      Text             = text,
    }, row)
  end

  local previewBtn = mkBtn("Preview Unredeemed Codes")
  local redeemBtn  = mkBtn("Redeem Unredeemed Codes")

  utils.track(previewBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
      utils.notify("Codes", "Previewing unredeemed codes…", 2.5)
      local ok = codesLogic.run({ dryRun = true })
      if ok then
        utils.notify("Codes", "Preview complete — check console.", 3)
      else
        utils.notify("Codes", "Preview failed — check console.", 3)
      end
    end)
  end))

  utils.track(redeemBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
      utils.notify("Codes", "Redeeming unredeemed codes…", 2.5)
      local ok = codesLogic.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
      if ok then
        utils.notify("Codes", "Redeem run finished — see console.", 3)
      else
        utils.notify("Codes", "Redeem failed — see console.", 3)
      end
    end)
  end))

  -- If it's a ScrollingFrame, extend canvas so row is reachable
  if container:IsA("ScrollingFrame") then
    local current = container.CanvasSize
    container.CanvasSize = UDim2.new(0, 0, 0, (current.Y.Offset or 0) + 60)
  end

  utils.notify("Codes", "Options tab: added Preview/Redeem buttons.", 3)
end

function app.start()
  UI = uiModule.build()

  -- ---- Inject Codes buttons after UI exists ----
  task.defer(function()
    -- small defer so descendants exist
    task.wait(0.1)
    local container = findOptionsContainer(UI)
    if not container then
      -- try a bit longer in case the Options tab is created after
      local t0 = os.clock()
      while not container and (os.clock() - t0) < 5 do
        task.wait(0.25)
        container = findOptionsContainer(UI)
      end
    end
    injectCodesButtons(container)
  end)

  ------------------------------------------------------------------
  -- Build model list, search, presets
  ------------------------------------------------------------------
  farm.getMonsterModels()
  local function rebuildModelButtons()
    for _, ch in ipairs(UI.ModelScrollFrame:GetChildren()) do
      if ch:IsA('TextButton') then ch:Destroy() end
    end
    local models = farm.getFiltered()
    local count = 0
    for _, name in ipairs(models) do
      local btn = utils.new('TextButton', {
        Size = UDim2.new(1, -10, 0, 30),
        BackgroundColor3 = farm.isSelected(name) and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN,
        TextColor3 = constants.COLOR_WHITE,
        Text = name,
        TextSize = 14,
        Font = Enum.Font.SourceSans,
        LayoutOrder = count,
      }, UI.ModelScrollFrame)
      utils.track(btn.MouseButton1Click:Connect(function()
        farm.toggleSelect(name)
        btn.BackgroundColor3 = farm.isSelected(name) and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
      end))
      count += 1
    end
    UI.ModelScrollFrame.CanvasSize = UDim2.new(0,0,0,count * 30)
  end
  local function applySearchFilter(text)
    farm.filterMonsterModels(text or '')
    rebuildModelButtons()
  end
  applySearchFilter('')
  utils.track(UI.SearchTextBox:GetPropertyChangedSignal('Text'):Connect(function()
    applySearchFilter(UI.SearchTextBox.Text)
  end))
  utils.track(UI.SelectSahurButton.MouseButton1Click:Connect(function()
    local sel = farm.getSelected()
    if not table.find(sel, 'To Sahur') then
      sel = table.clone(sel); table.insert(sel, 'To Sahur'); farm.setSelected(sel); rebuildModelButtons()
      utils.notify('🌲 Preset', 'Selected all To Sahur models.', 3)
    end
  end))
  utils.track(UI.SelectWeatherButton.MouseButton1Click:Connect(function()
    local sel = farm.getSelected()
    if not table.find(sel, 'Weather Events') then
      sel = table.clone(sel); table.insert(sel, 'Weather Events'); farm.setSelected(sel); rebuildModelButtons()
      utils.notify('🌲 Preset', 'Selected all Weather Events models.', 3)
    end
  end))
  utils.track(UI.SelectAllButton.MouseButton1Click:Connect(function()
    farm.setSelected(table.clone(farm.getMonsterModels()))
    rebuildModelButtons()
    utils.notify('🌲 Preset', 'Selected all models.', 3)
  end))
  utils.track(UI.ClearAllButton.MouseButton1Click:Connect(function()
    farm.setSelected({})
    rebuildModelButtons()
    utils.notify('🌲 Preset', 'Cleared all selections.', 3)
  end))

  ------------------------------------------------------------------
  -- Auto-Farm (mutually exclusive with Smart Farm)
  ------------------------------------------------------------------
  utils.track(UI.AutoFarmToggle.MouseButton1Click:Connect(function()
    local newState = not autoFarmEnabled

    if newState and smartFarmEnabled then
      smartFarmEnabled = false
      setSmartFarmUI(false)
      notifyToggle('Smart Farm', false)
    end

    autoFarmEnabled = newState
    setAutoFarmUI(autoFarmEnabled)
    if autoFarmEnabled then
      farm.setupAutoAttackRemote()
      local sel = farm.getSelected()
      notifyToggle('Auto-Farm', true, sel and #sel>0 and (' for: '..table.concat(sel, ', ')) or '')
      task.spawn(function()
        farm.runAutoFarm(function() return autoFarmEnabled end, function(t) UI.CurrentTargetLabel.Text = t end)
      end)
    else
      UI.CurrentTargetLabel.Text = 'Current Target: None'
      notifyToggle('Auto-Farm', false)
    end
  end))

  ------------------------------------------------------------------
  -- Smart Farm (mutually exclusive with Auto-Farm)
  ------------------------------------------------------------------
  utils.track(UI.SmartFarmToggle.MouseButton1Click:Connect(function()
    local newState = not smartFarmEnabled

    if newState and autoFarmEnabled then
      autoFarmEnabled = false
      setAutoFarmUI(false)
      notifyToggle('Auto-Farm', false)
    end

    smartFarmEnabled = newState
    setSmartFarmUI(smartFarmEnabled)
    if smartFarmEnabled then
      -- ✅ Use robust resolver (supports ReplicatedStorage.GameInfo.MonsterInfo)
      local module = resolveMonsterInfo()
      notifyToggle('Smart Farm', true, module and (' — using '..module:GetFullName()) or ' (MonsterInfo not found; will stop)')
      if module then
        task.spawn(function()
          smartFarm.runSmartFarm(function() return smartFarmEnabled end, function(txt) UI.CurrentTargetLabel.Text = txt end, {
            module = module,
            safetyBuffer = 0.8,
            refreshInterval = 0.05,
          })
        end)
      else
        smartFarmEnabled = false
        setSmartFarmUI(false)
      end
    else
      UI.CurrentTargetLabel.Text = 'Current Target: None'
      notifyToggle('Smart Farm', false)
    end
  end))

  ------------------------------------------------------------------
  -- Anti-AFK
  ------------------------------------------------------------------
  utils.track(UI.ToggleAntiAFKButton.MouseButton1Click:Connect(function()
    antiAfkEnabled = not antiAfkEnabled
    if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
    UI.ToggleAntiAFKButton.Text = 'Anti-AFK: '..(antiAfkEnabled and 'ON' or 'OFF')
    UI.ToggleAntiAFKButton.BackgroundColor3 = antiAfkEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    notifyToggle('Anti-AFK', antiAfkEnabled)
  end))

  ------------------------------------------------------------------
  -- Merchants
  ------------------------------------------------------------------
  utils.track(UI.ToggleMerchant1Button.MouseButton1Click:Connect(function()
    autoBuyM1Enabled = not autoBuyM1Enabled
    UI.ToggleMerchant1Button.Text = 'Auto Buy Mythics (Chicleteiramania): '..(autoBuyM1Enabled and 'ON' or 'OFF')
    UI.ToggleMerchant1Button.BackgroundColor3 = autoBuyM1Enabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoBuyM1Enabled then
      notifyToggle('Merchant — Chicleteiramania', true)
      task.spawn(function()
        merchants.autoBuyLoop('SmelterMerchantService', function() return autoBuyM1Enabled end, function(sfx)
          UI.ToggleMerchant1Button.Text = 'Auto Buy Mythics (Chicleteiramania): ON '..sfx
        end)
      end)
    else
      notifyToggle('Merchant — Chicleteiramania', false)
    end
  end))

  utils.track(UI.ToggleMerchant2Button.MouseButton1Click:Connect(function()
    autoBuyM2Enabled = not autoBuyM2Enabled
    UI.ToggleMerchant2Button.Text = 'Auto Buy Mythics (Bombardino Sewer): '..(autoBuyM2Enabled and 'ON' or 'OFF')
    UI.ToggleMerchant2Button.BackgroundColor3 = autoBuyM2Enabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoBuyM2Enabled then
      notifyToggle('Merchant — Bombardino Sewer', true)
      task.spawn(function()
        merchants.autoBuyLoop('SmelterMerchantService2', function() return autoBuyM2Enabled end, function(sfx)
          UI.ToggleMerchant2Button.Text = 'Auto Buy Mythics (Bombardino Sewer): ON '..sfx
        end)
      end)
    else
      notifyToggle('Merchant — Bombardino Sewer', false)
    end
  end))

  ------------------------------------------------------------------
  -- Auto Crates
  ------------------------------------------------------------------
  utils.track(UI.ToggleAutoCratesButton.MouseButton1Click:Connect(function()
    autoOpenCratesEnabled = not autoOpenCratesEnabled
    UI.ToggleAutoCratesButton.Text = 'Auto Open Crates: '..(autoOpenCratesEnabled and 'ON' or 'OFF')
    UI.ToggleAutoCratesButton.BackgroundColor3 = autoOpenCratesEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoOpenCratesEnabled then
      crates.refreshCrateInventory(true)
      notifyToggle('Crates', true, (' (1 every '..tostring(constants.crateOpenDelay or 1)..'s)'))
      task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end) end)
    else
      notifyToggle('Crates', false)
    end
  end))

  ------------------------------------------------------------------
  -- Close button
  ------------------------------------------------------------------
  utils.track(UI.CloseButton.MouseButton1Click:Connect(function()
    autoFarmEnabled=false; smartFarmEnabled=false; autoBuyM1Enabled=false; autoBuyM2Enabled=false; autoOpenCratesEnabled=false
    if antiAfkEnabled then antiAFK.disable(); antiAfkEnabled=false end
    utils.notify('🌲 WoodzHUB', 'Closed. All loops stopped and UI removed.', 3.5)
    if UI.ScreenGui and UI.ScreenGui.Parent then UI.ScreenGui:Destroy() end
  end))
end

return app
