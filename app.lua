-- app.lua (Rayfield-only, profile-aware)
-- Wires features to the Rayfield overlay UI.

----------------------------------------------------------------------
-- Safe utils
----------------------------------------------------------------------
local function getUtils()
	local parent = script and script.Parent
	if parent and parent._deps and parent._deps.utils then
		return parent._deps.utils
	end
	if rawget(getfenv(), "__WOODZ_UTILS") then
		return __WOODZ_UTILS
	end
	error("[app.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading app.lua")
end

local utils             = getUtils()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

----------------------------------------------------------------------
-- Requires (some may be nil if profile didn't load them)
----------------------------------------------------------------------
local constants   = require(script.Parent.constants)
local uiRF        = require(script.Parent.ui)          -- ui_rayfield.lua loaded as 'ui'
local farm        = script.Parent:FindFirstChild("farm")         and require(script.Parent.farm)         or nil
local merchants   = script.Parent:FindFirstChild("merchants")    and require(script.Parent.merchants)    or nil
local crates      = script.Parent:FindFirstChild("crates")       and require(script.Parent.crates)       or nil
local antiAFK     = script.Parent:FindFirstChild("anti_afk")     and require(script.Parent.anti_afk)     or nil
local smartFarm   = script.Parent:FindFirstChild("smart_target") and require(script.Parent.smart_target) or nil
local redeemCodes = script.Parent:FindFirstChild("redeem_unredeemed_codes") and require(script.Parent.redeem_unredeemed_codes) or nil
local fastlevel   = script.Parent:FindFirstChild("fastlevel")    and require(script.Parent.fastlevel)    or nil

----------------------------------------------------------------------
-- Module
----------------------------------------------------------------------
local app = {}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local autoFarmEnabled        = false
local smartFarmEnabled       = false
local autoBuyM1Enabled       = false
local autoBuyM2Enabled       = false
local autoOpenCratesEnabled  = false
local antiAfkEnabled         = false

-- Rayfield handle (set in start)
local RF = nil

-- Prevent Rayfield -> app -> Rayfield callback feedback
local suppressRF = false
local function rfSet(setterFn)
  if RF and setterFn then
    suppressRF = true
    pcall(setterFn)
    suppressRF = false
  end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function notifyToggle(name, on, extra)
	extra = extra or ""
	local msg = on and (name .. " enabled" .. extra) or (name .. " disabled")
	utils.notify("🌲 " .. name, msg, 3.5)
end

local function setCurrentTarget(text)
  text = text or "Current Target: None"
  if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(text) end) end
end

-- Resolve ReplicatedStorage MonsterInfo
local function resolveMonsterInfo()
	local RS = ReplicatedStorage
	local candidatePaths = {
		{ "GameInfo", "MonsterInfo" },
		{ "MonsterInfo" },
		{ "Shared", "MonsterInfo" },
		{ "Modules", "MonsterInfo" },
		{ "Configs", "MonsterInfo" },
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

----------------------------------------------------------------------
-- App start (profile-aware)
----------------------------------------------------------------------
function app.start(profile)
  profile = profile or { ui = {} }
  local uiFlags = profile.ui or {}

  -- Prime monster list if relevant
  if farm and uiFlags.modelPicker and farm.getMonsterModels then
    pcall(farm.getMonsterModels)
  end

  -- Build Rayfield and wire handlers (conditionally available)
  RF = uiRF.build({
    uiFlags = uiFlags,

    -- Targets helpers
    onClearAll = function()
      if not farm then return end
      farm.setSelected({})
      utils.notify("🌲 Preset", "Cleared all selections.", 3)
    end,

    -- Auto-Farm
    onAutoFarmToggle = function(v)
      if suppressRF or not farm or not uiFlags.autoFarm then return end
      local newState = (v ~= nil) and v or (not autoFarmEnabled)

      if newState and smartFarmEnabled then
        smartFarmEnabled = false
        rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
        notifyToggle("Smart Farm", false)
      end

      autoFarmEnabled = newState

      if autoFarmEnabled then
        farm.setFastLevelEnabled(fastlevel and fastlevel.isEnabled and fastlevel.isEnabled() or false)
        farm.setupAutoAttackRemote()
        local sel = farm.getSelected and farm.getSelected() or {}
        local extra = (#sel > 0) and (" for: " .. table.concat(sel, ", ")) or ""
        notifyToggle("Auto-Farm", true, extra)
        task.spawn(function()
          farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
        end)
      else
        setCurrentTarget("Current Target: None")
        notifyToggle("Auto-Farm", false)
      end
    end,

    -- Smart Farm
    onSmartFarmToggle = function(v)
      if suppressRF or not smartFarm or not uiFlags.smartFarm then return end
      local newState = (v ~= nil) and v or (not smartFarmEnabled)

      if newState and autoFarmEnabled then
        autoFarmEnabled = false
        rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(false) end end)
        notifyToggle("Auto-Farm", false)
      end

      smartFarmEnabled = newState

      if smartFarmEnabled then
        local module = resolveMonsterInfo()
        notifyToggle("Smart Farm", true, module and (" — using " .. module:GetFullName()) or " (MonsterInfo not found; will stop)")
        if module then
          task.spawn(function()
            smartFarm.runSmartFarm(
              function() return smartFarmEnabled end,
              setCurrentTarget,
              { module = module, safetyBuffer = 0.8, refreshInterval = 0.05 }
            )
          end)
        else
          smartFarmEnabled = false
          rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
        end
      else
        setCurrentTarget("Current Target: None")
        notifyToggle("Smart Farm", false)
      end
    end,

    -- Anti-AFK
    onToggleAntiAFK = function(v)
      if suppressRF or not antiAFK or not uiFlags.antiAFK then return end
      antiAfkEnabled = (v ~= nil) and v or (not antiAfkEnabled)
      if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
      notifyToggle("Anti-AFK", antiAfkEnabled)
    end,

    -- Merchants
    onToggleMerchant1 = function(v)
      if suppressRF or not merchants or not uiFlags.merchants then return end
      autoBuyM1Enabled = (v ~= nil) and v or (not autoBuyM1Enabled)
      if autoBuyM1Enabled then
        notifyToggle("Merchant — Chicleteiramania", true)
        task.spawn(function()
          merchants.autoBuyLoop("SmelterMerchantService", function() return autoBuyM1Enabled end, function(_) end)
        end)
      else
        notifyToggle("Merchant — Chicleteiramania", false)
      end
    end,
    onToggleMerchant2 = function(v)
      if suppressRF or not merchants or not uiFlags.merchants then return end
      autoBuyM2Enabled = (v ~= nil) and v or (not autoBuyM2Enabled)
      if autoBuyM2Enabled then
        notifyToggle("Merchant — Bombardino Sewer", true)
        task.spawn(function()
          merchants.autoBuyLoop("SmelterMerchantService2", function() return autoBuyM2Enabled end, function(_) end)
        end)
      else
        notifyToggle("Merchant — Bombardino Sewer", false)
      end
    end,

    -- Crates
    onToggleCrates = function(v)
      if suppressRF or not crates or not uiFlags.crates then return end
      autoOpenCratesEnabled = (v ~= nil) and v or (not autoOpenCratesEnabled)
      if autoOpenCratesEnabled then
        crates.refreshCrateInventory(true)
        local delayText = tostring(constants.crateOpenDelay or 1)
        notifyToggle("Crates", true, " (1 every " .. delayText .. "s)")
        task.spawn(function()
          crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end)
        end)
      else
        notifyToggle("Crates", false)
      end
    end,

    -- Codes
    onRedeemCodes = function()
      if not redeemCodes or not uiFlags.redeemCodes then return end
      task.spawn(function()
        local ok, err = pcall(function()
          redeemCodes.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
        end)
        if not ok then utils.notify("Codes", "Redeem failed: " .. tostring(err), 4) end
      end)
    end,

    -- Private server button (expects _G.TeleportToPrivateServer to be defined by your solo.lua)
    onPrivateServer = function()
      if not uiFlags.privateServer then return end
      task.spawn(function()
        if not _G.TeleportToPrivateServer then
          utils.notify("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
          return
        end
        local ok, err = pcall(_G.TeleportToPrivateServer)
        if ok then utils.notify("🌲 Private Server", "Teleport initiated to private server!", 3)
        else utils.notify("🌲 Private Server", "Failed to teleport: " .. tostring(err), 5) end
      end)
    end,

    -- Fast Level (owns Auto-Farm on OFF)
    onFastLevelToggle = function(v)
      if suppressRF or not fastlevel or not farm or not uiFlags.fastlevel then return end
      local isOn = fastlevel.isEnabled and fastlevel.isEnabled() or false
      local newState = (v ~= nil) and v or (not isOn)

      if newState then
        if smartFarmEnabled then
          smartFarmEnabled = false
          rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
          notifyToggle("Smart Farm", false)
        end

        fastlevel.enable()
        farm.setFastLevelEnabled(true)
        notifyToggle("Instant Level 70+", true, " — targeting Sahur only")

        if not autoFarmEnabled then
          autoFarmEnabled = true
          rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(true) end end)
          farm.setupAutoAttackRemote()
          task.spawn(function()
            farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
          end)
          notifyToggle("Auto-Farm", true)
        else
          -- restart to ensure loop picks up flag
          autoFarmEnabled = false
          task.wait(0.05)
          autoFarmEnabled = true
          rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(true) end end)
          farm.setupAutoAttackRemote()
          task.spawn(function()
            farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
          end)
        end
      else
        fastlevel.disable()
        farm.setFastLevelEnabled(false)
        notifyToggle("Instant Level 70+", false)

        -- also turn OFF Auto-Farm when Fast Level goes off
        if autoFarmEnabled then
          autoFarmEnabled = false
          rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(false) end end)
          setCurrentTarget("Current Target: None")
          notifyToggle("Auto-Farm", false)
        end
      end
    end,
  })

  utils.notify("🌲 WoodzHUB", ("Profile: %s"):format(profile.name or "default"), 3)
end

return app
