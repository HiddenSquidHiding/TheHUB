-- games.lua
-- Map universeId (tostring(game.GameId)) or "place:<placeId>" -> profile

return {
  --------------------------------------------------------------------
  -- Fallback (used when no specific entry matches)
  -- Turn stuff ON here so you always see a UI even if you’re in a new game.
  --------------------------------------------------------------------
  default = {
    name = "Generic",
    modules = {
      "anti_afk","farm","smart_target","merchants","crates",
      "redeem_unredeemed_codes","fastlevel"
    },
    ui = {
      -- Main tab
      modelPicker   = true,
      currentTarget = true,
      autoFarm      = true,
      smartFarm     = true,

      -- Options tab
      merchants     = true,
      crates        = true,
      antiAFK       = true,
      redeemCodes   = true,
      fastlevel     = true,
      privateServer = true,
    },
  },

  --------------------------------------------------------------------
  -- Brainrot Evolution (put your universe/game ID here if you want
  -- a specific profile for the main game)
  -- Use tostring(game.GameId)
  --------------------------------------------------------------------
  ["place:111989938562194"] = {  -- <-- replace with your Brainrot Evolution GameId
    name = "Brainrot Evolution",
    modules = {
      "anti_afk","farm","smart_target","merchants","crates",
      "redeem_unredeemed_codes","fastlevel"
    },
    ui = {
      modelPicker   = true,
      currentTarget = true,
      autoFarm      = true,
      smartFarm     = true,
      merchants     = true,
      crates        = true,
      antiAFK       = true,
      redeemCodes   = true,
      fastlevel     = true,
      privateServer = true,
    },
  },

  --------------------------------------------------------------------
  -- Brainrot Evolution DUNGEONS (place-specific)
  -- Key must be "place:<PlaceId>"
  --------------------------------------------------------------------
  ["place:90608986169653"] = {
    name = "Brainrot Dungeons",
    -- maybe a lighter set for the dungeon
    modules = { "anti_afk" }, -- swap in your dungeon-specific modules when ready
    ui = {
      modelPicker   = false,  -- no picker in dungeon
      currentTarget = false,
      autoFarm      = false,  -- (enable if you wire your dungeon auto)
      smartFarm     = false,

      merchants     = false,
      crates        = false,
      antiAFK       = true,
      redeemCodes   = false,
      fastlevel     = false,
      privateServer = false,
    },
  },
}
