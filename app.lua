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
local autoFarmEnabled=false
local autoBuyM1Enabled=false
local autoBuyM2Enabled=false
local autoOpenCratesEnabled=false
local antiAfkEnabled=false

-- Notify helper
local function notifyToggle(name, on, extra)
  extra = extra or ''
  local msg = on and (name .. ' enabled' .. extra) or (name .. ' disabled')
  utils.notify('🌲 ' .. name, msg, 3.5)
end

function app.start()
  ------------------------------------------------------------------
  -- Auto-Farm
  ------------------------------------------------------------------
  utils.track(ui.AutoFarmToggle.MouseButton1Click:Connect(function()
    autoFarmEnabled = not autoFarmEnabled
    ui.AutoFarmToggle.Text = 'Auto-Farm: '..(autoFarmEnabled and 'ON' or 'OFF')
    ui.AutoFarmToggle.BackgroundColor3 = autoFarmEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoFarmEnabled then
      farm.setupAutoAttackRemote()
      local sel = farm.getSelected()
      notifyToggle('Auto-Farm', true, sel and #sel>0 and (' for: '..table.concat(sel, ', ')) or '')
      task.spawn(function()
        farm.runAutoFarm(function() return autoFarmEnabled end, function(t) ui.CurrentTargetLabel.Text = t end)
      end)
    else
      ui.CurrentTargetLabel.Text = 'Current Target: None'
      notifyToggle('Auto-Farm', false)
    end
  end))

  ------------------------------------------------------------------
  -- Anti-AFK
  ------------------------------------------------------------------
  utils.track(ui.ToggleAntiAFKButton.MouseButton1Click:Connect(function()
    antiAfkEnabled = not antiAfkEnabled
    if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
    ui.ToggleAntiAFKButton.Text = 'Anti-AFK: '..(antiAfkEnabled and 'ON' or 'OFF')
    ui.ToggleAntiAFKButton.BackgroundColor3 = antiAfkEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    notifyToggle('Anti-AFK', antiAfkEnabled)
  end))

  ------------------------------------------------------------------
  -- Merchants
  ------------------------------------------------------------------
  utils.track(ui.ToggleMerchant1Button.MouseButton1Click:Connect(function()
    autoBuyM1Enabled = not autoBuyM1Enabled
    ui.ToggleMerchant1Button.Text = 'Auto Buy Mythics (Chicleteiramania): '..(autoBuyM1Enabled and 'ON' or 'OFF')
    ui.ToggleMerchant1Button.BackgroundColor3 = autoBuyM1Enabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoBuyM1Enabled then
      notifyToggle('Merchant — Chicleteiramania', true)
      task.spawn(function()
        merchants.autoBuyLoop('SmelterMerchantService', function() return autoBuyM1Enabled end, function(sfx)
          ui.ToggleMerchant1Button.Text = 'Auto Buy Mythics (Chicleteiramania): ON '..sfx
        end)
      end)
    else
      notifyToggle('Merchant — Chicleteiramania', false)
    end
  end))

  utils.track(ui.ToggleMerchant2Button.MouseButton1Click:Connect(function()
    autoBuyM2Enabled = not autoBuyM2Enabled
    ui.ToggleMerchant2Button.Text = 'Auto Buy Mythics (Bombardino Sewer): '..(autoBuyM2Enabled and 'ON' or 'OFF')
    ui.ToggleMerchant2Button.BackgroundColor3 = autoBuyM2Enabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
    if autoBuyM2Enabled then
      notifyToggle('Merchant — Bombardino Sewer', true)
      task.spawn(function()
        merchants.autoBuyLoop('SmelterMerchantService2', function() return autoBuyM2Enabled end, function(sfx)
          ui.ToggleMerchant2Button.Text = 'Auto Buy Mythics (Bombardino Sewer): ON '..sfx
        end)
      end)
    else
      notifyToggle('Merchant — Bombardino Sewer', false)
    end
  end))

  ------------------------------------------------------------------
  -- Auto Crates
  ------------------------------------------------------------------
  utils.track(ui.ToggleAutoCratesButton.MouseButton1Click:Connect(function()
    autoOpenCratesEnabled = not autoOpenCratesEnabled
    ui.ToggleAutoCratesButton.Text = 'Auto Open Crates: '..(autoOpenCratesEnabled and 'ON' or 'OFF')
    ui.ToggleAutoCratesButton.BackgroundColor3 = autoOpenCratesEnabled and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
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
  utils.track(ui.CloseButton.MouseButton1Click:Connect(function()
    autoFarmEnabled=false; autoBuyM1Enabled=false; autoBuyM2Enabled=false; autoOpenCratesEnabled=false
    if antiAfkEnabled then antiAFK.disable(); antiAfkEnabled=false end
    utils.notify('🌲 WoodzHUB', 'Closed. All loops stopped and UI removed.', 3.5)
    ui.ScreenGui:Destroy()
  end))
end

return app
