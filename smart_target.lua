-- smart_target.lua (stub)
local M = {}
function M.runSmartFarm(getEnabled, setTargetText)
  setTargetText = setTargetText or function() end
  while getEnabled and getEnabled() do
    setTargetText("Current Target: (smart stub running)")
    task.wait(0.5)
  end
  setTargetText("Current Target: None")
end
return M
