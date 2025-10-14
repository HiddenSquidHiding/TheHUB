-- app.lua — HTTP loader with utils + require shim so your modules work unchanged

if _G.WOODZHUB_RUNNING then
  warn("[WoodzHUB] app already running; skipping duplicate")
  return
end
_G.WOODZHUB_RUNNING = true

----------------------------------------------------------------------
-- 0) Minimal global utils so modules’ getUtils() succeeds
----------------------------------------------------------------------
_G.__WOODZ_UTILS = _G.__WOODZ_UTILS or (function()
  local StarterGui = game:GetService("StarterGui")
  local Players = game:GetService("Players")

  local function notify(title, msg, dur)
    pcall(function()
      StarterGui:SetCore("SendNotification", {
        Title = tostring(title or "WoodzHUB"),
        Text = tostring(msg or ""),
        Duration = tonumber(dur or 3)
      })
    end)
    print(("[WoodzHUB] %s - %s"):format(tostring(title or "Note"), tostring(msg or "")))
  end

  local function waitForCharacter()
    local plr = Players.LocalPlayer
    while not plr
       or not plr.Character
       or not plr.Character:FindFirstChild("HumanoidRootPart")
       or not plr.Character:FindFirstChildOfClass("Humanoid") do
      if not Players.LocalPlayer then plr = Players.LocalPlayer end
      if plr then plr.CharacterAdded:Wait() end
      task.wait(0.05)
    end
    return plr.Character
  end

  return {
    notify = notify,
    waitForCharacter = waitForCharacter,
  }
end)()

local function log(...)  print("[WoodzHUB]", ...) end
local function warnf(...) warn("[WoodzHUB]", ...) end

----------------------------------------------------------------------
-- 1) EDIT THESE URLS with your raw GitHub links
----------------------------------------------------------------------
local URLS = {
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
  ["games.lua"]                   = "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/games.lua",

  -- Brainrot Dungeon helper
  ["dungeon_be.lua"]              = "https://raw.githubusercontent.comHiddenSquidHiding/TheHUB/main/dungeon_be.lua",
}

----------------------------------------------------------------------
-- 2) HTTP fetcher + module loader with a require shim
----------------------------------------------------------------------
local function fetch_source(fname)
  local url = URLS[fname]
  if not url then return nil, "no URL" end
  local ok, src = pcall(game.HttpGet, game, url)
  if not ok then return nil, ("HTTP failed: %s"):format(tostring(src)) end
  if type(src) ~= "string" or #src == 0 then return nil, "empty body" end
  return src
end

-- modules sometimes call: require(script.Parent.constants)
-- We emulate that with a fake script.Parent and a shimmed require.
local KNOWN = {
  "ui_rayfield","farm","smart_target","anti_afk","merchants","crates",
  "redeem_unredeemed_codes","fastlevel","hud","constants","data_monsters","games","dungeon_be"
}
local FakeParent = {}
for _, n in ipairs(KNOWN) do
  FakeParent[n] = { Name = n } -- table “Instance” with Name
end
local FakeScript = { Parent = FakeParent }

local function load_module(fname)
  local src, err = fetch_source(fname)
  if not src then return nil, ("runtime error for %s: %s"):format(fname, tostring(err)) end

  local chunk, cerr = loadstring(src, "=" .. fname)
  if not chunk then return nil, ("compile error for %s: %s"):format(fname, tostring(cerr)) end

  -- custom environment
  local env = setmetatable({
    __WOODZ_UTILS = _G.__WOODZ_UTILS,
    script = FakeScript,
    require = function(arg)
      -- 1) require("constants") -> constants.lua
      if type(arg) == "string" then
        local name = arg
        if not name:find("%.lua$") then name = name .. ".lua" end
        return load_module(name)
      end
      -- 2) require(table with Name) -> Name.lua
      if type(arg) == "table" and type(arg.Name) == "string" then
        local name = arg.Name
        if not name:find("%.lua$") then name = name .. ".lua" end
        return load_module(name)
      end
      -- 3) anything else: fall back to global require (rare)
      return require(arg)
    end
  }, { __index = _G })

  setfenv(chunk, env)
  local ok, ret = pcall(chunk)
  if not ok then return nil, ("runtime error for %s: %s"):format(fname, tostring(ret)) end
  return ret
end

local function try_require(fname)
  local mod, err = load_module(fname)
  if not mod then
    warnf("optional module '%s' not available: %s", fname, tostring(err))
    return nil
  end
  return mod
end

----------------------------------------------------------------------
-- 3) Games profile (remote if present, else defaults)
----------------------------------------------------------------------
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
  -- Brainrot Evolution (replace place id if needed)
  ["place:111989938562194"] = {
    name = "Brainrot Evolution",
    modules = {
      "anti_afk","farm","smart_target","merchants","crates",
      "redeem_unredeemed_codes","fastlevel","hud","constants","data_monsters"
    },
    ui = {
      modelPicker = true, currentTarget = true,
      autoFarm = true, smartFarm = true,
      merchants = true, crates = true, antiAFK = true,
      redeemCodes = true, fastlevel = true, privateServer = true,
    },
  },
  -- Brainrot Dungeon
  ["place:90608986169653"] = {
    name = "Brainrot Dungeon",
    modules = { "anti_afk","dungeon_be","constants" },
    ui = {
      modelPicker = false, currentTarget = false,
      autoFarm = false, smartFarm = false,
      merchants = false, crates = false, antiAFK = true,
      redeemCodes = false, fastlevel = false, privateServer = false,
    },
  },
}

local GAMES = (function()
  local mod = try_require("games.lua")
  if type(mod) == "table" then return mod end
  return DEFAULT_GAMES
end)()

local function pick_profile(games)
  local keyPlace = "place:" .. tostring(game.PlaceId)
  local keyUni   = tostring(game.GameId)
  local prof = games[keyPlace] or games[keyUni] or games.default
  local key  = games[keyPlace] and keyPlace or (games[keyUni] and keyUni or "default")
  return prof, key
end

local profile, key = pick_profile(GAMES)
log(("profile: %s (key= %s)"):format(profile and profile.name or "?", key))

----------------------------------------------------------------------
-- 4) Load core modules now that utils/require shim exist
----------------------------------------------------------------------
local constants   = try_require("constants.lua") -- optional but many UIs use it
local hud         = try_require("hud.lua")       -- optional
local dataMon     = try_require("data_monsters.lua") -- optional

-- Load per-profile feature modules
local loaded = {}
for _, name in ipairs(profile.modules or {}) do
  local mod = try_require(name .. ".lua")
  if mod then loaded[name] = mod else warnf("module unavailable (skipped): %s", name) end
end

----------------------------------------------------------------------
-- 5) Build Rayfield (if declared)
----------------------------------------------------------------------
local UI
do
  local needUI = false
  local uiFlags = profile.ui or {}
  for k, v in pairs(uiFlags) do if v then needUI = true break end end

  local ui_mod = try_require("ui_rayfield.lua")
  if needUI and ui_mod and type(ui_mod.build) == "function" then
    local handlers = {}

    -- Example: wire only the callbacks you need. (You already had these.)
    handlers.onClearAll = function()
      if loaded.farm and loaded.farm.setSelected then loaded.farm.setSelected({}) end
    end

    handlers.onAutoFarmToggle = function(on)
      local farm = loaded.farm
      if not (farm and farm.runAutoFarm) then return end
      if on then
        if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
        task.spawn(function()
          farm.runAutoFarm(function() return true end, function(txt) if UI and UI.setCurrentTarget then UI.setCurrentTarget(txt) end end)
        end)
      end
    end

    handlers.onSmartFarmToggle = function(on)
      local sm = loaded.smart_target
      if not (sm and sm.runSmartFarm) then return end
      if on then
        local RS = game:GetService("ReplicatedStorage")
        local mi = nil
        for _, d in ipairs(RS:GetDescendants()) do
          if d:IsA("ModuleScript") and d.Name == "MonsterInfo" then mi = d break end
        end
        task.spawn(function()
          sm.runSmartFarm(function() return true end, function(t) if UI and UI.setCurrentTarget then UI.setCurrentTarget(t) end end, { module = mi, safetyBuffer = 0.8, refreshInterval = 0.05 })
        end)
      end
    end

    handlers.onToggleAntiAFK = function(on)
      local a = loaded.anti_afk
      if not a then return end
      if on and a.enable then a.enable() elseif a.disable then a.disable() end
    end

    handlers.onToggleMerchant1 = function(on)
      local m = loaded.merchants; if not (m and m.autoBuyLoop) then return end
      if on then task.spawn(function() m.autoBuyLoop("SmelterMerchantService", function() return true end, function() end) end end
    end

    handlers.onToggleMerchant2 = function(on)
      local m = loaded.merchants; if not (m and m.autoBuyLoop) then return end
      if on then task.spawn(function() m.autoBuyLoop("SmelterMerchantService2", function() return true end, function() end) end end
    end

    handlers.onToggleCrates = function(on)
      local c = loaded.crates; if not (c and c.autoOpenCratesEnabledLoop) then return end
      if on then
        if c.refreshCrateInventory then c.refreshCrateInventory(true) end
        task.spawn(function() c.autoOpenCratesEnabledLoop(function() return true end) end)
      end
    end

    handlers.onRedeemCodes = function()
      local codes = loaded.redeem_unredeemed_codes
      if not (codes and codes.run) then return end
      task.spawn(function() pcall(function() codes.run({ dryRun=false, concurrent=true, delayBetween=0.25 }) end) end)
    end

    handlers.onFastLevelToggle = function(on)
      local fl = loaded.fastlevel
      local farm = loaded.farm
      if not (fl and farm and farm.runAutoFarm) then return end
      if on then
        if fl.enable then fl.enable() end
        if farm.setFastLevelEnabled then farm.setFastLevelEnabled(true) end
        if farm.setupAutoAttackRemote then farm.setupAutoAttackRemote() end
        task.spawn(function()
          farm.runAutoFarm(function() return true end, function(t) if UI and UI.setCurrentTarget then UI.setCurrentTarget(t) end end)
        end)
      else
        if fl.disable then fl.disable() end
        if farm.setFastLevelEnabled then farm.setFastLevelEnabled(false) end
      end
    end

    handlers.onPrivateServer = function()
      if type(_G.TeleportToPrivateServer) == "function" then
        local ok, err = pcall(_G.TeleportToPrivateServer)
        if not ok then _G.__WOODZ_UTILS.notify("Private Server", tostring(err), 4) end
      else
        _G.__WOODZ_UTILS.notify("Private Server","solo.lua not loaded (_G.TeleportToPrivateServer missing).",4)
      end
    end

    UI = ui_mod.build(handlers, uiFlags)
    _G.__WOODZ_UTILS.notify("WoodzHUB", "Rayfield UI loaded.", 3)
  else
    warnf("[ui_rayfield] Rayfield failed to load")
  end
end

----------------------------------------------------------------------
-- 6) Per-place helper (Brainrot Dungeon)
----------------------------------------------------------------------
do
  local dungeon = loaded["dungeon_be"]
  if dungeon and type(dungeon.init)=="function" then
    dungeon.init()
    -- Enable auto/replay here if you want:
    -- if dungeon.setAuto then dungeon.setAuto(true) end
    -- if dungeon.setReplay then dungeon.setReplay(true) end
  end
end

log("Ready")
