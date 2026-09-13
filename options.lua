-- Mod Manager option schema for g9-battle-sprites.
--
-- Declared in manifest.json's "options_schema" field so the manager (and
-- native launchers reading mod_option_schemas.json) can render these rows even
-- while the mod is disabled.  main.lua calls mod.options:define() with the
-- IDENTICAL table at load time, which is what gives mod.options:get() its
-- defaults.  Keep the two copies in sync.
--
-- Row shapes: toggle { key, label, type="toggle", default=bool };
-- choice { key, label, type="choice", default=value,
--          choices={ { "LABEL", value }, ... } }.
return {
  {
    key = "enable_battle_sprites",
    label = "BATTLE SPRITES",
    type = "toggle",
    default = true,
    description = "ON (default): battle Pokemon use the true-colour animated DBK sprite sheets. OFF: every battle pic is left exactly as the game would draw it.",
  },
  {
    key = "animate_sprites",
    label = "ANIMATE",
    type = "toggle",
    default = true,
    description = "ON (default): the sprite sheet plays left-to-right as a loop. OFF: only the sheet's first frame is shown (a still picture).",
  },
  {
    key = "sprite_fps",
    label = "SPRITE SPEED",
    type = "choice",
    default = 12,
    choices = {
      { "SLOW", 6 },
      { "NORMAL", 12 },
      { "FAST", 18 },
      { "VERY FAST", 24 },
    },
    description = "Playback speed of the animated sheets (frames per second).",
  },
  {
    key = "sprite_shiny",
    label = "SHINY ART",
    type = "toggle",
    default = true,
    description = "ON (default): shiny Pokemon use the *_shiny sheets. OFF: shiny Pokemon use the normal-colour sheets.",
  },
  {
    key = "sprite_female",
    label = "FEMALE ART",
    type = "toggle",
    default = true,
    description = "ON (default): female Pokemon use their _female sheet where the pack has one. OFF: one sheet for both sexes.",
  },
  {
    key = "sprite_size",
    label = "SPRITE SIZE",
    type = "choice",
    default = 0,
    choices = {
      { "MAX DETAIL", 0 },
      { "SMALL", 3 },
      { "NORMAL", 2 },
      { "BIG", 1 },
    },
    description = "MAX DETAIL (default): every sheet is as detailed as it can be -- shown 1:1 when it already fits its picture box, and shrunk no further than it must be when it is too big, so it fills the box instead of sitting at half size inside it. SMALL / NORMAL / BIG instead divide every sheet by 3 / 2 / 1, keeping strictly proportional sizes. Every mode resamples with nearest-neighbour, so pixels stay hard-edged and the pack's exact colours are kept. NOTE: a custom battle screen (g9-Battle-Scene and its layouts) bakes its own one uniform scale for the whole field, so this row governs the game's own battle screens; the scene's own battles always keep every species' true relative size.",
  },
  {
    key = "sprite_metrics",
    label = "PACK ALIGNMENT",
    type = "toggle",
    default = true,
    description = "ON (default): place each sprite using the offsets from the pack's own SpeciesMetrics data (data/dbk_metrics.lua), so every Pokemon stands where the pack intends it to. OFF: every sprite simply sits bottom-centre in its box.",
  },
  {
    key = "dex_sprites",
    label = "DEX SPRITES",
    type = "toggle",
    default = true,
    description = "ON (default): the Pokedex shows the same true-colour sheet as the battle screen (its first frame when ANIMATE is off). OFF: the Pokedex keeps the game's own front pic.",
  },
}
