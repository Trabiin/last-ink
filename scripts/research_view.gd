extends Control
## Research screen (the Scriptorium). Opened with T, from the menus, the Research button on the
## Command Table, or by walking up to the Scriptorium in town.
##
## One plain list (Up/Down, Enter, Esc; mouse and touch tap): a branch of three nodes each for the four Hollowmark branches and every chapter branch.
## Enter on a node starts studying it (paying its cost the first time), Enter on the node being
## studied sets it aside. Study runs on the Command clock; researchers' Lore sets the pace.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const INSIGHT := Color("d7b8f0")
const ROW_H := 15.0
const HEAD_H := 13.0
const LIST_W := 318.0
const BRANCH_COLORS := {"wardcraft": Color("e8c66a"), "logistics": Color("b7c98a"), "inkcraft": Color("8fa7e8"), "arms": Color("e89a8a"), "abbey": Color("d98a7a")}

var sel := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _rows: Array = []  # node ids, in branch order
var _row_rects: Array = []
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	_rows.clear()
	for b in Empire.research_branches():
		for id in Empire.research_ids():
			if Empire.research_node(id)["branch"] == b["id"]:
				_rows.append(id)
	# Start on what is being studied, else the first thing you could start.
	sel = 0
	var first_free := -1
	for i in _rows.size():
		if _rows[i] == Empire.research_active:
			sel = i
			first_free = -2
			break
		if first_free == -1 and Empire.research_blocker(_rows[i]) == "":
			first_free = i
	if first_free >= 0:
		sel = first_free


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame or _rows.is_empty():
		return
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		sel = posmod(sel - 1, _rows.size())
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		sel = posmod(sel + 1, _rows.size())
	if Input.is_action_just_pressed("ui_accept"):
		_pick(sel)
	elif Input.is_action_just_pressed("research") or Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		close()


func _say(s: String) -> void:
	flash = s
	flash_t = 2.8


func _pick(i: int) -> void:
	var id: String = _rows[i]
	var n := Empire.research_node(id)
	match Empire.research_state(id):
		"done":
			_say(tr("Already known: %s.") % n["effect"])
		"active":
			Empire.shelve_research()
			_say(tr("Set aside %s. Progress is kept; %s again to resume.") % [n["name"], Prompts.confirm()])
		_:
			var why := Empire.research_blocker(id)
			if why != "":
				_say(tr("Can't: %s.") % why)
				return
			var prev := Empire.research_active
			var resumed: bool = id in Empire.research_paid
			if Empire.start_research(id):
				var msg := (tr("Resumed %s.") if resumed else tr("Started %s.")) % n["name"]
				if prev != "":
					msg += tr(" %s is set aside, progress kept.") % Empire.research_node(prev)["name"]
				if float(Empire.research_pace()["pace"]) <= 0.0:
					msg += tr(" Stalled until someone works the Scriptorium.")
				_say(msg)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
	elif Prompts.tapped(event):
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				if sel == i:
					_pick(i)  # tap to select, tap again to act (touch friendly)
				sel = i
				return
		if _close_rect().has_point(event.position):
			close()


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _text_r(right: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	_text(right - Vector2(w, 0), s, fsize, col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _bar(r: Rect2, f: float, col: Color) -> void:
	draw_rect(r, Color(0.14, 0.12, 0.16))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(f, 0.0, 1.0), r.size.y)), col)


## Little status mark at the start of a row.
func _mark(pos: Vector2, state: String) -> void:
	match state:
		"done":
			draw_line(pos + Vector2(0, -3), pos + Vector2(2, 0), GOOD, 1.5)
			draw_line(pos + Vector2(2, 0), pos + Vector2(7, -7), GOOD, 1.5)
		"active":
			draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -7), pos + Vector2(6, -3.5), pos + Vector2(0, 0)]), GOLD)
		"shelved":
			draw_rect(Rect2(pos + Vector2(0, -7), Vector2(2, 7)), SOFT)
			draw_rect(Rect2(pos + Vector2(4, -7), Vector2(2, 7)), SOFT)
		"locked":
			draw_rect(Rect2(pos + Vector2(0, -4), Vector2(6, 4)), DIM)
			draw_arc(pos + Vector2(3, -4), 2.2, PI, TAU, 6, DIM, 1.0)
		_:
			draw_circle(pos + Vector2(3, -3.5), 2.0, TEXT)


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	_row_rects.clear()

	_text(Vector2(8, 20), tr("Research"), 15, Color("f3efe4"))
	var daily := int(Empire.current_effect("scriptorium").get("insight", 0))
	_text(Vector2(84, 20), tr("Insight: %d banked, +%d a day") % [int(Empire.res.get("insight", 0)), daily], 9, INSIGHT)
	var pace := Empire.research_pace()
	var p := float(pace["pace"])
	var sub := ""
	var sub_col := GOLD
	if Empire.level_of("scriptorium") <= 0:
		sub = tr("Research happens in the Scriptorium. Build it first on the Buildings screen%s.") % Prompts.tag("buildings")
		sub_col = BAD
	elif p <= 0.0:
		sub = tr("Nobody is working the Scriptorium, so study is stalled. Give it a researcher (B, or R for the roster).")
		sub_col = BAD
	elif Empire.research_active == "":
		sub = tr("Nothing being studied. Pick a node and press %s. Study pace: %d%%.") % [Prompts.confirm(), int(round(p * 100))]
	else:
		var a := Empire.research_node(Empire.research_active)
		sub = tr("Studying %s: done in %s at %d%% pace.") % [a["name"], Empire.research_left_text(Empire.research_active), int(round(p * 100))]
	_text(Vector2(8, 34), sub, 8, sub_col)

	# The list, grouped by branch
	var y := 46.0
	var last_branch := ""
	for i in _rows.size():
		var id: String = _rows[i]
		var n := Empire.research_node(id)
		if n["branch"] != last_branch:
			last_branch = n["branch"]
			var b := {}
			for bb in Empire.research_branches():
				if bb["id"] == last_branch:
					b = bb
			y += HEAD_H
			_text(Vector2(10, y - 3), b.get("name", "?").to_upper(), 8, BRANCH_COLORS.get(last_branch, TEXT))
			_text(Vector2(84, y - 3), b.get("blurb", ""), 7, SOFT)
		var rr := Rect2(8, y, LIST_W, ROW_H - 2)
		_row_rects.append(rr)
		var on := i == sel
		draw_rect(rr, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(rr, GOLD, false, 1.0)
		var state := Empire.research_state(id)
		var base := rr.position + Vector2(0, 10)
		_mark(base + Vector2(6, 0), state)
		var col := TEXT
		if state == "locked":
			col = DIM
		elif state == "done":
			col = GOOD
		elif state == "active":
			col = GOLD
		var nx := 18.0
		if UiSkin.draw_icon(self, id, Rect2(rr.position + Vector2(15, 2), Vector2(14, 14)), Color(1, 1, 1, 0.4) if state == "locked" else Color.WHITE):
			nx = 34.0
		_text(base + Vector2(nx, 0), n["name"], 9, GOLD if on and state != "locked" else col, 148 - nx)
		match state:
			"done":
				_text(base + Vector2(150, 0), Loc.t("known"), 8, GOOD)
			"active", "shelved":
				var bx := Rect2(rr.position + Vector2(150, 4), Vector2(90, 5))
				_bar(bx, Empire.research_fraction(id), GOLD if state == "active" else SOFT)
				_text(Vector2(bx.end.x + 6, base.y), Empire.research_left_text(id) if state == "active" else tr("set aside"), 8, SOFT)
			_:
				var cost: Dictionary = n["cost"]
				_text(base + Vector2(150, 0), Empire.cost_text(cost), 8, (INSIGHT if Empire.can_afford(cost) else BAD) if state != "locked" else DIM)
				_text_r(base + Vector2(LIST_W - 6, 0), tr("%d day%s") % [int(n["days"]), "" if int(n["days"]) == 1 else "s"], 8, SOFT if state != "locked" else DIM)
		y += ROW_H

	_draw_details(vs)
	_text(Vector2(8, vs.y - 8), Prompts.help([["updown", "choose"], ["ui_accept", tr("study / set aside")], [["ui_cancel", "research"], "close"]], tr("Tap a node, tap again to study it")), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var w := font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		draw_rect(Rect2(vs.x - w - 18, vs.y - 21, w + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - w - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))


func _draw_details(vs: Vector2) -> void:
	if _rows.is_empty():
		return
	var id: String = _rows[sel]
	var n := Empire.research_node(id)
	var x := LIST_W + 22
	var w := vs.x - x - 10
	var top := 46.0
	draw_rect(Rect2(x - 8, top, w + 16, vs.y - top - 26), Color(0.08, 0.07, 0.1))
	draw_rect(Rect2(x - 8, top, 3, vs.y - top - 26), BRANCH_COLORS.get(n["branch"], TEXT))
	var y := top + 16
	UiSkin.draw_icon(self, id, Rect2(x + w - 34, top + 6, 32, 32))
	_text(Vector2(x, y), n["name"], 12, Color("f3efe4"), w - 40)
	y += 12
	var branch_name := ""
	for b in Empire.research_branches():
		if b["id"] == n["branch"]:
			branch_name = b["name"]
	_text(Vector2(x, y), branch_name, 8, BRANCH_COLORS.get(n["branch"], TEXT))
	y += 8
	y += _wrap(Vector2(x, y + 8), n["effect"] + ".", w, 9, GOOD) + 4
	y += _wrap(Vector2(x, y + 8), n["blurb"], w, 8, Color(0.78, 0.76, 0.74)) + 8
	var state := Empire.research_state(id)
	match state:
		"done":
			_text(Vector2(x, y + 8), tr("Known. Already working for you."), 9, GOOD)
		"active", "shelved":
			_text(Vector2(x, y + 8), tr("Studying now") if state == "active" else tr("Set aside (paid for, progress kept)"), 9, GOLD if state == "active" else SOFT)
			y += 14
			_bar(Rect2(x, y, w, 6), Empire.research_fraction(id), GOLD if state == "active" else SOFT)
			y += 8
			_text(Vector2(x, y + 8), tr("%d%% done. %s") % [int(Empire.research_fraction(id) * 100),
				(tr("Done in ") + Empire.research_left_text(id) + ".") if state == "active" else Prompts.confirm() + tr(" to resume.")], 8, SOFT, w)
		_:
			var cost: Dictionary = n["cost"]
			_text(Vector2(x, y + 8), tr("Costs %s, paid when you start.") % Empire.cost_text(cost), 8, INSIGHT if Empire.can_afford(cost) else BAD, w)
			y += 12
			_text(Vector2(x, y + 8), tr("Study: %d day%s at 100%% pace.") % [int(n["days"]), "" if int(n["days"]) == 1 else "s"], 8, SOFT, w)
			var why := Empire.research_blocker(id)
			if why != "":
				y += 12
				_text(Vector2(x, y + 8), tr("Can't yet: %s.") % why, 8, BAD, w)
	y += 22
	# Who sets the pace
	_text(Vector2(x, y), tr("Study pace"), 8, Color(0.75, 0.72, 0.7))
	var pace := Empire.research_pace()
	_text_r(Vector2(x + w, y), "%d%%" % int(round(float(pace["pace"]) * 100)), 9, GOOD if float(pace["pace"]) > 0.0 else BAD)
	y += 2
	for line in pace["why"]:
		y += _wrap(Vector2(x, y + 9), line, w, 8, SOFT if float(pace["pace"]) > 0.0 else BAD) + 1
