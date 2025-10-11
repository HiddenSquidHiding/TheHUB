-- init.lua (hardened)
-- Fetch modules from GitHub, inject sibling loader (with lazy autoload),
-- preload app dependencies to prevent require(nil) inside app.lua,
-- support games.lua profiles and one-off "run" scripts.

-- 👉 Point BASE at your repo:
local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

----------------------------------------------------------------------
-- Fetch + cached "use"
----------------------------------------------------------------------
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

----------------------------------------------------------------------
-- Minimal utils (also exported on _G for sibling modules)
----------------------------------------------------------------------
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
    local Players = game:GetService('Players')
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
    for _,d in ipairs(Workspace:GetDescendants()) do if d:IsA('BasePart') then return d end end
    return nil
  end
  function M.searchFoldersList()
    local folders={Workspace}
    for _,d in ipairs(Workspace:GetDescendants()) do if d:IsA('Folder') then table.insert(folders,d) end end
    return folders
  end
  return M
end)()

_G.__WOODZ_UTILS = utils

----------------------------------------------------------------------
-- Sibling loader with LAZY AUTOLOAD
----------------------------------------------------------------------
local siblings = { _deps = { utils = utils } }

local function loadWithSiblings(path, sibs)
  sibs._deps = sibs._deps or {}
  sibs._deps.utils = sibs._deps.utils or utils
  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk, ('[loader] compile failed for %s'):format(path))
  local baseEnv = getfenv()
  local fakeScript = { Parent = sibs }
  local function shimRequire(target)
    local tt = type(target)
    if tt == 'table' then
      return target
    elseif target == nil then
      error(("[loader] require(nil) from %s — likely missing sibling (e.g. script.Parent.<module>)."):format(path))
    else
      return baseEnv.require(target)
    end
  end
  local sandbox = setmetatable({ script = fakeScript, require = shimRequire }, { __index = baseEnv })
  sandbox._G = _G
  setfenv(chunk, sandbox)
  return chunk()
end

-- Lazy autoload: access siblings.<name> → load "<name>.lua" once
setmetatable(siblings, {
  __index = function(t, k)
    if k == nil or k == "_deps" then return rawget(t, k) end
    local filename = tostring(k) .. ".lua"
    local ok, mod = pcall(function() return loadWithSiblings(filename, siblings) end)
    if ok and mod ~= nil then
      rawset(t, k, mod)
      return mod
    end
    -- If missing, return nil so require(nil) gives a helpful error from shim.
    return nil
  end
})

----------------------------------------------------------------------
-- Shared data tables
----------------------------------------------------------------------
local constants     = use('constants.lua')
local data_monsters = use('data_monsters.lua')
siblings.constants     = constants
siblings.data_monsters = data_monsters

-- Preload HUD (common dependency for UI)
local hud = loadWithSiblings('hud.lua', siblings)
siblings.hud = hud

----------------------------------------------------------------------
-- Profile selection
----------------------------------------------------------------------
local function selectProfile()
  local games = use('games.lua')  -- returns table
  local placeKey    = "place:" .. tostring(game.PlaceId)
  local universeKey = "universe:" .. tostring(game.GameId)
  local prof = nil
  if type(games) == "table" then
    prof = games[placeKey] or games[universeKey] or games[tostring(game.GameId)] or games.default
  end
  return prof, games
end

local profile = selectProfile()

----------------------------------------------------------------------
-- Safe preload so app.lua never sees nil siblings on require(script.Parent.X)
----------------------------------------------------------------------
local function preloadModules(list)
  for _, name in ipairs(list) do
    local file = name .. '.lua'
    local ok, mod = pcall(function() return loadWithSiblings(file, siblings) end)
    if ok and mod ~= nil then
      siblings[name] = mod
    else
      warn(("[init] preload failed for %s: %s"):format(file, tostring(mod)))
    end
  end
end

-- Always preload the standard set app.lua expects
local ALWAYS_PRELOAD = {
  'ui_rayfield','farm','merchants','crates','anti_afk',
  'smart_target','redeem_unredeemed_codes','fastlevel'
}

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------
local function boot()
  -- Also preload any profile-declared modules (optional)
  if profile and type(profile) == "table" and type(profile.modules) == "table" then
    preloadModules(profile.modules)
  end
  preloadModules(ALWAYS_PRELOAD)

  -- If profile specifies a direct runner script, execute it and stop.
  if profile and type(profile.run) == "string" and #profile.run > 0 then
    local runnerPath = profile.run .. '.lua'
    local ok, err = pcall(function()
      local mod = loadWithSiblings(runnerPath, siblings)
      if type(mod) == "table" and type(mod.start) == "function" then
        mod.start()
      end
    end)
    if not ok then warn("[init] games.run failed: ", err) end
    return
  end

  -- Otherwise run the main app
  local app = loadWithSiblings('app.lua', siblings)
  app.start()
  local name = (profile and profile.name) or "Default"
  utils.notify('🌲 WoodzHUB', ('Loaded profile: %s'):format(name), 4)
end

boot()
