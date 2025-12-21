local VirtualInputManager = game:GetService("VirtualInputManager")

local isAFKActive = false
local afkConnection = nil

-- Safe key press function (F15 – no gameplay side effects)
local function doSafeKeyPress()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F15, false, game)   -- Press
    task.wait(0.05)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F15, false, game)  -- Release
end

-- Toggle function – call this from your menu buttons
local function toggleAFK(enabled)
    if enabled then
        if isAFKActive then return end  -- Already on
        isAFKActive = true
        print("Safe AFK Reset: ON")
        
        afkConnection = task.spawn(function()
            while isAFKActive do
                task.wait(300)  -- Every 5 minutes
                if isAFKActive then
                    doSafeKeyPress()
                    print("AFK timer reset (F15 press)")
                end
            end
        end)
    else
        if not isAFKActive then return end  -- Already off
        isAFKActive = false
        if afkConnection then
            task.cancel(afkConnection)
            afkConnection = nil
        end
        print("Safe AFK Reset: OFF")
    end
end

print("Safe AFK Reset logic loaded. Use toggleAFK(true/false) to control.")
