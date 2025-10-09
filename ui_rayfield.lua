-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (model picker, single "Clear All" button under picker, toggles, status).
-- Calls back into app.lua via the handlers you pass to build().

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function(_,_) end }
end

local utils     = getUtils()
local constants = require(script.Parent.constants)
local hud       = require(script.Parent.hud)
local farm      = require(script.Parent.farm)

local Players    = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local CoreGui    = game:GetService("CoreGui")

local Rayfield  = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local M = {}

function M.build(handlers)
  handlers = handlers or {}

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
  -- Targets: Search + Multi-select + Clear All (right under dropdown)
  --------------------------------------------------------------------------
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

  local function getSelected()
    local sel = farm.getSelected() or {}
    local cleaned = {}
    for _, v in ipairs(sel) do
      if typeof(v) == "string" then table.insert(cleaned, v) end
    end
    return cleaned
  end

  -- ===== Dropdown internals helpers =====
  local function _dropdownRoot(obj)
    if typeof(obj) == "table" then
      for _, k in ipairs({ "Dropdown", "Frame", "Holder", "Instance", "Object", "Root" }) do
        local v = rawget(obj, k)
        if typeof(v) == "Instance" and v:IsA("Frame") then return v end
      end
    end
    return nil
  end

  local function _isDropdownOpen(obj)
    local ok, isOpen = pcall(function() return obj and obj.Opened end)
    if ok and type(isOpen) == "boolean" then return isOpen end
    local ok2, res2 = pcall(function() return obj:IsOpen() end)
    if ok2 and type(res2) == "boolean" then return res2 end
    local root = _dropdownRoot(obj)
    if root then
      for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ScrollingFrame") and d.Visible and d.AbsoluteSize.Y > 0 then
          return true
        end
      end
    end
    return false
  end

  local function _clickAnyButton(root)
    if not root then return false end
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("TextButton") or d:IsA("ImageButton") then
        local ok = pcall(function() d:Activate() end)
        if ok then return true end
      end
    end
    return false
  end

  local function _openDropdown(obj)
    if not obj then return end
    local ok = pcall(function() if obj.Open then obj:Open() end end)
    if ok then return end
    _clickAnyButton(_dropdownRoot(obj))
  end

  local function _closeDropdown(obj)
    if not obj then return end
    local ok = pcall(function() if obj.Close then obj:Close() end end)
    if ok then return end
    -- Try toggling by clicking header again
    if _clickAnyButton(_dropdownRoot(obj)) then return end
    -- Last resort: flicker visibility to force rebuild
    local root = _dropdownRoot(obj)
    if root then
      root.Visible = false
      task.wait()
      root.Visible = true
    end
  end

  -- To avoid constant rebuilds, only refresh when options changed
  local function optionsSignature(options)
    local n = #options
    local parts = table.create(n)
    for i=1,n do parts[i] = options[i] end
    return table.concat(parts, "\0")
  end

  local modelDropdown
  local suppressDropdown = false
  local lastOptionsSig = ""

  local function syncDropdownSelectionFromFarm()
    if not modelDropdown then return end
    suppressDropdown = true
    pcall(function() modelDropdown:Set(getSelected()) end)
    suppressDropdown = false
  end

  local function refreshDropdownOptions()
    if not modelDropdown then return end
    local options  = filteredList()
    local selected = getSelected()

    local sig = optionsSignature(options)
    local wasOpen = _isDropdownOpen(modelDropdown)

    -- If it’s open, force-close first so Rayfield rebuilds visible rows properly.
    if wasOpen then _closeDropdown(modelDropdown) end

    if sig ~= lastOptionsSig then
      lastOptionsSig = sig
      suppressDropdown = true
      local ok = pcall(function() modelDropdown:Refresh(options, selected) end)
      if not ok then
        pcall(function() modelDropdown:Refresh(options) end)
        pcall(function() modelDropdown:Set(selected) end)
      end
      suppressDropdown = false
    else
      -- Options unchanged; just keep selection in sync.
      suppressDropdown = true
      pcall(function() modelDropdown:Set(selected) end)
      suppressDropdown = false
    end

    -- If it was open before, re-open after refresh.
    if wasOpen then
      task.defer(function() _openDropdown(modelDropdown) end)
    end
  end

  local SEARCH_PLACEHOLDER = "Type model names to filter…"
  local searchInputObj = MainTab:CreateInput({
    Name = "Search Models",
    PlaceholderText = SEARCH_PLACEHOLDER,
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
      currentSearch = tostring(text or "")
      refreshDropdownOptions()
    end,
  })

  -- Attach LIVE typing updates
  task.spawn(function()
    local function tryGetTextBoxFromReturn(obj)
      if typeof(obj) == "table" then
        for _, key in ipairs({ "Input", "TextBox", "Box", "Instance", "Object" }) do
          local v = rawget(obj, key)
          if typeof(v) == "Instance" and v:IsA("TextBox") then
            return v
          end
        end
      end
      return nil
    end

    local tb = tryGetTextBoxFromReturn(searchInputObj)
    if not tb then
      for _=1,20 do
        for _, root in ipairs({ CoreGui, Players.LocalPlayer:FindFirstChildOfClass("PlayerGui") }) do
          if root then
            for _, d in ipairs(root:GetDescendants()) do
              if d:IsA("TextBox") and d.PlaceholderText == SEARCH_PLACEHOLDER then
                tb = d; break
              end
            end
          end
          if tb then break end
        end
        if tb then break end
        task.wait(0.05)
      end
    end

    if tb then
      tb:GetPropertyChangedSignal("Text"):Connect(function()
        currentSearch = tostring(tb.Text or "")
        refreshDropdownOptions()
      end)
    end
  end)

  modelDropdown = MainTab:CreateDropdown({
    Name = "Target Models (multi-select)",
    Options = filteredList(),
    CurrentOption = getSelected(),
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
      -- no Set() here (prevents re-entry)
    end,
  })

  -- Initial sync
  lastOptionsSig = optionsSignature(filteredList())
  task.defer(syncDropdownSelectionFromFarm)

  -- 👉 Single button directly under the dropdown
  MainTab:CreateButton({
    Name = "Clear All Selections",
    Callback = function()
      if handlers.onClearAll then
        handlers.onClearAll()
      else
        farm.setSelected({})
      end
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Cleared all selections.", 3)
    end,
  })

  --------------------------------------------------------------------------
  -- Farming toggles + current target
  --------------------------------------------------------------------------
  MainTab:CreateSection("Farming")

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

  local currentLabel = MainTab:CreateLabel("Current Target: None")

  --------------------------------------------------------------------------
  -- Options: merchants / crates / AFK + extras
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
        local success, err = pcall(_G.TeleportToPrivateServer)
        if success then
          utils.notify("🌲 Private Server", "Teleport initiated to private server!", 3)
        else
          utils.notify("🌲 Private Server", "Failed to teleport: " .. tostring(err), 5)
        end
      end)
    end,
  })

  local rfFastLvl = OptionsTab:CreateToggle({
    Name = "Instant Level 70+ (Sahur only)",
    CurrentValue = false,
    Flag = "woodz_fastlevel",
    Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
  })

  --------------------------------------------------------------------------
  -- Optional: HUD auto-hide (same behavior you had before)
  --------------------------------------------------------------------------
  do
    local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local h1 = hud.findHUD(pg);         if h1 then hud.apply(h1, flags); hud.watch(h1, flags) end
    local h2 = hud.findHUD(StarterGui); if h2 then hud.apply(h2, flags); hud.watch(h2, flags) end
  end

  --------------------------------------------------------------------------
  -- Expose minimal UI control to app.lua
  --------------------------------------------------------------------------
  local UI = {
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Current Target: None") end) end,
    setAutoFarm      = function(on)   pcall(function() rfAutoFarm:Set(on and true or false) end) end,
    setSmartFarm     = function(on)   pcall(function() rfSmartFarm:Set(on and true or false) end) end,
    setMerchant1     = function(on)   pcall(function() rfMerch1:Set(on and true or false) end) end,
    setMerchant2     = function(on)   pcall(function() rfMerch2:Set(on and true or false) end) end,
    setCrates        = function(on)   pcall(function() rfCrates:Set(on and true or false) end) end,
    setAntiAFK       = function(on)   pcall(function() rfAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on)   pcall(function() rfFastLvl:Set(on and true or false) end) end,

    refreshModelOptions = function() refreshDropdownOptions() end,
    syncModelSelection  = function() syncDropdownSelectionFromFarm() end,

    destroy          = function() pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
