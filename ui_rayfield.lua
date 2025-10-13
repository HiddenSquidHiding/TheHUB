-- ui_rayfield.lua (minimal)
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local M = {}

function M.build(handlers)
  handlers = handlers or {}

  local Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — Rayfield",
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = { Enabled = false, FolderName = "WoodzHUB", FileName = "Rayfield" },
    KeySystem = false,
  })

  local Main   = Window:CreateTab("Main")
  local Opt    = Window:CreateTab("Options")

  Main:CreateSection("Targets")
  -- simple picker substitute (no data yet)
  local label = Main:CreateLabel("Use your full farm.lua later for model picker.")

  Main:CreateSection("Farming")
  local tgAuto = Main:CreateToggle({
    Name = "Auto-Farm",
    CurrentValue = false,
    Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end
  })
  local tgSmart = Main:CreateToggle({
    Name = "Smart Farm",
    CurrentValue = false,
    Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end
  })
  local currentLbl = Main:CreateLabel("Current Target: None")

  Opt:CreateSection("Options")
  Opt:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end
  })
  Opt:CreateButton({
    Name = "Redeem Unredeemed Codes",
    Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end
  })
  Opt:CreateToggle({
    Name = "Instant Level 70+ (Sahur only)",
    CurrentValue = false,
    Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end
  })

  -- Expose tiny control surface app.lua expects
  return {
    setCurrentTarget = function(txt) pcall(function() currentLbl:Set(txt or "Current Target: None") end) end,
    setAutoFarm      = function(on)  pcall(function() tgAuto:Set(on and true or false) end) end,
    setSmartFarm     = function(on)  pcall(function() tgSmart:Set(on and true or false) end) end,
    destroy          = function() pcall(function() Rayfield:Destroy() end) end,
  }
end

return M
