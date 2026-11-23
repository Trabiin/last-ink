class_name InkMenu
extends Control
## A small code-drawn list menu used by the title screen, pause and game over.
## Works with keyboard/gamepad (ui_up/ui_down/ui_accept/ui_cancel), mouse and touch.
## No ring menus: just a clear vertical list.

signal chosen(id: String)

var title := ""
var subtitle := ""
var items: Array = []  # each: {"id", "label", "enabled", "note" (beside, when disabled), "detail" (line below)}
var selected := 0
var dim := 0.7
var panel_alpha := 0.94  # the title screen lowers it so the key art shows through
var title_size := 22
var top := 0.34  # fraction of screen height where the title (or first item) starts
var min_top := -1.0  # if set, a long menu's panel never climbs above this fraction (the title logo): it scrolls instead
var _rects: Array = []
var _t := 0.0
# Long lists (issue #23): they move up, then scroll so the selected row stays on screen.
var _scroll := 0.0
var _max_scroll := 0.0
var _follow := true  # keys move the view with the selection; dragging frees it
var _touch_from := Vector2.INF  # where a finger went down on a scrolling list
var _touch_item := -1
var _text_mode := false  # the text itself scrolls (see _draw); up and down read through it
## Where the last draw put the panel and each line of text, for the layout tests (tests/test_menu_layout.gd).
var panel_rect := Rect2()
var drawn_text: Array = []
var view_override := Vector2.ZERO  # tests lay the menu out for other screen sizes


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_select_first_enabled()
	chosen.connect(_chosen_sfx)


func setup(p_title: String, p_items: Array, p_subtitle := "") -> void:
	title = p_title
	subtitle = p_subtitle
	items = p_items
	selected = 0
	_scroll = 0.0
	_follow = true
	_select_first_enabled()
	queue_redraw()


func _first_enabled() -> int:
	for i in items.size():
		if items[i].get("enabled", true):
			return i
	return 0


func _select_first_enabled() -> void:
	for i in items.size():
		if items[i].get("enabled", true):
			selected = i
			return


func _move(step: int) -> void:
	if items.is_empty():
		return
	for n in items.size():
		selected = posmod(selected + step, items.size())
		if items[selected].get("enabled", true):
			break
	queue_redraw()
	_sfx("ui_move")


func _choose(i: int) -> void:
	if i >= 0 and i < items.size() and items[i].get("enabled", true):
		chosen.emit(items[i]["id"])


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		var i := _hit(event.position)
		if i >= 0 and items[i].get("enabled", true) and i != selected:
			selected = i
			queue_redraw()
		return
	if _max_scroll > 0.0 and _scroll_input(event):
		return
	var pick := -2  # -2 = nothing, -1 = cancel, >= 0 = item index
	var down := event.is_action_pressed("ui_down")
	if _text_mode and ((down and _scroll < _max_scroll - 0.5) or (event.is_action_pressed("ui_up") and _scroll > 0.5 and selected == _first_enabled())):
		# Up and down read through long text a few lines at a time; the choices are reached at the end.
		var step := Access.px(39.0) * (1.0 if down else -1.0)
		_follow = false
		_scroll = clampf(_scroll + step, 0.0, _max_scroll)
		get_viewport().set_input_as_handled()
		queue_redraw()
		return
	if event.is_action_pressed("ui_down"):
		_follow = true
		_move(1)
	elif event.is_action_pressed("ui_up"):
		_follow = true
		_move(-1)
	elif event.is_action_pressed("ui_accept"):
		pick = selected
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		pick = -1
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		var i := _hit(event.position)
		if i < 0:
			return
		selected = i
		pick = i
	else:
		return
	# Mark handled before acting: a choice may change scene and free this menu.
	get_viewport().set_input_as_handled()
	if pick == -1:
		chosen.emit("cancel")
	elif pick >= 0:
		_choose(pick)


## On a list too long for the screen a finger can drag it, and a tap picks on release
## (so starting a drag never picks). The mouse wheel scrolls too. True when handled.
func _scroll_input(event: InputEvent) -> bool:
	if event is InputEventScreenDrag:
		_follow = false
		_scroll = clampf(_scroll - event.relative.y, 0.0, _max_scroll)
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_follow = false
		_scroll = clampf(_scroll + (-16.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 16.0), 0.0, _max_scroll)
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed:
			_touch_from = event.position
			_touch_item = _hit(event.position)
		elif _touch_from != Vector2.INF:
			var moved: float = (event.position as Vector2).distance_to(_touch_from)
			var i := _touch_item
			_touch_from = Vector2.INF
			if moved < 10.0 and i >= 0 and i == _hit(event.position):
				selected = i
				_choose(i)
		return true
	return false


func _hit(p: Vector2) -> int:
	for i in _rects.size():
		if (_rects[i] as Rect2).grow(4).has_point(p):
			return i
	return -1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _centered(font: Font, y: float, s: String, fsize: int, col: Color) -> float:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	var x := (_view().x - w) / 2.0
	draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), 4, Color(0, 0, 0, col.a * 0.9))
	draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)
	drawn_text.append(Rect2(x, y - Access.fs(fsize), w, Access.fs(fsize)))
	return w


func _view() -> Vector2:
	return view_override if view_override != Vector2.ZERO else get_viewport_rect().size


## How wide a line of subtitle or detail text may get before it wraps: a comfortable reading width,
## never wider than the panel can be on this screen. Grows with the text size so Largest wraps less.
func text_width() -> float:
	return minf(_view().x - 60.0, Access.px(440.0))


## text broken into lines no wider than max_w pixels at this (already scaled) font size. Each "\n" starts
## a new line and an empty paragraph stays an empty line. A word too long for a line on its own is cut.
static func wrap_px(font: Font, text: String, size: int, max_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" ", false):
			var tryline := word if line == "" else line + " " + word
			if line != "" and font.get_string_size(tryline, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
				out.append(line)
				line = word
			else:
				line = tryline
			while line.length() > 1 and font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
				var cut := line.length() - 1
				while cut > 1 and font.get_string_size(line.left(cut), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
					cut -= 1
				out.append(line.left(cut))
				line = line.substr(cut)
		out.append(line)
	return out


func _sub_lines(font: Font) -> PackedStringArray:
	return wrap_px(font, subtitle, Access.fs(9), text_width()) if subtitle != "" else PackedStringArray()


func _detail_lines(font: Font, it: Dictionary) -> PackedStringArray:
	var d := str(it.get("detail", ""))
	return wrap_px(font, d, Access.fs(8), text_width()) if d != "" else PackedStringArray()


## A row's height: the label, plus one smaller line per wrapped detail line.
func _row_h(font: Font, it: Dictionary) -> float:
	return Access.px(20.0) + Access.px(11.0) * _detail_lines(font, it).size()


## Subtitle line heights: blank lines between paragraphs take half a line.
func _sub_h(line: String) -> float:
	return Access.px(13.0) if line != "" else Access.px(7.0)


func _draw() -> void:
	var vs := _view()
	var font := ThemeDB.fallback_font
	drawn_text.clear()
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, dim))
	var sub := _sub_lines(font)
	var title_gap := Access.px(20.0)
	# Lay the list out first, so a long one can move up and scroll.
	var head := (title_gap if title != "" else 0.0) + Access.px(16.0)
	for line in sub:
		head += _sub_h(line)
	var list_h := 0.0
	for it in items:
		list_h += _row_h(font, it)
	var title_h := float(Access.fs(title_size + 6))
	var y := vs.y * top
	var bottom := vs.y - 8.0
	if y + head + list_h > bottom:
		var y_min := title_h + 12.0 if title != "" else Access.px(18.0) + 4.0  # room for the frame above the first line
		if min_top >= 0.0:
			y_min = maxf(y_min, vs.y * min_top + (title_h + 6.0 if title != "" else Access.px(18.0)))
		y = maxf(y_min, bottom - head - list_h)
	# A ledger panel behind the whole menu, sized to its widest line.
	var pw := 120.0
	if title != "":
		pw = maxf(pw, UiSkin.TITLE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(title_size + 6)).x)
	for line in sub:
		pw = maxf(pw, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x)
	for it in items:
		var lw := font.get_string_size(str(it["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(12)).x
		pw = maxf(pw, lw + 30.0)
		if not it.get("enabled", true) and str(it.get("note", "")) != "":  # the note sits right of the centred label
			pw = maxf(pw, lw + 2.0 * (6.0 + font.get_string_size(str(it["note"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x) + 8.0)
		for line in _detail_lines(font, it):
			pw = maxf(pw, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x)
	pw = minf(pw + 36.0, vs.x - 16.0)
	var ptop := y - title_h - 6.0 if title != "" else y - Access.px(18.0)
	panel_rect = Rect2((vs.x - pw) / 2.0, maxf(ptop, 4.0), pw, minf(y + head + list_h - 4.0, bottom) - maxf(ptop, 4.0))
	UiSkin.panel(self, panel_rect, "ledger", Color(1, 1, 1, panel_alpha))
	if title != "":
		_centered(UiSkin.TITLE_FONT, y, title, title_size + 6, Color("f3e3c3"))
		y += title_gap
	var row_top_off := Access.px(14.0)  # a row's top edge above its label's baseline
	# Text too long for the screen (the credits): the text and the list under it scroll together under
	# the title, starting at the top. Otherwise only a long list scrolls.
	var region_top := y - Access.px(11.0)
	var content_end := y + Access.px(16.0) - row_top_off + list_h
	for line in sub:
		content_end += _sub_h(line)
	_text_mode = not sub.is_empty() and content_end > bottom + 0.5 and content_end - list_h - region_top > (bottom - region_top) * 0.4
	if _text_mode:
		_max_scroll = content_end - bottom
		_scroll = clampf(_scroll, 0.0, _max_scroll)
		y -= _scroll
	for line in sub:
		if line != "" and (not _text_mode or (y - Access.fs(9) >= region_top - 0.5 and y + 2.0 <= bottom)):
			_centered(font, y, line, 9, Color(0.8, 0.78, 0.74))
		y += _sub_h(line)
	y += Access.px(16.0)
	var list_top := region_top if _text_mode else y - row_top_off  # first row's top edge (or the scroll area's)
	if not _text_mode:
		_max_scroll = maxf(0.0, list_top + list_h - bottom)
	if _max_scroll > 0.0 and _follow and not _text_mode:
		var row_top := list_top
		for i in selected:
			row_top += _row_h(font, items[i])
		var row_h := _row_h(font, items[selected]) if selected < items.size() else Access.px(20.0)
		if row_top - _scroll < list_top:
			_scroll = row_top - list_top
		elif row_top + row_h - _scroll > bottom:
			_scroll = row_top + row_h - bottom
	_scroll = clampf(_scroll, 0.0, _max_scroll)
	if _max_scroll > 0.0:
		# Little arrows say there is more above or below.
		var cx := vs.x / 2.0
		var arrow := Color(1.0, 0.82, 0.4, 0.75)
		if _scroll > 0.5:
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, list_top - 2), Vector2(cx + 5, list_top - 2), Vector2(cx, list_top - 7)]), arrow)
		if _scroll < _max_scroll - 0.5:
			draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, vs.y - 6), Vector2(cx + 5, vs.y - 6), Vector2(cx, vs.y - 1)]), arrow)
	if not _text_mode:
		y -= _scroll
	_rects.clear()
	for i in items.size():
		var it: Dictionary = items[i]
		var row_h2 := _row_h(font, it)
		if _max_scroll > 0.0 and (y - row_top_off < list_top - 0.5 or y - row_top_off + row_h2 > bottom + 0.5):
			_rects.append(Rect2(-100, -100, 0, 0))  # scrolled out of view: not drawn, not tappable
			y += row_h2
			continue
		var enabled: bool = it.get("enabled", true)
		var col := Color("ffd166") if i == selected else Color(0.92, 0.9, 0.86)
		if not enabled:
			col = Color(0.5, 0.5, 0.52)
		var label: String = it["label"]
		var w := _centered(font, y, label, 12, col)
		var r := Rect2((vs.x - w) / 2.0, y - Access.px(12.0), w, Access.px(16.0))
		_rects.append(r)
		if i == selected:
			# An ink-drop marker that bobs gently beside the chosen item.
			var mx := r.position.x - 10.0 + sin(_t * 5.0) * 1.5
			draw_circle(Vector2(mx, y - 4.0), 3.0, Color("ffd166"))
			draw_colored_polygon(PackedVector2Array([Vector2(mx - 2.6, y - 5.5), Vector2(mx + 2.6, y - 5.5), Vector2(mx, y - 10.5)]), Color("ffd166"))
		if not enabled and it.get("note", "") != "":
			draw_string(font, Vector2(r.end.x + 6.0, y - 1.0), it["note"], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color(0.55, 0.55, 0.58))
			drawn_text.append(Rect2(r.end.x + 6.0, y - 1.0 - Access.fs(8), font.get_string_size(it["note"], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x, Access.fs(8)))
		# Smaller lines under the label (save slot info and the like), wrapped like the subtitle.
		for line in _detail_lines(font, it):
			y += Access.px(11.0)
			_centered(font, y, line, 8, Color(0.62, 0.6, 0.6) if enabled else Color(0.45, 0.45, 0.48))
			_rects[i] = (_rects[i] as Rect2).merge(Rect2(r.position.x, y - Access.px(11.0), r.size.x, Access.px(12.0)))
		y += Access.px(20.0)


## Menu sounds (#20): a tick when moving, a click on a pick, a softer one on back.
func _chosen_sfx(id: String) -> void:
	_sfx("ui_back" if id == "cancel" else "ui_ok")


func _sfx(id: String) -> void:
	var a := get_node_or_null("/root/Audio")
	if a:
		a.sfx(id)
