-- fastlevel.lua
-- Simple flag helper for the "Instant Level 70+" mode (Sahur-only targeting).

local M = { _enabled = false }

function M.enable()  M._enabled = true  end
function M.disable() M._enabled = false end
function M.isEnabled() return M._enabled end

-- Convenience: the exact Sahur target the farm should lock to in this mode
function M.getTargetLabel()
  return "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur"
end

return M
