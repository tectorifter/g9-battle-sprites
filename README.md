# g9-battle-sprites

True-colour, **frame-animated battle sprites** for the whole national dex,
loaded from the **DBK animated "solo sprites"** pack
(`la-base-de-sky / la-base-de-sky-plugins / sprites-animados-dbk-solo-sprites`,
folders `Graphics/Pokemon/{Front, Front shiny, Back, Back shiny}`).

It replaces the enemy **front** pic and the player **back** pic in battle with
the matching animated sheet, and the **front pic on the Pokedex** entry page
(gen1 and gen2). Everything else — the send-out grow, faint slide, blink/squish,
the SGB/GBC palette machinery — keeps working, because the mod hands the
engine's own draw path a normal LÖVE `Image` per frame.

## The one decision that shapes everything: use the sheet directly

Every file in the pack is **one PNG per Pokemon**, laid out as a single
horizontal strip of frames that butt edge to edge, left to right, where
`frame height == sheet height` and
`frame count == round(width / height)`.

So there is **no splitting step and no per-Pokemon subfolders**. The mod:

1. decodes the sheet once — through up to three fallback routes, since a mod
   cannot assume any one image decoder exists on a given build: the engine's own
   asset path first (`love.image.newImageData(mod.assets:path(...))`, what every
   image-loading mod uses), then the raw bytes via a `FileData`, then a
   `love.graphics.newImage(path):getData()` detour,
2. crops each frame out of it **in memory**,
3. resamples that frame **once** to the on-screen pic box — at the largest
   scale that box allows (see [Sizes and alignment](#sizes-and-alignment)) — and
   offsets it by the pack's own metrics, then caches the result.

The raw PNG stays a single file under `assets/<type>/<STEM>.png`. You copy one
`.png` per Pokemon — never a folder of frames.

## Lookup (for each battle pic)

1. **national dex species id** (+ gender + shiny) → a **DBK stem** via
   `data/dbk_data.lua`.
2. `<mod>/assets/<front|front_shiny|back|back_shiny>/<STEM>.png` — your local
   copy. **This is the only source: the mod does not touch the network.**

Stems/ids are matched exactly; a lookup that cannot resolve falls through to the
vanilla pic, so a missing sheet is never an error on screen. A sheet that
resolves nowhere is **not** latched as dead — it is retried every ~15 s, so a
file copied into `assets/` while the game is running is picked up on the next
recheck without a restart.

Fill `assets/` by hand, or with the helper script that ships in the mod (see
[Getting the sheets](#getting-the-sheets-the-helper-script)).

## Form conventions (the part that needed care)

The national dex gives every *mechanically or sprite-distinct* form its own
species id, and `data/dbk_data.lua` maps each id to **the pack's own stem**.
Examples baked into the data:

| national dex id | DBK stem | What it is |
|---|---|---|
| `CHARIZARD_MEGA_X` | `CHARIZARD_1` | Mega Charizard X |
| `CHARIZARD_MEGA_Y` | `CHARIZARD_2` | Mega Charizard Y |
| `CHARIZARD_GMAX` | `CHARIZARD_3` | Gigantamax Charizard |
| `RAICHU_ALOLA` | `RAICHU_1` | Alolan Raichu |
| `SNEASEL_HISUI` | `SNEASEL_1` | Hisuian Sneasel |
| `ALCREMIE_GMAX` | `ALCREMIE_63` | Gigantamax Alcremie |
| `MEOWSTIC_FEMALE` | `MEOWSTIC_1` | Female Meowstic |
| `BASCULEGION_FEMALE` | `BASCULEGION_1` | Female Basculegion |
| `OINKOLOGNE_FEMALE` | `OINKOLOGNE_1` | Female Oinkologne |

**Ignored forms.** Cosmetic-only forms the pack has no sheet for (e.g. every
Alcremie flavour that is not base or gigantamax) are *not* mapped; they fall
back to the base species sheet. That matches the pack's own intent — base
`ALCREMIE`, gmax `ALCREMIE_63`, everything else irrelevant.

**Base fallback.** If an id is not mapped at all (totems, story-only modes like
`PIKACHU_STARTER`, `KORAIDON`/`MIRAIDON` modes), the mod walks the `_SUFFIX`
chain off the id until it finds a mapped stem — e.g.
`KOMMO_O_TOTEM → KOMMO_O → KOMMOO` (note: the pack **drops underscores** in
species names: `MR_MIME → MRMIME`, `NIDORAN_F → NIDORANfE`,
`NIDORAN_M → NIDORANmA`).

**Female art.** Some Pokemon have a distinct `_female` sheet next to their base
one (`ABOMASNOW_female`, `SNEASEL_1_female`, `EEVEE_1_female`, ...). The
`female` set in `data/dbk_data.lua` lists the ones that exist; a female mon uses
`<stem>_female` when the set contains the **base** stem and FEMALE ART is on.

**Shiny art** uses the `*_shiny` folders when SHINY ART is on.

## Sizes and alignment

The pack draws every sheet at **one uniform scale** (Essentials/DBK's
`FRONT_BATTLER_SPRITE_SCALE = 2`, `BACK_BATTLER_SPRITE_SCALE = 3`), so a bigger
Pokemon is simply a **taller sheet**: relative sizes come straight from the
sheet's own pixel height.

**SPRITE SIZE** decides how much of a sheet's own resolution reaches the
screen. `MAX DETAIL` (0, the default) sizes each sheet on its own: a sheet that
already fits its picture box is kept **1:1** (a small Pokemon keeps every source
pixel), and a sheet that does not is shrunk **no further than it must be**, so a
big Pokemon fills the box instead of sitting at half size inside it. Relative
size is still honoured for everything that fits; sheets taller than the box all
land on the box, which is as large as the screen can show them anyway. `SMALL`
(3), `NORMAL` (2) and `BIG` (1) instead divide every sheet by that one whole
number, which keeps their relative sizes strictly proportional. Whatever the
mode, a sheet too big to fit the box is scaled back to it, so nothing is ever
clipped.

**PACK ALIGNMENT** then places each sprite with the pack's own `SpeciesMetrics`
numbers, shipped in `data/dbk_metrics.lua` (`FrontSprite` / `BackSprite` x,y per
stem). The pack anchors a sheet's *untrimmed* frame bottom-centre at a fixed
base and shifts it by those values × 2 screen px. We trim each sheet to its
content first, so the padding the metrics assume is gone and is put back with
the same arithmetic Essentials/DBK use:

* the content bottom sits `padBot` rows above the frame bottom → `- padBot`;
* the content mid-x sits `(padL - padR) / 2` px off the frame mid-x, and our
  baseline centres the content → `- (padR - padL) / 2`.

`offset × 2 ÷ renderScale` converts a metric to sheet pixels, and the result
scales with the sprite, so alignment stays proportional at any SPRITE SIZE. The
final position is clamped inside the box, so nothing is ever baked off-canvas.

**Baking always samples the nearest source pixel, never an average.** Each
destination pixel takes the single source pixel nearest its own centre. That
holds at a fractional scale too: a fractional *step* simply means neighbouring
destination pixels advance by different whole numbers of source pixels, so
every block stays square and every pixel keeps an exact colour from the pack's
palette. Hard edges and true colours are the whole point — and a box/area filter
is the one thing that destroys both, blending neighbouring colours into new ones
and reading as a soft, muddy smear beside the game's crisp pixel UI. (An earlier
build area-averaged at a fractional scale and produced exactly that: the
"blurry sprites" complaint.) A destination pixel whose nearest source pixel is
transparent borrows the nearest opaque pixel it covers, so a one-pixel outline
or antenna is never punched out by the sampling stride.

Changing either option requeues every sheet, so the new setting shows up in the
next battle with no restart.

## Mod Manager options

| Row | Default | Meaning |
|---|---|---|
| **BATTLE SPRITES** | on | Master switch. Off → every pic is exactly what the game would draw. |
| **ANIMATE** | on | Play the sheet left-to-right as a loop. Off → frame 1 only. |
| **SPRITE SPEED** | NORMAL (12 fps) | Playback speed: SLOW 6 / NORMAL 12 / FAST 18 / VERY FAST 24. |
| **SHINY ART** | on | Use `*_shiny` sheets for shiny mons. |
| **FEMALE ART** | on | Use `_female` sheets where the pack has one. |
| **SPRITE SIZE** | MAX DETAIL (0) | How much of each sheet's own resolution reaches the screen: MAX DETAIL 0 = the largest scale that fits each sheet's box (1:1 wherever it fits), SMALL 3 / NORMAL 2 / BIG 1 = divide every sheet by 3/2/1 for strictly proportional sizes. See [Sizes and alignment](#sizes-and-alignment). |
| **PACK ALIGNMENT** | on | Offset each sprite by the pack's own SpeciesMetrics values. Off → every sprite bottom-centre in its box. |
| **DEX SPRITES** | on | Show the same sheet on the Pokedex front pic (first frame when ANIMATE is off). Off → the Pokedex keeps the game's own pic. |

Rows are declared in `options.lua` (so a disabled mod still shows them) and
mirrored in `main.lua`, which is what gives the values their defaults.

## Diagnostics (if sprites don't appear)

The on-screen diagnostics panel is **disabled in shipped builds** (there is no
option row for it, and no `render.compose` hook is installed) because it was
never meant for players to switch on. What it showed — and what is still
written to the game log (stdout) — is:

* `local assets -- front N, front_shiny N, back N, back_shiny N` at load. *All
  zeros* means the sheets are not where the mod expects — run
  `assets/download_assets.py`.
* `... is not in assets/<type>/ -- vanilla pic in use` at **info** = a species
  resolved to a stem, but that sheet file is not installed.
* `... could not be used (...)` at **warn** = a sheet is present but failed to
  decode (corrupt, partial, or an unsupported PNG), so the mod falls back to the
  vanilla pic. The parenthesised text names the decode route(s) that were tried
  and why they failed.

Sheets are decoded through up to three routes (the mod's own asset path first,
then the raw bytes, then a graphics detour); if every route fails, the first
failing reason is logged so a bad file or an unsupported PNG can be told apart
from a missing one.

If the panel is ever needed again, it is still in `main.lua`, dormant behind
`local DEBUG_PANEL_ENABLED = false` — flip the constant and it paints a white
box with black text at the top-left of the finished UI canvas (the engine's
developer console is Gen 1 only, and Gold implements it not at all).

## The `assets/` folders

```
assets/
  front/        front (enemy) sheets      e.g. ABOMASNOW.png
  front_shiny/  front shiny sheets
  back/         back (player) sheets
  back_shiny/   back shiny sheets
```

File name = the pack stem. One horizontal strip per file; never split it.
Each folder has its own README with the details. Anything you don't install
there simply uses the game's vanilla pic.

The mod **ships no artwork** — the sheets are the DBK pack author's
(`la-base-de-sky`), supplied by you.

## How it hooks the engine

Which generation is booted is read from `src.core.GameVersion.generation()`
(`1` = Red/Blue/Yellow, `2` = Gold/Silver/Crystal) and **only that
generation's battle screen is wrapped**. The generation also picks the asset
**box** a sheet is baked into — a back pic is 64×64 on gen1 and 48×48 on gen2 —
so sheets always land in the box of the game actually running. If the engine
has no `GameVersion` (older than this seam), the mod falls back to probing both
screens, as before.

* **gen1** (`src.battle.BattleState`): wraps `drawPicsLayer` to set each managed
  battler's `sprite` to its current frame `Image` right before the vanilla draw,
  and forces `resolveBattleScale → 1` for managed species (our frames are already
  baked to the box size). `drawBattlerPic` is wrapped only to mark the pic rect
  **true-colour** (`PaletteFX.markTrueColor`), so the SGB/GBC zone post-pass
  re-blits it unshaded.
* **gen2** (`src.ui.gen2.BattleState`): wraps `pic(mon, back)` to return the
  current frame `Image` with `trueColor = true` (Gold draws a trueColor pic
  raw), and `picScale → 1` for managed species.
* **The Pokedex** (`src.ui.DexEntryMenu` on gen1, `src.ui.gen2.PokedexMenu` on
  gen2): the dex does **not** draw through either battle screen — it asks
  `pokemon.sprite` / `Sprites.pic` for the front pic's **path** and loads that
  file itself, so the engine's `pokemon.sprite` hook (which can only swap the
  path string) can never hand it a frame baked in memory. The mod therefore
  wraps the dex screens' own pic accessors directly: gen1's `DexEntryMenu:draw`
  stashes `self.sprite`/`self.spriteTrueColor`, swaps in the current frame with
  `spriteTrueColor = true`, and restores vanilla on the way out; gen2's
  `PokedexMenu:picFor(species)` returns `frame, true`. The dex resolves the base
  front sheet from the species id (never the female/shiny variant, since the
  entry shows the default artwork), skips `UNOWN` (gen2's `drawUnownPic` has its
  own per-letter routine), and uses the same 56×56 front box both screens draw
  into. **DEX SPRITES** turns it off.
* **Custom battle scenes** (the `battle.mon_pic` seam): wraps `battle.mon_pic`
  to return the current frame `Image` for managed species. The native screens
  above only cover the vanilla renderers — a replacement scene such as
  `g9-Battle-Scene` draws its own pics, resolving each one through the
  `pokemon.sprite` hook and then `battle.mon_pic`. Without this wrap the mod is
  invisible in every scene battle. It passes `(img, ctx)` through untouched for
  unmanaged species, so it composes with other pic mods. A scene may put
  `box = <pixels>` in `ctx` to name the square it will draw the pic into, or
  `box = { w, h }` to name a non-square slot rect; the
  mod then caches a second set of frames baked to exactly that size, so the
  scene's own draw is a 1:1 blit instead of a fractional resample — which is
  what stops a scene on a different canvas from eating the art a second time.
  (`g9-Battle-Scene` passes each sprite's own slot rect.) The same `ctx` may
  also carry `scale`, the field's own size MULTIPLIER applied to every sheet
  (`g9-Battle-Scene` sends the pack's NATURAL 1:1 size for every sprite, and
  1 x 1.6 = x1.6 for its bossFight boss — the "+0.6", bosses only — so a wild
  Pokemon and the same species on your team read identically and each species
  keeps its true relative size); `natural = true` is the mode it now sends
  instead of a slot box, so a sheet is baked at exactly `scale` x its own
  trimmed pixels (no folding into a shared box, which used to make every
  species the same height and width) and only `maxH` can fold it; an older
  `divisor` (one whole-number field scale, applied as 1/divisor) is still
  honoured for g2-Battle-Scene forks. `zoom` is the
  integer the scene will scale the baked box by on its way to the screen, and
  `fill` asks this slot's sheet to GROW to fill its box (a nearest-neighbour
  resample straight to the box, for a screen with no explicit `scale`).
  Finally `maxH` names the pixels from that slot's ground line up to the
  top of the field: a sheet that would rise past it is folded back
  to fit, so nothing is ever clipped at the top of the scene. A scene that sends
  none of these still works, just with the mod's native-box frames.
* **While a sheet is still baking** (its file exists in `assets/`, but it has not
  been decoded/baked yet — the sheet's `"local"`/`"building"` window) the mod
  reports "pending" rather than "no sheet", and each seam suppresses the vanilla
  pic for that window: gen1 blanks `battler.sprite` (the engine skips a nil
  sprite), gen2 returns a nil pic (the engine's `drawPic` early-returns), and the
  `battle.mon_pic` seam returns **`false`**. A scene that knows the token — such
  as `g9-Battle-Scene`, which starts the bake during the pokeball's flight — draws
  NOTHING for that frame instead of the vanilla pic, so a trainer's send-out never
  flashes native art before the pack's frames are ready. A species with no sheet
  at all (or one that fails to decode) still reports "not pending" and falls
  through to the vanilla pic exactly as before, so the token is never a permanent
  blackout. A scene that predates the token reads `false` as "no swap" and draws
  the vanilla pic, i.e. the old behaviour.
* Frame building happens in a `core.update` hook — **never** inside a draw call.
  Resolved sheets are kept in a bounded LRU (64) whose frame `Image`s are dropped
  oldest-first while the raw bytes stay.
* The on-screen **diagnostics panel** (a `render.compose` wrap) is compiled out
  in shipped builds — see [Diagnostics](#diagnostics-if-sprites-dont-appear).

Pic boxes: gen1 front **56×56**, gen1 back **64×64** (pokered's 32×32 pic at 2×),
gen2 front **56×56**, gen2 back **48×48**. Every sheet is baked into that box at
the largest scale it allows and offset by the pack's metrics (see
[Sizes and alignment](#sizes-and-alignment)), so the art keeps as much of its
own resolution as the box can hold and feet placement matches the pack.

## Permissions / dependencies

```json
"permissions": ["engine_internals"]
```

* `engine_internals` — it requires the engine's BattleState modules and PaletteFX.
  No `network` permission: the mod reads only its own `assets/` folder.

`optional_dependencies`: `national_dex` (species-id source) and
`g9-battle-engine` (the battle engine it decorates). Neither is required;
the mod no-ops cleanly if it finds no supported battle screen.

## Install

Download the zip from the studio's **Mod exports** row
(`⬇ g9-battle-sprites .zip`) and unzip it into the game's `mods/` folder so the
tree is `mods/g9-battle-sprites/{manifest.json,main.lua,...}`.

### Getting the sheets (the helper script)

The mod ships no artwork and never touches the network, so **you fill `assets/`
yourself**. The helper that ships in the mod fetches the DBK pack from GitLab
once, on your machine, and writes it into the exact layout the mod reads:

```
cd mods/g9-battle-sprites/assets
python3 download_assets.py            # everything missing
python3 download_assets.py --force    # re-fetch everything
python3 download_assets.py --only front,back
python3 download_assets.py --dry-run  # show the plan, fetch nothing
```

It reads `../data/dbk_data.lua` for the stem list and writes each sheet into
`front/`, `front_shiny/`, `back/`, `back_shiny/` next to itself. Standard
library only, resumable, safe to re-run. Run it whenever you want to add sheets
— the running game itself downloads nothing.

## Files

| File | Role |
|---|---|
| `manifest.json` | Mod metadata; permissions, games, options schema |
| `main.lua` | The mod: stem resolution, assets/ loading, frame baking, gen1/gen2 battle hooks, gen1/gen2 Pokedex hooks |
| `options.lua` | Mod Manager rows (mirrored in `main.lua`) |
| `data/dbk_data.lua` | Generated: species→stem, stem existence, female stems |
| `data/dbk_metrics.lua` | Generated: per-stem FrontSprite/BackSprite alignment offsets from the pack's SpeciesMetrics files |
| `mod.card` | Human-readable summary shown by launchers |
| `assets/*/README.md` | Notes for the four drop-in asset folders |
| `assets/download_assets.py` | Helper (run by you, not the game) that fills `assets/` from the DBK mirror |
| `files.json` | Build manifest for the studio's export button (not shipped) |
| `README.md` | This document |

## Regenerating the data

`data/dbk_data.lua` is generated by joining the national dex species table to
the DBK pack's file listing. The generator script is `tools/rebuild_dbk_data.mjs`
(kept with the studio source, **not** shipped in the mod zip — see `files.json`).
It fetches all four pack folders live from GitLab and combines them with
`tools/mapping.json` (the reviewed national-dex join — species id → stem, which
carries the form decisions). When the pack gains sheets, run:

```
node tools/rebuild_dbk_data.mjs          # rewrites ../data/dbk_data.lua
```

The output is byte-stable for a given pack + mapping. A species whose stem is
not actually present in the pack is dropped, so the Lua never points at a
missing file.

`data/dbk_metrics.lua` is generated from the pack's own five SpeciesMetrics PBS
files (`pokemon_metrics.txt`, `pokemon_metrics_forms.txt`,
`pokemon_metrics_gmax.txt`, `pokemon_metrics_Gen_9_Pack.txt`,
`pokemon_metrics_female.txt`). Point the script at a folder holding those files
(or pass them explicitly):

```
node tools/rebuild_dbk_metrics.mjs /path/to/metrics-dir   # rewrites ../data/dbk_metrics.lua
```

It keys each section by the same PNG stem the sheet is stored under
(`[SPECIES,form,female]` → `SPECIES_form_female`, dropping empty parts) and drops
any stem the pack has no PNG for.
