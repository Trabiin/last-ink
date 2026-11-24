extends Control
## Roster screen on the Command Table: everyone who has joined, their stats and traits, and
## what they could be doing. Picking a role shows its effect before you commit.
##
## Two columns: the people list on the left, the role options on the right. Keyboard, gamepad,
## mouse and touch. The clock keeps running underneath (pause it with 1 if you want to think).

signal closed

const GOLD := Color("ffd166")
const STAT_KEYS := ["might", "craft", "lore", "charm", "grit"]
const STAT_NAMES := {"might": "Might", "craft": "Craft", "lore": "Lore", "charm": "Charm", "grit": "Grit"}
const TIER_NAMES := {"field": "Field hero", "core": "Core staff", "recruit": "Recruit"}
const TIER_COLORS := {"field": Color("e8a05a"), "core": Color("8fa7e8"), "recruit": Color("a9a39a")}
const LIST_X := 8.0
const LIST_W := 214.0
const ROW_H := 30.0
const OPT_X := 440.0

var sel := 0  # selected person
var opt := 0  # selected role option
var focus := 0  # 0 = people list, 1 = role options
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _row_rects: Array = []
var _opt_rects: Array = []
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open() -> void:
	# Under a CanvasLayer the anchors have no parent Control to fill, so size it by hand.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	focus = 0
	opt = 0
	sel = clampi(sel, 0, maxi(Empire.roster_ids().size() - 1, 0))


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _ids() -> Array:
	return Empire.roster_ids()


func _options() -> Array:
	var ids := _ids()
	return Empire.role_options(ids[sel]) if not ids.is_empty() else []


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return  # the key that opened the roster must not also act inside it
	var ids := _ids()
	var opts := _options()
	var up := Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up")
	var down := Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down")
	if focus == 0:
		if up:
			sel = posmod(sel - 1, ids.size())
		elif down:
			sel = posmod(sel + 1, ids.size())
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
			focus = 1
			opt = _current_option_index(opts)
		elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("roster"):
			close()
	else:
		if up:
			opt = posmod(opt - 1, opts.size())
		elif down:
			opt = posmod(opt + 1, opts.size())
		if Input.is_action_just_pressed("ui_accept"):
			_assign(opts[opt])
		elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left"):
			focus = 0
		elif Input.is_action_just_pressed("roster"):
			close()


func _current_option_index(opts: Array) -> int:
	var id: String = _ids()[sel]
	var st: Dictionary = Empire.recruits[id]
	for i in opts.size():
		if opts[i]["role"] == st["role"] and opts[i]["target"] == st["target"]:
			return i
	return 0


func _assign(o: Dictionary) -> void:
	var id: String = _ids()[sel]
	if not o["enabled"]:
		flash = tr("Can't: %s.") % o["note"] if o["note"] != "" else tr("Can't do that right now.")
	elif Empire.assign(id, o["role"], o["target"]):
		flash = "%s: %s." % [Empire.recruit(id)["name"], Empire.role_label(id)]
	flash_t = 2.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _row_rects.size():  # pointing at another person focuses them, like the arrow keys
			if (_row_rects[i] as Rect2).has_point(event.position) and sel != i:
				sel = i
				focus = 0
				opt = 0
		for i in _opt_rects.size():
			if (_opt_rects[i] as Rect2).has_point(event.position):
				focus = 1
				opt = i
	elif Prompts.tapped(event):
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
				focus = 0
				opt = 0
				return
		var opts := _options()
		for i in _opt_rects.size():
			if (_opt_rects[i] as Rect2).has_point(event.position):
				opt = i
				_assign(opts[i])
				return
		if _close_rect().has_point(event.position):
			close()


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	var lines := font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y
	return lines + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var ids := _ids()
	var n := ids.size()
	_text(Vector2(LIST_X, 20), tr("Roster"), 15, Color("f3efe4"))
	_text(Vector2(LIST_X + 64, 19), tr("%d people   upkeep %d Supplies a day   party %d/%d") % [n, n * Empire.UPKEEP_SUPPLIES, Empire.party_ids().size(), Empire.PARTY_SIZE], 9, Color(0.7, 0.68, 0.7))
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))

	# People list
	_row_rects.clear()
	var row_h := minf(ROW_H, (vs.y - 40.0) / float(maxi(n, 1)))  # a big roster squeezes onto one screen
	for i in n:
		var id: String = ids[i]
		var r := Empire.recruit(id)
		var row := Rect2(LIST_X, 32 + i * row_h, LIST_W, row_h - 3)
		_row_rects.append(row)
		var on := i == sel
		draw_rect(row, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(row, GOLD if focus == 0 else Color(0.55, 0.48, 0.3), false, 1.0)
		var injured := int(Empire.recruits[id]["injured"]) > 0
		var role_col := Color("ff9b8a") if injured else Color(0.62, 0.6, 0.62)
		if row_h >= 26.0:
			draw_rect(Rect2(row.position + Vector2(5, 7), Vector2(5, 13)), TIER_COLORS[r["tier"]])
			_text(row.position + Vector2(16, 12), r["name"], 10, GOLD if on else Color("ece6da"))
			var rx := 16.0
			if UiSkin.draw_icon(self, "role_" + Empire.role_of(id), Rect2(row.position + Vector2(15, 15), Vector2(10, 10))):
				rx = 28.0
			_text(row.position + Vector2(rx, 23), Empire.role_label(id), 8, role_col)
		else:  # compact: name and role on one line
			var mid := row.size.y / 2.0
			draw_rect(Rect2(row.position + Vector2(5, mid - 5), Vector2(5, 10)), TIER_COLORS[r["tier"]])
			draw_string(font, row.position + Vector2(16, mid + 3.5), r["name"], HORIZONTAL_ALIGNMENT_LEFT, 92, Access.fs(9), GOLD if on else Color("ece6da"))
			draw_string(font, row.position + Vector2(110, mid + 3), Empire.role_label(id), HORIZONTAL_ALIGNMENT_LEFT, LIST_W - 114, Access.fs(7), role_col)
	if n == 0:
		return

	# Detail: who they are
	var id: String = ids[sel]
	var r := Empire.recruit(id)
	var x := 236.0
	_text(Vector2(x, 46), r["name"], 15, Color("f3efe4"))
	_text(Vector2(x, 59), r["title"], 9, Color(0.75, 0.72, 0.7))
	_text(Vector2(x + 120, 59), Loc.t(TIER_NAMES[r["tier"]]), 9, TIER_COLORS[r["tier"]])
	var y := 76.0
	for k in STAT_KEYS:
		var v := int(r["stats"][k])
		_text(Vector2(x, y + 7), Loc.t(STAT_NAMES[k]), 9, Color(0.72, 0.7, 0.72))
		for seg in 10:
			var c := Color(0.85, 0.78, 0.6) if seg < v else Color(0.18, 0.16, 0.2)
			draw_rect(Rect2(x + 44 + seg * 11, y, 9, 7), c)
		_text(Vector2(x + 158, y + 7), str(v), 9, Color(0.85, 0.83, 0.78))
		y += 13
	y += 8
	for t in r.get("traits", []):
		var td: Dictionary = Empire.trait_data.get(t, {"name": t, "desc": ""})
		var tx := x
		if UiSkin.draw_icon(self, "trait_" + str(t), Rect2(x, y - 10, 12, 12)):
			tx = x + 15
		_text(Vector2(tx, y), td["name"], 9, Color("e8c66a"))
		y += 3
		y += _wrap(Vector2(x, y + 9), td["desc"], 190, 8, Color(0.68, 0.66, 0.68)) + 10
	y += 4
	y += _wrap(Vector2(x, y + 9), r["blurb"], 190, 8, Color(0.55, 0.53, 0.56))
	if Empire.has_bond(id):
		var br := Empire.bond_rank(id)
		y += 6
		_text(Vector2(x, y + 9), tr("Bond rank %d, %s%s") % [br, Empire.bond_rank_name(br), tr("  (wants a word: H)") if Empire.bond_next_scene(id) > 0 else ""], 8, Color("ff8fa3"))
		y += 12
		_wrap(Vector2(x, y + 9), tr("Likes ") + Empire.bond_info(id).get("likes_text", "?") + tr(". Pink heart: a role they like. Grey: one they dislike."), 190, 7, Color(0.6, 0.58, 0.6))

	# Detail: what they could do
	_text(Vector2(OPT_X, 46), tr("Assign"), 11, Color("f3efe4"))
	_text(Vector2(OPT_X + 48, 46), tr("now: ") + Empire.role_label(id), 8, Color(0.7, 0.68, 0.7))
	var opts := _options()
	_opt_rects.clear()
	var oy := 56.0
	var current := _current_option_index(opts)
	for i in opts.size():
		var o: Dictionary = opts[i]
		var rr := Rect2(OPT_X, oy, size.x - OPT_X - 8, 17)
		_opt_rects.append(rr)
		var hl := focus == 1 and i == opt
		draw_rect(rr, Color(0.16, 0.13, 0.09) if hl else Color(0.09, 0.08, 0.11))
		if hl:
			draw_rect(rr, GOLD, false, 1.0)
		var col := Color("ece6da") if o["enabled"] else Color(0.42, 0.41, 0.44)
		if i == current:
			draw_circle(rr.position + Vector2(7, 8.5), 2.5, GOLD)
		var mood := Empire.role_mood_for(id, o["role"], o["target"])
		if mood != "":
			var hc := rr.position + Vector2(rr.size.x - 9, 9)
			Art.draw_heart(self, hc, 3.5, Color("ff8fa3") if mood == "likes" else Color(0.4, 0.37, 0.42))
		_text(rr.position + Vector2(14, 12), o["label"], 9, GOLD if hl and o["enabled"] else col)
		if not o["enabled"] and o["note"] != "":
			var lw := font.get_string_size(o["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
			var room := rr.size.x - 26 - lw
			var note := Access.fit(font, "(" + o["note"] + ")", Access.fs(7), room)  # big text: trimmed, the row's footer says it in full
			_text(rr.position + Vector2(20 + lw, 12), note, 7, Color(0.45, 0.44, 0.47))
		oy += 19
	# Preview of the highlighted option
	var show: Dictionary = opts[opt if focus == 1 else current]
	if show["preview"] != "":
		_wrap(Vector2(OPT_X, oy + 12), show["preview"], size.x - OPT_X - 8, 8, Color("cfe0b0"))
	var help := Prompts.help([["updown", "choose"], ["ui_accept", "assign"], ["ui_cancel", "back"]], tr("Tap a role to assign it")) if focus == 1 else Prompts.help([["updown", tr("choose person")], ["ui_accept", tr("pick a role")], [["ui_cancel", "roster"], "close"]], tr("Tap a person, then tap a role"))
	# Under the roles; a long line (large text, long key names) slides left so it never runs off the edge.
	var hw := font.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
	_text(Vector2(maxf(8.0, minf(OPT_X, vs.x - 8.0 - hw)), vs.y - 10), help, 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		_text(Vector2(LIST_X, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))
