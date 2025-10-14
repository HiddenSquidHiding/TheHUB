-- init.lua — WoodzHUB single-entry bootstrap (executor-friendly)

-- ===== guard against double-loads =====
if _G.__WOODZHUB_BOOTED then
  return
end
_G.__WOODZHUB_BOOTED = true

-- ===== base URL to your repo (must end with "/") =====
_G.WOODZ_BASE_URL = _G.WOODZ_BASE_URL or "https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/"

-- ===== tiny helpers =====
local function http_get(path)
  local base = _G.WOODZ_BASE_URL or ""
  if base:sub(-1) ~= "/" then base = base .. "/" end
  local url = base .. path
  return game:HttpGet(url)
end

local function try_load_chunk(src, chunkname)
  local chunk, err = loadstring(src, chunkname or "=chunk")
  if not chunk then error(err or "loadstring failed") end
  local ok, ret = pcall(chunk)
  if not ok then error(ret) end
  return ret
end

-- ===== global utils expected by your modules =====
if rawget(getfenv(), "__WOODZ_UTILS") == nil then
  __WOODZ_UTILS = {
    notify = function(title, msg, dur)
      -- Safe notifier: console + Roblox notification if available
      pcall(function() print(("[%s] %s"):format(title or "WoodzHUB", tostring(msg))) end)
      pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
          Title = tostring(title or "WoodzHUB"),
          Text  = tostring(msg or ""),
          Duration = tonumber(dur) or 3
        })
      end)
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
end

-- ===== optional: preload data_monsters.lua so farm.lua sees it immediately =====
-- (farm.lua also fetches it by itself if this step fails; this just makes it deterministic)
do
  local ok = pcall(function()
    if type(_G.WOODZ_DATA_MONSTERS) ~= "table" then
      local src = http_get("data_monsters.lua")
      local ret = try_load_chunk(src, "=data_monsters.lua")
      if type(ret) ~= "table" then
        error("data_monsters.lua did not return a table")
      end
      _G.WOODZ_DATA_MONSTERS = ret
    end
  end)
  if not ok then
    -- Don't hard-fail here; farm.lua has its own fetch path using _G.WOODZ_BASE_URL
    __WOODZ_UTILS.notify("🌲 WoodzHUB", "data_monsters preload skipped (will be fetched by farm.lua).", 3)
  end
end

-- ===== fetch and run app.lua =====
local app
do
  local ok, src = pcall(function() return http_get("app.lua") end)
  if not ok or type(src) ~= "string" or #src == 0 then
    error("[init] failed to download app.lua")
  end
  local ok2, ret = pcall(function() return try_load_chunk(src, "=app.lua") end)
  if not ok2 then
    error("[init] app.lua load failed: " .. tostring(ret))
  end
  app = ret
end

-- app can be:
--  • a module table with start()   -> call start()
--  • a function (acts like start)  -> call it()
--  • or already side-effecting     -> do nothing
local t = type(app)
if t == "table" and type(app.start) == "function" then
  local ok, err = pcall(app.start)
  if not ok then
    __WOODZ_UTILS.notify("🌲 WoodzHUB", "app.start() error: " .. tostring(err), 6)
  end
elseif t == "function" then
  local ok, err = pcall(app)
  if not ok then
    __WOODZ_UTILS.notify("🌲 WoodzHUB", "app() error: " .. tostring(err), 6)
  end
else
  -- nothing to call; app.lua may have booted itself
end

__WOODZ_UTILS.notify("🌲 WoodzHUB", "Loaded successfully.", 3)
