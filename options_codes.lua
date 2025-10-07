-- options_codes.lua
-- Injects two buttons into the Options tab:
--  (1) Preview Unredeemed  (dry run)
--  (2) Redeem Unredeemed   (actual redeem)
--
-- This module searches the existing WoodzHUB GUI for the Options panel (LoggingTabFrame)
-- and appends a small button row at the bottom.

-- 🔧 Safe utils access
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  -- minimal fallbacks
  return {
    notify = function(title, msg) print(("[%s] %s"):format(title, msg)) end,
    new = function(t, props, parent)
      local i = Instance.new(t)
      if props then for k,v in pairs(props) do i[k] = v end end
      if parent then i.Parent = parent end
      return i
    end
  }
end

local utils = getUtils()
local new = utils.new

-- robust finder for the Options/LoggingTabFrame under your GUI
local function findOptionsContainer()
  local Players = game:GetService("Players")
  local plr = Players.LocalPlayer
  local pg = plr:WaitForChild("PlayerGui", 10)
  if not pg then return nil end

  -- Find ScreenGui named "WoodzHUB"
  local gui = pg:FindFirstChild("WoodzHUB") or pg:FindFirstChildOfClass("ScreenGui")
  if not gui then return nil end

  -- Try common paths
  local function deepFind(root, wanted)
    if not root then return nil end
    if root.Name == wanted then return root end
    for _, d in ipairs(root:GetDescendants()) do
      if d.Name == wanted then return d end
    end
    return nil
  end

  -- Options tab was previously named LoggingTabFrame
  local opt = deepFind(gui, "LoggingTabFrame") or deepFind(gui, "OptionsFrame") or deepFind(gui, "OptionsTab")
  return opt
end

local function injectButtons(container, onPreview, onRedeem)
  -- simple row with 2 buttons
  local row = new("Frame", {
    Name = "CodesRow",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -20, 0, 34),
    Position = UDim2.new(0, 10, 1, -44), -- bottom with margin
  }, container)

  local ui = new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 10),
  }, row)

  local function mkBtn(txt)
    return new("TextButton", {
      BackgroundColor3 = Color3.fromRGB(60,60,60),
      TextColor3       = Color3.fromRGB(255,255,255),
      Text             = txt,
      Font             = Enum.Font.SourceSans,
      TextSize         = 14,
      Size             = UDim2.new(0, 190, 0, 32),
      AutoButtonColor  = true,
    }, row)
  end

  local previewBtn = mkBtn("Preview Unredeemed Codes")
  local redeemBtn  = mkBtn("Redeem Unredeemed Codes")

  previewBtn.MouseButton1Click:Connect(function()
    onPreview()
  end)
  redeemBtn.MouseButton1Click:Connect(function()
    onRedeem()
  end)
end

-- Lazy-require the logic module (sibling)
local function getRedeemModule()
  local p = script and script.Parent
  if p and p:FindFirstChild("redeem_unredeemed_codes") then
    local ok, mod = pcall(function() return require(p.redeem_unredeemed_codes) end)
    if ok then return mod end
  end
  -- fallback: global search (if your loader put it elsewhere)
  for _, d in ipairs(getloadedmodules()) do
    if d.Name == "redeem_unredeemed_codes" then
      local ok, mod = pcall(function() return require(d) end)
      if ok then return mod end
    end
  end
  return nil
end

-- Public entry
local M = {}

function M.start()
  local container = findOptionsContainer()
  if not container then
    utils.notify("Codes", "Options tab not found (LoggingTabFrame). Load GUI first, then require options_codes.lua")
    return
  end

  local logic = getRedeemModule()
  if not logic then
    utils.notify("Codes", "redeem_unredeemed_codes.lua missing/failed to load")
    return
  end

  injectButtons(container,
    function() -- Preview
      task.spawn(function()
        logic.run({ dryRun = true }) -- just list
      end)
    end,
    function() -- Redeem
      task.spawn(function()
        logic.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
      end)
    end
  )

  utils.notify("Codes", "Options: added Preview/Redeem buttons.")
end

return M
