extends Control
## The journal screen (issue #114). I (rebindable) in town and at the Command Table, "Journal" in the
## menus, and in the mission pause menu. What it shows comes from scripts/journal.gd.
##
## Four tabs: Quests, People, Codex, History. Q / E, LB / RB (shown beside the tabs, TabStrip) or a tap
## switch tabs. Up / Down picks a
## row on the left; the right side is a torn ledger page with the details. Right (or Enter on most
## rows) moves to the page, where Up / Down scrolls; Left or Esc comes back. Enter on a quest is
## "show on map". The mouse wheel scrolls whichever side it is over. Esc or I closes.

signal closed
signal go(target: Dictionary)  # "show on map": the host closes the journal and goes there

const TABS := ["quests", "people", "codex", "history"]
const TAB_NAMES := {"quests": "Quests", "people": "People", "codex": "Codex", "history": "History"}
const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.62, 0.6, 0.62)
const DIM := Color(0.42, 0.41, 0.44)
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const HEAD := Color("c9a46a")
const INK := UiSkin.PAGE_INK
const INK_SOFT := UiSkin.PAGE_INK_SOFT
const INK_RED := Color("8a2a22")
const INK_GREEN := Color("2f5a2a")
const ROW_H := 15.0
const LIST_W := 214.0
const TOP := 34.0
const LINE := 13.0  # page text line height: matches the page's ruling
const BODY := 10
const SECTION_NAMES := {"story": "Main story", "personal": "Personal", "factions": "Factions", "open": "Open missions and threats"}
const GROUP_NAMES := {"roster": "On the roster", "gate": "Waiting at the south gate", "lead": "Rumours", "figure": "Others met"}
const HISTORY_FILTERS := ["", "mission", "expedition", "bond", "faction"]
const FILTER_NAMES := {"": "everything", "mission": "missions only", "expedition": "expeditions only", "bond": "people only", "faction": "faction requests only"}

var tab := 0
var sel := {}  # tab -> selected row index (rows that are headers are never selected)
var focus := 0  # 0 = list, 1 = page
var page_scroll := 0.0
var page_h := 0.0  # height of the page's content, for scrolling
var list_scroll := 0
var history_filter := 0
var can_go := true  # false mid-mission: the map is out of reach
var go_note := tr("after the mission")
var closed_frame := -1
var opened_frame := -1
var read_t := 0.0  # how long the selected codex entry has been on screen
var flash := ""
var flash_t := 0.0
var font: Font
var _rows: Array = []  # rows of the current tab: {"head": text} or {"kind", ...}
var _row_rects: Array = []  # [rect, row index]
var _strip := TabStrip.new()  # the tab row with its switch keys either side
var _go_rect := Rect2()
var _filter_rect := Rect2()
var _rule_base := 0.0
var _drag := 0.0  # touch drag on the page, before it snaps to whole ruled lines


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS  # also over the paused mission
	font = ThemeDB.fallback_font


## Opens on a tab ("quests", "people", "codex", "history"; "" = where it was left).
func open(which := "") -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	if which in TABS:
		tab = TABS.find(which)
	focus = 0
	_rebuild()


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _tab_id() -> String:
	return TABS[tab]


func _switch(d: int) -> void:
	tab = posmod(tab + d, TABS.size())
	focus = 0
	_rebuild()


## Builds the rows for the current tab, keeping the selection on a selectable row.
func _rebuild() -> void:
	_rows = []
	match _tab_id():
		"quests":
			var last := ""
			for q in Journal.quests():
				if q["section"] != last:
					last = q["section"]
					_rows.append({"head": Loc.t(SECTION_NAMES.get(last, last))})
				q["kind"] = "quest"
				_rows.append(q)
			if _rows.is_empty():
				_rows.append({"head": tr("Nothing to do. Suspicious.")})
		"people":
			var last := ""
			for p in Journal.people():
				if p["group"] != last:
					last = p["group"]
					_rows.append({"head": Loc.t(GROUP_NAMES.get(last, last))})
				p["kind"] = "person"
				_rows.append(p)
		"codex":
			for cat in Journal.CATS:
				var es := Journal.codex_in(cat)
				if es.is_empty():
					continue
				var n := es.filter(func(e): return e["unlocked"]).size()
				_rows.append({"head": "%s  %d/%d" % [Loc.t(Journal.CAT_NAMES[cat]), n, es.size()]})
				for e in es:
					e["kind"] = "codex"
					_rows.append(e)
		"history":
			_rows.append({"kind": "filter"})
			var chs := Journal.chapters_started()
			if not chs.is_empty():
				_rows.append({"head": tr("The story so far")})
				for i in range(chs.size() - 1, -1, -1):
					var c: Dictionary = chs[i]
					_rows.append({"kind": "chapter", "chapter": c, "title": c.get("title", "")})
			var lg := Journal.log_entries(HISTORY_FILTERS[history_filter])
			_rows.append({"head": tr("Missions and expeditions")})
			if lg.is_empty():
				_rows.append({"kind": "empty", "title": tr("Nothing written down yet.")})
			for e in lg:
				var row: Dictionary = e.duplicate()
				row["entry_kind"] = e["kind"]
				row["kind"] = "log"
				_rows.append(row)
	var s := int(sel.get(tab, -1))
	if s < 0 or s >= _rows.size() or _rows[s].has("head"):
		s = _first_pick()
	sel[tab] = s
	page_scroll = 0.0


func _first_pick() -> int:
	if _tab_id() == "history":  # land on the newest chapter, not the filter
		for i in _rows.size():
			if _rows[i].get("kind", "") == "chapter":
				return i
	for i in _rows.size():
		if not _rows[i].has("head"):
			return i
	return 0


func _row() -> Dictionary:
	var s := int(sel.get(tab, 0))
	return _rows[s] if s >= 0 and s < _rows.size() else {}


func _move(d: int) -> void:
	if _rows.is_empty():
		return
	var s := int(sel.get(tab, 0))
	for i in _rows.size():
		s = posmod(s + d, _rows.size())
		if not _rows[s].has("head"):
			break
	sel[tab] = s
	page_scroll = 0.0
	read_t = 0.0


func _process(delta: float) -> void:
	if not visible:
		return
	if size != get_viewport_rect().size:  # the window was resized while it was open
		size = get_viewport_rect().size
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	var row := _row()
	if row.get("kind", "") == "codex" and row.get("new", false):
		read_t += delta
		if read_t > 0.6:
			Journal.mark_read(row["id"])
			row["new"] = false
	if Engine.get_process_frames() == opened_frame:
		return
	var d := TabStrip.pressed()
	if d != 0:
		_switch(d)
		return
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
		elif _just("ui_cancel") or _just("pause") or _just("journal"):
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
		elif _just("journal"):
			close()


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


## Enter on a row: quests go to the map, the history filter cycles, anything else opens its page.
func _activate() -> void:
	var row := _row()
	match row.get("kind", ""):
		"quest":
			_go(row.get("target", {}))
		"filter":
			history_filter = (history_filter + 1) % HISTORY_FILTERS.size()
			_rebuild()
		_:
			focus = 1 if focus == 0 else focus


func _go(target: Dictionary) -> void:
	if target.is_empty():
		_say(tr("Nowhere on the map for this one."))
		return
	if not can_go:
		_say(tr("The map will have to wait until %s.") % go_note)
		return
	close()
	go.emit(target)


func _say(s: String) -> void:
	flash = s
	flash_t = 3.0


func _max_scroll() -> float:
	return ceilf(maxf(page_h - (_page_rect().size.y - 34.0), 0.0) / LINE) * LINE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var d := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		if _page_rect().has_point(event.position):
			page_scroll = clampf(page_scroll + d * LINE * 2, 0.0, _max_scroll())
		else:
			_move(d)
		accept_event()
		return
	if event is InputEventMouseMotion:
		for rr in _row_rects:
			if (rr[0] as Rect2).has_point(event.position) and int(rr[1]) != int(sel.get(tab, -1)):
				sel[tab] = int(rr[1])
				focus = 0
				page_scroll = 0.0
				read_t = 0.0
		return
	if event is InputEventScreenDrag and _page_rect().has_point(event.position):
		_drag -= event.relative.y
		var lines := roundi(_drag / LINE)
		if lines != 0:  # scroll in whole ruled lines so the writing stays on them
			_drag -= lines * LINE
			page_scroll = clampf(page_scroll + lines * LINE, 0.0, _max_scroll())
		return
	if not Prompts.tapped(event):
		return
	accept_event()
	if _close_rect().has_point(event.position):
		close()
		return
	var ti := _strip.hit(event.position)
	if ti >= 0:
		if ti != tab:
			tab = ti
			focus = 0
			_rebuild()
		return
	if _go_rect.has_area() and _go_rect.has_point(event.position):
		_go(_row().get("target", {}))
		return
	for rr in _row_rects:
		if (rr[0] as Rect2).has_point(event.position):
			var i := int(rr[1])
			var again := i == int(sel.get(tab, -1)) and focus == 0
			sel[tab] = i
			focus = 0
			if again or _rows[i].get("kind", "") == "filter":
				_activate()  # tap to pick, tap again to act (touch friendly)
			else:
				page_scroll = 0.0
				read_t = 0.0
			return
	if _page_rect().has_point(event.position):
		focus = 1


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 5), Vector2(50, 16))


func _page_rect() -> Rect2:
	return Rect2(LIST_W + 22, TOP + 2, size.x - LIST_W - 30, size.y - TOP - 22)


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0, f: Font = null) -> void:
	draw_string(f if f else font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _tw(s: String, fsize: int, f: Font = null) -> float:
	return (f if f else font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x


## Word-wraps text to lines no wider than w.
func _wrap(s: String, w: float, fsize: int, f: Font = null) -> PackedStringArray:
	var out := PackedStringArray()
	for para in s.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var cand := word if line == "" else line + " " + word
			if line != "" and _tw(cand, fsize, f) > w:
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
	_go_rect = Rect2()
	_filter_rect = Rect2()
	_text(Vector2(10, 20), tr("Journal"), 18, Color("f3e3c3"), -1, UiSkin.TITLE_FONT)
	var unread := Journal.unread_count()
	var labels := []
	for i in TABS.size():
		var label: String = Loc.t(TAB_NAMES[TABS[i]])
		if TABS[i] == "codex" and unread > 0:
			label += tr(" (%d new)") % unread
		labels.append(label)
	_strip.labels = labels
	_strip.current = tab
	var title_font: Font = UiSkin.TITLE_FONT
	_strip.draw(self, font, Vector2(maxf(86.0, 10.0 + _tw(tr("Journal"), 18, title_font) + 10.0), 6), BODY)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	_draw_list(vs)
	_draw_page()
	var help := []
	match _tab_id():
		"quests":
			help = [["updown", "choose"], ["ui_accept", tr("show on map")], ["leftright", tr("list / page")], [["ui_cancel", "journal"], "close"]]
		"history":
			help = [["updown", "choose"], ["ui_accept", tr("read / filter")], ["leftright", tr("list / page")], [["ui_cancel", "journal"], "close"]]
		_:
			help = [["updown", "choose"], ["leftright", tr("list / page")], [["ui_cancel", "journal"], "close"]]
	_text(Vector2(10, vs.y - 7), Prompts.help(help, tr("Tap a row, tap again to act. Drag the page to scroll.")), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var w := _tw(flash, 9)
		UiSkin.panel(self, Rect2(vs.x - w - 22, vs.y - 24, w + 16, 18), "paper", Color(1, 1, 1, a))
		_text(Vector2(vs.x - w - 14, vs.y - 11), flash, 9, Color(UiSkin.PAPER_INK, a))


func _draw_list(vs: Vector2) -> void:
	var y := TOP
	var fits := maxi(int((vs.y - y - 20.0) / ROW_H), 1)
	var s := int(sel.get(tab, 0))
	list_scroll = clampi(list_scroll, maxi(s - fits + 1, 0), mini(s, maxi(_rows.size() - fits, 0)))
	if s <= fits - 1:
		list_scroll = 0  # keep the first section header in view while near the top
	if list_scroll > 0:
		_arrow(Vector2(8 + LIST_W / 2, y - 2), true)
	for i in range(list_scroll, mini(list_scroll + fits, _rows.size())):
		var row: Dictionary = _rows[i]
		var rr := Rect2(8, y, LIST_W, ROW_H - 1)
		if row.has("head"):
			_text(rr.position + Vector2(2, 11), str(row["head"]).to_upper(), 8, HEAD, LIST_W)
			draw_rect(Rect2(rr.position + Vector2(2, 13), Vector2(LIST_W - 4, 1)), Color(HEAD, 0.35))
			y += ROW_H
			continue
		_row_rects.append([rr, i])
		var on := i == s
		if on:
			UiSkin.panel(self, rr.grow_individual(0, 1, 0, 1), "button", Color(1.2, 1.1, 0.9) if focus == 0 else Color(0.8, 0.76, 0.72))
		_draw_row(row, rr, on)
		y += ROW_H
	if list_scroll + fits < _rows.size():
		_arrow(Vector2(8 + LIST_W / 2, y + 2), false)


func _arrow(at: Vector2, up: bool) -> void:
	var d := -3.0 if up else 3.0
	draw_colored_polygon(PackedVector2Array([at + Vector2(-5, -d / 3), at + Vector2(5, -d / 3), at + Vector2(0, d)]), Color(GOLD, 0.8))


func _draw_row(row: Dictionary, rr: Rect2, on: bool) -> void:
	var p := rr.position
	var col := GOLD if on else TEXT
	match row["kind"]:
		"quest":
			_mark(p + Vector2(8, 7), str(row["state"]))
			var right := ""
			if int(row.get("days", -1)) >= 0:
				right = "%dd" % int(row["days"])
			var rw := _tw(right, 8) + 6 if right != "" else 0.0
			var c := col if row["state"] != "done" else (GOOD if on else Color(0.55, 0.65, 0.5))
			if row["state"] == "locked":
				c = SOFT
			_text(p + Vector2(17, 11), str(row["title"]), 9, c, LIST_W - 22 - rw)
			if right != "":
				_text(p + Vector2(LIST_W - rw, 11), right, 8, BAD if int(row["days"]) <= 1 else Color("e8c06a"))
		"person":
			var tc := col
			if row["group"] == "lead":
				tc = SOFT if not on else GOLD
			_text(p + Vector2(8, 11), str(row["name"]), 9, tc, 120)
			_text(p + Vector2(132, 11), str(row["title"]), 7, DIM if not on else SOFT, LIST_W - 136)
		"codex":
			var ind := 8.0 + 10.0 * int(row.get("indent", 0))
			if row["unlocked"]:
				_text(p + Vector2(ind, 11), str(row["title"]), 9, col, LIST_W - ind - 18)
				if row.get("new", false):
					draw_circle(p + Vector2(LIST_W - 8, 7), 2.5, Color("ff8a5a"))
			else:
				_text(p + Vector2(ind, 11), str(row["title"]), 9, DIM if not on else SOFT, LIST_W - ind - 8)
			if row["cat"] == "inks" and row.get("unlocked", false):
				var ink := str(row["id"]).trim_prefix("ink_")
				if ink != "stuff":
					draw_rect(Rect2(p + Vector2(2, 4), Vector2(3, 7)), Journal.ink_color(ink))
		"chapter":
			var done := Journal.chapter_done(row["chapter"])
			_text(p + Vector2(8, 11), str(row["title"]), 9, col, LIST_W - 50)
			_text(p + Vector2(LIST_W - 44, 11), Loc.t("done") if done else Loc.t("now"), 7, GOOD if done else Color("e8c06a"))
		"log":
			var oc := _outcome_color(str(row.get("outcome", "")))
			draw_rect(Rect2(p + Vector2(3, 4), Vector2(2, 7)), oc)
			_text(p + Vector2(8, 11), (tr("Day %d") % int(row["day"])) if int(row["day"]) > 0 else tr("Earlier"), 7, SOFT, 34)
			_text(p + Vector2(42, 11), str(row["title"]), 8, col, LIST_W - 46)
		"filter":
			_filter_rect = rr
			_text(p + Vector2(8, 11), tr("Showing: %s") % Loc.t(FILTER_NAMES[HISTORY_FILTERS[history_filter]]), 8, col)
			_text(p + Vector2(LIST_W - 42, 11), Loc.t("change"), 7, DIM)
		"empty":
			_text(p + Vector2(8, 11), str(row["title"]), 8, DIM)


## A small state mark in front of a quest: open, blocked, done or locked.
func _mark(c: Vector2, state: String) -> void:
	match state:
		"done":
			draw_line(c + Vector2(-3, 0), c + Vector2(-1, 2), GOOD, 1.5)
			draw_line(c + Vector2(-1, 2), c + Vector2(3, -3), GOOD, 1.5)
		"blocked":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3), c + Vector2(-3, 0)]), BAD)
		"locked":
			draw_arc(c, 2.5, 0, TAU, 10, DIM, 1.0)
		_:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3), c + Vector2(-3, 0)]), GOLD)


func _outcome_color(o: String) -> Color:
	match o:
		"great", "success":
			return GOOD
		"fail", "wiped":
			return BAD
		"retreat":
			return Color("e8c06a")
	return SOFT


# ---------------------------------------------------------------- the page

## The page is laid out as a list of blocks, then drawn with the scroll offset and clipped to the page.
## Block: ["title", text] | ["sub", text, color] | ["para", text, color] | ["fact", label, value] | ["gap"]
## | ["bar", label, value 0..10] | ["portrait", texture] | ["go"]
func _blocks() -> Array:
	var row := _row()
	var b := []
	match row.get("kind", ""):
		"quest":
			b.append(["title", row["title"]])
			var st: String = {"open": tr("Open"), "done": tr("Done"), "blocked": tr("Waiting on something"), "locked": tr("Not yet")}.get(row["state"], "")
			b.append(["sub", "%s%s" % [row.get("sub", Loc.t(SECTION_NAMES.get(row["section"], ""))), ("  ·  " + str(row["where"])) if str(row.get("where", "")) != "" else ""], INK_SOFT])
			b.append(["sub", st, INK_GREEN if row["state"] == "done" else (INK_RED if row["state"] == "blocked" else INK)])
			b.append(["gap"])
			if str(row.get("text", "")) != "":
				b.append(["para", row["text"], INK])
			if str(row.get("next", "")) != "":
				b.append(["gap"])
				b.append(["head", tr("Next step") if row["state"] != "done" else tr("Where it stands")])
				b.append(["para", row["next"], INK])
			if not row.get("target", {}).is_empty():
				b.append(["gap"])
				b.append(["go"])
		"person":
			b.append_array(_person_blocks(row))
		"codex":
			b.append(["title", row["title"]])
			b.append(["sub", Loc.t(Journal.CAT_NAMES.get(row["cat"], "")), INK_SOFT])
			b.append(["gap"])
			if not row["unlocked"]:
				b.append(["para", row["hint"], INK_SOFT])
			for ptxt in row["paras"]:
				b.append(["para", ptxt, INK])
				b.append(["gap"])
			for f in row["facts"]:
				b.append(["fact", f[0], f[1]])
		"chapter":
			var c: Dictionary = row["chapter"]
			b.append(["title", c.get("title", "")])
			b.append(["sub", tr("Finished") if Journal.chapter_done(c) else tr("Where things stand"), INK_SOFT])
			b.append(["gap"])
			for ptxt in Journal.paragraphs(c.get("recap", [])):
				b.append(["para", ptxt, INK])
				b.append(["gap"])
			if not Journal.chapter_done(c):
				var g := Story.current_goal()
				if not g.is_empty():
					b.append(["head", tr("What now")])
					b.append(["para", "%s%s" % [g["text"], (" (%s)" % g["hint"]) if str(g.get("hint", "")) != "" else ""], INK])
		"log":
			b.append(["title", row["title"]])
			var where: String = Empire.territory().find(str(row.get("province", ""))).get("name", "")
			b.append(["sub", "%s%s  ·  %s" % [(tr("Day %d") % int(row["day"])) if int(row["day"]) > 0 else tr("Before the journal"),  ("  ·  " + where) if where != "" else "", {"expedition": tr("Expedition report"), "bond": tr("Between people"), "faction": tr("Faction request")}.get(row.get("entry_kind", ""), tr("Mission"))], INK_SOFT])
			b.append(["gap"])
			for l in row.get("lines", []):
				b.append(["para", str(l), INK])
		"filter":
			b.append(["title", tr("History")])
			b.append(["para", tr("Every chapter so far, retold, and every mission result and expedition report since the journal was started. %s to show only missions or only expeditions.") % (tr("Tap this row") if Prompts.touch() else Prompts.confirm()), INK])
	return b


func _person_blocks(row: Dictionary) -> Array:
	var b := []
	var id: String = row["id"]
	if row["group"] == "figure":
		var f := Journal.figure(id)
		var tex := Dialogue.portrait(str(f.get("portrait", "")))
		if tex:
			b.append(["portrait", tex])
		b.append(["title", f.get("name", "")])
		b.append(["sub", f.get("title", ""), INK_SOFT])
		b.append(["gap"])
		b.append(["para", f.get("text", ""), INK])
		for ptxt in Journal.paragraphs(f.get("more", [])):
			b.append(["gap"])
			b.append(["para", ptxt, INK])
		return b
	var r := Empire.recruit(id)
	var tex2 := Dialogue.portrait(id)
	if tex2:
		b.append(["portrait", tex2, row["group"] == "lead"])  # a rumour is only a silhouette
	b.append(["title", r.get("name", id)])
	b.append(["sub", r.get("title", ""), INK_SOFT])
	var tier: String = {"field": tr("Fights in the field"), "core": tr("Close companion"), "recruit": tr("Recruit")}.get(r.get("tier", ""), "")
	match row["group"]:
		"roster":
			var status := tr("%s. Now: %s.") % [tier, Empire.role_label(id)]
			if int(Empire.recruits[id].get("injured", 0)) > 0:
				status += tr(" Hurt: out for %d more days.") % int(Empire.recruits[id]["injured"])
			b.append(["sub", status, INK])
		"gate":
			b.append(["sub", tr("Waiting at the south gate. Talk to them in town, or use Newcomers."), INK_GREEN])
		"lead":
			b.append(["sub", tr("Not met yet: only a rumour."), INK_RED])
	b.append(["gap"])
	if row["group"] == "lead":
		b.append(["para", str(r.get("rumour", r.get("blurb", ""))), INK])
		b.append(["gap"])
		b.append(["head", tr("How to bring them in")])
		b.append(["para", Empire.hook_text(id), INK])
		var hp := Empire.hook_progress(id)
		if str(hp[0]) != "":
			b.append(["para", str(hp[0]), INK_GREEN if hp[1] else INK_SOFT])
		return b
	b.append(["para", str(r.get("blurb", "")), INK])
	b.append(["gap"])
	if Empire.recruits.has(id) and Empire.bond_cast().has(id):
		var rank := Empire.bond_rank(id)
		b.append(["fact", tr("Bond"), tr("rank %d of %d, %s") % [rank, Empire.BOND_MAX, Empire.bond_rank_name(rank)]])
		b.append(["fact", tr("Next"), Empire.bond_next_text(id)])
	if not PartyPicker.hero_data(id).is_empty() and Empire.recruits.has(id):
		b.append(["fact", tr("Level"), "%d, %s" % [Progress.level(id), Skills.weapon_name(id)]])
	var traits := []
	for t in r.get("traits", []):
		var td: Dictionary = Empire.trait_data.get(t, {})
		traits.append("%s (%s)" % [td.get("name", t), td.get("desc", "")] if td.has("desc") else td.get("name", t))
	if not traits.is_empty():
		b.append(["fact", tr("Traits"), "; ".join(traits)])
	if row["group"] == "roster":  # what has happened to them: romance, friends and rivals, scars (issue #116)
		for ff in Relationships.fate_facts(id):
			b.append(["fact", ff[0], ff[1]])
	b.append(["gap"])
	var stats: Dictionary = r.get("stats", {})
	for k in Empire.STAT_NAMES:
		b.append(["bar", Loc.t(Empire.STAT_NAMES[k]), int(stats.get(k, 0))])
	if row["group"] == "gate":
		var cost := Empire.cost_text(Empire.hire_cost(id))
		if cost != "":
			b.append(["gap"])
			b.append(["fact", tr("Asks for"), cost])
	return b


func _draw_page() -> void:
	var pr := _page_rect()
	UiSkin.page(self, pr)
	var x := pr.position.x + 28.0
	var w := pr.size.x - 28.0 - 30.0
	var top := pr.position.y + 6.0
	var bottom := pr.end.y - 6.0
	var y := top - page_scroll
	_rule_base = pr.position.y + 14.0 - 3.0 - page_scroll  # baselines sit just above the page's ruling
	var tex: Texture2D = null
	var pw := 0.0
	var shade := false
	for blk in _blocks():
		if blk[0] == "portrait":
			tex = blk[1]
			shade = blk.size() > 2 and blk[2]
	if tex:
		pw = 78.0
		var ph := pw * float(tex.get_height()) / float(maxi(tex.get_width(), 1))
		var prect := Rect2(pr.end.x - pw - 26.0, top - page_scroll, pw, ph)
		if prect.end.y > top and prect.position.y < bottom:
			_clip_tex(Dialogue.fitted(tex, ph), prect, top, bottom, Color(0.16, 0.12, 0.1, 0.8) if shade else Color(1, 1, 1, 0.95))
	var title_w := w - (pw + 6.0 if tex else 0.0)
	for blk in _blocks():
		var kind: String = blk[0]
		var lw := title_w if y + page_scroll < top + 120.0 else w  # text runs beside the portrait, then under it
		match kind:
			"title":
				for line in _wrap(str(blk[1]), lw, 16, UiSkin.TITLE_FONT):
					y += 15.0
					_clip_text(Vector2(x, y), line, 16, INK, top, bottom, UiSkin.TITLE_FONT)
				y += 2.0
			"sub":
				for line in _wrap(str(blk[1]), lw, 9):
					y += 11.0
					_clip_text(Vector2(x, y), line, 9, blk[2], top, bottom)
			"head":
				y = _ruled(y)
				_clip_text(Vector2(x, y), str(blk[1]).to_upper(), 8, INK_RED, top, bottom)
			"para":
				for line in _wrap(str(blk[1]), lw, BODY):
					y = _ruled(y)
					_clip_text(Vector2(x, y), line, BODY, blk[2], top, bottom)
			"fact":
				var label := str(blk[1]) + ": "
				var lwid := _tw(label, 9)
				var lines := _wrap(str(blk[2]), lw - lwid, BODY)
				for i in lines.size():
					y = _ruled(y)
					if i == 0:
						_clip_text(Vector2(x, y), label, 9, INK_SOFT, top, bottom)
					_clip_text(Vector2(x + lwid, y), lines[i], BODY, INK, top, bottom)
			"bar":
				y = _ruled(y)
				_clip_text(Vector2(x, y), str(blk[1]), 9, INK_SOFT, top, bottom)
				if y - 7.0 > top and y < bottom:
					for i in 10:
						var on: bool = i < int(blk[2])
						draw_rect(Rect2(x + 46 + i * 9, y - 7, 7, 6), Color(INK, 0.85) if on else Color(INK, 0.15))
					_text(Vector2(x + 46 + 10 * 9 + 4, y), str(blk[2]), 9, INK)
			"gap":
				y += 5.0
			"go":
				y += 6.0
				var label2 := tr("Show on map") if can_go else tr("Show on map (%s)") % go_note
				var k := "" if Prompts.touch() else Prompts.confirm()
				if k != "" and focus == 0:
					label2 += "  [%s]" % k
				var bw := _tw(label2, 9) + 20
				var br := Rect2(x, y, bw, 16)
				if br.position.y > top and br.end.y < bottom:
					UiSkin.panel(self, br, "button", Color.WHITE if can_go else Color(0.6, 0.6, 0.6))
					_text(br.position + Vector2(10, 12), label2, 9, GOLD if can_go else SOFT)
					_go_rect = br
				y += 18.0
	page_h = y + page_scroll - top + 8.0
	if page_scroll > 0.0:
		_arrow(Vector2(pr.get_center().x, pr.position.y + 5), true)
	if page_scroll < _max_scroll():
		_arrow(Vector2(pr.get_center().x, pr.end.y - 4), false)
	if focus == 1:
		UiSkin.highlight(self, Rect2(pr.position + Vector2(2, 2), Vector2(3, pr.size.y - 4)), GOLD)


## The next baseline on the page's ruling at least a line below y (a blank ruled line between blocks).
func _ruled(y: float) -> float:
	return _rule_base + LINE * ceilf((y + 11.0 - _rule_base) / LINE)


func _clip_text(pos: Vector2, s: String, fsize: int, col: Color, top: float, bottom: float, f: Font = null) -> void:
	if pos.y - fsize * 0.7 < top or pos.y > bottom:
		return
	_text(pos, s, fsize, col, -1, f)


## Draws a texture into r, cut to the page's visible band.
func _clip_tex(tex: Texture2D, r: Rect2, top: float, bottom: float, tint: Color) -> void:
	var vis := Rect2(r.position.x, maxf(r.position.y, top), r.size.x, minf(r.end.y, bottom) - maxf(r.position.y, top))
	if vis.size.y <= 0:
		return
	var sy := tex.get_height() / r.size.y
	var src := Rect2(0, (vis.position.y - r.position.y) * sy, tex.get_width(), vis.size.y * sy)
	draw_texture_rect_region(tex, vis, src, tint)
