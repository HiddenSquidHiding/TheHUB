-- app.lua — Executor-friendly bootstrapper for WoodzHUB
-- - Remote-loads modules from GitHub raw if local require is not applicable
-- - Selects a profile from games.lua by place:PlaceId -> GameId -> default
-- - Wires Rayfield UI (ui_rayfield.lua) to modules (farm, anti_afk, crates, merchants, smart_target, redeem codes, fastlevel)
-- - Exports app.start() for compatibility with loaders expecting a start() entrypoint
-- - Prevents double-boot/UI duplication

----------------------------------------------------------------------
-- Single-run guard (covers both direct exec and module-style start())
----------------------------------------------------------------------
if _G.WOODZHUB_APP_RUNNING then
  warn("[app.lua] already running; skipping second boot")
  return { start = function() end } -- satisfy any start() caller gracefully
end
_G.WOODZHUB_APP_RUNNING = true

----------------------------------------------------------------------
-- Minimal utils (shared to modules via __WOODZ_UTILS)
----------------------------------------------------------------------
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local utils = {
  notify = function(title, msg, dur)
    dur = dur or 3
    print(("[%s] %s"):format(title, msg))
  end,
  waitForCharacter = function()
    local plr = Players.LocalPlayer
    while true do
      local ch = plr.Character
      if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
        return ch
      end
      plr.CharacterAdded:Wait()
      task.wait()
    end
  end,
  track = function(conn) return conn end,
  new = function(t, props, parent)
    local i = Instance.new(t)
    if props then for k,v in pairs(props) do i[k] = v end end
    if parent then i.Parent = parent end
    return i
  end,
}
_G.__WOODZ_UTILS = utils

----------------------------------------------------------------------
-- GitHub remote loader (adjust BASE to your repo)
----------------------------------------------------------------------
local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/' -- <-- change if needed

local function fetchSource(path)
  local ok, src = pcall(function() return game:HttpGet(BASE .. path) end)
  if not ok then
    warn(("[app.lua] fetch fail %s: %s"):format(path, tostring(src)))
    return nil
  end
  return src
end

----------------------------------------------------------------------
-- Shim require with sibling prefetch + shared environment
----------------------------------------------------------------------
local function preload(paths)
  local got = {}
  for _, p in ipairs(paths) do
    local src = fetchSource(p)
    if src then
      got[p] = src
      print("[init] fetched: " .. p)
    else
      warn("[init] missing on remote: " .. p)
    end
  end
  return got
end

-- Preload modules we may need (missing is OK)
local fetched = preload({
  "games.lua",
  "ui_rayfield.lua",
  "constants.lua",
  "farm.lua",
  "merchants.lua",
  "crates.lua",
  "anti_afk.lua",
  "smart_target.lua",
  "redeem_unredeemed_codes.lua",
  "fastlevel.lua",
  "hud.lua",
})

-- compiled cache so modules are singletons
local compiled = {}

local function loadWithSiblings(entryName)
  local filename = entryName:match("%.lua$") and entryName or (entryName .. ".lua")
  if compiled[filename] ~= nil then return compiled[filename] end

  local src = fetched[filename]
  if not src then
    warn("[loader] no source for " .. tostring(filename))
    compiled[filename] = nil
    return nil
  end

  local siblingNames = {}
  for k,_ in pairs(fetched) do siblingNames[k:gsub("%.lua$","")] = true end

  local env = getfenv()
  local parent = {}
  for name,_ in pairs(siblingNames) do parent[name] = { Name = name } end

  local function shimRequire(mod)
    if type(mod) == "table" and mod.Name then mod = tostring(mod.Name) end
    if type(mod) ~= "string" then
      error("[loader] require(nil) from " .. tostring(entryName) .. " — likely missing sibling", 2)
    end
    local fname = mod:match("%.lua$") and mod or (mod .. ".lua")
    if compiled[fname] ~= nil then return compiled[fname] end
    return loadWithSiblings(fname)
  end

  local chunk, err = loadstring(src, "="..filename)
  if not chunk then
    warn(("[loader] compile failed for %s: %s"):format(filename, tostring(err)))
    compiled[filename] = nil
    return nil
  end

  local sandbox = setmetatable({
    __WOODZ_UTILS = _G.__WOODZ_UTILS,
    script = { Parent = parent },
    require = shimRequire,
  }, { __index = env })

  setfenv(chunk, sandbox)

  local ok, ret = pcall(chunk)
  if not ok then
    warn(("[loader] run failed for %s: %s"):format(filename, tostring(ret)))
    compiled[filename] = nil
    return nil
  end

  compiled[filename] = ret
  return ret
end

----------------------------------------------------------------------
-- games.lua -> profile selection (place -> game -> default)
----------------------------------------------------------------------
local function loadGamesConfig()
  local games = loadWithSiblings("games.lua")
  if type(games) ~= "table" then
    warn("[app.lua] games.lua missing or invalid; falling back to default")
    games = {
      default = { name = "Generic", modules = {}, ui = {} }
    }
  end

  local gid = tostring(game.GameId)
  local pid = tostring(game.PlaceId)
  local placeKey = "place:" .. pid

  local key =
      (games[placeKey] and placeKey)
      or (games[gid] and gid)
      or "default"

  local profile = games[key] or games.default or { name="Generic", modules={}, ui={} }
  profile.name = profile.name or "Unnamed"
  profile.modules = profile.modules or {}
  profile.ui = profile.ui or {}

  print(("[app.lua] profile: %s (key=%s)"):format(profile.name, tostring(key)))
  return profile
end

local function opt(name)
  local mod = loadWithSiblings(name)
  if mod == nil then
    warn("[app.lua] optional module '"..name.."' not available")
  end
  return mod
end

----------------------------------------------------------------------
-- Boot logic (idempotent via global guard)
----------------------------------------------------------------------
local function boot()
  utils.notify("🌲 WoodzHUB", "Booting…", 2)

  local profile = loadGamesConfig()

  -- Modules (may be nil if missing)
  local constants   = opt("constants")
  local uiRF        = opt("ui_rayfield")
  local farm        = opt("farm")
  local merchants   = opt("merchants")
  local crates      = opt("crates")
  local antiAFK     = opt("anti_afk")
  local smartFarm   = opt("smart_target")
  local redeemCodes = opt("redeem_unredeemed_codes")
  local fastlevel   = opt("fastlevel")
  local hud         = opt("hud")

  -- State
  local autoFarmEnabled        = false
  local smartFarmEnabled       = false
  local autoBuyM1Enabled       = false
  local autoBuyM2Enabled       = false
  local autoOpenCratesEnabled  = false
  local antiAfkEnabled         = false

  -- Rayfield handle
  local RF = nil
  local suppressRF = false
  local function rfSet(fn)
    if RF and fn then
      suppressRF = true
      pcall(fn)
      suppressRF = false
    end
  end

  -- status label (throttled)
  local lastLabelText, lastLabelAt = nil, 0
  local function setCurrentTarget(text)
    text = text or "Current Target: None"
    local now = tick()
    if text == lastLabelText and (now - lastLabelAt) < 0.12 then return end
    lastLabelText, lastLabelAt = text, now
    if RF and RF.setCurrentTarget then pcall(function() RF.setCurrentTarget(text) end) end
  end

  local function notifyToggle(name, on, extra)
    extra = extra or ""
    local msg = on and (name .. " enabled" .. extra) or (name .. " disabled")
    utils.notify("🌲 " .. name, msg, 3.5)
  end

  -- Build Rayfield (pass profile.ui so your UI module can decide what to show)
  if uiRF and type(uiRF.build) == "function" then
    -- prevent double window if some external loader calls us twice
    if _G.WOODZHUB_UI_BUILT then
      warn("[app.lua] UI already built — skipping duplicate")
    else
      _G.WOODZHUB_UI_BUILT = true
      print("-- creating window")
      RF = uiRF.build({
        onClearAll = function()
          if not farm then return end
          farm.setSelected({})
          if RF and RF.syncModelSelection then RF.syncModelSelection() end
          utils.notify("🌲 Preset", "Cleared all selections.", 3)
        end,

        onAutoFarmToggle = function(v)
          if not farm then return end
          if suppressRF then return end
          local newState = (v ~= nil) and v or (not autoFarmEnabled)

          if newState and smartFarmEnabled then
            smartFarmEnabled = false
            rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
            notifyToggle("Smart Farm", false)
          end

          autoFarmEnabled = newState

          if autoFarmEnabled then
            if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
            local sel = farm.getSelected and farm.getSelected() or {}
            local extra = (#sel > 0) and (" for: " .. table.concat(sel, ", ")) or ""
            notifyToggle("Auto-Farm", true, extra)
            task.spawn(function()
              farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
            end)
          else
            setCurrentTarget("Current Target: None")
            notifyToggle("Auto-Farm", false)
          end
        end,

        onSmartFarmToggle = function(v)
          if not smartFarm or not farm then return end
          if suppressRF then return end
          local newState = (v ~= nil) and v or (not smartFarmEnabled)

          if newState and autoFarmEnabled then
            autoFarmEnabled = false
            rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(false) end end)
            notifyToggle("Auto-Farm", false)
          end

          smartFarmEnabled = newState

          if smartFarmEnabled then
            local function resolveMonsterInfo()
              local RS = ReplicatedStorage
              local paths = {
                {"GameInfo","MonsterInfo"},{"MonsterInfo"},{"Shared","MonsterInfo"},
                {"Modules","MonsterInfo"},{"Configs","MonsterInfo"},
              }
              for _, path in ipairs(paths) do
                local node, ok = RS, true
                for _, nm in ipairs(path) do
                  node = node:FindFirstChild(nm)
                  if not node then ok=false break end
                end
                if ok and node and node:IsA("ModuleScript") then return node end
              end
              for _, d in ipairs(RS:GetDescendants()) do
                if d:IsA("ModuleScript") and d.Name=="MonsterInfo" then return d end
              end
              return nil
            end

            local module = resolveMonsterInfo()
            notifyToggle("Smart Farm", true, module and (" — using " .. module:GetFullName()) or " (MonsterInfo not found; will stop)")
            if module then
              task.spawn(function()
                smartFarm.runSmartFarm(
                  function() return smartFarmEnabled end,
                  setCurrentTarget,
                  { module = module, safetyBuffer = 0.8, refreshInterval = 0.05 }
                )
              end)
            else
              smartFarmEnabled = false
              rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
            end
          else
            setCurrentTarget("Current Target: None")
            notifyToggle("Smart Farm", false)
          end
        end,

        onToggleMerchant1 = function(v)
          if not merchants then return end
          if suppressRF then return end
          autoBuyM1Enabled = (v ~= nil) and v or (not autoBuyM1Enabled)
          if autoBuyM1Enabled then
            notifyToggle("Merchant — Chicleteiramania", true)
            task.spawn(function()
              merchants.autoBuyLoop(
                "SmelterMerchantService",
                function() return autoBuyM1Enabled end,
                function(_) end
              )
            end)
          else
            notifyToggle("Merchant — Chicleteiramania", false)
          end
        end,

        onToggleMerchant2 = function(v)
          if not merchants then return end
          if suppressRF then return end
          autoBuyM2Enabled = (v ~= nil) and v or (not autoBuyM2Enabled)
          if autoBuyM2Enabled then
            notifyToggle("Merchant — Bombardino Sewer", true)
            task.spawn(function()
              merchants.autoBuyLoop(
                "SmelterMerchantService2",
                function() return autoBuyM2Enabled end,
                function(_) end
              )
            end)
          else
            notifyToggle("Merchant — Bombardino Sewer", false)
          end
        end,

        onToggleCrates = function(v)
          if not crates then return end
          if suppressRF then return end
          autoOpenCratesEnabled = (v ~= nil) and v or (not autoOpenCratesEnabled)
          if autoOpenCratesEnabled then
            if crates.refreshCrateInventory then crates.refreshCrateInventory(true) end
            local delayText = 1
            if constants and constants.crateOpenDelay then delayText = constants.crateOpenDelay end
            notifyToggle("Crates", true, " (1 every " .. tostring(delayText) .. "s)")
            task.spawn(function()
              crates.autoOpenCratesEnabledLoop(function() return autoOpenCratesEnabled end)
            end)
          else
            notifyToggle("Crates", false)
          end
        end,

        onToggleAntiAFK = function(v)
          if not antiAFK then return end
          if suppressRF then return end
          antiAfkEnabled = (v ~= nil) and v or (not antiAfkEnabled)
          if antiAfkEnabled then antiAFK.enable() else antiAFK.disable() end
          notifyToggle("Anti-AFK", antiAfkEnabled)
        end,

        onRedeemCodes = function()
          if not redeemCodes then return end
          task.spawn(function()
            local ok, err = pcall(function()
              redeemCodes.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
            end)
            if not ok then utils.notify("Codes", "Redeem failed: " .. tostring(err), 4) end
          end)
        end,

        onFastLevelToggle = function(v)
          if not (fastlevel and farm) then return end
          if suppressRF then return end
          local nowOn = (v ~= nil) and v or (not (fastlevel.isEnabled and fastlevel.isEnabled() or false))
          if nowOn then
            if smartFarmEnabled then
              smartFarmEnabled = false
              rfSet(function() if RF.setSmartFarm then RF.setSmartFarm(false) end end)
              notifyToggle("Smart Farm", false)
            end
            if fastlevel.enable then fastlevel.enable() end
            if farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
            notifyToggle("Instant Level 70+", true, " — targeting Sahur only")

            if not autoFarmEnabled then
              autoFarmEnabled = true
              rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(true) end end)
              if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
              task.spawn(function()
                farm.runAutoFarm(function() return autoFarmEnabled end, setCurrentTarget)
              end)
              notifyToggle("Auto-Farm", true)
            end
          else
            if fastlevel.disable then fastlevel.disable() end
            if farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end
            notifyToggle("Instant Level 70+", false)
            if autoFarmEnabled then
              autoFarmEnabled = false
              rfSet(function() if RF.setAutoFarm then RF.setAutoFarm(false) end end)
              setCurrentTarget("Current Target: None")
              notifyToggle("Auto-Farm", false)
            end
          end
        end,

        onPrivateServer = function()
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
      }, profile.ui or {}) -- << pass profile UI flags
      utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
    end
  else
    warn("[app.lua] ui_rayfield.lua missing - UI not loaded. Core still running.")
  end

  utils.notify("🌲 WoodzHUB", "Ready.", 2)
end

----------------------------------------------------------------------
-- Export app.start() for loaders that expect it, and also run once now
----------------------------------------------------------------------
local app = {}

function app.start()
  if _G.WOODZHUB_APP_STARTED then return end
  _G.WOODZHUB_APP_STARTED = true
  local ok, err = pcall(boot)
  if not ok then
    warn("[WoodzHUB] [init] Failed to load app.lua")
    warn(err)
  end
end

-- If executed directly (not required as a module), also call start()
local ok_direct, err_direct = pcall(function()
  app.start()
end)
if not ok_direct then
  warn(err_direct)
end

return app
