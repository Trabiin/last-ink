extends Control
## Mission results (issue #5): what happened, what the party brings home, and the way back
## to Hollowmark. Shown over the paused mission; Enter / A / tap the button returns home.

signal confirmed

const GOLD := Color("ffd166")
const PAPER := Color("f3f1ea")
const DIM := Color(0.68, 0.66, 0.66)

var result := {}
var _t := 0.0
var _btn := Rect2()
var _shown_frame := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(r: Dictionary) -> void:
	result = r
	_t = 0.0
	_shown_frame = Engine.get_process_frames()
	visible = true
	Audio.sfx("fanfare" if r.get("outcome", "") == "success" else "error")
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() - _shown_frame < 20:
		return  # a beat so a held attack button does not skip the screen
	var go := event.is_action_pressed("ui_accept")
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		go = _btn.grow(6).has_point(event.position)
	if go:
		get_viewport().set_input_as_handled()
		visible = false
		confirmed.emit()


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)


func _text_c(cx: float, y: float, s: String, size: int, col: Color) -> void:
	var w := ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
	draw_string_outline(ThemeDB.fallback_font, Vector2(cx - w / 2.0, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), 4, Color(0, 0, 0, 0.8))
	_text(Vector2(cx - w / 2.0, y), s, size, col)


func _row(x: float, y: float, w: float, label: String, value: String, col := PAPER) -> float:
	_text(Vector2(x, y), label, 9, DIM)
	var font := ThemeDB.fallback_font
	var lines := _wrap(value, w - 92.0, 9)
	for line in lines:
		_text(Vector2(x + 92, y), line, 9, col)
		y += 12.0
	return y + 3.0


func _wrap(s: String, width: float, size: int) -> Array:
	var font := ThemeDB.fallback_font
	var out := []
	var cur := ""
	for word in s.split(" "):
		var test := word if cur == "" else cur + " " + word
		if cur != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x > width:
			out.append(cur)
			cur = word
		else:
			cur = test
	out.append(cur)
	return out


func _draw() -> void:
	if result.is_empty():
		return
	var vs := get_viewport_rect().size
	var a := clampf(_t / 0.35, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, 0.72 * a))
	var outcome: String = result["outcome"]
	var w := minf(340.0, vs.x - 24.0)
	var rows := 4 + (result.get("lines", []) as Array).size()  # objective, time, found, total
	if outcome == "success" and not result.get("rewards", {}).is_empty():
		rows += 1
	if int(result.get("fray", 0)) != 0:
		rows += 1
	var h := 120.0 + 15.0 * rows + (12.0 if result.get("first_clear", false) else 0.0)
	var panel := Rect2((vs.x - w) / 2.0, (vs.y - h) / 2.0 - 6.0 + (1.0 - a) * 12.0, w, h)
	draw_rect(panel, Color(0.09, 0.07, 0.11, 0.97))
	var edge := GOLD if outcome == "success" else Color(0.55, 0.52, 0.56)
	draw_rect(panel, edge, false, 1.0)
	draw_rect(panel.grow(-3), Color(edge, 0.35), false, 1.0)
	var cx := panel.get_center().x
	var y := panel.position.y + 26.0
	_text_c(cx, y, result["title"], 18, GOLD if outcome == "success" else PAPER)
	y += 16.0
	var sub: String = result["name"]
	if result.get("province", "") != "":
		sub += "  ·  " + result["province"]
	_text_c(cx, y, sub, 9, DIM)
	if result.get("first_clear", false):
		y += 12.0
		_text_c(cx, y, tr("First clear"), 8, GOLD)
	y += 20.0
	var x := panel.position.x + 18.0
	var iw := w - 36.0
	var obj_note := "done" if outcome == "success" else tr("not finished")
	y = _row(x, y, iw, tr("Objective"), "%s  (%s)" % [result.get("objective", ""), obj_note], PAPER if outcome == "success" else DIM)
	var secs := int(result.get("time", 0.0))
	y = _row(x, y, iw, tr("Time"), tr("%d:%02d    Nibblers dispersed: %d") % [secs / 60, secs % 60, int(result.get("kills", 0))])
	var found := Missions.res_text(result.get("found", {}))
	if outcome == "wiped":
		y = _row(x, y, iw, tr("Found"), (tr("Dropped it all: ") + found) if found != "" else tr("Nothing"), Color("ff8f7a"))
	else:
		y = _row(x, y, iw, tr("Found"), found if found != "" else tr("Nothing"))
	if outcome == "success":
		var rew := Missions.res_text(result.get("rewards", {}))
		if rew != "":
			y = _row(x, y, iw, tr("Reward"), rew)
	var fray := int(result.get("fray", 0))
	if fray != 0:
		var now := int(result.get("fray_now", 0))
		y = _row(x, y, iw, tr("Fray"), tr("%s %d to %d (the Blank pulls back)") % [result["province"], now, clampi(now + fray, 0, 99)], Color("9fd3a8"))
	for line in result.get("lines", []):
		y = _row(x, y, iw, "", str(line))
	# Total
	y += 2.0
	draw_line(Vector2(x, y - 9), Vector2(x + iw, y - 9), Color(1, 1, 1, 0.12), 1.0)
	var pay := Missions.res_text(result.get("pay", {}))
	y = _row(x, y + 4, iw, tr("Brought home"), pay if pay != "" else tr("Nothing but bruises"), GOLD if pay != "" else DIM)
	# Button
	var bw := 170.0
	_btn = Rect2(cx - bw / 2.0, panel.end.y - 34.0, bw, 22.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_rect(_btn, Color(0.22, 0.17, 0.08))
	draw_rect(_btn, Color(GOLD, 0.6 + 0.4 * pulse), false, 1.0)
	_text_c(cx, _btn.position.y + 15.0, tr("Return to Hollowmark"), 10, GOLD)
	_text_c(cx, panel.end.y + 14.0, Prompts.confirm(), 8, Color(0.75, 0.72, 0.66, 0.9))
