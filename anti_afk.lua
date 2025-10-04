-- anti_afk.lua
local UserInputService = game:GetService("UserInputService")
local VirtualUser     = game:GetService("VirtualUser")

local M = {}
local enabled = false

local function loop()
  task.spawn(function()
    while enabled do
      pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:SetKeyDown("W"); task.wait(0.10); VirtualUser:SetKeyUp("W")
        task.wait(0.10)
        VirtualUser:MoveMouse(Vector2.new(10,0))
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
