-- init.lua (robust lazy loader; no preload)
-- Fetches modules from GitHub, injects a sibling table that behaves like a Folder,
-- supports games.lua profiles, then boots app.lua (or a per-game runner).

local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

-- -------------------------------------------------------------
-- Fetch + simple cached "use(path)"
-- -------------------------------------------------------------
local function fetch(path)
  local ok, res = pcall(function() return game:HttpGet(BASE .. path) end)
  if not ok then error(('[init] Failed to fetch %s: %s'):format(path, tostring(res))) end
  return res
end

local CACHE = {}
local function use(path)
  if CACHE[path] then return CACHE[path] end
  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk, 'Bad chunk for '..path)
  local env = setmetatable({}, { __index = getfenv() })
  setfenv(chunk, env)
  local mod = chunk()
  CACHE[path] = mod
  return mod
end

-- -------------------------------------------------------------
-- Minimal utils (also exported globally)
-- -------------------------------------------------------------
local utils = (function()
  local Players   = game:GetService('Players')
  local Workspace = game:GetService('Workspace')
  local M = { uiConnections = {} }
  function M.track(conn) table.insert(M.uiConnections, conn) return conn end
  function M.disconnectAll(list) for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end; table.clear(list) end
  function M.new(t, props, parent) local i=Instance.new(t); if props then for k,v in pairs(props) do i[k]=v end end; if parent then i.Parent=parent end; return i end
  function M.notify(title, content, duration)
    local player = Players.LocalPlayer
    local PlayerGui = player:WaitForChild('PlayerGui')
    local ScreenGui = M.new('ScreenGui', {ResetOnSpawn=false, ZIndexBehavior=Enum.ZIndexBehavior.Sibling, DisplayOrder=2e9}, PlayerGui)
    local frame = M.new('Frame', {Size=UDim2.new(0,300,0,100), Position=UDim2.new(1,-310,0,10), BackgroundColor3=Color3.fromRGB(30,30,30)}, ScreenGui)
    M.new('TextLabel', {Size=UDim2.new(1,0,0,30), BackgroundColor3=Color3.fromRGB(50,50,50), TextColor3=Color3.new(1,1,1), Text=title, TextSize=14, Font=Enum.Font.SourceSansBold}, frame)
    M.new('TextLabel', {Size=UDim2.new(1,-10,0,60), Position=UDim2.new(0,5,0,35), BackgroundTransparency=1, TextColor3=Color3.new(1,1,1), Text=content, TextWrapped=true, TextSize=14, Font=Enum.Font.SourceSans}, frame)
    task.spawn(function() task.wait(duration or 5) ScreenGui:Destroy() end)
  end
  function M.waitForCharacter()
    local player = Players.LocalPlayer
    while not player.Character or not player.Character:FindFirstChild('HumanoidRootPart') or not player.Character:FindFirstChild('Humanoid') do
      player.CharacterAdded:Wait(); task.wait(0.1)
    end
    return player.Character
  end
  function M.isValidCFrame(cf)
    if not cf then return false end
    local p=cf.Position
    return p.X==p.X and p.Y==p.Y and p.Z==p.Z and math.abs(p.X)<10000 and math.abs(p.Y)<10000 and math.abs(p.Z)<10000
  end
  function M.findBasePart(model)
    if not model then return nil end
    local names={'HumanoidRootPart','PrimaryPart','Body','Hitbox','Root','Main'}
    for _,n in ipairs(names) do local part=model:FindFirstChild(n); if part and part:IsA('BasePart') then return part end end
    for _,d in ipairs(model:GetDescendants()) do if d:IsA('BasePart') then return d end end
    return nil
  end
  return M
end)()

_G.__WOODZ_UTILS = utils

-- -------------------------------------------------------------
-- Sibling table acting like script.Parent
--   - lazy loads "<name>.lua" on first access
--   - provides :FindFirstChild / :WaitForChild / :IsA to satisfy code that treats it like an Instance
-- -------------------------------------------------------------
local siblings = { _deps = { utils = utils } }

local function loadWithSiblings(path)
  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk, ('[loader] compile failed for %s'):format(path))
  local baseEnv = getfenv()

  local function shimRequire(target)
    local tt = type(target)
    if tt == 'table' then
      return target
    elseif target == nil then
      error(("[loader] require(nil) from %s — missing sibling."):format(path))
    else
      return baseEnv.require(target)
    end
  end

  local sandbox = setmetatable({ script = { Parent = siblings }, require = shimRequire }, { __index = baseEnv })
  sandbox._G = _G
  setfenv(chunk, sandbox)
  return chunk()
end

local function lazyLoadKey(k)
  local filename = tostring(k) .. ".lua"
  local ok, mod = pcall(function() return loadWithSiblings(filename) end)
  if ok then return mod end
  return nil
end

setmetatable(siblings, {
  __index = function(t, k)
    -- Instance-like helpers
    if k == 'FindFirstChild' then
      return function(self, name) return rawget(self, name) end
    elseif k == 'WaitForChild' then
      return function(self, name, timeout)
        local t0 = tick()
        local v = rawget(self, name)
        while not v do
          if timeout and (tick()-t0) > timeout then return nil end
          task.wait(0.05)
          v = rawget(self, name)
        end
        return v
      end
    elseif k == 'IsA' then
      return function(self, className) return className == 'Folder' or className == 'Instance' end
    elseif k == '_deps' then
      return rawget(t, k)
    end
    -- lazy sibling load
    local mod = lazyLoadKey(k)
    if mod ~= nil then
      rawset(t, k, mod)
      return mod
    end
    return nil
  end
})

-- -------------------------------------------------------------
-- Shared data
-- -------------------------------------------------------------
local constants     = use('constants.lua')
local data_monsters = use('data_monsters.lua')
siblings.constants     = constants
siblings.data_monsters = data_monsters

-- -------------------------------------------------------------
-- Profile selection (games.lua)
-- -------------------------------------------------------------
local function selectProfile()
  local gamesTbl = use('games.lua')
  local placeKey    = "place:" .. tostring(game.PlaceId)
  local universeKey = "universe:" .. tostring(game.GameId)
  local prof = nil
  if type(gamesTbl) == "table" then
    prof = gamesTbl[placeKey] or gamesTbl[universeKey] or gamesTbl[tostring(game.GameId)] or gamesTbl.default
  end
  return prof, gamesTbl
end

local profile = selectProfile()

-- -------------------------------------------------------------
-- Boot
-- -------------------------------------------------------------
local function boot()
  -- If profile specifies a dedicated runner, run it and exit
  if profile and type(profile) == "table" and type(profile.run) == "string" and #profile.run > 0 then
    local runnerPath = profile.run .. '.lua'
    local ok, err = pcall(function()
      local mod = loadWithSiblings(runnerPath)
      if type(mod) == "table" and type(mod.start) == "function" then mod.start() end
    end)
    if not ok then warn("[init] games.run failed: ", err) end
    return
  end

  -- Normal app
  local ok, app = pcall(function() return loadWithSiblings('app.lua') end)
  if not ok or not app or not app.start then
    error("[init] Failed to load app.lua (or .start missing)")
  end
  app.start()
  utils.notify('🌲 WoodzHUB', ('Loaded profile: %s'):format((profile and profile.name) or "Default"), 4)
end

boot()
