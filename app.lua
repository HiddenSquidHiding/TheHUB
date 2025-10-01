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
local ui         = require(script.Parent.ui)
local farm       = require(script.Parent.farm)
local merchants  = require(script.Parent.merchants)
local crates     = require(script.Parent.crates)
local antiAFK    = require(script.Parent.anti_afk)

local app = {}

-- State flags
local autoFarmEnabled       = false
local autoBuyM1Enabled      = false
local autoBuyM2Enabled      = false
local autoOpenCratesEnabled = false
local antiAfkEnabled        = false

-- Notify helper
local function notifyToggle(name, on, extra)
  extra = extra or ''
  local msg = on and (name .. ' enabled' .. extra) or (name .. ' disabled')
  utils.notify('🌲 ' .. name, msg, 3.5)
end

-- Quick guard so we fail loudly if a control is missing
local function need(ctrl, name)
  if not ctrl then
    utils.notify('🌲 WoodzHUB Error', ("Missing UI control: %s (check ui.build)"):format(name), 6)
    error(("[app.lua] Missing UI control: %s"):format(name))
  end
  return ctrl
end

function app.start()
  ------------------------------------------------------------------
  -- 1) Build UI first, then wire handlers
  ------------------------------------------------------------------
  local UI = ui.build()
  -- Validate we have the controls we expect
  need(UI.ScreenGui,            "ScreenGui")
  need(UI.AutoFarmToggle,       "AutoFarmToggle")
  need(UI.CurrentTargetLabel,   "CurrentTargetLabel")
  need(UI.ToggleAntiAFKButton,  "ToggleAntiAFKButton")
  need(UI.ToggleMerchant1Button,"ToggleMerchant1Button")
  need(UI.ToggleMerchant2Button,"ToggleMerchant2Button")
  need(UI.ToggleAutoCratesButton,"ToggleAutoCratesButton")
  need(UI.CloseButton,          "CloseButton")

  ------------------------------------------------------------------
  -- Auto-Farm
  ------------------------------------------------------------------
  utils.track(UI.AutoFarmToggle.MouseButton1Click:Connect(function()
    autoFarmEnabled = not autoFarmEnabled
    UI.AutoFarmToggle.Text = 'Auto-Farm: '..(autoFarmEnabled and 'ON' or 'OFF')
    UI.AutoFarmToggle.BackgroundColor3 = autoFarmEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoFarmEnabled then
      farm.setupAutoAttackRemote()
      local sel = (farm.getSelected and farm.getSelected()) or nil
      notifyToggle('Auto-Farm', true, (sel and #sel>0) and (' for: '..table.concat(sel, ', ')) or '')
      task.spawn(function()
        if farm.runAutoFarm then
          farm.runAutoFarm(function() return autoFarmEnabled end, function(t) UI.CurrentTargetLabel.Text = t end)
        else
          -- Legacy API support
          if farm.setTargetLabel then farm.setTargetLabel(UI.CurrentTargetLabel) end
          farm.toggleFarm(true, game.Players.LocalPlayer, sel or {}, (require(script.Parent.data_monsters).weatherEventModels or {}), (require(script.Parent.data_monsters).toSahurModels or {}))
        end
      end)
    else
      UI.CurrentTargetLabel.Text = 'Current Target: None'
      notifyToggle('Auto-Farm', false)
      -- If using legacy API
      if farm.toggleFarm then
        local sel = (farm.getSelected and farm.getSelected()) or {}
        farm.toggleFarm(false, game.Players.LocalPlayer, sel, (require(script.Parent.data_monsters).weatherEventModels or {}), (require(script.Parent.data_monsters).toSahurModels or {}))
      end
    end
  end))

  ------------------------------------------------------------------
  -- Anti-AFK
  ------------------------------------------------------------------
  utils.track(UI.ToggleAntiAFKButton.MouseButton1Click:Connect(function()
    antiAfkEnabled = not antiAfkEnabled
    if antiAfkEnabled then
      if antiAFK.enable then antiAFK.enable() end
    else
      if antiAFK.disable then antiAFK.disable() end
    end
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
          UI.ToggleMerchant1Button.Text = 'Auto Buy Mythics (Chicleteiramania): ON '..(sfx or '')
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
          UI.ToggleMerchant2Button.Text = 'Auto Buy Mythics (Bombardino Sewer): ON '..(sfx or '')
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
      local delay = tostring(constants.crateOpenDelay or 1)
      notifyToggle('Crates', true, (' (1 every '..delay..'s)'))
      task.spawn(function()
        crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end)
      end)
    else
      notifyToggle('Crates', false)
    end
  end))

  ------------------------------------------------------------------
  -- Close button
  ------------------------------------------------------------------
  utils.track(UI.CloseButton.MouseButton1Click:Connect(function()
    autoFarmEnabled=false
    autoBuyM1Enabled=false
    autoBuyM2Enabled=false
    autoOpenCratesEnabled=false
    if antiAfkEnabled then if antiAFK.disable then antiAFK.disable() end; antiAfkEnabled=false end
    utils.notify('🌲 WoodzHUB', 'Closed. All loops stopped and UI removed.', 3.5)
    UI.ScreenGui:Destroy()
  end))
end

return app
