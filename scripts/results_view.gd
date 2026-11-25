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


const LABEL_W := 92.0


## The report's rows as [label, value, ink], in order.
func _rows() -> Array:
	var outcome: String = result["outcome"]
	var rows := []
	var obj_note := "done" if outcome == "success" else tr("not finished")
	rows.append([tr("Objective"), "%s  (%s)" % [result.get("objective", ""), obj_note], LedgerPage.INK if outcome == "success" else LedgerPage.INK_SOFT])
	var secs := int(result.get("time", 0.0))
	rows.append([tr("Time"), tr("%d:%02d    Nibblers dispersed: %d") % [secs / 60, secs % 60, int(result.get("kills", 0))], LedgerPage.INK])
	var found := Missions.res_text(result.get("found", {}))
	if outcome == "wiped":
		rows.append([tr("Found"), (tr("Dropped it all: %s") % found) if found != "" else tr("Nothing"), LedgerPage.RED])
	else:
		rows.append([tr("Found"), found if found != "" else tr("Nothing"), LedgerPage.INK])
	if outcome == "success":
		var rew := Missions.res_text(result.get("rewards", {}))
		if rew != "":
			rows.append([tr("Reward"), rew, LedgerPage.INK])
	var fray := int(result.get("fray", 0))
	if fray != 0:
		var now := int(result.get("fray_now", 0))
		rows.append([tr("Fray"), tr("%s %d to %d (the Blank pulls back)") % [result["province"], now, clampi(now + fray, 0, 99)], LedgerPage.GREEN])
	for line in result.get("lines", []):
		rows.append(["", str(line), LedgerPage.INK])
	return rows


## The report is written up on a worn ledger page (LedgerPage), every line on a ruled line.
func _draw() -> void:
	if result.is_empty():
		return
	var font := ThemeDB.fallback_font
	var vs := get_viewport_rect().size
	var a := clampf(_t / 0.35, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, 0.72 * a))
	var outcome: String = result["outcome"]
	var w := minf(360.0, vs.x - 24.0)
	var rows := _rows()
	var pay := Missions.res_text(result.get("pay", {}))
	var n := 1 + (1 if result.get("first_clear", false) else 0) + 1  # the subtitle, first clear, a gap
	for r in rows:
		n += maxi(1, InkMenu.wrap_px(font, str(r[1]), Access.fs(9), w - 34.0 - LABEL_W).size())
	n += 1 + maxi(1, InkMenu.wrap_px(font, pay, Access.fs(9), w - 34.0 - LABEL_W).size()) + 3  # a gap, the total, the button
	var h := minf(LedgerPage.height_for(n, font, 9), vs.y - 30.0)
	var box := Rect2(floorf((vs.x - w) / 2.0), floorf((vs.y - h) / 2.0 - 6.0 + (1.0 - a) * 12.0), w, h)
	var pg := LedgerPage.begin(self, box, font, 9)
	pg.heading(result["title"], 16, LedgerPage.GOLD if outcome == "success" else LedgerPage.INK)
	var sub: String = result["name"]
	if result.get("province", "") != "":
		sub += "  ·  " + result["province"]
	pg.line(sub, 9, LedgerPage.INK_SOFT)
	if result.get("first_clear", false):
		pg.line(tr("First clear"), 9, LedgerPage.GOLD)
	pg.skip()
	for r in rows:
		pg.field(r[0], r[1], LABEL_W, 9, LedgerPage.INK_SOFT, r[2])
	pg.skip()
	pg.field(tr("Brought home"), pay if pay != "" else tr("Nothing but bruises"), LABEL_W, 9, LedgerPage.INK, LedgerPage.GOLD if pay != "" else LedgerPage.INK_SOFT)
	# The button, on the page's last lines
	var room := pg.space(2)
	var bw := 170.0
	var cx := box.get_center().x
	var by := (room.end.y - 22.0) if room.size != Vector2.ZERO else box.end.y - 30.0
	_btn = Rect2(floorf(cx - bw / 2.0), floorf(by), bw, 22.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	UiSkin.panel(self, _btn, "button", Color(1.05 + 0.15 * pulse, 1.0 + 0.1 * pulse, 0.9))
	UiSkin.frame(self, _btn.grow(1.0))
	_text_c(cx, _btn.position.y + 15.0, tr("Return to Hollowmark"), 10, GOLD)
	_text_c(cx, box.end.y + 14.0, Prompts.confirm(), 8, Color(0.75, 0.72, 0.66, 0.9))
