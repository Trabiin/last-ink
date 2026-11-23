extends Control
## Expeditions screen (the Guildhall's job board). Opened with E (gamepad right stick click),
## from the menus, the top bar of the Command Table, or by walking up to the Guildhall in town.
##
## Three pages, all plain lists (Up/Down, Enter, Esc; mouse and touch tap):
## - board: squads out right now, the jobs on offer, and the reports row
## - squad: tick 2 to 4 people for the chosen job; the success chance and every reason behind
##   it update as you pick, and the last row sends them
## - reports: the written reports from squads that came back
## The board and the reports are two tabs (TabStrip): Q / E, LB / RB or a tap switch between them.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const ROW_H := 17.0

var page := "board"
var _strip := TabStrip.new()  # Job board | Reports, with the tab keys either side
var sel := 0
var job_id := ""
var squad: Array = []
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _rows: Array = []  # board: {"kind": "out"|"job"|"reports", "id", "enabled", "note"}; squad: {"kind": "person"|"send", ...}
var _row_rects: Array = []
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open(start_page := "board") -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	if start_page == "board" and Empire.unread_reports() > 0:
		start_page = "reports"  # news first; the board is one Esc away
	_go(start_page)


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _go(p: String, keep_sel := false) -> void:
	page = p
	_build_rows()
	if not keep_sel:
		sel = 0
		if page == "board":  # start on the first job you can actually take
			for i in _rows.size():
				if _rows[i]["kind"] == "job" and _rows[i]["enabled"]:
					sel = i
					break
	sel = clampi(sel, 0, maxi(_rows.size() - 1, 0))
	if page == "reports":
		_mark_read()


func _build_rows() -> void:
	_rows.clear()
	match page:
		"board":
			for e in Empire.expeditions:
				_rows.append({"kind": "out", "id": e["job"], "enabled": true, "note": ""})
			for jid in Empire.job_ids():
				if not Empire.expedition_running(jid).is_empty():
					continue
				var why := Empire.job_blocker(jid)
				_rows.append({"kind": "job", "id": jid, "enabled": why == "", "note": why})
			_rows.append({"kind": "reports", "id": "", "enabled": not Empire.reports.is_empty(), "note": ""})
		"squad":
			var ids := Empire.roster_ids()
			ids.sort_custom(func(a, b):
				var fa := Empire.squad_blocker(a) == ""
				var fb := Empire.squad_blocker(b) == ""
				if fa != fb:
					return fa
				return Empire.job_strength(job_id, a) > Empire.job_strength(job_id, b))
			for id in ids:
				var why := Empire.squad_blocker(id)
				_rows.append({"kind": "person", "id": id, "enabled": why == "", "note": why})
			_rows.append({"kind": "send", "id": "", "enabled": true, "note": ""})
		"reports":
			for i in Empire.reports.size():
				_rows.append({"kind": "report", "id": str(i), "enabled": true, "note": ""})


func _mark_read() -> void:
	if page == "reports" and sel < Empire.reports.size():
		Empire.reports[sel]["read"] = true


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	if page == "board" and Engine.get_process_frames() % 30 == 0:
		_build_rows()  # squads come home and cooldowns end while the screen is open
		sel = clampi(sel, 0, maxi(_rows.size() - 1, 0))
	queue_redraw()
	if Engine.get_process_frames() != opened_frame and page != "squad" and TabStrip.pressed() != 0:
		_tab_to("reports" if page == "board" else "board")
		return
	if Engine.get_process_frames() == opened_frame or _rows.is_empty():
		if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("expeditions"):
			_back()
		return
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		sel = posmod(sel - 1, _rows.size())
		_mark_read()
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		sel = posmod(sel + 1, _rows.size())
		_mark_read()
	if Input.is_action_just_pressed("ui_accept"):
		_pick(sel)
	elif Input.is_action_just_pressed("expeditions"):
		close()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		_back()


## The Job board and Reports tabs.
func _tab_to(p: String) -> void:
	if p == page:
		return
	if p == "reports" and Empire.reports.is_empty():
		_say(tr("No reports yet: squads write one when they come home."))
		return
	if p == "board":
		_back()
	else:
		_go("reports")


func _draw_tabs() -> void:
	var unread := Empire.unread_reports()
	_strip.labels = [tr("Job board"), tr("Reports (%d new)") % unread if unread > 0 else tr("Reports")]
	_strip.current = 1 if page == "reports" else 0
	var title_w := font.get_string_size(tr("Expeditions"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(15)).x
	_strip.draw(self, font, Vector2(maxf(100.0, 8.0 + title_w + 12.0), 7), 9)


func _back() -> void:
	if page == "board":
		close()
	else:
		var from := page
		var jid := job_id
		_go("board")
		for i in _rows.size():  # land back on the row you came from
			if (from == "squad" and _rows[i]["id"] == jid) or (from == "reports" and _rows[i]["kind"] == "reports"):
				sel = i


func _say(s: String) -> void:
	flash = s
	flash_t = 2.8


func _pick(i: int) -> void:
	var row: Dictionary = _rows[i]
	match row["kind"]:
		"job":
			if not row["enabled"]:
				_say(tr("Can't: %s.") % row["note"])
				return
			job_id = row["id"]
			squad = []
			_go("squad")
		"out":
			var e := Empire.expedition_running(row["id"])
			if not e.is_empty():
				_say(tr("Back in %s.") % Empire.job_left_text(e))
		"reports":
			if row["enabled"]:
				_go("reports")
			else:
				_say(tr("No reports yet. Send a squad out first."))
		"person":
			var id: String = row["id"]
			if id in squad:
				squad.erase(id)
			elif not row["enabled"]:
				_say(tr("Can't: %s.") % row["note"])
			elif squad.size() >= Empire.SQUAD_MAX:
				_say(tr("A squad is at most %d people.") % Empire.SQUAD_MAX)
			else:
				squad.append(id)
		"send":
			var why := _send_blocker()
			if why != "":
				_say(tr("Can't send: %s.") % why)
				return
			var j := Empire.job(job_id)
			var names := squad.map(func(id): return Empire.short_name(id))
			if Empire.send_expedition(job_id, squad):
				_go("board")
				_say(tr("%s set off: %s. Back in %s.") % [tr(" and ").join(names) if names.size() <= 2 else ", ".join(names), j["name"], Empire.job_days_text(job_id)])


func _send_blocker() -> String:
	if squad.size() < Empire.SQUAD_MIN:
		return tr("pick at least %d people") % Empire.SQUAD_MIN
	var why := Empire.job_blocker(job_id)
	if why != "":
		return why
	var cost := Empire.expedition_cost(job_id, squad.size())
	if not Empire.can_afford(cost):
		return tr("not enough Supplies for rations (%d)") % int(cost["supplies"])
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position) and sel != i:
				sel = i
				_mark_read()
	elif Prompts.tapped(event):
		if page != "squad":
			var ti := _strip.hit(event.position)
			if ti >= 0:
				_tab_to("reports" if ti == 1 else "board")
				return
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
				if page == "reports":
					_mark_read()
				else:
					_pick(i)
				return
		if _close_rect().has_point(event.position):
			_back()


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


## Wrapped text; returns the height it took.
func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _row_box(i: int, rr: Rect2) -> bool:
	var on := i == sel
	draw_rect(rr, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
	if on:
		draw_rect(rr, GOLD, false, 1.0)
	return on


func _danger_pips(pos: Vector2, n: int) -> void:
	for k in 3:
		var c := Color(0.85, 0.35, 0.3) if k < n else Color(0.25, 0.22, 0.27)
		draw_rect(Rect2(pos + Vector2(k * 6, -6), Vector2(4, 6)), c)


func _bar(r: Rect2, f: float, col: Color) -> void:
	draw_rect(r, Color(0.14, 0.12, 0.16))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(f, 0.0, 1.0), r.size.y)), col)


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close") if page == "board" else tr("Back"), 9, Color(0.75, 0.72, 0.7))
	_row_rects.clear()
	match page:
		"board":
			_draw_board(vs)
		"squad":
			_draw_squad(vs)
		"reports":
			_draw_reports(vs)
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var w := font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		draw_rect(Rect2(vs.x - w - 18, vs.y - 21, w + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - w - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))


func _draw_board(vs: Vector2) -> void:
	_text(Vector2(8, 20), tr("Expeditions"), 15, Color("f3efe4"))
	_draw_tabs()
	var gh := Empire.level_of("guildhall")
	var sub := tr("Guildhall level %d: up to %d squad%s out at once (%d out now). Squads of %d to %d. Supplies pay the rations.") % [
		gh, Empire.expedition_slots(), "" if Empire.expedition_slots() == 1 else "s", Empire.expeditions.size(), Empire.SQUAD_MIN, Empire.SQUAD_MAX]
	if gh > 0 and Empire.expeditions.size() >= Empire.expedition_slots():
		sub = tr("All squads are out (%d/%d). Wait for them, or upgrade the Guildhall%s to send more at once.") % [Empire.expeditions.size(), Empire.expedition_slots(), Prompts.tag("buildings")]
	if gh <= 0:
		sub = tr("Expeditions run from the Guildhall. Build it first on the Buildings screen%s.") % Prompts.tag("buildings")
	_text(Vector2(8, 34), sub, 8, GOLD if gh > 0 else BAD)
	var cols := [14.0, 214.0, 280.0, 318.0, 360.0]
	var hc := Color(0.55, 0.53, 0.56)
	var y := 52.0
	_text(Vector2(cols[0], y - 4), tr("Job"), 8, hc)
	_text(Vector2(cols[1], y - 4), tr("Kind"), 8, hc)
	_text(Vector2(cols[2], y - 4), tr("Days"), 8, hc)
	_text(Vector2(cols[3], y - 4), tr("Danger"), 8, hc)
	_text(Vector2(cols[4], y - 4), tr("Pays"), 8, hc)
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var rr := Rect2(8, y, vs.x - 16, ROW_H - 2)
		_row_rects.append(rr)
		var on := _row_box(i, rr)
		var base := rr.position + Vector2(0, 11)
		match row["kind"]:
			"out":
				var e := Empire.expedition_running(row["id"])
				var j := Empire.job(row["id"])
				var names := ", ".join(e["squad"].map(func(id): return Empire.short_name(id)))
				_text(base + Vector2(6, 0), tr("OUT"), 8, GOLD)
				_text(base + Vector2(30, 0), j["name"], 9, GOLD if on else TEXT, cols[1] - 40)
				_text(base + Vector2(cols[1] - 8, 0), names, 8, SOFT, 180)
				var bx := Rect2(rr.position + Vector2(cols[4] + 60, 5), Vector2(110, 5))
				_bar(bx, Empire.job_progress(e), Color(0.85, 0.7, 0.35))
				_text(Vector2(bx.end.x + 6, base.y), tr("back in ") + Empire.job_left_text(e), 8, SOFT)
			"job":
				var j := Empire.job(row["id"])
				var col := TEXT if row["enabled"] else DIM
				_text(base + Vector2(cols[0] - 8, 0), j["name"], 9, GOLD if on and row["enabled"] else col, cols[1] - cols[0] - 4)
				_text(base + Vector2(cols[1] - 8, 0), tr(j["kind"]), 8, col if row["enabled"] else DIM)
				_text(base + Vector2(cols[2] - 8, 0), Empire.job_days_text(row["id"]).get_slice(" ", 0), 9, col)
				_danger_pips(base + Vector2(cols[3] - 8, 0), int(j["danger"]))
				var full: bool = row["note"].begins_with("all squads")  # same for every job: say it once, up top
				var pays: String = Empire.reward_text(row["id"]) if row["enabled"] or full else row["note"]
				var pcol := Color("e8d9a8") if row["enabled"] else (DIM if full else Color(0.6, 0.45, 0.42))
				_text(base + Vector2(cols[4] - 8, 0), pays, 8, pcol, vs.x - cols[4] - 12)
			"reports":
				var unread := Empire.unread_reports()
				var label := tr("Reports (%d)") % Empire.reports.size()
				if unread > 0:
					label += tr("  %d new") % unread
				_text(base + Vector2(6, 0), label, 9, (GOLD if on else (GOLD if unread > 0 else TEXT)) if row["enabled"] else DIM)
				if not row["enabled"]:
					_text(base + Vector2(cols[1] - 8, 0), tr("nothing yet: squads write home when they get back"), 8, DIM)
		y += ROW_H
	# Details for the highlighted row
	y += 6
	draw_line(Vector2(8, y), Vector2(vs.x - 8, y), Color(0.25, 0.22, 0.28))
	y += 12
	if _rows.is_empty():
		return
	var row: Dictionary = _rows[sel]
	if row["kind"] in ["job", "out"]:
		var j := Empire.job(row["id"])
		var p := Empire.territory().find(j["province"])
		_text(Vector2(14, y), "%s  (%s)" % [j["name"], p.get("name", "?")], 9, GOLD)
		y += 4
		y += _wrap(Vector2(14, y + 8), j["blurb"], vs.x - 28, 8, Color(0.78, 0.76, 0.74))
		var wants := []
		for k in j["stats"]:
			wants.append(Loc.t(Empire.STAT_NAMES[k]) + ("" if float(j["stats"][k]) >= 1.0 else tr(" (counts half)")))
		var line := tr("Wants: %s.   Takes %s%s.   Rations: %d Supplies a person.   Danger: %s.") % [", ".join(wants), Empire.job_days_text(row["id"]),
			tr(" (Waystations)") if Empire.has_research("log_waystations") else "", int(j["rations"]), Loc.t(Empire.DANGER_NAMES[int(j["danger"])])]
		_text(Vector2(14, y + 14), line, 8, Color("cfe0b0"))
		_text(Vector2(14, y + 26), tr("Pays: %s.%s") % [Empire.reward_text(row["id"]), "" if row["note"] == "" else tr("   Can't yet: %s.") % row["note"]], 8,
			Color("e8d9a8") if row["note"] == "" else BAD)
	elif row["kind"] == "reports" and not Empire.reports.is_empty():
		var r: Dictionary = Empire.reports[0]
		_text(Vector2(14, y), tr("Latest: Day %d, %s") % [int(r["day"]), r["title"]], 9, GOLD)
	_text(Vector2(8, vs.y - 10), Prompts.help([["updown", "choose"], ["ui_accept", "pick"], [["ui_cancel", "expeditions"], "close"]], tr("Tap a row to pick")), 7, Color(0.5, 0.48, 0.52))


func _draw_squad(vs: Vector2) -> void:
	var j := Empire.job(job_id)
	_text(Vector2(8, 20), tr("Pick a squad: ") + j["name"], 13, Color("f3efe4"))
	var wants := []
	for k in j["stats"]:
		wants.append(Loc.t(Empire.STAT_NAMES[k]) + ("" if float(j["stats"][k]) >= 1.0 else tr(" (half)")))
	_text(Vector2(8, 34), tr("Wants %s.  %d to %d people.  %s, %s danger.") % [", ".join(wants), Empire.SQUAD_MIN, Empire.SQUAD_MAX,
		Empire.job_days_text(job_id), Loc.t(Empire.DANGER_NAMES[int(j["danger"])]).to_lower()], 8, GOLD)
	var lw := 300.0
	var y := 52.0
	var hc := Color(0.55, 0.53, 0.56)
	_text(Vector2(26, y - 4), tr("Who"), 8, hc)
	_text(Vector2(124, y - 4), tr("Adds"), 8, hc)
	_text(Vector2(160, y - 4), tr("Doing now"), 8, hc)
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var rr := Rect2(8, y, lw, ROW_H - 2)
		_row_rects.append(rr)
		var on := _row_box(i, rr)
		var base := rr.position + Vector2(0, 11)
		if row["kind"] == "send":
			var why := _send_blocker()
			var label := tr("Send squad (%d/%d)") % [squad.size(), Empire.SQUAD_MAX]
			_text(base + Vector2(10, 0), label, 9, (GOLD if on else Color("f3e3b0")) if why == "" else DIM)
			if why != "":
				_text(base + Vector2(120, 0), why, 8, Color(0.6, 0.45, 0.42), lw - 126)
		else:
			var id: String = row["id"]
			var picked: bool = id in squad
			var col := TEXT if row["enabled"] else DIM
			var box := Rect2(rr.position + Vector2(5, 4), Vector2(7, 7))
			draw_rect(box, Color(0.2, 0.18, 0.22))
			draw_rect(box, Color(0.5, 0.46, 0.5) if row["enabled"] else Color(0.28, 0.26, 0.3), false, 1.0)
			if picked:
				draw_rect(box.grow(-2), GOLD)
			_text(base + Vector2(18, 0), Empire.recruit(id)["name"], 9, GOLD if on and row["enabled"] else col, 96)
			_text(base + Vector2(116, 0), "%d" % int(round(Empire.job_strength(job_id, id))), 9, Color("cfe0b0") if row["enabled"] else col)
			var doing: String = row["note"] if row["note"] != "" else Empire.role_label(id)
			_text(base + Vector2(152, 0), doing, 8, SOFT, lw - 156)
		y += ROW_H

	# Right side: chance and why
	var x := lw + 20
	var w := vs.x - x - 10
	_text(Vector2(x, 60), tr("Success chance"), 9, Color(0.75, 0.72, 0.7))
	if squad.is_empty():
		_wrap(Vector2(x, 78), tr("Tick people on the left (%s). The chance and every reason behind it show up here as you pick.") % Prompts.confirm(), w, 8, SOFT)
	else:
		var odds := Empire.expedition_odds(job_id, squad)
		var c := int(odds["chance"])
		var ccol := GOOD if c >= 70 else (GOLD if c >= 40 else BAD)
		_text(Vector2(x, 86), "%d%%" % c, 22, ccol)
		_bar(Rect2(x + 64, 76, w - 64, 7), c / 100.0, ccol)
		var yy := 104.0
		for why in odds["why"]:
			yy += _wrap(Vector2(x, yy), ("+ " if why[1] else "- ") + why[0], w, 8, Color("cfe0b0") if why[1] else BAD) + 1
		if squad.size() < Empire.SQUAD_MIN:
			yy += _wrap(Vector2(x, yy), tr("Needs at least %d people to go.") % Empire.SQUAD_MIN, w, 8, BAD)
		yy += 6
		var cost := Empire.expedition_cost(job_id, squad.size())
		_text(Vector2(x, yy + 6), tr("Rations: %d Supplies (you have %d)") % [int(cost["supplies"]), int(Empire.res["supplies"])], 8,
			Color("e8d9a8") if Empire.can_afford(cost) else BAD)
		_text(Vector2(x, yy + 18), tr("On success: %s") % Empire.reward_text(job_id), 8, Color("e8d9a8"), w)
		_text(Vector2(x, yy + 30), tr("Failing pays a quarter and hurts people. Danger: %s.") % Loc.t(Empire.DANGER_NAMES[int(j["danger"])]), 8, SOFT, w)
		var leaving := []
		for id in squad:
			if Empire.role_of(id) != "idle":
				leaving.append("%s (%s)" % [Empire.short_name(id), Empire.role_label(id)])
		if not leaving.is_empty():
			_wrap(Vector2(x, yy + 38), tr("Leaves their job while away: ") + ", ".join(leaving), w, 8, Color(0.85, 0.7, 0.55))
	_text(Vector2(8, vs.y - 10), Prompts.help([["updown", "choose"], ["ui_accept", tr("tick / send")], ["ui_cancel", "back"]], tr("Tap people to tick them, then tap Send   Close: back")), 7, Color(0.5, 0.48, 0.52))


func _draw_reports(vs: Vector2) -> void:
	_text(Vector2(8, 20), tr("Expeditions"), 15, Color("f3efe4"))
	_draw_tabs()
	var lw := 220.0
	var y := 40.0
	for i in _rows.size():
		var r: Dictionary = Empire.reports[i]
		var rr := Rect2(8, y, lw, ROW_H - 2)
		_row_rects.append(rr)
		var on := _row_box(i, rr)
		var col: Color = {"great": GOOD, "success": Color("cfe0b0"), "fail": BAD}.get(r.get("outcome", ""), TEXT)
		_text(rr.position + Vector2(6, 11), tr("Day %d") % int(r["day"]), 8, SOFT)
		_text(rr.position + Vector2(40, 11), Empire.job(r["job"]).get("name", r["title"]), 8, GOLD if on else col, lw - 46)
		y += ROW_H
	if _rows.is_empty():
		return
	var r: Dictionary = Empire.reports[sel]
	var x := lw + 22
	var w := vs.x - x - 12
	draw_rect(Rect2(x - 8, 34, w + 16, vs.y - 52), Color(0.93, 0.91, 0.85))  # the report is a sheet of paper
	var ink := Color(0.16, 0.13, 0.12)
	var yy := 50.0
	yy += _wrap(Vector2(x, yy), r["title"], w, 11, ink) + 2
	var squad_names := ", ".join(r.get("squad", []).map(func(id): return Empire.recruit(id).get("name", id)))
	_text(Vector2(x, yy + 2), tr("Day %d.  Squad: %s.  Odds were %d%%.") % [int(r["day"]), squad_names, int(r.get("chance", 0))], 8, Color(0.4, 0.36, 0.34), w)
	yy += 14
	for line in r["lines"]:
		var lc := ink
		if line.begins_with("Brought back"):
			lc = Color(0.45, 0.33, 0.05)
		elif line.find("hurt") >= 0 or line.find("did not come back") >= 0 or line.find("dragged back") >= 0:
			lc = Color(0.6, 0.15, 0.12)
		elif line.find("joins your roster") >= 0:
			lc = Color(0.15, 0.4, 0.15)
		yy += _wrap(Vector2(x, yy + 4), line, w, 9, lc) + 5
	_text(Vector2(8, vs.y - 10), Prompts.help([["updown", tr("choose report")], ["ui_cancel", "back"]], tr("Tap a report to read it   Close: back")), 7, Color(0.5, 0.48, 0.52))
