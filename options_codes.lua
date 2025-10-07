-- options_codes.lua
-- Adds two buttons to the Options tab:
--   1) Preview Unredeemed Codes  (dry run)
--   2) Redeem Unredeemed Codes   (actual redeem)
-- Robustly waits for GUI to exist before injecting.

----------------------------------------------------------------------
-- Minimal utils (works even if your global utils aren't injected)
----------------------------------------------------------------------
local function notify(title, msg, dur)
  dur = dur or 3
  print(("[%s] %s"):format(title, msg))
  -- If you have your own notify, you can swap this out.
end

local function new(t, props, parent)
  local i = Instance.new(t)
  if props then for k,v in pairs(props) do i[k]=v end end
  if parent then i.Parent = parent end
  return i
end

local function tryRequireSibling(name)
  local p = script and script.Parent
  if p and p:FindFirstChild(name) then
    local ok, mod = pcall(function() return require(p[name]) end)
    if ok then return mod end
  end
  -- Last-resort: check loaded modules by name
  if getloadedmodules then
    for _,m in ipairs(getloadedmodules()) do
      if typeof(m)=="Instance" and m:IsA("ModuleScript") and m.Name==name then
        local ok, mod = pcall(function() return require(m) end)
        if ok then return mod end
      end
    end
  end
  return nil
end

----------------------------------------------------------------------
-- Finder: locate the Options container
----------------------------------------------------------------------
local Players = game:GetService("Players")

local function deepFind(root, name)
  if not root then return nil end
  if root.Name == name then return root end
  for _, d in ipairs(root:GetDescendants()) do
    if d.Name == name then return d end
  end
  return nil
end

local function findOptionsContainerOnce()
  local plr = Players.LocalPlayer
  local pg = plr and plr:FindFirstChildOfClass("PlayerGui")
  if not pg then return nil, "PlayerGui missing" end

  -- Prefer the WoodzHUB ScreenGui if present
  local hub = pg:FindFirstChild("WoodzHUB")
  if not hub then
    -- Fall back to any ScreenGui that contains our Options frame
    for _, sg in ipairs(pg:GetChildren()) do
      if sg:IsA("ScreenGui") then
        local hit = deepFind(sg, "LoggingTabFrame") or deepFind(sg, "OptionsFrame") or deepFind(sg, "OptionsTab")
        if hit then return hit end
      end
    end
    return nil, "Options frame not found yet"
  end

  local container = deepFind(hub, "LoggingTabFrame") or deepFind(hub, "OptionsFrame") or deepFind(hub, "OptionsTab")
  if not container then return nil, "Options frame not found yet" end
  return container
end

local function waitForOptionsContainer(timeout)
  timeout = timeout or 10
  local t0 = os.clock()
  while (os.clock() - t0) < timeout do
    local c, why = findOptionsContainerOnce()
    if c then return c end
    task.wait(0.25)
  end
  return nil, "Timed out waiting for Options container"
end

----------------------------------------------------------------------
-- UI injection
----------------------------------------------------------------------
local function injectButtons(container, logic)
  if not container then return false, "no container" end
  if not logic or type(logic.run) ~= "function" then
    return false, "redeem_unredeemed_codes module missing or invalid"
  end

  -- Avoid duplicates
  if container:FindFirstChild("Woodz_CodesRow") then
    return true
  end

  -- If the options container is a ScrollingFrame, respect its layout.
  local parentForRow = container
  local isScroll = container:IsA("ScrollingFrame")

  local row = new("Frame", {
    Name = "Woodz_CodesRow",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, -20, 0, 36),
    AnchorPoint = Vector2.new(0, 1),
    Position = isScroll and UDim2.new(0, 10, 0, (container.CanvasSize.Y.Offset or 0) + 10)
                         or UDim2.new(0, 10, 1, -46),
  }, parentForRow)

  local layout = new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 10),
  }, row)

  local function mkBtn(text)
    return new("TextButton", {
      BackgroundColor3 = Color3.fromRGB(60, 60, 60),
      TextColor3       = Color3.fromRGB(255, 255, 255),
      Font             = Enum.Font.SourceSans,
      TextSize         = 14,
      Size             = UDim2.new(0, 200, 0, 32),
      AutoButtonColor  = true,
      Text             = text,
    }, row)
  end

  local previewBtn = mkBtn("Preview Unredeemed Codes")
  local redeemBtn  = mkBtn("Redeem Unredeemed Codes")

  previewBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
      notify("Codes", "Previewing unredeemed codes…")
      local ok = logic.run({ dryRun = true })
      if ok then
        notify("Codes", "Preview complete — check console for list.")
      else
        notify("Codes", "Preview failed. See console.")
      end
    end)
  end)

  redeemBtn.MouseButton1Click:Connect(function()
    task.spawn(function()
      notify("Codes", "Redeeming unredeemed codes…")
      local ok = logic.run({ dryRun = false, concurrent = true, delayBetween = 0.25 })
      if ok then
        notify("Codes", "Redeem run finished. See console for results.")
      else
        notify("Codes", "Redeem failed. See console.")
      end
    end)
  end)

  -- If container is a ScrollingFrame, try to extend canvas so the row is reachable.
  if isScroll then
    local current = container.CanvasSize
    local needed  = (current.Y.Offset or 0) + 60
    container.CanvasSize = UDim2.new(0, 0, 0, needed)
  end

  return true
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------
local M = {}

-- Option A: let the module find the container (with retry)
function M.start()
  -- Load logic module
  local logic = tryRequireSibling("redeem_unredeemed_codes")
  if not logic then
    notify("Codes", "redeem_unredeemed_codes.lua missing or failed to load")
    return
  end

  local container, why = waitForOptionsContainer(12)
  if not container then
    notify("Codes", "Options tab not ready: " .. tostring(why))
    return
  end

  local ok, err = injectButtons(container, logic)
  if not ok then
    notify("Codes", "Failed to inject buttons: " .. tostring(err))
    return
  end
  notify("Codes", "Options: added Preview/Redeem buttons.")
end

-- Option B: pass your Options container explicitly (no waiting)
function M.startWithContainer(container)
  local logic = tryRequireSibling("redeem_unredeemed_codes")
  if not logic then
    notify("Codes", "redeem_unredeemed_codes.lua missing or failed to load")
    return
  end
  local ok, err = injectButtons(container, logic)
  if not ok then
    notify("Codes", "Failed to inject buttons: " .. tostring(err))
    return
  end
  notify("Codes", "Options (explicit): added Preview/Redeem buttons.")
end

return M
