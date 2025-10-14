-- games.lua — choose which controls to show per game
return {
  default = {
    name = "Generic",
    ui = {
      modelPicker=false, currentTarget=true,
      autoFarm=false, smartFarm=false,
      merchants=false, crates=false, antiAFK=true,
      redeemCodes=true, fastlevel=false, privateServer=false,
      dungeonAuto=false, dungeonReplay=false,
    },
  },

  -- Brainrot Evolution (the main world)
  ["place:111989938562194"] = {
    name = "Brainrot Evolution",
    ui = {
      modelPicker=true, currentTarget=true,
      autoFarm=true, smartFarm=true,
      merchants=true, crates=true, antiAFK=true,
      redeemCodes=true, fastlevel=true, privateServer=true,
      sahurHopper = true,
      dungeonAuto=false, dungeonReplay=false,
    },
  },

  -- Brainrot Evolution Dungeons (replace with actual PlaceId)
  ["place:90608986169653"] = {
    name = "Brainrot Dungeon",
    ui = {
      modelPicker=false, currentTarget=true,
      autoFarm=false, smartFarm=false,
      merchants=false, crates=false, antiAFK=true,
      redeemCodes=false, fastlevel=false, privateServer=false,
      dungeonAuto=true, dungeonReplay=true,
    },
  },
}
