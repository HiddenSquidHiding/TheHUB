-- anti_afk.lua (minimal)
local VirtualUser = game:GetService("VirtualUser")
local M = { _enabled=false }
local running = false

local function loop()
  if running then return end
  running = true
  task.spawn(function()
    while M._enabled do
      pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:SetKeyDown(Enum.KeyCode.W)
        task.wait(0.1)
        VirtualUser:SetKeyUp(Enum.KeyCode.W)
      end)
      task.wait(60)
    end
    running = false
  end)
end

function M.enable() M._enabled=true; loop() end
function M.disable() M._enabled=false end
return M
