# Map kit: premade maps and the assets they need

Ojon, 2026-11-25: the mission maps feel generic and repetitive. More interesting layouts need buildings you
can walk into, walls that make rooms and routes, and roofs that fade when you go inside. This document is the
plan for that: how premade maps are built, how that fits the way buildings already work, and the full list of
art a final map kit needs. Until that art is made, everything here runs on code-drawn stand-ins
(`tools/make_map_kit.py`, tracked in `data/placeholders.json`).

## 1. What we have now

- **Maps are text.** `maps/*.txt`, one character per 16 px tile. Ground comes from a PixelLab corner tileset per
  biome (`@ground`), paths are a mask, and everything else is a prop.
- **Buildings are props.** Each building is one finished sprite (`assets/props/house.png`, `townhall.png`, ...),
  with a traced collision footprint (`data/footprints.json`). They look good and Ojon has approved them, but you
  can never go inside one, they are all about the same size, and the same 8 houses turn up everywhere.
- **Biome maps are generated.** `tools/make_biomes.py` builds three layouts per biome from the same recipe:
  open ground, scattered props, a path, a Blank edge on one side. That is where the sameness comes from: every
  map is a field with things standing in it. Nothing makes you choose a route, nothing hides what is round a
  corner, and nothing tells you what this place was before the Blank got to it.

## 2. Decision: a hybrid, not a rewrite

| Option | What it means | Verdict |
|---|---|---|
| A. Keep whole-building sprites only | No change. Maps stay fields with houses in them. | No: this is the problem. |
| **B. Hybrid** | Whole-building sprites stay for Hollowmark and for buildings you never enter (the skyline, the background of a hamlet). Buildings you walk into, walled yards, camps and ruins are built from a **tile kit**: walls, floors, doors and roofs that fade. | **Yes.** |
| C. Everything from the kit, Hollowmark too | Rebuild the town's buildings from tiles. | Not now: it throws away approved art, and the town's building levels are drawn per level. Revisit only if we want town interiors. |

Why B works with what is there: both kinds of building collide (sprites by footprint, kit walls by tile), both
sort in depth with the heroes the same way (by their foot line), and both sit on the same ground. A map can mix
them: a kit-built farmhouse you can enter next to two prop cottages you can't.

**Rule of thumb for map makers:** if the player has a reason to go inside, build it from the kit. If it is
scenery, use a building prop.

## 3. How the kit works (built, `scripts/structures.gd`)

Map characters, written the way the place looks on screen (top-down 3/4, like the town):

| Char | Tile | Notes |
|---|---|---|
| `#` | top of a wall, seen from above | solid |
| `=` | wall face | solid; one or two rows under a `#` row make a south-facing wall |
| `!` | wall face with a window | solid |
| `_` | floor under a roof | rows of `_` closed in by walls and doors get a roof |
| `+` | doorway | walkable, drawn as a threshold; cut it through the cap and face rows |

```
####+#####      <- north wall top, a back door
#========#      <- the inside of the north wall
#________#
#________#      <- the room: gets a roof
####+#####      <- south wall top, front door
====+=!===      <- south wall outside face, two rows tall, a window
====+=====
```

- `@kit timber|stone|palisade` picks the set for the map; `@kitat x,y stone` gives the building touching that
  tile its own set (a Concord office in a timber village).
- **Roofs** cover each room and its walls, drawn as a gable with eaves. A roof fades out while the hero you
  control stands in that room and fades back when you leave. Allies inside a roofed room you are not in are
  hidden, the way they would be.
- **Walls block** like any wall, and **allies and enemies walk round them** (`scripts/paths.gd`, a tile grid
  path): an ally who loses sight of you finds the door; an enemy that heard you comes round the corner; allies
  don't pick targets through walls. Maps without kit walls behave exactly as before.
- **Depth:** each column of wall sorts at its foot, so a hero behind a wall is drawn behind it.
- Test map: `maps/kit_test.txt` (`xvfb-run -a godot --path . -s tools/shot.gd -- map=kit_test at=8,5`).

Known limits of the first version: ranged enemies (spitters, throwers) still shoot over walls; there is no
upper floor or stairs yet; roofs are one gable per room (an L-shaped room gets one roof over its bounding box).

## 4. The final art list

Everything is on the 16 px grid, 3/4 view, style palette (`tools/style_palette.hex`), ink outlines, lit from
the top left like the props. Walls are **two tiles tall** on screen (a hero is about 1.5 tiles). Counts are per
set; generation estimates assume PixelLab tiles at about $0.02 a generation with roughly three tries per keeper.

### 4.1 Structure sets (one per material)

Sets needed, in order: **timber** (villages, Act 1), **Concord stone** (offices, tollhouses, cells, Act 1),
**palisade** (camps, the Coven, Act 1), then **abbey stone** (Ch2), **causeway marble** (Ch3), **coast
stone and wreck timber** (Ch4), **capital** (Ch5-6).

Per set:

| Piece | Tiles | What |
|---|---|---|
| Wall tops | 16 | dual-grid autotile (like the ground sets), so corners and T-joins join up |
| Wall face, top / middle / base rows | 3 x 3 variants | 9 |
| Face ends (left, right) and outer corners | 6 | where a wall turns or stops |
| Windows | 3 | shuttered, lit, broken |
| Doors | 4 | open doorway, closed door, barred or locked, broken in |
| Damaged wall | 4 | a hole you can walk through, a crumbled top, a Blank-eaten edge going white |
| Floors | 4 | 3 variants plus a worn/doorway tile |
| Roof surface, ridge, eaves | 3 x 2 variants | 6 |
| Roof gable ends (left, right), hips | 4 | so a roof has ends instead of a cut edge |
| Chimney, dormer, roof hole | 3 | breaks up long roofs; the hole lets light in on a ruined house |
| **Per set** | **~60 tiles** | **~180 gens, about $3.50** |

### 4.2 Interior props (shared by all sets)

About 40 sprites, each with a footprint entry: table, bench (exists), chairs, bed, cot, shelf, cupboard, hearth,
cooking pot, counter, ledger desk, filing cabinet of drawers (Concord), strongbox, chest, rug x2, wall hangings
x2, banner (exists), candles (exist), lantern, cell bars, stocks, weapon rack, barrels and crates (exist),
sacks, hay bale, workbench, loom, cradle, a broken version of the five most used. **About 120 gens, $2.50.**

### 4.3 Outdoor dressing for premade maps

About 30: fences (wood, stone, broken), gates, hedges, low walls, a tithe wagon, a covered cart, tents (two
sizes), a campfire, a gibbet, a well (exists), a shrine, signposts, field crops (rows), a scarecrow post, a mill
wheel, stepping stones, a footbridge, a plank bridge over a gap. **About 90 gens, $2.**

### 4.4 Elevation (later, for the best layouts)

Cliff faces and ledges (dual grid, 16), stairs and ramps (4), a ladder. Gives maps a second height: walkways on a
mill, a ridge to look down from. **About 60 gens, $1.20.** Needs code for ledges; not built yet.

### 4.5 Total

Three Act 1 sets plus interiors and dressing: **about 480 generations, roughly $10.** All seven sets plus
elevation: about 1,200 generations, roughly $25. Per the cost rule, the first set is generated alone and its
real cost checked against this estimate before the rest.

## 5. Layouts: what makes a premade map interesting

The Act 1 set pieces (built with the kit, `tools/make_act1_maps.py`) follow these rules, and so should every
premade map after them:

1. **A place before a battlefield.** Each map is somewhere people lived or worked, and the layout shows it: the
   hamlet has a green, a well and a pen; the tax office has a queue rail and a filing room.
2. **Routes, not fields.** At least two ways to the goal, one of them through a building or a narrow gap.
3. **Something hidden.** A room, a yard or a back lane you only see when you go in.
4. **The Blank changes the map.** Its edge eats a known landmark during the mission, so the map you leave is not
   the map you entered.
5. **Built around the choice.** Where a mission asks you to choose (villagers or the strongbox), the two goals
   are in different directions, so choosing is also a route.
