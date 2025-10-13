-- farm.lua (stub so app.lua can load)
local M = {}

local selected = {}
local all = {"Weather Events","To Sahur"} -- placeholder

function M.getMonsterModels() return all end
function M.getFiltered() return all end
function M.filterMonsterModels(_) return all end
function M.getSelected() return selected end
function M.setSelected(t) selected = t or {} end
function M.toggleSelect(name)
  local i = table.find(selected, name)
  if i then table.remove(selected, i) else table.insert(selected, name) end
end
function M.isSelected(name) return table.find(selected, name) ~= nil end

function M.setupAutoAttackRemote() end

function M.runAutoFarm(getEnabled, setTargetText)
  setTargetText = setTargetText or function() end
  while getEnabled and getEnabled() do
    setTargetText("Current Target: (stub running)")
    task.wait(0.5)
  end
  setTargetText("Current Target: None")
end

-- used by fastlevel mode in your app.lua; no-op in stub
function M.setFastLevelEnabled(_) end

return M
