class_name PartyPicker
extends Control
## Before a mission: pick up to three field heroes to take along (issue #10).
##
## Ash always leads. Anyone else needs to be a field hero who has joined, is not injured,
## and is not busy governing, staffing, envoying or out on an expedition (free them in the
## Roster first; R jumps there). Picks are the same "party" role the Roster uses, so they stick
## between missions. Combat stats come from data/heroes.json, looks from data/recruits.json.
## Only heroes who have joined get a row: the ones still out there are a single "not found yet" card
## under the list, with the rumours the player can act on and no names or stats (no spoilers).
## Rows grow with the text size and the list scrolls once it outgrows the screen.
## The static helpers at the bottom are what main.gd uses to put the party on the field.

signal confirmed(mission: Dictionary)
signal closed
signal roster_requested

const HEROES_FILE := "res://data/heroes.json"
const GOLD := Color("ffd166")
const PAPER := Color("f3efe4")
const DIM := Color(0.45, 0.44, 0.47)
const RUMOUR := Color("c9b6e8")
const ROW_PAD := 4.0  # above the name and below the last status line
const ROW_GAP := 3.0
const LIST_X := 8.0
const LIST_W := 300.0
const DETAIL_X := 322.0
const DOLL_SCALE := 3.0
const DOLL_HEAD := 34.0  # how far the dolls' heads stand above their box: the detail text stops above them

static var _data := {}

var mission := {}
var sel := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var font: Font
var _row_rects: Array = []  # one per joined hero; Rect2() for rows scrolled out of sight
var scroll := 0  # first hero row drawn
var _list_drag := {}  # a finger dragged over the list (Prompts.list_steps)
var _row_px := 30.0  # a typical row's height, for drags
var _card_rect := Rect2()  # the "not found yet" card
## Every line of text drawn last frame as [text rect, the box it belongs in, what it is] (for tests).
var drawn_text: Array = []
var _go_rect := Rect2()
var _back_rect := Rect2()
var _dolls: Array = []  # [body Sprite2D, outfit Sprite2D, art pass Sprite2D] per preview slot
var _doll_ids: Array = []
var _doll_y := 0.0  # where the dolls stand, set by _draw
var t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	for i in Empire.PARTY_SIZE:
		var pair := []
		for k in 2:
			var s := Sprite2D.new()
			s.hframes = 24
			s.vframes = 8
			s.scale = Vector2(DOLL_SCALE, DOLL_SCALE)
			s.visible = false
			add_child(s)
			pair.append(s)
		var a := Sprite2D.new()  # art pass sprite (scripts/sprite_set.gd), used when the hero has one
		a.scale = Vector2(DOLL_SCALE, DOLL_SCALE)
		a.visible = false
		add_child(a)
		pair.append(a)
		_dolls.append(pair)
		_doll_ids.append("")


func open(m: Dictionary) -> void:
	mission = m
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	sel = clampi(sel, 0, _ids().size())


## Back from the Roster: same mission, fresh availability.
func reopen() -> void:
	open(mission)


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


## The field heroes who have joined, in roster order (Ash first): the rows of the list.
func _ids() -> Array:
	return _field_ids().filter(func(id): return Empire.recruits.has(id))


## Field heroes nobody has found yet. They stay off the list (no names, no stats) and only show as a count
## and the rumours that point the way.
func _unfound() -> Array:
	return _field_ids().filter(func(id): return not Empire.recruits.has(id))


static func _field_ids() -> Array:
	var out := []
	for id in Empire.recruit_data:
		if Empire.recruit_data[id].get("tier", "") == "field":
			out.append(id)
	return out


## The lines on the "not found yet" card: a count, then one line per rescue rumour on the Expeditions board.
func _unfound_lines() -> Array:
	var lost := _unfound()
	if lost.is_empty():
		return []
	var out := [[Loc.n("%d more hero is out there, not found yet.", "%d more heroes are out there, not found yet.", lost.size()) % lost.size(), DIM]]
	for id in lost:
		var how := Empire.join_hook(id)
		if how.get("type", "") != "rescue":
			continue
		var jid := str(how.get("job", ""))
		var rumour := str(Empire.job(jid).get("name", "?"))
		if not Empire.expedition_running(jid).is_empty():
			out.append([tr("%s. A squad is on its way.") % rumour, RUMOUR])
		else:
			out.append([tr("%s. Rescue job on the Expeditions board%s.") % [rumour, Prompts.tag("expeditions")], RUMOUR])
	return out


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	_update_dolls()
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return  # the key that opened the picker must not also act inside it
	var n := _ids().size() + 1  # the last row is "Set out"
	sel = clampi(sel, 0, n - 1)  # someone left the roster while the picker was shut
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		sel = posmod(sel - 1, n)
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		sel = posmod(sel + 1, n)
	if Input.is_action_just_pressed("ui_accept"):
		_press(sel)
	elif Input.is_action_just_pressed("roster"):
		_to_roster()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		close()


func _press(i: int) -> void:
	var ids := _ids()
	if i >= ids.size():
		_set_out()
	else:
		_toggle(ids[i])


func _toggle(id: String) -> void:
	var nm := short_of(id)
	if not Empire.recruits.has(id):
		_say(tr("%s hasn't joined yet.") % Empire.recruit(id)["name"])
	elif Empire.recruit(id).get("locked_party", false):
		_say(tr("Ash always leads."))
	elif id == str(mission.get("force", "")):
		_say(tr("It's %s's fight: they're coming.") % nm)  # personal missions (#113)
	elif Empire.role_of(id) == "party":
		Empire.assign(id, "idle")
		_say(tr("%s stays in Hollowmark.") % nm)
	elif blocker(id) != "":
		_say(tr("%s can't come: %s.") % [nm, blocker(id)])
	elif Empire.party_ids().size() >= Empire.PARTY_SIZE:
		_say(tr("The party is full. Leave someone behind first."))
	elif Empire.assign(id, "party"):
		_say(tr("%s is in.") % nm)


func _set_out() -> void:
	if mission_party(mission).is_empty():
		_say(tr("Nobody can go."))
		return
	visible = false
	closed_frame = Engine.get_process_frames()
	confirmed.emit(mission)


func _to_roster() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	roster_requested.emit()


func _say(s: String) -> void:
	flash = s
	flash_t = 2.8


func _gui_input(event: InputEvent) -> void:
	var rows := _ids().size()
	var on_list := Rect2(LIST_X, 0, LIST_W, _go_rect.position.y).has_point(event.position) if "position" in event else false
	var steps := Prompts.list_steps(event, _list_drag, _row_px, on_list)
	if steps != 0 and rows > 0:
		sel = clampi(mini(sel, rows - 1) + steps, 0, rows - 1)
		return
	if event is InputEventMouseMotion:
		var hit := _row_at(event.position)
		if hit >= 0:
			sel = hit
		if _go_rect.has_point(event.position):
			sel = rows
	elif event is InputEventScreenTouch or event is InputEventMouseButton:
		# A finger acts when it lifts without having dragged the list; a click acts at once.
		var hit := _row_at(event.position)
		if hit >= 0 and Prompts.list_tap(event, _list_drag, hit, sel) != "":
			sel = hit
			_press(hit)
			return
		if Prompts.tapped(event):
			if _go_rect.has_point(event.position):
				_set_out()
			elif _back_rect.has_point(event.position):
				close()


func _row_at(p: Vector2) -> int:
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(p):
			return i
	return -1


# ---------------------------------------------------------------- drawing

## One line of text with its top-left at `pos`, trimmed with "..." to max_w, kept for the layout tests.
func _text(pos: Vector2, s: String, fsize: int, col: Color, max_w := -1.0, box := Rect2()) -> void:
	if max_w >= 0.0:
		s = Access.fit(font, s, Access.fs(fsize), max_w)
	if s == "":
		return
	draw_string(font, pos + Vector2(0, font.get_ascent(Access.fs(fsize))), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)
	var r := Rect2(pos, Vector2(font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x, _lh(fsize)))
	drawn_text.append([r, box if box.size != Vector2.ZERO else Rect2(Vector2.ZERO, size), s])


## Height of one line at this (unscaled) size, as the text size and font draw it now.
func _lh(fsize: int) -> float:
	return font.get_height(Access.fs(fsize))


func _lines(s: String, fsize: int, w: float) -> PackedStringArray:
	return InkMenu.wrap_px(font, s, Access.fs(fsize), w)


## Wrapped text from `top` down, never past `bottom`: the last line that fits ends in "..." when more
## was cut. Returns the height used.
func _wrap(top: float, x: float, s: String, w: float, fsize: int, col: Color, bottom: float, box := Rect2()) -> float:
	var lines := _lines(s, fsize, w)
	var lh := _lh(fsize)
	var y := top
	for i in lines.size():
		if y + lh > bottom:
			break
		var line := lines[i]
		if i < lines.size() - 1 and y + 2.0 * lh > bottom:
			line = Access.fit(font, line + " ...", Access.fs(fsize), w)  # the next line won't fit
		_text(Vector2(x, y), line, fsize, col, w, box)
		y += lh
	return y - top


## What the line under a joined hero's name says.
func _status(id: String) -> Array:
	if Empire.recruit(id).get("locked_party", false):
		return [tr("Leads the party"), GOLD]
	if id == str(mission.get("force", "")):
		return [tr("Personal: it's their fight, they're coming"), Color("f29bd0")]
	if Empire.role_of(id) == "party":
		return [tr("Coming along"), Color("9fe07a")]
	var b := blocker(id)
	if b != "":
		return [tr("Busy: %s  (R: Roster)") % b, Color("ff9b8a")]
	return [tr("Ready, stays home unless picked"), Color(0.75, 0.72, 0.7)]


func _row_height(id: String) -> float:
	return ROW_PAD * 2.0 + _lh(10) + _lines(str(_status(id)[0]), 8, LIST_W - 34).size() * _lh(8)


## A small gold arrow over/under the list when more rows are scrolled out of sight.
func _scroll_arrow(at: Vector2, up: bool) -> void:
	var d := -3.0 if up else 3.0
	draw_colored_polygon(PackedVector2Array([at + Vector2(-5, -d / 3), at + Vector2(5, -d / 3), at + Vector2(0, d)]), Color(GOLD, 0.8))


func _draw() -> void:
	var vs := size
	drawn_text.clear()
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.04, 0.07, 0.985))
	var screen := Rect2(Vector2.ZERO, vs)
	var party := mission_party(mission)
	_text(Vector2(LIST_X, 4), tr("Choose your party"), 15, PAPER, vs.x - 16)
	var hl := UiSkin.header_line(font, tr("Choose your party"), 15, "%s   %d/%d" % [mission.get("name", tr("Mission")), party.size(), Empire.PARTY_SIZE], 9, vs.x, 0.0, null, LIST_X)
	_text(Vector2(hl[0], 4 + font.get_ascent(Access.fs(15)) - font.get_ascent(Access.fs(9))), hl[1], 9, Color(0.75, 0.7, 0.55))
	var list_top := 4.0 + _lh(15) + 6.0

	# The buttons sit at the bottom; the "not found yet" card above them; the hero rows fill the rest.
	var bh := maxf(22.0, _lh(10) + 8.0)
	var gy := vs.y - 6.0 - bh
	var go_label := tr("Set out with %d") % party.size()
	var go_w := maxf(150.0, font.get_string_size(go_label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10)).x + 20.0)
	var back_w := maxf(70.0, font.get_string_size(tr("Back"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x + 24.0)
	go_w = minf(go_w, LIST_W - back_w - 8.0)
	_go_rect = Rect2(LIST_X, gy, go_w, bh)
	_back_rect = Rect2(LIST_X + go_w + 8.0, gy, back_w, bh)
	var list_bottom := gy - 6.0
	var card := _unfound_lines()
	_card_rect = Rect2()
	if not card.is_empty():
		var wrapped := []
		var ch := 8.0
		for c in card:
			var ls := _lines(str(c[0]), 8, LIST_W - 16)
			wrapped.append([ls, c[1]])
			ch += ls.size() * _lh(8)
		ch = minf(ch, (list_bottom - list_top) * 0.45)  # rows come first: a long card is cut short
		_card_rect = Rect2(LIST_X, list_bottom - ch, LIST_W, ch)
		list_bottom = _card_rect.position.y - 5.0
		draw_rect(_card_rect, Color(0.07, 0.06, 0.09))
		draw_rect(_card_rect, Color(0.2, 0.19, 0.23), false, 1.0)
		var cy := _card_rect.position.y + 4.0
		for c in wrapped:
			for line in c[0]:
				if cy + _lh(8) > _card_rect.end.y - 2.0:
					break
				_text(Vector2(LIST_X + 8, cy), line, 8, c[1], LIST_W - 16, _card_rect)
				cy += _lh(8)

	var ids := _ids()
	_row_rects.clear()
	var heights := []
	for id in ids:
		heights.append(_row_height(id))
	_row_px = _lh(10) + _lh(8) + ROW_PAD * 2.0
	var area := list_bottom - list_top
	var span := func(a: int, b: int) -> float:  # height of rows a..b drawn together
		var h := 0.0
		for k in range(a, b + 1):
			h += heights[k] + ROW_GAP
		return h - ROW_GAP
	scroll = clampi(scroll, 0, maxi(ids.size() - 1, 0))
	if sel < ids.size():
		scroll = mini(scroll, sel)
		while scroll < sel and span.call(scroll, sel) > area:
			scroll += 1
	while scroll > 0 and span.call(scroll - 1, ids.size() - 1) <= area:
		scroll -= 1  # no empty space under the last row while rows above are hidden
	var y := list_top
	var last := scroll - 1
	for i in ids.size():
		if i < scroll or y + heights[i] > list_bottom + 0.5:
			_row_rects.append(Rect2())
			continue
		last = i
		var id: String = ids[i]
		var r := Empire.recruit(id)
		var row := Rect2(LIST_X, y, LIST_W, heights[i])
		_row_rects.append(row)
		y += heights[i] + ROW_GAP
		var on := i == sel
		draw_rect(row, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
		if on:
			draw_rect(row, GOLD, false, 1.0)
		var box := Rect2(row.position + Vector2(8, row.size.y / 2.0 - 6.0), Vector2(12, 12))
		var picked := id in party
		draw_rect(box, Color(0.05, 0.04, 0.07))
		draw_rect(box, GOLD if picked else Color(0.35, 0.32, 0.38), false, 1.0)
		if picked:
			draw_rect(box.grow(-3), GOLD)
		var tx := row.position.x + 28.0
		var tw := LIST_W - 34.0
		var ny := row.position.y + ROW_PAD
		var name_s: String = Access.fit(font, str(r["name"]), Access.fs(10), tw)
		_text(Vector2(tx, ny), name_s, 10, GOLD if on else Color("ece6da"), tw, row)
		var nw := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10)).x + 6.0
		# The title sits on the name's baseline; it is the first thing to give way on a narrow row.
		var title_y := ny + font.get_ascent(Access.fs(10)) - font.get_ascent(Access.fs(8))
		if tw - nw > 24.0:
			_text(Vector2(tx + nw, title_y), str(r["title"]), 8, Color(0.6, 0.58, 0.6), tw - nw, row)
		var st := _status(id)
		var sy := ny + _lh(10)
		for line in _lines(str(st[0]), 8, tw):
			_text(Vector2(tx, sy), line, 8, st[1], tw, row)
			sy += _lh(8)
	if scroll > 0:
		_scroll_arrow(Vector2(LIST_X + LIST_W / 2.0, list_top - 3.0), true)
	if last < ids.size() - 1:
		_scroll_arrow(Vector2(LIST_X + LIST_W / 2.0, list_bottom + 2.0), false)

	var go_on := sel == ids.size()
	# Only the focused row or button wears the gold frame, so there is never a second cursor on screen.
	draw_rect(_go_rect, Color(0.26, 0.2, 0.08) if go_on else Color(0.13, 0.11, 0.09))
	draw_rect(_go_rect, GOLD if go_on else Color(0.45, 0.38, 0.24), false, 2.0 if go_on else 1.0)
	_text(_go_rect.position + Vector2(10, (bh - _lh(10)) / 2.0), go_label, 10, GOLD if go_on else Color("ece6da"), go_w - 14, _go_rect)
	draw_rect(_back_rect, Color(0.1, 0.09, 0.12))
	draw_rect(_back_rect, Color(0.3, 0.27, 0.33), false, 1.0)
	_text(_back_rect.position + Vector2(12, (bh - _lh(9)) / 2.0), tr("Back"), 9, Color(0.75, 0.72, 0.7), back_w - 16, _back_rect)

	# The party, standing in a row, above the controls line
	var x := DETAIL_X
	var w := vs.x - DETAIL_X - 8
	var foot := vs.y - 3.0 - _lh(7)  # the controls line
	var pn := Relationships.pairs_among(party)  # friends and rivals in this party (issue #116)
	if not pn.is_empty():
		foot -= _lh(7)
		var tip := "   ".join(pn.map(func(p): return Relationships.pair_title(p)))
		_text(Vector2(x, foot), tip, 7, Color("9fe07a") if pn.all(func(p): return p["kind"] != "rivals") else Color("ffc48a"), w, screen)
	var dh := 54.0 + _lh(8)  # the names under the dolls grow with the text; the dolls' feet stay clear of them
	var doll_box := Rect2(x, foot - 2.0 - dh, w, dh)
	draw_rect(doll_box, Color(0.08, 0.07, 0.1))
	draw_rect(doll_box, Color(0.25, 0.22, 0.28), false, 1.0)
	for i in Empire.PARTY_SIZE:
		var cx := x + w * (i + 0.5) / Empire.PARTY_SIZE
		var cw := w / Empire.PARTY_SIZE - 6.0
		if i < party.size():
			var nm := Access.fit(font, short_of(party[i]), Access.fs(8), cw)
			var nmw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
			_text(Vector2(cx - nmw / 2.0, doll_box.end.y - 3.0 - _lh(8)), nm, 8, Color("ece6da"), cw, doll_box)
		else:
			var ew := font.get_string_size(Loc.t("empty"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
			_text(Vector2(cx - ew / 2.0, doll_box.get_center().y - _lh(8) / 2.0), Loc.t("empty"), 8, Color(0.35, 0.33, 0.38), cw, doll_box)
	_doll_y = doll_box.position.y + 10.0  # _update_dolls stands them 18 lower

	# Detail: how the highlighted hero fights
	var dbox := Rect2(x, list_top, w, doll_box.position.y - DOLL_HEAD - list_top)
	var bottom := dbox.end.y
	if sel < ids.size():
		_draw_detail(ids[sel], party, dbox)
	else:
		_text(Vector2(x, list_top + 4), tr("Ready?"), 13, PAPER, w, dbox)
		_wrap(list_top + 6 + _lh(13), x, tr("The clock stops while you are out. Whoever stays home keeps working their post."), w, 8, Color(0.68, 0.66, 0.68), bottom, dbox)

	var help := Prompts.help([["updown", "choose"], ["ui_accept", tr("pick or drop")], ["roster", "roster"], ["ui_cancel", "back"]], tr("Tap heroes to pick or drop them"))
	_text(Vector2(DETAIL_X, vs.y - 2.0 - _lh(7)), help, 7, Color(0.5, 0.48, 0.52), w, screen)
	if flash_t > 0.0:  # a toast over the bottom of the list, just above the buttons
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var fl := Access.fit(font, flash, Access.fs(9), LIST_W - 12)
		var fw := font.get_string_size(fl, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		var fr := Rect2(LIST_X, gy - 6.0 - _lh(9) - 4.0, fw + 12.0, _lh(9) + 4.0)
		draw_rect(fr, Color(0.1, 0.08, 0.06, 0.95 * a))
		draw_rect(fr, Color(GOLD, 0.5 * a), false, 1.0)
		_text(fr.position + Vector2(6, 2), fl, 9, Color(1, 0.9, 0.7, a), LIST_W - 12, fr)


func _draw_detail(id: String, party: Array, box: Rect2) -> void:
	var x := box.position.x
	var w := box.size.x
	var bottom := box.end.y
	var r := Empire.recruit(id)
	var hd := hero_data(id)
	var y := box.position.y + 4.0
	_text(Vector2(x, y), str(r["name"]), 13, PAPER, w, box)
	y += _lh(13)
	_text(Vector2(x, y), tr("Weapon: %s") % str(hd.get("weapon", "?")), 9, Color("e8c66a"), w, box)
	y += _lh(9) + 3.0
	var bars := [[tr("HP"), float(hd.get("hp", 40)), 70.0], [tr("Damage"), float(hd.get("damage", 10)), 16.0],
			[tr("Reach"), float(hd.get("reach", 20)), 30.0], [tr("Speed"), float(hd.get("speed", 68)), 80.0],
			[tr("Recovery"), float(hd.get("power_rate", 0.95)) * 100.0, 110.0]]
	var lw := 0.0
	for bar in bars:
		lw = maxf(lw, font.get_string_size(bar[0], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x)
	lw += 8.0
	var numw := font.get_string_size("000", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x + 6.0
	var bw := clampf(w - lw - numw, 40.0, 120.0)
	var step := maxf(11.0, _lh(8) + 1.0)
	for bar in bars:
		if y + step > bottom:
			break
		_text(Vector2(x, y), bar[0], 8, Color(0.72, 0.7, 0.72), lw, box)
		var by := y + (_lh(8) - 7.0) / 2.0
		draw_rect(Rect2(x + lw, by, bw, 7), Color(0.18, 0.16, 0.2))
		draw_rect(Rect2(x + lw, by, bw * clampf(bar[1] / bar[2], 0.05, 1.0), 7), Color(0.85, 0.78, 0.6))
		_text(Vector2(x + lw + bw + 6.0, y), str(int(bar[1])), 8, Color(0.85, 0.83, 0.78), numw, box)
		y += step
	var style: Dictionary = _load().get("styles", {}).get(AllyAI.preset_id(str(hd.get("ai", "balanced"))), {})
	y += 6.0
	if y + _lh(9) <= bottom:
		_text(Vector2(x, y), tr("As an ally: %s") % str(style.get("name", "?")), 9, Color("8fa7e8"), w, box)
		y += _lh(9) + 1.0
	y += _wrap(y, x, str(style.get("desc", "")), w, 8, Color(0.68, 0.66, 0.68), bottom, box) + 4.0
	y += _wrap(y, x, str(hd.get("special", "")), w, 8, Color("cfe0b0"), bottom, box) + 4.0
	var kit := []
	for a in Abilities.for_ids(hd.get("abilities", [])):
		kit.append(str(a.get("name", "")))
	var known := Skills.known_techs(id)
	var kit_line := tr("Abilities: %s") % ", ".join(kit)
	if not known.is_empty():  # weapon skill (issue #24): the techs learned so far
		kit_line += tr("   Techs (%s Lv %d): %s") % [Skills.weapon_name(id), Skills.weapon_level(id), ", ".join(known.map(func(t): return str(t.get("name", ""))))]
	y += _wrap(y, x, kit_line, w, 8, Color(0.78, 0.74, 0.86), bottom, box) + 4.0
	# Friends and rivals among the party (issue #116), as it would be with this hero in it.
	var with_me := party.filter(func(p): return p != id) + [id]
	for n in Relationships.notes(with_me, "party"):
		if Empire.short_name(id) in str(n[0]):
			y += _wrap(y, x, (str(n[0]) if id in party else tr("If picked: %s") % str(n[0])), w, 8, Color("9fe07a") if n[1] else Color("ff9b8a"), bottom, box) + 1.0


func _update_dolls() -> void:
	var party := mission_party(mission)
	var x := DETAIL_X
	var w := size.x - DETAIL_X - 8
	var py := _doll_y if _doll_y > 0.0 else size.y - 76
	var ids := _ids()
	var hl: String = ids[sel] if sel < ids.size() else ""
	for i in _dolls.size():
		var body: Sprite2D = _dolls[i][0]
		var outfit: Sprite2D = _dolls[i][1]
		var id: String = party[i] if i < party.size() else ""
		if id != _doll_ids[i]:
			_doll_ids[i] = id
			if id != "":
				var look: Dictionary = Empire.recruit(id).get("look", {})
				var cols := look_colors(look)
				var o: String = look.get("outfit", "archer")
				body.texture = Art.BODY
				body.material = Art.recolor_material("body", cols)
				outfit.texture = Art.OUTFITS.get(o, Art.OUTFITS["archer"])
				outfit.material = Art.recolor_material(o, cols)
		var pos := Vector2(x + w * (i + 0.5) / Empire.PARTY_SIZE, py + 18)
		# The highlighted hero walks on the spot; everyone else stands.
		var col := int(t * 8.0) % 4 if id == hl or hl == "" else 0
		var art_s: Sprite2D = _dolls[i][2]
		var sset := SpriteSet.of(id) if id != "" else null
		art_s.visible = sset != null
		if sset != null:
			art_s.position = pos + Vector2(0, 7 * DOLL_SCALE)  # feet line of the old doll frame
			sset.apply(art_s, "walk" if id == hl or hl == "" else "idle", 0, t)
		for s in [body, outfit]:
			(s as Sprite2D).visible = id != "" and sset == null
			(s as Sprite2D).position = pos
			(s as Sprite2D).frame = col


# ---------------------------------------------------------------- shared helpers

static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(HEROES_FILE, FileAccess.READ)
		if f:
			var d = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file())
			if d is Dictionary:
				_data = d
	return _data


static func hero_data(id: String) -> Dictionary:
	return _load().get("heroes", {}).get(id, {})


static func short_of(id: String) -> String:
	return str(hero_data(id).get("short", Empire.short_name(id)))


static func look_colors(look: Dictionary) -> Dictionary:
	var cols := {}
	for k in look.get("colors", {}):
		cols[k] = Color(look["colors"][k])
	return cols


## Why a joined field hero can't come right now ("" if they can).
static func blocker(id: String) -> String:
	if not Empire.recruits.has(id):
		return Loc.t("not joined")
	if Empire.recruit(id).get("tier", "") != "field":
		return Loc.t("not a fighter")
	var st: Dictionary = Empire.recruits[id]
	if str(st.get("role", "")) == Betrayal.AWAY_ROLE:  # the climax betrayal (issue #186)
		var why := Betrayal.away_label(id)
		return why if why != "" else Loc.t("gone")
	if int(st.get("injured", 0)) > 0:
		return Loc.n("injured, %d day", "injured, %d days", int(st["injured"])) % int(st["injured"])
	match st.get("role", "idle"):
		"idle", "party":
			return ""
		"expedition":
			return Loc.t("on an expedition")
		"governor":
			return Loc.t("governing %s") % str(Empire.territory().find(st.get("target", "")).get("name", Loc.t("a province")))
		"staff":
			return Loc.t("working the %s") % str(Empire.building(st.get("target", "")).get("name", Loc.t("town")))
		"envoy":
			return Loc.t("envoy to the %s") % str(Empire.faction(st.get("target", "")).get("short", "?"))
		_:
			return Empire.role_label(id).to_lower()


## Who actually goes out: Ash first, then the rest of the party who can fight today. A personal mission
## (#113) brings its hero along whatever the picks say: they take the last seat if the party is full.
static func mission_party(m := {}) -> Array:
	var out := []
	for id in Empire.party_ids():
		if blocker(id) == "" and Empire.recruit(id).get("tier", "") == "field":
			if Empire.recruit(id).get("locked_party", false):
				out.push_front(id)
			else:
				out.append(id)
	if out.is_empty() and Empire.recruits.has("ash"):
		out.append("ash")
	var force := str(m.get("force", ""))
	if force != "" and not force in out and blocker(force) == "":
		out = out.slice(0, Empire.PARTY_SIZE - 1)
		out.insert(mini(1, out.size()), force)
	return out.slice(0, Empire.PARTY_SIZE)


## Dresses and arms a freshly made Hero as recruit `id`.
static func apply(h: Hero, id: String) -> void:
	var hd := hero_data(id)
	var look: Dictionary = Empire.recruit(id).get("look", {})
	h.hero_id = id
	h.hero_name = short_of(id)
	h.outfit = look.get("outfit", "archer")
	h.colors = look_colors(look)
	h.max_hp = int(hd.get("hp", 40))
	h.hp = h.max_hp
	h.move_speed = float(hd.get("speed", 68))
	h.base_damage = int(hd.get("damage", 10))
	h.power_rate = float(hd.get("power_rate", 0.95))
	h.reach = float(hd.get("reach", 20))
	h.arc = deg_to_rad(float(hd.get("arc", 70)))
	var trail: Dictionary = hd.get("trail", {})
	h.trail_color = Color(str(trail.get("color", "e8e4d8")))
	h.trail_thrust = str(trail.get("style", "arc")) == "thrust"
	h.ai_style = AllyAI.preset_id(str(hd.get("ai", "balanced")))
	var heal: Dictionary = hd.get("heal", {})
	if not heal.is_empty():
		h.heal_every = float(heal.get("every", 6.0))
		h.heal_amount = int(heal.get("amount", 6))
		h.heal_range = float(heal.get("range", 80))
	h.poise = float(hd.get("poise", 1.0))
	h.set_abilities(hd.get("abilities", []), float(hd.get("ink", 12)))  # issue #7
	Progress.apply_to(h)  # levels and gear (issue #15)
