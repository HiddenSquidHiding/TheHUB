-- constants.lua
local M = {}

-- Colors
M.COLOR_BG_DARK    = Color3.fromRGB(30, 30, 30)
M.COLOR_BG         = Color3.fromRGB(40, 40, 40)
M.COLOR_BG_MED     = Color3.fromRGB(50, 50, 50)
M.COLOR_BTN        = Color3.fromRGB(60, 60, 60)
M.COLOR_BTN_ACTIVE = Color3.fromRGB(80, 80, 80)
M.COLOR_WHITE      = Color3.fromRGB(255, 255, 255)

-- Sizes
M.SIZE_MAIN = UDim2.new(0, 400, 0, 540)
M.SIZE_MIN  = UDim2.new(0, 400, 0, 50)

-- Merchant
M.mythicSkus = { 'Mythic1', 'Mythic2', 'Mythic3', 'Mythic4' }
M.merchantCooldown = 0.1

-- Crates
M.crateOpenDelay = 1.0
M.INV_REFRESH_COOLDOWN = 5
M.crateNames = {
  'Bronze Crate','Silver Crate','Golden Crate','Demon Crate','Sahur Crate',
  'Void Crate','Vault Crate','Lime Crate','Chairchachi Crate','To To To Crate',
  'Market Crate','Gummy Crate','Yoni Crate','Grapefruit Crate','Bus Crate',
  'Cheese Crate','Graipus Crate','Pasta Crate','Te Te Te Te Crate',
}

return M
