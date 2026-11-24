# Balance and performance (issue #35)

Two tools check the game without playing it for hours. Run them after any change to economy numbers,
XP, buildings, research, Fray or visual effects.

## Balance sim

```sh
godot --headless --audio-driver Dummy --path . -s tools/balance_sim.gd -- 90 steady,casual,idle,rush 3 /tmp/balance
```

Arguments: days per run, policies, seeds per policy, output folder. It writes `report.md` (flags, a
table of every run, and a 5-day timeline per policy) and one CSV per run with a row a day. 90 days for
all four policies and three seeds take about 10 seconds.

A scripted player (`tools/balance_bot.gd`) plays the Command layer through the same Empire calls
the screens use, one day at a time: story beats, hiring, bond talks and scenes, party, governors,
claims, building staff, builds, research, Forge weapon upgrades, Wardlamps, expeditions and
diplomacy. Missions are fought on paper: the kills, loot and material rolls, enemy XP, rewards and
mission-type effects are paid exactly as `main.gd` and the results screen pay them, always as a
success. So the sim is about the economy, not about whether a fight can be won.

| Policy | Plays like |
|---|---|
| `idle` | The story only. No jobs, buildings or missions: how fast the Blank wins on its own. |
| `casual` | Governors, builds, research, Forge, a mission every other day. No expeditions, lamps or diplomacy. |
| `steady` | Everything, one mission a day, Wardlamps where Fray climbs, claims while it keeps a reserve. |
| `rush` | Like steady, but claims everything it can and never builds lamps. |

Flags in the report: Hollowmark lost, an idle player losing in under 20 days, more than 3 hungry days,
Gilt over 1,500 and still climbing, Insight over 150, Ink over 120, Supplies over 600 (the last four
after day 30).

`tests/test_balance.gd` runs short versions of the same bot in the test suite and fails when Act 1
leaves these bands: no starving, Supplies under 300 and growing under +10 a day by day 20, the Auditor
met at level 5 to 9, level 15 or less on day 40, an idle player lasting at least 15 days.

### Findings, 2026-11-21

Fixed in the same PR:

- **Supplies piled up.** A steady player had 260 by day 20 and +12 to +18 a day, and was never
  short. Field heroes now eat field rations (1 Supply a day each, on top of upkeep): +4 to +8 a day
  in Act 1, about 130 banked by day 20.
- **Running out of Supplies did nothing.** The hunger tip promised "work slows and tempers go"; now
  it does: while hungry, nobody tends your land (the -2 Fray a day per province is gone, and the
  province panel says why), research runs at half pace, and everyone with a bond loses a point a day.
- **Levels came too fast.** The party met the Auditor (tuned for level 6) at level 10 or 11, and was
  level 15 by day 40 of 20. XP to the next level is now `60 x 1.24^(L-1)` (was `20 x 1.3^(L-1)`): the
  Auditor at level 6 to 8, level 13 on day 40, 16 on day 90, so the later chapters still have levels to
  give. The title screen's boss test sets level 6 with `Progress.xp_to_reach(6)`.

Filed:

- #189 Insight, Ink and (after every building is done) Gilt pile up once Act 1 is over: research
  runs out about day 25. The chapters need sinks.
- #190 A player heading for the story can beat the Auditor on day 6 or 7 (about 9 missions). Decision
  for Ojon: empire gates on the story missions.

Fine as it is: Gilt is the tight resource through Act 1 (it stays near the reserve while buildings go
up until about day 40), and a player who does nothing loses Hollowmark on day 19 to 22.

### The late economy, 2026-11-24 (issue #189)

Once Act 1 was over, Insight, Ink, Gilt and Supplies piled up: research ran out around day 25, Ink had almost
nothing to buy, and Gilt ran away once every building reached level 3. What there is to spend on now
(numbers in the data files and `scripts/sinks.gd`):

| Sink | Uses | Opens | Where |
|---|---|---|---|
| Building levels 4 and 5 | Gilt, Supplies, Ink to build; upkeep every dawn (level 4: 3 Gilt, 1 Supplies, 1 Ink; level 5: 5, 2, 2; the Inkworks pays no Ink) | Level 4 with Chapter 2's region, level 5 with Chapter 3's | `data/buildings.json` levels (`region`, `upkeep`); sprites made from level 3 by `tools/make_building_tiers.py` until hand-made art lands (#224) |
| Unpaid upkeep | A dawn that can't pay leaves the resource at what was left and every level 4+ building works as level 3 (a beacon as level 2) until a dawn that pays | | `Sinks.settle` |
| Hurrying the builders | 30% of the level's Gilt and 40% of its Supplies per day brought forward | Any time a building is going up | Buildings screen, the building's actions |
| Fourth research node per branch | Insight, some Ink | Scriptorium 2, after the branch's third node | `data/research.json` |
| Studies with ranks (one per branch, 5 ranks) | 40 Insight + 2 Ink, +15 and +1 a rank; 4 days, +1 a rank | After the fourth node | `ranks`, `step`, `days_step` |
| Chapter research (Causeway, Coast, Spire: 3 nodes each) | Insight, Ink | When the chapter opens its region; hidden until then | `branches[].region` |
| Level 3 Wardlamp (beacon) | 90 Gilt, 10 Supplies, 8 Ink; burns 1 Ink a day | Beacon Script | `wardlamp` |
| Lamps in later regions | Gilt and Ink cost +25% per chapter past the first | | `wardlamp.region_cost` |
| Tavern feast | 4 Supplies and 3 Gilt a head, every 6 days: bonds +2, injuries heal 2 days, Hollowmark Fray -8, party +10 max HP for 3 days | After the Auditor | Buildings screen, Hollowmark |
| Ink lessons | 2 Ink a day per benched field hero for 2 colour points, up to colour level 3, only from Ink above 30 | After the Auditor, Scriptorium 2 with a researcher | Scriptorium actions (a switch) |

Research numbers for the new nodes are "mods" in `data/research.json`, summed by `Empire.research_mod()`, so a
chapter thread can add nodes without code. The bot (`tools/balance_bot.gd`) builds up to level 5 as regions
open, hurries the builders while it holds more than 300 Gilt, feasts when the larder holds 120 Supplies, and
leaves lessons on.

Sim after the change (`-- 90 steady,casual,rush 3`): no flags. Highest after day 30 across the nine runs:
Insight 174, Ink 132 (one rush run, briefly), Gilt 450, Supplies 543 (rush, which holds the most land); on
day 90 every run is under the bands (Insight 18 to 99, Ink 18 to 78, Gilt 84 to 422). Ink now sits near the
lesson floor of 30 once lessons start; a player saving Ink for something switches lessons off. A steady
player builds the first level 4 around day 80: the one building crew is still the pace-setter, which is
what hurrying is for. `tests/test_sinks.gd` keeps an 80-day steady run inside the bands.

Still open: the idle policy loses Hollowmark on day 19 or 20, one day under its band, as before this change.
Chapters 3 to 5 have no story yet, so level 5 and the chapter research can only be reached by opening their
regions (tests do); their numbers are first drafts for those chapters to tune.

## Performance probe

```sh
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 --audio-driver Dummy \
    -s tools/perf_probe.gd -- 8 /tmp/perf.md all 100
godot --headless --audio-driver Dummy --path . -s tools/perf_probe.gd -- 8 /tmp/perf_cpu.md
```

Arguments: seconds to measure per scene, output file, scenes (`all` or a comma list of `town_noon`,
`town_night`, `command`, `fight`, `fight_night`, `defense`, `boss`, `tollgate`), and the value every
Visual effects slider is set to (100 = all effects at full, the worst case; 0 = the low-end fallback).
Town scenes have every building at level 3 and the whole roster in the streets; fight scenes keep 30
mixed enemies (Nibblers, Spitters, Moths, Enforcers, Sellswords, Scarecrows) around the party.

"Work ms" is the frame's real work (physics, scripts, drawing) without the wait for the next frame.
Headless, that is the game's CPU cost. Under xvfb the GPU is software (llvmpipe), so its fps are a
worst case and only useful to compare effect settings. **For real fps on a laptop, press F3 in the
game** (`scripts/perf_overlay.gd`): fps, frame time (average and worst over a second), draw calls,
nodes, RAM, VRAM, window size and GPU.

### Numbers, 2026-11-21 (4-core cloud container)

CPU cost, headless:

| Scene | Load ms | Work ms avg | Work p95 | Nodes | Enemies | RAM MB |
|---|---|---|---|---|---|---|
| Town, noon | 1121 | 2.1 | 3.1 | 696 | 0 | 91 |
| Town, night | 68 | 2.0 | 2.7 | 690 | 0 | 91 |
| Command Table | 989 | 7.2 | 10.0 | 62 | 0 | 118 |
| Fight, day | 331 | 4.9 | 8.7 | 2484 | 30 | 128 |
| Fight, night | 191 | 4.7 | 7.9 | 2508 | 31 | 128 |
| Defense | 113 | 3.7 | 5.4 | 1560 | 10 | 126 |
| The Auditor | 57 | 2.5 | 3.6 | 945 | 1 | 130 |
| Tollgate fight, dusk | 72 | 5.0 | 9.6 | 1547 | 30 | 133 |

The first load includes the one-time data and texture loading (about a second).

Rendering, xvfb at 1920x1080, all effects at 100: 141 draw calls and 57 MB of video memory in the
night town, 171 to 256 draw calls, up to 32k primitives and 65 MB in the big fights. Any laptop GPU
from the last ten years handles that; what decides fps there is the full-screen effect shaders, which
only F3 on the real machine can tell.

Visual effects sliders as the low-end fallback (xvfb at 1280x720, software GPU): the night town goes
from 133 ms a frame with every effect at 100 to 38 ms with every effect at 0 (3.5 times faster), the
night fight from 108 ms to 58 ms. So turning effects down works.

Filed: #191 the Command Table redraws everything every frame (the heaviest CPU scene, still inside
the 16.7 ms budget).
