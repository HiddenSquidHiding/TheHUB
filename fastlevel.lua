-- fastlevel.lua
-- When enabled, restricts farm selection to a single Sahur target.

-- 🔧 Safe utils access
local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  error("[fastlevel.lua] utils missing; ensure init.lua injects siblings._deps.utils before loading fastlevel.lua")
end

local utils = getUtils()
local farm  = require(script.Parent.farm)

local TARGET = "Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Tri Sarur"

local M = {
  _enabled = false,
  _prevSel = nil,
}

function M.enable()
  if M._enabled then return end
  M._enabled = true
  -- save current selection and force the single target
  M._prevSel = table.clone(farm.getSelected() or {})
  farm.setSelected({ TARGET })
  utils.notify("🌲 Instant Level 70+", "Targeting only: "..TARGET, 3)
end

function M.disable()
  if not M._enabled then return end
  M._enabled = false
  -- restore previous selection if we had one
  if M._prevSel then
    farm.setSelected(M._prevSel)
  end
  utils.notify("🌲 Instant Level 70+", "Restored previous selections.", 3)
end

function M.isEnabled() return M._enabled end
function M.targetName() return TARGET end

return M
