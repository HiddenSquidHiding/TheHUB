-- games.lua
-- Map universeId (tostring(game.GameId)) or placeId override -> profile
-- Each profile selects which modules to load and which Rayfield controls to show.

return {
  -- Fallback if no exact match
  default = {
    name = "Generic",
    modules = { "anti_afk" }, -- keep it light by default
    ui = {
      modelPicker   = false, currentTarget = false,
      autoFarm      = false, smartFarm     = false,
      merchants     = false, crates        = false, antiAFK = true,
      redeemCodes   = false, fastlevel     = false, privateServer = false,
    },
  },

  --------------------------------------------------------------------
  -- Brainrot Evolution (main experience) — replace this key if your
  -- universeId differs. Use tostring(game.GameId) for universe keys.
  --------------------------------------------------------------------
  ["place:111989938562194"] = {
    name = "Brainrot Evolution",
    modules = {
      "anti_afk","farm","smart_target","merchants","crates",
      "redeem_unredeemed_codes","fastlevel"
    },
    ui = {
      modelPicker   = true,  currentTarget = true,
      autoFarm      = true,  smartFarm     = true,
      merchants     = true,  crates        = true,  antiAFK = true,
      redeemCodes   = true,  fastlevel     = true,  privateServer = true,
    },
  },

  --------------------------------------------------------------------
  -- Brainrot Evolutions • Dungeons (PlaceId-specific route)
  -- This profile boots a dedicated module that draws its own Rayfield UI,
  -- so we don’t enable the generic hub controls here.
  --------------------------------------------------------------------
  ["place:90608986169653"] = {
    name    = "Brainrot Dungeons",
    modules = { },              -- let the dungeon module own its logic/UI
    run     = "brainrot_dungeon_rayfield", -- << require(this ModuleScript) if present
    ui      = {
      modelPicker   = false, currentTarget = false,
      autoFarm      = false, smartFarm     = false,
      merchants     = false, crates        = false, antiAFK = false,
      redeemCodes   = false, fastlevel     = false, privateServer = false,
    },
  },
}
