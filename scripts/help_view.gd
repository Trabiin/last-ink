class_name HelpView
extends Control
## The Help screen (issue #115): every explainer, unlock and tip in data/help.json, the controls
## on the device in use, and the switch for tips. "Help" in the pause menus in town, at the Command
## Table and in missions. The same words are also in the journal's codex under "Help & tips".
##
## Up / Down picks a row; Confirm on a topic replays it (the card plays over this screen), on the
## switch flips it. Right moves to the page, where Up / Down scrolls; Left or Back comes back.
## Back closes. Mouse: click a row, click again to act, wheel scrolls. Touch: tap, tap again, drag the page.

signal closed

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.62, 0.6, 0.62)
const DIM := Color(0.42, 0.41, 0.44)
const HEAD := Color("c9a46a")
const INK := UiSkin.PAGE_INK
const INK_SOFT := UiSkin.PAGE_INK_SOFT
const ROW_H := 15.0
const LIST_W := 200.0
const TOP := 30.0
const LINE := 13.0
const BODY := 10

## The controls page: [heading, [[what, actions or "move"], ...]].
const CONTROLS := [
	["In town and at the table", [["Move / pick a province", "move"], ["Talk, use, confirm", ["attack", "ui_accept"]],
		["Back / close", ["ui_cancel"]], ["Menu", ["pause"]], ["Go to the newest alert", ["alert_go"]],
		["Clock slower / faster", ["clock_slower", "clock_faster"]], ["Clock: stop, 1x, 2x, 4x", ["clock_speed_0", "clock_speed_1", "clock_speed_2", "clock_speed_3"]],
		["Ledger", ["ledger"]], ["Zoom the map", ["map_zoom_in", "map_zoom_out", "map_zoom_toggle"]]]],
	["Screens", [["Roster", ["roster"]], ["Buildings", ["buildings"]], ["Governor", ["govern"]], ["Expeditions", ["expeditions"]],
		["Research", ["research"]], ["Diplomacy", ["diplomacy"]], ["Bonds", ["bonds"]], ["Newcomers", ["newcomers"]],
		["Party gear & shop", ["gear"]], ["Forge & Market", ["armory"]], ["Journal", ["journal"]]]],
	["In the field", [["Move", "move"], ["Attack (hold: charged tech)", ["attack"]], ["Swap hero", ["swap"]],
		["Abilities", ["ability_1", "ability_2", "ability_3", "ability_4"]], ["Quick menu", ["quick_menu"]], ["Pause", ["pause"]], ["Screenshot", ["screenshot"]]]],
]
const TOUCH_CONTROLS := [
	["In town and at the table", ["Drag the stick on the left to walk; tap the hand button to talk or use.",
		"Tap a province to pick it, tap it again to act. Drag to pan, pinch to zoom.",
		"The buttons along the top open every screen. Tap the menu button for the rest."]],
	["In the field", ["The stick on the left moves. Attack is the big button; hold it when the gauge is full for a charged tech.",
		"The small buttons round Attack are abilities. The menu button opens the quick menu."]],
]

var sel := 0
var focus := 0  # 0 = list, 1 = page
var page_scroll := 0.0
var page_h := 0.0
var list_scroll := 0
var opened_frame := -1
var closed_frame := -1
var font: Font
var _rows: Array = []  # {"head": text} | {"kind": "topic", "id"} | {"kind": "tips"} | {"kind": "controls"}
var _row_rects: Array = []
var _replay_rect := Rect2()
var _drag := 0.0


## Pops the Help screen up over `host` (on the pause menu's layer) and returns it.
static func popup(host: Node, layer := 6) -> HelpView:
	var cl := CanvasLayer.new()
	cl.layer = layer
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(cl)
	HelpCard.ensure(host)
	var v := HelpView.new()
	cl.add_child(v)
	v.closed.connect(cl.queue_free)
	v.open()
	return v


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font


func open(topic_id := "") -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	focus = 0
	_rebuild()
	if topic_id != "":
		for i in _rows.size():
			if _rows[i].get("id", "") == topic_id:
				sel = i


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _rebuild() -> void:
	_rows = [{"head": tr("Help")}, {"kind": "tips"}, {"kind": "controls"}]
	for g in Help.GROUPS:
		var ts := Help.topics().filter(func(t): return t.get("group", "") == g)
		if ts.is_empty():
			continue
		_rows.append({"head": Loc.t(Help.GROUP_NAMES.get(g, g))})
		for t in ts:
			_rows.append({"kind": "topic", "id": t["id"]})
	sel = clampi(sel, 0, _rows.size() - 1)
	if _rows[sel].has("head"):
		_move(1)


func _row() -> Dictionary:
	return _rows[sel] if sel >= 0 and sel < _rows.size() else {}


func _move(d: int) -> void:
	for n in _rows.size():
		sel = posmod(sel + d, _rows.size())
		if not _rows[sel].has("head"):
			break
	page_scroll = 0.0


func _activate() -> void:
	var row := _row()
	match row.get("kind", ""):
		"tips":
			Settings.set_tips(not Settings.tips_enabled())
		"topic":
			var t := Help.topic(row["id"])
			if t.get("kind", "") == "unlock" and not _unlock_open(t):
				if is_instance_valid(Help.card):
					Help.card.show_talk(str(t.get("title", "")), Help.lines(t, "locked"), self)
			else:
				Help.play(row["id"], self)
		_:
			focus = 1


func _unlock_open(t: Dictionary) -> bool:
	return not Story.active() or Help.meets(t.get("when", {}))


func _process(_delta: float) -> void:
	if not visible:
		return
	if size != get_viewport_rect().size:
		size = get_viewport_rect().size
	queue_redraw()
	if Engine.get_process_frames() == opened_frame or Help.busy():
		return
	if is_instance_valid(Help.card) and Engine.get_process_frames() - Help.card.closed_frame <= 1:
		return  # the key that closed the card
	var up := _just("move_up") or _just("ui_up")
	var down := _just("move_down") or _just("ui_down")
	if focus == 0:
		if up:
			_move(-1)
		elif down:
			_move(1)
		elif _just("ui_accept"):
			_activate()
		elif _just("move_right") or _just("ui_right"):
			focus = 1
		elif _just("ui_cancel") or _just("pause"):
			close()
	else:
		if up:
			page_scroll = maxf(page_scroll - LINE * 3, 0.0)
		elif down:
			page_scroll = minf(page_scroll + LINE * 3, _max_scroll())
		elif _just("ui_accept"):
			_activate()
		elif _just("move_left") or _just("ui_left") or _just("ui_cancel") or _just("pause"):
			focus = 0


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _max_scroll() -> float:
	return ceilf(maxf(page_h - (_page_rect().size.y - 30.0), 0.0) / LINE) * LINE


func _gui_input(event: InputEvent) -> void:
	if Help.busy():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var d := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		if _page_rect().has_point(event.position):
			page_scroll = clampf(page_scroll + d * LINE * 2, 0.0, _max_scroll())
		else:
			_move(d)
		accept_event()
		return
	if event is InputEventScreenDrag and _page_rect().has_point(event.position):
		_drag -= event.relative.y
		var n := roundi(_drag / LINE)
		if n != 0:
			_drag -= n * LINE
			page_scroll = clampf(page_scroll + n * LINE, 0.0, _max_scroll())
		return
	if not Prompts.tapped(event):
		return
	accept_event()
	var pos: Vector2 = event.position
	if _close_rect().has_point(pos):
		close()
		return
	if _replay_rect.has_point(pos):
		_activate()
		return
	for rr in _row_rects:
		if (rr[0] as Rect2).has_point(pos):
			if int(rr[1]) == sel:
				_activate()
			else:
				sel = int(rr[1])
				page_scroll = 0.0
			focus = 0
			return


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 5), Vector2(50, 16))


func _page_rect() -> Rect2:
	return Rect2(LIST_W + 22, TOP + 2, size.x - LIST_W - 30, size.y - TOP - 20)


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0, f: Font = null) -> void:
	draw_string(f if f else font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _tw(s: String, fsize: int, f: Font = null) -> float:
	return (f if f else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x


func _wrap(s: String, w: float, fsize: int) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var cand := word if line == "" else line + " " + word
			if line != "" and _tw(cand, fsize) > w:
				out.append(line)
				line = word
			else:
				line = cand
		out.append(line)
	return out


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	_row_rects.clear()
	_replay_rect = Rect2()
	_text(Vector2(10, 20), tr("Help"), 18, Color("f3e3c3"), -1, UiSkin.TITLE_FONT)
	_text(Vector2(56, 19), tr("Everything the cast has explained, and the controls on this %s.") % _device_word(), 8, SOFT)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	_draw_list(vs)
	_draw_page()
	var help := [["updown", "choose"], ["ui_accept", tr("replay / switch")], ["leftright", tr("list / page")], ["ui_cancel", "close"]]
	_text(Vector2(10, vs.y - 6), Prompts.help(help, tr("Tap a row, tap it again to replay. Drag the page to scroll.")), 7, Color(0.5, 0.48, 0.52))


func _device_word() -> String:
	return {Prompts.KEYS: Loc.t("keyboard"), Prompts.PAD: Loc.t("gamepad"), Prompts.TOUCH: tr("touch screen")}.get(Prompts.device, Loc.t("device"))


func _draw_list(vs: Vector2) -> void:
	var y := TOP
	var fits := maxi(int((vs.y - y - 18.0) / ROW_H), 1)
	list_scroll = clampi(list_scroll, maxi(sel - fits + 1, 0), mini(sel, maxi(_rows.size() - fits, 0)))
	if sel <= fits - 1:
		list_scroll = 0
	for i in range(list_scroll, mini(list_scroll + fits, _rows.size())):
		var row: Dictionary = _rows[i]
		var rr := Rect2(8, y, LIST_W, ROW_H - 1)
		y += ROW_H
		if row.has("head"):
			_text(rr.position + Vector2(2, 11), str(row["head"]).to_upper(), 8, HEAD, LIST_W)
			draw_rect(Rect2(rr.position + Vector2(2, 13), Vector2(LIST_W - 4, 1)), Color(HEAD, 0.35))
			continue
		_row_rects.append([rr, i])
		var on := i == sel
		if on:
			UiSkin.panel(self, rr.grow_individual(0, 1, 0, 1), "button", Color(1.2, 1.1, 0.9) if focus == 0 else Color(0.8, 0.76, 0.72))
		var col := GOLD if on else TEXT
		match row["kind"]:
			"tips":
				_text(rr.position + Vector2(8, 11), tr("Tips as things happen"), 9, col, LIST_W - 40)
				var st := tr("On") if Settings.tips_enabled() else tr("Off")
				_text(rr.position + Vector2(LIST_W - _tw(st, 9) - 6, 11), st, 9, Color("9fd18b") if Settings.tips_enabled() else Color("ff9b8a"))
			"controls":
				_text(rr.position + Vector2(8, 11), tr("Controls"), 9, col, LIST_W - 12)
			"topic":
				var t := Help.topic(row["id"])
				var locked: bool = t.get("kind", "") == "unlock" and not _unlock_open(t)
				_text(rr.position + Vector2(8, 11), str(t.get("title", "")), 9, (SOFT if not on else GOLD) if locked else col, LIST_W - 26)
				if t.get("kind", "") in ["tip", "screen", "unlock"] and not Help.seen(row["id"]):
					draw_circle(rr.position + Vector2(LIST_W - 8, 7), 2.0, Color(DIM, 0.9))  # not heard yet


## The page as blocks, laid out and drawn with the scroll offset, clipped to the page.
## Block: ["title", text] | ["sub", text] | ["head", text] | ["para", text, speaker] | ["key", what, keys] | ["gap"] | ["replay", label]
func _blocks() -> Array:
	var row := _row()
	var b := []
	match row.get("kind", ""):
		"tips":
			b.append(["title", tr("Tips as things happen")])
			b.append(["sub", tr("Now: on") if Settings.tips_enabled() else tr("Now: off")])
			b.append(["gap"])
			b.append(["para", tr("When on, the cast explains each screen of the Command Table the first time it opens, and speaks up the first time something new happens: a surge, an erased province, an injury, the Concord making trouble."), ""])
			b.append(["gap"])
			b.append(["para", tr("When off, they keep quiet. The story still opens the empire a piece at a time, and says so. Everything they would have said is here, and in the journal's codex under Help & tips."), ""])
			b.append(["gap"])
			b.append(["replay", tr("Switch tips off") if Settings.tips_enabled() else tr("Switch tips on")])
		"controls":
			b.append(["title", tr("Controls")])
			b.append(["sub", tr("As set up on this %s. Change keys and buttons in Options.") % _device_word()])
			if Prompts.touch():
				for sec in TOUCH_CONTROLS:
					b.append(["gap"])
					b.append(["head", tr(sec[0])])
					for l in sec[1]:
						b.append(["para", tr(l), ""])
			else:
				for sec in CONTROLS:
					b.append(["gap"])
					b.append(["head", tr(sec[0])])
					for c in sec[1]:
						var keys := _keys_text(c[1])
						if keys != "":
							b.append(["key", tr(c[0]), keys])
		"topic":
			var t := Help.topic(row["id"])
			var kind: String = t.get("kind", "")
			b.append(["title", str(t.get("title", ""))])
			var sub: String = str(t.get("summary", ""))
			b.append(["sub", sub])
			b.append(["gap"])
			if kind == "unlock" and not _unlock_open(t):
				var note := Help.locked_note(str(t.get("screens", [""])[0]))
				b.append(["head", tr("Not open yet") + ((": " + note) if note.begins_with("day") else "")])
				for l in Help.lines(t, "locked"):
					b.append(["para", l[1], l[0]])
			else:
				for l in Help.lines(t):
					b.append(["para", l[1], l[0]])
			b.append(["gap"])
			var when: String = {"screen": tr("Plays the first time the screen opens."), "unlock": tr("The story opens this in the first days of Act 1."),
				"tip": tr("Said the first time it happens."), "manual": tr("Field notes.")}.get(kind, "")
			if kind != "manual":
				when += tr("  Heard already.") if Help.seen(row["id"]) else tr("  Not heard yet.")
			b.append(["sub", when])
			b.append(["gap"])
			b.append(["replay", tr("Hear it again") if Help.seen(row["id"]) or kind == "manual" else tr("Hear it now")])
	return b


## "Up/Down", "1 / 2 / 3 / 4", "A"...: the keys for these actions on the device in use.
func _keys_text(what) -> String:
	if what is String and what == "move":
		return tr("Stick / D-pad") if Prompts.pad() else tr("WASD / arrows")
	var seen := PackedStringArray()
	for a in what:
		var k := Prompts.key(a)
		if k != "" and not seen.has(k):
			seen.append(k)
	return " / ".join(seen)


func _draw_page() -> void:
	var pr := _page_rect()
	UiSkin.page(self, pr)
	var x := pr.position.x + 30
	var w := pr.size.x - 52
	var y := pr.position.y + 20 - page_scroll
	var top := pr.position.y + 4
	var bottom := pr.end.y - 4
	var start := y
	var last_who := ""
	for bl in _blocks():
		match bl[0]:
			"title":
				if y > top and y < bottom:
					_text(Vector2(x, y), bl[1], 16, INK, w, UiSkin.TITLE_FONT)
				y += LINE + 3
			"sub":
				for l in _wrap(str(bl[1]), w, 8):
					if y > top and y < bottom:
						_text(Vector2(x, y), l, 8, INK_SOFT, w)
					y += LINE
			"head":
				if y > top and y < bottom:
					_text(Vector2(x, y), str(bl[1]).to_upper(), 8, Color("8a2a22"), w)
				y += LINE
			"para":
				var who: String = bl[2]
				if who != "" and who != last_who:
					if y > top and y < bottom:
						_text(Vector2(x, y), Dialogue.display_name(who), 12, INK, w, UiSkin.TITLE_FONT)
					y += LINE
				last_who = who
				for l in _wrap(str(bl[1]), w, BODY):
					if y > top and y < bottom:
						_text(Vector2(x, y), l, BODY, INK, w)
					y += LINE
				y += LINE * 0.35  # a breath between paragraphs
			"key":
				if y > top and y < bottom:
					_text(Vector2(x, y), str(bl[1]), 9, INK, w * 0.6)
					_text(Vector2(x + w * 0.62, y), str(bl[2]), 9, Color("2f3a5a"), w * 0.38)
				y += LINE
			"gap":
				y += LINE * 0.5
			"replay":
				var r := Rect2(x - 4, y - 10, _tw(str(bl[1]), 9) + 22 + _tw(Prompts.confirm(), 7), 15)
				if r.position.y > top and r.end.y < bottom:
					_replay_rect = r
					UiSkin.panel(self, r, "button")
					_text(r.position + Vector2(8, 11), str(bl[1]), 9, GOLD)
					_text(r.position + Vector2(r.size.x - _tw(Prompts.confirm(), 7) - 6, 11), Prompts.confirm(), 7, SOFT)
				y += LINE + 4
	page_h = y + page_scroll - start
	if page_scroll > 0.0:
		_arrow(Vector2(pr.get_center().x, pr.position.y + 6), true)
	if page_scroll < _max_scroll():
		_arrow(Vector2(pr.get_center().x, pr.end.y - 6), false)


func _arrow(at: Vector2, up: bool) -> void:
	var d := -3.0 if up else 3.0
	draw_colored_polygon(PackedVector2Array([at + Vector2(-5, -d / 3), at + Vector2(5, -d / 3), at + Vector2(0, d)]), Color(INK, 0.6))
