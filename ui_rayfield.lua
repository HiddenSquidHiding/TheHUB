-- ui_rayfield.lua
-- Rayfield overlay UI (conditional controls via profile.ui)

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function(_,_) end }
end

local utils = getUtils()

local Rayfield  = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local M = {}

-- uiFlags fields (all optional booleans):
-- modelPicker,currentTarget,autoFarm,smartFarm,merchants,crates,antiAFK,redeemCodes,fastlevel,privateServer,dungeon
function M.build(handlers)
  handlers = handlers or {}
  local uiFlags = handlers.ui or {}

  local Window = Rayfield:CreateWindow({
    Name                = "🌲 WoodzHUB — Rayfield",
    LoadingTitle        = "WoodzHUB",
    LoadingSubtitle     = "Rayfield UI",
    ConfigurationSaving = { Enabled = false, FolderName = "WoodzHUB", FileName = "Rayfield" },
    KeySystem           = false,
  })

  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  ------------------------------------------------------------------
  -- Model picker
  ------------------------------------------------------------------
  local modelDropdown
  if uiFlags.modelPicker then
    MainTab:CreateSection("Targets")

    local currentSearch = ""

    local function getOptions()
      local list = {}
      if handlers.onModelSearch then
        list = handlers.onModelSearch(currentSearch or "") or {}
      end
      local out = {}
      for _, v in ipairs(list) do if typeof(v)=="string" then table.insert(out, v) end end
      return out
    end

    MainTab:CreateInput({
      Name = "Search Models",
      PlaceholderText = "Type model names to filter…",
      RemoveTextAfterFocusLost = false,
      Callback = function(text)
        currentSearch = tostring(text or "")
        if modelDropdown then
          local opts = getOptions()
          local ok = pcall(function() modelDropdown:Refresh(opts, true) end)
          if not ok then pcall(function() modelDropdown:Set(opts) end) end
        end
      end,
    })

    modelDropdown = MainTab:CreateDropdown({
      Name = "Target Models (multi-select)",
      Options = getOptions(),
      CurrentOption = {},
      MultipleOptions = true,
      Flag = "woodz_models",
      Callback = function(selection)
        local list = {}
        if typeof(selection) == "table" then
          for _, v in ipairs(selection) do if typeof(v)=="string" then table.insert(list, v) end end
        elseif typeof(selection) == "string" then
          table.insert(list, selection)
        end
        if handlers.onModelSet then handlers.onModelSet(list) end
      end,
    })

    MainTab:CreateButton({
      Name = "Clear All Selections",
      Callback = function()
        if handlers.onClearAll then handlers.onClearAll() end
        if modelDropdown then
          local opts = getOptions()
          pcall(function() modelDropdown:Refresh(opts, true) end)
          pcall(function() modelDropdown:Set({}) end)
        end
      end,
    })
  end

  ------------------------------------------------------------------
  -- Farming toggles + current target
  ------------------------------------------------------------------
  if uiFlags.autoFarm or uiFlags.smartFarm or uiFlags.currentTarget then
    MainTab:CreateSection("Farming")
  end

  local rfAutoFarm, rfSmartFarm, currentLabel

  if uiFlags.autoFarm then
    rfAutoFarm = MainTab:CreateToggle({
      Name = "Auto-Farm",
      CurrentValue = false,
      Flag = "woodz_auto_farm",
      Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
    })
  end

  if uiFlags.smartFarm then
    rfSmartFarm = MainTab:CreateToggle({
      Name = "Smart Farm",
      CurrentValue = false,
      Flag = "woodz_smart_farm",
      Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
    })
  end

  if uiFlags.currentTarget then
    currentLabel = MainTab:CreateLabel("Current Target: None")
  end

  ------------------------------------------------------------------
  -- Dungeon (Brainrot Dungeon) toggles
  ------------------------------------------------------------------
  if uiFlags.dungeon then
    MainTab:CreateSection("Dungeon")
    local rfDungeon = MainTab:CreateToggle({
      Name = "Dungeon Auto-Attack",
      CurrentValue = false,
      Flag = "woodz_dungeon_auto",
      Callback = function(v) if handlers.onDungeonAutoToggle then handlers.onDungeonAutoToggle(v) end end,
    })
    local rfReplay = MainTab:CreateToggle({
      Name = "Play Again Automatically",
      CurrentValue = false,
      Flag = "woodz_dungeon_replay",
      Callback = function(v) if handlers.onDungeonReplayToggle then handlers.onDungeonReplayToggle(v) end end,
    })
  end

  ------------------------------------------------------------------
  -- Options tab
  ------------------------------------------------------------------
  if uiFlags.merchants or uiFlags.crates or uiFlags.antiAFK then
    OptionsTab:CreateSection("Merchants / Crates / AFK")
  end

  local rfMerch1, rfMerch2, rfCrates, rfAFK, rfFastLvl

  if uiFlags.merchants then
    rfMerch1 = OptionsTab:CreateToggle({
      Name = "Auto Buy Mythics (Chicleteiramania)",
      CurrentValue = false,
      Flag = "woodz_m1",
      Callback = function(v) if handlers.onToggleMerchant1 then handlers.onToggleMerchant1(v) end end,
    })
    rfMerch2 = OptionsTab:CreateToggle({
      Name = "Auto Buy Mythics (Bombardino Sewer)",
      CurrentValue = false,
      Flag = "woodz_m2",
      Callback = function(v) if handlers.onToggleMerchant2 then handlers.onToggleMerchant2(v) end end,
    })
  end

  if uiFlags.crates then
    rfCrates = OptionsTab:CreateToggle({
      Name = "Auto Open Crates",
      CurrentValue = false,
      Flag = "woodz_crates",
      Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
    })
  end

  if uiFlags.antiAFK then
    rfAFK = OptionsTab:CreateToggle({
      Name = "Anti-AFK",
      CurrentValue = false,
      Flag = "woodz_afk",
      Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
    })
  end

  OptionsTab:CreateSection("Extras")

  if uiFlags.redeemCodes then
    OptionsTab:CreateButton({
      Name = "Redeem Unredeemed Codes",
      Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end,
    })
  end

  if uiFlags.fastlevel then
    rfFastLvl = OptionsTab:CreateToggle({
      Name = "Instant Level 70+ (Sahur only)",
      CurrentValue = false,
      Flag = "woodz_fastlevel",
      Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
    })
  end

  ------------------------------------------------------------------
  -- Export minimal UI control
  ------------------------------------------------------------------
  local UI = {
    setCurrentTarget = function(text) if currentLabel then pcall(function() currentLabel:Set(text or "Current Target: None") end) end end,
    setAutoFarm      = function(on)   if rfAutoFarm then pcall(function() rfAutoFarm:Set(on and true or false) end) end end,
    setSmartFarm     = function(on)   if rfSmartFarm then pcall(function() rfSmartFarm:Set(on and true or false) end) end end,
    destroy          = function() pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
