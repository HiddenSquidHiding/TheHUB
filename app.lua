-- app.lua (Rayfield-only)
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
-- Requires
----------------------------------------------------------------------
local constants   = require(script.Parent.constants)
local uiRF        = require(script.Parent.ui_rayfield)
local farm        = require(script.Parent.farm)
local merchants   = require(script.Parent.merchants)
local crates      = require(script.Parent.crates)
local antiAFK     = require(script.Parent.anti_afk)
local smartFarm   = require(script.Parent.smart_target)
local redeemCodes = require(script.Parent.redeem_unredeemed_codes)
local fastlevel   = require(script.Parent.fastlevel)

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

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function notifyToggle(name, on, extra)
	extra = extra or ""
	local msg = on and (name .. " enabled" .. extra) or (name .. " disabled")
	utils.notify("🌲 " .. name, msg, 3.5)
end

local function setAutoFarmUI(on)
	if RF and RF.setAutoFarm then RF.setAutoFarm(on) end
end

local function setSmartFarmUI(on)
	if RF and RF.setSmartFarm then RF.setSmartFarm(on) end
end

local function setCurrentTarget(text)
	text = text or "Current Target: None"
	if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(text) end) end
end

-- Resolve ReplicatedStorage MonsterInfo in several common locations
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
-- App start
----------------------------------------------------------------------
function app.start()
	-- Prime monster list once so presets have data
	farm.getMonsterModels()

	-- Build Rayfield and wire handlers
	RF = uiRF.build({
		-- Presets
		onSelectSahur = function()
			local sel = farm.getSelected()
			if not table.find(sel, "To Sahur") then
				sel = table.clone(sel); table.insert(sel, "To Sahur"); farm.setSelected(sel)
			end
			utils.notify("🌲 Preset", "Selected all To Sahur models.", 3)
		end,
		onSelectWeather = function()
			local sel = farm.getSelected()
			if not table.find(sel, "Weather Events") then
				sel = table.clone(sel); table.insert(sel, "Weather Events"); farm.setSelected(sel)
			end
			utils.notify("🌲 Preset", "Selected all Weather Events models.", 3)
		end,
		onSelectAll = function()
			farm.setSelected(table.clone(farm.getMonsterModels()))
			utils.notify("🌲 Preset", "Selected all models.", 3)
		end,
		onClearAll = function()
			farm.setSelected({})
			utils.notify("🌲 Preset", "Cleared all selections.", 3)
		end,

		-- Auto-Farm (mutually exclusive with Smart Farm)
		onAutoFarmToggle = function(v)
			local newState = (v ~= nil) and v or (not autoFarmEnabled)
			if newState and smartFarmEnabled then
				smartFarmEnabled = false
				setSmartFarmUI(false)
				notifyToggle("Smart Farm", false)
			end

			autoFarmEnabled = newState
			setAutoFarmUI(autoFarmEnabled)

			if autoFarmEnabled then
				farm.setupAutoAttackRemote()
				local sel = farm.getSelected()
				local extra = (sel and #sel > 0) and (" for: " .. table.concat(sel, ", ")) or ""
				notifyToggle("Auto-Farm", true, extra)

				task.spawn(function()
					farm.runAutoFarm(
						function() return autoFarmEnabled end,
						setCurrentTarget
					)
				end)
			else
				setCurrentTarget("Current Target: None")
				notifyToggle("Auto-Farm", false)
			end
		end,

		-- Smart Farm (mutually exclusive with Auto-Farm)
		onSmartFarmToggle = function(v)
			local newState = (v ~= nil) and v or (not smartFarmEnabled)

			if newState and autoFarmEnabled then
				autoFarmEnabled = false
				setAutoFarmUI(false)
				notifyToggle("Auto-Farm", false)
			end

			smartFarmEnabled = newState
			setSmartFarmUI(smartFarmEnabled)

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
					setSmartFarmUI(false)
				end
			else
				setCurrentTarget("Current Target: None")
				notifyToggle("Smart Farm", false)
			end
		end,

		-- Anti-AFK
		onToggleAntiAFK = function(v)
			antiAfkEnabled = (v ~= nil) and v or (not antiAfkEnabled)
			if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
			notifyToggle("Anti-AFK", antiAfkEnabled)
			if RF and RF.setAntiAFK then RF.setAntiAFK(antiAfkEnabled) end
		end,

		-- Merchants
		onToggleMerchant1 = function(v)
			autoBuyM1Enabled = (v ~= nil) and v or (not autoBuyM1Enabled)
			if autoBuyM1Enabled then
				notifyToggle("Merchant — Chicleteiramania", true)
				task.spawn(function()
					merchants.autoBuyLoop(
						"SmelterMerchantService",
						function() return autoBuyM1Enabled end,
						function(_) end -- Rayfield label is static; we don't rewrite its text
					)
				end)
			else
				notifyToggle("Merchant — Chicleteiramania", false)
			end
			if RF and RF.setMerchant1 then RF.setMerchant1(autoBuyM1Enabled) end
		end,

		onToggleMerchant2 = function(v)
			autoBuyM2Enabled = (v ~= nil) and v or (not autoBuyM2Enabled)
			if autoBuyM2Enabled then
				notifyToggle("Merchant — Bombardino Sewer", true)
				task.spawn(function()
					merchants.autoBuyLoop(
						"SmelterMerchantService2",
						function() return autoBuyM2Enabled end,
						function(_) end
					)
				end)
			else
				notifyToggle("Merchant — Bombardino Sewer", false)
			end
			if RF and RF.setMerchant2 then RF.setMerchant2(autoBuyM2Enabled) end
		end,

		-- Crates
		onToggleCrates = function(v)
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
			if RF and RF.setCrates then RF.setCrates(autoOpenCratesEnabled) end
		end,

		-- Codes
		onRedeemCodes = function()
			task.spawn(function()
				local ok, err = pcall(function()
					redeemCodes.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
				end)
				if not ok then utils.notify("Codes", "Redeem failed: " .. tostring(err), 4) end
			end)
		end,

		-- Instant Level 70+
		onFastLevelToggle = function(v)
			local newState = (v ~= nil) and v or (not fastlevel.isEnabled())
			if newState then
				if smartFarmEnabled then
					smartFarmEnabled = false; setSmartFarmUI(false); notifyToggle("Smart Farm", false)
				end
				fastlevel.enable()
				notifyToggle("Instant Level 70+", true, " — targeting Sahur only")
				if not autoFarmEnabled then
					autoFarmEnabled = true; setAutoFarmUI(true)
					farm.setupAutoAttackRemote()
					task.spawn(function()
						farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
					end)
					notifyToggle("Auto-Farm", true)
				end
			else
				fastlevel.disable()
				notifyToggle("Instant Level 70+", false)
			end
			if RF and RF.setFastLevel then RF.setFastLevel(newState) end
		end,
	})

	utils.notify("🌲 WoodzHUB", "Rayfield UI only mode active.", 4)
end

return app
