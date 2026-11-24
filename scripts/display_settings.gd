class_name DisplaySettings
extends RefCounted
## Window and display options for the desktop builds (issue #145): window mode, window size,
## pixel-perfect scaling, vsync, a frame cap, and what happens when the window loses focus.
## Static like Settings, and saved in the same file (user://settings.cfg, section [display]).
##
## Settings.apply_all() calls apply() once from the title screen. apply() also puts a small
## watcher node on the root (it outlives scene changes) that handles Alt+Enter / F11 and the
## focus-lost pause and mute. The rows live on the options screen's Display page (OptionsView).
##
## The web build only offers what a browser allows: fullscreen on or off, scaling and the
## focus behaviour. Window size, vsync and the frame cap are the browser's business there.

const SECTION := "display"

## Window modes, in the order the options row cycles them.
const MODES := ["Windowed", "Borderless", "Fullscreen"]
const MODE_INFO := [
	"A normal window you can move and resize.",
	"Fills the screen without a border, so switching to other windows is instant.",
	"Exclusive fullscreen: the game takes the screen over. Can be a little smoother on some machines.",
]
## Window sizes for windowed mode: multiples of the 640x360 layout grid first, so pixels stay even.
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]
const SCALINGS := ["Smooth", "Pixel-perfect"]
const SCALING_INFO := [
	"Fills the window at any size. Pixels may be a hair uneven at odd sizes.",
	"Scales by whole numbers only, so every pixel is the same size. The view widens a little to fill the rest.",
]
const FPS_CAPS := [0, 30, 60, 90, 120, 144, 165, 240]  # 0 = no cap
const BACKGROUNDS := ["Pause and mute", "Mute only", "Keep playing"]
const BACKGROUND_INFO := [
	"Fights open the pause menu, the Command clock stops and the sound goes quiet while you are in another window.",
	"The game keeps running but the sound goes quiet while you are in another window.",
	"The game and its sound carry on while you are in another window.",
]

static var mode := 0
static var size_i := 0
static var scaling := 0
static var vsync := true
static var fps_i := 0
static var background := 0

static var _loaded := false
static var _watch: Node = null


## True on Windows, macOS and Linux builds (and the editor), false in the browser.
static func is_desktop() -> bool:
	return not OS.has_feature("web") and OS.has_feature("pc")


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	background = 0 if is_desktop() else 2  # a browser tab already pauses itself when hidden
	var cfg := ConfigFile.new()
	if cfg.load(Settings.PATH) != OK:
		return
	mode = clampi(int(cfg.get_value(SECTION, "mode", mode)), 0, MODES.size() - 1)
	size_i = clampi(int(cfg.get_value(SECTION, "size", size_i)), 0, SIZES.size() - 1)
	scaling = clampi(int(cfg.get_value(SECTION, "scaling", scaling)), 0, SCALINGS.size() - 1)
	vsync = bool(cfg.get_value(SECTION, "vsync", vsync))
	fps_i = clampi(int(cfg.get_value(SECTION, "fps_cap", fps_i)), 0, FPS_CAPS.size() - 1)
	background = clampi(int(cfg.get_value(SECTION, "background", background)), 0, BACKGROUNDS.size() - 1)
	if not is_desktop() and mode == 2:
		mode = 1  # the browser has one kind of fullscreen


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)  # keep the other options
	cfg.set_value(SECTION, "mode", mode)
	cfg.set_value(SECTION, "size", size_i)
	cfg.set_value(SECTION, "scaling", scaling)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.set_value(SECTION, "fps_cap", fps_i)
	cfg.set_value(SECTION, "background", background)
	cfg.save(Settings.PATH)


# ---------------------------------------------------------------- choices for the options rows

## Window modes this platform offers (indexes into MODES).
static func modes() -> Array:
	return [0, 1, 2] if is_desktop() else [0, 1]


static func mode_name(i: int = -1) -> String:
	load_settings()
	if i < 0:
		i = mode
	if not is_desktop():
		return Loc.t("Fullscreen") if i > 0 else Loc.t("In the page")
	return Loc.t(MODES[i])


static func mode_info() -> String:
	load_settings()
	if not is_desktop():
		return Loc.t("Fill the screen with the game, or keep it in the page. Esc leaves fullscreen in a browser.")
	return Loc.t(MODE_INFO[mode]) + "  " + Loc.t("Alt+Enter or F11 switches between windowed and fullscreen.")


## Window sizes that fit on the screen the window is on (always at least the smallest).
static func sizes() -> Array:
	var usable := Vector2i(1 << 20, 1 << 20)
	if DisplayServer.get_name() != "headless":
		usable = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var out := []
	for i in SIZES.size():
		if i == 0 or (SIZES[i].x <= usable.x and SIZES[i].y <= usable.y):
			out.append(i)
	return out


static func size_name() -> String:
	load_settings()
	if mode != 0:
		var s: Vector2i = DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()) if DisplayServer.get_name() != "headless" else SIZES[size_i]
		return Loc.t("%d x %d (screen)") % [s.x, s.y]
	return "%d x %d" % [SIZES[size_i].x, SIZES[size_i].y]


static func fps_name() -> String:
	load_settings()
	return Loc.t("Off") if FPS_CAPS[fps_i] == 0 else Loc.t("%d fps") % FPS_CAPS[fps_i]


## Steps one option by -1/+1 within what this platform offers, then applies and saves.
## Returns false when nothing changed (at the end of the list, or not available here).
static func step(id: String, dir: int) -> bool:
	load_settings()
	var before := [mode, size_i, scaling, vsync, fps_i, background]
	match id:
		"mode":
			mode = _step_in(modes(), mode, dir)
		"size":
			if mode != 0:
				return false
			size_i = _step_in(sizes(), size_i, dir)
		"scaling":
			scaling = clampi(scaling + dir, 0, SCALINGS.size() - 1)
		"vsync":
			vsync = dir > 0
		"fps":
			fps_i = clampi(fps_i + dir, 0, FPS_CAPS.size() - 1)
		"background":
			background = clampi(background + dir, 0, BACKGROUNDS.size() - 1)
	if before == [mode, size_i, scaling, vsync, fps_i, background]:
		return false
	apply_window(id == "size" or id == "mode")
	save()
	return true


static func _step_in(allowed: Array, current: int, dir: int) -> int:
	var at := allowed.find(current)
	if at < 0:
		return allowed[0]
	return allowed[clampi(at + dir, 0, allowed.size() - 1)]


## Alt+Enter / F11: windowed <-> the fullscreen kind last used (borderless unless set otherwise).
static func toggle_fullscreen() -> void:
	load_settings()
	if mode == 0:
		mode = _last_full
	else:
		_last_full = mode
		mode = 0
	apply_window(true)
	save()


static var _last_full := 1


# ---------------------------------------------------------------- applying

## Loads the options and puts every one of them into effect. Safe to call again.
static func apply() -> void:
	load_settings()
	_ensure_watch()
	apply_window(true)


## Window mode, size, scaling, vsync and frame cap. resize = also set the window size and
## centre it (only when the player changed the mode or size, never behind their back).
static func apply_window(resize := false) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if scaling == 1 else Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if DisplayServer.get_name() == "headless":
		return
	if is_desktop():
		var vs := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		if DisplayServer.window_get_vsync_mode() != vs:  # only on a change: some drivers warn on every set
			DisplayServer.window_set_vsync_mode(vs)
		Engine.max_fps = FPS_CAPS[fps_i]
	var want: DisplayServer.WindowMode = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN][mode]
	if not is_desktop() and mode > 0:
		want = DisplayServer.WINDOW_MODE_FULLSCREEN
	var now := DisplayServer.window_get_mode()
	if now != want:
		DisplayServer.window_set_mode(want)
		resize = resize or want == DisplayServer.WINDOW_MODE_WINDOWED
	if is_desktop() and want == DisplayServer.WINDOW_MODE_WINDOWED and resize:
		if not sizes().has(size_i):
			size_i = sizes().back()
		var screen := DisplayServer.window_get_current_screen()
		var area := DisplayServer.screen_get_usable_rect(screen)
		var sz: Vector2i = SIZES[size_i]
		DisplayServer.window_set_size(sz)
		DisplayServer.window_set_position(area.position + (area.size - sz) / 2)


static func _ensure_watch() -> void:
	if is_instance_valid(_watch):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_watch = DisplayWatch.new()
	_watch.name = "DisplayWatch"  # no-tr: node name
	tree.root.add_child.call_deferred(_watch)


# ---------------------------------------------------------------- focus

static var _paused_by_focus := false
static var _muted_by_focus := false


## The window lost focus: pause and/or mute as the player chose.
static func focus_lost() -> void:
	load_settings()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if background <= 1:
		var master := AudioServer.get_bus_index("Master")
		if master >= 0 and not AudioServer.is_bus_mute(master):
			AudioServer.set_bus_mute(master, true)
			_muted_by_focus = true
	if background == 0 and not tree.paused:
		var scene := tree.current_scene
		if scene and scene.has_method("pause_for_focus_loss"):
			scene.pause_for_focus_loss()  # a fight opens its pause menu, which stays up until the player resumes
		else:
			tree.paused = true
			_paused_by_focus = true


## The window has focus again: undo only what focus_lost() did.
static func focus_back() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if _muted_by_focus:
		_muted_by_focus = false
		Settings.apply_audio()
	if _paused_by_focus:
		_paused_by_focus = false
		if tree and tree.paused:
			tree.paused = false
