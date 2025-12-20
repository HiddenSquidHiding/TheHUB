-- ui_rayfield.lua — Rayfield UI with per-player persistence (UserId-based)

local ok, Rayfield = pcall(function()
  return loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()
end)

if not ok or not Rayfield then
  warn("[ui_rayfield] Rayfield failed to load from URL")
  return {
    build = function()
      warn("[ui_rayfield] Rayfield failed to load")
      return {
        setCurrentTarget = function() end,
        setAutoFarm      = function() end,
        setSmartFarm     = function() end,
        setSahur         = function() end,
        setDungeonAuto   = function() end,
        setDungeonReplay = function() end,
        destroy          = function() end,
      }
    end
  }
end

local M = {}

function M.build(h)
  h = h or {}

  ------------------------------------------------------------------
  -- Per-player config filename
  ------------------------------------------------------------------
  local Players = game:GetService("Players")
  local lp = Players.LocalPlayer
  local uid = tostring(lp and lp.UserId or "guest")  -- e.g., 12345678
  -- If you prefer username instead of UserId, use:
  -- local uname = tostring(lp and lp.Name or "guest")

  ------------------------------------------------------------------
  -- Window (persistence enabled; per-account file)
  ------------------------------------------------------------------
  local Window = Rayfield:CreateWindow({
    Name            = "🌲 WoodzHUB — Rayfield",
    LoadingTitle    = "WoodzHUB",
    LoadingSubtitle = "Rayfield UI",
    KeySystem       = false,
    ConfigurationSaving = {
      Enabled    = true,
      FolderName = "WoodzHUB",
      FileName   = "settings_" .. uid,   -- per-account file, e.g. settings_12345678.json
      -- If using username instead: "settings_" .. uname
    },
  })

  local Main    = Window:CreateTab("Main")
  local Options = Window:CreateTab("Options")
  local Extra   = Window:CreateTab("Extra")

  ------------------------------------------------------------------
  -- Targets section (Search + Multi-select + Clear All)
  ------------------------------------------------------------------
  Main:CreateSection("Targets")

  local currentSearch = ""

  local function getOptions()
    if h.picker_getOptions then
      local ok2, list = pcall(h.picker_getOptions, currentSearch)
      if ok2 and type(list) == "table" then return list end
    end
    return {}
  end

  local function getSelected()
    if h.picker_getSelected then
      local ok2, sel = pcall(h.picker_getSelected)
      if ok2 and type(sel) == "table" then return sel end
    end
    return {}
  end

  local function setSelected(list)
    if h.picker_setSelected then
      pcall(h.picker_setSelected, list or {})
    end
  end

  local dropdown
  local function refreshDropdown()
    if not dropdown then return end
    local options = getOptions()
    local ok2 = pcall(function() dropdown:Refresh(options, true) end)
    if not ok2 then pcall(function() dropdown:Set(options) end) end
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
        for _, v in ipairs(selection) do
          if typeof(v) == "string" then table.insert(out, v) end
        end
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
    local togAF = Main:CreateToggle({
      Name = "Auto-Farm",
      CurrentValue = false,
      Callback = function(v) h.onAutoFarmToggle(v) end,
    })
    M.setAutoFarm = function(v) pcall(function() togAF:Set(v and true or false) end) end
  end

  if h.onSmartFarmToggle then
    local togSF = Main:CreateToggle({
      Name = "Smart Farm",
      CurrentValue = false,
      Callback = function(v) h.onSmartFarmToggle(v) end,
    })
    M.setSmartFarm = function(v) pcall(function() togSF:Set(v and true or false) end) end
  end

  ------------------------------------------------------------------
  -- Options
  ------------------------------------------------------------------
  Options:CreateSection("General")

  if h.onToggleAntiAFK then
    Options:CreateToggle({
      Name="Anti-AFK",
      CurrentValue=false,
      Callback=function(v) h.onToggleAntiAFK(v) end
    })
  end

  if h.onToggleMerchant1 then
    Options:CreateToggle({
      Name="Auto Buy Mythics (Chicleteiramania)",
      CurrentValue=false,
      Callback=function(v) h.onToggleMerchant1(v) end
    })
  end

  if h.onToggleMerchant2 then
    Options:CreateToggle({
      Name="Auto Buy Mythics (Bombardino Sewer)",
      CurrentValue=false,
      Callback=function(v) h.onToggleMerchant2(v) end
    })
  end

  if h.onToggleCrates then
    Options:CreateToggle({
      Name="Auto Open Crates",
      CurrentValue=false,
      Callback=function(v) h.onToggleCrates(v) end
    })
  end

  if h.onRedeemCodes then
    Options:CreateButton({
      Name="Redeem Unredeemed Codes",
      Callback=function() h.onRedeemCodes() end
    })
  end

  if h.onFastLevelToggle then
    Options:CreateToggle({
      Name="Instant Level 70+ (Sahur only)",
      CurrentValue=false,
      Callback=function(v) h.onFastLevelToggle(v) end
    })
  end

  -- Server Hopper button
  if h.onServerHopperToggle then
    Options:CreateButton({
      Name = "Server Hop",
      Callback = function() h.onServerHopperToggle() end
    })
  end

  -- Private Server button (solo.lua must define _G.TeleportToPrivateServer)
  if h.onPrivateServer then
    Options:CreateButton({
      Name = "Private Server",
      Callback = function() h.onPrivateServer() end
    })
  end

  -- Dungeon toggles (persisted)
  if h.onDungeonAutoToggle then
    local togAuto = Options:CreateToggle({
      Name = "Dungeon Auto-Attack",
      CurrentValue = false,
      Flag = "DungeonAuto",  -- ✅ persistence flag
      Callback = function(v)
        h.onDungeonAutoToggle(v)
        pcall(function() Rayfield:SaveConfiguration() end)
      end,
    })
    M.setDungeonAuto = function(v) pcall(function() togAuto:Set(v and true or false) end) end
  end

  if h.onDungeonReplayToggle then
    local togReplay = Options:CreateToggle({
      Name = "Dungeon Auto-Replay",
      CurrentValue = false,
      Flag = "DungeonReplay", -- ✅ persistence flag
      Callback = function(v)
        h.onDungeonReplayToggle(v)
        pcall(function() Rayfield:SaveConfiguration() end)
      end,
    })
    M.setDungeonReplay = function(v) pcall(function() togReplay:Set(v and true or false) end) end
  end

  ------------------------------------------------------------------
  -- Extra
  ------------------------------------------------------------------
  Extra:CreateSection("General")

  -- Sahur auto-hop (persisted)
  if h.onSahurToggle then
    local togSahur = Extra:CreateToggle({
      Name = "Auto Sahur (Auto-Hop)",
      CurrentValue = false,
      Flag = "AutoSahur", -- ✅ persistence flag
      Callback = function(enabled)
        if h and h.onSahurToggle then
          h.onSahurToggle(enabled)
        end
        pcall(function() Rayfield:SaveConfiguration() end)
      end,
    })
    M.setSahur = function(v) pcall(function() togSahur:Set(v and true or false) end) end
  end

  ------------------------------------------------------------------
  -- Exposed helpers
  ------------------------------------------------------------------
  M.setCurrentTarget = function(text)
    pcall(function() lbl:Set(text or "Current Target: None") end)
  end

  M.destroy = function()
    pcall(function() Rayfield:Destroy() end)
  end

  ------------------------------------------------------------------
  -- Persistence restore (must run AFTER all controls are created)
  ------------------------------------------------------------------
  pcall(function() Rayfield:LoadConfiguration() end)

  local function getFlagBool(name)
    local f = Rayfield.Flags and Rayfield.Flags[name]
    return f and ((f.CurrentValue ~= nil and f.CurrentValue) or f.Value or f.Enabled) or false
  end

  task.defer(function()
    -- Sahur
    if getFlagBool("AutoSahur") then
      if M.setSahur then pcall(function() M.setSahur(true) end) end
      if h.onSahurToggle then pcall(function() h.onSahurToggle(true) end) end
    end



     -- Auto-Farm
    if getFlagBool("Auto-Farm") then
      if M.setAutoFarm then pcall(function() M.setAutoFarm(true) end) end
      if h.onAutoFarmToggle then pcall(function() h.onAutoFarmToggle(true) end) end
    end


    
    -- Dungeon Auto-Attack
    if getFlagBool("DungeonAuto") then
      if M.setDungeonAuto then pcall(function() M.setDungeonAuto(true) end) end
      if h.onDungeonAutoToggle then pcall(function() h.onDungeonAutoToggle(true) end) end
    end

    -- Dungeon Auto-Replay
    if getFlagBool("DungeonReplay") then
      if M.setDungeonReplay then pcall(function() M.setDungeonReplay(true) end) end
      if h.onDungeonReplayToggle then pcall(function() h.onDungeonReplayToggle(true) end) end
    end
  end)

  return M
end

return M
