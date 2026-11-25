# Last Ink: Art Style Bible

Every art pass asset is made and judged against this page. It exists because assets generated one by one, each
looking fine on its own, did not fit together (Phase 3 review, 2026-11-19). The fix: one approved target scene,
one fixed palette, and generation that is always anchored to them.

## The target scene

![Target plaza](style/target_plaza.png)

`docs/style/target_plaza.png` (320 x 180, one game screen at 1:1) was approved by Ojon on 2026-11-19. It is the
reference for the whole game: when an asset and the target disagree, the target wins. Crops of it are the
generation references in `docs/style/` (`ref_building.png`, `ref_props.png`, `ref_grass.png`, `ref_cobble.png`).

## Rules

| Rule | Value |
|---|---|
| **Camera** | Top-down three-quarter, like SNES action RPGs. One camera for everything: high and tilted like `docs/style/target_town.png` (the scene the look was modelled on), vertical walls stay vertical, roofs seen from above. Buildings may face straight on or be turned slightly with the door to the south-east or south-west, so the town has a shape: the facade stays the main face and the side wall recedes steeply. Never a 45 degree corner view where both walls slope equally (that reads isometric). Props face straight on. Characters use PixelLab's `high top-down` (Ash is the reference). |
| **Scale** | 16 px tiles. Heroes, NPCs and small enemies on a 32 px canvas (about 2 tiles tall). A 5x5-tile building plot holds an 80 x 80 sprite. |
| **Light** | From the top left. Shadows fall to the bottom right. |
| **Outline** | Ink black `#12141f` outer outline on characters, enemies and objects; inner edges use the darkest shade of the local colour. Ground tiles have no outline. |
| **Shading** | Cel shading, 3 to 4 shades per material, no dithering on objects, no anti-aliasing, hard alpha. |
| **Palette** | The 38 colours of `tools/style_palette.hex` and nothing else (below). |
| **Mood** | Muted and a little gloomy: charcoal, bone, rust, moss, slate. Saturated colour is saved for accents, light (candles, lamps, Ink glow) and character signatures. |

## Palette

![Palette](style/palette.png)

`tools/style_palette.hex`, in ramps: ink and night slate, stone (4), wood (5), plaster and bone (4), foliage (6),
slate roof (3), clay roof (3), skin (3), then the accents (Ash ink-blue, Ink glow, Bran rust, Daro brass,
lamplight, Gristle poison green, crimson). **Paper white `#f3eee2` is not in it**: only the Blank uses it, and the
Blank's erasure of the world is a code effect drawn over the art, so no "erased" versions are generated.

## Materials

The town and the countryside are built from one small vocabulary, so different buildings read as one place:
- Walls: dark timber frame with bone plaster, or warm grey stone, or plain planks for poor buildings.
- Roofs: slate blue or dark red clay. Nothing else.
- Ground: dark mossy grass, mossy grey cobbles in towns, packed brown dirt paths in the country.
- Metal: dark iron (stone dark and ink shades), brass only as an accent.

## How assets are generated

1. **Buildings and props:** PixelLab `POST /v2/generate-image-v2` (Pro, about $0.08 per call, several options per
   call) with a crop of the target as `style_image`, `style_options.color_palette = false`, and
   `target_palette` = the 38 colours. Prompts start with the camera sentence:
   *"Front view pixel art building sprite for a top-down RPG, flat front facade facing the viewer straight on, roof
   seen from slightly above, no side walls, no isometric angle: ..."* (props: *"Single pixel art game prop sprite
   for a top-down RPG, seen from slightly above and straight on from the front: ..."*).
2. **Building levels:** level 3 first; levels 1 and 2 use the chosen level 3 as a `reference_image` and ask for a
   humbler version, so material and roof stay the same.
3. **Ground:** `create-tileset` with the target's grass and cobble crops as lower and upper references and the
   palette as `color_image`; then snapped.
4. **Characters:** `create-character-v3` as before (Ash's settings), then snapped to the palette on import.
5. **Every asset** goes through `tools/palette_lock.py` `snap()` before it enters the game (hard alpha, Ink
   outline, 38 colours).

## How assets are picked

- Judge candidates **in place**: on the game ground at game zoom, next to Ash and the target's neighbours, never on
  their own on a plain background.
- Pick for fit with the set, not for the most impressive single image.
- Reject anything off-angle (diagonal, isometric, a ground patch under it), off-scale or off-palette.
- Each phase PR shows an in-game screenshot beside the target.

## Sitting in the world

Generated sprites come out front-on and evenly lit, so on their own they look pasted onto the ground. Code
and one offline pass make them belong:

- **Depth pass** (`tools/depth_pass.py`): eave shadow under every roof, contact shade along the base,
  right-side shade (light from the top left). Palette steps only: each darkening is one step down the
  material's own ramp. Originals stay in `tools/art_src/`, so rerunning never darkens twice.
- **Variants** (same tool): roof recolours (stone to clay or blue slate), moss on roofs, wood and plaster
  shifted a step, written as `<kind>_v1.png`, `_v2`... `scripts/prop.gd` picks one per placement from its
  map position, so a row of houses never shows the same sprite twice in a row. No flips: they would break
  the top-left light.
- **Cast shadows** (`Art.add_cast_shadow`): each prop and building throws its own silhouette to the right
  along the ground, minus itself. The shadow is a sibling in the Y-sorted entities, sorted a little in front
  of its caster, so it falls over a neighbour's wall or a barrel beside a stall.
- **Lamps** (`Art.add_lamp`): two lights each. A shadowed one lights only the ground (light mask 2), so prop
  footprints (`Art.add_occluder`) throw shadows on it; an unshadowed one lights actors and props (mask 1),
  so nothing stands in its own shadow.
- **Scene effects** (`scripts/ambience.gd`): drifting cloud shadows by day, low mist that thickens at dawn,
  dusk and night, and a vignette. Every effect has a slider in Options > Visual effects (`Settings.FX`).
- Real 3/4 depth (roofs seen from above) can only come from regenerating the sprites; see docs/ART_SPEND.md.

## Camera for buildings (from 2026-11-19, issue #94)

Buildings are drawn in **true 3/4 top-down**: the roof seen from above and receding, like the target's houses.
Prompt: "top-down 3/4 view from above at the same angle as the reference: the roof is seen from above and recedes
away from the viewer, large roof surface visible", with a crop of the target's blue-roof house as `style_image`.
Some come back turned to the corner; that is welcome: Hollowmark mixes angles along winding streets.

- Every option a call returns is its own building, so no sprite repeats in town.
- Building levels: make level 3 first, then edit it down with `edit-images-v2` ("the same building at its humble
  beginning: run-down, patched roof... keep the exact same shape, angle and size"), up to 4 buildings per call.
- Town layout comes from `tools/make_hollowmark.py`: streets, buildings by bottom-centre tile, and footpaths
  (`,`) routed from every door to the nearest street.

## Figure sizes

PixelLab fills whatever canvas it is given, so every character comes out about 30 px tall at a 32 px canvas.
Check each new figure against Ash (29 px) before animating it. Targets: adults 28 to 31 px, children and
small animals about 20 px, big people (Ottoline) about 33 px, bosses about twice a hero (the Auditor is 62 px),
and never taller than the buildings around them. To change a figure's size, resize its 5 drawn rotations with
PixelLab's pixel-art `/resize` (it keeps outlines clean, unlike a plain downscale), import them as a new
character with every direction given (`direction_images`, almost free), then animate that character.

## UI (Phase 6)

- **Fonts.** Body text is Jersey 10 (set as the project's custom theme font, so `ThemeDB.fallback_font` is it
  everywhere); titles and headings use Jacquard 12 (`UiSkin.TITLE_FONT`). Both are pixel fonts under the OFL:
  antialiasing, hinting and subpixel positioning are off in their import settings so they stay crisp.
  The project font is `assets/fonts/body.tres` and the heading face `assets/fonts/heading.tres`: FontVariations
  whose base font Options > Accessibility > Font swaps for Atkinson Hyperlegible (antialiased, sized down by
  `Access.READABLE_SCALE` in `Access.fs`) (issue #192). Draw text with `ThemeDB.fallback_font` and
  `UiSkin.TITLE_FONT`, never a .ttf directly, or the option misses it. The title logo is art and keeps Jacquard.
- **Frames.** `scripts/ui_skin.gd` (`UiSkin.panel(canvas, rect, kind, tint)`) draws 9-slice frames from
  `assets/ui/`: `ledger` (dark ink-blue panel, brass corners: HUD plates, menus, dialogue box, banter),
  `button` (leather and brass: ability slots, town buttons, name tags, tinted with the speaker's colour) and
  `paper` (torn parchment, repeated so its edge stays ragged: signs; text on it uses `UiSkin.PAPER_INK`).
  Clean frames stretch; only paper tiles. Keep text at least 14 px (the corner size) in from a ledger frame's edge.
- **Icons.** `assets/icons/<id>.png`, 32 px, palette-snapped. The id is the data id (items, gear, abilities,
  research, buildings, factions, resources), or `tech_<hero>`, `role_<role>`, `trait_<trait>`, `status_<kind>`.
  `UiSkin.draw_icon()` returns false when an icon is missing, so new content without art still lays out.
  Made with PixelLab Pro (generate-image-v2) at 32x32: one call gives 64 images, so a prompt listing 8 concepts
  "A..H, one per image" returns 8 options for each ($0.08 for 8 icons, picked by eye).
- **Less text on screen.** Control hints show only until two missions are cleared.

## UI bars and rows (from 2026-11-24)

Flat single-colour bars and strips read as placeholder next to the art, so every bar, list row and colour
strip is drawn as pixel art by `scripts/ui_skin.gd`, in whole pixels only:

- **`UiSkin.bar(canvas, rect, fill, ramp, opts)`**: a 1 px ink `#12141f` frame, a recessed `#1f2233` trough with a
  lit lower lip, and the fill shaded from a 4-step ramp: lit top row, base, shaded bottom row, a short gleam on
  tall bars and a lighter leading edge. Options: `notch` (a notch every n px; HP bars use one per 10 HP via
  `UiSkin.notch_every`), `notches` (fractions: tech stages, quarters, a boss's phase line), `ghost` (HP just
  lost, draining in plaster shadow), `hatch` (stripes for danger, with `Access.danger_patterns`), `dim`.
- **`UiSkin.field_bar`**: the small bar over a fighter's head in world pixels: ink frame, two rows (light over
  base), only shown once hurt. Enemies crimson, elites brass, the wardstone and objectives ink-blue.
- **`UiSkin.row`** for list rows (recessed ink panel, the chosen row warm with a brass pixel `frame` and corner
  studs; muted brass when its list is not the one being steered), **`UiSkin.tab`** for the kind/colour marker
  down a row's left edge (a shaded bookmark ribbon with a notched tail, instead of a 3 px flat strip),
  **`UiSkin.swatch`** for colour chips and **`UiSkin.scrollbar`**.
- **Ramps** (`UiSkin.RAMP`, all from the style palette plus the FX accent tints below): HP moss (healthy),
  brass (under half), crimson (under a quarter); Ink ink-blue; gauge wood to brass, lamplight when full; XP
  plum; gear slots rust (weapon), slate (armour), brass (trinket). `UiSkin.ramp(colour)` builds a muted ramp
  from any data colour (a tech's or an Ink colour's), pulled toward night slate so it sits in the art.

**Panels (2026-11-25)**: the ledger frame's dark inner band is a single shadow line now, so text and rows sit on
the panel's face, never on a band (`UiSkin.inner(rect)` gives the face). Ledger panels and rows carry a fixed
pixel grain (`UiSkin.grain`): sparse lighter and darker specks and short fibres, so no surface is one flat colour.

## Effects (from 2026-11-24)

Skills, techs, weapon swings, guards, the swap marker and every burst are drawn in code, and drawn straight
onto the 4x screen they came out as smooth, bright vector shapes. They now draw on the **pixel FX layer**
(`scripts/fx_layer.gd`, `shaders/pixel_fx.gdshader`):

- Effect nodes join with `FxLayer.adopt(node)` (`Fx`, `TechFx` and `Hero.fx_overlay` already do). The main view
  skips that visibility layer; a SubViewport sharing the world draws only it, at one pixel per world pixel on
  the camera's whole-pixel grid, and the shader turns it into pixel art: every colour snaps to the FX palette,
  see-through comes in flat steps (a sixth, a third, two thirds, solid; big faint areas are one even wash, never a dotted mesh), and the night tint is
  mostly taken back out (effects are light).
- **FX palette** = the 38 style colours + accent tints for light: bone light `#e6dfcd`, plum `#3b2a4a #6a4a7e
  #8f6fae #b49bcc`, rose `#7a3a52 #b05a78 #d98aa0`, pale ink `#b8cff2`, pale lamplight `#f7e3a6`, pale poison
  `#b5e88a`, crimson light `#c4504a`, rust light `#d98a5a`, ink mid `#5b84c4`, brass mid `#c9a24a`. Paper white
  stays the Blank's alone.
- **Held frames**: bursts, sweeps, rings and tech blasts move at 15 frames a second (`Fx.STEP`), like the
  sprites, instead of gliding every screen frame.
- **Shapes**: weapon swings and sweeps are crescent smears (thick at the leading edge, thinning to the tail, a
  lit rim, a glint at the head, speed lines behind), thrusts tapered streaks, sparks short streaks or 1-2 px
  chips. These replace the swooshes that were taken out of the sprite animations.
- **Two pictures**: the air (`FxLayer.BIT`: blasts, swings, guards, sparks) over the whole world, and the
  ground (`FxLayer.adopt(node, true)`: hero shadows, where a charging tech will land, the marks of blasts still to
  come) drawn inside the world just before the actors, so it lands on the ground under everyone.
- Anything that must stay crisp text or a readability marker (damage numbers, status marks, enemy tells)
  stays on the normal world layer.
- Check them all at once: `xvfb-run -a godot --fixed-fps 60 --resolution 1280x720 --path . -s tools/fx_gallery.gd --
  out=/tmp/fx.png age=8` (`nofx=1` for the old look).

## Proportions (Phase 8)

One body plan for every person: the heroes' (Ash is the reference). Measured on the south-facing figure, in
pixels at 1x. `tools/art_audit.json` holds the bands and each sprite's measured head; `tools/audit_art.py` flags
anything outside them and redraws `lineup.png` (everyone on one ground line) and `heads.png` (heads at 8x
with a pixel ruler).

| Class | Height | Head (w x h, top of hair or hood to chin) | Notes |
|---|---|---|---|
| Adult | 28-31 | 9-12 x 9-11 | About 3 heads tall. Shoulders 16-20 wide |
| Heavy | 28-31 | 9-12 x 9-11 | Wider (up to 28) but not taller: build is width, never a bigger head |
| Elder | 26-30 | 9-12 x 9-11 | A stoop takes height, not head size |
| Giant (Ottoline) | 32-36 | 10-13 x 10-12 | The only adult allowed past 31 |
| Child | 19-23 | 8-10 x 7-9 | A child's head is nearly an adult's, on a much shorter body |
| Animal | 14-22 | | |
| Boss | 54-66 | | About 2x a hero |

PixelLab fills the canvas whatever the prompt says, so sizes are fixed after generation (pixel-art /resize, then
import with all directions given, then animate; see "Figure sizes"). One figure per sprite: groups such as
the Merrow Three are separate sprites standing together.

## Checking icons and props

`python3 tools/prop_icon_audit.py OUT` checks every icon, prop and building (Chapter 2 placeholders skipped) for
light gaps in the ink outline, stray pixels, salt-and-pepper noise, 1 px kinks in straight edges, soft alpha,
off-palette colour and pixel-identical copies, and draws contact sheets at game size and zoomed with each flagged
pixel marked. Free fixes live in `tools/prop_icon_fixes.json` and are applied by `python3 tools/fix_props_icons.py`
(outline, dedither, remap, pixels; safe to replay). Glow, flame, steam and motion arcs keep no outline on purpose.

The same files live in the PixelLab Creator gallery as "Last Ink | icon|prop|building | <name>" so they can be
edited there. After any change to one of these PNGs run `python3 tools/pixellab_gallery.py push` (free): it replaces
the matching gallery image (ids in `tools/pixellab_gallery.json`) and adds new files. `pull` brings edits made in
PixelLab back into the game files. After every sync that changed anything, rebuild the Art Review page
(`tools/build_art_review.py OUT`) and republish it, so the new version shows there and can be OKed.

## Prop scale (Phase 8)

Props are sized against a 30 px person. Tallest allowed (px): barrels 16, a stack of two crates 22, bench 18, grave
20, sign 22, boulder 30, cart 26, banner 34, fountain 36, well 40, lamppost 46, stall 56. A hedge shrub may be 24 (it tiles into a wall; smaller leaves gaps). A door is at least
22 px tall. A hedge or wall is never one sprite repeated: mix variants, or use a tile edge.

## Collision footprints (buildings and props)

Everything solid stands on a **footprint**: the ground under it as a convex polygon, in `data/footprints.json`, read
by `scripts/footprints.gd`. Footprints are traced from the art by `tools/footprints.py`, so they follow the walls an
angled building shows and reach back as far as its roof hides Ash. That makes a building feel like a building: solid
from every side, and from behind you stop at the back wall (hidden by the roof, drawn behind it by the Y-sorted
layer) instead of walking into the roof and standing against the front face.

When art lands or changes:

1. Add the kind to `data/footprints.json` (`{}` for something solid, `{"walk": true}` for grass you walk through).
2. Run `python3 tools/footprints.py` (variants of a different shape get their own entry automatically).
3. Look at `python3 tools/footprint_sheet.py /tmp/fp.png <kind>`: Ash behind (hidden), beside (touching the wall)
   and in front (on the doorstep). Tune with the hand fields `d` (depth), `clip` (leave out a hanging sign or a gate
   arm) or `inset`; their meaning is in the script's header.
4. `tests/test_footprints.gd` fails if anything placed on a map has no footprint, if art changed size since it was
   traced, if a footprint can be walked through from N/S/E/W, or if a map's spawns, spots or posts get walled off.

`tools/shot.gd ... collisions=1` draws every collision shape in a screenshot.
