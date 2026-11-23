extends "res://tests/test_case.gd"
## Accessibility part 2 (issue #192): the readable font, map markings without colour, reduced camera
## motion, captions and the menu-sound bus, rebinding every action (menu keys with a locked way back,
## clashes only where both keys can be pressed, one-handed layouts), the Controls page, and the assists
## (damage taken, enemy speed, healing between fights, skipping story fights, a gentler Blank).

const MAIN := "res://scenes/main.tscn"
const COMMAND := "res://scenes/command.tscn"
const DEV_ACTIONS := ["screenshot"]  # F12 for testers (diag.gd), not a game control

var _cfg_backup = null


func before_each() -> void:
	_cfg_backup = FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else null
	Access._loaded = true
	Access.reset()
	Assists._loaded = true
	Assists.reset()
	Settings.load_settings()
	Settings.difficulty = 1
	Settings.reset_bindings()
	autoload("Saves").pending = {}
	autoload("Empire").reset()
	autoload("Audio").captions = []


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0
	Access.reset()
	Assists.reset()
	Settings.reset_bindings()
	autoload("Audio").captions = []
	if _cfg_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_backup)
		f.close()
	Access._loaded = false
	Access.load_settings()
	Access.apply()
	Assists._loaded = false
	Assists.load_settings()
	Settings._loaded = false
	Settings.load_settings()
	Settings.apply_bindings()


func _keys(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(Settings._code(ev))
	return out


func _pads(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			out.append(int(ev.button_index))
	return out


func _launch(id: String) -> Node:
	Missions.launch(Missions.find(id))
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	await frames(5)
	if main.dialogue_box.visible:
		main.dialogue_box._close()  # the mission's opening talk
	await frames(3)
	return main


# ---------------------------------------------------------------- options

func test_options_persist() -> void:
	Access.readable_font = true
	Access.map_symbols = false
	Access.reduce_motion = true
	Access.captions = true
	Access.save()
	Assists.damage_i = 2
	Assists.pace_i = 1
	Assists.recover = true
	Assists.skip_fights = true
	Assists.blank_i = 1
	Assists.save()
	Settings.apply_layout(1)
	Settings.save()  # another screen saving its own options must not wipe these
	Access._loaded = false
	Access.load_settings()
	Assists._loaded = false
	Assists.load_settings()
	Settings._loaded = false
	Settings.load_settings()
	check(Access.readable_font and not Access.map_symbols and Access.reduce_motion and Access.captions, "accessibility options kept")
	check_eq([Assists.damage_i, Assists.pace_i, Assists.recover, Assists.skip_fights, Assists.blank_i], [2, 1, true, true, 1], "assists kept")
	check_eq(Settings.layout, 1, "keyboard layout kept")
	check(Assists.any_on(), "the Options row knows assists are on")
	Assists.reset()
	Access.reset()
	check(not Assists.any_on(), "assists reset")
	check(Access.map_symbols and not Access.readable_font and not Access.captions, "accessibility reset")


## The readable font swaps both faces everywhere: the project font every label and draw_string uses, and
## the heading face.
func test_readable_font() -> void:
	var body: FontVariation = ThemeDB.fallback_font as FontVariation
	check(body != null, "the project font is a FontVariation the option can swap")
	if body == null:
		return
	check(body == Access.BODY_FONT, "and it is assets/fonts/body.tres")
	check(UiSkin.TITLE_FONT == Access.HEADING_FONT, "headings use assets/fonts/heading.tres")
	check_eq(body.base_font, Access.PIXEL_BODY, "pixel font by default")
	var w_pixel := body.get_string_size("Hollowmark", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Access.readable_font = true
	Access.apply_font()
	check_eq(body.base_font, Access.READABLE_BODY, "body text in Atkinson Hyperlegible")
	var head: FontVariation = UiSkin.TITLE_FONT  # through a variable: GDScript folds CONST.property at compile time
	check_eq(head.base_font, Access.READABLE_HEADING, "headings in Atkinson Hyperlegible Bold")
	check(body.get_string_size("Hollowmark", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x != w_pixel, "measuring follows the new face")
	var lbl := Label.new()
	lbl.text = "Hollowmark"
	tree.root.add_child(lbl)
	await frames(2)
	check_eq(lbl.get_theme_font("font").get_rid(), body.get_rid(), "labels draw with the same face")
	lbl.queue_free()
	Access.readable_font = false
	Access.apply_font()
	check_eq(body.base_font, Access.PIXEL_BODY, "and back")


func test_reduce_motion() -> void:
	check(Access.ease_k(1.0 / 60.0, 9.0) < 0.5, "the map glides normally")
	check_eq(Access.follow_speed(7.0), 7.0, "the camera follows as designed")
	Access.reduce_motion = true
	check_eq(Access.ease_k(1.0 / 60.0, 9.0), 1.0, "reduced: the map jumps")
	check(Access.follow_speed(7.0) >= 14.0, "reduced: the camera sticks to the hero")
	var main := await _launch("meadow_patrol")
	if main == null:
		return
	await frames(2)
	check(main.camera.position_smoothing_speed >= 14.0, "in a mission")


# ---------------------------------------------------------------- map markings

func test_map_markings() -> void:
	var cmd := await goto(COMMAND, 20)
	if cmd == null:
		return
	# Every owner on the map has its own shape, so no two owners rely on colour to tell apart.
	var shapes := {}
	for owner in ["free", "erased"] + Array(autoload("Empire").faction_ids()):
		var shape: String = cmd.OWNER_MARKS.get(owner, "")
		check(shape != "", "%s has a map shape" % owner)
		check(not shapes.has(shape), "%s's shape (%s) is its own" % [owner, shape])
		shapes[shape] = true
	# Unravelling land is hatched on the map itself.
	var p: Dictionary = cmd.territory.find("oldmill")
	p["fray"] = 80
	Access.map_symbols = true
	cmd._bake()
	var on: Image = cmd.map_img
	Access.map_symbols = false
	cmd._bake()
	var off: Image = cmd.map_img
	var hatched := 0
	var cells := 0
	var elsewhere := 0
	for y in on.get_height():
		for x in on.get_width():
			var darker := on.get_pixel(x, y).get_luminance() < off.get_pixel(x, y).get_luminance() - 0.1
			if cmd.territory.cell(x, y) == p["index"] and (x + y) % 4 == 0:
				cells += 1
				hatched += 1 if darker else 0
			elif darker and cmd.territory.cell(x, y) >= 0 and int(cmd.territory.provinces[cmd.territory.cell(x, y)]["fray"]) < 60:
				elsewhere += 1
	check(cells > 0 and hatched > cells / 8, "an Unravelling province is hatched (%d of %d; the Blank has eaten the rest)" % [hatched, cells])
	check_eq(elsewhere, 0, "land below Unravelling is not hatched")
	Access.map_symbols = true
	cmd.queue_redraw()
	await frames(3)  # draws the marks, chips and legend without errors


# ---------------------------------------------------------------- captions and buses

func test_captions_and_buses() -> void:
	var audio := autoload("Audio")
	for bus in ["Music", "SFX", "UI", "Voice"]:
		check(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	check(Settings.BUSES.has("UI"), "menu sounds have their own volume")
	audio.sfx("hero_down")
	check(audio.captions.is_empty(), "captions off: nothing shows")
	Access.captions = true
	audio.sfx("hero_down")
	check_eq(audio.captions.size(), 1, "a captioned sound shows a caption")
	audio.sfx("hit")
	check_eq(audio.captions.size(), 1, "hits are not captioned")
	audio.sfx("alert", 1.0, 0.0, "Warning bell: test")
	check_eq(str(audio.captions[-1]["text"]), "Warning bell: test", "a caller can say what the sound means")
	audio.captions = []
	var alerts := Alerts.inst()
	if check(alerts != null, "the alerts node"):
		alerts.add("The Blank is gathering against Old Mill. Surge in 3 days.", true, {"province": "oldmill"})
		check(audio.captions.any(func(c): return str(c["text"]).contains("surge")), "a surge warning is captioned as one")
	audio.captions = []
	for i in 6:
		audio.caption("line %d" % i)
	check_eq(audio.captions.size(), audio.MAX_CAPTIONS, "only the newest few stay up")
	audio.caption("hum", Vector2.RIGHT, "hum")
	audio.caption("hum again", Vector2.RIGHT, "hum")
	check_eq(audio.captions.filter(func(c): return c["key"] == "hum").size(), 1, "a repeating sound refreshes its caption")
	audio._update_captions(10.0)
	check(audio.captions.is_empty(), "captions fade out")
	# The Blank's hum, with an arrow towards it.
	var main := await _launch("meadow_patrol")
	if main == null:
		return
	audio.unlocked = true
	var leader: Node2D = main.leader
	leader.global_position.x = main.blank.edge_x(leader.global_position.y) - 20.0
	await frames(90)
	var hum: Array = audio.captions.filter(func(c): return c["key"] == "hum")
	check(not hum.is_empty(), "the hum is captioned near the Blank")
	if not hum.is_empty():
		check(hum[0]["dir"].x > 0.5, "with an arrow pointing east, to the Blank")
	audio.captions = []


# ---------------------------------------------------------------- rebinding

func test_every_action_rebindable() -> void:
	Settings.apply_bindings()
	var listed := {}
	for a in Settings.REMAPPABLE:
		listed[a[0]] = true
		check(InputMap.has_action(a[0]), "%s exists" % a[0])
	# Every action the game defines is on the Controls page (Godot's own editor ui_* aside).
	for action in InputMap.get_actions():
		var id := str(action)
		if (id.begins_with("ui_") and not listed.has(id)) or id in DEV_ACTIONS:
			continue
		check(listed.has(id), "%s can be rebound" % id)


func test_menu_keys_keep_a_way_back() -> void:
	Settings.apply_bindings()
	Settings.bind_key("ui_accept", KEY_K)
	check(KEY_K in _keys("ui_accept"), "Confirm on K")
	check(KEY_ENTER in _keys("ui_accept"), "Enter still confirms")
	Settings.bind_key("ui_cancel", KEY_O)
	check(KEY_ESCAPE in _keys("ui_cancel"), "Escape still backs out")
	Settings.bind_key("pause", KEY_O)
	check(KEY_ESCAPE in _keys("pause"), "Escape still pauses")
	Settings.bind_key("ui_up", KEY_I)
	check(KEY_UP in _keys("ui_up"), "the arrow keys still move through menus")
	Settings.bind_pad("ui_accept", {"b": JOY_BUTTON_Y})
	check(JOY_BUTTON_A in _pads("ui_accept"), "A still confirms")
	Settings.bind_pad("ui_cancel", {"b": JOY_BUTTON_X})
	check(JOY_BUTTON_B in _pads("ui_cancel"), "B still backs out")
	Settings.bind_key("ui_cancel", KEY_ESCAPE)  # binding the fallback itself
	check_eq(_keys("ui_cancel").count(KEY_ESCAPE), 1, "no duplicate Escape")
	# Saved and put back on the next start.
	Settings._loaded = false
	Settings.load_settings()
	Settings.reset_bindings()
	check(not (KEY_K in _keys("ui_accept")), "reset takes K off Confirm")
	check(KEY_ENTER in _keys("ui_accept") and KEY_J in _keys("ui_accept"), "and Enter and J confirm again")


func test_clashes_only_where_both_are_used() -> void:
	Settings.apply_bindings()
	# The dialogue log shares the gamepad's Back with the quick menu: one only works in conversations.
	check(not Settings.clash("dialogue_log", "quick_menu"), "menu keys never clash with play keys")
	check(not Settings.clash("roster", "swap"), "town keys never clash with mission keys")
	check(Settings.clash("gear", "move_up"), "moving clashes with everything you can press while moving")
	check(Settings.clash("attack", "roster"), "so does Attack (it talks in town)")
	var swapped := Settings.bind_key("gear", KEY_W)
	check_eq(swapped, "move_up", "binding a town key to W swaps with Move up")
	check_eq(Settings.key_name("move_up"), "K", "Move up takes the old key")
	Settings.reset_bindings()
	swapped = Settings.bind_key("clock_speed_0", KEY_C)  # C is the quick menu, in missions only
	check_eq(swapped, "", "no swap across places that never meet")
	check(KEY_C in _keys("quick_menu"), "the quick menu keeps its key")
	Settings.reset_bindings()
	# An action with no key takes one from a clashing action, which gives it up.
	swapped = Settings.bind_key("map_pan_left", KEY_K)
	check_eq(swapped, "gear", "the gear key moves to map panning")
	check(not (KEY_K in _keys("gear")), "and Party gear gives it up instead of sharing it")
	Settings.reset_bindings()
	check(KEY_K in _keys("gear"), "reset gives it back")


func test_one_handed_layouts() -> void:
	Settings.apply_layout(1)
	check(KEY_SPACE in _keys("attack") and Settings.key_name("attack") == "Space", "left hand: attack on Space")
	check_eq(Settings.key_name("ui_cancel"), "Q", "left hand: back on Q")
	check(KEY_ESCAPE in _keys("ui_cancel"), "Escape still backs out")
	Settings.apply_layout(2)
	check_eq(Settings.key_name("attack"), "Enter", "right hand: attack on Enter")
	check_eq(Settings.key_name("move_up"), "Up", "right hand: move with the arrows")
	check_eq(Settings.key_name("ability_1"), OS.get_keycode_string(KEY_COMMA), "right hand: abilities beside the arrows")
	check(not (KEY_SPACE in _keys("attack") and Settings.key_name("attack") == "Space"), "the left layout is gone")
	Settings.bind_pad("swap", {"b": JOY_BUTTON_LEFT_SHOULDER})
	Settings.apply_layout(0)
	check_eq(Settings.key_name("attack"), "J", "default again")
	check_eq(Settings.pad_name("swap"), "LB", "a layout leaves the gamepad alone")


func test_controls_page() -> void:
	var host := Node.new()
	tree.root.add_child(host)
	var view := OptionsView.popup(host, "controls")
	await frames(2)
	var heads := view._rows.filter(func(r): return r["kind"] == "header")
	check(heads.size() >= 3, "the Controls page has headings (%d)" % heads.size())
	check(view._rows.any(func(r): return r["id"] == "dialogue_log"), "the dialogue log key is listed")
	check(view._rows.any(func(r): return r["id"] == "ui_accept" and str(r["key"]).contains("Enter")), "Confirm shows its locked Enter")
	check_eq(view._rows[0]["id"], "layout", "the layout comes first")
	for i in view._rows.size():
		view._move_sel(1)
		check(view._rows[view.sel]["kind"] != "header", "the highlight never lands on a heading")
	view.sel = 0
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	view._input(wheel)
	check_eq(view.sel, 2, "the mouse wheel scrolls (over the first heading)")
	view._activate(0)
	check_eq(Settings.layout, 1, "picking the layout row steps it")
	view.close()
	host.queue_free()
	await frames(2)


func test_assists_page() -> void:
	var host := Node.new()
	tree.root.add_child(host)
	var view := OptionsView.popup(host)
	await frames(2)
	var i: int = view._rows.map(func(r): return r["id"]).find("assists_page")
	check(i == view._rows.map(func(r): return r["id"]).find("difficulty") + 1, "Assists sit right under Difficulty")
	view._activate(i)
	check_eq(view.page, "assists", "it opens the Assists page")
	var ids: Array = view._rows.map(func(r): return r["id"])
	for id in ["difficulty", "as:damage", "as:pace", "as:recover", "as:skip", "as:blank"]:
		check(id in ids, "%s on the page" % id)
	view._step(ids.find("as:damage"), 1)
	view._step(ids.find("as:pace"), 1)
	view._activate(ids.find("as:recover"))
	check_eq([Assists.damage_i, Assists.pace_i, Assists.recover], [1, 1, true], "rows change the assists")
	for r in view._rows:
		var text := (str(r.get("label", "")) + " " + str(r.get("detail", "")) + " " + str(r.get("value", ""))).to_lower()
		for word in ["easy", "cheat", "baby", "casual", "weak"]:
			check(not text.contains(word), "no judging words on the Assists page: '%s' in %s" % [word, r["id"]])
	view._activate(view._rows.map(func(r): return r["id"]).find("as:reset"))
	check(not Assists.any_on(), "reset")
	view.close()
	host.queue_free()
	await frames(2)


# ---------------------------------------------------------------- assists

func test_damage_and_enemy_speed() -> void:
	var hero := Hero.new()
	var enemy := Enemy.new()
	check_eq(Settings.difficulty_damage(hero, 20), 20, "full damage by default")
	Assists.damage_i = 2
	check_eq(Settings.difficulty_damage(hero, 20), 10, "50% damage taken")
	check_eq(Settings.difficulty_damage(enemy, 20), 20, "enemies take what they always did")
	Settings.difficulty = 0
	check_eq(Settings.difficulty_damage(hero, 20), 5, "on top of Story difficulty")
	Settings.difficulty = 1
	check_eq(Settings.difficulty_damage(hero, 1), 1, "a hit never rounds down to nothing")
	hero.free()
	enemy.free()
	var main := await _launch("meadow_patrol")
	if main == null:
		return
	for e in main.entities.get_children():
		if e is Enemy:
			e.queue_free()
	await frames(2)
	var spawned: Array = EnemyKinds.spawn(main.entities, main.leader.global_position + Vector2(200, 0), {}, "nibbler")
	var n: Enemy = spawned[0]
	n.set_physics_process(false)
	await frames(1)
	var moved := []
	for pi in [0, 2]:
		Assists.pace_i = pi
		var from := n.global_position
		n.velocity = Vector2(60, 0)
		n._slide()
		moved.append(n.global_position.x - from.x)
		check_eq(n.velocity, Vector2(60, 0), "the enemy's own speed is kept for its logic")
	check(moved[0] > 0.0 and absf(moved[1] / moved[0] - 0.7) < 0.05, "Slowest moves at 70%% (%s)" % str(moved))


func test_heal_between_fights() -> void:
	var main := await _launch("meadow_patrol")
	if main == null:
		return
	for e in main.entities.get_children():
		if e is Enemy:
			e.queue_free()
	main.respawn_t = 1e9
	await frames(2)
	var h: Hero = main.leader
	h.hp = 5
	main._calm_t = main.RECOVER_WAIT + 1.0
	await frames(20)
	check_eq(h.hp, 5, "off: no healing")
	Assists.recover = true
	main._calm_t = main.RECOVER_WAIT - 0.1
	for i in 60:
		await tree.physics_frame
	check(h.hp > 5, "on: health comes back once it is quiet (%d)" % h.hp)
	h.hp = 5
	EnemyKinds.spawn(main.entities, h.global_position + Vector2(40, 0), {}, "nibbler")
	await frames(30)
	check(h.hp <= 5, "not with an enemy close by")


func test_skip_story_fight() -> void:
	var main := await _launch("meadow_prologue")
	if main == null:
		return
	check(not main._pause_items().any(func(it): return it["id"] == "skip"), "no skip without the assist")
	Assists.skip_fights = true
	check(main._pause_items().any(func(it): return it["id"] == "skip"), "the assist adds Skip this fight")
	main.set_paused(true)
	main._on_pause_choice("skip")
	for i in 120:
		await tree.process_frame
		if main.results_view.visible:
			break
	check(main.results_view.visible, "the results come up")
	if main.results_view.visible:
		var r: Dictionary = main.results_view.result
		check_eq(r.get("outcome", ""), "success", "the mission counts as won")
		check(r.get("lines", []).has(main.tr("Fight skipped.")), "the results say it was skipped, plainly")
	tree.paused = false
	autoload("Empire").reset()
	await frames(2)
	var patrol := await _launch("meadow_patrol")
	if patrol != null:
		check(not patrol._pause_items().any(func(it): return it["id"] == "skip"), "only story missions can be skipped")


## A boss's conversations (opening, turn, last words) still play when its fight is skipped.
func test_skip_boss_keeps_its_talks() -> void:
	Assists.skip_fights = true
	var main := await _launch("auditor_duel")
	if main == null:
		return
	main.skip_fight()
	var talks := 0
	for i in 600:
		await tree.process_frame
		if main.dialogue_box.visible:
			talks += 1
			main.dialogue_box._close()
		if main.results_view.visible:
			break
	check(talks >= 1, "the boss's conversations played (%d)" % talks)
	check(main.results_view.visible and main.results_view.result.get("outcome", "") == "success", "then the mission is won")


func test_gentle_blank() -> void:
	var E := autoload("Empire")
	E.reset()
	var t = E.territory()
	var pick: Dictionary = {}
	for p in t.provinces:
		if E.province_open(p) and p["owner"] != "erased" and E.fray_rate(p) >= 2:
			pick = p
			break
	if not check(not pick.is_empty(), "a province whose Fray grows"):
		return
	Assists.blank_i = 2
	var full: int = E.fray_rate(pick)
	var surge_full: int = E.surge_fray()
	Assists.blank_i = 1
	var gentle: int = E.fray_rate(pick)
	check(gentle < full and gentle > 0, "Gentle: Fray grows slower (%d instead of %d)" % [gentle, full])
	check(E.fray_sources(pick).any(func(s): return str(s[0]).contains("Gentle")), "and the province panel says why")
	check(E.surge_fray() < surge_full, "surges hit softer")
	Assists.blank_i = 0
	Settings.difficulty = 1
	check_eq(E.fray_rate(pick), full, "Auto on Normal: full pressure")
	Settings.difficulty = 0
	check_eq(E.fray_rate(pick), gentle, "Auto on Story: gentle")
	Settings.difficulty = 1
