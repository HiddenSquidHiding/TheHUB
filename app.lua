-- app.lua — self-contained loader (no script.Parent, no BASE required)
-- Edit the URLS table below once with your raw GitHub links.

if _G.WOODZHUB_RUNNING then
  warn("[WoodzHUB] app already running; skip duplicate")
  return
end
_G.WOODZHUB_RUNNING = true

-- ====== 1) EDIT THESE URLS TO YOUR RAW FILE LINKS ======
local URLS = {
  -- Core UI + features
  ["ui_rayfield.lua"]             = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/ui_rayfield.lua",
  ["farm.lua"]                    = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/farm.lua",
  ["smart_target.lua"]            = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/smart_target.lua",
  ["anti_afk.lua"]                = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/anti_afk.lua",
  ["merchants.lua"]               = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/merchants.lua",
  ["crates.lua"]                  = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/crates.lua",
  ["redeem_unredeemed_codes.lua"] = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/redeem_unredeemed_codes.lua",
  ["fastlevel.lua"]               = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/fastlevel.lua",
  ["hud.lua"]                     = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/hud.lua",
  ["constants.lua"]               = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/constants.lua",
  ["data_monsters.lua"]           = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/data_monsters.lua",

  -- Per-game helper (Brainrot Dungeon)
  ["dungeon_be.lua"]              = "https://raw.githubusercontent.comHiddenSquidHiding/TheHUB/main/dungeon_be.lua",

  -- Optional: game profile map; if you don’t want a separate file, we inline a default below.
  ["games.lua"]                   = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/games.lua",
}

-- ====== 2) Optional: global BASE as a final fallback (not required) ======
local BASE = rawget(_G, "WOODZHUB_BASE")  -- e.g. "https://raw.githubusercontent.com/USER/REPO/BRANCH/PATH"

-- ====== Utility: safe notify & simple logger ======
local function notify(title, msg, dur)
  pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
      Title = tostring(title or "WoodzHUB"),
      Text = tostring(msg or ""),
      Duration = tonumber(dur or 3),
    })
  end)
end

local function log(...) print("[WoodzHUB]", ...) end
local function warnf(...) warn("[WoodzHUB]", ...) end

-- ====== 3) Fetch helper: FS -> URLS -> BASE/file ======
local function fetch_source(fname)
  -- memory FS first
  if _G.WOODZHUB_FS and _G.WOODZHUB_FS[fname] then
    return _G.WOODZHUB_FS[fname], "fs"
  end
  -- explicit URL map
  local url = URLS[fname]
  if url and type(url) == "string" and #url > 0 then
    local ok, src = pcall(game.HttpGet, game, url)
    if ok and type(src) == "string" then return src, "url_map" end
    warnf("HTTP failed for %s -> %s", fname, url)
  end
  -- base fallback
  if BASE then
    local u = (string.sub(BASE, -1) == "/") and (BASE .. fname) or (BASE .. "/" .. fname)
    local ok, src = pcall(game.HttpGet, game, u)
    if ok and type(src) == "string" then return src, "base" end
    warnf("HTTP failed for %s -> %s", fname, u)
  end
  return nil, "missing"
end

local function require_remote(fname, chunkname)
  local src, where = fetch_source(fname)
  if not src then return nil, ("missing file: %s"):format(fname) end
  local fn, err = loadstring(src, "=" .. (chunkname or fname))
  if not fn then return nil, ("compile error for %s: %s"):format(fname, tostring(err)) end
  local ok, mod = pcall(fn)
  if not ok then return nil, ("runtime error for %s: %s"):format(fname, tostring(mod)) end
  return mod, nil
end

local function try_require(fname)
  local mod, err = require_remote(fname)
  if not mod then
    warnf("optional module '%s' not available: %s", fname, tostring(err))
    return nil
  end
  return mod
end

-- ====== 4) Inline default games profile (used if remote games.lua missing) ======
local DEFAULT_GAMES = {
  default = {
    name = "Generic",
    modules = { "anti_afk" },
    ui = {
      modelPicker = false, currentTarget = false,
      autoFarm = false, smartFarm = false,
      merchants = false, crates = false, antiAFK = true,
      redeemCodes = false, fastlevel = false, privateServer = false,
    },
  },

  -- Brainrot Evolution (example place or universe key):
  -- Replace place IDs with your real ones
  ["place:111989938562194"] = {
    name = "Brainrot Evolution",
    modules = {
      "anti_afk","farm","smart_target","merchants","crates",
      "redeem_unredeemed_codes","fastlevel"
    },
    ui = {
      modelPicker = true, currentTarget = true,
      autoFarm = true, smartFarm = true,
      merchants = true, crates = true, antiAFK = true,
      redeemCodes = true, fastlevel = true, privateServer = true,
    },
  },

  -- Brainrot Evolution Dungeons (load dungeon_be.lua instead of farm, etc.)
  ["place:90608986169653"] = {
    name = "Brainrot Dungeon",
    modules = { "anti_afk", "dungeon_be" },
    ui = {
      -- This place uses its own helper, so keep the UI light or even none
      modelPicker = false, currentTarget = false,
      autoFarm = false, smartFarm = false,
      merchants = false, crates = false, antiAFK = true,
      redeemCodes = false, fastlevel = false, privateServer = false,
    },
  },
}

-- Try to load games.lua from your repo; fallback to DEFAULT_GAMES
local GAMES = (function()
  local mod = try_require("games.lua")
  if type(mod) == "table" then return mod end
  return DEFAULT_GAMES
end)()

-- ====== 5) Pick profile for current place/universe ======
local function pick_profile(games)
  local keyPlace = "place:" .. tostring(game.PlaceId)
  local keyUni   = tostring(game.GameId)
  local prof = games[keyPlace] or games[keyUni] or games.default
  local key = games[keyPlace] and keyPlace or (games[keyUni] and keyUni or "default")
  return prof, key
end

local profile, profileKey = pick_profile(GAMES)
log(("profile: %s (key=%s)"):format(profile and profile.name or "?", profileKey))

-- ====== 6) Safe load core modules (constants/hud first; many modules expect them) ======
local constants = try_require("constants.lua") or {
  COLOR_BG_DARK = Color3.fromRGB(30,30,30),
  COLOR_BG      = Color3.fromRGB(40,40,40),
  COLOR_BG_MED  = Color3.fromRGB(50,50,50),
  COLOR_BTN     = Color3.fromRGB(60,60,60),
  COLOR_BTN_ACTIVE = Color3.fromRGB(80,80,80),
  COLOR_WHITE   = Color3.fromRGB(255,255,255),
  SIZE_MAIN = UDim2.new(0,400,0,540), SIZE_MIN = UDim2.new(0,400,0,50),
  crateOpenDelay = 1.0, merchantCooldown = 0.1,
}
local hud = try_require("hud.lua")
local data_monsters = try_require("data_monsters.lua") -- optional

-- ====== 7) Load feature modules listed in the profile (if present) ======
local loaded = {}
for _, fname in ipairs(profile.modules or {}) do
  local mod = try_require(fname .. ".lua")
  if mod then loaded[fname] = mod else warnf("module unavailable (skipped): %s", fname) end
end

-- ====== 8) Build Rayfield (if ui_rayfield.lua available & any UI flags true) ======
local ui
do
  local wantUI =
    (profile.ui and (
      profile.ui.modelPicker or profile.ui.currentTarget or profile.ui.autoFarm or
      profile.ui.smartFarm or profile.ui.merchants or profile.ui.crates or
      profile.ui.antiAFK or profile.ui.redeemCodes or profile.ui.fastlevel or
      profile.ui.privateServer
    )) and true or false

  local ui_mod = try_require("ui_rayfield.lua")
  if wantUI and ui_mod and type(ui_mod.build) == "function" then
    -- Handlers wiring
    local handlers = {}

    -- Clear all (model picker)
    handlers.onClearAll = function()
      local farm = loaded["farm"]
      if farm and farm.setSelected then farm.setSelected({}) end
    end

    -- Auto-Farm toggle
    handlers.onAutoFarmToggle = function(on)
      local farm = loaded["farm"]
      if not farm or not farm.runAutoFarm then return end
      if on then
        if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
        task.spawn(function()
          farm.runAutoFarm(function() return true end, function(txt) if ui and ui.setCurrentTarget then ui.setCurrentTarget(txt) end end)
        end)
      else
        -- your farm.lua loop should stop when its getter returns false;
        -- since we passed a constant true above, you can adapt to store a flag:
        -- This minimal example omits a state flag; use your actual app.lua wiring if needed.
      end
    end

    -- Smart Farm toggle
    handlers.onSmartFarmToggle = function(on)
      local smart = loaded["smart_target"]
      if not smart or not smart.runSmartFarm then return end
      if on then
        -- try resolve MonsterInfo (optional)
        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local module = nil
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
          if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then module = d break end
        end
        task.spawn(function()
          smart.runSmartFarm(function() return true end, function(txt) if ui and ui.setCurrentTarget then ui.setCurrentTarget(txt) end end, { module = module, safetyBuffer = 0.8, refreshInterval = 0.05 })
        end)
      end
    end

    -- Anti-AFK toggle
    handlers.onToggleAntiAFK = function(on)
      local a = loaded["anti_afk"]
      if not a then return end
      if on and a.enable then a.enable() elseif a.disable then a.disable() end
    end

    -- Merchants
    handlers.onToggleMerchant1 = function(on)
      local m = loaded["merchants"]; if not m or not m.autoBuyLoop then return end
      if on then task.spawn(function() m.autoBuyLoop("SmelterMerchantService", function() return true end, function() end) end) end
    end
    handlers.onToggleMerchant2 = function(on)
      local m = loaded["merchants"]; if not m or not m.autoBuyLoop then return end
      if on then task.spawn(function() m.autoBuyLoop("SmelterMerchantService2", function() return true end, function() end) end) end
    end

    -- Crates
    handlers.onToggleCrates = function(on)
      local c = loaded["crates"]; if not c or not c.autoOpenCratesEnabledLoop then return end
      if on then
        if c.refreshCrateInventory then c.refreshCrateInventory(true) end
        task.spawn(function() c.autoOpenCratesEnabledLoop(function() return true end) end)
      end
    end

    -- Codes
    handlers.onRedeemCodes = function()
      local codes = loaded["redeem_unredeemed_codes"]; if not codes or not codes.run then return end
      task.spawn(function() pcall(function() codes.run({ dryRun=false, concurrent=true, delayBetween=0.25 }) end) end)
    end

    -- Fast Level
    handlers.onFastLevelToggle = function(on)
      local fl = loaded["fastlevel"]; local farm = loaded["farm"]
      if not fl or not farm or not farm.runAutoFarm then return end
      if on then
        if fl.enable then fl.enable() end
        if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
        task.spawn(function()
          if farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
          farm.runAutoFarm(function() return true end, function(txt) if ui and ui.setCurrentTarget then ui.setCurrentTarget(txt) end end)
        end)
      else
        if fl.disable then fl.disable() end
        if farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end
      end
    end

    -- Private Server button: call global if present (your solo.lua can define _G.TeleportToPrivateServer)
    handlers.onPrivateServer = function()
      if type(_G.TeleportToPrivateServer) == "function" then
        local ok, err = pcall(_G.TeleportToPrivateServer)
        if not ok then notify("Private Server", "Failed: "..tostring(err), 4) end
      else
        notify("Private Server", "solo.lua not loaded (_G.TeleportToPrivateServer missing).", 4)
      end
    end

    -- Build UI with the profile's declared flags
    ui = ui_mod.build(handlers, profile.ui or {})
    notify("WoodzHUB", "Rayfield UI loaded.", 3)
  else
    warnf("ui_rayfield.lua missing - UI not loaded. Core still running.")
  end
end

-- ====== 9) Start per-place helper (Brainrot Dungeon) if loaded ======
do
  local dungeon = loaded["dungeon_be"]
  if dungeon and type(dungeon.init)=="function" then
    dungeon.init()
    -- You can also auto-enable depending on preference:
    -- dungeon.setAuto(true); dungeon.setReplay(true)
  end
end

log("Ready")
