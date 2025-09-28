-- hud.lua
local M = {}

local function findHUD(container)
  local hud = container:FindFirstChild('HUD')
  if hud and hud:IsA('ScreenGui') then return hud end
  for _, inst in ipairs(container:GetDescendants()) do
    if inst:IsA('ScreenGui') and inst.Name=='HUD' then return inst end
  end
  return nil
end

local function applyPremiumHidden(hud, hidden)
  if not hud then return end
  local buffs = hud:FindFirstChild('Buffs')
  if not (buffs and buffs:IsA('Frame')) then return end
  local premium = buffs:FindFirstChild('Premium')
  if premium and premium:IsA('Frame') then premium.Visible = not hidden end
end

local function applyVipHidden(hud, hidden)
  if not hud then return end
  local buttons = hud:FindFirstChild('Buttons', true)
  if not (buttons and buttons:IsA('Frame')) then return end
  local vip = buttons:FindFirstChild('VIP')
  if vip and vip:IsA('Frame') then vip.Visible = not hidden end
end

local function applyLimitedPetHidden(hud, hidden)
  if not hud then return end
  local limited = hud:FindFirstChild('LimitedPet1', true)
  if limited and limited:IsA('Frame') then limited.Visible = not hidden end
end

function M.apply(hud, flags)
  applyPremiumHidden(hud, flags.premiumHidden)
  applyVipHidden(hud, flags.vipHidden)
  applyLimitedPetHidden(hud, flags.limitedPetHidden)
end

function M.watch(hud, flags)
  if not hud then return function() end end
  return hud.DescendantAdded:Connect(function(d)
    if not d:IsA('Frame') then return end
    if flags.premiumHidden and d.Name=='Premium' and d.Parent and d.Parent.Name=='Buffs' then d.Visible=false; return end
    if flags.vipHidden and d.Name=='VIP' then
      local p=d.Parent; while p and p~=hud do if p.Name=='Buttons' then d.Visible=false; return end; p=p.Parent end
    end
    if flags.limitedPetHidden and d.Name=='LimitedPet1' then d.Visible=false; return end
  end)
end

M.findHUD = findHUD
M.applyPremiumHidden = applyPremiumHidden
M.applyVipHidden = applyVipHidden
M.applyLimitedPetHidden = applyLimitedPetHidden

return M
