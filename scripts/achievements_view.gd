class_name AchievementsView
extends Control
## The Achievements screen (issue #150), from the title menu: the same list Steam has, in every build.
## Tabs for All and each group (Q / E, LB / RB, or tap), a row per achievement with its badge, name,
## what it asks, and the date it was unlocked or how far a counting one has got. Hidden ones keep their
## secret until unlocked; ones waiting for a later chapter say so.
##   Up / Down (or wheel, or a finger drag) scroll; Esc / B / Close goes back.

signal closed

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.62, 0.6, 0.62)
const DIM := Color(0.42, 0.41, 0.44)
const BAR := Color("c9a46a")
const TOP := 30.0
const ROW_GAP := 4.0

var tab := TabStrip.new()
var sel := 0
var scroll := 0.0
var opened_frame := -1
var font: Font
var _rows: Array = []  # achievements shown on the current tab
var _row_rects: Array = []  # [Rect2, index]
var _list_drag := {}


static func popup(host: Node, layer := 6) -> AchievementsView:
	var cl := CanvasLayer.new()
	cl.layer = layer
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(cl)
	var v := AchievementsView.new()
	cl.add_child(v)
	v.closed.connect(cl.queue_free)
	v.open()
	return v


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font


func open() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	var labels := [tr("All")]
	for g in Achievements.groups:
		labels.append(str(g["name"]))
	tab.labels = labels
	_set_tab(0)


func close() -> void:
	visible = false
	closed.emit()


func _set_tab(i: int) -> void:
	tab.current = i
	sel = 0
	scroll = 0.0
	if i == 0:
		_rows = Achievements.list.duplicate()
	else:
		var gid := str(Achievements.groups[i - 1]["id"])
		_rows = Achievements.list.filter(func(a): return str(a.get("group", "")) == gid)


func _process(_delta: float) -> void:
	if not visible:
		return
	if size != get_viewport_rect().size:
		size = get_viewport_rect().size
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return
	var t := TabStrip.pressed()
	if t != 0:
		_set_tab(tab.stepped(t))
	elif _just("move_up") or _just("ui_up"):
		sel = posmod(sel - 1, maxi(_rows.size(), 1))
	elif _just("move_down") or _just("ui_down"):
		sel = posmod(sel + 1, maxi(_rows.size(), 1))
	elif _just("ui_cancel") or _just("pause"):
		close()


func _just(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _gui_input(event: InputEvent) -> void:
	var n := Prompts.list_steps(event, _list_drag, _row_h(), event is InputEventMouseButton or ("position" in event and event.position.y > TOP + 20.0))
	if n != 0:
		sel = clampi(sel + n, 0, maxi(_rows.size() - 1, 0))
		accept_event()
		return
	if event is InputEventMouseMotion:
		for rr in _row_rects:
			if (rr[0] as Rect2).has_point(event.position):
				sel = int(rr[1])
		return
	if not Prompts.tapped(event):
		return
	accept_event()
	var pos: Vector2 = event.position
	if _close_rect().has_point(pos):
		close()
		return
	var hit := tab.hit(pos)
	if hit >= 0:
		_set_tab(hit)
		return
	for rr in _row_rects:
		if (rr[0] as Rect2).has_point(pos):
			sel = int(rr[1])


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 5), Vector2(50, 16))


func _row_h() -> float:
	return float(Access.fs(10) + Access.fs(8)) + 12.0


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0, f: Font = null) -> void:
	var ff := f if f else font
	draw_string(ff, pos, Access.fit(ff, s, Access.fs(fsize), width) if width > 0.0 else s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _tw(s: String, fsize: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	_row_rects.clear()
	var title := tr("Achievements")
	_text(Vector2(10, 20), title, 18, Color("f3e3c3"), -1, UiSkin.TITLE_FONT)
	var count := tr("%d of %d unlocked") % [Achievements.unlocked_count(), Achievements.list.size()]
	if SteamLink.active:
		count += tr(", kept in step with Steam")
	var hl := UiSkin.header_line(font, title, 18, count, 8, vs.x, 56.0, UiSkin.TITLE_FONT, 10.0)
	_text(Vector2(hl[0], 19), hl[1], 8, SOFT)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	var w := minf(vs.x - 24.0, 460.0)
	var x0 := floorf((vs.x - w) / 2.0)
	tab.draw(self, font, Vector2(x0, TOP + 1.0), 9, w)
	var list_top := TOP + TabStrip.height(9) + 6.0
	var bottom := vs.y - 14.0
	var rh := _row_h()
	var step := rh + ROW_GAP
	# Keep the selected row in view.
	var sel_top := sel * step
	if sel_top - scroll < 0.0:
		scroll = sel_top
	elif sel_top + rh - scroll > bottom - list_top:
		scroll = sel_top + rh - (bottom - list_top)
	scroll = clampf(scroll, 0.0, maxf(0.0, _rows.size() * step - ROW_GAP - (bottom - list_top)))
	for i in _rows.size():
		var y := list_top + i * step - scroll
		if y < list_top - 0.5 or y + rh > bottom + 0.5:
			continue
		var r := Rect2(x0, y, w, rh)
		_row_rects.append([r, i])
		_draw_row(r, _rows[i], i == sel)
	if scroll > 0.5:
		_arrow(Vector2(vs.x / 2.0, list_top - 2.0), -1)
	if scroll < _rows.size() * step - ROW_GAP - (bottom - list_top) - 0.5:
		_arrow(Vector2(vs.x / 2.0, vs.y - 9.0), 1)
	var help := [["updown", "scroll"], ["ui_cancel", "close"]]
	_text(Vector2(10, vs.y - 3), Prompts.help(help, tr("Drag to scroll. Tap the tabs to switch.")), 7, Color(0.5, 0.48, 0.52))


func _arrow(at: Vector2, dir: int) -> void:
	var c := Color(1.0, 0.82, 0.4, 0.75)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-5, 0), at + Vector2(5, 0), at + Vector2(0, 5 * dir)]), c)


func _draw_row(r: Rect2, a: Dictionary, on: bool) -> void:
	var id := str(a["id"])
	var got := Achievements.is_unlocked(id)
	var secret: bool = a.get("hidden", false) and not got
	UiSkin.panel(self, r, "button", Color(1.2, 1.1, 0.9) if on else (Color(0.95, 0.9, 0.82) if got else Color(0.62, 0.6, 0.6)))
	# The badge: a filled ink drop when unlocked, an empty one when not.
	var c := r.position + Vector2(13, r.size.y / 2.0 + 1.0)
	var drop := PackedVector2Array([c + Vector2(0, -8), c + Vector2(5, -1), c + Vector2(4, 3), c + Vector2(0, 5), c + Vector2(-4, 3), c + Vector2(-5, -1)])
	if got:
		draw_colored_polygon(drop, GOLD)
		draw_circle(c + Vector2(-1.5, 0), 1.2, Color(1, 1, 1, 0.7))
	else:
		drop.append(drop[0])
		draw_polyline(drop, DIM if not on else SOFT, 1.0)
	var name := tr("Hidden achievement") if secret else str(a.get("name", id))
	var desc := tr("Keep playing the story to find out.") if secret else str(a.get("desc", ""))
	var right := ""
	var prog := Achievements.progress_of(a)
	if got:
		right = Time.get_date_string_from_unix_time(int(Achievements.have[id]))
	elif a.get("later", false):
		right = tr("later chapter")
	elif not prog.is_empty():
		right = "%d / %d" % prog
	var rw := _tw(right, 8) if right != "" else 0.0
	var tx := r.position.x + 26.0
	var name_col := (GOLD if on else TEXT) if got else (GOLD.lerp(SOFT, 0.4) if on else SOFT)
	var line1 := r.position.y + 4.0 + Access.fs(10)
	_text(Vector2(tx, line1), name, 10, name_col, r.size.x - 34.0 - rw - 8.0)
	var bar := not got and not prog.is_empty() and int(prog[1]) > 0
	_text(Vector2(tx, line1 + 3.0 + Access.fs(8)), desc, 8, SOFT if got else DIM.lerp(SOFT, 0.5), r.size.x - 34.0 - (76.0 if bar else 0.0))
	if right != "":
		_text(Vector2(r.end.x - rw - 8.0, line1), right, 8, BAR if got else DIM.lerp(SOFT, 0.5))
	if bar:  # how far a counting one has got, under its "12 / 25"
		var bw := 60.0
		var br := Rect2(r.end.x - bw - 8.0, line1 + 3.0 + Access.fs(8) - 4.0, bw, 3.0)
		draw_rect(br, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(br.position, Vector2(bw * float(prog[0]) / float(prog[1]), 3.0)), BAR)
