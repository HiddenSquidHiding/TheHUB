-- app.lua
-- Single-boot loader that fetches modules (HTTP) and builds the Rayfield UI exactly once.

local TAG = "[WoodzHUB]"

-- ---------------- basics & helpers ----------------
local HttpService = game:GetService("HttpService")

local function log(...) print(TAG, ...) end
local function warnf(...) warn(TAG, ...) end

-- Minimal utils given to modules
__WOODZ_UTILS = __WOODZ_UTILS or {
  notify = function(title, msg, dur)
    warn(("[%s] %s"):format(title or TAG, msg or ""))
  end,
  waitForCharacter = function()
    local Players = game:GetService("Players")
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
}

-- ---------------- remote loader ----------------
local BASE = _G.WOODZHUB_BASE or "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"

local function fetchText(url)
  local ok, res = pcall(game.HttpGet, game, url)
  if ok and type(res) == "string" and #res > 0 then return res end
  return nil, res
end

local function fetchModule(name)
  local url = BASE .. name .. ".lua"
  local src, err = fetchText(url)
  if not src then return nil, ("HTTP get failed for %s: %s"):format(name, tostring(err)) end
  local chunk, lerr = loadstring(src, "="..name)
  if not chunk then return nil, ("compile failed for %s: %s"):format(name, tostring(lerr)) end
  -- Give modules access to siblings via a synthetic environment
  local env = getfenv()
  env.__WOODZ_UTILS = __WOODZ_UTILS
  setfenv(chunk, env)
  local ok, ret = pcall(chunk)
  if not ok then return nil, ("runtime error for %s: %s"):format(name, tostring(ret)) end
  return ret
end

local function tryRequire(name, optional)
  local mod, err = fetchModule(name)
  if not mod then
    if optional then
      warnf(("[app.lua] optional module '%s' not available: %s"):format(name, err))
      return nil
    else
      error(("[app.lua] required module '%s' failed: %s"):format(name, err))
    end
  end
  return mod
end

-- ---------------- games profile ----------------
local function loadGames()
  local m, err = fetchModule("games")
  if not m or type(m) ~= "table" then
    warnf("[app.lua] games.lua missing or invalid; falling back to default")
    return {
      default = {
        name = "Generic",
        modules = { "anti_afk" },
        ui = {
          modelPicker=false, currentTarget=false,
          autoFarm=false, smartFarm=false,
          merchants=false, crates=false, antiAFK=true,
          redeemCodes=false, fastlevel=false, privateServer=false,
        },
      },
      ["place:111989938562194"] = { -- Brainrot Evolution (example)
        name = "Brainrot Evolution",
        modules = {
          "ui_rayfield","anti_afk","farm","smart_target",
          "merchants","crates","redeem_unredeemed_codes","fastlevel"
        },
        ui = {
          modelPicker=true, currentTarget=true,
          autoFarm=true, smartFarm=true,
          merchants=true, crates=true, antiAFK=true,
          redeemCodes=true, fastlevel=true, privateServer=true,
        },
      },
      ["place:90608986169653"] = { -- Brainrot Dungeon (example)
        name = "Brainrot Dungeon",
        modules = { "ui_rayfield","dungeon_be","anti_afk" },
        ui = {
          modelPicker=false, currentTarget=false,
          autoFarm=false, smartFarm=false,
          merchants=false, crates=false, antiAFK=true,
          redeemCodes=false, fastlevel=false, privateServer=false,
        },
      },
    }
  end
  return m
end

local function chooseProfile(gamesTbl)
  local placeKey = "place:"..tostring(game.PlaceId)
  if gamesTbl[placeKey] then return gamesTbl[placeKey], placeKey end
  local uniKey = tostring(game.GameId)
  if gamesTbl[uniKey] then return gamesTbl[uniKey], uniKey end
  return gamesTbl.default, "default"
end

-- ---------------- boot ----------------
local function start()
  if _G.__WOODZ_BOOTED then
    return
  end
  _G.__WOODZ_BOOTED = true

  local games = loadGames()
  local profile, key = chooseProfile(games)
  profile = profile or games.default
  key = key or "default"

  log(("profile: %s (key=%s)"):format(profile.name or "?", key))

  -- Load requested modules
  local loaded = {}
  for _, name in ipairs(profile.modules or {}) do
    local mod = tryRequire(name, true) -- optional: true (don’t hard-crash if missing)
    if mod then loaded[name] = mod end
  end

  -- Build Rayfield if present
  local UI = nil
  if loaded.ui_rayfield and type(loaded.ui_rayfield.build) == "function" then
    UI = loaded.ui_rayfield.build({
      onAutoFarmToggle  = function(v) if loaded.farm and loaded.farm.runAutoFarm then
        if v then
          loaded.farm.setupAutoAttackRemote()
          task.spawn(function()
            loaded.farm.runAutoFarm(function() return true end, function() end)
          end)
        end
      end end,

      onSmartFarmToggle = function(v) end, -- wire as needed
      onToggleMerchant1 = function(v) end,
      onToggleMerchant2 = function(v) end,
      onToggleCrates    = function(v) end,
      onToggleAntiAFK   = function(v) if loaded.anti_afk then if v then loaded.anti_afk.enable() else loaded.anti_afk.disable() end end end,
      onRedeemCodes     = function() if loaded.redeem_unredeemed_codes then pcall(function() loaded.redeem_unredeemed_codes.run({dryRun=false,concurrent=true,delayBetween=0.25}) end) end end,
      onFastLevelToggle = function(v) end,
      onClearAll        = function() if loaded.farm and loaded.farm.setSelected then loaded.farm.setSelected({}) end end,
    })
  else
    warnf("[app.lua] ui_rayfield.lua missing - UI not loaded. Core still running.")
  end

  -- If this is Brainrot Dungeon profile, initialize dungeon helper if present
  if key == "place:90608986169653" and loaded.dungeon_be and type(loaded.dungeon_be.init) == "function" then
    loaded.dungeon_be.init()
    -- You can expose UI toggles if you decide to show any in Rayfield for this profile.
  end

  log("Ready")
end

-- Export a start() so the executor’s “missing start()” message never appears.
return { start = start }
