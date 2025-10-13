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
-- Optional requires (graceful if missing)
----------------------------------------------------------------------
local function tryRequire(name)
	local ok, mod = pcall(function() return require(script.Parent[name]) end)
	if not ok then
		warn(("-- [app.lua] optional module '%s' not available: %s"):format(tostring(name), tostring(mod)))
		return nil
	end
	return mod
end

local constants   = tryRequire("constants")                or {}
local uiRF        = tryRequire("ui_rayfield")
local farm        = tryRequire("farm")
local merchants   = tryRequire("merchants")
local crates      = tryRequire("crates")
local antiAFK     = tryRequire("anti_afk")
local smartFarm   = tryRequire("smart_target")
local redeemCodes = tryRequire("redeem_unredeemed_codes")
local fastlevel   = tryRequire("fastlevel")

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

-- Throttled label setter (Rayfield labels are heavier than TextLabels)
local lastLabelText, lastLabelAt = nil, 0
local function setCurrentTarget(text)
  text = text or "Current Target: None"
  local now = tick()
  if text == lastLabelText and (now - lastLabelAt) < 0.15 then return end
  lastLabelText, lastLabelAt = text, now
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
	if not uiRF then
		utils.notify("🌲 WoodzHUB", "ui_rayfield.lua missing - UI not loaded. Core still running.", 5)
		return
	end

	-- Prime monster list once so picker has data (if farm exists)
	if farm and farm.getMonsterModels then pcall(function() farm.getMonsterModels() end) end

	RF = uiRF.build({
		-- Picker helper
		onClearAll = function()
			if not farm then return end
			farm.setSelected({})
			utils.notify("🌲 Preset", "Cleared all selections.", 3)
		end,

		-- Auto-Farm (mutually exclusive with Smart Farm)
		onAutoFarmToggle = function(v)
			if not farm then return end
			if suppressRF then return end
			local newState = (v ~= nil) and v or (not autoFarmEnabled)

			-- if switching on while smart farm is on, turn that off first
			if newState and smartFarmEnabled then
				smartFarmEnabled = false
				rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
				notifyToggle("Smart Farm", false)
			end

			autoFarmEnabled = newState

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
			if not smartFarm then return end
			if suppressRF then return end
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
			if not antiAFK then return end
			if suppressRF then return end
			antiAfkEnabled = (v ~= nil) and v or (not antiAfkEnabled)
			if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
			notifyToggle("Anti-AFK", antiAfkEnabled)
		end,

		-- Merchants
		onToggleMerchant1 = function(v)
			if not merchants then return end
			if suppressRF then return end
			autoBuyM1Enabled = (v ~= nil) and v or (not autoBuyM1Enabled)
			if autoBuyM1Enabled then
				notifyToggle("Merchant — Chicleteiramania", true)
				task.spawn(function()
					merchants.autoBuyLoop(
						"SmelterMerchantService",
						function() return autoBuyM1Enabled end,
						function(_) end
					)
				end)
			else
				notifyToggle("Merchant — Chicleteiramania", false)
			end
		end,

		onToggleMerchant2 = function(v)
			if not merchants then return end
			if suppressRF then return end
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
		end,

		-- Crates
		onToggleCrates = function(v)
			if not crates then return end
			if suppressRF then return end
			autoOpenCratesEnabled = (v ~= nil) and v or (not autoOpenCratesEnabled)
			if autoOpenCratesEnabled then
				if crates.refreshCrateInventory then crates.refreshCrateInventory(true) end
				local delayText = tostring((constants and constants.crateOpenDelay) or 1)
				notifyToggle("Crates", true, " (1 every " + delayText + "s)")
				task.spawn(function()
					crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end)
				end)
			else
				notifyToggle("Crates", false)
			end
		end,

		-- Codes
		onRedeemCodes = function()
			if not redeemCodes then return end
			task.spawn(function()
				local ok, err = pcall(function()
					redeemCodes.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
				end)
				if not ok then utils.notify("Codes", "Redeem failed: " .. tostring(err), 4) end
			end)
		end,

		-- Private server: expect _G.TeleportToPrivateServer to be set by your solo.lua
		onPrivateServer = function()
			task.spawn(function()
				if not _G.TeleportToPrivateServer then
					utils.notify("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
					return
				end
				local success, err = pcall(_G.TeleportToPrivateServer)
				if success then
					utils.notify("🌲 Private Server", "Teleport initiated to private server!", 3)
				else
					utils.notify("🌲 Private Server", "Failed to teleport: " .. tostring(err), 5)
				end
			end)
		end,

		-- Instant Level 70+ (Sahur only). When OFF -> also turn Auto-Farm OFF.
		onFastLevelToggle = function(v)
			if not (farm and fastlevel) then return end
			if suppressRF then return end

			local newState = (v ~= nil) and v or (not fastlevel.isEnabled())
			if newState then
				-- ensure SmartFarm is off
				if smartFarmEnabled then
					smartFarmEnabled = false
					rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
					notifyToggle("Smart Farm", false)
				end

				fastlevel.enable()                          -- internal flag
				farm.setFastLevelEnabled(true)              -- tell farm to ignore 3s stall
				notifyToggle("Instant Level 70+", true, " — targeting Sahur only")

				-- ensure Auto-Farm is on
				if not autoFarmEnabled then
					autoFarmEnabled = true
					rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(true) end end)
					farm.setupAutoAttackRemote()
					task.spawn(function()
						farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
					end)
					notifyToggle("Auto-Farm", true)
				end
			else
				fastlevel.disable()
				farm.setFastLevelEnabled(false)
				notifyToggle("Instant Level 70+", false)

				-- ALSO turn Auto-Farm OFF when L70+ is turned OFF (your request)
				if autoFarmEnabled then
					autoFarmEnabled = false
					rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(false) end end)
					setCurrentTarget("Current Target: None")
					notifyToggle("Auto-Farm", false)
				end
			end
		end,
	})

	utils.notify("🌲 WoodzHUB", "Rayfield UI only mode active.", 4)
end

return app
