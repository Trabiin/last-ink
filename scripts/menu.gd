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
var _rects: Array = []
var _t := 0.0
# Long lists (issue #23): they move up, then scroll so the selected row stays on screen.
var _scroll := 0.0
var _max_scroll := 0.0
var _follow := true  # keys move the view with the selection; dragging frees it
var _touch_from := Vector2.INF  # where a finger went down on a scrolling list
var _touch_item := -1


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
	_select_first_enabled()
	queue_redraw()


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
	var x := (get_viewport_rect().size.x - w) / 2.0
	draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), 4, Color(0, 0, 0, col.a * 0.9))
	draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)
	return w


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, dim))
	# Lay the list out first, so a long one can move up and scroll.
	var head := (20.0 if title != "" else 0.0) + (13.0 * subtitle.split("\n").size() if subtitle != "" else 0.0) + 16.0
	var list_h := 0.0
	for it in items:
		list_h += 31.0 if str(it.get("detail", "")) != "" else 20.0
	var y := vs.y * top
	var bottom := vs.y - 8.0
	if y + head + list_h > bottom:
		y = maxf(float(title_size) + (18.0 if title != "" else 4.0), bottom - head - list_h)  # room for the frame above the title
	# A ledger panel behind the whole menu, sized to its widest line.
	var pw := 120.0
	if title != "":
		pw = maxf(pw, UiSkin.TITLE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(title_size + 6)).x)
	for line in subtitle.split("\n"):
		pw = maxf(pw, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x)
	for it in items:
		pw = maxf(pw, font.get_string_size(str(it["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(12)).x + 30.0)
		pw = maxf(pw, font.get_string_size(str(it.get("detail", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x)
	pw = minf(pw + 36.0, vs.x - 16.0)
	var ptop := y - float(title_size) - 14.0 if title != "" else y - 18.0
	UiSkin.panel(self, Rect2((vs.x - pw) / 2.0, maxf(ptop, 4.0), pw, minf(y + head + list_h - 4.0, bottom) - maxf(ptop, 4.0)), "ledger", Color(1, 1, 1, panel_alpha))
	if title != "":
		_centered(UiSkin.TITLE_FONT, y, title, title_size + 6, Color("f3e3c3"))
		y += 20.0
	if subtitle != "":
		for line in subtitle.split("\n"):
			_centered(font, y, line, 9, Color(0.8, 0.78, 0.74))
			y += 13.0
	y += 16.0
	var list_top := y - 14.0  # first row's top edge
	_max_scroll = maxf(0.0, list_top + list_h - bottom)
	if _max_scroll > 0.0 and _follow:
		var row_top := list_top
		for i in selected:
			row_top += 31.0 if str(items[i].get("detail", "")) != "" else 20.0
		var row_h := 31.0 if selected < items.size() and str(items[selected].get("detail", "")) != "" else 20.0
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
	y -= _scroll
	_rects.clear()
	for i in items.size():
		var it: Dictionary = items[i]
		var row_h2 := 31.0 if str(it.get("detail", "")) != "" else 20.0
		if _max_scroll > 0.0 and (y - 14.0 < list_top - 0.5 or y - 14.0 + row_h2 > bottom + 0.5):
			_rects.append(Rect2(-100, -100, 0, 0))  # scrolled out of view: not drawn, not tappable
			y += row_h2
			continue
		var enabled: bool = it.get("enabled", true)
		var col := Color("ffd166") if i == selected else Color(0.92, 0.9, 0.86)
		if not enabled:
			col = Color(0.5, 0.5, 0.52)
		var label: String = it["label"]
		var w := _centered(font, y, label, 12, col)
		var r := Rect2((vs.x - w) / 2.0, y - 12.0, w, 16.0)
		_rects.append(r)
		if i == selected:
			# An ink-drop marker that bobs gently beside the chosen item.
			var mx := r.position.x - 10.0 + sin(_t * 5.0) * 1.5
			draw_circle(Vector2(mx, y - 4.0), 3.0, Color("ffd166"))
			draw_colored_polygon(PackedVector2Array([Vector2(mx - 2.6, y - 5.5), Vector2(mx + 2.6, y - 5.5), Vector2(mx, y - 10.5)]), Color("ffd166"))
		if not enabled and it.get("note", "") != "":
			draw_string(font, Vector2(r.end.x + 6.0, y - 1.0), it["note"], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color(0.55, 0.55, 0.58))
		if it.get("detail", "") != "":
			# A second, smaller line under the label (save slot info and the like).
			_centered(font, y + 11.0, it["detail"], 8, Color(0.62, 0.6, 0.6) if enabled else Color(0.45, 0.45, 0.48))
			_rects[i] = r.merge(Rect2(r.position.x, y, r.size.x, 12.0))
			y += 11.0
		y += 20.0


## Menu sounds (#20): a tick when moving, a click on a pick, a softer one on back.
func _chosen_sfx(id: String) -> void:
	_sfx("ui_back" if id == "cancel" else "ui_ok")


func _sfx(id: String) -> void:
	var a := get_node_or_null("/root/Audio")
	if a:
		a.sfx(id)
