-- crates.lua (stub)
local M = {}
function M.refreshCrateInventory(_) return {} end
function M.autoOpenCratesEnabledLoop(getEnabled)
  while getEnabled and getEnabled() do task.wait(1) end
end
return M
