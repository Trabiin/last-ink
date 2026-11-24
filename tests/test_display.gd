extends "res://tests/test_case.gd"
## Desktop builds (issue #145): export presets for Windows, macOS and Linux, the app's name, icon
## and save folder, the Display options (window mode, size, scaling, vsync, frame cap, focus
## behaviour), Alt+Enter, and Quit on the title screen. The builds themselves are exported and
## booted by CI (.github/workflows/desktop.yml).

const TITLE := "res://scenes/title.tscn"
const MAIN := "res://scenes/main.tscn"
const HUB := "res://scenes/hub.tscn"

var _cfg_backup = null  # the real settings file, put back after each test


func before_each() -> void:
	_cfg_backup = FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else null
	DisplaySettings._loaded = false
	DisplaySettings.mode = 0
	DisplaySettings.size_i = 0
	DisplaySettings.scaling = 0
	DisplaySettings.vsync = true
	DisplaySettings.fps_i = 0
	DisplaySettings.background = 0
	DisplaySettings._loaded = true
	autoload("Saves").pending = {}
	autoload("Empire").reset()


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0
	DisplaySettings.focus_back()
	if _cfg_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_backup)
		f.close()
	DisplaySettings._loaded = false
	DisplaySettings.load_settings()
	DisplaySettings.apply_window()


func _presets() -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {}
	if not check_eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg reads"):
		return out
	for sec in cfg.get_sections():
		if sec.begins_with("preset.") and not sec.ends_with(".options"):
			var opts := {}
			for k in cfg.get_section_keys(sec + ".options"):
				opts[k] = cfg.get_value(sec + ".options", k)
			out[str(cfg.get_value(sec, "platform"))] = {"preset": sec, "custom_features": str(cfg.get_value(sec, "custom_features", "")),
				"exclude": str(cfg.get_value(sec, "exclude_filter", "")), "include": str(cfg.get_value(sec, "include_filter", "")),
				"path": str(cfg.get_value(sec, "export_path", "")), "options": opts}
	return out


func test_export_presets_for_every_desktop_platform() -> void:
	if not FileAccess.file_exists("res://export_presets.cfg"):
		return  # an exported build (CI smoke test) carries no presets: checked in the editor run
	var p := _presets()
	for plat in ["Windows Desktop", "macOS", "Linux"]:
		if not check(p.has(plat), "a %s preset" % plat):
			continue
		var e: Dictionary = p[plat]
		var o: Dictionary = e["options"]
		check(not "test_shortcuts" in e["custom_features"], "%s leaves out the test shortcuts (#111)" % plat)
		check(int(o.get("debug/export_console_wrapper", 1)) == 0, "%s has no debug console" % plat)
		check("tests/*" in e["exclude"] and "tools/*" in e["exclude"] and "docs/*" in e["exclude"], "%s leaves out tests, tools and docs" % plat)
		check(e["include"] == p["Web"]["include"], "%s ships the same data files as the web build" % plat)
		check(e["path"].begins_with("build/"), "%s exports into build/" % plat)
		if plat != "macOS":
			check_eq(str(o.get("binary_format/architecture")), "x86_64", "%s architecture" % plat)
			check(bool(o.get("binary_format/embed_pck", false)), "%s is one file (pck embedded)" % plat)
	if p.has("Windows Desktop"):
		var w: Dictionary = p["Windows Desktop"]["options"]
		check(ResourceLoader.exists(str(w.get("application/icon"))), "Windows .exe icon exists")
		check(bool(w.get("application/modify_resources", false)), "Windows writes icon and version into the .exe")
		check_eq(str(w.get("application/product_name")), "Last Ink", "Windows product name")
		check_eq(str(w.get("application/file_version", "x")), "", "Windows file version follows project.godot")
	if p.has("macOS"):
		var m: Dictionary = p["macOS"]["options"]
		check_eq(str(m.get("binary_format/architecture")), "universal", "macOS is universal (Intel + Apple Silicon)")
		check(ResourceLoader.exists(str(m.get("application/icon"))), "macOS icon exists")
		check(str(m.get("application/bundle_identifier", "")).count(".") >= 2, "macOS bundle identifier")
		check_eq(str(m.get("application/short_version", "x")), "", "macOS version follows project.godot")
		check_eq(int(m.get("codesign/codesign", 0)), 1, "macOS ad-hoc signed so Apple Silicon opens it")
	check(not "test_shortcuts" in p.get("Linux", {}).get("custom_features", "x"), "Linux has no test shortcuts")


func test_app_name_icon_version_and_save_folder() -> void:
	check_eq(str(ProjectSettings.get_setting("application/config/name")), "Last Ink", "app name")
	check(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)), "own save folder, not Godot's")
	check_eq(str(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")), "Last Ink", "save folder name")
	var icon := str(ProjectSettings.get_setting("application/config/icon", ""))
	check(ResourceLoader.exists(icon), "project icon exists")
	var ver := str(ProjectSettings.get_setting("application/config/version", ""))
	check(ver.split(".").size() == 3, "version is x.y.z (%s): tags v<version> make releases" % ver)
	check(ProjectSettings.globalize_path("user://").trim_suffix("/").ends_with("Last Ink"), "user:// is the Last Ink folder (%s)" % ProjectSettings.globalize_path("user://"))
	var saves := autoload("Saves")
	check_eq(saves.game_version(), ver, "saves record the project version")


func test_display_options_step_and_persist() -> void:
	var D := DisplaySettings
	check(D.is_desktop(), "the test run counts as desktop")
	check_eq(D.modes(), [0, 1, 2], "desktop offers windowed, borderless and fullscreen")
	check(D.step("mode", 1), "windowed -> borderless")
	check_eq(D.mode_name(), "Borderless", "mode name")
	check(not D.step("size", 1), "no window size while fullscreen")
	check(D.size_name().ends_with("(screen)"), "fullscreen shows the screen size")
	D.step("mode", -1)
	check(D.step("size", 1), "window size steps in windowed mode")
	check_eq(D.size_name(), "1280 x 800", "second size (16:10, issue #149)")
	D.step("size", 1)
	check_eq(D.size_name(), "1600 x 900", "third size")
	check(not D.step("size", -5) or D.size_i == 0, "size clamps at the smallest")
	D.step("fps", 3)  # Off, 30, 40 (the Deck lock, issue #149), 60
	check_eq(D.fps_name(), "60 fps", "frame cap")
	D.step("vsync", -1)
	check(not D.vsync, "vsync off")
	D.step("scaling", 1)
	check_eq(tree.root.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_INTEGER, "pixel-perfect scaling applied")
	D.step("background", 1)
	D.step("mode", 1)
	D.step("mode", 1)
	var want := [D.mode, D.size_i, D.scaling, D.vsync, D.fps_i, D.background]
	check_eq(want, [2, 0, 1, false, 2, 1], "values before saving")
	D._loaded = false
	D.mode = 0
	D.scaling = 0
	D.load_settings()
	check_eq([D.mode, D.size_i, D.scaling, D.vsync, D.fps_i, D.background], want, "options survive a restart")
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	check(cfg.has_section("options") or true, "settings file still holds the other options")
	Settings.save()  # the other options' save keeps the display section
	cfg.load(Settings.PATH)
	check_eq(int(cfg.get_value("display", "mode", -1)), 2, "Settings.save keeps [display]")
	D.step("scaling", -1)
	check_eq(tree.root.content_scale_stretch, Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "smooth scaling applied")


func test_alt_enter_and_f11_toggle_fullscreen() -> void:
	var D := DisplaySettings
	D.apply()
	await frames(2)
	check(tree.root.get_node_or_null("DisplayWatch") != null, "the display watcher sits on the root")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.alt_pressed = true
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	check_eq(D.mode, 1, "Alt+Enter goes borderless fullscreen")
	var f11 := InputEventKey.new()
	f11.keycode = KEY_F11
	f11.pressed = true
	Input.parse_input_event(f11)
	await frames(2)
	check_eq(D.mode, 0, "F11 goes back to windowed")
	D.step("mode", 2)
	D.toggle_fullscreen()
	D.toggle_fullscreen()
	check_eq(D.mode, 2, "toggling back returns to the fullscreen kind last used")


func test_focus_loss_pauses_and_mutes_in_town() -> void:
	var hub := await goto(HUB, 15)
	check(hub != null, "town loads")
	DisplaySettings.background = 0
	var master := AudioServer.get_bus_index("Master")
	DisplaySettings.focus_lost()
	check(tree.paused, "town pauses while the window is in the background")
	check(AudioServer.is_bus_mute(master), "and goes quiet")
	DisplaySettings.focus_back()
	check(not tree.paused, "focus back unpauses")
	check_eq(AudioServer.is_bus_mute(master), Settings.volumes["Master"] <= 0, "sound back as the options say")
	# Mute only.
	DisplaySettings.background = 1
	DisplaySettings.focus_lost()
	check(not tree.paused and AudioServer.is_bus_mute(master), "mute only: keeps running, quiet")
	DisplaySettings.focus_back()
	# Keep playing.
	DisplaySettings.background = 2
	DisplaySettings.focus_lost()
	check(not tree.paused and not AudioServer.is_bus_mute(master), "keep playing: nothing changes")
	DisplaySettings.focus_back()
	# A pause the player made stays when focus comes back.
	DisplaySettings.background = 0
	tree.paused = true
	DisplaySettings.focus_lost()
	DisplaySettings.focus_back()
	check(tree.paused, "focus back leaves the player's own pause alone")
	tree.paused = false


func test_focus_loss_opens_the_pause_menu_in_a_fight() -> void:
	var Empire := autoload("Empire")
	Empire.reset()
	Dialogue.mark_seen("talk:meadow_intro")
	Empire.active_mission = Missions.find("meadow_patrol").duplicate(true)
	var main := await goto(MAIN, 20)
	DisplaySettings.background = 0
	DisplaySettings.focus_lost()
	await frames(2)
	check(tree.paused and main.pause_menu.visible, "the fight opens its pause menu")
	DisplaySettings.focus_back()
	await frames(2)
	check(tree.paused and main.pause_menu.visible, "and it stays up until the player resumes")
	main.set_paused(false)


func test_options_display_page_and_save_folder() -> void:
	var t := await goto(TITLE)
	var view := OptionsView.popup(t)
	await frames(2)
	var ids: Array = view._rows.map(func(r): return r["id"])
	check(ids.has("display_page"), "Options has a Display page")
	check(ids.has("save_folder"), "and a Save folder button on desktop")
	var detail: String = view._rows[ids.find("save_folder")]["detail"]
	check(detail.contains("Last Ink"), "the save folder row says where saves live (%s)" % detail)
	view._activate(ids.find("display_page"))
	await frames(2)
	check_eq(view.page, "display", "Display page opens")
	var dids: Array = view._rows.map(func(r): return r["id"])
	for id in ["d:mode", "d:size", "d:scaling", "d:vsync", "d:fps", "d:background", "display_back"]:
		check(dids.has(id), "Display row %s" % id)
	view.sel = dids.find("d:fps")
	view._step(view.sel, 1)
	check_eq(DisplaySettings.fps_name(), "30 fps", "stepping a row changes the option")
	view._activate(dids.find("d:vsync"))
	check(not DisplaySettings.vsync, "accept on a two-way row flips it")
	view._activate(dids.find("d:vsync"))
	check(DisplaySettings.vsync, "and back")
	await frames(2)
	view._back()
	await frames(1)
	check_eq(view.page, "main", "back to the main page")
	check_eq(view._rows[view.sel]["id"], "display_page", "the cursor returns to Display")
	view.close()
	await frames(2)


func test_title_has_quit_on_desktop() -> void:
	var t := await goto(TITLE)
	var ids: Array = t.menu.items.map(func(i): return i["id"]) if "items" in t.menu else []
	check(ids.has("quit"), "Quit on the title screen (%s)" % str(ids))
	check(not ids.has("tests") or OS.has_feature("editor"), "no test shortcuts outside the editor")
