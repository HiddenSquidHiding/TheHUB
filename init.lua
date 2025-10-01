-- init.lua
local BASE = 'https://raw.githubusercontent.com/HiddenSquidHiding/TheHUB/main/'

-- Fetch helper
local function fetch(path)
  local ok, res = pcall(function() return game:HttpGet(BASE .. path) end)
  if not ok then error(('[init] Failed to fetch %s: %s'):format(path, tostring(res))) end
  return res
end

-- Simple in-memory cache
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

--------------------------------------------------------------------
-- Embedded utils (local; no network)
--------------------------------------------------------------------
local utils = (function()
  local Players  = game:GetService('Players')
  local Workspace = game:GetService('Workspace')
  local M = { uiConnections = {} }

  function M.track(conn) table.insert(M.uiConnections, conn) return conn end
  function M.disconnectAll(list) for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end; table.clear(list) end
  function M.new(t, props, parent) local i = Instance.new(t); if props then for k,v in pairs(props) do i[k]=v end end; if parent then i.Parent=parent end; return i end

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
    local player = game:GetService('Players').LocalPlayer
    while not player.Character or not player.Character:FindFirstChild('HumanoidRootPart') or not player.Character:FindFirstChild('Humanoid') do
      player.CharacterAdded:Wait(); task.wait(0.1)
    end
    return player.Character
  end

  function M.isValidCFrame(cf) if not cf then return false end; local p=cf.Position; return p.X==p.X and p.Y==p.Y and p.Z==p.Z and math.abs(p.X)<10000 and math.abs(p.Y)<10000 and math.abs(p.Z)<10000 end
  function M.findBasePart(model) if not model then return nil end; local names={'HumanoidRootPart','PrimaryPart','Body','Hitbox','Root','Main'}; for _,n in ipairs(names) do local part=model:FindFirstChild(n); if part and part:IsA('BasePart') then return part end end; for _,d in ipairs(model:GetDescendants()) do if d:IsA('BasePart') then return d end end; return nil end
  function M.searchFoldersList() local folders={Workspace}; for _,d in ipairs(Workspace:GetDescendants()) do if d:IsA('Folder') then table.insert(folders,d) end end; return folders end

  return M
end)()

-- Sibling registry visible as `script.Parent`
local siblings = { _deps = { utils = utils } }

-- Hardened shim loader for modules that do `require(script.Parent.X)`
local function loadWithSiblings(path, sibs)
  local src = fetch(path)
  local chunk = loadstring(src, '='..path)
  assert(chunk)

  local baseEnv = getfenv()
  local fakeScript = { Parent = sibs }

  local function shimRequire(target)
    -- If they passed one of our injected tables (or any non-ModuleScript), just return it
    if target == nil then
      error(("[loader] require(nil) from %s — likely missing sibling (e.g. script.Parent._deps.utils). Check init.lua injected fields."):format(path), 2)
    end
    local t = typeof(target)
    if t ~= "Instance" then
      return target
    end
    if target:IsA("ModuleScript") then
      return baseEnv.require(target)
    else
      -- Non-ModuleScript Instance — return as-is (or error)
      return target
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

-- Load core modules (these must exist in your repo)
local constants     = use('constants.lua')
local data_monsters = use('data_monsters.lua')
local hud           = use('hud.lua')
siblings.constants     = constants
siblings.data_monsters = data_monsters
siblings.hud           = hud

-- Load helpers then app
local anti_afk  = loadWithSiblings('anti_afk.lua', siblings)
local crates    = loadWithSiblings('crates.lua', siblings)
local merchants = loadWithSiblings('merchants.lua', siblings)
local farm      = loadWithSiblings('farm.lua', siblings)
local ui        = loadWithSiblings('ui.lua', siblings)
siblings.anti_afk  = anti_afk
siblings.crates    = crates
siblings.merchants = merchants
siblings.farm      = farm
siblings.ui        = ui

local app = loadWithSiblings('app.lua', siblings)
app.start()

-- Startup toast
utils.notify('🌲 WoodzHUB', 'Loaded successfully from GitHub modules.', 5)
