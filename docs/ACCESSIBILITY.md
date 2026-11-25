# Accessibility

Issue #34 (first pass) and #192 (part 2: readable font, map markings, camera motion, rebinding every
action, assists, captions, visible focus on every screen, Largest text polish).

## What the player gets

**Options > Accessibility** (and, the first time the game starts, a short "Before you start" page with
the most important ones, shown before the title menu and the prologue):

| Option | What it does |
|---|---|
| Text size | Normal, Large (+20%), Largest (+40%). Every text the game draws: menus, dialogue, HUD, damage numbers. Long pages scroll. |
| Reduce flashing | Hit flashes become a soft tint, blinking tells and invulnerability hold still, bright bursts and glows are dimmer and sparser, the Blank's flicker drifts slowly, the beam tech stops crackling. |
| Danger markers | Patterned (default): danger zones are hatched with a dark dashed outline, aim lines are chevrons, wind-ups show a warning sign. Colour only: the old red wash and red "!". |
| Charged techs | Hold (hold Attack, let go to fire) or Toggle (press once to charge, again to fire). |
| Hold to attack | Keep Attack held to swing again each time the gauge fills. |
| Stick deadzone | 5-60% for movement and map panning (menus never go below 50%). |
| Auto-advance dialogue | Off, Slow, Normal, Fast. |
| Dialogue log | Everything said this session: Backspace / gamepad Back / mouse wheel up / "Log" in any conversation, or from this page. |
| Font | Pixel (Jersey 10, headings Jacquard 12) or Readable: Atkinson Hyperlegible everywhere, headings included (the title logo stays, it is art). Applies at once. |
| Map markings | Shapes and numbers (default): on the Command Table every owner has a shape (yours a flag, unclaimed a ring, the Concord a square, the Coven a triangle, the Guild a diamond, erased land a cross) on the map, the legend and the panel; every province shows its Fray in a box after its name (plain when Safe, a double top rule when Fraying, hatched when Unravelling) and Unravelling land is hatched on the map. Colour only: the old washes. |
| Leader marker | After a swap (default): a small brass marker drops in over the hero you now control and fades after a second. Always: it stays over that hero. (No marker otherwise: the camera follows your hero and its HUD plate is framed in brass.) |
| Captions | Important sounds as text near the bottom of the screen: warning and alarm bells (saying what they are about, e.g. a Blank surge coming), a hero falling, fanfares, level-ups, the Blank's hum (with an arrow towards it). |
| Camera motion | Full or Reduced: the camera sticks to the hero instead of gliding after them, the Command Table's map jumps instead of sweeping, the fog stops drifting. |

**Options > Assists** (right under Difficulty), each its own switch, saved per device in `[assists]`:

| Assist | What it does |
|---|---|
| Damage taken | 100%, 75%, 50% or 25% of the damage the party takes, on top of the difficulty. |
| Enemy speed | Normal, Slower (85%) or Slowest (70%): enemies move, wind up, attack and throw at that pace. The party is unaffected. |
| Heal between fights | Three seconds with no enemy near the leader and the living heroes heal a quarter of their health a second. |
| Skip story fights | Story missions get "Skip this fight" in the pause menu: any conversation the fight would have played (a boss's opening, turn and last words) plays, then the mission is won with the full rewards. |
| Blank pressure | Auto (gentle on Story difficulty), Gentle or Full. Gentle takes 40% off each province's daily Fray growth (shown as its own line in the province panel) and surges hit at 60%. |

Assists never lock anything: no ending, reward, scene or achievement checks them, and no text judges them.

**Options > Controls**: every action can be rebound (keyboard key and gamepad input), grouped as Moving and
fighting, Town and Command Table, Menus and conversations; menu keys too. The arrow keys, Enter, Escape, the
d-pad, A, B and Start always keep working in menus and for pause, whatever is bound, so nobody can lock
themselves out (shown next to those bindings). Two actions only swap keys when both can be pressed in the
same place (`Settings.clash`): mission keys and town/table keys share the gamepad freely. Keyboard layouts:
Default, One hand (left: WASD, Space, Tab, C, 1-4, Q) and One hand (right: arrows, Enter, Shift, /, , . ; ').
Menu sounds have their own volume; a Voice volume appears once recorded speech ships (`assets/audio/voice/`).

Text speed and screen shake are repeated on the page. Settings live per device in `user://settings.cfg`,
section `[access]`.

## Rules for new code

- **Font sizes** go through `Access.fs(size)`, in the draw call and the measuring call alike, and fixed
  line heights or text rows through `Access.px(h)`. `tests/test_access.gd` scans `scripts/` and fails on
  a `draw_string` / `get_string_size` (and friends) whose size skips it. Text that must keep its size
  (the title logo, scenery) is marked `# no-fs` or listed in the test. Use `Access.fit()` to trim a note
  that has no room at big sizes.
- **Enemy tells** use `Telegraph`: `circle` / `rect` for where an attack lands, `aim` for aim lines,
  `alert` for the wind-up mark. Never a red-only shape.
- **Bars** use `UiSkin.bar` / `UiSkin.field_bar`. Anything that warns (low HP, high Fray, a boss's second
  phase) passes `hatch` when `Access.danger_patterns` is on, so the warning is stripes as well as a colour,
  and HP bars carry a notch every 10 HP so their length reads without colour.
- **Flashes**: `Access.flash(col)` for a hit flash colour, `Access.strobe(t, hz)` for blinking,
  `Access.calm(a)` for bright glows, `Access.pulse(t, speed)` for pulsing. `Fx.burst` already calms itself.
- **Anything that shows spoken lines** calls `DialogueLog.track(self, line, kind)` every frame while the
  line is up, skips its own input while `DialogueLog.is_open()`, and opens the log on `DialogueLog.asked()`.
- **Fonts**: draw with `ThemeDB.fallback_font` (body) and `UiSkin.TITLE_FONT` (headings), never a .ttf, so
  the readable font reaches it. Don't read `UiSkin.TITLE_FONT.base_font` directly in code: GDScript folds
  `CONST.property` at compile time; go through a variable.
- **Map**: anything new on the Command Table that tells owners or states apart by colour also gets a shape or
  a number while `Access.map_symbols` is on. A new faction gets the next spare shape automatically; give it its
  own in `command.gd` `OWNER_MARKS`.
- **Enemies**: a new enemy script multiplies its `_physics_process` delta by `Assists.pace()` (after the dying
  check) and moves with `_slide()` instead of `move_and_slide()`, so the enemy speed assist reaches it.
- **Input**: a new input action goes into `Settings.REMAPPABLE` (and `GROUPS` unless it is a town/table key);
  `tests/test_access2.gd` fails on any action the Controls page doesn't list.
- **Sounds**: an effect that carries information gets an entry in `Audio.CAPTIONS`, or pass the caption as the
  fourth argument of `Audio.sfx` when the same sound means different things.
- **Cameras** that follow something use `Access.follow_speed()`, smoothed pans and zooms `Access.ease_k()`.
- **Focus**: a list screen keeps one `sel` (or equivalent) that the arrow keys / d-pad move and draws exactly
  one cursor: the gold frame (`UiSkin.highlight` or a gold outline) plus gold text. Nothing else on screen
  wears gold while unfocused (a default button gets a muted frame). Pointing at a row with the mouse focuses
  it, like the arrow keys; a click on the focused row acts. The focused row is always drawn on screen: a
  list taller than the screen scrolls with the focus.
- **Wheel and touch**: on a scrolling list the wheel and a finger drag walk through it without wrapping
  round (`Prompts.list_steps`, `Prompts.step_row`), and a finger only picks or acts when it lifts without
  having dragged (`Prompts.list_tap`), so scrolling never uses an item. Add new list screens to
  `tests/test_focus.gd` (`_audit_table`), which checks all of this at Normal and at Largest with the
  readable font.
- **Room at large sizes**: text beside a title starts after the title (`UiSkin.header_line`), footers
  slide left rather than off the edge, and a view's `_text(..., width)` trims with "..." instead of
  cutting mid-letter.
- Check a new screen at Largest: `ACCESS_SHOTS=/tmp/a11y TEXT_SIZE=2 xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- access_shots`
  (add it to `tests/test_access_shots.gd`). Add `FONT=1` for the readable font.

## Checked

- Colour-blind simulation (protanopia, deuteranopia, tritanopia; Machado 2009) of the Command Table, the
  mission HUD and the danger markers: owners and Fray read by shape and number, HP and Ink bars carry their
  percentages, danger zones read by their hatching and outline.

- Visible focus (2026-11-24): every list screen on the Command Table, the party picker, Help, the quick
  menu, Party gear and the skill tree, at Normal and at Largest with the readable font
  (`tests/test_focus.gd`): arrow keys and d-pad reach every row and the focused row stays on screen, the
  mouse pointer moves the focus, a tap focuses and a second tap acts, the wheel and a finger drag reach
  rows out of sight. Screens built from Godot controls (the report form, the playtest survey) use the
  engine's focus with a gold frame. Single-button cards (results, chapter cards, help cards) take
  Enter / A / a tap anywhere.
- Largest text, both fonts, every screen in `tests/test_access_shots.gd`: the title tagline keeps clear
  of the menu, the Command Table legend wraps above itself instead of running into "Next to fall",
  headers, footers, Research headings, Journal rows, quick menu tabs and the HUD plates fit.

## Still open

- The Game Accessibility Guidelines review and Steam accessibility tags wait on the store page (#151).
- Re-run `tests/test_access_shots.gd` at Largest with both fonts after the final UI pass (#144).
