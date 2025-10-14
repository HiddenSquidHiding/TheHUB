-- app.lua  • WoodzHUB bootstrap (GitHub raw loader + Rayfield UI)
-- Requires: _G.WOODZHUB_BASE = "https://raw.githubusercontent.com/<user>/<repo>/<branch>/"

local TAG = "[WoodzHUB]"
local BASE = (_G.WOODZHUB_BASE or "") .. ""
assert(type(BASE) == "string" and #BASE > 0, TAG .. " _G.WOODZHUB_BASE not set")
if string.sub(BASE, -1) ~= "/" then BASE = BASE .. "/" end

local function log(...) print(TAG, ...) end
local function warnf(...) warn(TAG, ...) end

-- ---------------------- HTTP loader ----------------------
local function http_get(path)
  local url = BASE .. path
  local ok, res = pcall(game.HttpGet, game, url, true)
  if not ok then
    warnf(("[loader] GET failed %s -> %s"):format(url, tostring(res)))
    return nil, url, res
  end
  return res, url
end

local function load_remote(path, required)
  local src, url, err = http_get(path)
  if not src then
    if required then warnf(("required file missing: %s (%s)"):format(path, tostring(err)))
    else warnf(("optional file missing: %s"):format(path)) end
    return nil
  end
  local chunk, lerr = loadstring(src, "=" .. path)
  if not chunk then
    warnf(("loadstring failed for %s: %s"):format(path, tostring(lerr)))
    return nil
  end
  local ok, ret = pcall(chunk)
  if not ok then
    warnf(("runtime error for %s: %s"):format(path, tostring(ret)))
    return nil
  end
  return ret
end

-- ---------------------- utils (very small) ----------------------
local utils = {
  notify = function(title, msg, dur)
    dur = dur or 3
    print(("[%s] %s"):format(title, msg))
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
_G.__WOODZ_UTILS = utils -- make available to modules

-- ---------------------- games profile ----------------------
local function loadGames()
  local cfg = load_remote("games.lua", false)
  if type(cfg) ~= "table" then
    warnf("[app.lua] games.lua missing or invalid; falling back to default")
    cfg = {
      default = {
        name = "Generic",
        modules = { "ui_rayfield", "anti_afk" },
        ui = {
          modelPicker=false,currentTarget=false,autoFarm=false,smartFarm=false,
          merchants=false,crates=false,antiAFK=true,redeemCodes=false,
          fastlevel=false,privateServer=false,dungeon=false
        }
      }
    }
  end
  return cfg
end

local function pickProfile(cfg)
  local placeKey = "place:" .. tostring(game.PlaceId)
  if cfg[placeKey] then return placeKey, cfg[placeKey] end
  local uniKey = "universe:" .. tostring(game.GameId)
  if cfg[uniKey] then return uniKey, cfg[uniKey] end
  return "default", cfg.default
end

-- ---------------------- Module cache ----------------------
local loaded = {}
local function try_mod(name)
  if loaded[name] ~= nil then return loaded[name] end
  local mod = load_remote(name .. ".lua", false)
  if not mod then
    warnf(("optional module '%s' not available"):format(name))
    loaded[name] = false
    return nil
  end
  loaded[name] = mod
  return mod
end

-- ---------------------- Boot ----------------------
local function start()
  local cfg = loadGames()
  local key, prof = pickProfile(cfg)
  log(("profile: %s (key=%s)"):format(prof.name or "?", key))

  -- Load requested modules (soft)
  for _, m in ipairs(prof.modules or {}) do
    if not try_mod(m) then warnf(("module unavailable (skipped): %s"):format(m)) end
  end

  -- UI (Rayfield)
  local ui_mod = try_mod("ui_rayfield")
  local RF = nil
  if ui_mod and type(ui_mod.build) == "function" then
    -- handlers we expose to UI
    local anti_afk = try_mod("anti_afk")
    local dungeon  = try_mod("dungeon_be")
    local farm     = try_mod("farm")
    local redeem   = try_mod("redeem_unredeemed_codes")

    local state = {
      afk=false, dungeonAuto=false, dungeonReplay=true,
      autoFarm=false
    }

    local handlers = {
      onToggleAntiAFK = function(v)
        state.afk = not not v
        if anti_afk then
          if state.afk then anti_afk.enable() else anti_afk.disable() end
        end
        utils.notify("🌲 Anti-AFK", state.afk and "enabled" or "disabled", 3)
      end,

      onDungeonAuto = function(v)
        state.dungeonAuto = not not v
        if dungeon and dungeon.init then dungeon.init() end
        if dungeon and dungeon.setAuto then dungeon.setAuto(state.dungeonAuto) end
        utils.notify("🌲 Dungeon", state.dungeonAuto and "auto ON" or "auto OFF", 3)
      end,

      onDungeonReplay = function(v)
        state.dungeonReplay = not not v
        if dungeon and dungeon.setReplay then dungeon.setReplay(state.dungeonReplay) end
        utils.notify("🌲 Dungeon", "Replay " .. (state.dungeonReplay and "ON" or "OFF"), 3)
      end,

      onRedeemCodes = function()
        if redeem and redeem.run then
          task.spawn(function()
            local ok, err = pcall(function()
              redeem.run({ dryRun=false, concurrent=true, delayBetween=0.25 })
            end)
            if not ok then utils.notify("Codes", "Redeem failed: "..tostring(err), 4) end
          end)
        else
          utils.notify("Codes","redeem_unredeemed_codes.lua missing",3)
        end
      end,
    }

    RF = ui_mod.build({
      handlers = handlers,
      flags = prof.ui or {},
      title = prof.name or "WoodzHUB",
    })
  else
    warnf("[ui_rayfield] Rayfield failed to load")
  end

  -- Auto-start dungeon if this profile wants it and UI didn’t add controls
  if (prof.ui and prof.ui.dungeon) then
    local dungeon = try_mod("dungeon_be")
    if dungeon and dungeon.init then
      dungeon.init()
      -- don’t auto-run; user can toggle in UI
    end
  end

  log("Ready")
end

-- Expose start() for older bootstraps, then run it now
_G.WOODZHUB_START = start
start()
