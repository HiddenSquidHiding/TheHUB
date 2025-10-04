-- anti_afk.lua
-- Standalone Anti-AFK helper with enable/disable/toggle/isEnabled/ensure

local Players    = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local AntiAFK = {
  _enabled = false,
  _running = false,
}

local function loop()
  if AntiAFK._running then return end
  AntiAFK._running = true
  task.spawn(function()
    while AntiAFK._enabled do
      pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:SetKeyDown("W")
        task.wait(0.1)
        VirtualUser:SetKeyUp("W")
        task.wait(0.1)
        VirtualUser:MoveMouse(Vector2.new(10, 0))
      end)
      task.wait(60)
    end
    AntiAFK._running = false
  end)
end

function AntiAFK.enable()
  if AntiAFK._enabled then return end
  AntiAFK._enabled = true
  loop()
end

function AntiAFK.disable()
  AntiAFK._enabled = false
  -- loop will naturally stop at next tick
end

function AntiAFK.toggle()
  if AntiAFK._enabled then AntiAFK.disable() else AntiAFK.enable() end
end

function AntiAFK.isEnabled()
  return AntiAFK._enabled
end

-- Ensure a running loop if enabled (safe to call repeatedly)
function AntiAFK.ensure()
  if AntiAFK._enabled then loop() end
end

return AntiAFK
