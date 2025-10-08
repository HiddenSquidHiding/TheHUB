-- app.lua
-- Top-level wiring for UI <-> features

----------------------------------------------------------------------
-- Safe utils resolution (avoid require(nil))
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

----------------------------------------------------------------------
-- Requires & Services
----------------------------------------------------------------------
local utils             = getUtils()
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local constants   = require(script.Parent.constants)
local uiModule    = require(script.Parent.ui)
local farm        = require(script.Parent.farm)
local merchants   = require(script.Parent.merchants)
local crates      = require(script.Parent.crates)
local antiAFK     = require(script.Parent.anti_afk)
local redeemCodes = require(script.Parent.redeem_unredeemed_codes)
local smartFarm   = require(script.Parent.smart_target)
local fastlevel   = require(script.Parent.fastlevel)
local uiRF        = require(script.Parent.ui_rayfield)


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
local fastLevelEnabled		 = false

-- UI refs (set in start)
local UI = nil

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function notifyToggle(name, on, extra)
	extra = extra or ""
	local msg = on and (name .. " enabled" .. extra) or (name .. " disabled")
	utils.notify("🌲 " .. name, msg, 3.5)
end

local function setToggleVisual(button, isOn, textPrefix)
	button.Text = (textPrefix or "Toggle") .. (isOn and "ON" or "OFF")
	button.BackgroundColor3 = isOn and constants.COLOR_BTN_ACTIVE or constants.COLOR_BTN
end

local function setAutoFarmUI(on)
	setToggleVisual(UI.AutoFarmToggle, on, "Auto-Farm: ")
end

local function setSmartFarmUI(on)
	setToggleVisual(UI.SmartFarmToggle, on, "Smart Farm: ")
end

-- Resolve ReplicatedStorage MonsterInfo in several common locations
local function resolveMonsterInfo()
	local RS = ReplicatedStorage

	local candidatePaths = {
		{ "GameInfo", "MonsterInfo" }, -- common path
		{ "MonsterInfo" },
		{ "Shared", "MonsterInfo" },
		{ "Modules", "MonsterInfo" },
		{ "Configs", "MonsterInfo" },
	}

	-- Try listed paths (with short WaitForChild fallback)
	for _, path in ipairs(candidatePaths) do
		local node = RS
		local ok = true

		for _, name in ipairs(path) do
			node = node:FindFirstChild(name) or node:WaitForChild(name, 1)
			if not node then
				ok = false
				break
			end
		end

		if ok and node and node:IsA("ModuleScript") then
			return node
		end
	end

	-- Last resort: scan descendants for a ModuleScript named "MonsterInfo"
	for _, d in ipairs(RS:GetDescendants()) do
		if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then
			return d
		end
	end

	return nil
end

----------------------------------------------------------------------
-- UI Builders
----------------------------------------------------------------------
local function rebuildModelButtons()
	-- Clear previous buttons
	for _, ch in ipairs(UI.ModelScrollFrame:GetChildren()) do
		if ch:IsA("TextButton") then
			ch:Destroy()
		end
	end

	-- Build current
	local models = farm.getFiltered()
	local count = 0

	for _, name in ipairs(models) do
		local btn = utils.new("TextButton", {
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

	UI.ModelScrollFrame.CanvasSize = UDim2.new(0, 0, 0, count * 30)
end

local function applySearchFilter(text)
	farm.filterMonsterModels(text or "")
	rebuildModelButtons()
end

----------------------------------------------------------------------
-- Presets
----------------------------------------------------------------------
local function addPresetOnce(label, successMsg)
	local sel = farm.getSelected()
	if not table.find(sel, label) then
		sel = table.clone(sel)
		table.insert(sel, label)
		farm.setSelected(sel)
		rebuildModelButtons()
		utils.notify("🌲 Preset", successMsg, 3)
	end
end

----------------------------------------------------------------------
-- App start
----------------------------------------------------------------------
function app.start()
	UI = uiModule.build()

	------------------------------------------------------------------
	-- Build model list, search, presets
	------------------------------------------------------------------
	farm.getMonsterModels()

	applySearchFilter("")

	utils.track(UI.SearchTextBox:GetPropertyChangedSignal("Text"):Connect(function()
		applySearchFilter(UI.SearchTextBox.Text)
	end))

	utils.track(UI.SelectSahurButton.MouseButton1Click:Connect(function()
		addPresetOnce("To Sahur", "Selected all To Sahur models.")
	end))

	utils.track(UI.SelectWeatherButton.MouseButton1Click:Connect(function()
		addPresetOnce("Weather Events", "Selected all Weather Events models.")
	end))

	utils.track(UI.SelectAllButton.MouseButton1Click:Connect(function()
		farm.setSelected(table.clone(farm.getMonsterModels()))
		rebuildModelButtons()
		utils.notify("🌲 Preset", "Selected all models.", 3)
	end))

	utils.track(UI.ClearAllButton.MouseButton1Click:Connect(function()
		farm.setSelected({})
		rebuildModelButtons()
		utils.notify("🌲 Preset", "Cleared all selections.", 3)
	end))

	------------------------------------------------------------------
	-- Auto-Farm (mutually exclusive with Smart Farm)
	------------------------------------------------------------------
	utils.track(UI.AutoFarmToggle.MouseButton1Click:Connect(function()
		local newState = not autoFarmEnabled

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
					function(t) UI.CurrentTargetLabel.Text = t end
				)
			end)
		else
			UI.CurrentTargetLabel.Text = "Current Target: None"
			notifyToggle("Auto-Farm", false)
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
						function(txt) UI.CurrentTargetLabel.Text = txt end,
						{
							module = module,
							safetyBuffer = 0.8,
							refreshInterval = 0.05,
						}
					)
				end)
			else
				smartFarmEnabled = false
				setSmartFarmUI(false)
			end
		else
			UI.CurrentTargetLabel.Text = "Current Target: None"
			notifyToggle("Smart Farm", false)
		end
	end))

	------------------------------------------------------------------
	-- Anti-AFK
	------------------------------------------------------------------
	utils.track(UI.ToggleAntiAFKButton.MouseButton1Click:Connect(function()
		antiAfkEnabled = not antiAfkEnabled

		if antiAfkEnabled then
			antiAFK.enable()
		else
			antiAFK.disable()
		end

		setToggleVisual(UI.ToggleAntiAFKButton, antiAfkEnabled, "Anti-AFK: ")
		notifyToggle("Anti-AFK", antiAfkEnabled)
	end))

	------------------------------------------------------------------
	-- Redeem Codes (one-shot)
	------------------------------------------------------------------
	utils.track(UI.RedeemCodesButton.MouseButton1Click:Connect(function()
    -- Brief UI feedback while running
		UI.RedeemCodesButton.Text = "Redeeming..."
		UI.RedeemCodesButton.AutoButtonColor = false
		UI.RedeemCodesButton.Active = false

    task.spawn(function()
		local ok, err = pcall(function()
        -- dryRun=false; concurrent=true; small spacing if sequential
			redeemCodes.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
		end)

			if not ok then
				utils.notify("Codes", "Redeem failed: " .. tostring(err), 4)
			end

      -- restore button
			UI.RedeemCodesButton.Text = "Redeem Unredeemed Codes"
			UI.RedeemCodesButton.AutoButtonColor = true
			UI.RedeemCodesButton.Active = true
		end)
	end))

	
	------------------------------------------------------------------
	-- Merchants
	------------------------------------------------------------------
	utils.track(UI.ToggleMerchant1Button.MouseButton1Click:Connect(function()
		autoBuyM1Enabled = not autoBuyM1Enabled
		setToggleVisual(UI.ToggleMerchant1Button, autoBuyM1Enabled, "Auto Buy Mythics (Chicleteiramania): ")

		if autoBuyM1Enabled then
			notifyToggle("Merchant — Chicleteiramania", true)
			task.spawn(function()
				merchants.autoBuyLoop(
					"SmelterMerchantService",
					function() return autoBuyM1Enabled end,
					function(sfx)
						UI.ToggleMerchant1Button.Text = "Auto Buy Mythics (Chicleteiramania): ON " .. sfx
					end
				)
			end)
		else
			notifyToggle("Merchant — Chicleteiramania", false)
		end
	end))

	utils.track(UI.ToggleMerchant2Button.MouseButton1Click:Connect(function()
		autoBuyM2Enabled = not autoBuyM2Enabled
		setToggleVisual(UI.ToggleMerchant2Button, autoBuyM2Enabled, "Auto Buy Mythics (Bombardino Sewer): ")

		if autoBuyM2Enabled then
			notifyToggle("Merchant — Bombardino Sewer", true)
			task.spawn(function()
				merchants.autoBuyLoop(
					"SmelterMerchantService2",
					function() return autoBuyM2Enabled end,
					function(sfx)
						UI.ToggleMerchant2Button.Text = "Auto Buy Mythics (Bombardino Sewer): ON " .. sfx
					end
				)
			end)
		else
			notifyToggle("Merchant — Bombardino Sewer", false)
		end
	end))

	------------------------------------------------------------------
	-- Auto Crates
	------------------------------------------------------------------
	utils.track(UI.ToggleAutoCratesButton.MouseButton1Click:Connect(function()
		autoOpenCratesEnabled = not autoOpenCratesEnabled
		setToggleVisual(UI.ToggleAutoCratesButton, autoOpenCratesEnabled, "Auto Open Crates: ")

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
	end))

	  ------------------------------------------------------------------
  -- Instant Level 70+ (forces single Sahur target; favors Auto-Farm)
  ------------------------------------------------------------------
  utils.track(UI.FastLevelButton.MouseButton1Click:Connect(function()
    fastLevelEnabled = not fastLevelEnabled
    setToggleVisual(UI.FastLevelButton, fastLevelEnabled, "Instant Level 70+: ")

    if fastLevelEnabled then
      -- Ensure Smart Farm is off (it chooses targets itself)
      if smartFarmEnabled then
        smartFarmEnabled = false
        setSmartFarmUI(false)
        notifyToggle("Smart Farm", false)
      end

      -- Force target selection to the Sahur mob, preserving previous selection
      fastlevel.enable()
      -- Rebuild list so highlight reflects the forced selection
      rebuildModelButtons()
      notifyToggle("Instant Level 70+", true, " — targeting Sahur only")

      -- Make sure Auto-Farm is running; if not, start it now
      if not autoFarmEnabled then
        autoFarmEnabled = true
        setAutoFarmUI(true)
        farm.setupAutoAttackRemote()
        task.spawn(function()
          farm.runAutoFarm(
            function() return autoFarmEnabled end,
            function(t) UI.CurrentTargetLabel.Text = t end
          )
        end)
        notifyToggle("Auto-Farm", true)
      end
    else
      -- Restore prior selection and UI
      fastlevel.disable()
      rebuildModelButtons()
      notifyToggle("Instant Level 70+", false)
    end
  end))

	------------------------------------------------------------------
	-- Close button
	------------------------------------------------------------------
	utils.track(UI.CloseButton.MouseButton1Click:Connect(function()
		autoFarmEnabled       = false
		smartFarmEnabled      = false
		autoBuyM1Enabled      = false
		autoBuyM2Enabled      = false
		autoOpenCratesEnabled = false

		if antiAfkEnabled then
			antiAFK.disable()
			antiAfkEnabled = false
		end

    	if fastlevel and fastlevel.isEnabled and fastlevel.isEnabled() then
      		fastlevel.disable()
			fastLevelEnabled = false
    	end


		utils.notify("🌲 WoodzHUB", "Closed. All loops stopped and UI removed.", 3.5)

		if UI.ScreenGui and UI.ScreenGui.Parent then
			UI.ScreenGui:Destroy()
		end
	end))
end

return app
