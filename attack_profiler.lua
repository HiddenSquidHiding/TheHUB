-- attack_profiler.lua
-- Visual profiler for attack RemoteFunction cadence.
-- Runs each delay for N seconds, shows attempts/success%/avg RTT live.

-- ========== optional utils ==========
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return {
    notify = function() end,
    waitForCharacter = function()
      local Players = game:GetService("Players")
      local plr = Players.LocalPlayer
      while true do
        local ch = plr.Character
        if ch and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid") then
          return ch
        end
        plr.CharacterAdded:Wait()
        task.wait()
      end
    end,
  }
end
local utils = getUtils()

-- ========== services ==========
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local player            = Players.LocalPlayer

local Prof = {}

-- --------- helpers ----------
local function interpretResult(res)
  local t = typeof(res)
  if t == "boolean" then return res end
  if t == "string" then
    local s = res:lower()
    if s:find("ok") or s:find("success") or s == "true" then return true end
    return false
  end
  if t == "table" then
    if res.ok == true or res.success == true or res.Success == true or res[1] == true then
      return true
    end
    return false
  end
  -- Many games return nil; treat no-error nil as success (tunable).
  return true
end

local function fetchRequestAttack()
  local ok, rf = pcall(function()
    return ReplicatedStorage:WaitForChild("Packages")
      :WaitForChild("Knit")
      :WaitForChild("Services")
      :WaitForChild("MonsterService")
      :WaitForChild("RF")
      :WaitForChild("RequestAttack")
  end)
  if ok and rf and rf:IsA("RemoteFunction") then
    return rf
  end
  return nil
end

-- ========== GUI ==========
local function makeGui()
  local pg = player:WaitForChild("PlayerGui", 5)
  if not pg then return nil end

  local gui = Instance.new("ScreenGui")
  gui.Name = "Woodz_AttackProfiler"
  gui.ResetOnSpawn = false
  gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
  gui.DisplayOrder = 2_000_000_000
  gui.Parent = pg

  local frame = Instance.new("Frame")
  frame.Name = "Root"
  frame.AnchorPoint = Vector2.new(1,0)
  frame.Position = UDim2.new(1, -12, 0, 12)
  frame.Size = UDim2.new(0, 360, 0, 420)
  frame.BackgroundColor3 = Color3.fromRGB(32,32,32)
  frame.BorderSizePixel = 0
  frame.Parent = gui

  local title = Instance.new("TextLabel")
  title.BackgroundTransparency = 1
  title.Size = UDim2.new(1, -30, 0, 24)
  title.Position = UDim2.new(0, 10, 0, 8)
  title.Font = Enum.Font.SourceSansBold
  title.TextSize = 16
  title.TextColor3 = Color3.fromRGB(255,255,255)
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.Text = "🌲 WoodzHUB • Attack Profiler"
  title.Parent = frame

  local close = Instance.new("TextButton")
  close.Text = "✕"
  close.Font = Enum.Font.SourceSansBold
  close.TextSize = 16
  close.TextColor3 = Color3.fromRGB(255,255,255)
  close.BackgroundColor3 = Color3.fromRGB(180,55,55)
  close.Size = UDim2.new(0, 28, 0, 24)
  close.Position = UDim2.new(1, -34, 0, 8)
  close.Parent = frame

  local header = Instance.new("Frame")
  header.BackgroundColor3 = Color3.fromRGB(45,45,45)
  header.BorderSizePixel = 0
  header.Size = UDim2.new(1, -20, 0, 26)
  header.Position = UDim2.new(0, 10, 0, 40)
  header.Parent = frame

  local function mkH(text, x, w)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(230,230,230)
    l.Font = Enum.Font.SourceSansBold
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Position = UDim2.new(0, x, 0, 0)
    l.Size = UDim2.new(0, w, 1, 0)
    l.Parent = header
  end
  mkH("Delay (s)", 10, 70)
  mkH("Attempts", 90, 70)
  mkH("Success", 170, 70)
  mkH("Success %", 250, 70)
  mkH("Avg RTT", 330, 60)

  local listHolder = Instance.new("ScrollingFrame")
  listHolder.BackgroundColor3 = Color3.fromRGB(40,40,40)
  listHolder.BorderSizePixel = 0
  listHolder.Position = UDim2.new(0, 10, 0, 70)
  listHolder.Size = UDim2.new(1, -20, 0, 270)
  listHolder.ScrollBarThickness = 6
  listHolder.CanvasSize = UDim2.new(0,0,0,0)
  listHolder.Parent = frame

  local uiList = Instance.new("UIListLayout")
  uiList.SortOrder = Enum.SortOrder.LayoutOrder
  uiList.Padding = UDim.new(0, 4)
  uiList.Parent = listHolder

  local status = Instance.new("TextLabel")
  status.BackgroundTransparency = 1
  status.TextColor3 = Color3.fromRGB(255,255,255)
  status.Font = Enum.Font.SourceSans
  status.TextSize = 14
  status.TextXAlignment = Enum.TextXAlignment.Left
  status.Text = "Ready."
  status.Position = UDim2.new(0, 10, 1, -52)
  status.Size = UDim2.new(1, -20, 0, 22)
  status.Parent = frame

  local barBg = Instance.new("Frame")
  barBg.BackgroundColor3 = Color3.fromRGB(55,55,55)
  barBg.BorderSizePixel = 0
  barBg.Position = UDim2.new(0, 10, 1, -26)
  barBg.Size = UDim2.new(1, -20, 0, 16)
  barBg.Parent = frame

  local bar = Instance.new("Frame")
  bar.BackgroundColor3 = Color3.fromRGB(90,180,90)
  bar.BorderSizePixel = 0
  bar.Size = UDim2.new(0, 0, 1, 0)
  bar.Parent = barBg

  return {
    gui = gui,
    frame = frame,
    close = close,
    list = listHolder,
    status = status,
    bar = bar,
  }
end

local function makeRow(parent, delay)
  local row = Instance.new("Frame")
  row.BackgroundColor3 = Color3.fromRGB(36,36,36)
  row.BorderSizePixel = 0
  row.Size = UDim2.new(1, 0, 0, 28)
  row.Parent = parent

  local function mk(text, x, w, bold)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(220,220,220)
    l.Font = bold and Enum.Font.SourceSansBold or Enum.Font.SourceSans
    l.TextSize = 14
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = text
    l.Position = UDim2.new(0, x, 0, 4)
    l.Size = UDim2.new(0, w, 1, -8)
    l.Parent = row
    return l
  end

  local colDelay   = mk(("%.3f"):format(delay), 10, 70, true)
  local colAtt     = mk("0", 90, 70)
  local colSucc    = mk("0", 170, 70)
  local colRatio   = mk("0%", 250, 70)
  local colRTT     = mk("-", 330, 60)

  return {
    row = row,
    set = function(att, succ, ratio, avgRttMs)
      colAtt.Text = tostring(att)
      colSucc.Text = tostring(succ)
      colRatio.Text = ("%d%%"):format(math.floor((ratio or 0)*100 + 0.5))
      if avgRttMs then
        colRTT.Text = ("%d ms"):format(math.floor(avgRttMs + 0.5))
      end
    end
  }
end

-- ========== public API ==========
-- opts:
--   delays = {0.05,0.075,...}
--   secondsPerDelay = 10
--   getRemote = function() -> RemoteFunction  (optional; default tries Knit MonsterService.RF.RequestAttack)
--   remote = RemoteFunction                    (optional)
--   getTargetCF = function() -> CFrame         (optional; default: player's HRP or current camera CFrame)
--   successFromResult = function(res)->bool    (optional; default interpretResult above)
--   onDone = function(summaryTable)            (optional)
function Prof.start(opts)
  opts = opts or {}
  local delays = opts.delays or {0.05, 0.075, 0.10, 0.125, 0.15, 0.175, 0.20, 0.25, 0.30, 0.35, 0.40}
  local secondsPer = math.max(10, tonumber(opts.secondsPerDelay) or 10)
  local successFromResult = opts.successFromResult or interpretResult

  local rf = opts.remote or (opts.getRemote and opts.getRemote()) or fetchRequestAttack()
  if not rf then
    utils.notify("🌲 Attack Profiler", "RequestAttack remote not found.", 5)
    return
  end

  local gui = makeGui()
  if not gui then
    utils.notify("🌲 Attack Profiler", "Failed to create GUI.", 5)
    return
  end

  local rows = {}
  for _, d in ipairs(delays) do
    table.insert(rows, { delay = d, ui = makeRow(gui.list, d), attempts = 0, successes = 0, totalTime = 0, rttSumMs = 0 })
  end
  gui.list.CanvasSize = UDim2.new(0,0,0, #rows * 32)

  local cancelled = false
  gui.close.MouseButton1Click:Connect(function()
    cancelled = true
    if gui.gui then gui.gui:Destroy() end
  end)

  -- default aim: player HRP; fallback to Camera frame
  local function defaultTargetCF()
    local ch = player.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then return hrp.CFrame end
    local cam = workspace.CurrentCamera
    return cam and cam.CFrame or CFrame.new()
  end
  local getTargetCF = opts.getTargetCF or defaultTargetCF

  task.spawn(function()
    for idx, item in ipairs(rows) do
      if cancelled then break end
      local delay = item.delay
      local tEnd = tick() + secondsPer
      gui.status.Text = ("Testing delay %.3fs..."):format(delay)
      gui.bar.Size = UDim2.new(0, 0, 1, 0)

      while not cancelled and tick() < tEnd do
        local now = tick()
        local remaining = tEnd - now
        local progress = 1 - math.clamp(remaining / secondsPer, 0, 1)
        gui.bar.Size = UDim2.new(progress, 0, 1, 0)

        -- fire once per delay
        item.attempts += 1
        local cf = getTargetCF()
        local t0 = tick()
        local ok, res = pcall(function() return rf:InvokeServer(cf) end)
        local rtt = (tick() - t0) * 1000.0 -- ms
        item.rttSumMs += rtt

        local success = false
        if ok then
          success = successFromResult(res)
        else
          success = false
        end
        if success then item.successes += 1 end

        -- update UI
        local ratio = (item.attempts > 0) and (item.successes / item.attempts) or 0
        local avgRtt = (item.attempts > 0) and (item.rttSumMs / item.attempts) or nil
        item.ui.set(item.attempts, item.successes, ratio, avgRtt)

        -- wait
        local nextAt = t0 + delay
        while not cancelled and tick() < nextAt do
          RunService.Heartbeat:Wait()
        end
      end
    end

    if not cancelled then
      gui.status.Text = "Done."
      gui.bar.Size = UDim2.new(1,0,1,0)
      -- Compute best by success ratio (tie-breaker: smaller delay, then lower RTT)
      table.sort(rows, function(a,b)
        local ra = (a.attempts > 0) and (a.successes / a.attempts) or 0
        local rb = (b.attempts > 0) and (b.successes / b.attempts) or 0
        if math.abs(ra - rb) > 1e-6 then return ra > rb end
        if math.abs(a.delay - b.delay) > 1e-6 then return a.delay < b.delay end
        local rtta = (a.attempts > 0) and (a.rttSumMs / a.attempts) or math.huge
        local rttb = (b.attempts > 0) and (b.rttSumMs / b.attempts) or math.huge
        return rtta < rttb
      end)

      local best = rows[1]
      local bestRatio = (best.attempts > 0) ? (best.successes / best.attempts) : 0
      utils.notify("🌲 Attack Profiler",
        ("Best delay: %.3fs (success %.0f%%)"):format(best.delay, bestRatio*100), 5)

      if typeof(opts.onDone) == "function" then
        opts.onDone(rows)
      end
    end
  end)
end

return Prof
