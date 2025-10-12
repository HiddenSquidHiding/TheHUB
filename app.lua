-- app.lua (Rayfield-only, safe requires)
-- Returns a table with start(); nothing runs at top-level.

----------------------------------------------------------------------
-- Safe utils
----------------------------------------------------------------------
local function getUtils()
	local parent = script and script.Parent
	if parent and parent._deps and parent._deps.utils then return parent._deps.utils end
	if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
	error("[app.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading app.lua")
end
local utils = getUtils()

----------------------------------------------------------------------
-- Soft require helper: returns module or nil (never throws)
----------------------------------------------------------------------
local function softRequire(name)
	local ok, mod = pcall(function() return require(script.Parent[name]) end)
	if not ok then
		warn(("[app.lua] optional module '%s' not available: %s"):format(name, tostring(mod)))
		return nil
	end
	return mod
end

----------------------------------------------------------------------
-- Optional modules (guarded)
----------------------------------------------------------------------
local constants   = softRequire("constants")            or {}
local uiRF        = softRequire("ui_rayfield")          -- Rayfield UI wrapper (required for full UI; else we’ll just notify)
local farm        = softRequire("farm")
local merchants   = softRequire("merchants")
local crates      = softRequire("crates")
local antiAFK     = softRequire("anti_afk")
local smartFarm   = softRequire("smart_target")
local redeemCodes = softRequire("redeem_unredeemed_codes")
local fastlevel   = softRequire("fastlevel")

----------------------------------------------------------------------
-- Module (must return this with start())
----------------------------------------------------------------------
local app = {}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local autoFarmEnabled       = false
local smartFarmEnabled      = false
local autoBuyM1Enabled      = false
local autoBuyM2Enabled      = false
local autoOpenCratesEnabled = false
local antiAfkEnabled        = false

-- Rayfield handle (set in start)
local RF = nil
local suppressRF = false
local function rfSet(setterFn)
	if RF and setterFn then
		suppressRF = true
		pcall(setterFn)
		suppressRF = false
	end
end

-- Throttled label setter for UI
local lastLabelText, lastLabelAt = nil, 0
local function setCurrentTarget(text)
	text = text or "Current Target: None"
	local now = tick()
	if text == lastLabelText and (now - lastLabelAt) < 0.15 then return end
	lastLabelText, lastLabelAt = text, now
	if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(text) end) end
end

local function notifyToggle(name, on, extra)
	extra = extra or ""
	local msg = on and (name .. " enabled" .. extra) or (name .. " disabled")
	utils.notify("🌲 " .. name, msg, 3.5)
end

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
function app.start()
	-- If the Rayfield UI wrapper is missing, don’t crash — just notify.
	if not uiRF then
		utils.notify("🌲 WoodzHUB", "ui_rayfield.lua missing — UI not loaded. Core still running.", 5)
	end

	-- Build Rayfield (if present) and wire handlers
	if uiRF and uiRF.build then
		RF = uiRF.build({
			-- Clear All under model picker
			onClearAll = function()
				if farm and farm.setSelected then
					farm.setSelected({})
					utils.notify("🌲 Preset", "Cleared all selections.", 3)
				end
			end,

			-- Auto-Farm (mutually exclusive with Smart Farm)
			onAutoFarmToggle = function(v)
				if suppressRF then return end
				if not farm then utils.notify("🌲 Auto-Farm", "farm.lua missing.", 3) return end
				local newState = (v ~= nil) and v or (not autoFarmEnabled)

				if newState and smartFarmEnabled then
					smartFarmEnabled = false
					rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
					notifyToggle("Smart Farm", false)
				end

				autoFarmEnabled = newState

				if autoFarmEnabled then
					if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
					local sel = (farm.getSelected and farm.getSelected()) or {}
					local extra = (#sel > 0) and (" for: " .. table.concat(sel, ", ")) or ""
					notifyToggle("Auto-Farm", true, extra)
					task.spawn(function()
						if farm.runAutoFarm then
							farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
						else
							utils.notify("🌲 Auto-Farm", "runAutoFarm missing in farm.lua", 4)
						end
					end)
				else
					setCurrentTarget("Current Target: None")
					notifyToggle("Auto-Farm", false)
				end
			end,

			-- Smart Farm (mutually exclusive with Auto-Farm)
			onSmartFarmToggle = function(v)
				if suppressRF then return end
				if not smartFarm then utils.notify("🌲 Smart Farm", "smart_target.lua missing.", 3) return end
				local newState = (v ~= nil) and v or (not smartFarmEnabled)

				if newState and autoFarmEnabled then
					autoFarmEnabled = false
					rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(false) end end)
					notifyToggle("Auto-Farm", false)
				end

				smartFarmEnabled = newState

				if smartFarmEnabled then
					local ReplicatedStorage = game:GetService("ReplicatedStorage")
					local function resolveMonsterInfo()
						local RS = ReplicatedStorage
						local paths = {
							{"GameInfo","MonsterInfo"},{"MonsterInfo"},{"Shared","MonsterInfo"},
							{"Modules","MonsterInfo"},{"Configs","MonsterInfo"},
						}
						for _, pth in ipairs(paths) do
							local node = RS
							local ok = true
							for _, nm in ipairs(pth) do
								node = node:FindFirstChild(nm) or node:WaitForChild(nm, 1)
								if not node then ok=false; break end
							end
							if ok and node and node:IsA("ModuleScript") then return node end
						end
						for _, d in ipairs(RS:GetDescendants()) do
							if d:IsA("ModuleScript") and d.Name=="MonsterInfo" then return d end
						end
						return nil
					end
					local module = resolveMonsterInfo()
					notifyToggle("Smart Farm", true, module and (" — using " .. module:GetFullName()) or " (MonsterInfo not found; will stop)")
					if module and smartFarm.runSmartFarm then
						task.spawn(function()
							smartFarm.runSmartFarm(
								function() return smartFarmEnabled end,
								setCurrentTarget,
								{ module=module, safetyBuffer=0.8, refreshInterval=0.05 }
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
				if suppressRF then return end
				if not antiAFK then utils.notify("🌲 Anti-AFK", "anti_afk.lua missing.", 3) return end
				antiAfkEnabled = (v ~= nil) and v or (not antiAfkEnabled)
				if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
				notifyToggle("Anti-AFK", antiAfkEnabled)
			end,

			-- Merchants
			onToggleMerchant1 = function(v)
				if suppressRF then return end
				if not merchants then utils.notify("🌲 Merchant", "merchants.lua missing.", 3) return end
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
				if suppressRF then return end
				if not merchants then utils.notify("🌲 Merchant", "merchants.lua missing.", 3) return end
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
				if suppressRF then return end
				if not crates then utils.notify("🌲 Crates", "crates.lua missing.", 3) return end
				autoOpenCratesEnabled = (v ~= nil) and v or (not autoOpenCratesEnabled)
				if autoOpenCratesEnabled then
					if crates.refreshCrateInventory then crates.refreshCrateInventory(true) end
					local delayText = tostring((constants and constants.crateOpenDelay) or 1)
					notifyToggle("Crates", true, " (1 every " .. delayText .. "s)")
					task.spawn(function()
						if crates.autoOpenCratesEnabledLoop then
							crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end)
						end
					end)
				else
					notifyToggle("Crates", false)
				end
			end,

			-- Codes
			onRedeemCodes = function()
				if not redeemCodes then utils.notify("Codes", "redeem_unredeemed_codes.lua missing.", 4) return end
				task.spawn(function()
					local ok, err = pcall(function()
						redeemCodes.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
					end)
					if not ok then utils.notify("Codes", "Redeem failed: " .. tostring(err), 4) end
				end)
			end,

			-- Instant Level 70+
			onFastLevelToggle = function(v)
				if suppressRF then return end
				if not (fastlevel and farm) then utils.notify("🌲 Instant L70+", "fastlevel.lua or farm.lua missing.", 4) return end
				local want = (v ~= nil) and v or (not (fastlevel.isEnabled and fastlevel.isEnabled()))
				if want then
					-- Turn off Smart Farm if on
					if smartFarmEnabled then
						smartFarmEnabled = false
						rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
						notifyToggle("Smart Farm", false)
					end
					if fastlevel.enable then fastlevel.enable() end
					if farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
					notifyToggle("Instant Level 70+", true, " — targeting Sahur only")
					-- Ensure Auto-Farm is running
					if not autoFarmEnabled then
						autoFarmEnabled = true
						rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(true) end end)
						if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
						task.spawn(function()
							if farm.runAutoFarm then
								farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
							end
						end)
						notifyToggle("Auto-Farm", true)
					end
				else
					if fastlevel.disable then fastlevel.disable() end
					if farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end
					notifyToggle("Instant Level 70+", false)
					-- Also turn off Auto-Farm when leaving fast level mode
					if autoFarmEnabled then
						autoFarmEnabled = false
						rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(false) end end)
						setCurrentTarget("Current Target: None")
						notifyToggle("Auto-Farm", false)
					end
				end
			end,
		})

		utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
	else
		utils.notify("🌲 WoodzHUB", "Running without UI (ui_rayfield.lua not found).", 4)
	end
end

return app
