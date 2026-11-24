class_name DialogueLog
extends Control
## The dialogue log (issue #34): every line the player has seen this session, from conversations, bond
## scenes, the cast's explainers and banter, newest at the bottom. Opened from any conversation
## (Backspace / gamepad Back / mouse wheel up / the "Log" tag under the box) and from Options >
## Accessibility. Starting a new game or loading a save clears it (Empire.reset).
##
## Viewers call DialogueLog.track(self, line) every frame with the line they are showing; it is written
## down once, when it first appears, so skipped lines never show up.
##
## Up/Down or the wheel scroll a line, Left/Right (or PgUp/PgDn) a page; Back / Esc / B closes.
## Touch: drag to scroll, tap outside or on Close.

signal closed

const MAX_ENTRIES := 400
const ACTION := "dialogue_log"
const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.66, 0.64, 0.66)
const DIM := Color(0.5, 0.48, 0.52)

## [{"who": speaker id ("" = narration), "text": the line as shown, "kind": "talk"|"scene"|"help"|"banter"}]
static var entries: Array = []
static var _last := {}  # viewer instance id -> the line array it last logged
static var _open: DialogueLog = null

var scroll := 0.0  # pixels scrolled up from the newest line
var _opened_frame := -1
var _drag_from := Vector2.INF
var _drag_scroll := 0.0
var _close_rect := Rect2()
var _panel := Rect2()
var _content_h := 0.0
var _view_h := 0.0
var font: Font


# ---------------------------------------------------------------- recording

## Writes a line down if it is new for this viewer. line: [speaker, text, ...].
static func track(viewer: Object, line: Array, kind := "talk") -> void:
	if line.size() < 2 or str(line[1]) == "":
		return
	var key := viewer.get_instance_id()
	if is_same(_last.get(key), line):
		return
	_last[key] = line
	add(str(line[0]), str(line[1]), kind)


static func add(who: String, text: String, kind := "talk") -> void:
	if not entries.is_empty():
		var prev: Dictionary = entries.back()
		if prev["who"] == who and prev["text"] == text:
			return  # the same line shown twice in a row (a banter repeat, a replayed card)
	entries.append({"who": who, "text": text, "kind": kind})
	if entries.size() > MAX_ENTRIES:
		entries = entries.slice(entries.size() - MAX_ENTRIES)


static func clear() -> void:
	entries = []
	_last = {}


static func is_open() -> bool:
	return is_instance_valid(_open) and _open.visible


## The key that opens the log, made on first use so every scene has it (Controls stays untouched).
static func ensure_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION, 0.5)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_BACKSPACE
	InputMap.action_add_event(ACTION, k)
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_BACK
	InputMap.action_add_event(ACTION, b)


## For conversation viewers: true on the frame the player asks for the log.
static func asked(event: InputEvent = null) -> bool:
	ensure_action()
	if event != null:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			return true
		return event.is_action_pressed(ACTION)
	return Input.is_action_just_pressed(ACTION)


## Short button name for the hint under a conversation ("" on touch).
static func key_name() -> String:
	ensure_action()
	return Prompts.key(ACTION)


# ---------------------------------------------------------------- the view

## Opens the log over whatever is running, on its own top layer.
static func popup(host: Node) -> DialogueLog:
	if is_open():
		return _open
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var view := DialogueLog.new()
	layer.add_child(view)
	view.closed.connect(layer.queue_free)
	_open = view
	return view


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	_opened_frame = Engine.get_process_frames()
	ensure_action()


func close() -> void:
	visible = false
	if _open == self:
		_open = null
	closed.emit()


func _line_h() -> float:
	return Access.px(13.0)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	get_viewport().set_input_as_handled()  # nothing reaches the conversation or the game underneath
	if Engine.get_process_frames() == _opened_frame:
		return  # the press that opened it
	var page := maxf(_view_h - _line_h() * 2.0, _line_h())
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_by(_line_h() * 2.0)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_by(-_line_h() * 2.0)
				return
	if event is InputEventScreenDrag:
		if _drag_from != Vector2.INF:
			scroll = _drag_scroll + (event.position.y - _drag_from.y)
			_clamp()
		return
	if (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
		if _drag_from != Vector2.INF and event.position.distance_to(_drag_from) < 6.0:
			_tap(event.position)
		_drag_from = Vector2.INF
		return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		_drag_from = event.position
		_drag_scroll = scroll
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed(ACTION):
		close()
	elif event.is_action_pressed("ui_up", true) or event.is_action_pressed("move_up", true):
		_scroll_by(_line_h())
	elif event.is_action_pressed("ui_down", true) or event.is_action_pressed("move_down", true):
		_scroll_by(-_line_h())
	elif event.is_action_pressed("ui_left", true) or _key(event, KEY_PAGEUP):
		_scroll_by(page)
	elif event.is_action_pressed("ui_right", true) or _key(event, KEY_PAGEDOWN):
		_scroll_by(-page)
	elif _key(event, KEY_HOME):
		scroll = INF
		_clamp()
	elif _key(event, KEY_END):
		scroll = 0.0


func _key(event: InputEvent, k: Key) -> bool:
	return event is InputEventKey and event.pressed and event.physical_keycode == k


func _tap(p: Vector2) -> void:
	if _close_rect.has_point(p) or not _panel.has_point(p):
		close()


func _scroll_by(d: float) -> void:
	scroll += d
	_clamp()


func _clamp() -> void:
	scroll = clampf(scroll, 0.0, maxf(_content_h - _view_h, 0.0))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.025, 0.05, 0.7))
	var w := minf(Access.px(470.0), vs.x - 16.0)
	_panel = Rect2((vs.x - w) / 2.0, 8.0, w, vs.y - 16.0)
	UiSkin.panel(self, _panel, "ledger")
	var head_y := _panel.position.y + Access.px(22.0)
	draw_string(UiSkin.TITLE_FONT, Vector2(_panel.position.x + 18, head_y), tr("Dialogue log"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(16), Color("f3f1ea"))
	var close_s := tr("Close")
	var cw := font.get_string_size(close_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x + 14.0
	_close_rect = Rect2(_panel.end.x - cw - 14, head_y - Access.px(13.0), cw, Access.px(17.0))
	UiSkin.panel(self, _close_rect, "button")
	draw_string(font, _close_rect.position + Vector2(7, Access.px(12.0)), close_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), TEXT)

	var top := head_y + Access.px(10.0)
	var bottom := _panel.end.y - Access.px(20.0)
	_view_h = bottom - top
	var x := _panel.position.x + 20.0
	var text_x := x + Access.px(78.0)
	var text_w := _panel.end.x - 20.0 - text_x
	var fsize := Access.fs(10)
	# Measure every entry, newest last, then draw upwards from the bottom.
	var heights := []
	_content_h = 0.0
	for e in entries:
		var h := font.get_multiline_string_size(Dialogue.plain(str(e["text"])), HORIZONTAL_ALIGNMENT_LEFT, text_w, fsize).y + Access.px(5.0)
		heights.append(h)
		_content_h += h
	_clamp()
	if entries.is_empty():
		draw_string(font, Vector2(x, top + Access.px(20.0)), tr("Nothing has been said yet."), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10), SOFT)
	var y := bottom + scroll
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var h: float = heights[i]
		y -= h
		if y > bottom:
			continue
		if y + h < top:
			break
		if y < top - 1.0:
			continue  # half above the top: hidden rather than drawn over the heading
		var who := str(e["who"])
		var col := TEXT
		if who != "":
			var acc := Dialogue.accent(who)
			draw_rect(Rect2(x - 6, y + 2, 2, h - 6), acc)
			draw_string(font, Vector2(x, y + Access.px(10.0)), Dialogue.display_name(who), HORIZONTAL_ALIGNMENT_LEFT, text_x - x - 6, Access.fs(9), acc.lightened(0.35))
		else:
			col = SOFT  # narration
		Dialogue.draw_text(self, font, Vector2(text_x, y + Access.px(10.0)), str(e["text"]), text_w, fsize, col, -1, Color(col, 0.9))
	# Scroll bar.
	if _content_h > _view_h:
		var bar := Rect2(_panel.end.x - 10, top, 2, _view_h)
		draw_rect(bar, Color(1, 1, 1, 0.08))
		var frac := _view_h / _content_h
		var pos := 1.0 - (scroll + _view_h) / _content_h
		draw_rect(Rect2(bar.position.x, top + _view_h * pos, 2, maxf(_view_h * frac, 6.0)), GOLD)
	var hint := Prompts.help([["updown", "scroll"], ["leftright", "page"], ["ui_cancel", "close"]], tr("Drag to scroll, tap outside to close"))
	draw_string(font, Vector2(x, _panel.end.y - Access.px(8.0)), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), DIM)
