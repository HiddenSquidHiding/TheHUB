-- ui_rayfield.lua  • Rayfield window + game-aware controls

local utils = rawget(getfenv(), "__WOODZ_UTILS") or {
  notify = function(_,_) end
}

local Rayfield = nil
do
  local ok, lib = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
  end)
  if ok then Rayfield = lib else warn("[ui_rayfield] could not fetch Rayfield:", lib) end
end

local M = {}

function M.build(opts)
  opts = opts or {}
  local h = opts.handlers or {}
  local f = opts.flags or {}
  local title = opts.title or "WoodzHUB"

  if not Rayfield then
    warn("[ui_rayfield] Rayfield failed to load")
    return {
      destroy=function() end,
      setCurrentTarget=function() end,
    }
  end

  local Window = Rayfield:CreateWindow({
    Name = "🌲 WoodzHUB — "..title,
    LoadingTitle = "WoodzHUB",
    LoadingSubtitle = "Rayfield",
    ConfigurationSaving = { Enabled = false, FolderName = "WoodzHUB", FileName = "RF" },
    KeySystem = false,
  })

  local Main    = Window:CreateTab("Main")
  local Options = Window:CreateTab("Options")

  -- MAIN
  if f.dungeon then
    Main:CreateSection("Dungeon")
    local togA = Main:CreateToggle({
      Name = "Auto-Attack Dungeon",
      CurrentValue = false,
      Callback = function(v) if h.onDungeonAuto then h.onDungeonAuto(v) end end,
    })
    local togR = Main:CreateToggle({
      Name = "Auto Replay",
      CurrentValue = true,
      Callback = function(v) if h.onDungeonReplay then h.onDungeonReplay(v) end end,
    })
  end

  -- OPTIONS
  Options:CreateSection("General")
  if f.antiAFK ~= false then
    Options:CreateToggle({
      Name = "Anti-AFK",
      CurrentValue = false,
      Callback = function(v) if h.onToggleAntiAFK then h.onToggleAntiAFK(v) end end,
    })
  end

  if f.redeemCodes then
    Options:CreateButton({
      Name = "Redeem Unredeemed Codes",
      Callback = function() if h.onRedeemCodes then h.onRedeemCodes() end end,
    })
  end

  if f.privateServer then
    OptionsTab:CreateButton({
    Name = "Private Server",
    Callback = function()
      task.spawn(function()
        if not _G.TeleportToPrivateServer then
          utils.notify("🌲 Private Server", "Run solo.lua first to set up the function!", 4)
          return
        end
        local success, err = pcall(_G.TeleportToPrivateServer)
        if success then
          utils.notify("🌲 Private Server", "Teleport initiated to private server!", 3)
        else
          utils.notify("🌲 Private Server", "Failed to teleport: " .. tostring(err), 5)
        end
      end)
    end,
  })

  utils.notify("🌲 WoodzHUB", "Rayfield UI loaded.", 3)

  local api = {
    destroy = function() pcall(function() Rayfield:Destroy() end) end,
    setCurrentTarget = function(_) end,
  }
  return api
end

return M
