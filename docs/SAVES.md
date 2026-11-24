# Saves: format, upgrades and the rule for every PR

Players will have 10+ hour campaigns. A new build must load every save an older build wrote.
Issue #110 set this up; this page is the rule every later change follows.

## The rule

**Any PR that adds, renames, moves or reinterprets saved state adds a migration step and a fixture.**

- Only adding a field that `from_dict()` already defaults when it is missing? Then no step is needed,
  but the loader must tolerate the key being absent (use `d.get(key, default)`, never `d[key]`), and
  the existing fixtures prove it in CI.
- Content cut or renamed (a recruit, research node, faction, mission id)? The loader drops unknown ids;
  a rename needs a step that rewrites the old id to the new one.
- Two PRs can each add a step at the same time: steps are separate files, so they merge in any order.

## What a save looks like

One JSON file per slot in `user://` (`save_auto.json`, `save_1.json` .. `save_3.json`; on the web this is
the browser's IndexedDB). Top level is the scene snapshot (mission, hub or Command Table) plus:

| Key | Meaning |
|---|---|
| `version` | Save format. `2` since #110. Bumped only if the outer layout changes in a way a step cannot express. |
| `game_version` | `application/config/version` in `project.godot` of the build that wrote it. Old saves: `"pre-release"`. |
| `migrations` | Ids of every upgrade step this save already has. New saves list every step the build knows. |
| `saved_at`, `playtime`, `scene`, `area_name` | For menus and for loading the right scene. |
| `empire` | The campaign: `Empire.to_dict()` (`scripts/empire.gd`). |

## How loading works (`scripts/save.gd`, `scripts/save_migrations.gd`)

1. The file is parsed. Not JSON, not an object, or no `version`: the slot is **broken**.
2. `version` higher than this build's `Saves.VERSION`, or a step id this build does not know: the save is
   **newer**. It is left untouched, shown as "made by a newer version", and cannot be loaded here.
3. Otherwise every step in `scripts/migrations/` that the save does not list runs, in file-name order.
   A step that returns `{}` makes the slot broken.
4. `Empire.from_dict()` starts from a fresh campaign (`Empire.reset()`) and copies in what the save has,
   so anything new in the data (recruits, provinces, research nodes, bonds, factions) gets its default.

Nothing is ever deleted:

- A **broken** save is copied to `save_<slot>.broken-<time>.json`, the slot is freed, and the title screen
  tells the player once ("About your saves").
- Saving over a **newer** save first copies it to `save_<slot>.newer-<time>.json`.
- Saving over a save that needed upgrading first copies the original to `save_<slot>.v<old version>-<time>.json`.

## Adding a migration step

1. Before changing the code, make a real save that has the old shape: play to the state that matters
   (or script it, like `tests/run.gd` does) and copy the slot file from the user data folder
   (`~/.local/share/godot/app_userdata/Last Ink/` on Linux).
2. Save it as `tests/fixtures/saves/<step id>__<what it shows>.json`.
3. Add `scripts/migrations/<yyyymmdd>_<what>.gd`. Steps run sorted by file name, so the name must sort after
   every step yours relies on (`20261120_journal` would have run before `20261120_save_format_v2`; it is
   `20261121_journal` for that reason):

   ```gdscript
   extends RefCounted
   ## What changed in the save, and what old saves get instead.

   static func migrate(save: Dictionary) -> Dictionary:
       var empire: Dictionary = save.get("empire", {})
       # ...change `save` / `empire` in place...
       return save  # or {} if this save truly cannot be converted
   ```

   `save` is the whole file; the campaign is under `save["empire"]`. Steps may use the game's static
   classes and data files. Keep a step working forever: later steps run after it on old saves.
4. Add checks for what your step changed to `tests/test_saves.gd` (see `test_first_build_save_is_converted`).
5. Run `tools/run_tests.sh saves`.

The tests fail if a step has no fixture, if a step file name is not `<yyyymmdd>_<what>.gd`, or if any
fixture fails to upgrade, load into the campaign, save again and read back without further upgrades.

## Steps so far

| Step | What it does |
|---|---|
| `20261120_save_format_v2` | Format 1 to 2. First-build saves get a campaign and scene, mission saves from before missions.json get the Meadow patrol, banter speaker names become recruit ids, `said_first_kill` / `said_low_power` become seen dialogue events, and the save is marked `pre-release`. |
| `20261120_territory_regions` | Issue #53: saves from the nine-province map get `regions: ["marches"]` (the only region they could have). Their provinces keep owner, Fray and scars; the 15 new provinces start as `data/provinces.json` has them, under the fog. |
| `20261120_weapon_ink_skills` | Issue #24: heroes in the save get weapon and Ink skill levels for the fighting they have already done (30 weapon points and 10 points in each Ink colour their abilities use per character level past 1), capped at level 3 like the Barracks drill; techs are chosen by hold length. |
| `20261121_journal` | Issue #114: the journal's state (`empire.journal`). Enemies on the rosters of provinces where a mission was cleared count as met and beaten once (the Auditor too after `auditor_duel`), the save's expedition reports become history, and each mission cleared before the journal gets a history entry marked "before the journal". Dated a day later on purpose: steps run in file-name order and this one needs `20261120_save_format_v2` to have run first. |
| `20261121_personal_missions` | Issue #113: personal Guildhall jobs became Command Table missions. A squad out on one (`personal_<who>`) is called home, its 2 Supplies a head are refunded, a report says where the mission waits, and old `personal_*` cooldowns are dropped. Bond ranks are kept. |
| `20261121_stores_and_satchel` | Issue #112: the satchel got a capacity (10 slots, per-item carry limits) and Hollowmark got stores. Old saves get `empire.progress.armory` with the starting pack, and every satchel item above it moves to the stores so nothing found is lost. A mid-mission save keeps its satchel; the restock after the mission stores the extras. |
| `20261123_faction_asks` | Issue #131: faction asks (`empire.asks`). Old saves have never been asked anything, so nothing is on offer or accepted; the factions' first asks are spread over the next days (2, 3 and 4 days after the save's day, in `data/factions.json` order) so they don't all arrive on one dawn. |
| `20261124_names` | Issue #158 naming pass: ids did not change, so nothing moves; old display names (Hesper Quoin, Quill Marrow, Lampwick Hills...) in text the save keeps (journal history, reports, notices) are rewritten to the new ones. `20261120_save_format_v2` and `20261122_relationships` also know the old names, because they run before this step on old saves. |
| `20261125_chapter2` | Issue #28 Chapter 2: Saint Ledger's Abbey (was Concord) and the Bonefield Cloister (was free) get their new owners, the Abbey and the Erasers, unless the player holds them or they are erased. A campaign that saw the End of Act 1 opens the Abbey region, which `act1_end` now does itself. Standing with the new factions starts at their `start`. |
| `20261126_chapter3` | Issue #29 Chapter 3: the Velvet Causeway (was Concord) belongs to the Velvet Nobility unless the player holds it or it is erased. The Causeway region opens with Chapter 3's first beat (`ch3_invitation`), so nothing is opened here. Standing with the Nobility starts at its `start`. |
