-- anti_afk.lua
-- Standalone Anti-AFK helper with enable/disable/toggle/isEnabled/ensure

local Players    = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")

local AntiAFK = {
  _enabled = false,
  _running = false,
}

local function loop()
task.spawn(function()
    while enabled do
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
end)
end

function M.setEnabled(flag)
  enabled = flag and true or false
  if enabled then loop() end
end

return M
