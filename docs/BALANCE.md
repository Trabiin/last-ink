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
| Command Table | 989 | 7.2 (0.5 after #191) | 10.0 (0.7 after #191) | 62 | 0 | 118 |
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

Fixed (#191): the Command Table redrew the whole screen every frame. It now redraws each layer only
when what it shows changes (selection, hover, a new day, resources, settings, pan and zoom); the fog,
the Blank's static, the surge rings and the alert markers move on small layers of their own, and the
gold outline and "TIME PAUSED" pulse through modulate. Headless, 2026-11-24: 8.2 ms avg / 12.2 ms p95
before, 0.5 ms / 0.7 ms after. `tests/test_command_redraw.gd` fails if an idle table redraws again.
