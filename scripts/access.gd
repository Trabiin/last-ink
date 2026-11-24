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
##
## Part 2 (issue #192): a readable font (Atkinson Hyperlegible for the body and heading faces), owner
## symbols and Fray numbers on the Command Table, reduced camera motion and captions for sound cues.
## Assists that change the game itself (damage taken, enemy pace...) live in Assists.

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
static var readable_font := false
static var map_symbols := true
static var reduce_motion := false
static var captions := false

static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	min_size = DECK_MIN_SIZE if DisplaySettings.on_deck() else 0
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
	readable_font = bool(cfg.get_value(SECTION, "readable_font", readable_font))
	map_symbols = bool(cfg.get_value(SECTION, "map_symbols", map_symbols))
	reduce_motion = bool(cfg.get_value(SECTION, "reduce_motion", reduce_motion))
	captions = bool(cfg.get_value(SECTION, "captions", captions))
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
	cfg.set_value(SECTION, "readable_font", readable_font)
	cfg.set_value(SECTION, "map_symbols", map_symbols)
	cfg.set_value(SECTION, "reduce_motion", reduce_motion)
	cfg.set_value(SECTION, "captions", captions)
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
	readable_font = false
	map_symbols = true
	reduce_motion = false
	captions = false
	apply()
	save()


## Puts the options that live in the engine in place (the stick deadzone, the font). Settings.apply_all() calls it.
static func apply() -> void:
	load_settings()
	apply_deadzone()
	apply_font()


## Should the title screen show the first-boot settings page?
static func needs_first_boot() -> bool:
	load_settings()
	return not first_boot_done


static func finish_first_boot() -> void:
	load_settings()
	first_boot_done = true
	save()


# ---------------------------------------------------------------- text size

## Smallest pixel-font size (issue #149). Valve asks for text at least 9 pixels tall at the Steam
## Deck's 1280x800; Jersey's capitals are 9 screen pixels tall from size 8 at that 2x scale, so on a
## Deck nothing is drawn smaller than 8 (hints and captions drawn at 6 or 7 elsewhere). 0 = no floor.
## Set by load_settings from DisplaySettings.on_deck().
const DECK_MIN_SIZE := 8
static var min_size := 0


static func text_scale() -> float:
	load_settings()
	return TEXT_SCALE[text_size]


## A font size scaled by the text size option. Every font size in the game goes through this, paired
## in the draw call and in the measuring call, so centred and wrapped text keeps lining up.
static func fs(size: int) -> int:
	if not _loaded:
		load_settings()
	if readable_font:
		# Atkinson's letters stand taller and wider than Jersey's at the same size: this keeps the readable
		# font at the pixel font's height, so layouts keep fitting and Text size still does the growing.
		# Its capitals at 7 are already 9 screen pixels tall at 1280x800, so the Deck floor isn't needed.
		return maxi(7, roundi(size * TEXT_SCALE[text_size] * READABLE_SCALE))
	if text_size == 0:
		return maxi(size, min_size)
	return maxi(maxi(size, min_size), roundi(size * TEXT_SCALE[text_size]))


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


# ---------------------------------------------------------------- readable font

## The two faces every text in the game is drawn with: the project font (body.tres, the theme's custom
## font and so ThemeDB.fallback_font) and UiSkin.TITLE_FONT (heading.tres). Both are FontVariations, so
## swapping their base font changes every label and draw_string at once, with no code at the call sites.
const BODY_FONT := preload("res://assets/fonts/body.tres")
const HEADING_FONT := preload("res://assets/fonts/heading.tres")
const PIXEL_BODY := preload("res://assets/fonts/Jersey10-Regular.ttf")
const PIXEL_HEADING := preload("res://assets/fonts/Jacquard12-Regular.ttf")
const READABLE_BODY := preload("res://assets/fonts/AtkinsonHyperlegible-Regular.ttf")
const READABLE_HEADING := preload("res://assets/fonts/AtkinsonHyperlegible-Bold.ttf")
const READABLE_SCALE := 0.86  # see fs()
const FONT_INFO := [
	"The game's pixel lettering (Jersey 10, headings in Jacquard 12).",
	"Atkinson Hyperlegible everywhere, headings too: plain, open letter shapes made for low vision.",
]


static func apply_font() -> void:
	load_settings()
	var body: Font = READABLE_BODY if readable_font else PIXEL_BODY
	var head: Font = READABLE_HEADING if readable_font else PIXEL_HEADING
	var body_var: FontVariation = BODY_FONT
	var head_var: FontVariation = HEADING_FONT
	if body_var.base_font != body:
		body_var.base_font = body
	if head_var.base_font != head:
		head_var.base_font = head
	# Labels and other Controls cache their shaped text; tell them the theme changed.
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)


# ---------------------------------------------------------------- camera

## How quickly cameras that follow someone catch up: snappier with reduced camera motion, so the view
## never drifts or sweeps after the hero.
static func follow_speed(normal: float) -> float:
	load_settings()
	return maxf(normal, 14.0) if reduce_motion else normal


## The share of the way a smoothed camera (the Command Table's pan and zoom) moves this frame:
## reduced camera motion jumps straight there instead of sweeping across the map.
static func ease_k(delta: float, speed: float) -> float:
	load_settings()
	return 1.0 if reduce_motion else 1.0 - exp(-delta * speed)


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
