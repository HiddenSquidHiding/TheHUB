-- init.lua — robust HTTP loader + safe boot

local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

local function fetch(path)
  local ok, res = pcall(function() return game:HttpGet(BASE .. path) end)
  if not ok then error(('[init] Failed to fetch %s: %s'):format(path, tostring(res))) end
  return res
end

local function safeFetch(path)
  local ok, res = pcall(function() return game:HttpGet(BASE .. path) end)
  return ok and res or nil, ok and nil or res
end

-- tiny utils (for notify without relying on other modules)
local function notify(title, msg, dur)
  dur = dur or 4
  pcall(function()
    local Players = game:GetService('Players')
    local player = Players.LocalPlayer
    local PlayerGui = player and player:FindFirstChildOfClass('PlayerGui')
    if not PlayerGui then return end
    local ScreenGui = Instance.new('ScreenGui')
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.DisplayOrder = 2e9
    ScreenGui.Parent = PlayerGui
    local f = Instance.new('Frame')
    f.Size = UDim2.new(0,300,0,90)
    f.Position = UDim2.new(1,-310,0,10)
    f.BackgroundColor3 = Color3.fromRGB(30,30,30)
    f.Parent = ScreenGui
    local t = Instance.new('TextLabel')
    t.Size = UDim2.new(1,0,0,28)
    t.BackgroundColor3 = Color3.fromRGB(50,50,50)
    t.TextColor3 = Color3.new(1,1,1)
    t.Font = Enum.Font.SourceSansBold
    t.TextSize = 14
    t.Text = title
    t.Parent = f
    local c = t:Clone()
    c.BackgroundTransparency = 1
    c.Size = UDim2.new(1,-10,0,54)
    c.Position = UDim2.new(0,5,0,32)
    c.Font = Enum.Font.SourceSans
    c.TextSize = 14
    c.TextWrapped = true
    c.Text = msg
    c.Parent = f
    task.spawn(function() task.wait(dur); ScreenGui:Destroy() end)
  end)
  print(('[%s] %s'):format(title, msg))
end

-- cache + simple use()
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

-- sibling-aware loader
local siblings = { _deps = {} }
local function loadWithSiblings(path, sibs)
  sibs = sibs or siblings
  local src, err = safeFetch(path)
  if not src then return nil, err end
  local chunk, loadErr = loadstring(src, '='..path)
  if not chunk then return nil, loadErr or 'loadstring failed' end
  local baseEnv = getfenv()
  local fakeScript = { Parent = sibs }
  local function shimRequire(target)
    local tt = type(target)
    if tt == 'table' then
      return target -- already a module table
    elseif target == nil then
      error(("[loader] require(nil) from %s — missing sibling"):format(path))
    else
      return baseEnv.require(target) -- normal ModuleScript instance path
    end
  end
  local sandbox = setmetatable({ script = fakeScript, require = shimRequire }, { __index = baseEnv })
  sandbox._G = _G
  setfenv(chunk, sandbox)
  local ok, ret = pcall(chunk)
  if not ok then return nil, ret end
  return ret, nil
end

-- expose minimal utils for modules that look for it
_G.__WOODZ_UTILS = {
  notify = notify,
  track = function(x) return x end,
  disconnectAll = function() end,
  new = function(t, props, parent) local i=Instance.new(t); if props then for k,v in pairs(props) do i[k]=v end end; if parent then i.Parent=parent end; return i end,
  waitForCharacter = function()
    local Players = game:GetService('Players')
    local p = Players.LocalPlayer
    while not p.Character or not p.Character:FindFirstChild('HumanoidRootPart') or not p.Character:FindFirstChildOfClass('Humanoid') do
      p.CharacterAdded:Wait(); task.wait(0.05)
    end
    return p.Character
  end,
}

-- preload some common core (optional, non-fatal if missing)
local function preload(name, filename)
  local mod, err = loadWithSiblings(filename, siblings)
  if mod then siblings[name] = mod else
    print(("-- [init] preload skipped for %s: %s"):format(filename, tostring(err)))
  end
end

-- try to bring these next to app.lua in the "siblings" table so script.Parent[...] works
preload('constants',                 'constants.lua')
preload('hud',                       'hud.lua')
preload('ui_rayfield',               'ui_rayfield.lua')
preload('farm',                      'farm.lua')
preload('merchants',                 'merchants.lua')
preload('crates',                    'crates.lua')
preload('anti_afk',                  'anti_afk.lua')
preload('smart_target',              'smart_target.lua')
preload('redeem_unredeemed_codes',   'redeem_unredeemed_codes.lua')
preload('fastlevel',                 'fastlevel.lua')
preload('games',                     'games.lua')  -- optional

-- finally, load app.lua with siblings available
local app, appErr = loadWithSiblings('app.lua', siblings)
if not app or type(app) ~= 'table' or type(app.start) ~= 'function' then
  notify('🌲 WoodzHUB', '[init] Failed to load app.lua (or .start missing)', 6)
  if appErr then warn(appErr) end
  return
end

local ok, runErr = pcall(function() app.start() end)
if not ok then
  notify('🌲 WoodzHUB', '[init] app.start crashed (see console).', 6)
  warn(runErr)
else
  notify('🌲 WoodzHUB', 'Loaded successfully.', 3)
end
