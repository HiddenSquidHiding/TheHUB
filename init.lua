-- init.lua (Rayfield-only boot, no HUD)
local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

local function fetch(path)
  local ok, res = pcall(function() return game:HttpGet(BASE .. path) end)
  if not ok then error(('[init] Failed to fetch %s: %s'):format(path, tostring(res))) end
  return res
end

-- tiny utils (exposed globally so sibling modules can find it)
local utils = (function()
  local Players = game:GetService('Players')
  local M = { uiConnections = {} }
  function M.track(conn) table.insert(M.uiConnections, conn); return conn end
  function M.disconnectAll(list) for _,c in ipairs(list) do pcall(function() c:Disconnect() end) end; table.clear(list) end
  function M.new(t, props, parent) local i=Instance.new(t); if props then for k,v in pairs(props) do i[k]=v end end; if parent then i.Parent=parent end; return i end
  function M.notify(title, content, duration)
    local player = Players.LocalPlayer
    local pg = player:FindFirstChildOfClass('PlayerGui') or player:WaitForChild('PlayerGui')
    local sg = M.new('ScreenGui',{ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=2e9},pg)
    local f = M.new('Frame',{Size=UDim2.new(0,300,0,100),Position=UDim2.new(1,-310,0,10),BackgroundColor3=Color3.fromRGB(30,30,30)},sg)
    M.new('TextLabel',{Size=UDim2.new(1,0,0,30),BackgroundColor3=Color3.fromRGB(50,50,50),TextColor3=Color3.new(1,1,1),Text=title,TextSize=14,Font=Enum.Font.SourceSansBold},f)
    M.new('TextLabel',{Size=UDim2.new(1,-10,0,60),Position=UDim2.new(0,5,0,35),BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),Text=content,TextWrapped=true,TextSize=14,Font=Enum.Font.SourceSans},f)
    task.spawn(function() task.wait(duration or 3); sg:Destroy() end)
  end
  function M.waitForCharacter()
    local p = game:GetService('Players').LocalPlayer
    while not p.Character or not p.Character:FindFirstChild('HumanoidRootPart') or not p.Character:FindFirstChild('Humanoid') do
      p.CharacterAdded:Wait(); task.wait(0.1)
    end
    return p.Character
  end
  return M
end)()
_G.__WOODZ_UTILS = utils

-- simple module cache loader (for stand-alone files)
local CACHE = {}
local function use(path)
  if CACHE[path] then return CACHE[path] end
  local src = fetch(path)
  local chunk = loadstring(src, '='..path); assert(chunk, 'Bad chunk for '..path)
  local env = setmetatable({}, { __index = getfenv() })
  setfenv(chunk, env)
  local mod = chunk()
  CACHE[path] = mod
  return mod
end

-- sibling-aware loader (so script.Parent.* works)
local function loadWithSiblings(path, sibs)
  sibs = sibs or {}
  sibs._deps = sibs._deps or {}
  sibs._deps.utils = sibs._deps.utils or utils

  local src = fetch(path)
  local chunk = loadstring(src, '='..path); assert(chunk)
  local baseEnv = getfenv()
  local fakeScript = { Parent = sibs }
  local function shimRequire(target)
    if type(target) == 'table' then return target end
    if target == nil then
      error(("[loader] require(nil) from %s — missing sibling."):format(path))
    end
    return baseEnv.require(target)
  end
  local sandbox = setmetatable({ script=fakeScript, require=shimRequire }, { __index = baseEnv })
  sandbox._G = _G
  sandbox.__WOODZ_UTILS = _G.__WOODZ_UTILS
  setfenv(chunk, sandbox)
  return chunk()
end

-- core data
local constants     = use('constants.lua')
local data_monsters = use('data_monsters.lua')

-- siblings table (NO HUD)
local siblings = { _deps = { utils = utils }, constants = constants, data_monsters = data_monsters }

-- load feature modules (no hud)
local anti_afk   = loadWithSiblings('anti_afk.lua', siblings); siblings.anti_afk = anti_afk
local crates     = loadWithSiblings('crates.lua', siblings);   siblings.crates   = crates
local merchants  = loadWithSiblings('merchants.lua', siblings);siblings.merchants= merchants
local farm       = loadWithSiblings('farm.lua', siblings);     siblings.farm     = farm
local smart      = loadWithSiblings('smart_target.lua', siblings); siblings.smart_target = smart
local ui_rf      = loadWithSiblings('ui_rayfield.lua', siblings);   siblings.ui_rayfield = ui_rf
local redeem     = loadWithSiblings('redeem_unredeemed_codes.lua', siblings); siblings.redeem_unredeemed_codes = redeem
local fastlevel  = loadWithSiblings('fastlevel.lua', siblings); siblings.fastlevel = fastlevel

-- app (expects Rayfield)
local app        = loadWithSiblings('app.lua', siblings)
if app and app.start then
  task.spawn(function()
    local ok, err = pcall(app.start)
    if not ok then warn('[WoodzHUB] app.start error: ', err) end
  end)
else
  warn('[WoodzHUB] app.lua missing start()')
end

utils.notify('🌲 WoodzHUB', 'Loaded without HUD.', 3)
