-- ui_rayfield.lua — Rayfield UI with live-search model picker + Clear All.

local ok, Rayfield = pcall(function()
  return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not ok or not Rayfield then
  return {
    build = function()
      warn("[ui_rayfield] Rayfield failed to load")
      return { setCurrentTarget=function()end, setAutoFarm=function()end }
    end
  }
end

local M = {}

function M.build(h)
  h = h or {}

  local Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — Rayfield",
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
  })

  local Main    = Window:CreateTab("Main")
  local Options = Window:CreateTab("Options")

  ------------------------------------------------------------------
  -- Targets section (Search + Multi-select + Clear All)
  ------------------------------------------------------------------
  Main:CreateSection("Targets")

  local currentSearch = ""

  local function getOptions()
    if h.picker_getOptions then
      local ok, list = pcall(h.picker_getOptions, currentSearch)
      if ok and type(list) == "table" then return list end
    end
    return {}
  end

  local function getSelected()
    if h.picker_getSelected then
      local ok, sel = pcall(h.picker_getSelected)
      if ok and type(sel) == "table" then return sel end
    end
    return {}
  end

  local function setSelected(list)
    if h.picker_setSelected then pcall(h.picker_setSelected, list or {}) end
  end

  local dropdown
  local function refreshDropdown()
    if not dropdown then return end
    local options = getOptions()
    local ok = pcall(function() dropdown:Refresh(options, true) end)
    if not ok then pcall(function() dropdown:Set(options) end) end
  end

  Main:CreateInput({
    Name = "Search Models",
    PlaceholderText = "Type to filter…",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
      currentSearch = tostring(text or "")
      refreshDropdown()
    end,
  })

  dropdown = Main:CreateDropdown({
    Name = "Target Models (multi-select)",
    Options = getOptions(),
    CurrentOption = getSelected(),
    MultipleOptions = true,
    Callback = function(selection)
      local out = {}
      if typeof(selection) == "table" then
        for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(out, v) end end
      elseif typeof(selection) == "string" then
        table.insert(out, selection)
      end
      setSelected(out)
    end,
  })

  Main:CreateButton({
    Name = "Clear All Selections",
    Callback = function()
      if h.picker_clear then pcall(h.picker_clear) end
      pcall(function() dropdown:Set({}) end)
    end,
  })

  ------------------------------------------------------------------
  -- Farming
  ------------------------------------------------------------------
  Main:CreateSection("Farming")

  local lbl = Main:CreateLabel("Current Target: None")

  if h.onAutoFarmToggle then
    local tog = Main:CreateToggle({
      Name = "Auto-Farm",
      CurrentValue = false,
      Callback = function(v) h.onAutoFarmToggle(v) end,
    })
    M.setAutoFarm = function(v) pcall(function() tog:Set(v and true or false) end) end
  end

  if h.onSmartFarmToggle then
    local tog = Main:CreateToggle({
      Name = "Smart Farm",
      CurrentValue = false,
      Callback = function(v) h.onSmartFarmToggle(v) end,
    })
    M.setSmartFarm = function(v) pcall(function() tog:Set(v and true or false) end) end
  end

  ------------------------------------------------------------------
  -- Options
  ------------------------------------------------------------------
  Options:CreateSection("General")

  if h.onToggleAntiAFK then
    Options:CreateToggle({ Name="Anti-AFK", CurrentValue=false, Callback=function(v) h.onToggleAntiAFK(v) end })
  end
  if h.onToggleMerchant1 then
    Options:CreateToggle({ Name="Auto Buy Mythics (Chicleteiramania)", CurrentValue=false, Callback=function(v) h.onToggleMerchant1(v) end })
  end
  if h.onToggleMerchant2 then
    Options:CreateToggle({ Name="Auto Buy Mythics (Bombardino Sewer)", CurrentValue=false, Callback=function(v) h.onToggleMerchant2(v) end })
  end
  if h.onToggleCrates then
    Options:CreateToggle({ Name="Auto Open Crates", CurrentValue=false, Callback=function(v) h.onToggleCrates(v) end })
  end
  if h.onRedeemCodes then
    Options:CreateButton({ Name="Redeem Unredeemed Codes", Callback=function() h.onRedeemCodes() end })
  end
  if h.onFastLevelToggle then
    Options:CreateToggle({ Name="Instant Level 70+ (Sahur only)", CurrentValue=false, Callback=function(v) h.onFastLevelToggle(v) end })
  end

  -- 🔹 Private Server button (uses solo.lua -> _G.TeleportToPrivateServer)
  if h.onPrivateServer then
    Options:CreateButton({ Name = "Private Server", Callback = function() h.onPrivateServer() end })
  end

  -- Dungeon toggles (if provided)
  if h.onDungeonAutoToggle then
    Options:CreateToggle({ Name="Dungeon Auto-Attack", CurrentValue=false, Callback=function(v) h.onDungeonAutoToggle(v) end })
  end
  if h.onDungeonReplayToggle then
    Options:CreateToggle({ Name="Dungeon Auto-Replay", CurrentValue=false, Callback=function(v) h.onDungeonReplayToggle(v) end })
  end

  -- exposed helpers
  M.setCurrentTarget = function(text) pcall(function() lbl:Set(text or "Current Target: None") end) end
  M.destroy = function() pcall(function() Rayfield:Destroy() end) end

  return M
end

return M
