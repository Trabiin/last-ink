# Automated tests

Every push and pull request runs the tests in GitHub Actions (job `test` in
`.github/workflows/deploy-web.yml`). `main` only deploys to GitHub Pages when they pass.

## Running them

```sh
tools/run_tests.sh            # everything (about a minute and a half)
tools/run_tests.sh saves      # only test files whose name contains "saves"
GODOT=~/godot/godot tools/run_tests.sh   # pick the Godot 4.3 binary
```

The script imports the project, runs `tests/run.gd` headless, and fails when:

- any test fails, or
- the log has any `SCRIPT ERROR`, `ERROR` or `WARNING` line (warnings count as errors). A test that
  triggers one on purpose, like a corrupt save being set aside, announces it first with
  `allow_log("<regex>")`. Engine noise at shutdown and on machines with no sound card is ignored.

Tests never touch your real saves: they write to `user://test_run/`.

## Player reports

Bug reports and feedback from players land in a private repository; the triage routine that turns
them into issues here is in [FEEDBACK.md](FEEDBACK.md#triage-routine-claude).

## What is covered

| File | Checks |
|---|---|
| `tests/test_data.gd` | Every `data/*.json` parses. Every id it points at exists: recruits, traits, join hooks, field heroes, abilities, AI styles, techs, gear, items, bonds and their scenes, provinces, factions and deals, buildings, research, expeditions, missions, mission types, personal missions (steps, spots on their maps, speakers and talks), maps and their @spot lines, enemies and rosters, Verity's plans, dialogue and story speakers, talks, beats and goals, portraits, sprite sets and every sprite frame. |
| `tests/test_saves.gd` | Save migrations (docs/SAVES.md): every step is well formed and has a fixture, every fixture upgrades and loads, cut content is dropped safely, newer saves are kept and not loaded, broken saves are set aside and reported, backups before overwriting, and old saves resume in the real scenes. |
| `tests/test_capture.gd` | Trailer capture (#152): every shot in `tools/capture/shots/` names a real scene, mission, map, field heroes, AI presets and enemy kinds, keeps its camera keys in order and only stages fights in missions; a broken shot is reported line by line. Recording itself: `tools/capture.sh` ([tools/capture/README.md](../tools/capture/README.md)). |
| `tests/test_feedback.gd` | Crash reports and feedback (#146): error counting ignores shutdown noise, session logs rotate and carry the header and breadcrumbs, a session without a clean exit counts as a crash, the title offers a report once (never during tests, muted until the next version), reports hold only what was ticked (text capped, save in use, halved screenshot, no key), the zip, sending to a local fake endpoint (success and refusal), the form from the title, town, table and mission pause menus (asks before throwing away typed text, Save to file), F12, and nothing depends on the test shortcuts. The report worker has its own tests: `node tools/feedback_worker/test.mjs`. |
| `tests/test_balance.gd` | Balance guard rails (#35, docs/BALANCE.md): a scripted player runs the Command layer for 40 days (steady, casual) or 60 (doing nothing) and Act 1 stays in its bands (no starving, Supplies and Gilt not piling up by day 20, the Auditor met around level 6 to 8, level 20 far off on day 40, an idle player lasting two weeks); field rations, hunger slowing Fray tending, research and bonds; `Progress.xp_to_reach`; the F3 performance readout. |
| `tests/test_scenes.gd` | Boots the title, New Game into the prologue, the hub, the Command Table and every screen on it, one mission of each type (patrol, boss, defense, reclaim, rescue, raid, salvage, and a personal mission with a forced hero and one with an escort) launched and settled, map layouts varying between visits, a retreat, the quick menu, and save/load round trips in a mission, in town and at the table. |
| `tests/test_skills.gd` | Weapon and Ink skills (#24): five techs per hero with known keys, motifs and sounds, Ink colours and tiers on every ability, skill levels, the Barracks cap, the save step, every tech fired at an enemy in a real mission, allies choosing among techs, and the Techs tab and Skills screen. |
| `tests/test_ally_techs.gd` | Allies' charged techs (#108, #124): every field hero as an AI ally in a real mission fires its tech at a crowd under each preset, "On my call" never charges or fires by itself, "Unleash" fires within a few seconds, taking control mid-charge never fires the tech and keeps the gauge, every tech a hero can learn scores at its standoff, and tech modes survive a save. Fights run three times faster with three times the physics ticks, so the game sees the same 1/60 s steps. `tools/ai_tech_sim.gd` stays as the long soak test. |
| `tests/test_bonds.gd` | Bonds (#50, #120, #122): every bond has a portrait, rank 3 and 5 perks, a personal mission with a home province, one scene per rank with 2 to 3 choices, known speakers and expressions, and every line and choice fits the scene view's text box; every rank scene (and the romance moment) plays through the real scene view and moves the bond on; personal missions come up at rank 4, an erased home province locks them until it is reclaimed; every perk unlocks at its rank, and the eight perks from #120 do what they say. Screenshots: `BOND_SHOTS=/tmp/bonds xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- bonds`. |
| `tests/test_skill_trees.gd` | Skill trees (#25): every field hero has a full tree whose nodes use only stats, perks, focuses and ability changes the code reads, every branch changes how the hero plays, bond gates and one capstone, Skill Points from levels, learning in order, unlearning for Gilt (not on missions), stats and abilities changed, the save step and cleaning bad saved trees, every kind of passive in a real fight (bodyguard, evade, last stand, auras, thorns, damage bonuses, kill rewards, leech, swing stun, poison kills, revives), tree poison as the shared poison status (no stagger per tick, credit and kill rewards, cures, a dormant Auditor untouched), learning mid-mission, ally focus, and the screen from the quick menu and the Gear screen. |
| `tests/test_journal.gd` | The journal (#114): `data/journal.json` is well formed and complete (every region, faction, enemy kind and Ink colour has a codex entry, every story goal names a chapter, figure portraits exist), the quest log through the story, personal stories, factions, surges and Verity's plans, enemies and history recorded and saved, the save step on an old save, and the screen in town (I, the menu, show on map to the Command Table), at the table and from the mission pause menu. |
| `tests/test_voice.gd` | Script voice (#167, docs/VOICES.md): no banned AI-prose phrase in any data value or script string (allowlist in the file), one punctuation style (no em/en dashes, curly quotes or the `…` character; no spaced hyphen as a dash in data), and an advisory count of the softer tells (lectures, corrections, moral tags, stated feelings, words another character owns). `VOICE_REPORT=1` lists every hit. |
| `tests/test_items.gd` | Items, Forge and Market (#112): about a dozen consumables of every kind including the Blank ward, every material with a source, a use and an icon, every recipe well formed with an icon, six-tier weapon lines, armour and perk trinkets, Forge/Market sprites and status icons, satchel capacity and restock, Forge jobs (blockers, crafting over days, weapon upgrades, saved), Market income, stable rotating stock, buying and selling, statuses taking hold, curing, stun immunity, boons, the ward, trinket perks, and the Forge & Market screen in town and at the table. |
| `tests/test_help.gd` | Onboarding and help (#115): `data/help.json` is well formed (every voice exists with a portrait, every Command screen has an explainer, every unlock says why it is shut and opens by a set day, button tokens name real actions), button tokens follow the device, pad style and remaps, the story opens Bonds, Expeditions, Research and Diplomacy over the first days (no envoys before), old saves are not told their first week, first-time tips come due (surge, erasure, injury, Concord trouble, hunger), the Command Table explainer and screen explainers play once and hold the screen still, locked screens stay shut with a reason, unlocks wait for story beats in town, the Help screen from the town, table and mission pause menus (replay, tips switch, controls per device), the codex holds every topic, and a new player running the clock reaches day 5 with everything open and explained. |
| `tests/test_display.gd` | Desktop builds (#145): Windows, macOS and Linux export presets (no test shortcuts, no debug console, one-file builds, icons, version from `project.godot`), the app name, icon and own save folder, the Display options (step, persist, survive `Settings.save`, pixel-perfect scaling), Alt+Enter and F11, pause and mute when the window loses focus (in town, and the pause menu in a fight), the Display page and Save folder button on the options screen, and Quit on the title screen. |
| `tests/test_access.gd` | Accessibility (#34): every option persists next to the other settings, every font size the game draws or measures goes through `Access.fs` (source scan), the first-start page before the title menu, the Accessibility page (rows, wrap, deadzone reaching the stick actions, scrolling at Largest, reset), reduced flashing (tints, no strobing, calmer sparks), Toggle and Hold charged techs and Hold to attack in a real mission, the dialogue log (once per line, cap, cleared by a new game, opens from a real conversation which waits under it) and auto-advance, and the danger markers in both styles. Screenshots at any text size: `ACCESS_SHOTS=/tmp/a11y TEXT_SIZE=2 xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- access_shots`. |
| `tests/test_scripts.gd` | Every script in `scripts/` compiles. |

## Writing a test

Add `tests/test_<area>.gd`:

```gdscript
extends "res://tests/test_case.gd"

func test_something() -> void:
    var empire := autoload("Empire")
    empire.reset()
    check_eq(empire.day, 1, "a new campaign starts on day 1")
    var hub := await goto("res://scenes/hub.tscn")
    check(hub.leader != null, "Ash is in town")
```

Each `test_*` method gets a fresh instance; `before_each()` / `after_each()` run around it. Helpers:
`check`, `check_eq`, `frames(n)`, `goto(scene)`, `wait_scene(scene)` (after the game changed scene
itself), `autoload(name)`, `allow_log(regex)`.

## Exported builds

`.github/workflows/desktop.yml` also runs the `scenes`, `saves` and `display` tests inside the exported
Windows, macOS and Linux builds (`tools/smoke_build.sh`, see [DESKTOP.md](DESKTOP.md)). Tests that list
files in `res://` must accept the names an export uses (`x.gd.remap`, `x.png.import`).

