-- =============================================================================
-- g9-battle-sprites -- true-colour animated battle sprites for the national dex
-- =============================================================================
--
-- WHAT IT DOES
--   Replaces the enemy front pic and the player back pic in battle -- and the
--   front pic on the Pokedex entry page -- with an animated, full-colour
--   sprite sheet from the DBK "solo sprites" pack
--   (la-base-de-sky / sprites-animados-dbk-solo-sprites, folders
--   Graphics/Pokemon/{Front, Front shiny, Back, Back shiny}).
--
--   The pack ships ONE png per Pokemon: a single horizontal strip whose frames
--   butt edge to edge, left to right, frame height == sheet height.  We use that
--   sheet DIRECTLY -- nothing is ever split into per-frame .png files on disk,
--   and no per-Pokemon subfolders are created (the pack is already one file per
--   Pokemon).  Frames are cropped out of the sheet in memory, each frame is
--   resampled once to the exact battle-pic box and cached as an Image.
--
-- LOOKUP (per battle pic)
--   1. national_dex species id (+ gender + shiny) -> a DBK sheet stem
--      (data/dbk_data.lua maps every species id to its stem; unknown forms fall
--      back to their base species).
--   2. <mod>/assets/<front|front_shiny|back|back_shiny>/<STEM>.png -- the mod's
--      own assets/ folder, and the ONLY source.  A sheet that is not installed
--      there simply leaves the vanilla pic untouched: there is no network
--      access and nothing is ever written.
--
-- FORM CONVENTIONS (the part that needed care)
--   * national_dex represents every mechanically/sprite-distinct form as its
--     own species id, and the map resolves each to the pack's own stem:
--       CHARIZARD_MEGA_X -> CHARIZARD_1     RAICHU_ALOLA    -> RAICHU_1
--       CHARIZARD_GMAX   -> CHARIZARD_3     SNEASEL_HISUI   -> SNEASEL_1
--       ALCREMIE_GMAX    -> ALCREMIE_63     MEOWSTIC_FEMALE -> MEOWSTIC_1
--       BASCULEGION_FEMALE -> BASCULEGION_1 OINKOLOGNE_FEMALE -> OINKOLOGNE_1
--   * cosmetic-only forms the pack has no sheet for (e.g. every Alcremie
--     flavour except base + gmax) are not mapped and fall back to the base
--     species sheet, which is the pack's own intent (base == ALCREMIE,
--     gmax == ALCREMIE_63).
--   * a Pokemon whose *gender* picks a different sheet (ABOMASNOW_female,
--     SNEASEL_1_female, ...) uses <stem>_female when the mon is female and the
--     pack has that file (data/dbk_data.lua's `female` set).
--   * shiny mons use the *_shiny folders.
--
-- PICTURE BOXES (why the frames are baked at these exact sizes)
--   Every frame is resampled ONCE into a canvas of the on-screen size the
--   vanilla pic occupies, so the engine's own placement math lands the sprite
--   exactly where the GB drew it and the pic scale can stay 1.
--     gen1 enemy front: 7x7 tiles at (96,0)          -> 56x56 at 1x
--     gen1 player back: pokered's 32x32 pic at 2x     -> 64x64 at 1x
--     gen2 enemy front: 7x7 tile box at (96,0)        -> 56x56 at 1x
--     gen2 player back: 6x6 tile box at (16,48)       -> 48x48 at 1x
--   (src/battle/BattleState.lua documents the gen1 back as "32x32 drawn at 2x";
--   src/ui/gen2/BattleState.lua documents the gen2 boxes.)
--
-- SIZES AND ALIGNMENT (the SPRITE SIZE / PACK ALIGNMENT options)
--   A sheet's pixels ARE the art's own resolution, so the way to keep the
--   image faithful is to spend as many of them on screen as the pic box can
--   hold.  MAX DETAIL (the default) therefore sizes each sheet on its own:
--   copied 1:1 when it already fits the box (a small Pokemon keeps every source
--   pixel), and shrunk only as far as it must be when it does not (a big
--   Pokemon fills the box instead of sitting at half size inside it).  Relative
--   size is still honoured for everything that fits; sheets taller than the box
--   all land on the box, which is as large as the screen can show them anyway.
--
--   The resample is ALWAYS nearest-neighbour, on a fractional grid: each
--   destination pixel takes the source pixel nearest its own centre, so hard
--   edges and the pack's exact palette survive.  (An area/box filter instead
--   blends neighbouring colours into new ones, which reads as a soft, muddy
--   smear beside the game's crisp pixel UI -- the earlier "blurry sprites"
--   complaint.)  A destination pixel whose nearest source pixel is transparent
--   borrows the nearest OPAQUE pixel it covers, so a one-pixel outline or
--   antenna is never punched out by the stride.
--
--   SMALL / NORMAL / BIG instead divide every sheet by one whole number (3 / 2
--   / 1), the old strictly-proportional behaviour, for anyone who prefers it.
--   A sheet too big to fit the box is always shrunk to fit, whatever the mode.
--
--
--   Alignment comes from the pack's own SpeciesMetrics data, parsed into
--   data/dbk_metrics.lua (FrontSprite/BackSprite x,y per stem).  The pack
--   anchors a sheet's UNTRIMMED frame bottom-centre at a fixed base and then
--   shifts it by those values * 2 screen px.  We trim each sheet to its content
--   first, so the padding the metrics assume is gone and is put back with the
--   same arithmetic Essentials/DBK use; see setupFrames for the derivation.
--   PACK ALIGNMENT off simply bottom-centres every sprite in its box.
--
-- HOW IT HOOKS IN
--   gen1: wraps src.battle.BattleState:drawPicsLayer to hand each managed
--         battler its current frame as battler.sprite (the engine's own pic
--         draw path -- faint slides, send-out grow, squish/blink all keep
--         working), forces resolveBattleScale -> 1 for managed species, and
--         marks the drawn rect true-colour (PaletteFX.markTrueColor) so the
--         SGB/GBC zone pass leaves it alone.
--   gen2: wraps src.ui.gen2.BattleState:pic to return the current frame Image
--         with trueColor = true (Gold draws a trueColor pic raw), picScale -> 1
--         for managed species, and frontAnimFrame -> nil so Crystal's own
--         animated front pics never take precedence.
--   dex:  the Pokedex does NOT draw through either battle screen -- it asks
--         src.pokemon.Sprites.path / Sprites.pic for a front-pic PATH and loads
--         that file itself, so the pokemon.sprite hook (which can only swap the
--         path string) can never hand it our in-memory frame.  gen1's
--         src.ui.DexEntryMenu:draw and gen2's src.ui.gen2.PokedexMenu:picFor are
--         therefore wrapped directly to return the current frame with
--         trueColor = true (see the dex block below).  DEX SPRITES turns it off.
--   A core.update hook advances frame building on a strict per-frame time
--   budget, so image work never blocks a frame and no image work ever happens
--   inside a draw call.
--
-- SECURITY / SANDBOX NOTES
--   Needs only the "engine_internals" permission (it requires the BattleState
--   modules and PaletteFX).  It reads exclusively from its own assets/ folder:
--   no network access, no cache and no write of any kind.  It never touches
--   another mod, a playthrough save, or a host path.
-- =============================================================================
return function(mod)
  -- ---------------------------------------------------------------------------
  -- Options (identical table to options.lua -- keep the two in sync)
  -- ---------------------------------------------------------------------------
  local OPTIONS = {
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
      description = "MAX DETAIL (default): every sheet is as detailed as it can be -- shown 1:1 when it already fits its picture box, and shrunk no further than it must be when it is too big, so it fills the box instead of sitting at half size inside it. SMALL / NORMAL / BIG instead divide every sheet by 3 / 2 / 1, keeping strictly proportional sizes. Every mode resamples with nearest-neighbour, so pixels stay hard-edged and the pack's exact colours are kept. NOTE: a custom battle screen (g9-Battle-Scene and its layouts) bakes its own field scale instead -- every sprite at the pack's natural 1:1 size, its boss at x1.6 -- so this row governs the game's own battle screens; the scene's own battles always keep every species' true relative size.",
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
  mod.options:define(OPTIONS)

  -- ---------------------------------------------------------------------------
  -- Constants
  -- ---------------------------------------------------------------------------
  -- On-screen pic boxes in GB pixels (see the PICTURE BOXES note up top).
  local FRONT_BOX = { w = 56, h = 56 }
  local BACK_BOX_GEN1 = { w = 64, h = 64 }   -- pokered 32x32 pic drawn at 2x
  local BACK_BOX_GEN2 = { w = 48, h = 48 }   -- pokecrystal 6x6 tile box at 1x

  -- Frame building is spread across frames under this per-update time budget so
  -- a new sheet never stalls the game.  Scan rows per chunk bounds the work of
  -- one step even when a single step would blow the budget.
  local BUILD_BUDGET = 0.008
  local SCAN_ROWS = 6
  -- How many resolved sheets to keep before the least-recently-used one has its
  -- frame Images dropped (the raw png bytes are kept, so a rebuild is offline
  -- and cheap; any Image still referenced by a live battler simply stays alive
  -- until Lua collects it).
  local MAX_SHEETS = 64
  local EVICT_AGE_FRAMES = 1200
  -- Re-scan a sheet that was not found in assets/ this often, so a file copied
  -- in mid-session is picked up without a restart.
  local RECHECK_FRAMES = 900

  local GEN = 0   -- 1 or 2, set once a supported battle screen is found

  local function localFolder(back, shiny)
    if back then return shiny and "back_shiny" or "back" end
    return shiny and "front_shiny" or "front"
  end

  -- ---------------------------------------------------------------------------
  -- Generated data (species -> stem, stem existence, female stems)
  -- ---------------------------------------------------------------------------
  local function readData(rel)
    local text, err = mod:read(rel)
    if not text then return nil, err end
    local chunk, cerr = loadstring(text, "@" .. rel)
    if not chunk then return nil, cerr end
    local ok, value = pcall(chunk)
    if not ok or type(value) ~= "table" then return nil, "bad data" end
    return value
  end

  local DATA, dataErr = readData("data/dbk_data.lua")
  if not (DATA and DATA.species and DATA.stems and DATA.female) then
    mod.log:error("g9-battle-sprites: data/dbk_data.lua is missing or invalid (%s)"
      .. " -- mod inactive", tostring(dataErr))
    return
  end

  -- Per-species alignment offsets from the pack's own SpeciesMetrics files (see
  -- data/dbk_metrics.lua).  Optional: without it every sprite is simply
  -- bottom-centred in its box.
  local METRICS = readData("data/dbk_metrics.lua")
  if not METRICS then
    mod.log:warn("g9-battle-sprites: data/dbk_metrics.lua is missing or invalid --"
      .. " sprites will be bottom-centred (reinstall the mod, or turn PACK"
      .. " ALIGNMENT off to silence this)")
  end

  -- ---------------------------------------------------------------------------
  -- Option accessors
  -- ---------------------------------------------------------------------------
  local function opt(key, default)
    local ok, value = pcall(mod.options.get, mod.options, key)
    if ok and value ~= nil then return value end
    return default
  end
  local function wantEnabled() return opt("enable_battle_sprites", true) ~= false end
  local function animateOn() return opt("animate_sprites", true) ~= false end
  local function wantShiny() return opt("sprite_shiny", true) ~= false end
  local function wantFemale() return opt("sprite_female", true) ~= false end
  local function dexOn() return opt("dex_sprites", true) ~= false end
  -- The on-screen diagnostics panel is disabled outright: it was useful while
  -- the sheet loader was being brought up, but it is not something a player
  -- should be able to switch on.  The diag code stays (it is the only way to
  -- see what the mod is doing on a build with no developer console) but is
  -- dormant unless this is flipped to true in source.
  local DEBUG_PANEL_ENABLED = false
  local function debugOn() return DEBUG_PANEL_ENABLED end

  -- The pack's own render scales (Essentials/DBK Settings).  Its SpeciesMetrics
  -- x,y values are stored in half-units of these, so converting an offset back
  -- to sheet pixels divides by them (see setupFrames).
  local FRONT_SCALE = 2
  local BACK_SCALE = 3

  -- SPRITE SIZE.  0 (MAX DETAIL, the default) means "the largest scale that
  -- fits this sheet's own box", i.e. 1:1 wherever the sheet already fits and a
  -- shrink to the box only where it does not.  A value n > 0 divides every
  -- sheet by n (3 = SMALL, 2 = NORMAL, 1 = BIG/1:1).  Values >= 8 are the old
  -- "sheet height in pixels that fills the box" setting, kept working for
  -- anyone who already saved one (110 -> 2, 160 -> 3, 80 -> 1).
  local LEGACY_SIZE_REF = FRONT_BOX.h
  local function spriteSizeMode()
    local n = tonumber(opt("sprite_size", 0))
    if not n then n = 0 end
    if n >= 8 then n = math.floor(n / LEGACY_SIZE_REF + 0.5) end
    if n < 1 then n = 0 end
    return n
  end
  -- Round half up (Lua 5.1/LuaJIT has no math.round).
  local function round(n) return math.floor(n + 0.5) end
  local function useMetrics() return opt("sprite_metrics", true) ~= false end
  local function fpsValue()
    local n = tonumber(opt("sprite_fps", 12))
    if not n or n < 1 then n = 12 elseif n > 60 then n = 60 end
    return n
  end

  -- ---------------------------------------------------------------------------
  -- On-screen diagnostics (dormant -- see DEBUG_PANEL_ENABLED)
  -- ---------------------------------------------------------------------------
  -- The engine's in-game developer console is Gen 1 ONLY -- Gold exposes
  -- mod.developer but implements neither the console nor its hotkeys -- and
  -- mod.log lines go to stdout, which a player never sees.  So a mod that only
  -- logs is completely silent on exactly the build most players run.  The
  -- panel below paints a small box INTO the finished UI canvas from
  -- render.compose, so "no sheets in assets/" or "the battle screen never asked
  -- us" is readable on screen with no console at all.  It is switched off in
  -- shipped builds (DEBUG_PANEL_ENABLED = false, and there is no option row for
  -- it); flip the constant if the loader ever needs diagnosing again.
  local DIAG_MAX_EVENTS = 5
  local DIAG_MAX_CHARS = 31
  local DIAG_MAX_REASON_LINES = 3

  local diag = {
    on = false,
    lastFrame = -1,
    events = {},
    font = nil,
    fontH = 9,
    stats = { pics = 0, scene = 0, gen1 = 0, ready = 0, failed = 0, missing = 0 },
    census = { front = 0, front_shiny = 0, back = 0, back_shiny = 0 },
    inst = "none",
    gen = 0,
    lastResolve = nil,
    lastFail = nil,
    lastFailWhy = nil,
  }

  local function diagPush(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    if not ok then line = tostring(fmt) end
    if #line > DIAG_MAX_CHARS then line = line:sub(1, DIAG_MAX_CHARS) end
    table.insert(diag.events, 1, line)
    while #diag.events > DIAG_MAX_EVENTS do table.remove(diag.events) end
  end

  local function diagGetFont()
    if diag.font then return diag.font, diag.fontH end
    local g = love and love.graphics
    if not g then return nil, 9 end
    local font
    if g.newFont then
      local ok, f = pcall(g.newFont, 8)
      if ok then font = f end
    end
    if not font and g.getFont then
      local ok, f = pcall(g.getFont)
      if ok then font = f end
    end
    if not font then return nil, 9 end
    diag.font = font
    if font.getHeight then
      local okH, h = pcall(font.getHeight, font)
      if okH and type(h) == "number" and h > 0 then diag.fontH = h + 1 end
    end
    return diag.font, diag.fontH
  end

  -- ---------------------------------------------------------------------------
  -- Mon inspection (works on both generations, defensively)
  -- ---------------------------------------------------------------------------
  local statsModule            -- cached require("src.pokemon.Stats"), or false
  local function shinyFromDvs(dvs)
    if statsModule == nil then
      local ok, m = pcall(require, "src.pokemon.Stats")
      statsModule = (ok and type(m) == "table") and m or false
    end
    if statsModule and statsModule.isShiny then
      local ok, shiny = pcall(statsModule.isShiny, dvs)
      if ok then return shiny and true or false end
    end
    return false
  end

  local function isShiny(mon)
    if type(mon) ~= "table" then return false end
    if mon.shiny ~= nil then return mon.shiny and true or false end
    if type(mon.dvs) == "table" then return shinyFromDvs(mon.dvs) end
    return false
  end

  local function isFemale(mon)
    if type(mon) ~= "table" then return false end
    local flag = mon.isFemale
    if type(flag) == "boolean" then return flag end
    local g = mon.gender or mon.sex
    if type(g) == "string" then
      g = g:lower()
      return g == "female" or g == "f"
    end
    return false
  end

  -- ---------------------------------------------------------------------------
  -- Species id -> DBK stem
  -- ---------------------------------------------------------------------------
  local function stripLastWord(name)
    local s = name:find("_[^_]*$")
    if not s then return nil end
    return name:sub(1, s - 1)
  end

  -- Walk the form suffix chain until a mapped, existing stem is found:
  -- KOMMO_O_TOTEM -> KOMMO_O -> KOMMOO (the pack drops underscores).
  local function baseStem(species)
    local name = species
    while true do
      name = stripLastWord(name)
      if not name then return nil end
      local stem = DATA.species[name]
      if stem and DATA.stems[stem] then return stem end
    end
  end

  local function resolveStem(species)
    if type(species) ~= "string" then return nil end
    local stem = DATA.species[species]
    if not (stem and DATA.stems[stem]) then stem = baseStem(species) end
    if stem and DATA.stems[stem] then return stem end
    return nil
  end

  local function femaleStem(stem)
    if DATA.female[stem] then return stem .. "_female" end
    return stem
  end

  -- Resolve a live mon to (stem, shiny) for the given side.
  local function monStem(mon)
    if type(mon) ~= "table" then return nil end
    local stem = resolveStem(mon.species)
    if not stem then return nil end
    if wantFemale() and isFemale(mon) then stem = femaleStem(stem) end
    local shiny = false
    if wantShiny() then shiny = isShiny(mon) end
    return stem, shiny
  end

  -- ---------------------------------------------------------------------------
  -- PNG -> ImageData
  -- ---------------------------------------------------------------------------
  -- A mod cannot assume any single decode route works on a given build, so a
  -- sheet is decoded through up to three of them, cheapest first:
  --
  --   A. straight from the mod's own folder with the engine's path helper --
  --      love.image.newImageData(mod.assets:path(rel)).  This is the call
  --      mod.assets:image makes and what every image-loading mod uses.
  --   B. the file bytes copied into a FileData and decoded from that
  --      (love.data.newFileData, or the 0.10 love.filesystem equivalent).  It
  --      needs no path but does need a working byte -> FileData constructor.
  --   C. love.graphics.newImage(path):getData() -- a detour through the GPU,
  --      kept as a last resort for a build with graphics but no usable image
  --      decoder.
  --
  -- Route A is tried first: it is the shortest path to a decoder and the one
  -- the engine itself blesses.  Every route's failure is reported, so the DEBUG
  -- panel can say exactly what went wrong instead of the mod simply looking
  -- dead.
  local function assetPath(rel)
    local assets = mod.assets
    if not (assets and type(assets.path) == "function") then return nil end
    local ok, full = pcall(assets.path, assets, rel)
    if ok and type(full) == "string" and full ~= "" then return full end
    return nil
  end

  local function decodeFromPath(rel)
    local img = love and love.image
    if not (img and img.newImageData) then return nil, "no love.image" end
    local full = assetPath(rel)
    if not full then return nil, "no mod.assets:path" end
    local ok, id = pcall(img.newImageData, full)
    if ok and id then return id end
    return nil, "newImageData(path): " .. tostring(ok and "nil" or id)
  end

  local function decodeFromImage(rel)
    local g = love and love.graphics
    if not (g and g.newImage) then return nil, "no love.graphics" end
    local full = assetPath(rel)
    if not full then return nil, "no mod.assets:path" end
    local ok, img = pcall(g.newImage, full)
    if not (ok and img) then
      return nil, "newImage: " .. tostring(ok and "nil" or img)
    end
    if type(img.getData) ~= "function" then return nil, "Image has no getData" end
    local okd, id = pcall(img.getData, img)
    if okd and id then return id end
    return nil, "Image:getData: " .. tostring(okd and "nil" or id)
  end

  local function decodeFromBytes(bytes, stem)
    local img = love and love.image
    if not (img and img.newImageData) then return nil, "no love.image" end
    if type(bytes) ~= "string" or #bytes == 0 then return nil, "no bytes" end
    local fd
    local dm = love and love.data
    if dm and dm.newFileData then
      local ok, res = pcall(dm.newFileData, bytes, stem .. ".png")
      if ok and res then fd = res end
    end
    if not fd then
      local fsmod = love and love.filesystem
      if fsmod and fsmod.newFileData then
        local ok, res = pcall(fsmod.newFileData, bytes, stem .. ".png")
        if ok and res then fd = res end
      end
    end
    if not fd then
      if not (dm and dm.newFileData)
        and not (love.filesystem and love.filesystem.newFileData) then
        return nil, "no FileData constructor"
      end
      return nil, "FileData not accepted"
    end
    local ok, id = pcall(img.newImageData, fd)
    if ok and id then return id end
    return nil, "newImageData(FileData): " .. tostring(ok and "nil" or id)
  end

  -- Decode one sheet through the routes above, reporting which one won (or why
  -- every available route failed).
  local function decodeSheet(sheet)
    local reasons = {}
    if sheet.rel then
      local id, why = decodeFromPath(sheet.rel)
      if id then return id, "path" end
      reasons[#reasons + 1] = "A " .. tostring(why)
    end
    -- The byte route needs the file contents; read them now and only now, so a
    -- big sheet is not held in memory when the path route already worked.
    if not sheet.bytes and sheet.rel then
      local okr, bytes = pcall(mod.read, mod, sheet.rel)
      if okr and type(bytes) == "string" and #bytes > 0 then sheet.bytes = bytes end
    end
    local idb, whyb = decodeFromBytes(sheet.bytes, sheet.stem)
    if idb then return idb, "bytes" end
    reasons[#reasons + 1] = "B " .. tostring(whyb)
    if sheet.rel then
      local idc, whyc = decodeFromImage(sheet.rel)
      if idc then return idc, "image" end
      reasons[#reasons + 1] = "C " .. tostring(whyc)
    end
    sheet.bytes = nil
    return nil, table.concat(reasons, " | ")
  end

  -- ---------------------------------------------------------------------------
  -- Sheet store
  -- ---------------------------------------------------------------------------
  local sheets = {}          -- key -> record
  local readyCount = 0
  local frameCounter = 0
  -- Weak keys: an evicted sheet's frame Images must be collectable even though
  -- every frame we mark was registered here.
  local ourFrames = setmetatable({}, { __mode = "k" })

  local function sheetKey(back, shiny, stem, box, divisor, zoom, maxH, fill, scale, natural)
    local tag = box and ("@" .. box.w .. "x" .. box.h) or ""
    -- The uniform scale (divisor) and the integer zoom the screen will draw
    -- the baked box at belong in the identity too: they decide how every
    -- frame is resampled, so a sheet baked for one screen's scale must
    -- never be handed to a screen asking for another (see setupFrames).
    local div = divisor and ("d" .. divisor) or ""
    local z = (zoom and zoom ~= 1) and ("z" .. zoom) or ""
    -- An EXPLICIT field scale (see setupFrames path 0) is likewise part of
    -- the identity: a sheet baked at 2x is not the sheet a screen asking
    -- for 3.2x should be handed.
    local sc = scale and ("x" .. scale) or ""
    -- maxH (the on-screen pixels a sprite may rise above its own ground
    -- line) also changes the bake: a sheet folded to fit a short band must
    -- not be reused where there is more headroom.
    local m = maxH and ("m" .. math.floor(maxH + 0.5)) or ""
    -- fill (may the sheet grow past native to fill its box?) decides the
    -- scale too, so it is part of the identity.
    local f = fill and "F" or ""
    -- NATURAL mode (see setupFrames path 0n) bakes the sheet at exactly its
    -- own scaled size with no box at all, so a natural bake must never be
    -- handed to a caller that asked for a box, or vice versa.
    local nat = natural and "R" or ""
    return (back and "b" or "f") .. (shiny and "s" or "n") .. tag .. div .. z .. sc .. m .. f .. nat .. "/" .. stem
  end

  -- The pic box a sheet is baked into.  `override` lets a custom battle screen
  -- name the exact pixel box it will draw the pic into (see the battle.mon_pic
  -- wrap), so its own draw becomes a 1:1 blit instead of a fractional resample.
  local function boxFor(back, override)
    if override then return override end
    if not back then return FRONT_BOX end
    if GEN == 2 then return BACK_BOX_GEN2 end
    return BACK_BOX_GEN1
  end

  local function now()
    local t = love and love.timer and love.timer.getTime
    if t then
      local ok, v = pcall(t)
      if ok and v then return v end
    end
    return frameCounter / 60
  end

  -- -- shared sheet lifecycle ---------------------------------------------
  -- (declared ahead of the builder that calls them)

  local function finishFailed(sheet, why)
    -- A file that is present but unusable (corrupt, or a sheet with no opaque
    -- pixels).  Say so out loud and latch it: a sheet that silently never
    -- arrives looks exactly like the mod not working at all.
    sheet.build = nil
    sheet.bytes = nil
    sheet.status = "failed"
    diag.stats.failed = diag.stats.failed + 1
    diag.lastFail = tostring(sheet.stem)
    diag.lastFailWhy = tostring(why)
    diagPush("%s BUILD FAIL", sheet.stem)
    mod.log:warn("g9-battle-sprites: %s could not be used (%s) -- "
      .. "falling back to the vanilla pic", sheet.stem, tostring(why))
  end

  local function finishReady(sheet, how)
    sheet.status = "ready"
    sheet.lastUsed = frameCounter
    readyCount = readyCount + 1
    diag.stats.ready = diag.stats.ready + 1
    diagPush("%s READY %df", sheet.stem,
      sheet.frameCount or #(sheet.frames or {}))
    mod.log:info("g9-battle-sprites: %s ready (%d frames, %s)",
      sheet.stem, sheet.frameCount or #(sheet.frames or {}), how)
  end

  -- -- frame builder ------------------------------------------------------
  -- Building is split into small steps; stepFrames() runs a bounded number of
  -- them per core.update so a 40-frame sheet never blocks a frame.  Phase 1
  -- scans the sheet once for the union content bbox (across EVERY frame, so the
  -- sprite never jitters from frame to frame); phase 2 lays out the destination
  -- rect (setupFrames: one integer divisor + the pack's alignment offsets) and
  -- bakes each frame by NEAREST-NEIGHBOUR resampling on a whole-number grid.
  -- Two things keep the art crisp.  First, the resize is by an integer factor
  -- (setupFrames), so every destination pixel steps the same whole number of
  -- source pixels and every block stays square; a fractional factor is what
  -- makes pixel-art pixels come out uneven and eats diagonals.  Second, the
  -- sample takes the nearest source pixel rather than averaging the covered
  -- ones: a box filter turns the pack's art into a soft, muddy smear that reads
  -- as "blurry" next to the game's crisp pixel UI, whereas the nearest source
  -- pixel keeps hard edges.  A destination pixel whose nearest source pixel is
  -- transparent borrows the nearest OPAQUE pixel from the area it covers, so a
  -- one-pixel outline or antenna is never punched out by the sampling stride.

  local function beginBuild(sheet, imageData)
    local W, H = imageData:getDimensions()
    if H < 1 or W < 1 then return false end
    local count = math.max(1, math.floor((W + H / 2) / H))
    local fw = math.floor(W / count)
    if fw < 1 then return false end
    sheet.build = {
      id = imageData, W = W, H = H, count = count, fw = fw,
      box = boxFor(sheet.back, sheet.box),
      divisor = sheet.divisor, zoom = sheet.zoom or 1,
      scale = sheet.scale,
      maxH = sheet.maxH,
      fill = sheet.fill,
      natural = sheet.natural and true or false,
      back = sheet.back, stem = sheet.stem,
      phase = "scan", row = 0,
      x0 = fw, y0 = H, x1 = -1, y1 = -1,
    }
    sheet.frames = nil
    sheet.status = "building"
    return true
  end

  local function scanChunk(b, rows)
    local id, W, fw = b.id, b.W, b.fw
    local last = math.min(b.H - 1, b.row + rows - 1)
    local x0, y0, x1, y1 = b.x0, b.y0, b.x1, b.y1
    for y = b.row, last do
      for x = 0, W - 1 do
        local a = select(4, id:getPixel(x, y))
        if a and a > 0 then
          local lx = x - math.floor(x / fw) * fw
          if lx < x0 then x0 = lx end
          if lx > x1 then x1 = lx end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    b.row = last + 1
    b.x0, b.y0, b.x1, b.y1 = x0, y0, x1, y1
  end

  local function setupFrames(b)
    if b.x1 < b.x0 or b.y1 < b.y0 then return false end
    local cw, ch = b.x1 - b.x0 + 1, b.y1 - b.y0 + 1
    local box = b.box

    -- 0n. NATURAL mode (b.natural, set by the battle.mon_pic caller): bake the
    --     sheet at exactly b.scale x its own trimmed pixels and return an image
    --     that size -- no box, no padding. This is what lets a custom battle
    --     screen hand every species its OWN size (the pack's relative sizes,
    --     "normal size") instead of folding each one into the same slot-sized
    --     canvas. Only the screen's own headroom (b.maxH) can fold it back, so
    --     a sheet too tall for its band keeps its head on screen rather than
    --     being clipped. Because the canvas IS the content there is nowhere to
    --     put a metrics offset, so natural mode ignores the pack alignment.
    if b.natural then
      local scale = (b.scale and b.scale > 0) and b.scale or 1
      if b.maxH and ch * scale > b.maxH then scale = b.maxH / ch end
      if scale <= 0 then scale = 1 end
      local dw = math.max(1, round(cw * scale))
      local dh = math.max(1, round(ch * scale))
      b.cw, b.ch, b.dw, b.dh, b.scale = cw, ch, dw, dh, scale
      b.box = { w = dw, h = dh }
      b.ox, b.oy = 0, 0
      b.phase = "frames"
      b.frame = 0
      return true
    end

    -- Ways a sheet's own scale can be chosen, in priority order:
    --
    -- 0n. NATURAL (b.natural, set by the battle.mon_pic caller) -- handled
    --    above, before any box math: no box, just b.scale x the sheet's own
    --    trimmed pixels, folded only against b.maxH. This is what
    --    g9-Battle-Scene uses (see its drawSprite), so every species keeps
    --    the size its art gives it instead of being folded into a slot box.
    -- 0. An EXPLICIT field scale plus a BOX (b.scale + b.box, set by an older
    --    battle.mon_pic caller): every sheet is multiplied by exactly this
    --    factor, then folded to fit the box/headroom. Kept for any screen
    --    still asking for a box; g9-Battle-Scene now sends natural instead.
    -- 1. A custom battle screen's older UNIFORM divisor scale (b.divisor):
    --    every sheet baked at 1/divisor, the same whole-number step for both
    --    teams (kept for g2-Battle-Scene forks).
    -- 1b. b.fill: the boss's own slot asks a sheet to GROW past its native
    --    size to fill the box it was given. Ordinary slots never fill, so
    --    each species keeps its own relative size.
    -- 2. MAX DETAIL (mode 0): the largest scale that fits this sheet's own
    --    box, capped at 1:1 -- a sheet that already fits keeps every source
    --    pixel; one that does not is shrunk no further than it must be.
    -- 3. SMALL / NORMAL / BIG (modes 3 / 2 / 1): divide every sheet by one
    --    whole number, which keeps their relative sizes strictly
    --    proportional.
    -- 4. Modes 2/3 both fall back to fitting the box for a sheet they
    --    cannot fit, so nothing is ever clipped.
    --
    -- Per-axis fit bounds: the content may be as wide as the box and as tall
    -- as the box, but never taller than the headroom the battle screen
    -- reported for that slot (b.maxH = the pixels from its ground line to
    -- the field's own top), so a slot in a short band folds a tall sheet
    -- instead of letting its head be clipped.
    local fitW = box.w
    local fitH = b.maxH and math.min(box.h, b.maxH) or box.h
    local mode = spriteSizeMode()
    local scale
    if b.scale and b.scale > 0 then
      -- 0. An explicit field scale plus a box (an older battle.mon_pic
      --    caller): use it directly -- upscaling is intended -- then fold it
      --    back only as far as the box/headroom demand.
      scale = b.scale
      if cw * scale > fitW then scale = fitW / cw end
      if ch * scale > fitH then scale = fitH / ch end
    elseif b.fill then
      -- A slot that asks its sheet to FILL (the scene's boss slot, BOSS_MUL
      -- bands tall): use the largest scale that fits both axes, upscaling a
      -- small sheet as well as shrinking a large one. A non-integer ratio
      -- (the boss's +0.6 -> 1.6x) can't be an integer zoom step, so it is one
      -- nearest-neighbour resample straight to the box.
      scale = math.min(fitW / cw, fitH / ch)
    elseif b.divisor and b.divisor >= 1 then
      local zoom = b.zoom or 1
      scale = 1 / b.divisor
      if cw * scale * zoom > fitW then scale = fitW / (cw * zoom) end
      if ch * scale * zoom > fitH then scale = fitH / (ch * zoom) end
    elseif mode <= 0 then
      scale = math.min(1, fitW / cw, fitH / ch)
    else
      scale = 1 / mode
      if cw * scale > fitW then scale = fitW / cw end
      if ch * scale > fitH then scale = fitH / ch end
    end
    if scale > 1 and not (b.fill or (b.scale and b.scale > 0)) then scale = 1 end
    local dw = math.max(1, round(cw * scale))
    local dh = math.max(1, round(ch * scale))
    b.cw, b.ch, b.dw, b.dh = cw, ch, dw, dh
    b.scale = scale

    -- Pack alignment.  The pack anchors a sheet's UNTRIMMED frame bottom-centre
    -- at the base and shifts it by its SpeciesMetrics x,y * 2 screen px, while
    -- the frame itself is drawn at the pack's own render scale (2 front, 3
    -- back).  We trimmed the sheet to its content, so the padding those metrics
    -- take for granted is gone and has to be added back:
    --   * content bottom sits padBot rows above the frame bottom -> -padBot;
    --   * content mid-x sits (padL - padR) / 2 px off the frame mid-x, and our
    --     baseline centres the content, so - (padR - padL) / 2.
    -- `offset * 2 / renderScale` converts a metric to sheet pixels, which then
    -- shrinks with the sprite (so alignment stays proportional at any size).
    -- The result is clamped inside the box: the baked canvas IS the pic box, so
    -- anything outside it would be lost, and keeping a whole sprite (nudged to
    -- the nearest edge) reads better than clipping its head or feet.
    local baseX = (box.w - dw) / 2
    local baseY = box.h - dh
    local offX, offY = 0, 0
    if useMetrics() and METRICS then
      local m = METRICS[b.stem]
      if m then
        local div = b.back and BACK_SCALE or FRONT_SCALE
        local mx = b.back and m.bx or m.fx
        local my = b.back and m.by or m.fy
        local padL = b.x0
        local padR = b.fw - 1 - b.x1
        local padBot = (b.H - 1) - b.y1
        if mx then offX = (mx * 2) / div - (padR - padL) / 2 end
        if my then offY = (my * 2) / div - padBot end
      end
    end
    local ox = math.floor(baseX + offX * scale)
    local oy = math.floor(baseY + offY * scale)
    if ox < 0 then ox = 0 elseif ox > box.w - dw then ox = box.w - dw end
    if oy < 0 then oy = 0 elseif oy > box.h - dh then oy = box.h - dh end
    b.ox, b.oy = ox, oy
    b.phase = "frames"
    b.frame = 0
    return true
  end

  local function buildOneFrame(sheet)
    local b = sheet.build
    local id, fw = b.id, b.fw
    local cw, ch, dw, dh, ox, oy = b.cw, b.ch, b.dw, b.dh, b.ox, b.oy
    local box = b.box
    local f = b.frame
    local out = love.image.newImageData(box.w, box.h)
    local baseX = f * fw + b.x0
    -- One path for every sheet: the bake scales the content by `b.scale`, so
    -- destination pixel t covers source pixels [t*step, (t+1)*step) and takes
    -- the single source pixel nearest its centre.  `step` is fractional in MAX
    -- DETAIL, but the sample is still exactly one source pixel, so no colour is
    -- ever blended and edges stay hard (see the header note).  When the sampled
    -- pixel is transparent, borrow the nearest OPAQUE pixel the destination
    -- pixel covers, so a one-pixel outline or antenna is never punched out by
    -- the stride.
    local stepX = cw / dw
    local stepY = ch / dh
    for ty = 0, dh - 1 do
      local syn = b.y0 + math.min(ch - 1, math.floor((ty + 0.5) * stepY))
      local sy0 = b.y0 + math.floor(ty * stepY)
      local sy1 = b.y0 + math.min(ch, math.ceil((ty + 1) * stepY))
      for tx = 0, dw - 1 do
        local sxn = baseX + math.min(cw - 1, math.floor((tx + 0.5) * stepX))
        local cr, cg, cb, ca = id:getPixel(sxn, syn)
        if ca == 0 then
          local sx0 = baseX + math.floor(tx * stepX)
          local sx1 = baseX + math.min(cw, math.ceil((tx + 1) * stepX))
          local bestD = math.huge
          for sy = sy0, math.max(sy0, sy1 - 1) do
            for sx = sx0, math.max(sx0, sx1 - 1) do
              local pr, pg, pb, pa = id:getPixel(sx, sy)
              if pa and pa > 0 then
                local ddx, ddy = sx - sxn, sy - syn
                local dd = ddx * ddx + ddy * ddy
                if dd < bestD then bestD, cr, cg, cb, ca = dd, pr, pg, pb, pa end
              end
            end
          end
        end
        if ca and ca > 0 then
          out:setPixel(ox + tx, oy + ty, cr, cg, cb, ca)
        end
      end
    end
    local img = love.graphics.newImage(out)
    img:setFilter("nearest", "nearest")
    sheet.frames = sheet.frames or {}
    sheet.frames[f + 1] = img
    ourFrames[img] = true
    b.frame = f + 1
    return b.frame >= b.count
  end

  -- One bounded step.  Returns true when the sheet is no longer "building".
  local function advanceBuild(sheet)
    local b = sheet.build
    if not b then return true end
    if b.phase == "scan" then
      scanChunk(b, SCAN_ROWS)
      if b.row < b.H then return false end
      if not setupFrames(b) then
        finishFailed(sheet, "sheet has no opaque pixels")
        return true
      end
      return false
    end
    if buildOneFrame(sheet) then
      sheet.build = nil
      finishReady(sheet, sheet.how or "built")
      return true
    end
    return false
  end

  local function stepBuilds()
    if next(sheets) == nil then return end
    local deadline = now() + BUILD_BUDGET
    for _, sheet in pairs(sheets) do
      if sheet.status == "building" then
        while true do
          if advanceBuild(sheet) then break end
          if now() >= deadline then return end
        end
      end
    end
  end

  -- -- sheet source: the mod's OWN assets/ folder -------------------------

  -- Move a fresh sheet onto the "needs decoding" track.  assets/ is the only
  -- source.  A sheet that is not installed there is NOT latched as dead: it
  -- stays "new" with a retryAt, so a file copied into assets/ while the game is
  -- running is picked up on the next recheck.
  local function sheetStart(sheet)
    if sheet.status ~= "new" then return end
    if sheet.retryAt and frameCounter < sheet.retryAt then return end
    local folder = localFolder(sheet.back, sheet.shiny)
    local rel = "assets/" .. folder .. "/" .. sheet.stem .. ".png"
    local info = mod:info(rel)
    if info and info.type == "file" then
      sheet.rel = rel
      sheet.status = "local"
      return
    end
    if debugOn() and not sheet.warnedStem then
      sheet.warnedStem = true
      if DATA.stems[sheet.stem] then
        mod.log:info("g9-battle-sprites: %s is not in assets/%s/ -- vanilla "
          .. "pic in use", sheet.stem, folder)
      else
        mod.log:info("g9-battle-sprites: stem %s is not in this pack -- "
          .. "species uses the vanilla pic", sheet.stem)
      end
    end
    if not sheet.diagMissing then
      sheet.diagMissing = true
      diag.stats.missing = diag.stats.missing + 1
      diagPush("%s NO PNG", sheet.stem)
    end
    sheet.retryAt = frameCounter + RECHECK_FRAMES
  end

  local function evictIfNeeded()
    if readyCount <= MAX_SHEETS then return end
    local victim, oldest = nil, math.huge
    for _, sheet in pairs(sheets) do
      if sheet.status == "ready" and sheet.lastUsed
        and (frameCounter - sheet.lastUsed) > EVICT_AGE_FRAMES then
        if sheet.lastUsed < oldest then
          oldest = sheet.lastUsed
          victim = sheet
        end
      end
    end
    if victim then
      victim.frames = nil
      victim.status = "new"
      readyCount = readyCount - 1
    end
  end

  -- SPRITE SIZE / PACK ALIGNMENT changes cannot be seen in already-baked
  -- frames, so every sheet is requeued when either changes (a cheap re-fetch
  -- from the mod's own assets/, spread over frames by the build budget).  The
  -- signature starts nil and is seeded on the first poll so a fresh session
  -- never throws away work.
  local lastSizeSig = nil
  local function sizeSig()
    local d = spriteSizeMode()
    return (d > 0 and tostring(d) or "max") .. (useMetrics() and ":m" or ":n")
  end

  local function pollAll()
    frameCounter = frameCounter + 1
    diag.on = debugOn()
    if next(sheets) == nil then return end

    local sig = sizeSig()
    if lastSizeSig == nil then
      lastSizeSig = sig
    elseif sig ~= lastSizeSig then
      lastSizeSig = sig
      for _, sheet in pairs(sheets) do
        if sheet.status == "ready" then readyCount = readyCount - 1 end
        sheet.status = "new"
        sheet.frames = nil
        sheet.build = nil
      end
    end

    for _, sheet in pairs(sheets) do
      if sheet.status == "local" then
        local id, why = decodeSheet(sheet)
        if id then
          sheet.bytes = nil
          sheet.how = why
          if not beginBuild(sheet, id) then
            finishFailed(sheet, "cannot lay out sheet")
          end
        else
          finishFailed(sheet, "decode failed: " .. tostring(why))
        end
      end
    end

    stepBuilds()
    evictIfNeeded()
  end

  -- Returns (frames, pending). `frames` is the baked frame array once the sheet
  -- is ready (nil until then). `pending` is true while the sheet EXISTS in
  -- assets/ and is still on its way -- "local" (file found, not yet decoded)
  -- or "building" (decoding done, frames baking) -- i.e. exactly the window in
  -- which a caller must NOT fall back to the vanilla pic, because a real sheet
  -- is coming. A file that is missing ("new" after sheetStart) or unusable
  -- ("failed") reports pending = false, so vanilla is still drawn for a species
  -- this pack genuinely has no art for. Telling those two apart is what lets
  -- every wrap below suppress the vanilla pic DURING a build -- the native
  -- flash a trainer's send-out used to show for the mon's first frames --
  -- without ever hiding a mon the pack does not manage.
  --
  -- NB: getFrames has TWO return values, so call it in its own statement: the
  -- expression `stem and getFrames(...)` truncates the call to ONE value and
  -- `pending` is silently lost (which reads as "not pending" and lets the
  -- vanilla pic through). Every call site below guards the stem separately.
  local function getFrames(back, shiny, stem, boxOverride, divisor, zoom, maxH, fill, scale, natural)
    if not stem then return nil, false end
    local key = sheetKey(back, shiny, stem, boxOverride, divisor, zoom, maxH, fill, scale, natural)
    local sheet = sheets[key]
    if not sheet then
      sheet = { key = key, back = back, shiny = shiny, stem = stem,
                box = boxOverride, divisor = divisor, zoom = zoom,
                maxH = maxH, fill = fill, scale = scale,
                natural = natural and true or false, status = "new" }
      sheets[key] = sheet
    end
    if sheet.status == "new" then sheetStart(sheet) end
    if sheet.status == "ready" then
      sheet.lastUsed = frameCounter
      return sheet.frames, false
    end
    return nil, sheet.status == "local" or sheet.status == "building"
  end

  -- ---------------------------------------------------------------------------
  -- Animation clock
  -- ---------------------------------------------------------------------------
  local function frameIndex(count)
    if count < 1 then return 1 end
    if count == 1 or not animateOn() then return 1 end
    local i = math.floor(now() * fpsValue()) % count
    return i + 1
  end

  -- ---------------------------------------------------------------------------
  -- gen1 (Red/Blue/Yellow): drawPicsLayer substitution
  -- ---------------------------------------------------------------------------
  local managedSpecies = {}   -- species -> whether a frame Image is in use now

  local function ensureBattler(battler, back)
    if type(battler) ~= "table" then return end
    if not (wantEnabled() and type(battler.mon) == "table") then return end
    diag.stats.gen1 = diag.stats.gen1 + 1

    local stem, shiny = monStem(battler.mon)
    -- The call must sit in its own statement: `stem and getFrames(...)` would
    -- collapse it to a single value and drop the `pending` flag.
    local frames, pending = nil, false
    if stem then frames, pending = getFrames(back, shiny, stem) end
    -- Remember the vanilla pic BEFORE anything can blank it, so a later frame
    -- (or turning the mod off) can always put it back.
    if battler.__g9bsVanilla == nil and type(battler.sprite) == "string" then
      battler.__g9bsVanilla = battler.sprite
    end
    if not frames then
      if pending then
        -- The sheet is on its way. Draw NOTHING this frame rather than the
        -- vanilla pic: the sprite simply appears, already at its true size,
        -- the frame the bake finishes -- a native flash is never shown.
        battler.__g9bsFrame = nil
        battler.sprite = nil
        return
      end
      -- Not available at all (a species this pack has no sheet for, or one
      -- that failed to load): leave the vanilla pic exactly as it was.
      if battler.mon.species then managedSpecies[battler.mon.species] = false end
      if battler.__g9bsVanilla ~= nil then
        battler.sprite = battler.__g9bsVanilla
      end
      battler.__g9bsFrame = nil
      return
    end
    managedSpecies[battler.mon.species] = true
    local img = frames[frameIndex(#frames)]
    battler.__g9bsFrame = img
    battler.sprite = img
    if debugOn() and battler.__g9bsLogged ~= stem then
      battler.__g9bsLogged = stem
      diag.lastResolve = tostring(battler.mon.species) .. "->" .. stem
      diagPush("%s -> %s", battler.mon.species, stem)
      mod.log:info("g9-battle-sprites: %s -> %s%s (%s)",
        tostring(battler.mon.species), stem, shiny and " [shiny]" or "",
        back and "back" or "front")
    end
  end

  local function installGen1()
    local ok, BattleState = pcall(require, "src.battle.BattleState")
    if not (ok and type(BattleState) == "table"
      and type(BattleState.drawPicsLayer) == "function") then
      return false
    end
    if BattleState.__g9BattleSprites then return true end
    BattleState.__g9BattleSprites = true
    GEN = 1

    local vanillaLayer = BattleState.drawPicsLayer
    function BattleState:drawPicsLayer(...)
      if wantEnabled() then
        ensureBattler(self.enemy, false)
        ensureBattler(self.player, true)
      end
      return vanillaLayer(self, ...)
    end

    -- Our frames are pre-baked to the on-screen box, so the pic scale is 1
    -- (the vanilla gen1 back pic is a 32x32 image drawn at 2x).
    local vanillaScale = BattleState.resolveBattleScale
    if type(vanillaScale) == "function" then
      BattleState.resolveBattleScale = function(data, side, path, species, ...)
        if wantEnabled() and species and managedSpecies[species] then
          return 1
        end
        return vanillaScale(data, side, path, species, ...)
      end
    end

    -- Full-colour opt-out for the SGB/GBC zone post-pass: mark the rect our
    -- pic occupies so it is re-blitted unshaded (the engine's own trueColor
    -- mechanism, src/render/PaletteFX.markTrueColor).  x/y already carry the
    -- shake/slide offsets, so they must NOT be added again here.
    local vanillaBattlerPic = BattleState.drawBattlerPic
    if type(vanillaBattlerPic) == "function" then
      local PFX = nil
      local PFXok = false
      function BattleState:drawBattlerPic(battler, x, y, scale, shakeX, shakeY)
        local img = type(battler) == "table" and battler.__g9bsFrame
        if img and ourFrames[img] then
          if not PFXok then
            PFXok = true
            local okP, m = pcall(require, "src.render.PaletteFX")
            PFX = okP and m or nil
          end
          if PFX and PFX.markTrueColor then
            pcall(PFX.markTrueColor, x, y,
              img:getWidth() * (scale or 1), img:getHeight() * (scale or 1))
          end
        end
        return vanillaBattlerPic(self, battler, x, y, scale, shakeX, shakeY)
      end
    end
    return true
  end

  -- ---------------------------------------------------------------------------
  -- gen2 (Gold): BattleState:pic substitution
  -- ---------------------------------------------------------------------------
  local function installGen2()
    local ok, BattleState = pcall(require, "src.ui.gen2.BattleState")
    if not (ok and type(BattleState) == "table"
      and type(BattleState.pic) == "function") then
      return false
    end
    if BattleState.__g9BattleSprites then return true end
    BattleState.__g9BattleSprites = true
    GEN = 2

    local vanillaPic = BattleState.pic
    function BattleState:pic(mon, back)
      if wantEnabled() and type(mon) == "table" then
        diag.stats.pics = diag.stats.pics + 1
        local stem, shiny = monStem(mon)
        local frames, pending = nil, false
        if stem then frames, pending = getFrames(back and true or false, shiny, stem) end
        if frames then
          managedSpecies[mon.species] = true
          if debugOn() and mon.__g9bsLogged ~= stem then
            mon.__g9bsLogged = stem
            diag.lastResolve = tostring(mon.species) .. "->" .. stem
            diagPush("%s -> %s", mon.species, stem)
            mod.log:info("g9-battle-sprites: %s -> %s%s (%s)",
              tostring(mon.species), stem, shiny and " [shiny]" or "",
              back and "back" or "front")
          end
          return frames[frameIndex(#frames)], true, nil
        end
        if pending then
          -- The sheet is on its way: hand back NO image rather than the
          -- vanilla pic, so the native screen's own intro/send-out never
          -- flashes it while the pack bakes (drawPic returns early on a nil
          -- image, so nothing is drawn this frame).
          return nil, false
        end
        if mon.species then managedSpecies[mon.species] = false end
      end
      return vanillaPic(self, mon, back)
    end

    local vanillaPicScale = BattleState.picScale
    if type(vanillaPicScale) == "function" then
      function BattleState:picScale(path, mon, back)
        if wantEnabled() and type(mon) == "table"
          and managedSpecies[mon.species] then
          return 1
        end
        return vanillaPicScale(self, path, mon, back)
      end
    end

    -- Crystal draws its own animated front pics over the static one; for a
    -- species we manage, suppress that so our sheet wins the box.
    local vanillaFrontAnim = BattleState.frontAnimFrame
    if type(vanillaFrontAnim) == "function" then
      function BattleState:frontAnimFrame(mon)
        if wantEnabled() and type(mon) == "table"
          and managedSpecies[mon.species] then
          return nil
        end
        return vanillaFrontAnim(self, mon)
      end
    end
    return true
  end

  -- ---------------------------------------------------------------------------
  -- Pokedex front pic (gen1 DexEntryMenu, gen2 PokedexMenu)
  -- ---------------------------------------------------------------------------
  -- The battle seams above are not the only place a Pokemon's front pic is
  -- drawn, and the Pokedex never goes through them: gen1's DexEntryMenu asks
  -- src.pokemon.Sprites.path for the front pic's FILE PATH and loads it itself,
  -- and gen2's PokedexMenu does the same through Sprites.pic + Assets.image.
  -- The engine's own pokemon.sprite hook can only substitute that path string,
  -- so a sheet we bake in memory as an Image can never arrive through it -- the
  -- dex keeps loading the vanilla png while the battle screen shows our sheet.
  -- The fix is to wrap the dex screens' own pic accessors instead, exactly as
  -- the battle wraps do: hand them our current frame (already baked to the 7x7
  -- front box both dex screens draw into), trueColor = true, and fall through to
  -- vanilla when the pack has no sheet.  DEX SPRITES turns this off.
  --
  -- The dex has no live mon, so the sheet is chosen from the species id alone:
  -- the base front sheet, never the female or shiny variant (the entry shows the
  -- default artwork, as the cart does), and UNOWN is skipped because gen2's
  -- drawUnownPic has its own per-letter routine.
  local function dexFrame(species)
    if not (wantEnabled() and dexOn()) then return nil, false end
    if type(species) ~= "string" or species == "UNOWN" then return nil, false end
    local stem = resolveStem(species)
    if not stem then return nil, false end
    -- getFrames has two return values: keep the call in its own statement, or
    -- the assignment collapses it to one and drops `pending`.
    local frames, pending = nil, false
    frames, pending = getFrames(false, false, stem)
    if frames then return frames[frameIndex(#frames)], false end
    return nil, pending
  end

  local function installDexGen1()
    local ok, DexEntryMenu = pcall(require, "src.ui.DexEntryMenu")
    if not (ok and type(DexEntryMenu) == "table"
      and type(DexEntryMenu.draw) == "function") then
      return false
    end
    if DexEntryMenu.__g9BattleSpritesDex then return true end
    DexEntryMenu.__g9BattleSpritesDex = true
    local vanillaDraw = DexEntryMenu.draw
    -- DexEntryMenu.new resolves the vanilla pic into self.sprite once, and the
    -- entry page spends its first PIC_DELAY frames with that pic hidden (while
    -- the cry loads) -- exactly the window our first bake lands in.  Stash the
    -- vanilla sprite the first time we touch an instance so turning DEX SPRITES
    -- off, or a species with no sheet, can always put it back.
    function DexEntryMenu:draw(...)
      if not self.__g9bsDexStash then
        self.__g9bsDexStash = true
        self.__g9bsDexSprite = self.sprite
        self.__g9bsDexTrueColor = self.spriteTrueColor
      end
      if type(self.species) == "string" then
        local frame, pending = dexFrame(self.species)
        if frame then
          self.sprite = frame
          self.spriteTrueColor = true
        elseif pending then
          -- The sheet is on its way: draw no pic rather than flash vanilla.
          self.sprite = nil
          self.spriteTrueColor = false
        else
          self.sprite = self.__g9bsDexSprite
          self.spriteTrueColor = self.__g9bsDexTrueColor
        end
      else
        self.sprite = self.__g9bsDexSprite
        self.spriteTrueColor = self.__g9bsDexTrueColor
      end
      return vanillaDraw(self, ...)
    end
    mod.log:info("g9-battle-sprites: Pokedex front pic hooked (gen1)")
    return true
  end

  local function installDexGen2()
    local ok, PokedexMenu = pcall(require, "src.ui.gen2.PokedexMenu")
    if not (ok and type(PokedexMenu) == "table"
      and type(PokedexMenu.picFor) == "function") then
      return false
    end
    if PokedexMenu.__g9BattleSpritesDex then return true end
    PokedexMenu.__g9BattleSpritesDex = true
    local vanillaPicFor = PokedexMenu.picFor
    -- picFor(species) -> image, trueColor.  Its vanilla Image is cached by path
    -- in self.picCache; we bypass that cache and hand back a baked frame with
    -- trueColor = true so drawPic blits it raw (the same box the cart's 7x7
    -- block uses, so placement/padding are unchanged).  A pending sheet returns
    -- (nil, false) -- the "draw nothing this frame" signal the battle wraps use,
    -- so vanilla never flashes while the pack bakes.
    function PokedexMenu:picFor(species)
      local frame, pending = dexFrame(species)
      if frame then return frame, true end
      if pending then return nil, false end
      return vanillaPicFor(self, species)
    end
    mod.log:info("g9-battle-sprites: Pokedex front pic hooked (gen2)")
    return true
  end

  -- One boot is one generation, so install the matching dex arm only: the gen2
  -- module cannot even be required on a gen1 boot (RequireGuard throws).  The
  -- generation is passed in -- it is decided later, in the boot flow below.
  local function installDex(wantGen)
    if wantGen == 2 then
      if installDexGen2() then return "gen2" end
      if installDexGen1() then return "gen1" end
    elseif wantGen == 1 then
      if installDexGen1() then return "gen1" end
      if installDexGen2() then return "gen2" end
    else
      local g1 = installDexGen1()
      local g2 = installDexGen2()
      if g1 or g2 then
        return (g1 and "gen1" or "") .. (g2 and "+gen2" or "")
      end
    end
    return nil
  end

  -- ---------------------------------------------------------------------------
  -- Install + polling
  -- ---------------------------------------------------------------------------
  -- Which generation is actually booted (1 = Red/Blue/Yellow, 2 = Gold/Silver/
  -- Crystal).  src.core.GameVersion is a zero-require core module and stays
  -- loadable on both sides of the generation line, so it is the one answer
  -- that is the same whether the game is Gen 1 or Gen 2.  This matters for
  -- ASSET LOADING, not just for hooking: every frame is baked into the
  -- on-screen pic box, and the boxes genuinely differ -- gen1's back pic is
  -- pokered's 32x32 at 2x (64x64), gen2's is pokecrystal's 6x6 tile box at 1x
  -- (48x48) -- so a sheet baked for the wrong generation lands in the wrong
  -- box.  With no GameVersion (an engine older than this seam), fall back to
  -- probing both battle screens, which is how the mod answered before.
  local function currentGeneration()
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    if ok and type(GameVersion) == "table"
      and type(GameVersion.generation) == "function" then
      local gen = GameVersion.generation()
      if gen == 1 or gen == 2 then return gen end
    end
    return nil
  end

  -- A boot is exactly one generation, so install the matching arm and only
  -- that one.  Besides keeping GEN honest for the asset box above, this stops
  -- a Gold boot from wrapping Gen 1's src.battle.BattleState facade, which
  -- Gen2Compat serves for compatibility but which Gold's screen never calls.
  local gen = currentGeneration()
  local gen1, gen2
  if gen == 2 then
    gen2 = installGen2()
    if not gen2 then gen1 = installGen1() end
  elseif gen == 1 then
    gen1 = installGen1()
    if not gen1 then gen2 = installGen2() end
  else
    gen1 = installGen1()
    gen2 = installGen2()
  end
  local tag = gen and (gen == 2 and "gen2" or "gen1")
                or ((gen1 and "gen1" or "") .. (gen2 and "+gen2" or ""))
  if not (gen1 or gen2) then
    mod.log:warn("g9-battle-sprites: no supported battle screen found "
      .. "(wanted src.battle.BattleState or src.ui.gen2.BattleState) -- inactive")
    diag.inst = "INACTIVE"
    return
  end
  diag.inst = tag
  diag.gen = GEN

  -- The Pokedex draws its own front pic (see the dex block above): hook the
  -- matching dex screen now that the generation is known.
  local dexTag = installDex(gen)
  if dexTag then diag.dex = dexTag
  else
    mod.log:warn("g9-battle-sprites: no Pokedex screen found -- dex front "
      .. "pics left vanilla")
  end

  if not (mod.hooks and mod.hooks.wrap) then
    mod.log:error("g9-battle-sprites: mod.hooks:wrap is unavailable -- "
      .. "frame building cannot run, so the mod is inactive")
    return
  end
  mod.hooks:wrap("core.update", function(next, game, dt)
    pollAll()
    return next(game, dt)
  end)

  -- ---------------------------------------------------------------------------
  -- Layout/custom battle screens: the battle.mon_pic seam
  -- ---------------------------------------------------------------------------
  -- A custom battle screen (g9-Battle-Scene, and any g2-Battle-Scene fork) does
  -- NOT draw through BattleState:drawPicsLayer or BattleState:pic.  Its
  -- battle_screen resolves each battler's pic through the pokemon.sprite hook
  -- (for the path), loads that file, and then raises battle.mon_pic with the
  -- loaded Image so an animator can swap in the current frame on the way to the
  -- screen.  A mod that only wraps the two native screens is therefore
  -- invisible in every layout battle -- the sheets are on disk, the species
  -- resolve, and nothing on screen changes.  This wrap is that second seam: the
  -- same lookup, the same frame clock, and the same fall-through to the vanilla
  -- pic when the pack has no sheet for a species.  When the pack DOES have one
  -- but it is still baking it returns `false` instead -- the screen's signal to
  -- draw nothing this frame -- so the vanilla pic is never shown in the window
  -- between a mon appearing and its frames being ready (a trainer's send-out
  -- used to flash it there).  A screen that predates the token reads `false` as
  -- "no swap" and draws the vanilla pic, i.e. exactly the old behaviour.
  -- ctx = { species, side = "front"|"back", kind = "battle", mon, battler,
  --         battle, shiny, ... } -- mon is the live battler, as on Gen 2.
  mod.hooks:wrap("battle.mon_pic", function(next, img, ctx)
    if not wantEnabled() or type(ctx) ~= "table" then return next(img, ctx) end
    diag.stats.scene = diag.stats.scene + 1
    local mon = ctx.mon
    if type(mon) ~= "table" and type(ctx.battler) == "table" then
      mon = ctx.battler.mon
    end
    if type(mon) ~= "table" then return next(img, ctx) end
    local back = ctx.side == "back"
    local stem, shiny = monStem(mon)
    -- A layout battle screen names the exact pixel box it will draw the pic
    -- into (g9-Battle-Scene passes its own slot rect as ctx.box = {w,h}), plus
    -- the ONE scale the whole field is baked at (ctx.scale, sent by
    -- g9-Battle-Scene: the pack's NATURAL size x2 for every sprite, x2 x 1.6 =
    -- x3.2 for the boss -- the "+0.6", bosses only), the integer that screen
    -- will in turn scale the baked box by (ctx.zoom), and the pixels from that
    -- slot's ground line to the top of the field (ctx.maxH). Baking at that
    -- scale/size makes the screen's own draw a 1:1 blit instead of the
    -- fractional resample it would otherwise do -- which is where a screen on a
    -- different canvas eats the art a second time -- and the zoom is folded
    -- into the fit so an enlarged boss is never clipped by the box it is drawn
    -- out of. ctx.divisor (older forks) and ctx.fill (a sheet growing to fill
    -- its box) are still understood; ctx.scale supersedes them in
    -- g9-Battle-Scene.
    local boxOverride, divisor, zoom, maxH, fill, scale, natural
    if ctx.natural then
      -- NATURAL mode (g9-Battle-Scene): no box at all. The screen draws each
      -- sprite at its OWN size, so the mod returns an image that is exactly
      -- `scale` x the sheet's trimmed pixels (folded only to `maxH`), and the
      -- screen's blit is 1:1. This is what keeps every species' own relative
      -- size instead of folding them all into the same slot-sized box.
      natural = true
    elseif type(ctx.box) == "number" and ctx.box >= 8 then
      local n = round(ctx.box)
      boxOverride = { w = n, h = n }
    elseif type(ctx.box) == "table" then
      -- A non-square pixel box: the screen owns the exact slot rect (a grid
      -- column's width by its band's height), so both axes matter.
      local bw, bh = tonumber(ctx.box.w), tonumber(ctx.box.h)
      if bw and bh and bw >= 8 and bh >= 8 then
        boxOverride = { w = round(bw), h = round(bh) }
      end
    end
    -- The field's own scale multiplier (g9-Battle-Scene: x1 for every sprite,
    -- x1.6 for the boss). It is a straight multiplier, NOT a divisor: a value
    -- above 1 upscales on purpose. Clamp only to something sane.
    if type(ctx.scale) == "number" and ctx.scale > 0 then
      scale = ctx.scale
      if scale > 64 then scale = 64 end
    end
    if type(ctx.divisor) == "number" and ctx.divisor >= 1 then
      divisor = math.floor(ctx.divisor + 0.5)
      if divisor < 1 then divisor = 1 end
    end
    if type(ctx.zoom) == "number" and ctx.zoom > 1 then
      zoom = math.floor(ctx.zoom + 0.5)
    end
    -- The headroom a sheet may rise into before it is folded back (the
    -- screen sends the band's own height, so a huge sheet keeps its head
    -- inside its row instead of being clipped at the top of the field).
    if type(ctx.maxH) == "number" and ctx.maxH >= 8 then
      maxH = math.floor(ctx.maxH + 0.5)
    end
    -- May this sheet grow past its native size to fill the box? A shelf
    -- behaviour kept for older forks (g9-Battle-Scene now sends ctx.natural
    -- instead), true only for a boss slot.
    fill = ctx.fill and true or false
    local frames, pending = nil, false
    if stem then
      frames, pending = getFrames(back, shiny, stem, boxOverride, divisor, zoom, maxH, fill, scale, natural)
    end
    if frames then
      managedSpecies[mon.species] = true
      if debugOn() and mon.__g9bsLogged ~= stem then
        mon.__g9bsLogged = stem
        diag.lastResolve = tostring(mon.species) .. "->" .. stem
        diagPush("%s -> %s (scn)", mon.species, stem)
        mod.log:info("g9-battle-sprites: %s -> %s%s (%s, scene)",
          tostring(mon.species), stem, shiny and " [shiny]" or "",
          back and "back" or "front")
      end
      return frames[frameIndex(#frames)]
    end
    if pending then
      -- The sheet is on its way: `false` tells the calling screen to draw
      -- NOTHING this frame (g9-Battle-Scene's drawSprite returns early on it)
      -- instead of the vanilla pic, so a layout scene's trainer send-out never
      -- flashes native art while the pack bakes. A screen that does not know
      -- the token treats a false result as "no swap" and draws the vanilla pic
      -- exactly as before, so this is safe to ship ahead of any screen update.
      return false
    end
    if mon.species then managedSpecies[mon.species] = false end
    return next(img, ctx)
  end)

  -- A load-time census of the four drop-in asset folders.  This is the one line
  -- that answers "did the mod even see my sheets?" -- a zero here means the
  -- sheets are not where the mod reads, and no amount of species resolution
  -- will find anything.
  local function assetCount(folder)
    if type(mod.list) ~= "function" then return nil end
    local ok, names = pcall(mod.list, mod, "assets/" .. folder)
    if not ok or type(names) ~= "table" then return nil end
    local n = 0
    for _, name in ipairs(names) do
      if type(name) == "string" and name:sub(-4):lower() == ".png" then
        n = n + 1
      end
    end
    return n
  end
  local cFront, cFrontS = assetCount("front"), assetCount("front_shiny")
  local cBack, cBackS = assetCount("back"), assetCount("back_shiny")
  diag.census.front = cFront or 0
  diag.census.front_shiny = cFrontS or 0
  diag.census.back = cBack or 0
  diag.census.back_shiny = cBackS or 0
  if cFront ~= nil then
    mod.log:info("g9-battle-sprites: local assets -- front %d, front_shiny %d, "
      .. "back %d, back_shiny %d",
      cFront, cFrontS or 0, cBack or 0, cBackS or 0)
  end

  local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
  end

  -- -- the diagnostics panel ------------------------------------------------
  -- Everything below paints into the finished UI canvas.  Each diag* helper is
  -- pcall-guarded at the call site, so a diagnostics bug can never take down a
  -- frame -- the worst case is "no panel".

  local function diagBuildingCount()
    local n = 0
    for _, s in pairs(sheets) do
      if s.status == "building" then n = n + 1 end
    end
    return n
  end

  local function diagLines()
    local lines = {}
    local function add(s)
      if s == nil then return end
      s = tostring(s)
      if #s > DIAG_MAX_CHARS then s = s:sub(1, DIAG_MAX_CHARS) end
      lines[#lines + 1] = s
    end
    local c = diag.census
    local total = c.front + c.front_shiny + c.back + c.back_shiny
    add("g9-battle-sprites DIAG")
    if total == 0 then
      add("!! NO PNG IN assets/ !!")
      add("run download_assets.py")
    elseif diag.stats.ready == 0 then
      add("PNG found, 0 sheets ready")
    end
    add(("gen%s  %s"):format(tostring(diag.gen), diag.inst))
    add(("ready %d build %d fail %d"):format(
      diag.stats.ready, diagBuildingCount(), diag.stats.failed))
    add(("assets F%d S%d B%d BS%d"):format(
      c.front, c.front_shiny, c.back, c.back_shiny))
    add(("pics %d scene %d gen1 %d"):format(
      diag.stats.pics, diag.stats.scene, diag.stats.gen1))
    if diag.stats.missing > 0 then
      add(("missing sheets %d"):format(diag.stats.missing))
    end
    if diag.lastResolve then add("last " .. diag.lastResolve) end
    if diag.lastFail then
      add("FAIL " .. diag.lastFail)
      local why = tostring(diag.lastFailWhy or "")
      for i = 1, DIAG_MAX_REASON_LINES do
        local start = (i - 1) * DIAG_MAX_CHARS + 1
        if start > #why then break end
        add(why:sub(start, start + DIAG_MAX_CHARS - 1))
      end
    end
    for i = 1, math.min(4, #diag.events) do add(diag.events[i]) end
    return lines
  end

  -- Paint the panel into `canvas` (the UI canvas handed to render.compose).
  -- White box + black text: whichever way the SGB/GBC zone pass maps the UI
  -- palette, the lightest and darkest entries stay two very different shades,
  -- so the text stays legible.  Every graphics state we touch is saved and
  -- restored so the composite that follows is byte-identical to vanilla.
  local function diagDrawCanvas(canvas)
    local g = love and love.graphics
    if not (g and canvas and g.rectangle and g.print) then return end
    local font, fh = diagGetFont()
    if not font then return end
    local lines = diagLines()
    local w = (canvas.getWidth and canvas:getWidth()) or 160
    local cap = (canvas.getHeight and canvas:getHeight()) or 144
    local h = 4 + #lines * fh
    if h > cap then h = cap end
    g.push()
    g.origin()
    local prevCanvas = g.getCanvas and g.getCanvas()
    local prevFont = g.getFont and g.getFont()
    local prevShader = g.getShader and g.getShader()
    local prevBlend = g.getBlendMode and g.getBlendMode()
    local sx, sy, sw, sh = g.getScissor and g.getScissor()
    g.setCanvas(canvas)
    if g.setScissor then g.setScissor() end
    if g.setBlendMode then g.setBlendMode("alpha") end
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 0, 0, w, h)
    g.setColor(0, 0, 0, 1)
    g.setFont(font)
    for i = 1, #lines do
      g.print(lines[i], 2, 2 + (i - 1) * fh)
    end
    g.setColor(1, 1, 1, 1)
    if prevFont then g.setFont(prevFont) else g.setFont() end
    if prevCanvas then g.setCanvas(prevCanvas) else g.setCanvas() end
    if g.setShader then g.setShader(prevShader) end
    if prevBlend and g.setBlendMode then g.setBlendMode(prevBlend) end
    if sx and g.setScissor then g.setScissor(sx, sy, sw, sh) end
    g.pop()
  end

  -- Only registered when the panel is compiled in.  render.compose's `next` is
  -- the engine's no-op returning false (it only decides who owns the window),
  -- so returning the next value leaves the normal composite untouched.
  if DEBUG_PANEL_ENABLED then
    mod.hooks:wrap("render.compose", function(next, renderer, ctx)
      if diag.on and type(ctx) == "table" and ctx.uiCanvas
        and diag.lastFrame ~= frameCounter then
        diag.lastFrame = frameCounter
        pcall(diagDrawCanvas, ctx.uiCanvas)
      end
      return next(renderer, ctx)
    end)
  end

  mod.log:info("g9-battle-sprites: loaded (%s) -- %d species mapped, %d stems, "
    .. "%d female variants; %d local sheets",
    tag,
    count(DATA.species), count(DATA.stems), count(DATA.female),
    (cFront or 0) + (cFrontS or 0) + (cBack or 0) + (cBackS or 0))
end
