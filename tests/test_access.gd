extends "res://tests/test_case.gd"
## Accessibility (issue #34): the options persist, text size reaches every text the game draws, the first
## start shows the settings page, reduced flashing, patterned danger markers, Toggle and Hold-to-attack,
## the stick deadzone, the dialogue log and auto-advance. Screenshots at every text size:
## tests/test_access_shots.gd.

const TITLE := "res://scenes/title.tscn"
const MAIN := "res://scenes/main.tscn"
## Text that must keep its own size: the title logo (a fixed piece of art) and the faint words scribbled
## on the ground (scenery). Everything else a player reads goes through Access.fs.
const FIXED_SIZE_FILES := ["title.gd", "area.gd", "access.gd"]

var _cfg_backup = null


func before_each() -> void:
	_cfg_backup = FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else null
	Access._loaded = true
	Access.reset()
	autoload("Saves").pending = {}
	autoload("Empire").reset()


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0
	for a in ["attack"]:
		Input.action_release(a)
	if is_instance_valid(DialogueLog._open):
		DialogueLog._open.close()
	if _cfg_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_backup)
		f.close()
	Access._loaded = false
	Access.load_settings()
	Access.apply()


func _reload() -> void:
	Access._loaded = false
	Access.load_settings()


## Every option survives a restart and keeps the other sections of the settings file.
func test_options_persist() -> void:
	Settings.save()
	Access.text_size = 2
	Access.reduce_flashing = true
	Access.danger_patterns = false
	Access.tech_mode = 1
	Access.hold_attack = true
	Access.deadzone = 45
	Access.auto_advance = 2
	Access.save()
	Settings.save()  # another screen saving its own options must not wipe these
	_reload()
	check_eq(Access.text_size, 2, "text size")
	check(Access.reduce_flashing, "reduce flashing")
	check(not Access.danger_patterns, "danger markers")
	check_eq(Access.tech_mode, 1, "tech mode")
	check(Access.hold_attack, "hold to attack")
	check_eq(Access.deadzone, 45, "deadzone")
	check_eq(Access.auto_advance, 2, "auto-advance")
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	check(cfg.has_section("options"), "Settings' own section is still there")
	Access.reset()
	_reload()
	check_eq(Access.text_size, 0, "reset text size")
	check(Access.danger_patterns and not Access.reduce_flashing, "reset markers and flashing")


func test_text_scale() -> void:
	check_eq(Access.fs(10), 10, "Normal leaves sizes alone")
	Access.text_size = 1
	check_eq(Access.fs(10), 12, "Large is 20% bigger")
	check(Access.fs(7) > 7, "even tiny text grows")
	Access.text_size = 2
	check_eq(Access.fs(10), 14, "Largest is 40% bigger")
	check_eq(Access.px(13.0), 18.0, "line heights grow with it")
	check_eq(Access.fit(ThemeDB.fallback_font, "short", 10, 500.0), "short", "fit leaves short text")
	var trimmed := Access.fit(ThemeDB.fallback_font, "a rather long note that cannot fit", 10, 40.0)
	check(trimmed.ends_with("...") and ThemeDB.fallback_font.get_string_size(trimmed, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= 40.0, "fit trims: " + trimmed)


## Every font size the game draws or measures with goes through Access.fs, so a new screen can't
## forget the option. (Scans the source, like the translation check.)
func test_every_text_call_scales() -> void:
	var calls := RegEx.create_from_string("\\b(draw_string_outline|draw_string|draw_multiline_string|get_string_size|get_multiline_string_size)\\(")
	var bad := 0
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd") or f in FIXED_SIZE_FILES:
			continue
		var lines := FileAccess.get_file_as_string("res://scripts/" + f).split("\n")
		for i in lines.size():
			var line: String = lines[i]
			if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("func ") or "no-fs" in line:
				continue
			var n := calls.search_all(line).size()
			if n == 0:
				continue
			var both := line + (lines[i + 1] if i + 1 < lines.size() else "")  # arguments carried onto the next line
			var scaled := both.count("Access.fs(") + both.count("fsize") + both.count(", size") + both.count("Access.fit(")
			if scaled < n:
				bad += 1
				check(false, "scripts/%s:%d: font size not through Access.fs: %s" % [f, i + 1, line.strip_edges().left(90)])
	check(bad == 0, "%d text call(s) ignore the text size option" % bad)


## The first start shows the settings page before the title menu; Start (or backing out) closes it for good.
func test_first_start_page() -> void:
	Access.first_boot_done = false
	Access.save()
	_reload()
	check(Access.needs_first_boot(), "a fresh settings file asks")
	var title := await goto(TITLE, 10)
	title._first_boot()
	await frames(3)
	var view: OptionsView = _find_options(title)
	if not check(view != null, "the first-start page opened"):
		return
	check_eq(view.page, "first", "it is the short page")
	check(not title.menu.visible, "the title menu waits")
	var ids: Array = view._rows.map(func(r): return r["id"])
	for want in ["a:text", "a:flash", "difficulty", "a:danger", "a:tech", "start"]:
		check(want in ids, "first page has %s" % want)
	view._step(ids.find("a:text"), 1)
	check_eq(Access.text_size, 1, "text size changes from the page")
	view._activate(ids.find("a:flash"))
	check(Access.reduce_flashing, "flashing toggles from the page")
	view._activate(ids.find("start"))
	await frames(3)
	check(title.menu.visible, "the menu is back")
	_reload()
	check(not Access.needs_first_boot(), "never asked again")
	check_eq(Access.text_size, 1, "and the choice stuck")


func _find_options(n: Node) -> OptionsView:
	if n is OptionsView:
		return n
	for c in n.get_children():
		var f := _find_options(c)
		if f:
			return f
	return null


## The Accessibility page under Options: every row steps, wraps on accept and saves.
func test_options_page() -> void:
	var title := await goto(TITLE, 10)
	var view := OptionsView.popup(title)
	await frames(2)
	var ids: Array = view._rows.map(func(r): return r["id"])
	check("access_page" in ids, "Options lists Accessibility")
	view._activate(ids.find("access_page"))
	check_eq(view.page, "access", "the page opens")
	ids = view._rows.map(func(r): return r["id"])
	for want in ["a:text", "a:flash", "a:danger", "a:tech", "a:hold", "a:deadzone", "a:auto", "text_speed", "shake", "dialogue_log", "a:reset"]:
		check(want in ids, "page has %s" % want)
	view._activate(ids.find("a:tech"))
	check(Access.toggle_techs(), "techs to Toggle")
	view._activate(ids.find("a:tech"))
	check(not Access.toggle_techs(), "and back to Hold (wraps)")
	view._activate(ids.find("a:danger"))
	check(not Access.danger_patterns, "markers to colour only")
	view._step(ids.find("a:deadzone"), 1)
	check_eq(Access.deadzone, Access.DEADZONE_DEFAULT + 5, "deadzone steps by 5")
	check(is_equal_approx(InputMap.action_get_deadzone("move_left"), 0.35), "and reaches the stick actions")
	check(InputMap.action_get_deadzone("ui_left") >= 0.5, "menus keep their own floor")
	Access.text_size = 2
	view._rebuild()
	await frames(2)
	var shown := 0
	for r in view._row_rects:
		if (r as Rect2).size != Vector2.ZERO:
			check((r as Rect2).end.y <= view.get_viewport_rect().size.y, "a row stays on screen at Largest")
			shown += 1
	check(shown > 3 and shown <= view._rows.size(), "long pages scroll at Largest (%d shown)" % shown)
	view.sel = view._rows.size() - 1
	await frames(2)
	check((view._row_rects.back() as Rect2).size != Vector2.ZERO, "picking the last row scrolls to it")
	view._activate(ids.find("a:reset"))
	check(Access.danger_patterns and Access.deadzone == Access.DEADZONE_DEFAULT, "reset puts the defaults back")
	view._back()
	check_eq(view.page, "main", "back to the main page")
	view.close()


func test_reduce_flashing() -> void:
	check_eq(Access.flash(Color.RED), Color(1, 1, 1), "normal hit flash is white")
	check(Access.strobe(0.0, 8.0) != Access.strobe(1.0 / 16.0 + 0.001, 8.0), "normal tells blink")
	Access.reduce_flashing = true
	check(Access.flash(Color.RED) != Color(1, 1, 1), "reduced hit flash is a tint")
	for t in [0.0, 0.03, 0.07, 0.11]:
		check(Access.strobe(t, 8.0), "reduced tells hold still")
	check(Access.calm(1.0) < 0.5, "bright glows are lowered")
	var parent := Node2D.new()
	tree.root.add_child(parent)
	Fx.burst(parent, Vector2.ZERO, [Color.WHITE], 20)
	var fx: Fx = parent.get_child(0)
	check(fx.particles.size() < 20, "fewer sparks")
	for p in fx.particles:
		check((p[3] as Color) != Color.WHITE, "no pure white sparks")
	parent.queue_free()


## Toggle: one press starts the charge, letting go keeps it, the next press fires. Hold: letting go fires
## or swings. Hold to attack: a held button swings again once the gauge is full.
func test_tech_modes() -> void:
	autoload("Saves").pending = {}
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	if main == null:
		return
	for e in main.entities.get_children():
		if e is Enemy:
			e.queue_free()
	var h: Hero = main.leader
	await _ticks(5)
	if main.dialogue_box.visible:
		main.dialogue_box._close()  # the mission's opening talk
	await _ticks(3)
	Access.tech_mode = 1
	h.power = 1.0
	h.swing_t = 0.0
	Input.action_press("attack")
	await _ticks(2)
	check(h.charging, "Toggle: the press starts a charge")
	Input.action_release("attack")
	await _ticks(10)
	check(h.charging, "Toggle: letting go keeps charging")
	var start := Time.get_ticks_msec()
	while not h.charge_ready and Time.get_ticks_msec() - start < 4000:
		await tree.physics_frame
	check(h.charge_ready, "and it reaches the tech")
	Input.action_press("attack")
	await _ticks(2)
	Input.action_release("attack")
	check(not h.charging, "Toggle: the second press fires")
	check(h.power < 1.0, "the gauge was spent")
	await _ticks(30)
	Access.tech_mode = 0
	h.power = 1.0
	h.swing_t = 0.0
	Input.action_press("attack")
	await _ticks(3)
	check(h.charging, "Hold: the press starts a charge")
	Input.action_release("attack")
	await _ticks(2)
	check(not h.charging, "Hold: letting go ends it")
	# Hold to attack.
	await _ticks(40)
	Access.hold_attack = true
	h.power = 0.3
	h.swing_t = 0.0
	Input.action_press("attack")
	await _ticks(2)
	check(h.swing_t > 0.0 or h.power < 0.3, "the press swings")
	var swings := 0
	var was := h.power
	for i in 240:
		await tree.physics_frame
		if h.power < was - 0.5:
			swings += 1
		was = h.power
	Input.action_release("attack")
	check(swings >= 1, "holding swings again when the gauge fills (%d)" % swings)
	check(not h.charging, "a held button never turns into a charge")
	check(Techs.how_to() != "", "the HUD can say how")


## Waits n physics ticks (the hero reads its buttons there; headless frames can outrun them).
func _ticks(n: int) -> void:
	for i in n:
		await tree.physics_frame


func test_dialogue_log_records() -> void:
	DialogueLog.clear()
	var viewer := RefCounted.new()
	var line := ["bran", "Hello there.", ""]
	DialogueLog.track(viewer, line)
	DialogueLog.track(viewer, line)
	check_eq(DialogueLog.entries.size(), 1, "a line is written once while it shows")
	DialogueLog.track(viewer, ["", "Wind.", ""])
	DialogueLog.track(viewer, ["bran", "", ""])
	check_eq(DialogueLog.entries.size(), 2, "narration counts, empty lines don't")
	DialogueLog.add("bran", "Hello again.")
	DialogueLog.add("bran", "Hello again.")
	check_eq(DialogueLog.entries.size(), 3, "a repeat in a row is dropped")
	for i in DialogueLog.MAX_ENTRIES + 20:
		DialogueLog.add("bran", "Line %d" % i)
	check_eq(DialogueLog.entries.size(), DialogueLog.MAX_ENTRIES, "capped")
	autoload("Empire").reset()
	check(DialogueLog.entries.is_empty(), "a new game or a load clears it")


## A real conversation writes its lines as they show, opens the log on its key and waits under it;
## auto-advance moves on by itself.
func test_dialogue_box_log_and_auto() -> void:
	DialogueLog.clear()
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	if main == null:
		return
	main.play_talk("meadow_intro")
	await frames(5)
	var box = main.dialogue_box
	check(box.visible, "the talk is up")
	check_eq(DialogueLog.entries.size(), 1, "the first line is logged")
	box._advance()
	box._advance()
	await frames(3)
	check_eq(DialogueLog.entries.size(), 2, "the next line is logged when it shows")
	DialogueLog.ensure_action()
	Input.action_press(DialogueLog.ACTION)
	await frames(2)
	Input.action_release(DialogueLog.ACTION)
	check(DialogueLog.is_open(), "Backspace / Back opens the log")
	var at: int = box._at
	box._shown = 99999.0
	await frames(10)
	check_eq(box._at, at, "the conversation waits under the log")
	var log: DialogueLog = DialogueLog._open
	log.scroll = 0.0
	log._scroll_by(1000.0)
	check(log.scroll >= 0.0, "scrolling stays in range")
	log.close()
	await frames(2)
	check(not DialogueLog.is_open(), "it closes")
	Access.auto_advance = 3  # Fast
	box._shown = 99999.0
	await frames(2)
	var before: int = box._at
	var waited := 0
	while box._at == before and waited < 400 and box.visible:
		await tree.process_frame
		waited += 1
	check(box._at != before or not box.visible, "auto-advance moves on by itself")
	check(waited > 30, "but not at once (%d frames)" % waited)
	box._close()
	await frames(2)


## Danger markers draw in both styles over a real fight, and no enemy draws its own red "!" any more.
func test_danger_markers() -> void:
	for f in ["enemy.gd", "enforcer.gd", "spitter.gd", "moth.gd", "auditor.gd", "struck_line.gd"]:
		var src := FileAccess.get_file_as_string("res://scripts/" + f)
		check(not "\"!\"" in src, "%s draws its tell through Telegraph" % f)
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	if main == null:
		return
	var spawned := []
	for kind in ["enforcer", "spitter", "nibbler", "moth"]:
		spawned.append_array(EnemyKinds.spawn(main.entities, main.leader.global_position + Vector2(60, 0), {}, kind))
	for e in spawned:
		e.set("state", Enemy.State.WINDUP)
		e.set("state_t", 0.4)
		if e.get("aim") != null:
			e.set("aim", Vector2.LEFT * 20.0)
	for patterns in [true, false]:
		Access.danger_patterns = patterns
		for e in spawned:
			if is_instance_valid(e):
				e.queue_redraw()
				e.overlay.queue_redraw()
		await frames(3)
	check(Telegraph.patterned() == false, "the option reaches the markers")
	var seg := Telegraph._clip(Vector2(-10, 5), Vector2(20, 5), Rect2(0, 0, 10, 10))
	check(seg.size() == 2 and seg[0].x == 0.0 and seg[1].x == 10.0, "stripes are clipped to their zone")
