-- games.lua
-- Map universeId (tostring(game.GameId)) or place override "place:<PlaceId>" -> profile table.
-- Must return a LUA TABLE (not JSON), and be a ModuleScript named exactly "games".

return {
  -- Fallback if no match
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

  -- Main Brainrot Evolution (UNIVERSE / GameId)
  -- Get this value by running:  print(game.GameId)  in the in-game console.
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

  -- Brainrot Evolution DUNGEON (place override)
  ["place:90608986169653"] = {
    name = "Brainrot Dungeon",
    modules = { "anti_afk","dungeon_be" },
    ui = {
      modelPicker = false,  currentTarget = false,
      autoFarm = false,     smartFarm = false,
      merchants = false,    crates = false, antiAFK = true,
      redeemCodes = false,  fastlevel = false, privateServer = false,
      dungeon = true,       -- shows Dungeon toggles in Rayfield
    },
  },
}
