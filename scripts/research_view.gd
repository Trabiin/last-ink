extends Control
## Research screen (the Scriptorium). Opened with T, from the menus, the Research button on the
## Command Table, or by walking up to the Scriptorium in town.
##
## One plain list (Up/Down, Enter, Esc; mouse and touch tap, wheel or drag to scroll): the four Hollowmark
## branches (three nodes, a fourth node and a study with ranks each) and every chapter branch whose
## region of the map is open (issue #189); the list scrolls to keep the chosen node in view.
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
const BRANCH_COLORS := {"wardcraft": Color("e8c66a"), "logistics": Color("b7c98a"), "inkcraft": Color("8fa7e8"), "arms": Color("e89a8a"), "abbey": Color("d98a7a"),
	"causeway": Color("c98ad9"), "coast": Color("8ad0d9"), "spire": Color("f2c25c")}
const LIST_TOP := 46.0

var sel := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _rows: Array = []  # node ids, in branch order
var _hidden_branches := 0  # chapter branches still behind the fog
var scroll := 0.0  # how far the list is scrolled down, in pixels
var _drag := {}  # a finger drag over the list (Prompts.list_steps / list_tap)
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
	_hidden_branches = 0
	scroll = 0.0
	for b in Empire.research_branches():
		if Empire.research_branch_lock(b["id"]) != "":
			_hidden_branches += 1  # a chapter that has not opened its region yet: no spoilers
			continue
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
	call_deferred("_follow_sel")


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
		_follow_sel()
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		sel = posmod(sel + 1, _rows.size())
		_follow_sel()
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
	# The wheel or a finger dragged over the list walks the focus, and the list follows it (issue #192's rule).
	var on_list: bool = "position" in event and event.position.x < LIST_W + 16 and event.position.y >= LIST_TOP
	var n := Prompts.list_steps(event, _drag, ROW_H, on_list)
	if n != 0:
		var to := clampi(sel + n, 0, maxi(_rows.size() - 1, 0))
		if to != sel:
			sel = to
			_follow_sel()
			Audio.sfx("ui_move")
		accept_event()
		return
	if event is InputEventScreenDrag and _drag.get("on_list", false):
		accept_event()
		return
	if event is InputEventMouseMotion:
		var hover := _row_at(event.position)
		if hover >= 0:
			sel = hover
		return
	var row := _row_at(event.position) if "position" in event else -1
	match Prompts.list_tap(event, _drag, row, sel):
		"focus":
			sel = row
			return
		"act":
			_pick(sel)  # tap to select, tap again to act (touch friendly)
			return
	if Prompts.tapped(event) and row < 0 and _close_rect().has_point(event.position):
		close()


## The row under a point, or -1 (rows scrolled out of view are never hit).
func _row_at(p: Vector2) -> int:
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(p):
			return i
	return -1


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


## Height of the whole list, branch heads and the footer line included.
func _list_height() -> float:
	var h := 0.0
	var last := ""
	for id in _rows:
		var br := str(Empire.research_node(id)["branch"])
		if br != last:
			last = br
			h += HEAD_H
		h += ROW_H
	return h + (HEAD_H if _hidden_branches > 0 else 0.0)


func _list_bottom() -> float:
	return size.y - 16.0


func _clamp_scroll() -> void:
	scroll = clampf(scroll, 0.0, maxf(_list_height() - (_list_bottom() - LIST_TOP), 0.0))


## Scrolls just enough to show the chosen row (and its branch head).
func _follow_sel() -> void:
	var y := 0.0
	var last := ""
	for i in _rows.size():
		var br := str(Empire.research_node(_rows[i])["branch"])
		if br != last:
			last = br
			y += HEAD_H
		if i == sel:
			var view := _list_bottom() - LIST_TOP
			if y - HEAD_H < scroll:
				scroll = y - HEAD_H
			elif y + ROW_H > scroll + view:
				scroll = y + ROW_H - view
			break
		y += ROW_H
	_clamp_scroll()


## "Readings of the Edge (2/5)" for studies with ranks.
func _row_name(id: String) -> String:
	var n := Empire.research_node(id)
	if Empire.research_max_rank(id) <= 1:
		return n["name"]
	return "%s (%d/%d)" % [n["name"], Empire.research_rank(id), Empire.research_max_rank(id)]


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	# Text cut by its width ends in "..." rather than mid-letter (long names at large text sizes).
	draw_string(font, pos, Access.fit(font, s, Access.fs(fsize), width) if width > 0.0 else s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _text_r(right: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	_text(right - Vector2(w, 0), s, fsize, col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _bar(r: Rect2, f: float, col: Color) -> void:
	UiSkin.bar(self, r, f, Color(col, 1.0), {"dim": col.a < 0.5})  # pixel bar: ink frame, shaded ramp


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
	var hl := UiSkin.header_line(font, tr("Research"), 15, tr("Insight: %d banked, +%d a day") % [int(Empire.res.get("insight", 0)), daily], 9, vs.x, 84.0)
	_text(Vector2(hl[0], 20), hl[1], 9, INSIGHT)
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

	# The list, grouped by branch, scrolled; rows outside the list area are skipped (and can't be tapped).
	var y := LIST_TOP - scroll
	var last_branch := ""
	var top_clip := LIST_TOP - 2.0
	var bottom_clip := _list_bottom()
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
			if y - HEAD_H >= top_clip and y <= bottom_clip:
				var bname: String = b.get("name", "?").to_upper()
				_text(Vector2(10, y - 3), bname, 8, BRANCH_COLORS.get(last_branch, TEXT))
				# The blurb starts after the name (long names and large text push it right) and is trimmed to the list.
				var bx := maxf(84.0, 10.0 + font.get_string_size(bname, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x + 8.0)
				_text(Vector2(bx, y - 3), Access.fit(font, b.get("blurb", ""), Access.fs(7), LIST_W + 8.0 - bx), 7, SOFT)
		var rr := Rect2(8, y, LIST_W, ROW_H - 2)
		if y < top_clip or y + ROW_H - 2 > bottom_clip:
			_row_rects.append(Rect2())  # out of view: keeps the index, never hit
			y += ROW_H
			continue
		_row_rects.append(rr)
		var on := i == sel
		UiSkin.row(self, rr, on)
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
		_text(base + Vector2(nx, 0), _row_name(id), 9, GOLD if on and state != "locked" else col, 148 - nx)
		match state:
			"done":
				_text(base + Vector2(150, 0), Loc.t("known"), 8, GOOD)
			"active", "shelved":
				var bx := Rect2(rr.position + Vector2(150, 4), Vector2(90, 5))
				_bar(bx, Empire.research_fraction(id), GOLD if state == "active" else SOFT)
				_text(Vector2(bx.end.x + 6, base.y), Empire.research_left_text(id) if state == "active" else tr("set aside"), 8, SOFT)
			_:
				var cost := Empire.research_cost(id)
				var days := int(ceil(Empire.research_days(id)))
				_text(base + Vector2(150, 0), Empire.cost_text(cost), 8, (INSIGHT if Empire.can_afford(cost) else BAD) if state != "locked" else DIM)
				_text_r(base + Vector2(LIST_W - 6, 0), Loc.days(days), 8, SOFT if state != "locked" else DIM)
		y += ROW_H
	if _hidden_branches > 0:
		y += HEAD_H
		if y <= bottom_clip and y >= top_clip:
			_text(Vector2(10, y - 3), tr("More to study as the story opens new regions of the map."), 7, DIM)
	# Scroll bar, when the list is longer than the screen
	var view := bottom_clip - LIST_TOP
	var total := _list_height()
	if total > view:
		var track := Rect2(LIST_W + 11, LIST_TOP, 3, view)
		var th := maxf(view * view / total, 12.0)
		UiSkin.scrollbar(self, track, (view - th) * scroll / maxf(total - view, 1.0), th)

	_draw_details(vs)
	_text(Vector2(8, vs.y - 8), Prompts.help([["updown", "choose"], ["ui_accept", tr("study / set aside")], [["ui_cancel", "research"], "close"]], tr("Tap a node, tap again to study it")), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var w := font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		UiSkin.toast(self, Rect2(vs.x - w - 18, vs.y - 21, w + 12, 15), a)
		_text(Vector2(vs.x - w - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))


func _draw_details(vs: Vector2) -> void:
	if _rows.is_empty():
		return
	var id: String = _rows[sel]
	var n := Empire.research_node(id)
	var x := LIST_W + 22
	var w := vs.x - x - 10
	var top := 46.0
	# Written up on a ledger page (LedgerPage), on its lines.
	var pg := LedgerPage.begin(self, Rect2(x - 8, top, w + 16, vs.y - top - 26), font)
	pg.heading(_row_name(id), 12, LedgerPage.INK, id)
	var branch_name := ""
	for b in Empire.research_branches():
		if b["id"] == n["branch"]:
			branch_name = b["name"]
	pg.line(branch_name, 8, LedgerPage.ink(BRANCH_COLORS.get(n["branch"], TEXT)))
	pg.para(n["effect"] + ".", 8, LedgerPage.GREEN)
	pg.para(n["blurb"], 8, LedgerPage.INK)
	pg.skip()
	var state := Empire.research_state(id)
	if Empire.research_max_rank(id) > 1 and state != "done":
		var rk := Empire.research_rank(id)
		pg.para(tr("Rank %d of %d studied. Each rank costs more and takes longer than the last.") % [rk, Empire.research_max_rank(id)], 8, LedgerPage.GOLD if rk > 0 else LedgerPage.INK_SOFT)
	match state:
		"done":
			pg.line(tr("Known. Already working for you.") if Empire.research_max_rank(id) <= 1 else tr("Every rank studied. Already working for you."), 8, LedgerPage.GREEN)
		"active", "shelved":
			pg.line(tr("Studying now") if state == "active" else tr("Set aside (paid for, progress kept)"), 8, LedgerPage.GOLD if state == "active" else LedgerPage.INK_SOFT)
			var br := pg.space()
			if br.size.x > 0.0:
				UiSkin.bar(self, Rect2(br.position.x, br.end.y - 6.0, br.size.x, 5.0), Empire.research_fraction(id), "brass" if state == "active" else "stone", {"notches": [0.25, 0.5, 0.75]})
			pg.line(tr("%d%% done. %s") % [int(Empire.research_fraction(id) * 100),
				(tr("Done in %s.") % Empire.research_left_text(id)) if state == "active" else tr("%s to resume.") % Prompts.confirm()], 8, LedgerPage.INK_SOFT)
		_:
			var cost := Empire.research_cost(id)
			var days := int(ceil(Empire.research_days(id)))
			pg.line(tr("Costs %s, paid when you start.") % Empire.cost_text(cost), 8, LedgerPage.PLUM if Empire.can_afford(cost) else LedgerPage.RED)
			pg.line(Loc.n("Study: %d day at 100%% pace.", "Study: %d days at 100%% pace.", days) % days, 8, LedgerPage.INK_SOFT)
			var why := Empire.research_blocker(id)
			if why != "":
				pg.line(tr("Can't yet: %s.") % why, 8, LedgerPage.RED)
	pg.skip()
	# Who sets the pace
	var pace := Empire.research_pace()
	var good := float(pace["pace"]) > 0.0
	pg.line(tr("Study pace"), 8, LedgerPage.INK, "%d%%" % int(round(float(pace["pace"]) * 100)), LedgerPage.GREEN if good else LedgerPage.RED)
	for line in pace["why"]:
		pg.para(line, 8, LedgerPage.INK_SOFT if good else LedgerPage.RED)
