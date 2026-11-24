extends Control
## Bonds screen. Opened with H, from the menus, or the Bonds button on the Command Table.
##
## Left: the core cast who have joined, with their bond rank (0-5) and how close the next one is.
## Right: what they like, what their bond has unlocked, their personal mission, and their scenes.
## Enter on someone who "wants a word" plays their next rank scene; otherwise Enter (or Right)
## moves to their scene list, where seen scenes can be replayed. Esc / H closes.

signal closed

const SceneView := preload("res://scripts/scene_view.gd")
const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const HEART := Color("ff8fa3")
const ROW_H := 34.0
const LIST_W := 220.0
const SCENE_ROW_H := 14.0

var sel := 0
var focus := 0  # 0 = people, 1 = scenes
var scene_sel := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var scene_view
var _row_rects: Array = []
var _row_index: Array = []  # list index of each visible row in _row_rects
var scroll := 0  # first visible row of the people list (it scrolls once the cast outgrows the screen)
var _scene_rects: Array = []
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	scene_view = SceneView.new()
	scene_view.visible = false
	add_child(scene_view)
	scene_view.finished.connect(func(_id, _r): opened_frame = Engine.get_process_frames())


func open(who := "") -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	focus = 0
	var ids := _ids()
	sel = clampi(sel, 0, maxi(ids.size() - 1, 0))
	if who != "" and who in ids:
		sel = ids.find(who)
	else:  # start on whoever wants a word
		for i in ids.size():
			if Empire.bond_next_scene(ids[i]) > 0:
				sel = i
				break


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _ids() -> Array:
	return Empire.bond_ids()


## Scene rows for the selected person: every rank, seen or not. [{"rank", "state": seen|ready|locked}]
func _scene_rows() -> Array:
	var ids := _ids()
	if ids.is_empty():
		return []
	var id: String = ids[sel]
	var out := []
	for sc in Empire.bond_info(id).get("scenes", []):
		var r := int(sc["rank"])
		var state := "locked"
		if r <= Empire.bond_rank(id):
			state = "seen"
		elif Empire.bond_next_scene(id) == r:
			state = "ready"
		out.append({"rank": r, "state": state, "title": Empire.bond_scene(id, r).get("title", sc.get("title", ""))})
		if r == 3 and Relationships.can_romance(id):  # the romance question sits between rank 3 and 4 (issue #116)
			var m := Relationships.moment_scene(id)
			var ms := "seen" if Relationships.romance_of(id) != "" else ("ready" if Empire.bond_next_scene(id) == Relationships.MOMENT else "locked")
			out.append({"rank": Relationships.MOMENT, "state": ms, "title": m.get("title", ""), "num": "3+"})
	return out


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if scene_view.visible or Engine.get_process_frames() == opened_frame or Engine.get_process_frames() == scene_view.closed_frame:
		return
	var ids := _ids()
	if ids.is_empty():
		if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("bonds") \
				or Input.is_action_just_pressed("ui_accept"):
			close()
		return
	var up := Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up")
	var down := Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down")
	if focus == 0:
		if up:
			sel = posmod(sel - 1, ids.size())
		elif down:
			sel = posmod(sel + 1, ids.size())
		if Input.is_action_just_pressed("ui_accept"):
			_pick_person()
		elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
			_to_scenes()
		elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("bonds"):
			close()
	else:
		var rows := _scene_rows()
		if up:
			scene_sel = posmod(scene_sel - 1, rows.size())
		elif down:
			scene_sel = posmod(scene_sel + 1, rows.size())
		if Input.is_action_just_pressed("ui_accept"):
			_pick_scene(scene_sel)
		elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left") \
				or Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
			focus = 0
		elif Input.is_action_just_pressed("bonds"):
			close()


func _say(s: String) -> void:
	flash = s
	flash_t = 3.0


func _to_scenes() -> void:
	var rows := _scene_rows()
	focus = 1
	scene_sel = 0
	for i in rows.size():  # land on the newest scene you can play
		if rows[i]["state"] != "locked":
			scene_sel = i


func _pick_person() -> void:
	var id: String = _ids()[sel]
	var r := Empire.bond_next_scene(id)
	if r > 0:
		_play(id, r, false)
	else:
		_to_scenes()


func _pick_scene(i: int) -> void:
	var rows := _scene_rows()
	if i < 0 or i >= rows.size():
		return
	var id: String = _ids()[sel]
	match rows[i]["state"]:
		"seen":
			_play(id, int(rows[i]["rank"]), true)
		"ready":
			_play(id, int(rows[i]["rank"]), false)
		_:
			_say(tr("Not yet. %s") % Empire.bond_next_text(id))


func _play(id: String, r: int, is_replay: bool) -> void:
	var why := Empire.bond_scene_blocker(id)
	if why != "" and not is_replay:
		_say(tr("Can't now: %s.") % why)
		return
	scene_view.play(id, r, is_replay)


func _gui_input(event: InputEvent) -> void:
	if scene_view.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] \
			and event.position.x < LIST_W + 12:
		var ids := _ids()
		sel = clampi(sel + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 0, maxi(ids.size() - 1, 0))
		focus = 0
		return
	if event is InputEventMouseMotion:
		for k in _row_rects.size():
			if (_row_rects[k] as Rect2).has_point(event.position):
				var i: int = _row_index[k]
				if sel != i:
					focus = 0
				sel = i
		for i in _scene_rects.size():
			if (_scene_rects[i] as Rect2).has_point(event.position):
				focus = 1
				scene_sel = i
	elif Prompts.tapped(event):
		if _close_rect().has_point(event.position):
			close()
			return
		for k in _row_rects.size():
			if (_row_rects[k] as Rect2).has_point(event.position):
				var i: int = _row_index[k]
				if sel == i and focus == 0:
					_pick_person()  # tap to select, tap again to act (touch friendly)
				sel = i
				focus = 0
				return
		for i in _scene_rects.size():
			if (_scene_rects[i] as Rect2).has_point(event.position):
				if focus == 1 and scene_sel == i:
					_pick_scene(i)
				focus = 1
				scene_sel = i
				return


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


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
	draw_rect(r, Color(0.14, 0.12, 0.16))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(f, 0.0, 1.0), r.size.y)), col)


## Five little hearts: filled up to the rank.
func _pips(pos: Vector2, rank: int, col: Color) -> void:
	for i in Empire.BOND_MAX:
		var c := pos + Vector2(i * 10, 0)
		Art.draw_heart(self, c, 4.0, col if i < rank else Color(0.3, 0.28, 0.33))


## A small gold arrow over/under the people list when more rows are scrolled out of sight.
func _scroll_arrow(at: Vector2, up: bool) -> void:
	var d := -3.0 if up else 3.0
	draw_colored_polygon(PackedVector2Array([at + Vector2(-5, -d / 3), at + Vector2(5, -d / 3), at + Vector2(0, d)]), Color(GOLD, 0.8))


## Progress from this rank to the next as 0..1.
func _progress(id: String) -> float:
	var r := Empire.bond_rank(id)
	if r >= Empire.BOND_MAX:
		return 1.0
	var lo := Empire.bond_threshold(r)
	var hi := Empire.bond_threshold(r + 1)
	return float(Empire.bond_points(id) - lo) / float(maxi(hi - lo, 1))


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	_row_rects.clear()
	_row_index.clear()
	_scene_rects.clear()
	_text(Vector2(8, 20), tr("Bonds"), 15, Color("f3efe4"))
	var ready := Empire.bond_ready_ids().size()
	var sub := tr("Chat once a day in Hollowmark, put people in roles they like, send them on jobs. Each rank has a scene.")
	var hl := UiSkin.header_line(font, tr("Bonds"), 15, (Loc.n("%d wants a word with Ash.", "%d want a word with Ash.", ready) % ready) if ready > 0 else "", 9, vs.x, 62.0)
	_text(Vector2(hl[0], 20), hl[1], 9, HEART)
	_text(Vector2(8, 34), sub, 8, SOFT, vs.x - 16)
	var ids := _ids()
	if ids.is_empty():
		_text(Vector2(8, 60), tr("Nobody close enough to Ash yet."), 10, TEXT)
		return
	var y := 44.0
	var fits := maxi(int((vs.y - y - 22.0) / ROW_H), 1)
	scroll = clampi(scroll, maxi(sel - fits + 1, 0), mini(sel, maxi(ids.size() - fits, 0)))
	if scroll > 0:
		_scroll_arrow(Vector2(8 + LIST_W / 2, y - 3), true)
	for i in range(scroll, mini(scroll + fits, ids.size())):
		var id: String = ids[i]
		var rr := Rect2(8, y, LIST_W, ROW_H - 3)
		_row_rects.append(rr)
		_row_index.append(i)
		var on := i == sel
		draw_rect(rr, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(rr, GOLD if focus == 0 else Color(0.5, 0.45, 0.35), false, 1.0)
		var accent := Color(Empire.bond_info(id).get("color", "c9c3b6"))
		draw_rect(Rect2(rr.position, Vector2(3, rr.size.y)), accent)
		var rank := Empire.bond_rank(id)
		_text(rr.position + Vector2(10, 12), Empire.recruit(id)["name"], 9, GOLD if on else TEXT, 110)
		_pips(rr.position + Vector2(130, 9), rank, HEART if not Betrayal.marked(id) else Color(0.55, 0.53, 0.58))
		_text_r(rr.position + Vector2(LIST_W - 6, 12), Empire.bond_rank_name(rank), 8, SOFT)
		_bar(Rect2(rr.position + Vector2(10, 18), Vector2(120, 4)), _progress(id), HEART if rank < Empire.BOND_MAX else GOOD)
		var ready_r := Empire.bond_next_scene(id)
		var mood := Empire.role_mood(id)
		if Betrayal.marked(id):  # Chapter 4 on: the heart goes grey (issue #186)
			_text(rr.position + Vector2(138, 25), tr("somewhere else"), 8, Color(0.6, 0.58, 0.63))
		elif ready_r > 0:
			_text(rr.position + Vector2(138, 25), tr("wants a word!"), 8, HEART)
		elif mood == "likes":
			_text(rr.position + Vector2(138, 25), tr("happy in role"), 8, GOOD)
		elif mood == "dislikes":
			_text(rr.position + Vector2(138, 25), tr("unhappy in role"), 8, BAD)
		if Empire.talked_today(id):
			_text(rr.position + Vector2(10, 29), tr("chatted today"), 7, DIM)
		y += ROW_H
	if scroll + fits < ids.size():
		_scroll_arrow(Vector2(8 + LIST_W / 2, y + 1), false)
	var missing := Empire.bond_cast().size() - ids.size()
	if missing > 0 and scroll + fits >= ids.size():
		_text(Vector2(10, y + 10), Loc.n("%d more person Ash could get close to hasn't joined yet.", "%d more people Ash could get close to haven't joined yet.", missing) % missing, 7, DIM, LIST_W)
	_draw_details(vs, ids[sel])
	_text(Vector2(8, vs.y - 8), Prompts.help([["updown", "choose"], ["ui_accept", tr("talk / scenes")], ["leftright", tr("people / scenes")], [["ui_cancel", "bonds"], "close"]], tr("Tap a name, tap again to talk   Tap a scene twice to play it")), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var w := font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		draw_rect(Rect2(vs.x - w - 18, vs.y - 21, w + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - w - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))


func _draw_details(vs: Vector2, id: String) -> void:
	var info := Empire.bond_info(id)
	var x := LIST_W + 24
	var w := vs.x - x - 10
	var top := 44.0
	draw_rect(Rect2(x - 8, top, w + 16, vs.y - top - 18), Color(0.08, 0.07, 0.1))
	draw_rect(Rect2(x - 8, top, 3, vs.y - top - 18), Color(info.get("color", "c9c3b6")))
	var r := Empire.recruit(id)
	var rank := Empire.bond_rank(id)
	var y := top + 14
	_text(Vector2(x, y), "%s, %s" % [r["name"], r.get("title", "")], 11, Color("f3efe4"), w)
	y += 12
	var pts := Loc.count("%d bond point", "%d bond points", Empire.bond_points(id))
	if rank < Empire.BOND_MAX:
		pts += tr(" (rank %d at %d)") % [rank + 1, Empire.bond_threshold(rank + 1)]
	_text(Vector2(x, y), tr("Rank %d, %s.  %s") % [rank, Empire.bond_rank_name(rank), pts], 8, HEART, w)
	y += 4
	var nxt := Empire.bond_next_text(id)
	y += _wrap(Vector2(x, y + 9), nxt, w, 8, HEART if Empire.bond_next_scene(id) > 0 else Color("e8d9a8")) + 4
	# Likes and what they are doing now
	y += _wrap(Vector2(x, y + 9), tr("Likes: %s.") % info.get("likes_text", "?"), w, 8, Color("cfe0b0")) + 1
	y += _wrap(Vector2(x, y + 9), tr("Dislikes: %s.") % info.get("dislikes_text", "?"), w, 8, Color(0.85, 0.65, 0.6)) + 1
	var mood := Empire.role_mood(id)
	var pts_cfg: Dictionary = Empire.bond_data["points"]
	var now := tr("Now: %s") % Empire.role_label(id)
	if mood == "likes":
		now += tr(", which they like (+%d a day).") % int(pts_cfg["liked_role"])
	elif mood == "dislikes":
		now += tr(", which they dislike (%d a day).") % int(pts_cfg["disliked_role"])
	else:
		now += "."
	y += _wrap(Vector2(x, y + 9), now, w, 8, GOOD if mood == "likes" else (BAD if mood == "dislikes" else SOFT)) + 6
	# Perks
	_text(Vector2(x, y + 8), tr("Perks"), 9, Color(0.75, 0.72, 0.7))
	y += 11
	var perks: Dictionary = info.get("perks", {})
	for k in perks:
		var pk: Dictionary = perks[k]
		var got := rank >= int(k)
		y += _wrap(Vector2(x, y + 9), tr("%s Rank %s, %s: %s") % ["+" if got else "-", k, pk["name"], pk["desc"]], w, 8, GOOD if got else DIM) + 1
	var pj := Empire.personal_job(id)
	if pj != "":
		var state := tr("unlocks at rank 4")
		var col := DIM
		if Empire.personal_done(id):
			state = "done"
			col = GOOD
		elif Empire.personal_lost(id) != "":
			state = tr("lost with %s, which the Blank erased. Reclaim it to bring the mission back") % Empire.personal_lost(id)
			col = BAD
		elif rank >= 4:
			var pd := PersonalMissions.def_for(id)
			state = tr("waiting at %s on the Command Table") % Empire.territory().find(pd.get("province", "")).get("name", "?")
			var why := PersonalMissions.blocker(id)
			if why != "":
				state += " (%s)" % why
			col = GOLD
		y += _wrap(Vector2(x, y + 9), tr("Personal mission, %s: %s.") % [PersonalMissions.def_for(id).get("name", "?"), state], w, 8, col) + 1
	# Romance, friends and rivals (issue #116)
	var rs := Relationships.status_text(id)
	if rs != "":
		var rcol := HEART if Relationships.romance_of(id) == "partner" or Relationships.moment_ready(id) else (BAD if Relationships.romance_of(id) == "ex" else SOFT)
		y += _wrap(Vector2(x, y + 9), rs, w, 8, rcol) + 1
	var kin := {"friends": [], "rivals": [], "truce": []}
	for pr in Relationships.pairs_of(id):
		if Empire.recruits.has(pr[1]):
			kin[pr[0]["kind"]].append(Empire.short_name(pr[1]))
	var bits := []
	for k in ["friends", "truce", "rivals"]:
		if not kin[k].is_empty():
			bits.append("%s: %s" % [{"friends": tr("Gets on with"), "truce": tr("Made peace with"), "rivals": tr("Can't stand")}[k], ", ".join(kin[k])])
	if not bits.is_empty():
		y += _wrap(Vector2(x, y + 9), tr("%s.  (Posting them together matters: see Roster, Buildings, Expeditions, party.)") % ".  ".join(bits), w, 8, Color("b9c4d8")) + 1
	y += 8
	# Scenes
	_text(Vector2(x, y + 8), tr("Scenes"), 9, Color(0.75, 0.72, 0.7))
	y += 12
	var rows := _scene_rows()
	for i in rows.size():
		var row: Dictionary = rows[i]
		var rr := Rect2(x - 2, y, w, SCENE_ROW_H - 2)
		_scene_rects.append(rr)
		var on := focus == 1 and i == scene_sel
		if on:
			draw_rect(rr, Color(0.17, 0.14, 0.09))
			draw_rect(rr, GOLD, false, 1.0)
		var label := ""
		var col := DIM
		match row["state"]:
			"seen":
				label = "%s. %s" % [row.get("num", str(row["rank"])), row["title"]]
				col = TEXT
			"ready":
				label = tr("%s. %s  (new: %s to play)") % [row.get("num", str(row["rank"])), row["title"], Prompts.confirm()]
				col = HEART
			_:
				label = "%s. ???" % row.get("num", str(row["rank"]))
		_text(rr.position + Vector2(4, 9), label, 8, GOLD if on and row["state"] != "locked" else col, w - 8)
		y += SCENE_ROW_H
