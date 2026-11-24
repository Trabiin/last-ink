extends "res://tests/test_case.gd"
## Steam Deck and controller (issue #149, the parts that don't need Steam): the 1280x800 layout
## (16:10, the view is 640x400), Valve's smallest-text rule on a Deck, the Deck's first-start display
## defaults, the 16:10 window sizes and the 40 fps cap, the Command clock across a suspend, rumble
## (only your hero, only on a pad, the option) and every screen worked with nothing but gamepad
## buttons: real joypad events through the input map, no keyboard, mouse or test shortcuts.
## Screenshots at Deck size: SHOT_SIZE=1280x800 LASTINK_DECK=1 in test_access_shots.gd.

const TITLE := "res://scenes/title.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"
const DECK := Vector2i(1280, 800)

var _cfg_backup = null  # the real settings file, put back after each test


func before_each() -> void:
	_cfg_backup = FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else null
	autoload("Saves").pending = {}
	autoload("Empire").reset()
	Settings.reset_bindings()
	Settings.tips = false
	for t in Help.topics():
		Help.mark(t["id"])
	Access.first_boot_done = true


func after_each() -> void:
	tree.paused = false
	tree.root.size = Vector2i(1280, 720)
	DisplaySettings._deck_override = -1
	Access._loaded = false
	Access.load_settings()
	Settings.rumble_i = 2
	Rumble.last = {}
	Prompts.device = Prompts.KEYS
	if _cfg_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_backup)
		f.close()


# ---------------------------------------------------------------- real gamepad input

## A gamepad button pressed and let go, through the input map like a real pad.
func _pad(button: JoyButton) -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = pressed
		ev.pressure = 1.0 if pressed else 0.0
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames(1)
	await frames(1)


## A screen's focused row (the journal keeps one per tab).
func _sel(v: Control) -> int:
	var s = v.get("sel")
	if s is Dictionary:
		return int(s.get(v.get("tab"), 0))
	return int(s) if s != null else -1


## D-pad down through an InkMenu until the item with this id is selected.
func _menu_to(menu: InkMenu, id: String) -> bool:
	for k in 40:
		if menu.items[menu.selected].get("id", "") == id:
			return true
		await _pad(JOY_BUTTON_DPAD_DOWN)
	return false


## The Options screen a host opened (OptionsView.popup puts it on a CanvasLayer under the host).
func _options_in(host: Node) -> OptionsView:
	for c in host.find_children("*", "OptionsView", true, false):
		if c.visible:
			return c
	return null


func _table() -> Node:
	tree.root.size = DECK
	var Empire := autoload("Empire")
	for id in ["gristle", "ninefingers", "abeyance"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for k in Dialogue.data().get("talks", {}):
		Dialogue.mark_seen("talk:" + str(k))
	return await goto(COMMAND, 15)


# ---------------------------------------------------------------- 1280x800

func test_layout_fills_a_16_10_screen() -> void:
	var cmd := await _table()
	if not check(cmd != null, "the Command Table loads"):
		return
	var view: Vector2 = tree.root.get_visible_rect().size
	check_eq(view, Vector2(640, 400), "at 1280x800 the game lays out on 640x400 (more world above and below, no stretching)")
	await frames(3)
	var map: Rect2 = cmd._map_rect()
	check(map.end.y >= view.y - 10.0, "the territory map reaches the bottom of a 16:10 screen (ends at %d of %d)" % [map.end.y, view.y])
	check_eq(cmd.map_clip.size, map.size, "the map's clip window grows with it")
	var views := {"Roster": cmd.roster_view, "Buildings": cmd.buildings_view, "Expeditions": cmd.expedition_view,
		"Research": cmd.research_view, "Diplomacy": cmd.diplomacy_view, "Bonds": cmd.bonds_view,
		"Newcomers": cmd.newcomers_view, "Party gear": cmd.gear_view, "Forge & Market": cmd.armory_view, "Journal": cmd.journal_view}
	for name in views:
		var v: Control = views[name]
		if name == "Party gear":
			v.open("town")
		else:
			v.open()
		await frames(3)
		check(v.size.is_equal_approx(view), "%s covers the whole 640x400 screen (%s)" % [name, v.size])
		var rows = v.get("_row_rects")
		if rows is Array:
			for e in rows:
				var r = e[0] if e is Array else (e["rect"] if e is Dictionary else e)
				if r is Rect2 and r.size != Vector2.ZERO:
					check(Rect2(Vector2.ZERO, view).grow(0.5).encloses(r), "%s: row %s is on screen" % [name, r])
		v.close()
		await frames(2)


func test_smallest_text_on_a_deck() -> void:
	DisplaySettings._deck_override = 1
	Access._loaded = false
	Access.load_settings()
	Access.text_size = 0
	Access.readable_font = false
	check_eq(Access.min_size, Access.DECK_MIN_SIZE, "a Deck sets the smallest text size")
	for size in [6, 7, 8, 12]:
		check(Access.fs(size) >= 8, "pixel text drawn at %d is at least 8 on a Deck (capitals 9 screen pixels at 1280x800)" % size)
	check_eq(Access.fs(12), 12, "bigger text is left alone")
	Access.text_size = 1
	check(Access.fs(6) >= 8, "the floor holds at Large text too")
	Access.text_size = 0
	DisplaySettings._deck_override = 0
	Access._loaded = false
	Access.load_settings()
	Access.text_size = 0
	check_eq(Access.fs(6), 6, "elsewhere text keeps its designed size")
	# Measured, not assumed: Jersey's capitals at 8 are 9 screen pixels at the Deck's 2x scale.
	var font: Font = load("res://assets/fonts/body.tres")
	check(font.get_ascent(8) * 2.0 >= 9.0, "Jersey at size 8 stands at least 9 pixels tall at 2x")


func test_deck_display_defaults_and_choices() -> void:
	var D := DisplaySettings
	var before := [D.mode, D.size_i, D.fps_i]
	D._deck_override = 1
	D.mode = 0
	D.size_i = 0
	D.fps_i = 0
	D.deck_defaults()
	check_eq(D.MODES[D.mode], "Borderless", "a Deck starts filling the screen")
	check_eq(D.SIZES[D.size_i], DECK, "with the Deck's 1280x800 as the window size")
	check_eq(D.FPS_CAPS[D.fps_i], 60, "and a 60 fps cap (the Deck's screen is 60 Hz)")
	D._deck_override = 0
	D.mode = 0
	D.fps_i = 0
	D.deck_defaults()
	check_eq(D.mode, 0, "other machines keep the normal defaults")
	# 16:10 window sizes, stepped through by size; indexes of older saves unchanged.
	check_eq(D.SIZES[0], Vector2i(1280, 720), "saved size 0 is still 1280x720")
	check_eq(D.SIZES[5], Vector2i(3840, 2160), "saved size 5 is still 3840x2160")
	for s in [Vector2i(1280, 800), Vector2i(1920, 1200), Vector2i(2560, 1600)]:
		check(D.SIZES.has(s), "%s offered as a window size" % s)
	var order: Array = D.sizes()
	for k in order.size() - 1:
		var a: Vector2i = D.SIZES[order[k]]
		var b: Vector2i = D.SIZES[order[k + 1]]
		check(a.x * a.y <= b.x * b.y, "window sizes step from small to large")
	# The 40 fps lock, between 30 and 60 on the row.
	var fps := D.fps_order().map(func(i): return D.FPS_CAPS[i])
	check_eq(fps.slice(0, 4), [0, 30, 40, 60], "frame caps step Off, 30, 40, 60, ...")
	check_eq(D.FPS_CAPS[2], 60, "saved cap index 2 is still 60 fps")
	D._loaded = true
	D.fps_i = D.FPS_CAPS.find(30)
	D.step("fps", 1)
	check_eq(D.FPS_CAPS[D.fps_i], 40, "one step up from 30 is the 40 fps lock")
	D.step("fps", 1)
	check_eq(D.FPS_CAPS[D.fps_i], 60, "then 60")
	D.mode = before[0]
	D.size_i = before[1]
	D.fps_i = before[2]
	D.save()


func test_clock_survives_a_suspend() -> void:
	var Empire := autoload("Empire")
	Empire.set_speed(Empire.SPEEDS.size() - 1)
	var day: int = Empire.day
	var t: float = Empire.day_t
	Empire.tick_frame(3600.0 * 5)  # the first frame after five hours asleep (what the Command Table and town call)
	var moved: float = (Empire.day - day) + (Empire.day_t - t)
	var most: float = Empire.MAX_TICK * Empire.SPEEDS[Empire.speed] / Empire.DAY_SECONDS
	check(moved <= most + 0.0001, "waking from sleep moves the clock one short step, not five hours (%.3f days)" % moved)
	Empire.set_speed(1)


# ---------------------------------------------------------------- rumble

func _mission() -> Node:
	tree.root.size = DECK
	await goto(COMMAND, 10)
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	await frames(30)
	if main and main.dialogue_box.visible:
		main.dialogue_box._close()
		await frames(5)
	return main


func test_rumble_on_your_hero_only_and_the_option() -> void:
	var main := await _mission()
	if not check(main != null and main.leader != null, "a mission loads"):
		return
	var hero: Hero = main.leader
	Settings.rumble_i = 2
	Prompts.device = Prompts.PAD
	Rumble.last = {}
	Rumble._until = 0.0
	hero.invuln_t = 0.0
	hero.take_hit(8, hero.global_position + Vector2(10, 0))
	check(not Rumble.last.is_empty() and float(Rumble.last["strong"]) > 0.0, "your hero hurt rumbles the pad")
	var full: float = float(Rumble.last.get("strong", 0.0))
	var ally: Hero = null
	for h in main.heroes:
		if h != hero:
			ally = h
	if ally:
		Rumble.last = {}
		Rumble._until = 0.0
		ally.invuln_t = 0.0
		ally.take_hit(8, ally.global_position + Vector2(10, 0))
		check(Rumble.last.is_empty(), "an ally getting hit does not")
	Rumble._until = 0.0
	Rumble.tech(hero, true)
	check(not Rumble.last.is_empty(), "your tech rumbles")
	Rumble.last = {}
	Rumble._until = 0.0
	main.shake(6.0)
	check(not Rumble.last.is_empty(), "a boss-sized slam rumbles")
	Rumble.last = {}
	Rumble._until = 0.0
	main.shake(2.0)
	check(Rumble.last.is_empty(), "small shakes (every swing) don't, unless they are yours")
	Rumble._until = 0.0
	Settings.rumble_i = 1
	Rumble.hurt(hero, 0.1)
	check(float(Rumble.last.get("strong", 1.0)) < full, "Light is softer than Full")
	Rumble.last = {}
	Rumble._until = 0.0
	Settings.rumble_i = 0
	Rumble.hurt(hero, 0.5)
	check(Rumble.last.is_empty(), "Off never rumbles")
	Settings.rumble_i = 2
	Prompts.device = Prompts.KEYS
	Rumble.hurt(hero, 0.5)
	check(Rumble.last.is_empty(), "keyboard players never get a buzzing pad")
	Settings.shake_i = 0
	Prompts.device = Prompts.PAD
	Rumble._until = 0.0
	Rumble.hurt(hero, 0.5)
	check(not Rumble.last.is_empty(), "screen shake off keeps the rumble (separate options)")
	Settings.shake_i = 2


# ---------------------------------------------------------------- gamepad only

func test_title_with_a_pad() -> void:
	tree.root.size = DECK
	var title := await goto(TITLE, 20)
	if not check(title != null and title.get("menu") != null, "the title loads"):
		return
	var menu: InkMenu = title.menu
	check(await _menu_to(menu, "options"), "D-pad reaches Options")
	await _pad(JOY_BUTTON_A)
	var opts := _options_in(title)
	if check(opts != null, "A opens Options"):
		await _pad(JOY_BUTTON_B)
		check(not is_instance_valid(opts) or not opts.visible, "B closes Options")
	check(menu.visible, "back on the title menu")


func test_command_table_with_a_pad() -> void:
	var cmd := await _table()
	if not check(cmd != null, "the Command Table loads"):
		return
	await frames(3)
	# The map: the d-pad walks provinces, A opens one, B steps back.
	var start: int = cmd.selected
	for d in [JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP]:
		await _pad(d)
		if cmd.selected != start:
			break
	check(cmd.selected != start, "the d-pad moves between provinces")
	# Screens with their own button: Y roster, X govern, L3 buildings, R3 expeditions.
	for pair in [[JOY_BUTTON_Y, cmd.roster_view], [JOY_BUTTON_LEFT_STICK, cmd.buildings_view],
			[JOY_BUTTON_RIGHT_STICK, cmd.expedition_view]]:
		await _pad(pair[0])
		var v: Control = pair[1]
		if check(v.visible, "button %d opens %s" % [pair[0], v.name]):
			await _check_list(v, v.name)
	# Every other screen through the Start menu.
	for id in ["roster", "buildings", "research", "diplomacy", "bonds", "newcomers", "gear", "armory", "journal"]:
		await _pad(JOY_BUTTON_START)
		if not check(cmd.menu.visible, "Start opens the Command menu"):
			return
		if not check(await _menu_to(cmd.menu, id), "the d-pad reaches %s in the menu" % id):
			await _pad(JOY_BUTTON_B)
			continue
		if not cmd.menu.items[cmd.menu.selected].get("enabled", true):
			await _pad(JOY_BUTTON_B)  # still locked this early in the story: nothing to open
			continue
		await _pad(JOY_BUTTON_A)
		var v: Control = {"roster": cmd.roster_view, "buildings": cmd.buildings_view, "research": cmd.research_view,
			"diplomacy": cmd.diplomacy_view, "bonds": cmd.bonds_view, "newcomers": cmd.newcomers_view,
			"gear": cmd.gear_view, "armory": cmd.armory_view, "journal": cmd.journal_view}[id]
		if check(v.visible, "A on %s opens it" % id):
			await _check_list(v, id)
	# Help and Options from the menu, the Rumble row changed with the d-pad.
	await _pad(JOY_BUTTON_START)
	check(await _menu_to(cmd.menu, "options"), "the d-pad reaches Options")
	await _pad(JOY_BUTTON_A)
	var opts := _options_in(cmd)
	if check(opts != null, "A opens Options"):
		for k in 30:
			if opts._rows[opts.sel]["id"] == "rumble":
				break
			await _pad(JOY_BUTTON_DPAD_DOWN)
		check_eq(opts._rows[opts.sel]["id"], "rumble", "the d-pad reaches the Rumble row")
		Settings.rumble_i = 2
		await _pad(JOY_BUTTON_DPAD_LEFT)
		check_eq(Settings.rumble_i, 1, "d-pad left turns rumble down to Light")
		await _pad(JOY_BUTTON_A)
		check_eq(Settings.rumble_i, 2, "A cycles it")
		await _pad(JOY_BUTTON_B)
		check(not is_instance_valid(opts) or not opts.visible, "B leaves Options")
	check(cmd.menu.visible, "back on the Command menu")
	await _pad(JOY_BUTTON_B)
	check(not cmd.menu.visible and not tree.paused, "B closes the menu and the clock runs again")


## A list screen: the d-pad moves its focus, B closes it without opening anything underneath.
func _check_list(v: Control, name: String) -> void:
	await frames(2)
	var before := _sel(v)
	await _pad(JOY_BUTTON_DPAD_DOWN)
	if before >= 0:
		check(_sel(v) != before, "%s: the d-pad moves the focus" % name)
	await _pad(JOY_BUTTON_B)
	await frames(2)
	check(not v.visible, "%s: B closes it" % name)
	var cmd := tree.current_scene
	check(not cmd.menu.visible, "%s: closing it doesn't also open the menu" % name)


func test_mission_with_a_pad() -> void:
	var main := await _mission()
	if not check(main != null and main.leader != null, "a mission loads"):
		return
	await _pad(JOY_BUTTON_START)
	check(main.pause_menu.visible, "Start pauses the fight (paused %s, box %s)" % [tree.paused, main.dialogue_box.visible if main.get("dialogue_box") else "-"])
	await _pad(JOY_BUTTON_B)
	await frames(2)
	check(not main.pause_menu.visible, "B resumes")
	await _pad(JOY_BUTTON_BACK)
	await frames(2)
	if check(main.quick_menu != null and main.quick_menu.visible, "Back opens the quick menu"):
		var tab: int = main.quick_menu.tab
		await _pad(JOY_BUTTON_RIGHT_SHOULDER)
		check(main.quick_menu.tab != tab, "RB turns to the next tab")
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		check_eq(main.quick_menu.tab, tab, "LB turns back")
		await _pad(JOY_BUTTON_B)
		await frames(2)
		check(not main.quick_menu.visible, "B closes the quick menu")
	check(not tree.paused, "back in the fight")
	# A conversation, read through with A alone.
	main.play_talk("meadow_intro")
	await frames(5)
	if check(main.dialogue_box.visible, "a conversation opens"):
		for k in 60:
			if not main.dialogue_box.visible:
				break
			await _pad(JOY_BUTTON_A)
		check(not main.dialogue_box.visible, "A reads it through to the end")


func test_town_with_a_pad() -> void:
	tree.root.size = DECK
	var hub := await goto("res://scenes/hub.tscn", 20)
	if not check(hub != null and hub.get("menu") != null, "the town loads"):
		return
	if hub.get("dialogue_box") and hub.dialogue_box.visible:
		hub.dialogue_box._close()
		await frames(5)
	await _pad(JOY_BUTTON_START)
	check(hub.menu.visible, "Start opens the town menu")
	check(await _menu_to(hub.menu, "roster"), "the d-pad reaches Roster")
	await _pad(JOY_BUTTON_A)
	if check(hub.roster_view.visible, "A opens the roster"):
		await _pad(JOY_BUTTON_B)
		await frames(2)
		check(not hub.roster_view.visible, "B closes it")
	if hub.menu.visible:
		await _pad(JOY_BUTTON_B)
	await frames(2)
	check(not hub.menu.visible and not tree.paused, "back to walking round town")
