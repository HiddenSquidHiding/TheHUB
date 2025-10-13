-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (feature-gated by uiFlags from games.lua).
-- Single-instance; safe if the executor re-runs it.

----------------------------------------------------------------------
-- Minimal utils
----------------------------------------------------------------------
local function getUtils()
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return {
    notify = function(_, _) end,
  }
end
local utils = getUtils()

----------------------------------------------------------------------
-- Singleton: don't build twice
----------------------------------------------------------------------
if _G.WOODZHUB_RAYFIELD_UI and type(_G.WOODZHUB_RAYFIELD_UI) == "table" then
  return _G.WOODZHUB_RAYFIELD_UI
end

----------------------------------------------------------------------
-- Load Rayfield
----------------------------------------------------------------------
local okRF, Rayfield = pcall(function()
  return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not okRF or not Rayfield then
  warn("[ui_rayfield] Rayfield failed to load")
  return {
    build = function()
      return setmetatable({}, {
        __index = function()
          return function() end
        end
      })
    end
  }
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function truthy(x) return x == nil or x == true end

-- optional farm access (only if present)
local farm = nil
pcall(function() farm = require(script.Parent and script.Parent.farm) end)

----------------------------------------------------------------------
-- Module
----------------------------------------------------------------------
local SINGLETON = { windowBuilt = false, UI = nil }
local M = {}

function M.build(handlers, uiFlags)
  handlers = handlers or {}
  uiFlags  = uiFlags  or {}

  if SINGLETON.windowBuilt and SINGLETON.UI then
    return SINGLETON.UI
  end

  -- Window
  local Window = Rayfield:CreateWindow({
    Name                = "🌲 WoodzHUB",
    LoadingTitle        = "WoodzHUB",
    LoadingSubtitle     = "Rayfield UI",
    ConfigurationSaving = { Enabled = false },
    KeySystem           = false,
  })

  -- Tabs
  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  --------------------------------------------------------------------
  -- MAIN TAB
  --------------------------------------------------------------------
  MainTab:CreateSection("Status")
  local currentLabel = MainTab:CreateLabel("Ready.")

  -- Model picker (search + multi-select) — only if enabled by profile
  local modelDropdown, currentSearch = nil, ""
  local suppressDropdown = false

  local function filteredList()
    if not farm or not farm.filterMonsterModels then return {} end
    local list = farm.filterMonsterModels(currentSearch or "")
    local out = {}
    for _, v in ipairs(list or {}) do
      if typeof(v) == "string" then table.insert(out, v) end
    end
    return out
  end
  local function syncDropdownSelectionFromFarm()
    if not (modelDropdown and farm and farm.getSelected) then return end
    local sel = farm.getSelected() or {}
    suppressDropdown = true
    pcall(function() modelDropdown:Set(sel) end)
    suppressDropdown = false
  end
  local function refreshDropdownOptions()
    if not modelDropdown then return end
    local opts = filteredList()
    suppressDropdown = true
    local ok = pcall(function() modelDropdown:Refresh(opts, true) end)
    if not ok then pcall(function() modelDropdown:Set(opts) end) end
    syncDropdownSelectionFromFarm()
    suppressDropdown = false
  end

  if truthy(uiFlags.modelPicker) then
    MainTab:CreateSection("Targets")
    MainTab:CreateInput({
      Name = "Search Models",
      PlaceholderText = "Type to filter…",
      RemoveTextAfterFocusLost = false,
      Callback = function(text)
        currentSearch = tostring(text or "")
        refreshDropdownOptions()
      end,
    })

    -- seed farm list once
    pcall(function() if farm and farm.getMonsterModels then farm.getMonsterModels() end end)

    modelDropdown = MainTab:CreateDropdown({
      Name = "Target Models (multi-select)",
      Options = filteredList(),
      CurrentOption = (farm and farm.getSelected and farm.getSelected()) or {},
      MultipleOptions = true,
      Flag = "woodz_models",
      Callback = function(selection)
        if suppressDropdown then return end
        if not (farm and farm.setSelected) then return end
        local list = {}
        if typeof(selection) == "table" then
          for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(list, v) end end
        elseif typeof(selection) == "string" then
          table.insert(list, selection)
        end
        farm.setSelected(list)
      end,
    })

    MainTab:CreateButton({
      Name = "Clear All Selections",
      Callback = function()
        if farm and farm.setSelected then farm.setSelected({}) end
        syncDropdownSelectionFromFarm()
        utils.notify("🌲 Preset", "Cleared all selections.", 3)
      end,
    })
  end

  -- Farming toggles
  local rfAutoFarm, rfSmartFarm, rfFastLvl
  if truthy(uiFlags.autoFarm) or truthy(uiFlags.smartFarm) or uiFlags.fastlevel then
    MainTab:CreateSection("Farming")
  end

  if truthy(uiFlags.autoFarm) then
    rfAutoFarm = MainTab:CreateToggle({
      Name = "Auto-Farm",
      CurrentValue = false,
      Flag = "woodz_auto_farm",
      Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
    })
  end

  if truthy(uiFlags.smartFarm) then
    rfSmartFarm = MainTab:CreateToggle({
      Name = "Smart Farm",
      CurrentValue = false,
      Flag = "woodz_smart_farm",
      Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
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

  --------------------------------------------------------------------
  -- OPTIONS TAB
  --------------------------------------------------------------------
  if truthy(uiFlags.antiAFK) then
    OptionsTab:CreateSection("AFK")
    local rfAFK = OptionsTab:CreateToggle({
      Name = "Anti-AFK",
      CurrentValue = false,
      Flag = "woodz_afk",
      Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
    })
  end

  if uiFlags.merchants or uiFlags.crates then
    OptionsTab:CreateSection("Merchants / Crates")
  end

  local rfMerch1, rfMerch2, rfCrates
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

  if uiFlags.redeemCodes or uiFlags.privateServer then
    OptionsTab:CreateSection("Extras")
  end

  if uiFlags.redeemCodes then
    OptionsTab:CreateButton({
      Name = "Redeem Unredeemed Codes",
      Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end,
    })
  end

  if uiFlags.privateServer then
    OptionsTab:CreateButton({
      Name = "Private Server",
      Callback = function()
        task.spawn(function()
          if not _G.TeleportToPrivateServer then
            utils.notify("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
            return
          end
          local ok, err = pcall(_G.TeleportToPrivateServer)
          if ok then utils.notify("🌲 Private Server", "Teleport initiated!", 3)
          else utils.notify("🌲 Private Server", "Failed: "..tostring(err), 5) end
        end)
      end,
    })
  end

  -- NEW: Dungeon section
  local rfDungeonAuto, rfDungeonReplay
  if uiFlags.dungeon then
    OptionsTab:CreateSection("Dungeon")
    rfDungeonAuto = OptionsTab:CreateToggle({
      Name = "Dungeon Auto-Attack",
      CurrentValue = false,
      Flag = "woodz_dungeon_auto",
      Callback = function(v) if handlers.onDungeonAuto then handlers.onDungeonAuto(v) end end,
    })
    rfDungeonReplay = OptionsTab:CreateToggle({
      Name = "Auto Replay (Play Again)",
      CurrentValue = false,
      Flag = "woodz_dungeon_replay",
      Callback = function(v) if handlers.onDungeonReplay then handlers.onDungeonReplay(v) end end,
    })
  end

  --------------------------------------------------------------------
  -- Expose control surface
  --------------------------------------------------------------------
  local UI = {
    -- Status
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Ready.") end) end,

    -- Farming setters
    setAutoFarm  = function(on) if rfAutoFarm  then pcall(function() rfAutoFarm:Set(on and true or false) end) end end,
    setSmartFarm = function(on) if rfSmartFarm then pcall(function() rfSmartFarm:Set(on and true or false) end) end end,
    setFastLevel = function(on) if rfFastLvl   then pcall(function() rfFastLvl:Set(on and true or false) end)   end end,

    -- Merchants/Crates
    setMerchant1 = function(on) if rfMerch1 then pcall(function() rfMerch1:Set(on and true or false) end) end end,
    setMerchant2 = function(on) if rfMerch2 then pcall(function() rfMerch2:Set(on and true or false) end) end end,
    setCrates    = function(on) if rfCrates  then pcall(function() rfCrates:Set(on and true or false) end)  end end,

    -- Dungeon
    setDungeonAuto   = function(on) if rfDungeonAuto   then pcall(function() rfDungeonAuto:Set(on and true or false) end) end end,
    setDungeonReplay = function(on) if rfDungeonReplay then pcall(function() rfDungeonReplay:Set(on and true or false) end) end end,

    -- Model list control (if picker is enabled)
    refreshModelOptions = function() pcall(refreshDropdownOptions) end,
    syncModelSelection  = function() pcall(syncDropdownSelectionFromFarm) end,

    -- Cleanup
    destroy = function() pcall(function() Rayfield:Destroy() end) end,
  }

  SINGLETON.windowBuilt = true
  SINGLETON.UI = UI
  _G.WOODZHUB_RAYFIELD_UI = UI

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
