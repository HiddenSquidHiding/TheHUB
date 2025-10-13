-- ui_rayfield.lua
-- Rayfield UI builder (single-instance). Driven by uiFlags from games.lua.

----------------------------------------------------------------------
-- utils (minimal)
----------------------------------------------------------------------
local function getUtils()
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function() end }
end
local utils = getUtils()

----------------------------------------------------------------------
-- Singleton: prevent double window
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
  return { build = function() return {} end }
end

----------------------------------------------------------------------
-- Optional farm (for model picker)
----------------------------------------------------------------------
local farm = nil
pcall(function()
  -- try executor/memory loader first
  if _G.WOODZHUB_FS and _G.WOODZHUB_FS["farm.lua"] then
    local chunk = loadstring(_G.WOODZHUB_FS["farm.lua"], "=farm.lua")
    farm = (chunk and select(2, pcall(chunk))) or nil
  end
  if not farm then farm = require("farm") end
end)

----------------------------------------------------------------------
-- Module
----------------------------------------------------------------------
local SINGLETON = { windowBuilt = false, UI = nil }
local M = {}

function M.build(handlers, uiFlags)
  handlers = handlers or {}
  uiFlags  = uiFlags or {}

  if SINGLETON.windowBuilt and SINGLETON.UI then
    return SINGLETON.UI
  end

  local Window = Rayfield:CreateWindow({
    Name                = "🌲 WoodzHUB",
    LoadingTitle        = "WoodzHUB",
    LoadingSubtitle     = "Rayfield UI",
    ConfigurationSaving = { Enabled = false },
    KeySystem           = false,
  })

  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  -- Status
  MainTab:CreateSection("Status")
  local currentLabel = MainTab:CreateLabel("Ready.")

  -- Model picker
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

  local function truthy(x) return x == nil or x == true end

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

  -- Farming toggles (Main)
  if truthy(uiFlags.autoFarm) then
    MainTab:CreateSection("Farming")
    MainTab:CreateToggle({
      Name = "Auto-Farm",
      CurrentValue = false,
      Flag = "woodz_auto_farm",
      Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
    })
  end

  if truthy(uiFlags.smartFarm) then
    MainTab:CreateToggle({
      Name = "Smart Farm",
      CurrentValue = false,
      Flag = "woodz_smart_farm",
      Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
    })
  end

  -- Options: AFK / Merchants / Crates / Extras / Dungeon
  if truthy(uiFlags.antiAFK) then
    OptionsTab:CreateSection("AFK")
    OptionsTab:CreateToggle({
      Name = "Anti-AFK",
      CurrentValue = false,
      Flag = "woodz_afk",
      Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
    })
  end

  if uiFlags.merchants or uiFlags.crates then
    OptionsTab:CreateSection("Merchants / Crates")
  end

  if uiFlags.merchants then
    OptionsTab:CreateToggle({
      Name = "Auto Buy Mythics (Chicleteiramania)",
      CurrentValue = false,
      Flag = "woodz_m1",
      Callback = function(v) if handlers.onToggleMerchant1 then handlers.onToggleMerchant1(v) end end,
    })
    OptionsTab:CreateToggle({
      Name = "Auto Buy Mythics (Bombardino Sewer)",
      CurrentValue = false,
      Flag = "woodz_m2",
      Callback = function(v) if handlers.onToggleMerchant2 then handlers.onToggleMerchant2(v) end end,
    })
  end

  if uiFlags.crates then
    OptionsTab:CreateToggle({
      Name = "Auto Open Crates",
      CurrentValue = false,
      Flag = "woodz_crates",
      Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
    })
  end

  if uiFlags.redeemCodes or uiFlags.privateServer or uiFlags.fastlevel or uiFlags.dungeon then
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

  if uiFlags.fastlevel then
    OptionsTab:CreateToggle({
      Name = "Instant Level 70+ (Sahur only)",
      CurrentValue = false,
      Flag = "woodz_fastlevel",
      Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
    })
  end

  if uiFlags.dungeon then
    OptionsTab:CreateToggle({
      Name = "Dungeon Auto-Attack",
      CurrentValue = false,
      Flag = "woodz_dungeon_auto",
      Callback = function(v) if handlers.onDungeonAuto then handlers.onDungeonAuto(v) end end,
    })
    OptionsTab:CreateToggle({
      Name = "Auto Replay (Play Again)",
      CurrentValue = false,
      Flag = "woodz_dungeon_replay",
      Callback = function(v) if handlers.onDungeonReplay then handlers.onDungeonReplay(v) end end,
    })
  end

  -- UI control surface
  local UI = {
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Ready.") end) end,

    setAutoFarm  = function(on) end,
    setSmartFarm = function(on) end,
    setFastLevel = function(on) end,

    setMerchant1 = function(on) end,
    setMerchant2 = function(on) end,
    setCrates    = function(on) end,

    setDungeonAuto   = function(on) end,
    setDungeonReplay = function(on) end,

    refreshModelOptions = function() pcall(refreshDropdownOptions) end,
    syncModelSelection  = function() pcall(syncDropdownSelectionFromFarm) end,

    destroy = function() pcall(function() Rayfield:Destroy() end) end,
  }

  SINGLETON.windowBuilt = true
  SINGLETON.UI = UI
  _G.WOODZHUB_RAYFIELD_UI = UI
  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
