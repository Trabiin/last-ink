extends Control
## A full-screen story card (issue #18): "Chapter 1 complete", "New story mission", "End of Act 1".
## Shows a title and a line underneath on a dark band; any confirm key, click or tap closes it
## (after a short beat, so a key held from the dialogue box does not skip it).

signal closed

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")

var heading := ""
var line := ""
var closed_frame := -1
var _t := 0.0
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	visible = false


func show_card(p_heading: String, p_line: String) -> void:
	heading = p_heading
	line = p_line
	_t = 0.0
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	queue_redraw()


func _close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	size = get_viewport_rect().size
	queue_redraw()
	if _t < 0.6:
		return
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack") \
			or Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		_close()


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if pressed:
		accept_event()
		if _t >= 0.6:
			_close()


func _draw() -> void:
	var vs := size
	var a := clampf(_t / 0.5, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.02, 0.04, 0.55 * a))
	var band := Rect2(0, vs.y * 0.5 - 46, vs.x, 92)
	draw_rect(band, Color(0.05, 0.04, 0.07, 0.92 * a))
	draw_line(band.position, band.position + Vector2(vs.x, 0), Color(GOLD, 0.8 * a), 1.0)
	draw_line(band.end - Vector2(vs.x, 0), band.end, Color(GOLD, 0.8 * a), 1.0)
	_centered(vs.y * 0.5 - 10, heading, 18, Color(GOLD, a))
	_centered(vs.y * 0.5 + 14, line, 10, Color(TEXT, a))
	if _t >= 0.6:
		_centered(vs.y * 0.5 + 34, Prompts.confirm() + tr(" to continue"), 8, Color(0.7, 0.68, 0.66, a))


func _centered(y: float, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	draw_string(font, Vector2((size.x - w) / 2.0, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)
