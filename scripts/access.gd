class_name Access
extends RefCounted
## Accessibility options (issue #34): text size, reduced flashing, patterned danger markers, how charged
## techs and attacks are held, stick deadzone and dialogue auto-advance. Static like Settings and saved
## in the same file (user://settings.cfg, section [access]), so they are per device, not per save.
##
## The options screen's Accessibility page (OptionsView) changes them; the first time the game starts the
## title screen shows the most important ones before anything else (OptionsView page "first").
##
## Helpers the rest of the game calls:
##   Access.fs(9)          a font size scaled by the text size option (every draw_string / get_string_size)
##   Access.px(13)         a line height or text row height scaled the same way
##   Access.flash(col)     the colour a hit flash should use (pure white, or a soft tint when reducing flashing)
##   Access.strobe(t, hz)  on/off blinking that stays on when reducing flashing
##   Access.calm(a)        alpha of a bright burst or glow (lowered when reducing flashing)

const SECTION := "access"

const TEXT_SIZES := ["Normal", "Large", "Largest"]
const TEXT_SCALE := [1.0, 1.2, 1.4]
const TEXT_INFO := [
	"Text as designed.",
	"All text 20% bigger: menus, dialogue, the HUD and numbers in fights.",
	"All text 40% bigger. Long screens scroll or squeeze to fit.",
]
const TECH_MODES := ["Hold", "Toggle"]
const TECH_INFO := [
	"With a full gauge, hold Attack to charge a tech and let go to fire it.",
	"With a full gauge, press Attack once to start charging and again to fire. Nothing has to be held.",
]
const DEADZONE_MIN := 5
const DEADZONE_MAX := 60
const DEADZONE_DEFAULT := 30
## Movement and map panning on the sticks take the deadzone; menu navigation never goes below its own 50%.
const STICK_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "map_pan_left", "map_pan_right", "map_pan_up", "map_pan_down"]
const MENU_ACTIONS := ["ui_left", "ui_right", "ui_up", "ui_down"]
const AUTO_ADVANCE := ["Off", "Slow", "Normal", "Fast"]
const AUTO_DELAY := [0.0, 4.0, 2.4, 1.2]  # seconds after a line has finished typing (plus a little per word)

static var text_size := 0
static var reduce_flashing := false
static var danger_patterns := true
static var tech_mode := 0
static var hold_attack := false
static var deadzone := DEADZONE_DEFAULT
static var auto_advance := 0
static var first_boot_done := false

static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(Settings.PATH) != OK:
		return
	text_size = clampi(int(cfg.get_value(SECTION, "text_size", text_size)), 0, TEXT_SIZES.size() - 1)
	reduce_flashing = bool(cfg.get_value(SECTION, "reduce_flashing", reduce_flashing))
	danger_patterns = bool(cfg.get_value(SECTION, "danger_patterns", danger_patterns))
	tech_mode = clampi(int(cfg.get_value(SECTION, "tech_mode", tech_mode)), 0, TECH_MODES.size() - 1)
	hold_attack = bool(cfg.get_value(SECTION, "hold_attack", hold_attack))
	deadzone = clampi(int(cfg.get_value(SECTION, "deadzone", deadzone)), DEADZONE_MIN, DEADZONE_MAX)
	auto_advance = clampi(int(cfg.get_value(SECTION, "auto_advance", auto_advance)), 0, AUTO_ADVANCE.size() - 1)
	# Testers who played before this page existed see it once too: it only asks, never resets anything.
	first_boot_done = bool(cfg.get_value(SECTION, "first_boot_done", false))


static func save() -> void:
	load_settings()
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)  # keep every other section
	cfg.set_value(SECTION, "text_size", text_size)
	cfg.set_value(SECTION, "reduce_flashing", reduce_flashing)
	cfg.set_value(SECTION, "danger_patterns", danger_patterns)
	cfg.set_value(SECTION, "tech_mode", tech_mode)
	cfg.set_value(SECTION, "hold_attack", hold_attack)
	cfg.set_value(SECTION, "deadzone", deadzone)
	cfg.set_value(SECTION, "auto_advance", auto_advance)
	cfg.set_value(SECTION, "first_boot_done", first_boot_done)
	cfg.save(Settings.PATH)


## Back to the defaults (the tests and the options page's reset row). Does not touch first_boot_done.
static func reset() -> void:
	load_settings()
	text_size = 0
	reduce_flashing = false
	danger_patterns = true
	tech_mode = 0
	hold_attack = false
	deadzone = DEADZONE_DEFAULT
	auto_advance = 0
	apply()
	save()


## Puts the options that live in the engine in place (the stick deadzone). Settings.apply_all() calls it.
static func apply() -> void:
	load_settings()
	apply_deadzone()


## Should the title screen show the first-boot settings page?
static func needs_first_boot() -> bool:
	load_settings()
	return not first_boot_done


static func finish_first_boot() -> void:
	load_settings()
	first_boot_done = true
	save()


# ---------------------------------------------------------------- text size

static func text_scale() -> float:
	load_settings()
	return TEXT_SCALE[text_size]


## A font size scaled by the text size option. Every font size in the game goes through this, paired
## in the draw call and in the measuring call, so centred and wrapped text keeps lining up.
static func fs(size: int) -> int:
	if not _loaded:
		load_settings()
	if text_size == 0:
		return size
	return maxi(size, roundi(size * TEXT_SCALE[text_size]))


## A line height, text row height or gap that has to grow with the text.
static func px(h: float) -> float:
	if not _loaded:
		load_settings()
	return h if text_size == 0 else roundf(h * TEXT_SCALE[text_size])


## s trimmed with "..." so it fits in w pixels at this (already scaled) font size.
static func fit(font: Font, s: String, size: int, w: float) -> String:
	if w <= 0.0:
		return ""
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= w:
		return s
	while s.length() > 1 and font.get_string_size(s + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
		s = s.left(s.length() - 1)
	return s.strip_edges() + "..."


# ---------------------------------------------------------------- flashing

## The colour of a hit flash: pure white normally, the sprite's own colour barely lifted when
## reducing flashing (the hit still reads from the number, the knockback and the sound).
static func flash(base := Color(1, 1, 1)) -> Color:
	if not _loaded:
		load_settings()
	if not reduce_flashing:
		return Color(1, 1, 1)
	return base.lerp(Color(1, 1, 1), 0.3)


## True/false blinking at hz (a wind-up tell, invulnerability). Reducing flashing holds it on, so the
## state still shows but nothing strobes.
static func strobe(t: float, hz: float) -> bool:
	if not _loaded:
		load_settings()
	if reduce_flashing:
		return true
	return int(t * hz * 2.0) % 2 == 0


## Alpha (or brightness) of a bright burst, glow or flash: lower and gentler when reducing flashing.
static func calm(a: float) -> float:
	if not _loaded:
		load_settings()
	return a * 0.4 if reduce_flashing else a


## A sine pulse (0..1) for glows; slowed right down when reducing flashing.
static func pulse(t: float, speed: float) -> float:
	if not _loaded:
		load_settings()
	return 0.5 + 0.5 * sin(t * (minf(speed, 3.0) if reduce_flashing else speed))


# ---------------------------------------------------------------- input

## 0.05..0.6 for InputMap.
static func deadzone_f() -> float:
	load_settings()
	return deadzone / 100.0


static func apply_deadzone() -> void:
	var dz := deadzone_f()
	for a in STICK_ACTIONS:
		if InputMap.has_action(a):
			InputMap.action_set_deadzone(a, dz)
	for a in MENU_ACTIONS:
		if InputMap.has_action(a):
			InputMap.action_set_deadzone(a, maxf(dz, 0.5))


static func toggle_techs() -> bool:
	load_settings()
	return tech_mode == 1


static func auto_delay(text: String) -> float:
	load_settings()
	if auto_advance == 0:
		return 0.0
	return AUTO_DELAY[auto_advance] + 0.12 * text.split(" ", false).size()
