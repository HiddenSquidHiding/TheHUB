-- anti_afk.lua (safe version)
local VirtualInputManager = game:GetService("VirtualInputManager")
local M = { _enabled = false }
local afkConnection = nil

-- Safe key press function (F15 – no gameplay side effects)
local function doSafeKeyPress()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game)   -- Press
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F15, false, game)  -- Release
end

local function loop()
    if afkConnection then return end  -- Already running
    afkConnection = task.spawn(function()
        while M._enabled do
            task.wait(300)  -- Every 5 minutes
            if M._enabled then
                doSafeKeyPress()
                print("AFK timer reset (F15 press)")
            end
        end
        afkConnection = nil
    end)
end

function M.enable()
    if M._enabled then return end
    M._enabled = true
    print("Safe AFK Reset: ON")
    loop()
end

function M.disable()
    if not M._enabled then return end
    M._enabled = false
    if afkConnection then
        task.cancel(afkConnection)
        afkConnection = nil
    end
    print("Safe AFK Reset: OFF")
end

print("Safe AFK Reset logic loaded. Use M.enable()/M.disable() to control.")
return M