-- ui_rayfield.lua (Rayfield overlay only; no HUD touches)
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function() end }
end

local utils     = getUtils()
local constants = require(script.Parent.constants)
local farm      = require(script.Parent.farm)

local Players   = game:GetService("Players")

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local M = {}

function M.build(handlers)
  handlers = handlers or {}

  local Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — Rayfield",
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
  })

  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  -- Targets
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

  local dd; local suppress = false
  local function syncFromFarm()
    if not dd then return end
    local sel = farm.getSelected() or {}
    suppress = true; pcall(function() dd:Set(sel) end); suppress = false
  end
  local function refreshDD()
    if not dd then return end
    local opts = filteredList()
    suppress = true
    local ok = pcall(function() dd:Refresh(opts, true) end)
    if not ok then pcall(function() dd:Set(opts) end) end
    syncFromFarm()
    suppress = false
  end

  MainTab:CreateInput({
    Name = "Search Models",
    PlaceholderText = "Type model names to filter…",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
      currentSearch = tostring(text or "")
      refreshDD()
    end,
  })

  dd = MainTab:CreateDropdown({
    Name = "Target Models (multi-select)",
    Options = filteredList(),
    CurrentOption = farm.getSelected() or {},
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

  MainTab:CreateButton({
    Name = "Clear All Selections",
    Callback = function()
      if handlers.onClearAll then handlers.onClearAll() end
      syncFromFarm()
      utils.notify("🌲 Preset", "Cleared all selections.", 3)
    end,
  })

  -- Farming
  MainTab:CreateSection("Farming")

  local tAuto = MainTab:CreateToggle({
    Name = "Auto-Farm",
    CurrentValue = false,
    Flag = "woodz_auto_farm",
    Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
  })
  local tSmart = MainTab:CreateToggle({
    Name = "Smart Farm",
    CurrentValue = false,
    Flag = "woodz_smart_farm",
    Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
  })

  local lbl = MainTab:CreateLabel("Current Target: None")

  -- Options
  OptionsTab:CreateSection("Merchants / Crates / AFK")
  local tM1 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Chicleteiramania)",
    CurrentValue = false,
    Callback = function(v) if handlers.onToggleMerchant1 then handlers.onToggleMerchant1(v) end end,
  })
  local tM2 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Bombardino Sewer)",
    CurrentValue = false,
    Callback = function(v) if handlers.onToggleMerchant2 then handlers.onToggleMerchant2(v) end end,
  })
  local tCr = OptionsTab:CreateToggle({
    Name = "Auto Open Crates",
    CurrentValue = false,
    Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
  })
  local tAFK = OptionsTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
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
        if ok then utils.notify("🌲 Private Server","Teleport initiated to private server!",3)
        else utils.notify("🌲 Private Server","Failed to teleport: "..tostring(err),5) end
      end)
    end,
  })
  local tFL = OptionsTab:CreateToggle({
    Name = "Instant Level 70+ (Sahur only)",
    CurrentValue = false,
    Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
  })

  -- expose to app.lua
  return {
    setCurrentTarget = function(text) pcall(function() lbl:Set(text or "Current Target: None") end) end,
    setAutoFarm      = function(on) pcall(function() tAuto:Set(on and true or false) end) end,
    setSmartFarm     = function(on) pcall(function() tSmart:Set(on and true or false) end) end,
    setMerchant1     = function(on) pcall(function() tM1:Set(on and true or false) end) end,
    setMerchant2     = function(on) pcall(function() tM2:Set(on and true or false) end) end,
    setCrates        = function(on) pcall(function() tCr:Set(on and true or false) end) end,
    setAntiAFK       = function(on) pcall(function() tAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on) pcall(function() tFL:Set(on and true or false) end) end,

    refreshModelOptions = function() refreshDD() end,
    syncModelSelection  = function() syncFromFarm() end,
    destroy             = function() pcall(function() Rayfield:Destroy() end) end,
  }
end

return M
