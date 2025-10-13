local function getUtils()
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return {
    notify = function(_,_) end
  }
end
local utils = getUtils()

-- SAFE sibling getter: never calls require(nil)
local function tryRequire(name)
  local parent = script and script.Parent
  if not parent then return nil, "no parent" end
  local instOrTable = rawget(parent, name)  -- because parent is a table (siblings) in our HTTP loader
  if instOrTable == nil then
    -- also try actual Instance child (when running from Studio/assets instead of HTTP loader)
    if typeof(parent) == "Instance" then
      instOrTable = parent:FindFirstChild(name)
      if not instOrTable then return nil, "missing" end
    else
      return nil, "missing"
    end
  end
  local ok, mod = pcall(function() return require(instOrTable) end)
  if not ok then return nil, mod end
  return mod, nil
end

-- Optional modules (any may be missing)
local uiRF        = select(1, tryRequire("ui_rayfield"))
local farm        = select(1, tryRequire("farm"))
local merchants   = select(1, tryRequire("merchants"))
local crates      = select(1, tryRequire("crates"))
local antiAFK     = select(1, tryRequire("anti_afk"))
local smartFarm   = select(1, tryRequire("smart_target"))
local redeemCodes = select(1, tryRequire("redeem_unredeemed_codes"))
local fastlevel   = select(1, tryRequire("fastlevel"))

-- Soft warnings (non-fatal)
local function soft(name)
  if _G.__WOODZ_WARNED then return end
end

local function warnMissing(label, mod)
  if not mod then
    print(("-- [app.lua] optional module '%s' not available"):format(label))
  end
end

warnMissing('ui_rayfield', uiRF)
warnMissing('farm', farm)
warnMissing('merchants', merchants)
warnMissing('crates', crates)
warnMissing('anti_afk', antiAFK)
warnMissing('smart_target', smartFarm)
warnMissing('redeem_unredeemed_codes', redeemCodes)
warnMissing('fastlevel', fastlevel)

local app = {}

function app.start()
  if not uiRF then
    utils.notify("🌲 WoodzHUB", "ui_rayfield.lua missing — UI not loaded. Core still running.", 6)
    return
  end

  local autoFarmEnabled        = false
  local smartFarmEnabled       = false
  local autoBuyM1Enabled       = false
  local autoBuyM2Enabled       = false
  local autoOpenCratesEnabled  = false
  local antiAfkEnabled         = false

  local RF = uiRF.build({
    onAutoFarmToggle = function(v)
      if not farm then utils.notify("🌲 Auto-Farm", "farm.lua missing.", 4); return end
      autoFarmEnabled = v and true or false
      if autoFarmEnabled then
        if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
        task.spawn(function()
          farm.runAutoFarm(function() return autoFarmEnabled end,
            function(txt) if RF and RF.setCurrentTarget then RF.setCurrentTarget(txt) end end)
        end)
        utils.notify("🌲 Auto-Farm", "enabled", 3)
      else
        if RF and RF.setCurrentTarget then RF.setCurrentTarget("Current Target: None") end
        utils.notify("🌲 Auto-Farm", "disabled", 3)
      end
    end,

    onSmartFarmToggle = function(v)
      if not smartFarm then utils.notify("🌲 Smart Farm", "smart_target.lua missing.", 4); return end
      smartFarmEnabled = v and true or false
      if smartFarmEnabled then
        task.spawn(function()
          smartFarm.runSmartFarm(function() return smartFarmEnabled end,
            function(txt) if RF and RF.setCurrentTarget then RF.setCurrentTarget(txt) end end,
            { refreshInterval = 0.05 })
        end)
        utils.notify("🌲 Smart Farm", "enabled", 3)
      else
        if RF and RF.setCurrentTarget then RF.setCurrentTarget("Current Target: None") end
        utils.notify("🌲 Smart Farm", "disabled", 3)
      end
    end,

    onToggleAntiAFK = function(v)
      if not antiAFK then utils.notify("🌲 Anti-AFK", "anti_afk.lua missing.", 4); return end
      antiAfkEnabled = v and true or false
      if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
      utils.notify("🌲 Anti-AFK", antiAfkEnabled and "enabled" or "disabled", 3)
    end,

    onToggleMerchant1 = function(v)
      if not merchants then utils.notify("🌲 Merchant", "merchants.lua missing.", 4); return end
      autoBuyM1Enabled = v and true or false
      if autoBuyM1Enabled then
        task.spawn(function() merchants.autoBuyLoop("SmelterMerchantService", function() return autoBuyM1Enabled end, function() end) end)
      end
    end,

    onToggleMerchant2 = function(v)
      if not merchants then utils.notify("🌲 Merchant", "merchants.lua missing.", 4); return end
      autoBuyM2Enabled = v and true or false
      if autoBuyM2Enabled then
        task.spawn(function() merchants.autoBuyLoop("SmelterMerchantService2", function() return autoBuyM2Enabled end, function() end) end)
      end
    end,

    onToggleCrates = function(v)
      if not crates then utils.notify("🎁 Crates", "crates.lua missing.", 4); return end
      autoOpenCratesEnabled = v and true or false
      if autoOpenCratesEnabled then
        if crates.refreshCrateInventory then crates.refreshCrateInventory(true) end
        task.spawn(function() crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end) end)
      end
    end,

    onRedeemCodes = function()
      if not redeemCodes then utils.notify("Codes", "redeem_unredeemed_codes.lua missing.", 4); return end
      task.spawn(function() pcall(function() redeemCodes.run({ dryRun=false, concurrent=true, delayBetween=0.25 }) end) end)
    end,

    onFastLevelToggle = function(v)
      if not fastlevel then utils.notify("🌲 Instant Level 70+", "fastlevel.lua missing.", 4); return end
      if v then fastlevel.enable() else fastlevel.disable() end
      utils.notify("🌲 Instant Level 70+", v and "enabled" or "disabled", 3)
    end,
  })

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
end

return app
