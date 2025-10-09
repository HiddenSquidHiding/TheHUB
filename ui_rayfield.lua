-- ui_rayfield.lua
-- Rayfield overlay UI for WoodzHUB (model picker, 3-button row presets, toggles, status).
-- Calls back into app.lua via the handlers you pass to build().

local function getUtils()
  local p = script and script.Parent
  if p and p._deps and p._deps.utils then return p._deps.utils end
  if rawget(getfenv(), "__WOODZ_UTILS") then return __WOODZ_UTILS end
  return { notify = function(_,_) end }
end

local utils     = getUtils()
local constants = require(script.Parent.constants)
local hud       = require(script.Parent.hud)
local farm      = require(script.Parent.farm)   -- used for model picker

local Rayfield  = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Players   = game:GetService("Players")
local CoreGui   = game:GetService("CoreGui")

local M = {}

function M.build(handlers)
  handlers = handlers or {}

  local Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — Rayfield",
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Rayfield UI",
    ConfigurationSaving = { Enabled = false, FolderName = "WoodzHUB", FileName = "Rayfield" },
    KeySystem = false,
  })

  local MainTab    = Window:CreateTab("Main")
  local OptionsTab = Window:CreateTab("Options")

  --------------------------------------------------------------------------
  -- Model Picker (Search + Multi-select Dropdown)
  --------------------------------------------------------------------------
  MainTab:CreateSection("Targets")

  local currentSearch = ""
  pcall(function() farm.getMonsterModels() end)

  local function filteredList()
    local list = farm.filterMonsterModels(currentSearch or "")
    local out = {}
    for _, v in ipairs(list or {}) do
      if typeof(v) == "string" then table.insert(out, v) end
    end
    return out
  end

  local modelDropdown
  local suppressDropdown = false -- prevents callback recursion/stack overflow

  local function syncDropdownSelectionFromFarm()
    if not modelDropdown then return end
    local sel = farm.getSelected() or {}
    suppressDropdown = true
    pcall(function() modelDropdown:Set(sel) end)
    suppressDropdown = false
  end

  local function refreshDropdownOptions()
    if not modelDropdown then return end
    local options = filteredList()
    suppressDropdown = true
    local ok = pcall(function() modelDropdown:Refresh(options, true) end)
    if not ok then
      pcall(function() modelDropdown:Set(options) end) -- harmless on forks without Refresh
    end
    syncDropdownSelectionFromFarm()
    suppressDropdown = false
  end

  MainTab:CreateInput({
    Name = "Search Models",
    PlaceholderText = "Type model names to filter…",
    RemoveTextAfterFocusLost = false,
    Callback = function(text)
      currentSearch = tostring(text or "")
      refreshDropdownOptions()
    end,
  })

  modelDropdown = MainTab:CreateDropdown({
    Name = "Target Models (multi-select)",
    Options = filteredList(),
    CurrentOption = farm.getSelected() or {},
    MultipleOptions = true,
    Flag = "woodz_models",
    Callback = function(selection)
      if suppressDropdown then return end  -- stop feedback loop
      local list = {}
      if typeof(selection) == "table" then
        for _, v in ipairs(selection) do if typeof(v) == "string" then table.insert(list, v) end end
      elseif typeof(selection) == "string" then
        table.insert(list, selection)
      end
      farm.setSelected(list)
      -- DO NOT call :Set() here; it re-triggers the callback.
    end,
  })

  refreshDropdownOptions()

  --------------------------------------------------------------------------
  -- Presets (custom 3-button horizontal row via an anchor label + listeners)
  --------------------------------------------------------------------------
  MainTab:CreateSection("Presets")

  local ANCHOR_TEXT = "__WOODZ_PRESET_ANCHOR__"
  local anchor = MainTab:CreateLabel(ANCHOR_TEXT)

  local function buildPresetRow(container, afterSibling)
    local row = Instance.new("Frame")
    row.Name = "Woodz_PresetsRow"
    row.BackgroundTransparency = 1
    row.Size = UDim2.new(1, 0, 0, 40)
    pcall(function() row.LayoutOrder = (afterSibling and afterSibling.LayoutOrder or 0) + 1 end)
    row.Parent = container

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment   = Enum.VerticalAlignment.Center
    layout.Padding             = UDim.new(0, 8)
    layout.Parent = row

    local function mkBtn(text, cb)
      local btn = Instance.new("TextButton")
      btn.AutoButtonColor  = true
      btn.Text             = text
      btn.Font             = Enum.Font.SourceSans
      btn.TextSize         = 14
      btn.TextColor3       = Color3.fromRGB(235,235,235)
      btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
      btn.Size             = UDim2.new(1/3, -8, 1, 0) -- 3 buttons across with padding
      btn.Parent = row

      local corner = Instance.new("UICorner")
      corner.CornerRadius = UDim.new(0, 6)
      corner.Parent = btn

      local stroke = Instance.new("UIStroke")
      stroke.Thickness       = 1
      stroke.Transparency    = 0.3
      stroke.Color           = Color3.fromRGB(90, 90, 90)
      stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
      stroke.Parent = btn

      btn.MouseButton1Click:Connect(function()
        task.spawn(function() pcall(cb) end)
      end)
    end

    mkBtn("Select To Sahur", function()
      if handlers.onSelectSahur then handlers.onSelectSahur() end
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Selected all To Sahur models.", 3)
    end)

    mkBtn("Select Weather", function()
      if handlers.onSelectWeather then handlers.onSelectWeather() end
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Selected all Weather Events models.", 3)
    end)

    mkBtn("Clear All", function()
      if handlers.onClearAll then handlers.onClearAll() end
      syncDropdownSelectionFromFarm()
      utils.notify("🌲 Preset", "Cleared all selections.", 3)
    end)
  end

  local function onAnchorLabelFound(lbl)
    if not (lbl and lbl.Parent) then return end
    local container = lbl.Parent
    buildPresetRow(container, lbl)
    pcall(function() lbl:Destroy() end)
  end

  -- 1) Immediate direct-instance attempt (some Rayfield builds expose the TextLabel)
  do
    local lbl = nil
    if typeof(anchor) == "table" then
      -- Try common keys Rayfield wrappers use
      for _, k in ipairs({"Label","_Label","Instance","Object","TextLabel"}) do
        local v = rawget(anchor, k)
        if typeof(v) == "Instance" and v:IsA("TextLabel") and tostring(v.Text) == ANCHOR_TEXT then
          lbl = v; break
        end
      end
    end
    if lbl then
      onAnchorLabelFound(lbl)
    end
  end

  -- 2) If not found yet, set up listeners and a one-shot scan
  local function tryScanTree(root)
    for _, d in ipairs(root:GetDescendants()) do
      if d:IsA("TextLabel") and tostring(d.Text) == ANCHOR_TEXT then
        onAnchorLabelFound(d)
        return true
      end
    end
    return false
  end

  local function onDescendantAdded(inst)
    if inst:IsA("TextLabel") and tostring(inst.Text) == ANCHOR_TEXT then
      onAnchorLabelFound(inst)
    end
  end

  -- Listen in CoreGui and (fallback) PlayerGui until we succeed
  local cgConn, pgConn
  cgConn = CoreGui.DescendantAdded:Connect(onDescendantAdded)
  local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
  if pg then pgConn = pg.DescendantAdded:Connect(onDescendantAdded) end

  -- One-shot scans (catch the case where anchor is already in the tree)
  if tryScanTree(CoreGui) then
    if cgConn then cgConn:Disconnect() end
    if pgConn then pgConn:Disconnect() end
  elseif pg and tryScanTree(pg) then
    if cgConn then cgConn:Disconnect() end
    if pgConn then pgConn:Disconnect() end
  else
    -- Safety: auto-stop the listeners once the row exists
    task.spawn(function()
      for _=1,60 do
        local found = false
        for _, root in ipairs({CoreGui, pg}) do
          if root and root:FindFirstChild("Woodz_PresetsRow", true) then
            found = true; break
          end
        end
        if found then break end
        task.wait(0.25)
      end
      if cgConn then cgConn:Disconnect() end
      if pgConn then pgConn:Disconnect() end
    end)
  end

  --------------------------------------------------------------------------
  -- Toggles (farming)
  --------------------------------------------------------------------------
  MainTab:CreateSection("Farming")
  local rfAutoFarm = MainTab:CreateToggle({
    Name = "Auto-Farm",
    CurrentValue = false,
    Flag = "woodz_auto_farm",
    Callback = function(v) if handlers.onAutoFarmToggle then handlers.onAutoFarmToggle(v) end end,
  })
  local rfSmartFarm = MainTab:CreateToggle({
    Name = "Smart Farm",
    CurrentValue = false,
    Flag = "woodz_smart_farm",
    Callback = function(v) if handlers.onSmartFarmToggle then handlers.onSmartFarmToggle(v) end end,
  })

  local currentLabel = MainTab:CreateLabel("Current Target: None")

  --------------------------------------------------------------------------
  -- Options
  --------------------------------------------------------------------------
  OptionsTab:CreateSection("Merchants / Crates / AFK")
  local rfMerch1 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Chicleteiramania)",
    CurrentValue = false,
    Flag = "woodz_m1",
    Callback = function(v) if handlers.onToggleMerchant1 then handlers.onToggleMerchant1(v) end end,
  })
  local rfMerch2 = OptionsTab:CreateToggle({
    Name = "Auto Buy Mythics (Bombardino Sewer)",
    CurrentValue = false,
    Flag = "woodz_m2",
    Callback = function(v) if handlers.onToggleMerchant2 then handlers.onToggleMerchant2(v) end end,
  })
  local rfCrates = OptionsTab:CreateToggle({
    Name = "Auto Open Crates",
    CurrentValue = false,
    Flag = "woodz_crates",
    Callback = function(v) if handlers.onToggleCrates then handlers.onToggleCrates(v) end end,
  })
  local rfAFK = OptionsTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Flag = "woodz_afk",
    Callback = function(v) if handlers.onToggleAntiAFK then handlers.onToggleAntiAFK(v) end end,
  })

  OptionsTab:CreateSection("Extras")
  OptionsTab:CreateButton({
    Name = "Redeem Unredeemed Codes",
    Callback = function() if handlers.onRedeemCodes then handlers.onRedeemCodes() end end,
  })

  -- NEW: Private Server button -> runs your solo.lua
  -- NEW: Private Server button -> inlined solo logic (runs only on click)
OptionsTab:CreateButton({
  Name = "Private Server",
  Callback = function()
    task.spawn(function()
      -- Inlined: MD5, HMAC, Base64 utils from solo.lua
      local md5 = {}
      local hmac = {}
      local base64 = {}

      do
        do
          local T = {
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
          }

          local function add(a, b)
            local lsw = bit32.band(a, 0xFFFF) + bit32.band(b, 0xFFFF)
            local msw = bit32.rshift(a, 16) + bit32.rshift(b, 16) + bit32.rshift(lsw, 16)
            return bit32.bor(bit32.lshift(msw, 16), bit32.band(lsw, 0xFFFF))
          end

          local function rol(x, n)
            return bit32.bor(bit32.lshift(x, n), bit32.rshift(x, 32 - n))
          end

          local function F(x, y, z) return bit32.bor(bit32.band(x, y), bit32.band(bit32.bnot(x), z)) end
          local function G(x, y, z) return bit32.bor(bit32.band(x, z), bit32.band(y, bit32.bnot(z))) end
          local function H(x, y, z) return bit32.bxor(x, bit32.bxor(y, z)) end
          local function I(x, y, z) return bit32.bxor(y, bit32.bor(x, bit32.bnot(z))) end

          function md5.sum(message)
            local a, b, c, d = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
            local message_len = #message
            local padded_message = message .. "\128"
            while #padded_message % 64 ~= 56 do padded_message = padded_message .. "\0" end
            local len_bytes = ""
            local len_bits = message_len * 8
            for i = 0, 7 do len_bytes = len_bytes .. string.char(bit32.band(bit32.rshift(len_bits, i * 8), 0xFF)) end
            padded_message = padded_message .. len_bytes

            for i = 1, #padded_message, 64 do
              local chunk = padded_message:sub(i, i + 63)
              local X = {}
              for j = 0, 15 do
                local b1, b2, b3, b4 = chunk:byte(j * 4 + 1, j * 4 + 4)
                X[j] = bit32.bor(b1, bit32.lshift(b2, 8), bit32.lshift(b3, 16), bit32.lshift(b4, 24))
              end

              local aa, bb, cc, dd = a, b, c, d
              local s = { 7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21 }

              for j = 0, 63 do
                local f, k, shift_index
                if j < 16 then
                  f = F(b, c, d); k = j; shift_index = j % 4
                elseif j < 32 then
                  f = G(b, c, d); k = (1 + 5 * j) % 16; shift_index = 4 + (j % 4)
                elseif j < 48 then
                  f = H(b, c, d); k = (5 + 3 * j) % 16; shift_index = 8 + (j % 4)
                else
                  f = I(b, c, d); k = (7 * j) % 16; shift_index = 12 + (j % 4)
                end

                local temp = add(a, f)
                temp = add(temp, X[k])
                temp = add(temp, T[j + 1])
                temp = rol(temp, s[shift_index + 1])

                local new_b = add(b, temp)
                a, b, c, d = d, new_b, b, c
              end

              a = add(a, aa); b = add(b, bb); c = add(c, cc); d = add(d, dd)
            end

            local function to_le_hex(n)
              local s = ""
              for i = 0, 3 do s = s .. string.char(bit32.band(bit32.rshift(n, i * 8), 0xFF)) end
              return s
            end

            return to_le_hex(a) .. to_le_hex(b) .. to_le_hex(c) .. to_le_hex(d)
          end
        end

        do
          function hmac.new(key, msg, hash_func)
            if #key > 64 then key = hash_func(key) end
            local o_key_pad = ""; local i_key_pad = ""
            for i = 1, 64 do
              local byte = (i <= #key and string.byte(key, i)) or 0
              o_key_pad = o_key_pad .. string.char(bit32.bxor(byte, 0x5C))
              i_key_pad = i_key_pad .. string.char(bit32.bxor(byte, 0x36))
            end
            return hash_func(o_key_pad .. hash_func(i_key_pad .. msg))
          end
        end

        do
          local b = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
          function base64.encode(data)
            return (
              (data:gsub(".", function(x)
                local r, b_val = "", x:byte()
                for i = 8, 1, -1 do r = r .. (b_val % 2 ^ i - b_val % 2 ^ (i - 1) > 0 and "1" or "0") end
                return r
              end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
                if #x < 6 then return "" end
                local c = 0
                for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
                return b:sub(c + 1, c + 1)
              end) .. ({ "", "==", "=" })[#data % 3 + 1]
            )
          end
        end
      end

      local function GenerateReservedServerCode(placeId)
        local uuid = {}
        for i = 1, 16 do uuid[i] = math.random(0, 255) end
        uuid[7] = bit32.bor(bit32.band(uuid[7], 0x0F), 0x40) -- v4
        uuid[9] = bit32.bor(bit32.band(uuid[9], 0x3F), 0x80) -- RFC 4122

        local firstBytes = ""
        for i = 1, 16 do firstBytes = firstBytes .. string.char(uuid[i]) end

        local gameCode = string.format("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x", table.unpack(uuid))

        local placeIdBytes = ""
        local pIdRec = placeId
        for _ = 1, 8 do
          placeIdBytes = placeIdBytes .. string.char(pIdRec % 256)
          pIdRec = math.floor(pIdRec / 256)
        end

        local content = firstBytes .. placeIdBytes

        local SUPERDUPERSECRETROBLOXKEYTHATTHEYDIDNTCHANGEEVERSINCEFOREVER = "e4Yn8ckbCJtw2sv7qmbg"
        local signature = hmac.new(SUPERDUPERSECRETROBLOXKEYTHATTHEYDIDNTCHANGEEVERSINCEFOREVER, content, md5.sum)

        local accessCodeBytes = signature .. content

        local accessCode = base64.encode(accessCodeBytes)
        accessCode = accessCode:gsub("+", "-"):gsub("/", "_")

        local pdding = 0
        accessCode, _ = accessCode:gsub("=", function() pdding = pdding + 1; return "" end)

        accessCode = accessCode .. tostring(pdding)

        return accessCode, gameCode
      end

      -- Teleport logic (runs only here, on button click)
      local success, err = pcall(function()
        local accessCode, _ = GenerateReservedServerCode(game.PlaceId)
        game.RobloxReplicatedStorage.ContactListIrisInviteTeleport:FireServer(game.PlaceId, "", accessCode)
      end)

      if success then
        utils.notify("🌲 Private Server", "Teleport initiated to private server!", 3)
      else
        utils.notify("🌲 Private Server", "Failed to teleport: " .. tostring(err), 5)
      end
    end)
  end,
})

  local rfFastLvl = OptionsTab:CreateToggle({
    Name = "Instant Level 70+ (Sahur only)",
    CurrentValue = false,
    Flag = "woodz_fastlevel",
    Callback = function(v) if handlers.onFastLevelToggle then handlers.onFastLevelToggle(v) end end,
  })

  -- Optional: apply HUD hiding like old UI
  do
    local StarterGui = game:GetService("StarterGui")
    local flags = { premiumHidden=true, vipHidden=true, limitedPetHidden=true }
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local h1 = hud.findHUD(pg);          if h1 then hud.apply(h1, flags); hud.watch(h1, flags) end
    local h2 = hud.findHUD(StarterGui);  if h2 then hud.apply(h2, flags); hud.watch(h2, flags) end
  end

  -- Controls exposed back to app.lua
  local UI = {
    setCurrentTarget = function(text) pcall(function() currentLabel:Set(text or "Current Target: None") end) end,
    setAutoFarm      = function(on)   pcall(function() rfAutoFarm:Set(on and true or false) end) end,
    setSmartFarm     = function(on)   pcall(function() rfSmartFarm:Set(on and true or false) end) end,
    setMerchant1     = function(on)   pcall(function() rfMerch1:Set(on and true or false) end) end,
    setMerchant2     = function(on)   pcall(function() rfMerch2:Set(on and true or false) end) end,
    setCrates        = function(on)   pcall(function() rfCrates:Set(on and true or false) end) end,
    setAntiAFK       = function(on)   pcall(function() rfAFK:Set(on and true or false) end) end,
    setFastLevel     = function(on)   pcall(function() rfFastLvl:Set(on and true or false) end) end,

    refreshModelOptions = function() refreshDropdownOptions() end,
    syncModelSelection  = function() syncDropdownSelectionFromFarm() end,

    destroy          = function() pcall(function() Rayfield:Destroy() end) end,
  }

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)
  return UI
end

return M
