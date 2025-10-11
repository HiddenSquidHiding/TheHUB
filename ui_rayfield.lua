-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (model picker with live search), single "Clear All" button, toggles, status.

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
  -- Targets: Search + Multi-select + Clear All
  --------------------------------------------------------------------------
  MainTab:CreateSection("Targets")

  -- Cache the full list once; we’ll filter locally to avoid side-effects.
  local allModels = {}
  pcall(function() allModels = farm.getMonsterModels() or {} end)

  -- If it came back empty (e.g., early load), retry shortly once.
  if #allModels == 0 then
    task.delay(1, function()
      local ok, list = pcall(function() return farm.getMonsterModels() end)
      if ok and type(list) == "table" then allModels = list end
    end)
  end

  -- Filtering (local, side-effect free)
  local function filteredList(search)
    search = tostring(search or ""):lower()
    if search == "" then return table.clone(allModels) end
    local out = {}
    for _, name in ipairs(allModels) do
      if typeof(name) == "string" and string.find(name:lower(), search, 1, true) then
        table.insert(out, name)
      end
    end
    return out
  end

  local function selectedList()
    local sel = farm.getSelected() or {}
    local out = {}
    for _, v in ipairs(sel) do if typeof(v) == "string" then table.insert(out, v) end end
    return out
  end

  local function toSet(t)
    local s = {}
    for _, v in ipairs(t or {}) do s[v] = true end
    return s
  end

  -- ——— Dropdown (we recreate it on each search) ———
  local currentSearch = ""
  local modelDropdown = nil
  local suppress = false

  local function dd_root(drop)
    if typeof(drop) ~= "table" then return nil end
    for _, k in ipairs({ "Dropdown", "Frame", "Holder", "Instance", "Object", "Root" }) do
      local v = rawget(drop, k)
      if typeof(v) == "Instance" and v:IsA("Frame") then return v end
    end
    return nil
  end

  local function dd_destroy(drop)
    if not drop then return end
    -- Try official Destroy
    local ok = pcall(function() if drop.Destroy then drop:Destroy() end end)
    if ok then return end
    -- Fallback: destroy the root instance
    local root = dd_root(drop)
    if root and root.Parent then
      pcall(function() root:Destroy() end)
    end
  end

  local function dd_is_open(drop)
    if not drop then return false end
    local ok, opened = pcall(function() return drop.Opened end)
    if ok and type(opened) == "boolean" then return opened end
    local ok2, res2 = pcall(function() return drop:IsOpen() end)
    if ok2 and type(res2) == "boolean" then return res2 end
    -- Heuristic: visible scrolling frame under root
    local root = dd_root(drop)
    if root then
      for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ScrollingFrame") and d.Visible and d.AbsoluteSize.Y > 0 then return true end
      end
    end
    return false
  end

  local function dd_open(drop)
    if not drop then return end
    pcall(function() if drop.Open then drop:Open() end end)
    local root = dd_root(drop)
    if root then
      for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("TextButton") or d:IsA("ImageButton") then
          pcall(function() d:Activate() end)
          break
        end
      end
    end
  end

  local function createDropdown(options, selected)
    return MainTab:CreateDropdown({
      Name = "Target Models (multi-select)",
      Options = options,
      CurrentOption = selected,
      MultipleOptions = true,
      Flag = "woodz_models",
      Callback = function(selection)
        if suppress then return end
        local list = {}
        if typeof(selection) == "table" then
          for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(list, v) end end
        elseif typeof(selection) == "string" then
          table.insert(list, selection)
        end
        farm.setSelected(list)
      end,
    })
  end

  local function rebuildDropdown()
    local wasOpen = dd_is_open(modelDropdown)
    local options  = filteredList(currentSearch)
    local selected = selectedList()

    -- Keep selection only for items still present after filter
    local optSet = toSet(options)
    local keep = {}
    for _, v in ipairs(selected) do if optSet[v] then table.insert(keep, v) end end

    -- Destroy old dropdown cleanly, then create a fresh one
    dd_destroy(modelDropdown)
    suppress = true
    modelDropdown = createDropdown(options, keep)
    suppress = false

    if wasOpen then task.defer(function() dd_open(modelDropdown) end) end
  end

  -- Initial dropdown
  modelDropdown = createDropdown(filteredList(""), selectedList())

  -- Search input (ALWAYS rebuild in callback so it works even if we can't hook TextBox)
  local SEARCH_PLACEHOLDER = "Type model names to filter…"
  local searchInput = MainTab:CreateInput({
    Name = "Search Models",
    PlaceholderText = SEARCH_PLACEHOLDER,
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
      currentSearch = tostring(text or "")
      rebuildDropdown()
    end,
  })

  -- Try to also hook live typing (nice-to-have; callback above already works)
  task.spawn(function()
    local function tryGetTextBox(obj)
      if typeof(obj) == "table" then
        for _, key in ipairs({ "Input", "TextBox", "Box", "Instance", "Object" }) do
          local v = rawget(obj, key)
          if typeof(v) == "Instance" and v:IsA("TextBox") then return v end
        end
      end
      return nil
    end
    local tb = tryGetTextBox(searchInput)
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
        rebuildDropdown()
      end)
    end
  end)

  -- Clear button directly under dropdown
  MainTab:CreateButton({
    Name = "Clear All Selections",
    Callback = function()
      if handlers.onClearAll then handlers.onClearAll() else farm.setSelected({}) end
      suppress = true
      pcall(function() if modelDropdown and modelDropdown.Set then modelDropdown:Set({}) end end)
      suppress = false
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
  -- Optional: HUD auto-hide
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

    -- If your code wants to refresh available models from Workspace (e.g., after map change):
    refreshModelOptions = function()
      local ok, list = pcall(function() return farm.getMonsterModels() end)
      if ok and type(list) == "table" then
        allModels = list
        rebuildDropdown()
      end
    end,

    -- Sync UI selection from farm
    syncModelSelection  = function()
      suppress = true
      pcall(function() if modelDropdown and modelDropdown.Set then modelDropdown:Set(selectedList()) end end)
      suppress = false
    end,

    destroy          = function() pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
