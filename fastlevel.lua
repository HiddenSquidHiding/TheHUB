-- fastlevel.lua (stub)
local M = { _on=false }
function M.enable() M._on=true end
function M.disable() M._on=false end
function M.isEnabled() return M._on end
return M
