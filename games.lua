-- games.lua
-- Map universeId (tostring(game.GameId)) or placeId override -> profile
-- Each profile selects which modules to load and which Rayfield controls to show.

return {
  -- fallback
  default = {
    name = "Generic",
    modules = { "anti_afk" },
    ui = {
      modelPicker = false, currentTarget = false,
      autoFarm = false, smartFarm = false,
      merchants = false, crates = false, antiAFK = true,
      redeemCodes = false, fastlevel = false, privateServer = false,
      dungeon = false,
    },
  },

  --------------------------------------------------------------------
  -- Brainrot Evolution (main experience) — replace this key if your
  -- universeId differs. Use tostring(game.GameId) for universe keys.
  --------------------------------------------------------------------
  ["place:111989938562194"] = {
    name = "Brainrot Evolution",
    modules = { "anti_afk","farm","smart_target","merchants","crates","redeem_unredeemed_codes","fastlevel" },
    ui = {
      modelPicker = true,   currentTarget = true,
      autoFarm = true,      smartFarm = true,
      merchants = true,     crates = true,  antiAFK = true,
      redeemCodes = true,   fastlevel = true, privateServer = true,
      dungeon = false,
    },
  },

  --------------------------------------------------------------------
  -- Brainrot Evolutions • Dungeons (PlaceId-specific route)
  -- This profile boots a dedicated module that draws its own Rayfield UI,
  -- so we don’t enable the generic hub controls here.
  --------------------------------------------------------------------
  ["place:90608986169653"] = {
    name = "Brainrot Dungeon",
    modules = { "anti_afk","dungeon_be" },
    ui = {
      modelPicker = false,  currentTarget = false,
      autoFarm = false,     smartFarm = false,
      merchants = false,    crates = false, antiAFK = true,
      redeemCodes = false,  fastlevel = false, privateServer = false,
      dungeon = true,       -- shows "Dungeon Auto-Attack" + "Play Again" toggles
    },
  },
}
