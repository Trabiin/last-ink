extends "res://tests/test_case.gd"
## Visible focus (issue #192): every list screen can be worked with the keyboard or a pad, the mouse
## (hover moves the focus, a click picks, the wheel scrolls) and touch (tap, tap again; drag scrolls),
## and the focused row is always drawn on screen, at every text size and with either font.

const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"

var _log := []


func after_each() -> void:
	tree.root.size = Vector2i(1280, 720)
	Access.text_size = 0
	Access.readable_font = false
	Access.apply_font()


## A key or button press as the game sees it (both _input listeners and is_action_just_pressed).
func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames(1)
	await frames(1)


## [rect, index] for every row a screen drew last frame.
func _rows(v: Control) -> Array:
	var out := []
	var raw: Array = v.get("_row_rects")
	var idx = v.get("_row_index")
	for i in raw.size():
		var e = raw[i]
		if e is Array:
			out.append([e[0], int(e[1])])
		elif e is Dictionary:
			out.append([e["rect"], int(e["index"])])
		elif e is Rect2 and e.size != Vector2.ZERO:
			out.append([e, int(idx[i]) if idx is Array and i < idx.size() else i])
	if v.get("_go_rect") is Rect2:  # the party picker's "Set out" button is the row after the heroes
		out.append([v.get("_go_rect"), raw.size()])
	return out


## The focused row (the journal keeps one per tab).
func _sel(v: Control) -> int:
	var s = v.get("sel")
	if s is Dictionary:
		return int(s.get(v.get("tab"), 0))
	return int(s)


func _rect_of(v: Control, i: int) -> Rect2:
	for r in _rows(v):
		if r[1] == i:
			return r[0]
	return Rect2()


## Mouse events straight to the screen (the quick menu reads them in _input, the rest in _gui_input).
func _send(v: Control, ev: InputEvent) -> void:
	if v is QuickMenu:
		v._input(ev)
	else:
		v._gui_input(ev)


func _motion(v: Control, p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	_send(v, ev)
	await frames(2)


func _wheel(v: Control, p: Vector2, down := true) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = p
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
	_send(v, ev)
	await frames(2)


## Rows the focus can land on (the quick menu skips greyed-out ones).
func _focusable(v: Control, r: Array) -> bool:
	var rows = v.get("rows")
	if v is QuickMenu and rows is Array and r[1] < rows.size():
		return rows[r[1]].get("enabled", true)
	return true


## A real finger: through the input system, in window pixels (the screen is drawn at 2x).
func _tap(v: Control, p: Vector2) -> void:
	var at := v.get_global_transform_with_canvas() * p * (Vector2(tree.root.size) / tree.root.get_visible_rect().size)
	for pressed in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.position = at
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await frames(1)
	await frames(1)


## Back to the top with the arrow keys, then the wheel (or a finger pushing the list up) over the list
## must bring rows into view that were not drawn before.
func _scroll_check(tag: String, v: Control, how: String, first: int) -> void:
	for k in 80:
		if _sel(v) == first:
			break
		await _press("ui_up")
	var before := {}
	for r in _rows(v):
		before[r[1]] = true
	var at: Vector2 = (_rows(v)[0][0] as Rect2).get_center()
	for k in 40:
		if how == "wheel":
			await _wheel(v, at)
		else:
			await _drag(v, at, -80.0)
	var fresh := _rows(v).filter(func(r): return not before.has(r[1]))
	check(not fresh.is_empty(), "%s: the %s scrolls the list to rows out of sight" % [tag, how])


## A finger moved up by dy (negative) in small steps.
func _drag(v: Control, at: Vector2, dy: float) -> void:
	var scale := Vector2(tree.root.size) / tree.root.get_visible_rect().size
	var p := v.get_global_transform_with_canvas() * at * scale
	var down := InputEventScreenTouch.new()
	down.position = p
	down.pressed = true
	Input.parse_input_event(down)
	for k in 4:
		var ev := InputEventScreenDrag.new()
		ev.relative = Vector2(0, dy / 4.0) * scale
		p += ev.relative
		ev.position = p
		Input.parse_input_event(ev)
	var up := InputEventScreenTouch.new()
	up.position = p
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await frames(2)


## The whole audit for one list screen. `down` is the action that moves the focus down its list.
func _audit(name: String, v: Control, down := "ui_down", tap_focuses := true) -> void:
	var tag := "%s (text %d, font %s)" % [name, Access.text_size, "readable" if Access.readable_font else "pixel"]
	await frames(3)
	print("  audit %s: %s" % [tag, v.size])
	var rows := _rows(v)
	if not check(rows.size() >= 2, "%s: draws at least two rows to audit" % tag):
		return
	var start: int = _sel(v)
	# Keyboard / pad: the focus moves, and it can reach the last row while staying on screen.
	await _press(down)
	check(_sel(v) != start, "%s: %s moves the focus" % [tag, down])
	var seen := {}
	var view := v.get_viewport_rect() if v.size == Vector2.ZERO else Rect2(Vector2.ZERO, v.size)
	for k in 80:
		var r := _rect_of(v, _sel(v))
		check(r.size != Vector2.ZERO and view.encloses(r.grow(-0.5)),
			"%s: the focused row %d is drawn on screen (%s in %s)" % [tag, _sel(v), r, view])
		if seen.has(_sel(v)) or failures.size() > 0 and failures[-1].begins_with(tag):
			break
		seen[_sel(v)] = true
		await _press(down)
	# A list longer than the screen: the wheel and a finger drag reach the rows out of sight.
	var drawn := {}
	for r in _rows(v):
		drawn[r[1]] = true
	if seen.size() > drawn.size():
		await _scroll_check(tag, v, "wheel", seen.keys().min())
		await _scroll_check(tag, v, "drag", seen.keys().min())
	# Mouse: hovering a row moves the focus to it (one cursor, no separate hover look).
	rows = _rows(v).filter(func(r): return _focusable(v, r) and r[1] != _sel(v))
	if check(not rows.is_empty(), "%s: another row to point at" % tag):
		await _motion(v, (rows[0][0] as Rect2).get_center())
		check_eq(_sel(v), rows[0][1], "%s: hovering a row focuses it" % tag)
	if not tap_focuses:  # one tap acts here (the quick menu): covered by its own tests
		return
	# Touch: a tap focuses a row (a second tap acts; not tried here, it may open things).
	rows = _rows(v)
	var third: Array = rows[1] if rows[1][1] != _sel(v) else rows[0]
	await _tap(v, (third[0] as Rect2).get_center())
	check_eq(_sel(v), third[1], "%s: tapping a row focuses it" % tag)


## Opens every list screen on the Command Table and audits it.
func _audit_table(cmd: Node) -> void:
	var views := [["Roster", cmd.roster_view], ["Buildings", cmd.buildings_view], ["Expeditions", cmd.expedition_view],
		["Research", cmd.research_view], ["Diplomacy", cmd.diplomacy_view], ["Bonds", cmd.bonds_view],
		["Newcomers", cmd.newcomers_view], ["Forge & Market", cmd.armory_view], ["Journal", cmd.journal_view]]
	for pair in views:
		var v: Control = pair[1]
		if v == null:
			continue
		v.open()
		await frames(3)
		await _audit(pair[0], v)
		v.close()
		await frames(2)
	cmd.governor_view.open("hollowmark")
	await frames(3)
	await _audit("Governor", cmd.governor_view)
	cmd.governor_view.close()
	await frames(2)
	var help := HelpView.popup(cmd)
	await frames(3)
	await _audit("Help", help)
	help.queue_free()
	await frames(2)
	cmd._open_brief(Missions.find("meadow_patrol"))
	await frames(2)
	cmd._on_brief("go")
	await frames(3)
	await _audit("Party picker", cmd.party_picker)
	cmd.party_picker.close()
	await frames(2)


## The game's own screen (640 x 360 at 2x); a headless run would otherwise lay screens out on a taller
## window and hide a list running off the bottom.
func _screen(sz := Vector2i(1280, 720)) -> void:
	tree.root.size = sz
	await frames(2)


func _setup() -> Node:
	await _screen()
	Settings.reset_bindings()
	Settings.tips = false
	for t in Help.topics():
		Help.mark(t["id"])
	autoload("Saves").pending = {}
	var Empire := autoload("Empire")
	Empire.reset()
	for id in ["gristle", "ninefingers", "abeyance"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for k in Dialogue.data().get("talks", {}):
		Dialogue.mark_seen("talk:" + str(k))
	return await goto(COMMAND, 15)


func test_every_list_screen_normal_text() -> void:
	var cmd := await _setup()
	if not check(cmd != null, "the Command Table loads"):
		return
	await _audit_table(cmd)
	await _audit_quick_menu()


## The quick menu in a fight, with every item in the satchel: more rows than fit at Largest.
func _audit_quick_menu() -> void:
	var main := await goto(MAIN, 30)
	if not check(main != null and main.has_method("open_quick_menu"), "a mission loads"):
		return
	for id in Satchel.ids():
		autoload("Empire").satchel[id] = 1
	main.open_quick_menu()
	await frames(3)
	var q: QuickMenu = main.quick_menu
	q._set_tab(0)
	await _audit("Quick menu items", q, "ui_down", false)
	main.quick_menu.close()
	await frames(2)


func test_every_list_screen_largest_readable() -> void:
	Access.text_size = Access.TEXT_SIZES.size() - 1
	Access.readable_font = true
	Access.apply_font()
	var cmd := await _setup()
	if not check(cmd != null, "the Command Table loads"):
		return
	await _audit_table(cmd)
	await _audit_quick_menu()


## Party gear and the skill tree lay their rows out in their own way: pointing at a slot, a tech, a
## stall row or a tree node focuses it.
func test_gear_and_tree_follow_the_pointer() -> void:
	var cmd := await _setup()
	if not check(cmd != null, "the Command Table loads"):
		return
	var g: GearView = cmd.gear_view
	g.open("town")
	await frames(3)
	check(g._slot_rects.size() >= 2, "gear: slots drawn")
	if g._slot_rects.size() >= 2:
		g.slot_i = 0
		await _motion(g, (g._slot_rects[1] as Rect2).get_center())
		check_eq(g.slot_i, 1, "gear: hovering a slot focuses it")
	g._set_tab("skills")
	await frames(3)
	if check(g._tech_rects.size() >= 2, "gear: techs drawn"):
		g.tech_i = 0
		await _motion(g, (g._tech_rects[1] as Rect2).get_center())
		check_eq(g.tech_i, 1, "gear: hovering a tech focuses it")
	g._set_tab("shop")
	await frames(3)
	if check(g._shop_rects.size() >= 2, "gear: stall rows drawn"):
		g.shop_i = 0
		await _motion(g, (g._shop_rects[1] as Rect2).get_center())
		check_eq(g.shop_i, 1, "gear: hovering a stall row focuses it")
	g.close()
	await frames(2)
	var t := SkillTreeView.new()
	cmd.add_child(t)
	t.open("town")
	await frames(3)
	var keys: Array = t._node_rects.keys()
	if check(keys.size() >= 2, "tree: nodes drawn"):
		var k: String = keys[1] if keys[0] == t.sel else keys[0]
		await _motion(t, (t._node_rects[k] as Rect2).get_center())
		check_eq(t.sel, k, "tree: hovering a node focuses it")
		await _motion(t, t._reset_rect.get_center())
		check_eq(t.sel, SkillTreeView.RESET, "tree: hovering Reset focuses it")
	t.queue_free()
	await frames(2)
