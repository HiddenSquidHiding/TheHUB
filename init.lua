-- init.lua
-- Replace the BASE to your repo's raw path (keep trailing slash)
local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

local function fetch(path)
  local ok, res = pcall(function() return game:HttpGet(BASE .. path) end)
  if not ok then error('Failed to fetch '..path..': '..tostring(res)) end
  return res
end

-- Lightweight module cache & loader
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

-- Provide a tiny dependency anchor so modules can `require(script.Parent._deps.utils)`
local utilsSrc = fetch('utils.lua')
local utils = (loadstring(utilsSrc, '=utils.lua')())

-- Emulate a folder with children layout via a table
local _deps = { utils = utils }

-- Load base modules
local constants     = use('constants.lua')
local data_monsters = use('data_monsters.lua')
local hud           = use('hud.lua')

-- Helper to load modules that expect sibling-style requires (`script.Parent.X`)
local function loadWithSiblings(path, siblings)
  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk)
  local env = getfenv()
  local fakeScript = { Parent = siblings }
  local sandbox = setmetatable({ script = fakeScript }, {__index = env})
  sandbox._G = _G
  setfenv(chunk, sandbox)
  return chunk()
end

-- Build a sibling table visible as `script.Parent`
local siblings = {
  constants = constants,
  data_monsters = data_monsters,
  hud = hud,
  _deps = _deps, -- exposes utils to siblings
}

-- Load the rest
local crates    = loadWithSiblings('crates.lua', siblings)
local merchants = loadWithSiblings('merchants.lua', siblings)
local farm      = loadWithSiblings('farm.lua', siblings)
local ui        = loadWithSiblings('ui.lua', siblings)

siblings.crates = crates
siblings.merchants = merchants
siblings.farm = farm
siblings.ui = ui

-- Run the app
local app = loadWithSiblings('app.lua', siblings)
app.start()
