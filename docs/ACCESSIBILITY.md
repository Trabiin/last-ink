# Accessibility

Issue #34 (first pass); what is still open is in #192.

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
- **Flashes**: `Access.flash(col)` for a hit flash colour, `Access.strobe(t, hz)` for blinking,
  `Access.calm(a)` for bright glows, `Access.pulse(t, speed)` for pulsing. `Fx.burst` already calms itself.
- **Anything that shows spoken lines** calls `DialogueLog.track(self, line, kind)` every frame while the
  line is up, skips its own input while `DialogueLog.is_open()`, and opens the log on `DialogueLog.asked()`.
- Check a new screen at Largest: `ACCESS_SHOTS=/tmp/a11y TEXT_SIZE=2 xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- access_shots`
  (add it to `tests/test_access_shots.gd`).
