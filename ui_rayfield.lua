-- ui_rayfield.lua
-- Single-instance Rayfield UI for WoodzHUB
-- Exposes build(handlers, uiFlags) and returns a stable UI handle

-- Safe utils (works in executor context)
local function getUtils()
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function() end }
end
local utils = getUtils()

-- Global guard: if UI already exists, return it
if _G.WOODZHUB_RAYFIELD_UI and type(_G.WOODZHUB_RAYFIELD_UI) == "table" then
  return _G.WOODZHUB_RAYFIELD_UI
end

-- Lazy Rayfield load
local okRF, Rayfield = pcall(function()
  return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)
if not okRF or not Rayfield then
  warn("[ui_rayfield] Rayfield failed to load")
  return {
    build = function() return {
      setCurrentTarget = function() end,
      setAutoFarm = function() end,
      setSmartFarm = function() end,
      setMerchant1 = function() end,
      setMerchant2 = function() end,
      setCrates = function() end,
      setAntiAFK = function() end,
      setFastLevel = function() end,
      refreshModelOptions = function() end,
      syncModelSelection = function() end,
      destroy = function() end,
    } end
  }
end

-- Singleton state
local SINGLETON = {
  windowBuilt = false,
  UI = nil,
}

local function truthy(x) return x == nil or x == true end

local M = {}

function M.build(handlers, uiFlags)
  handlers = handlers or {}
  uiFlags = uiFlags or {}

  -- If already built, just return the same handle
  if SINGLETON.windowBuilt and SINGLETON.UI then
    return SINGLETON.UI
  end

  -- Window
  local Window = Rayfield:CreateWindow({
    Name                = "🌲 WoodzHUB",
    LoadingTitle        = "WoodzHUB",
    LoadingSubtitle     = "Rayfield UI",
    ConfigurationSaving = { Enabled = false, FolderName = "WoodzHUB", FileName = "Rayfield" },
    KeySystem           = false,
  })

  -- Tabs
  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  --------------------------------------------------------------------
  -- MAIN TAB
  --------------------------------------------------------------------
  MainTab:CreateSection("Farming")

  -- Auto-Farm
  local rfAutoFarm
  if truthy(uiFlags.autoFarm) then
    rfAutoFarm = MainTab:CreateToggle({
      Name = "Auto-Farm",
      CurrentValue = false,
      Flag = "woodz_auto_farm",
      Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
    })
  end

  -- Smart Farm
  local rfSmartFarm
  if truthy(uiFlags.smartFarm) then
    rfSmartFarm = MainTab:CreateToggle({
      Name = "Smart Farm",
      CurrentValue = false,
      Flag = "woodz_smart_farm",
      Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
    })
  end

  -- Current Target label
  local currentLabel = MainTab:CreateLabel("Current Target: None")

  --------------------------------------------------------------------
  -- OPTIONS TAB
  --------------------------------------------------------------------
  OptionsTab:CreateSection("Merchants / Crates / AFK")

  local rfMerch1, rfMerch2, rfCrates, rfAFK, rfFastLvl

  if truthy(uiFlags.merchants) then
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

  if truthy(uiFlags.crates) then
    rfCrates = OptionsTab:CreateToggle({
      Name = "Auto Open Crates",
      CurrentValue = false,
      Flag = "woodz_crates",
      Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
    })
  end

  if truthy(uiFlags.antiAFK) then
    rfAFK = OptionsTab:CreateToggle({
      Name = "Anti-AFK",
      CurrentValue = false,
      Flag = "woodz_afk",
      Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
    })
  end

  OptionsTab:CreateSection("Extras")

  if truthy(uiFlags.redeemCodes) then
    OptionsTab:CreateButton({
      Name = "Redeem Unredeemed Codes",
      Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end,
    })
  end

  if truthy(uiFlags.privateServer) then
    OptionsTab:CreateButton({
      Name = "Private Server",
      Callback = function()
        task.spawn(function()
          if type(_G.TeleportToPrivateServer) ~= "function" then
            utils.notify("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
            return
          end
          local ok, err = pcall(_G.TeleportToPrivateServer)
          if ok then utils.notify("🌲 Private Server", "Teleport initiated!", 3)
          else utils.notify("🌲 Private Server", "Failed: " .. tostring(err), 5) end
        end)
      end,
    })
  end

  if truthy(uiFlags.fastlevel) then
    rfFastLvl = OptionsTab:CreateToggle({
      Name = "Instant Level 70+ (Sahur only)",
      CurrentValue = false,
      Flag = "woodz_fastlevel",
      Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
    })
  end

  --------------------------------------------------------------------
  -- Stable UI handle exposed to app.lua
  --------------------------------------------------------------------
  local UI = {
    setCurrentTarget = function(text)
      pcall(function() currentLabel:Set(text or "Current Target: None") end)
    end,
    setAutoFarm  = function(on) if rfAutoFarm then pcall(function() rfAutoFarm:Set(on and true or false) end) end end,
    setSmartFarm = function(on) if rfSmartFarm then pcall(function() rfSmartFarm:Set(on and true or false) end) end end,
    setMerchant1 = function(on) if rfMerch1 then pcall(function() rfMerch1:Set(on and true or false) end) end end,
    setMerchant2 = function(on) if rfMerch2 then pcall(function() rfMerch2:Set(on and true or false) end) end end,
    setCrates    = function(on) if rfCrates then pcall(function() rfCrates:Set(on and true or false) end) end end,
    setAntiAFK   = function(on) if rfAFK then pcall(function() rfAFK:Set(on and true or false) end) end end,
    setFastLevel = function(on) if rfFastLvl then pcall(function() rfFastLvl:Set(on and true or false) end) end end,
    refreshModelOptions = function() end, -- (no picker in this file version)
    syncModelSelection  = function() end,
    destroy = function() pcall(function() Rayfield:Destroy() end) end,
  }

  SINGLETON.windowBuilt = true
  SINGLETON.UI = UI
  _G.WOODZHUB_RAYFIELD_UI = UI

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
