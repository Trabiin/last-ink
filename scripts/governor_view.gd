extends Control
## Governor screen on the Command Table: pick who runs the selected province.
##
## Opened with G (gamepad X, or the Governor button in the province panel). Lists everyone
## who could govern, best fit first, with what the province would do under each of them.
## On an unclaimed province next to your land, picking someone claims it (for Gilt and
## Supplies) and posts them there. A plain list: Up/Down, Enter, Esc; mouse and touch tap.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const FIT_COLORS := {"good": Color("9fd18b"), "fair": Color("d8cfa8"), "poor": Color("ff9b8a")}
const ROW_H := 19.0
const LIST_Y := 92.0

var pid := ""
var sel := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _rows: Array = []  # [{"kind": "recall"|"person", "id", "enabled", "note"}]
var _row_rects: Array = []
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open(province_id: String) -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	pid = province_id
	visible = true
	opened_frame = Engine.get_process_frames()
	_build_rows()
	sel = 0
	var cur := Empire.governor_of(pid)
	for i in _rows.size():
		if _rows[i]["id"] == cur and cur != "":
			sel = i


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _province() -> Dictionary:
	return Empire.territory().find(pid)


## Why nobody can be posted here at all ("" = you can).
func _province_blocker() -> String:
	var p := _province()
	if p["owner"] == "you":
		return ""
	return Empire.claim_blocker(pid)


func _build_rows() -> void:
	_rows.clear()
	var block := _province_blocker()
	var people := []
	for id in Empire.roster_ids():
		people.append(id)
	people.sort_custom(func(a, b):
		var ba := Empire.governor_blocker(a) == ""
		var bb := Empire.governor_blocker(b) == ""
		if ba != bb:
			return ba
		return Empire.governor_score(a, pid) > Empire.governor_score(b, pid))
	for id in people:
		var note := Empire.governor_blocker(id)
		_rows.append({"kind": "person", "id": id, "enabled": note == "" and block == "", "note": note})
	if Empire.governor_of(pid) != "":
		_rows.append({"kind": "recall", "id": "", "enabled": true, "note": ""})


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
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("govern"):
		close()


func _pick(i: int) -> void:
	var row: Dictionary = _rows[i]
	var p := _province()
	flash_t = 2.5
	if row["kind"] == "recall":
		var gov := Empire.governor_of(pid)
		Empire.recall_governor(pid)
		flash = tr("%s comes home. %s has no governor.") % [Empire.recruit(gov)["name"], p["name"]]
	elif not row["enabled"]:
		var why: String = row["note"] if row["note"] != "" else _province_blocker()
		flash = tr("Can't: %s.") % why
		return
	elif row["id"] == Empire.governor_of(pid):
		close()
		return
	elif p["owner"] != "you":
		if Empire.claim(pid, row["id"]):
			flash = tr("Claimed %s. %s governs it.") % [p["name"], Empire.recruit(row["id"])["name"]]
	elif Empire.assign(row["id"], "governor", pid):
		flash = tr("%s now governs %s.") % [Empire.recruit(row["id"])["name"], p["name"]]
	var keep: String = row["id"]
	_build_rows()
	sel = 0
	for j in _rows.size():
		if _rows[j]["id"] == keep:
			sel = j


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
	elif Prompts.tapped(event):
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
				_pick(i)
				return
		if _close_rect().has_point(event.position):
			close()


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)


func _rate_text(r: int) -> String:
	return "%+d/day" % r if r != 0 else "0/day"


func _draw() -> void:
	var vs := size
	var p := _province()
	UiSkin.screen(self, vs)
	var claiming: bool = p["owner"] != "you"
	_text(Vector2(8, 20), (tr("Claim %s") if claiming else tr("Govern %s")) % p["name"], 15, Color("f3efe4"))
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))

	# What this province wants, and where it stands now
	var fav: String = p.get("favors", "charm")
	_text(Vector2(8, 36), tr("Wants a governor with high %s.") % Loc.t(Empire.STAT_NAMES[fav]), 9, GOLD)
	_text(Vector2(8, 47), p.get("favors_why", ""), 8, Color(0.68, 0.66, 0.68))
	var now := Empire.fray_rate(p)
	var gov := Empire.governor_of(pid)
	var status := tr("Fray %d   %s now") % [int(p["fray"]), _rate_text(now)]
	if p["owner"] == "you":
		status += tr("   governor: %s") % (Empire.recruit(gov)["name"] if gov != "" else tr("none (Fray +%d, output -%d%%)") % [Empire.FRAY_UNGOVERNED, int(round((1.0 - Empire.UNGOVERNED_OUTPUT) * 100))])
	_text(Vector2(8, 61), status, 9, BAD if now > 0 else GOOD)
	var block := _province_blocker()
	if claiming:
		var cost := Empire.claim_cost(pid)
		var parts := []
		for k in cost:
			parts.append("%d %s" % [int(cost[k]), Loc.t(Empire.RES_NAMES[k])])
		var line := tr("Claiming costs %s. Pick who goes to run it.") % ", ".join(parts)
		if block != "":
			line = tr("Can't claim: %s.") % block
		_text(Vector2(8, 74), line, 9, BAD if block != "" else Color("e8d9a8"))

	# Column headers
	var hx := [22.0, 128.0, 262.0, 330.0, 404.0]
	var hy := LIST_Y - 4
	var hc := Color(0.55, 0.53, 0.56)
	_text(Vector2(hx[0], hy), tr("Who"), 8, hc)
	_text(Vector2(hx[1], hy), tr("Doing now"), 8, hc)
	_text(Vector2(hx[2], hy), tr("Fit"), 8, hc)
	_text(Vector2(hx[3], hy), tr("Fray there"), 8, hc)
	_text(Vector2(hx[4], hy), tr("Governor adds a day"), 8, hc)

	_row_rects.clear()
	var y := LIST_Y
	var row_h := clampf((vs.y - LIST_Y - 70.0) / float(maxi(_rows.size(), 1)), 13.0, ROW_H)  # a big roster squeezes up
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var rr := Rect2(8, y, vs.x - 16, row_h - 2)
		_row_rects.append(rr)
		var on := i == sel
		draw_rect(rr, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(rr, GOLD, false, 1.0)
		var base := rr.position + Vector2(0, minf(12.0, row_h - 3.0))
		if row["kind"] == "recall":
			_text(base + Vector2(hx[0] - 8, 0), tr("Recall %s (leave %s ungoverned)") % [Empire.recruit(gov)["name"], p["name"]], 9, GOLD if on else Color("ece6da"))
			_text(base + Vector2(hx[3] - 8, 0), _rate_text(Empire.fray_rate(p, "")), 9, BAD)
		else:
			var id: String = row["id"]
			var col := Color("ece6da") if row["enabled"] else Color(0.42, 0.41, 0.44)
			if id == gov:
				draw_circle(rr.position + Vector2(7, (row_h - 2.0) / 2.0), 2.5, GOLD)
			_text(base + Vector2(hx[0] - 8, 0), Empire.recruit(id)["name"], 9, GOLD if on and row["enabled"] else col)
			var doing := Empire.role_label(id)
			if row["note"] != "":
				doing = row["note"]
			draw_string(font, base + Vector2(hx[1] - 8, 0), doing, HORIZONTAL_ALIGNMENT_LEFT, hx[2] - hx[1] - 6, Access.fs(8), Color(0.62, 0.6, 0.62))
			var e := Empire.governor_effect(id, pid)
			var stat := int(Empire.recruit(id)["stats"][fav])
			_text(base + Vector2(hx[2] - 8, 0), "%s (%d)" % [e["fit"].capitalize(), stat], 9, FIT_COLORS[e["fit"]] if row["enabled"] else col)
			var r := Empire.fray_rate(p, id)
			_text(base + Vector2(hx[3] - 8, 0), _rate_text(r), 9, (BAD if r > 0 else GOOD) if row["enabled"] else col)
			_text(base + Vector2(hx[4] - 8, 0), Empire.output_text(e), 9, Color("e8d9a8") if row["enabled"] else col)
		y += row_h

	# Why: every reason behind the highlighted choice
	y += 8
	if not _rows.is_empty():
		var row: Dictionary = _rows[sel]
		if row["kind"] == "person":
			var e := Empire.governor_effect(row["id"], pid)
			for w in e["why"].slice(0, maxi(int((vs.y - 24.0 - y) / 11.0) - 1, 1)):  # as many reasons as fit
				_text(Vector2(14, y + 8), ("+ " if w[1] else "- ") + w[0], 8, Color("cfe0b0") if w[1] else BAD)
				y += 11
			if row["id"] != gov and Empire.role_of(row["id"]) != "idle":
				_text(Vector2(14, y + 8), tr("Leaves their current job: %s.") % Empire.role_label(row["id"]), 8, Color(0.75, 0.72, 0.7))
		else:
			_text(Vector2(14, y + 8), tr("An ungoverned province frays %d faster a day and delivers %d%% less.") % [Empire.FRAY_UNGOVERNED, int(round((1.0 - Empire.UNGOVERNED_OUTPUT) * 100))], 8, BAD)

	_text(Vector2(8, vs.y - 10), Prompts.help([["updown", "choose"], ["ui_accept", "post"], [["ui_cancel", "govern"], "close"]], tr("Tap someone to post them")), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		_text(Vector2(240, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))
