-- app.lua
-- Profile-aware boot that selects modules & UI per game/place via games.lua

----------------------------------------------------------------------
-- 1) Safe utils
----------------------------------------------------------------------
local function getUtils()
  local p = script and script.Parent
  if p and typeof(p) == "Instance" and p:FindFirstChild("_deps") and p._deps:FindFirstChild("utils") then
    return require(p._deps.utils)
  end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return {
    notify = function(_,_) end,
    waitForCharacter = function()
      local Players = game:GetService('Players')
      local plr = Players.LocalPlayer
      while not (plr and plr.Character and plr.Character:FindFirstChild('HumanoidRootPart') and plr.Character:FindFirstChildOfClass('Humanoid')) do
        plr.CharacterAdded:Wait(); task.wait(0.05)
      end
      return plr.Character
    end,
  }
end
local utils = getUtils()

----------------------------------------------------------------------
-- 2) Safe sibling require helpers (Instance or table registry)
----------------------------------------------------------------------
local function siblingsRegistry()
  -- if your loader registered a virtual sibling map, use it
  local reg = rawget(getfenv(), "__WOODZ_SIBLINGS")
  return (type(reg) == "table") and reg or nil
end

local function findSibling(name)
  -- prefer real Instances
  local p = script and rawget(script, "Parent")
  if typeof(p) == "Instance" then
    return p:FindFirstChild(name)
  end
  -- fallback: table registry the loader might have created
  local reg = siblingsRegistry()
  if reg and reg[name] then
    return reg[name]
  end
  return nil
end

local function tryRequireSibling(name, required)
  local inst = findSibling(name)
  if not inst then
    if required then
      warn(("[app.lua] required module '%s' missing next to app.lua"):format(name))
    else
      warn(("[app.lua] optional module '%s' not available"):format(name))
    end
    return nil
  end
  local ok, mod = pcall(function() return require(inst) end)
  if not ok then
    warn(("[app.lua] failed to require '%s': %s"):format(name, tostring(mod)))
    return nil
  end
  return mod
end

----------------------------------------------------------------------
-- 3) Load games.lua and pick a profile by place or universe
----------------------------------------------------------------------
local function loadGamesConfig()
  local games = tryRequireSibling("games", false)
  if type(games) ~= "table" then
    warn("[app.lua] games.lua missing or invalid; falling back to default")
    games = {
      default = {
        name = "Generic",
        modules = { "anti_afk" },
        ui = {
          modelPicker=false, currentTarget=false,
          autoFarm=false, smartFarm=false,
          merchants=false, crates=false, antiAFK=true,
          redeemCodes=false, fastlevel=false, privateServer=false,
          dungeon=false,
        },
      }
    }
  end
  return games
end

local function chooseProfile(games)
  local placeKey = "place:" .. tostring(game.PlaceId)
  local gameKey  = tostring(game.GameId)
  local profile  = games[placeKey] or games[gameKey] or games.default

  if not profile then
    profile = {
      name = "Fallback",
      modules = { "anti_afk" },
      ui = { antiAFK = true }
    }
  end

  print(("[app.lua] profile: %s (key=%s%s)"):format(
    tostring(profile.name or "unnamed"),
    games[placeKey] and placeKey or (games[gameKey] and gameKey or "default"),
    games[placeKey] and "" or (games[gameKey] and "" or " (default)")
  ))
  return profile
end

----------------------------------------------------------------------
-- 4) Boot per profile: load modules that exist
----------------------------------------------------------------------
local function boot()
  local games = loadGamesConfig()
  local profile = chooseProfile(games)
  local uiFlags = profile.ui or {}

  -- Resolve modules
  local loaded = {}

  for _, modName in ipairs(profile.modules or {}) do
    local m = tryRequireSibling(modName, false)
    if m then
      loaded[modName] = m
      print(("[app.lua] loaded module: %s"):format(modName))
    else
      warn(("[app.lua] module unavailable (skipped): %s"):format(modName))
    end
  end

  -- Try to load Rayfield UI (optional)
  local uiRF = nil
  if uiFlags and (
      uiFlags.modelPicker or uiFlags.currentTarget or uiFlags.autoFarm or
      uiFlags.smartFarm or uiFlags.merchants or uiFlags.crates or
      uiFlags.antiAFK or uiFlags.redeemCodes or uiFlags.fastlevel or
      uiFlags.privateServer or uiFlags.dungeon
    ) then
    uiRF = tryRequireSibling("ui_rayfield", false)
    if not uiRF then
      warn("-- [app.lua] ui_rayfield.lua missing – UI not loaded. Core still running.")
    end
  end

  ------------------------------------------------------------------
  -- 5) Wire Rayfield only if present & requested
  ------------------------------------------------------------------
  local RF = nil
  local suppress = false
  local function setSafe(fn) suppress=true; pcall(fn); suppress=false end

  if uiRF then
    RF = uiRF.build({
      onAutoFarmToggle = (uiFlags.autoFarm and loaded.farm) and function(v)
        if suppress then return end
        local farm = loaded.farm
        if v then
          if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
          task.spawn(function()
            farm.runAutoFarm(function() return true end, function(txt)
              if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(txt) end) end
            end)
          end)
        else
          if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget("Current Target: None") end) end
        end
      end or nil,

      onSmartFarmToggle = (uiFlags.smartFarm and loaded.smart_target) and function(v)
        if suppress then return end
        local smart = loaded.smart_target
        if v then
          local RS = game:GetService("ReplicatedStorage")
          local function resolveMonsterInfo()
            local candidates = {
              {"GameInfo","MonsterInfo"},
              {"MonsterInfo"},
              {"Shared","MonsterInfo"},
              {"Modules","MonsterInfo"},
              {"Configs","MonsterInfo"},
            }
            for _, path in ipairs(candidates) do
              local node = RS
              local ok = true
              for _, n in ipairs(path) do
                node = node:FindFirstChild(n)
                if not node then ok=false; break end
              end
              if ok and node and node:IsA("ModuleScript") then return node end
            end
            for _, d in ipairs(RS:GetDescendants()) do
              if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then return d end
            end
            return nil
          end
          local mod = resolveMonsterInfo()
          task.spawn(function()
            smart.runSmartFarm(function() return true end, function(txt)
              if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(txt) end) end
            end, { module = mod, safetyBuffer = 0.8, refreshInterval = 0.05 })
          end)
        else
          if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget("Current Target: None") end) end
        end
      end or nil,

      onToggleMerchant1 = (uiFlags.merchants and loaded.merchants) and function(v)
        if v then
          task.spawn(function()
            loaded.merchants.autoBuyLoop("SmelterMerchantService", function() return true end, function() end)
          end)
        end
      end or nil,

      onToggleMerchant2 = (uiFlags.merchants and loaded.merchants) and function(v)
        if v then
          task.spawn(function()
            loaded.merchants.autoBuyLoop("SmelterMerchantService2", function() return true end, function() end)
          end)
        end
      end or nil,

      onToggleCrates = (uiFlags.crates and loaded.crates) and function(v)
        if v then
          loaded.crates.refreshCrateInventory(true)
          task.spawn(function()
            loaded.crates.autoOpenCratesEnabledLoop(function() return true end)
          end)
        end
      end or nil,

      onToggleAntiAFK = (uiFlags.antiAFK and loaded.anti_afk) and function(v)
        if v then loaded.anti_afk.enable() else loaded.anti_afk.disable() end
      end or nil,

      onRedeemCodes = (uiFlags.redeemCodes and loaded.redeem_unredeemed_codes) and function()
        task.spawn(function()
          pcall(function()
            loaded.redeem_unredeemed_codes.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
          end)
        end)
      end or nil,

      onFastLevelToggle = (uiFlags.fastlevel and loaded.fastlevel and loaded.farm) and function(v)
        local fast = loaded.fastlevel
        local farm = loaded.farm
        if v then
          if fast.enable then fast.enable() end
          if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
          task.spawn(function()
            if farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
            farm.runAutoFarm(function() return true end, function(txt)
              if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(txt) end) end
            end)
          end)
        else
          if fast.disable then fast.disable() end
          if farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end
          if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget("Current Target: None") end) end
        end
      end or nil,
    })
  end

  ------------------------------------------------------------------
  -- 6) Dungeon profile: autostart if module provided
  ------------------------------------------------------------------
  if uiFlags.dungeon and loaded.dungeon_be then
    if type(loaded.dungeon_be.start) == "function" then
      print("[app.lua] starting dungeon_be module")
      pcall(function() loaded.dungeon_be.start() end)
    elseif type(loaded.dungeon_be.run) == "function" then
      print("[app.lua] running dungeon_be module")
      pcall(function() loaded.dungeon_be.run() end)
    else
      warn("[app.lua] dungeon_be module has no start/run; loaded but idle")
    end
  end

  utils.notify("🌲 WoodzHUB", "Loaded profile: "..tostring(profile.name or "Unknown"), 4)
end

boot()
return { start = boot }
