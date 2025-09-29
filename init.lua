-- init.lua
local BASE = 'https://raw.githubusercontent.com/USER/REPO/BRANCH/woodzhub/'

local function fetch(path)
  local ok, res = pcall(function() return game:HttpGet(BASE .. path) end)
  if not ok then error('Failed to fetch '..path..': '..tostring(res)) end
  return res
end

local CACHE = {}
local function use(path)
  if CACHE[path] then return CACHE[path] end
  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk, 'Bad chunk for '..path)
  local env = setmetatable({}, {__index = getfenv()})
  setfenv(chunk, env)
  local mod = chunk()
  CACHE[path] = mod
  return mod
end

local utilsSrc = fetch('utils.lua')
local utils = (loadstring(utilsSrc, '=utils.lua')())

local _deps = { utils = utils }

local constants     = use('constants.lua')
local data_monsters = use('data_monsters.lua')
local hud           = use('hud.lua')

local function loadWithSiblings(path, siblings)
  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk)
  local baseEnv = getfenv()
  local fakeScript = { Parent = siblings }
  local function shimRequire(target)
    if type(target) == 'table' then return target end
    return baseEnv.require(target)
  end
  local sandbox = setmetatable({ script = fakeScript, require = shimRequire }, { __index = baseEnv })
  sandbox._G = _G
  setfenv(chunk, sandbox)
  return chunk()
end

local siblings = {
  constants = constants,
  data_monsters = data_monsters,
  hud = hud,
  _deps = _deps,
}

-- NEW: load anti_afk before app/farm so require() works
local anti_afk = loadWithSiblings('anti_afk.lua', siblings)
siblings.anti_afk = anti_afk

local crates    = loadWithSiblings('crates.lua', siblings)
local merchants = loadWithSiblings('merchants.lua', siblings)
local farm      = loadWithSiblings('farm.lua', siblings)
local ui        = loadWithSiblings('ui.lua', siblings)

siblings.crates = crates
siblings.merchants = merchants
siblings.farm = farm
siblings.ui = ui

local app = loadWithSiblings('app.lua', siblings)
app.start()
