# Trailer capture (issue #152)

Tools for recording trailer footage, store GIFs and social clips straight out of the game, so they
can be made again whenever the art changes. All of it lives in `tools/`, which every export preset
leaves out: players never get a capture mode, a hidden key or a debug flag.

| Piece | What it does |
|---|---|
| `tools/capture.gd` | Plays a **shot**: sets up a scene and party, hides the HUD, puts every hero on the ally AI (nobody waits for a player), keeps the party standing, stages the fight and moves the camera along a path. |
| `tools/capture/shots/*.json` | The shots. One file per piece of footage. |
| `tools/capture.sh` | Records a shot with Godot's movie maker at a locked 60 fps (1080p by default, `--4k` for 2160p), trims it to the shot and encodes an MP4. |
| `tools/clips.sh` | ffmpeg recipes: store GIF under 3 MB, WebM under 3 MB, 9:16 vertical cut, joining shots into a reel, burned-in captions, stills. |
| `tests/test_capture.gd` | Checks every shot against the game's data, so a renamed hero or enemy shows up in CI, not on trailer day. |

## Recording

Needs Godot 4.3 (`GODOT=path`, default `godot` then `~/godot/godot`) and ffmpeg. On Linux without a
display it runs under `xvfb-run` by itself.

```sh
tools/capture.sh meadow_skirmish             # build/captures/meadow_skirmish.mp4, 1920x1080, 60 fps
tools/capture.sh meadow_skirmish --4k        # 3840x2160
tools/capture.sh meadow_skirmish --preview   # 960x540, quick, for blocking out a camera path
tools/capture.sh all                         # every shot
tools/capture.sh blank_edge day=0.9 seed=5   # override a shot's settings for one run
tools/capture.sh meadow_skirmish --keep-frames   # also a PNG sequence for an editor
tools/capture.sh meadow_skirmish --audio     # keep the game's sound (off by default)
```

The movie maker renders every frame however long it takes, so the footage is a perfect 60 fps even
on a machine that can't play it that fast (without a GPU expect about a tenth of real time). The
1080p and 4K sizes are exact multiples of the 640x360 layout grid, so pixels stay square and sharp.

Same shot, same seed, same footage: enemies, AI choices and the camera replay identically, so a shot
can be re-recorded after an art change and dropped into the same spot in an edit.

## Clips

```sh
tools/clips.sh gif build/captures/meadow_skirmish.mp4 --from 3 --len 5      # under 3 MB, hard pixels
tools/clips.sh webm build/captures/meadow_skirmish.mp4 --len 6 --max 3M
tools/clips.sh vertical build/captures/meadow_skirmish.mp4 --len 15         # 1080x1920 crop of the middle
tools/clips.sh vertical build/captures/town_plaza.mp4 --fit                 # whole frame over a blurred copy
tools/clips.sh reel build/captures/reel.mp4 build/captures/blank_edge.mp4 build/captures/meadow_skirmish.mp4 --fade 0.25
tools/clips.sh captions build/captures/reel.mp4 tools/capture/sample.srt    # in the game's font
tools/clips.sh still build/captures/town_plaza.mp4 3.5                      # a store screenshot
```

## Writing a shot

A shot is a JSON file in `tools/capture/shots/`. Every key but `_about` is optional.

```json
{
	"_about": "What this footage is for.",
	"scene": "mission",
	"mission": "meadow_patrol",
	"map": "gutterwoods",
	"party": ["ash", "bran", "gristle"],
	"presets": {"bran": "aggressive"},
	"day": 0.62,
	"seed": 4,
	"seconds": 9,
	"party_at": {"from": "blank", "off": [-34, 0]},
	"camera": [ {"t": 0, "follow": "party", "zoom": 1.8}, {"t": 6, "follow": "ash", "zoom": 3} ],
	"beats": [ {"t": 0, "spawn": "nibbler", "count": 3, "at": {"from": "party", "off": [7, 0]}} ]
}
```

**Setup**

| Key | Default | Meaning |
|---|---|---|
| `scene` | `mission` | `mission`, `town` (Hollowmark), `command` (the Command Table) or `title` |
| `mission`, `map` | `meadow_patrol` | which mission, and optionally another map from `maps/` |
| `party` | Ash, Bran, Gristle | 1 to 3 field heroes; the first leads |
| `presets` | the hero's own | ally AI per hero: `aggressive`, `balanced`, `distance`, `support` |
| `day` | game default | time of day: 0.5 noon, 0.75 dusk, 0.9 night |
| `levels` | | every Hollowmark building at this level (town shots) |
| `fx` | player's options | Visual effects sliders, e.g. `{"mist": 80, "vignette": 0}` |
| `seed` | 1 | random seed: change it for a different take of the same fight |
| `seconds` | 6 | length of the recorded footage |
| `settle` | 20 | frames to wait after the scene loads before recording starts |
| `party_at` | map start | where the party stands at the first frame |
| `clear` | true | missions start empty, with no Nibblers streaming out of the Blank: only the beats' enemies |
| `all_ai` | true in missions | the leader is on the AI too |
| `god` | true | heroes take hits but never go below a third of their health |
| `hide_ui` | true (false for `command`, `title`) | hide every on-screen layer: HUD, touch buttons, banter, menus, cards |
| `bars` | true | `false` also hides the bars and gauges drawn over the heroes |
| `numbers` | true | `false` hides floating damage numbers and tech names |

**Places** (`party_at`, a beat's `at`, a camera key's `at`) are in 16 px tiles: `[x, y]` is a tile on
the map; `{"from": "...", "off": [x, y]}` is an offset from `start` (the party's start tile),
`blank` (the Blank's edge, level with the start), `party` (the middle of the living party),
`hero:<id>`, `enemies` (the middle of the living enemies) or `mark:<name>`.

**Camera** keys `{t, at | follow, off, zoom, ease}`: the camera eases from each key to the next.
`follow` takes `party`, `leader`, a hero id or `enemies` and moves with them. `ease` (on the key being
moved to) is `smooth` (default), `linear`, `in`, `out` or `cut`. Zoom 2 is the game's own view; 1.5
is wider, 3 closer. No keys: it follows the party. On the Command Table and title, keys take `zoom`
and `focus` (`[x, y]` as fractions of the screen) for a slow push in.

**Beats** happen at `t` seconds into the footage:

| Beat | Meaning |
|---|---|
| `spawn`, `count`, `at`, `hp` | enemies of that kind appear (`hp: 2` keeps them up twice as long) |
| `tech` | that hero fires its charged tech now, at the nearest enemy (`all` for everyone) |
| `order` | that ally charges its tech the AI way, with the gauge and the telegraph |
| `ability`, `slot` | that hero uses ability 1-4 |
| `swing` | a basic attack at the nearest enemy |
| `walk`, `for` | the leader walks `[x, y]` for that many seconds, as if the stick were held |
| `move`, `at` | puts a hero somewhere (between cuts) |
| `preset`, `to` | switches a hero's AI preset |
| `shake` | screen shake |
| `slow`, `for` | slow motion (`0.3` = 30% speed) for that many seconds |
| `mark`, `at` | names a place for later `{"from": "mark:<name>"}` |
| `call`, `args` | calls into the scene, e.g. `"call": "dialogue_box.play", "args": ["quill_first"]` |
| `say` | a note printed with its time in the log, for lining up music and captions |

`tools/capture.sh` refuses a shot with a mistake in it (a hero not in the party, an enemy kind that
doesn't exist) and says what is wrong; `tools/run_tests.sh capture` checks them all.

## Sample shots

| Shot | For |
|---|---|
| `blank_edge` | the trailer's hook: the Blank's edge at dusk, Ash walks up, something crawls out |
| `meadow_skirmish` | combat: a pack jumps the party, allies' techs, slow motion on Ash's |
| `gutterwoods_brawl` | combat in another biome with the newer heroes and an Enforcer |
| `town_plaza` | Hollowmark built up, late afternoon |
| `command_table` | the empire layer with its menus, slow push in |

They are placeholders for the final cut: the announce and launch trailers wait for the final art.
