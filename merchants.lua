-- merchants.lua (stub)
local M = {}
function M.autoBuyLoop(_, getEnabled)
  while getEnabled and getEnabled() do task.wait(0.5) end
end
return M
