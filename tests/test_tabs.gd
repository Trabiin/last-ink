extends "res://tests/test_case.gd"
## Tab rows (TabStrip, scripts/tab_strip.gd): every tabbed screen shows its switch keys beside the tabs,
## read from the live bindings and the device in use, and switches the same way (tab_prev / tab_next,
## a tap on a tab or on either glyph).
##
## Screenshots of every tab row on each device (needs a display, not --headless):
##   TAB_SHOTS=/tmp/tabs [TEXT_SIZE=2] xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- test_tabs

const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"


func after_each() -> void:
	Prompts.device = Prompts.KEYS
	Prompts.pad_style = "xbox"
	Settings.reset_bindings()


func test_glyphs_follow_device_and_bindings() -> void:
	Settings.reset_bindings()
	Prompts.device = Prompts.KEYS
	check_eq(TabStrip.glyph_label(TabStrip.PREV), "Q", "keyboard: Q for the tab to the left")
	check_eq(TabStrip.glyph_label(TabStrip.NEXT), "E", "keyboard: E for the tab to the right")
	Prompts.device = Prompts.PAD
	Prompts.pad_style = "xbox"
	check_eq(TabStrip.glyph_label(TabStrip.PREV), "LB", "Xbox pad: LB")
	check_eq(TabStrip.glyph_label(TabStrip.NEXT), "RB", "Xbox pad: RB")
	Prompts.pad_style = "playstation"
	check_eq(TabStrip.glyph_label(TabStrip.PREV), "L1", "PlayStation pad: L1")
	check_eq(TabStrip.glyph_label(TabStrip.NEXT), "R1", "PlayStation pad: R1")
	Prompts.device = Prompts.TOUCH
	check_eq(TabStrip.glyph_label(TabStrip.NEXT), "", "touch: an arrow to tap instead of a key")
	Prompts.device = Prompts.KEYS
	Settings.bind_key("tab_next", KEY_O)
	check_eq(TabStrip.glyph_label(TabStrip.NEXT), "O", "a rebound key shows at once")
	check(Settings.group_of("tab_prev") == "menu" and Settings.group_of("tab_next") == "menu", "tab keys are menu keys")


func test_hit_and_step() -> void:
	var s := TabStrip.new(["A", "B", "C"], 0)
	var ci := Control.new()
	tree.root.add_child(ci)
	ci.draw.connect(func(): s.draw(ci, ThemeDB.fallback_font, Vector2(10, 4), 9))
	ci.queue_redraw()
	await frames(2)
	check_eq(s.rects.size(), 3, "a rect per tab")
	check_eq(s.hit((s.rects[2] as Rect2).get_center()), 2, "tapping a tab picks it")
	check_eq(s.hit(s.prev_rect.get_center()), 2, "the left glyph wraps round to the last tab")
	check_eq(s.hit(s.next_rect.get_center()), 1, "the right glyph steps right")
	check(s.prev_rect.end.x <= (s.rects[0] as Rect2).position.x and s.next_rect.position.x >= (s.rects[2] as Rect2).end.x,
		"the glyphs sit either side of the tabs")
	check_eq(s.hit(Vector2(-50, -50)), -1, "a tap elsewhere picks nothing")
	ci.queue_free()


func test_every_tabbed_screen_switches_the_same_way() -> void:
	Settings.reset_bindings()
	Settings.tips = false
	for t in Help.topics():
		Help.mark(t["id"])
	autoload("Saves").pending = {}
	autoload("Empire").reset()
	var cmd := await goto(COMMAND, 15)
	if not check(cmd != null, "the Command Table loads"):
		return
	var g: GearView = cmd.gear_view
	g.open("town")
	await frames(3)
	await _press("tab_next")
	check_eq(g.tab, "skills", "gear: E / RB moves to Skills")
	await _press("tab_prev")
	check_eq(g.tab, "equip", "gear: Q / LB comes back to Equip")
	await _press("tab_next")
	await _press("tab_next")
	check(g._tree != null, "gear: on to the Tree tab, which opens the skill tree")
	if g._tree != null:
		await frames(2)
		check(g._tree.tabs != null and g._tree.tabs.rects.size() == g._tabs().size(), "the skill tree shows the gear tab row")
		await _press("tab_next")
		await frames(2)
		check(g._tree == null, "the skill tree steps on to the next tab")
		check_eq(g.tab, g._tabs()[posmod(g._tabs().find("tree") + 1, g._tabs().size())], "and lands on the tab after Tree")
	g.close()
	await frames(2)
	var a = cmd.armory_view
	a.open("forge")
	await frames(3)
	await _press("tab_next")
	check_eq(a.tab, "market", "Forge & Market: E / RB moves on")
	await _press("tab_prev")
	check_eq(a.tab, "forge", "Forge & Market: Q / LB comes back")
	a.close()
	await frames(2)
	var x = cmd.expedition_view
	x.open("board")
	await frames(3)
	await _press("tab_next")
	check_eq(x.page, "board", "Expeditions: no reports yet, so the board stays")
	autoload("Empire").reports.append({"day": 1, "job": autoload("Empire").job_ids()[0], "title": "Test", "outcome": "success", "lines": [], "read": true})
	await _press("tab_next")
	check_eq(x.page, "reports", "Expeditions: E / RB opens the reports")
	await _press("tab_prev")
	check_eq(x.page, "board", "Expeditions: and back to the board")
	x.close()
	autoload("Empire").reports.clear()
	await frames(2)
	await _shots(cmd)


func _press(action: String) -> void:
	Input.action_press(action)
	await frames(1)
	Input.action_release(action)
	await frames(1)


# ---------------------------------------------------------------- screenshots (TAB_SHOTS only)

func _shots(cmd: Node) -> void:
	var dir := OS.get_environment("TAB_SHOTS")
	if dir == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	Access.text_size = clampi(int(OS.get_environment("TEXT_SIZE")), 0, Access.TEXT_SIZES.size() - 1)  # 2 = Largest
	var devices := [["keys", Prompts.KEYS, "xbox"], ["xbox", Prompts.PAD, "xbox"], ["ps", Prompts.PAD, "playstation"], ["touch", Prompts.TOUCH, "xbox"]]
	for d in devices:
		Prompts.device = d[1]
		Prompts.pad_style = d[2]
		cmd.gear_view.open("town")
		await _shot(dir, "gear_%s" % d[0])
		cmd.gear_view._set_tab("tree")
		await _shot(dir, "tree_%s" % d[0])
		if cmd.gear_view._tree != null:
			cmd.gear_view._tree.close()
		cmd.gear_view.close()
		cmd.armory_view.open()
		await _shot(dir, "armory_%s" % d[0])
		cmd.armory_view.close()
		cmd.journal_view.open()
		await _shot(dir, "journal_%s" % d[0])
		cmd.journal_view.close()
		cmd.expedition_view.open()
		await _shot(dir, "expeditions_%s" % d[0])
		cmd.expedition_view.close()
	for k in Dialogue.data().get("talks", {}):
		Dialogue.mark_seen("talk:" + str(k))
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	await frames(30)
	for i in 20:  # click through any opening narration
		if not main.get_tree().paused:
			break
		await _press("ui_accept")
		await frames(5)
	for d in devices:
		Prompts.device = d[1]
		Prompts.pad_style = d[2]
		main.open_quick_menu()
		await _shot(dir, "quick_%s" % d[0])
		main.quick_menu.close()
		await frames(3)
	Prompts.device = Prompts.KEYS
	Access.text_size = 0


func _shot(dir: String, name: String) -> void:
	await frames(4)
	var img := tree.root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [dir, name])
