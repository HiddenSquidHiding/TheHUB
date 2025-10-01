-- init.lua
-- 👉 Adjust BASE to your repo layout. If files live in /woodzhub/, keep the trailing folder.
local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

-- --- Fetch & simple module cache -----------------------------------------
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

-- --- Embedded utils (so we never depend on network for this) -------------
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

  function M.searchFoldersList()
    local folders={Workspace}
    for _,d in ipairs(Workspace:GetDescendants()) do if d:IsA('Folder') then table.insert(folders,d) end end
    return folders
  end

  return M
end)()

-- Optional global fallback for modules that can’t see script.Parent._deps
_G.__WOODZ_UTILS = utils

-- --- Shared table given to all modules as script.Parent -------------------
local siblings = {
  _deps = { utils = utils },  -- ✅ ensure present up-front
}

-- --- Loader for modules that do require(script.Parent.X) ------------------
local function loadWithSiblings(path, sibs)
  -- extra guard: ensure _deps.utils exists before every load
  sibs._deps = sibs._deps or {}
  sibs._deps.utils = sibs._deps.utils or utils

  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk)

  local baseEnv = getfenv()
  local fakeScript = { Parent = sibs }

  -- Robust require shim:
  -- - If `target` is a table: return it.
  -- - If `target` is nil: throw a helpful error instead of calling require(nil).
  -- - Otherwise: let Roblox require handle Instances/ModuleScript.
  local function shimRequire(target)
    local tt = type(target)
    if tt == 'table' then
      return target
    elseif target == nil then
      error(("[loader] require(nil) from %s — likely missing sibling (e.g. script.Parent._deps.utils). Check init.lua injected fields."):format(path))
    else
      return baseEnv.require(target)
    end
  end

  local sandbox = setmetatable({
    script  = fakeScript,
    require = shimRequire,
  }, { __index = baseEnv })

  sandbox._G = _G
  setfenv(chunk, sandbox)
  return chunk()
end

-- --- Load core modules ----------------------------------------------------
local constants     = use('constants.lua')       -- plain table is fine via `use`
local data_monsters = use('data_monsters.lua')   -- plain table is fine via `use`

-- ⬇️ CHANGED: load HUD with siblings so it gets _deps.utils injected
local hud           = loadWithSiblings('hud.lua', siblings)

siblings.constants     = constants
siblings.data_monsters = data_monsters
siblings.hud           = hud

-- --- Load helpers & app (order ensures siblings are available) -----------
local anti_afk  = loadWithSiblings('anti_afk.lua', siblings)
siblings.anti_afk = anti_afk

local crates    = loadWithSiblings('crates.lua', siblings)
local merchants = loadWithSiblings('merchants.lua', siblings)
local farm      = loadWithSiblings('farm.lua', siblings)
local ui        = loadWithSiblings('ui.lua', siblings)

siblings.crates    = crates
siblings.merchants = merchants
siblings.farm      = farm
siblings.ui        = ui

-- --- Boot the app ---------------------------------------------------------
local app = loadWithSiblings('app.lua', siblings)
app.start()

-- Startup toast
utils.notify('🌲 WoodzHUB', 'Loaded successfully from GitHub modules.', 5)
