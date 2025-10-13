local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

local function httpget(path)
  return game:HttpGet(BASE .. path)
end

local function fetch(path)
  local ok, res = pcall(function() return httpget(path) end)
  if not ok then error(('[init] Failed to fetch %s: %s'):format(path, tostring(res))) end
  return res
end

local function safeFetch(path)
  local ok, res = pcall(function() return httpget(path) end)
  return ok and res or nil, ok and nil or res
end

-- minimal utils so modules can run during preload
local function notify(title, msg, dur)
  dur = dur or 4
  print(('[%s] %s'):format(title, msg))
  pcall(function()
    local Players = game:GetService('Players')
    local player = Players.LocalPlayer
    local pg = player and player:FindFirstChildOfClass('PlayerGui')
    if not pg then return end
    local gui = Instance.new('ScreenGui')
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 2e9
    gui.Parent = pg
    local f = Instance.new('Frame')
    f.BackgroundColor3 = Color3.fromRGB(30,30,30)
    f.Size = UDim2.new(0,300,0,90)
    f.Position = UDim2.new(1,-310,0,10)
    f.Parent = gui
    local t = Instance.new('TextLabel')
    t.BackgroundColor3 = Color3.fromRGB(50,50,50)
    t.TextColor3 = Color3.new(1,1,1)
    t.Font = Enum.Font.SourceSansBold
    t.TextSize = 14
    t.Text = title
    t.Size = UDim2.new(1,0,0,28)
    t.Parent = f
    local c = t:Clone()
    c.BackgroundTransparency = 1
    c.Font = Enum.Font.SourceSans
    c.TextWrapped = true
    c.Text = msg
    c.Size = UDim2.new(1,-10,0,54)
    c.Position = UDim2.new(0,5,0,32)
    c.Parent = f
    task.spawn(function() task.wait(dur); gui:Destroy() end)
  end)
end

_G.__WOODZ_UTILS = {
  notify = notify,
  track = function(x) return x end,
  disconnectAll = function() end,
  new = function(t, props, parent)
    local i=Instance.new(t)
    if props then for k,v in pairs(props) do i[k]=v end end
    if parent then i.Parent=parent end
    return i
  end,
  waitForCharacter = function()
    local Players = game:GetService('Players')
    local p = Players.LocalPlayer
    while not p.Character
      or not p.Character:FindFirstChild('HumanoidRootPart')
      or not p.Character:FindFirstChildOfClass('Humanoid') do
      p.CharacterAdded:Wait(); task.wait(0.05)
    end
    return p.Character
  end,
}

-- shared siblings table used as script.Parent for every module
local siblings = {
  _deps = { utils = __WOODZ_UTILS }, -- <-- IMPORTANT: inject utils here
}

-- helper: detect obvious non-Lua content (HTML/Markdown/JSON error)
local function looksNonLua(s)
  if not s or #s == 0 then return true end
  -- common first chars for non-lua: '<' (HTML), '{' (JSON error), '#' (markdown)
  local first = s:sub(1,1)
  if first == '<' or first == '{' or first == '#' then return true end
  -- also catch GitHub 404 JSON
  if s:find('"Not Found"') or s:find('<!DOCTYPE') then return true end
  return false
end

local function loadWithSiblings(path, sibs)
  sibs = sibs or siblings
  local src, err = safeFetch(path)
  if not src then return nil, err end
  if looksNonLua(src) then
    return nil, ('%s does not look like Lua (got non-Lua/404/markdown). Check your BASE URL or file path.'):format(path)
  end
  local chunk, loadErr = loadstring(src, '='..path)
  if not chunk then return nil, loadErr or 'loadstring failed' end
  local baseEnv = getfenv()
  local fakeScript = { Parent = sibs }
  local function shimRequire(target)
    local tt = type(target)
    if tt == 'table' then
      return target
    elseif target == nil then
      error(("[loader] require(nil) from %s — missing sibling"):format(path))
    else
      return baseEnv.require(target)
    end
  end
  local sandbox = setmetatable({ script = fakeScript, require = shimRequire }, { __index = baseEnv })
  sandbox._G = _G
  setfenv(chunk, sandbox)
  local ok, ret = pcall(chunk)
  if not ok then return nil, ret end
  return ret, nil
end

local function preload(name, filename)
  local mod, err = loadWithSiblings(filename, siblings)
  if mod then
    siblings[name] = mod
  else
    print(("-- [init] preload skipped for %s: %s"):format(filename, tostring(err)))
  end
end

-- try to preload these; missing ones won’t crash
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
preload('games',                     'games.lua')

-- finally, load app.lua
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
