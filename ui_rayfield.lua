-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (model picker + toggles + extras), single-window, robust Rayfield loader.

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function() end }
end

local utils     = getUtils()

-- Optional siblings. These may not exist in every game; guard all uses.
local ok_const, constants = pcall(function() return require(script.Parent.constants) end)
local ok_hud,    hud      = pcall(function() return require(script.Parent.hud) end)
local ok_farm,   farm     = pcall(function() return require(script.Parent.farm) end)

local Players    = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

-- ---------- Rayfield loader (2 URL fallback + reuse if already loaded) ----------
local function loadRayfieldOnce()
  if _G.__WOODZ_RAYFIELD then
    return _G.__WOODZ_RAYFIELD
  end
  local urls = {
    "https://sirius.menu/rayfield", -- primary
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source", -- fallback
  }
  local lastErr
  for _, url in ipairs(urls) do
    local ok, modOrErr = pcall(function()
      return loadstring(game:HttpGet(url))()
    end)
    if ok and type(modOrErr) == "table" and modOrErr.CreateWindow then
      _G.__WOODZ_RAYFIELD = modOrErr
      return modOrErr
    else
      lastErr = tostring(modOrErr)
    end
  end
  return nil, lastErr or "unable to fetch Rayfield"
end

local M = {}

function M.build(handlers)
  -- Guard against duplicate windows (if caller accidentally calls build twice)
  if _G.__WOODZ_WINDOW_BUILT then
    return _G.__WOODZ_WINDOW_BUILT
  end

  handlers = handlers or {}

  local Rayfield, why = loadRayfieldOnce()
  if not Rayfield then
    utils.notify("[ui_rayfield]", "Rayfield failed to load: "..tostring(why), 5)
    -- Return a tiny no-op facade so app.lua can proceed without UI
    local nullUI = {
      setCurrentTarget = function() end,
      setAutoFarm = function() end, setSmartFarm=function() end,
      setMerchant1=function() end, setMerchant2=function() end,
      setCrates=function() end, setAntiAFK=function() end,
      setFastLevel=function() end,
      refreshModelOptions=function() end,
      syncModelSelection=function() end,
      destroy=function() end,
    }
    _G.__WOODZ_WINDOW_BUILT = nullUI
    return nullUI
  end

  local Window = Rayfield:CreateWindow({
    Name                = "🌲 WoodzHUB — Rayfield",
    LoadingTitle        = "WoodzHUB",
    LoadingSubtitle     = "Rayfield UI",
    ConfigurationSaving = { Enabled = false, FolderName = "WoodzHUB", FileName = "Rayfield" },
    KeySystem           = false,
  })

  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  --------------------------------------------------------------------------
  -- Targets (only if farm module available)
  --------------------------------------------------------------------------
  local currentLabel
  if ok_farm and type(farm.getMonsterModels) == "function" then
    MainTab:CreateSection("Targets")

    local currentSearch = ""
    pcall(function() farm.getMonsterModels() end)

    local function filteredList()
      local list = farm.filterMonsterModels(currentSearch or "")
      local out = {}
      for _, v in ipairs(list or {}) do
        if typeof(v) == "string" then table.insert(out, v) end
      end
      return out
    end

    local modelDropdown
    local suppressDropdown = false

    local function syncDropdownSelectionFromFarm()
      if not modelDropdown then return end
      local sel = farm.getSelected() or {}
      suppressDropdown = true
      pcall(function() modelDropdown:Set(sel) end)
      suppressDropdown = false
    end

    local function refreshDropdownOptions()
      if not modelDropdown then return end
      local options = filteredList()
      suppressDropdown = true
      local ok = pcall(function() modelDropdown:Refresh(options, true) end)
      if not ok then
        pcall(function() modelDropdown:Set(options) end) -- fallback for old Rayfield forks
      end
      syncDropdownSelectionFromFarm()
      suppressDropdown = false
    end

    -- Search input (appears above dropdown)
    MainTab:CreateInput({
      Name = "Search Models",
      PlaceholderText = "Type model names to filter…",
      RemoveTextAfterFocusLost = false,
      Callback = function(text)
        currentSearch = tostring(text or "")
        refreshDropdownOptions()
      end,
    })

    modelDropdown = MainTab:CreateDropdown({
      Name = "Target Models (multi-select)",
      Options = filteredList(),
      CurrentOption = farm.getSelected() or {},
      MultipleOptions = true,
      Flag = "woodz_models",
      Callback = function(selection)
        if suppressDropdown then return end
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
        if handlers.onClearAll then handlers.onClearAll() end
        syncDropdownSelectionFromFarm()
        utils.notify("🌲 Preset", "Cleared all selections.", 3)
      end,
    })

    MainTab:CreateSection("Farming")
  else
    MainTab:CreateSection("Farming")
  end

  --------------------------------------------------------------------------
  -- Farming toggles + current target
  --------------------------------------------------------------------------
  local rfAutoFarm = MainTab:CreateToggle({
    Name = "Auto-Farm",
    CurrentValue = false,
    Flag = "woodz_auto_farm",
    Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
  })

  local rfSmartFarm = MainTab:CreateToggle({
    Name = "Smart Farm",
    CurrentValue = false,
    Flag = "woodz_smart_farm",
    Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
  })

  currentLabel = MainTab:CreateLabel("Current Target: None")

  --------------------------------------------------------------------------
  -- Options
  --------------------------------------------------------------------------
  OptionsTab:CreateSection("Merchants / Crates / AFK")

  local rfMerch1 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Chicleteiramania)",
    CurrentValue = false,
    Flag = "woodz_m1",
    Callback = function(v) if handlers.onToggleMerchant1 then handlers.onToggleMerchant1(v) end end,
  })

  local rfMerch2 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Bombardino Sewer)",
    CurrentValue = false,
    Flag = "woodz_m2",
    Callback = function(v) if handlers.onToggleMerchant2 then handlers.onToggleMerchant2(v) end end,
  })

  local rfCrates = OptionsTab:CreateToggle({
    Name = "Auto Open Crates",
    CurrentValue = false,
    Flag = "woodz_crates",
    Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
  })

  local rfAFK = OptionsTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Flag = "woodz_afk",
    Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
  })

  OptionsTab:CreateSection("Extras")

  OptionsTab:CreateButton({
    Name = "Redeem Unredeemed Codes",
    Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end,
  })

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

  local rfFastLvl = OptionsTab:CreateToggle({
    Name = "Instant Level 70+ (Sahur only)",
    CurrentValue = false,
    Flag = "woodz_fastlevel",
    Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
  })

  -- Optional HUD auto-hide (only if hud.lua exists)
  if ok_hud then
    local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local h1 = hud.findHUD(pg);         if h1 then hud.apply(h1, flags); hud.watch(h1, flags) end
    local h2 = hud.findHUD(StarterGui); if h2 then hud.apply(h2, flags); hud.watch(h2, flags) end
  end

  -- UI control facade for app.lua
  local UI = {
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Current Target: None") end) end,
    setAutoFarm      = function(on)   pcall(function() rfAutoFarm:Set(on and true or false) end) end,
    setSmartFarm     = function(on)   pcall(function() rfSmartFarm:Set(on and true or false) end) end,
    setMerchant1     = function(on)   pcall(function() rfMerch1:Set(on and true or false) end) end,
    setMerchant2     = function(on)   pcall(function() rfMerch2:Set(on and true or false) end) end,
    setCrates        = function(on)   pcall(function() rfCrates:Set(on and true or false) end) end,
    setAntiAFK       = function(on)   pcall(function() rfAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on)   pcall(function() rfFastLvl:Set(on and true or false) end) end,
    refreshModelOptions = function() if ok_farm then pcall(function() farm.getMonsterModels() end) end,
    syncModelSelection  = function() end,
    destroy          = function() pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  _G.__WOODZ_WINDOW_BUILT = UI
  return UI
end

return M
