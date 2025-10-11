-- games.lua
-- Map universeId (tostring(game.GameId)) or placeId override -> profile
-- Each profile selects which modules to load and which Rayfield controls to show.

return {
  -- Fallback if no exact match
  default = {
    name = "Generic",
    modules = { "anti_afk" }, -- keep it light by default
    ui = {
      modelPicker = false, currentTarget = false,
      autoFarm = false, smartFarm = false,
      merchants = false, crates = false, antiAFK = true,
      redeemCodes = false, fastlevel = false, privateServer = false,
    },
  },

  --------------------------------------------------------------------
  -- Example profile — replace the key with your universeId (GameId)
  -- tostring(game.GameId)
  --------------------------------------------------------------------
  ["0000000000000000000"] = {
    name = "Brainrot Evolution",
    modules = {
      "anti_afk","farm","smart_target","merchants","crates",
      "redeem_unredeemed_codes","fastlevel"
    },
    ui = {
      modelPicker = true,   currentTarget = true,
      autoFarm = true,      smartFarm = true,
      merchants = true,     crates = true,  antiAFK = true,
      redeemCodes = true,   fastlevel = true, privateServer = true,
    },
  },

  --------------------------------------------------------------------
  -- You can also target a specific place:
  -- key format: "place:<placeId>"
  --------------------------------------------------------------------
  -- ["place:1234567890"] = {
  --   name = "My Special Place",
  --   modules = { "anti_afk", "farm" },
  --   ui = {
  --     modelPicker = true, currentTarget = true,
  --     autoFarm = true, smartFarm = false,
  --     merchants = false, crates = false, antiAFK = true,
  --     redeemCodes = false, fastlevel = false, privateServer = true,
  --   },
  -- },
}
