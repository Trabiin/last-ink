extends Control
## The alert tray and the pinned story goal (issue #22), drawn over the Command Table or the
## Hollowmark HUD. On the Command Table it also puts markers on the territory map: a pin over
## every province an alert points at, a gold star over story missions, and a ring round the
## province the story goal wants.
##
## Tab (gamepad RT, action "alert_go") goes to the newest alert, or to the story goal when the
## tray is empty. Click or tap a row to go there; the x on a row dismisses it.
##
## The host (command.gd or hub.gd) provides:
##   alerts_blocked() -> bool     true while a screen or menu is open
##   alert_go(target: Dictionary) target = {"province", "mission"?} or {"view"}

const GOLD := Color("ffd166")
const WARN := Color(1, 0.6, 0.52)
const ROW_H := 12.0
const MAX_ROWS := 4

var host: Node
var on_map := false  # true on the Command Table
var origin := Vector2(6, 39)  # top-left corner, or bottom-left when grow_up
var grow_up := false  # stack upwards from origin (the Command Table keeps the map's top clear)
var width := 300.0
var font: Font
var t := 0.0
var rows: Array = []  # [Rect2 row, Rect2 x-button, alert] filled while drawing
var goal_rect := Rect2()
var goal_target := {}
var flash_pid := ""
var flash_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	Alerts.inst()
	if on_map:
		var f := Alerts.take_focus()  # sent here from town by a "go there"
		if not f.is_empty():
			if f.has("province"):
				flash(f["province"])
			host.call_deferred("alert_go", f)


func _process(delta: float) -> void:
	t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if host == null or host.alerts_blocked():
		return
	if Input.is_action_just_pressed("alert_go"):
		go(Alerts.inst().next_target())


## Goes to an alert (or the goal, id -1) and clears the alert.
func go(a: Dictionary) -> void:
	if a.is_empty():
		return
	var target: Dictionary = a.get("target", {})
	if int(a.get("id", -1)) >= 0:
		Alerts.inst().dismiss(int(a["id"]))
	if target.has("province"):
		flash(target["province"])
	host.alert_go(target)


func flash(pid: String) -> void:
	flash_pid = pid
	flash_t = 1.2


func _input(event: InputEvent) -> void:
	if host == null or host.alerts_blocked() or not visible:
		return
	var pos := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos == Vector2.INF:
		return
	pos = get_global_transform_with_canvas().affine_inverse() * pos
	for r in rows:
		if (r[1] as Rect2).has_point(pos):
			Alerts.inst().dismiss(int(r[2]["id"]))
			get_viewport().set_input_as_handled()
			return
		if (r[0] as Rect2).has_point(pos):
			go(r[2])
			get_viewport().set_input_as_handled()
			return
	if goal_rect.has_point(pos) and not goal_target.is_empty():
		go({"id": -1, "target": goal_target})
		get_viewport().set_input_as_handled()


func _hidden() -> bool:
	if host == null:
		return true
	if not on_map and ((host.dialogue_box and host.dialogue_box.visible) or (host.chapter_card and host.chapter_card.visible)):
		return true  # conversations and story cards have the screen to themselves
	return false


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), 3, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)


func _fit(s: String, w: float, size: int) -> String:
	if font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x <= w:
		return s
	while s.length() > 4 and font.get_string_size(s + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x > w:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + "..."


func _draw() -> void:
	rows = []
	goal_rect = Rect2()
	goal_target = {}
	if _hidden():
		return
	var store := Alerts.inst()
	if on_map:
		_draw_markers(store)
	var x := origin.x
	var pend: Array = store.pending()
	var tab_hint := Loc.t("tap") if Prompts.touch() else Prompts.key("alert_go")  # follows the device and remaps (issue #115)
	var g := Alerts.goal()
	var y := origin.y
	if grow_up:
		var h := (15.0 if not g.is_empty() else 0.0) + mini(pend.size(), MAX_ROWS) * (ROW_H + 1.0) \
			+ (10.0 if pend.size() > MAX_ROWS else 0.0) + store.plain.size() * 11.0
		y = origin.y - h

	# The pinned story goal.
	if not g.is_empty():
		goal_target = g.get("target", {})
		var gs := tr("Story: ") + str(g["text"])
		var hint := Prompts.fill(str(g.get("hint", "")))
		var gw := font.get_string_size(gs, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
		var key := ""
		if not goal_target.is_empty():
			key = tr("  [%s: go]") % tab_hint if pend.is_empty() else tr("  [go]")
		var hw := font.get_string_size(("  " + hint if hint != "" else "") + key, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
		goal_rect = Rect2(x, y, minf(gw + hw + 12, width + 60), 13)
		draw_rect(goal_rect, Color(0.06, 0.05, 0.08, 0.78))
		draw_rect(Rect2(x, y, 2, 13), GOLD)
		_text(Vector2(x + 6, y + 10), gs, 8, GOLD)
		if hint != "":
			_text(Vector2(x + 6 + gw + 6, y + 10), hint, 7, Color(0.75, 0.72, 0.66))
		if key != "":
			var kx := x + 6 + gw + (font.get_string_size("  " + hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x if hint != "" else 0.0)
			_text(Vector2(kx, y + 10), key, 7, GOLD.darkened(0.15))
		y += 15.0

	# Alerts that point somewhere, newest first.
	var shown := 0
	for a in pend:
		if shown >= MAX_ROWS:
			break
		var r := Rect2(x, y, width, ROW_H)
		var xr := Rect2(x + width - 12, y, 12, ROW_H)
		var col: Color = WARN if a["warning"] else Color(0.93, 0.9, 0.83)
		var pulse := 0.0
		if Engine.get_process_frames() - int(a["frame"]) < 240:
			pulse = 0.5 + 0.5 * sin(t * 8.0)  # new: blink for a few seconds
		draw_rect(r, Color(0.06, 0.05, 0.08, 0.8))
		draw_rect(Rect2(x, y, 2, ROW_H), (WARN if a["warning"] else GOLD).lerp(Color.WHITE, pulse * 0.6))
		var go := (tr("%s: go") % tab_hint) if shown == 0 else Loc.t("go")
		var gw2 := font.get_string_size(go, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
		_text(Vector2(x + 6, y + 9), _fit(str(a["text"]), width - gw2 - 30, 8), 8, col)
		_text(Vector2(x + width - 18 - gw2, y + 9), go, 7, GOLD)
		_text(Vector2(xr.position.x + 3, y + 9), "x", 7, Color(0.6, 0.58, 0.6))
		rows.append([r, xr, a])
		y += ROW_H + 1.0
		shown += 1
	if pend.size() > MAX_ROWS:
		_text(Vector2(x + 6, y + 8), tr("+%d more") % (pend.size() - MAX_ROWS), 7, Color(0.7, 0.68, 0.7))
		y += 10.0

	# Plain notices fade out below.
	for n in store.plain:
		var a3 := clampf(float(n[2]) / 0.6, 0.0, 1.0)
		_text(Vector2(x + 2, y + 9), _fit(str(n[0]), width + 60, 8), 8, Color(WARN, a3) if n[1] else Color(0.9, 0.88, 0.8, a3))
		y += 11.0


## Markers on the territory map: alert pins, story stars, the goal's ring and the "go there" flash.
func _draw_markers(store: Alerts) -> void:
	var flagged := store.flagged_provinces()
	var g := Alerts.goal()
	var goal_pid: String = g.get("target", {}).get("province", "") if not g.is_empty() else ""
	for p in host.territory.provinces:
		var pid: String = p["id"]
		var pos: Vector2 = host._province_screen_pos(p)
		var story := false
		for m in Missions.list_for_province(pid):
			if m.get("story", false):
				story = true
		if story:
			var c := pos + Vector2(-18, -10)
			_star(c, 4.5 + 0.6 * sin(t * 4.0), GOLD)
		if pid == goal_pid:
			var pulse := 0.5 + 0.5 * sin(t * 3.0)
			draw_arc(pos + Vector2(0, -6), 19.0 + pulse * 2.0, 0, TAU, 40, Color(GOLD, 0.35 + 0.35 * pulse), 1.5)
		if flagged.has(pid):
			var col: Color = WARN if flagged[pid] else GOLD
			var bob := sin(t * 5.0) * 1.5
			var tip := pos + Vector2(14, -14 + bob)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, -6), tip + Vector2(0, -12), tip + Vector2(4, -6)]), Color(0.05, 0.04, 0.07))
			draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -1.5), tip + Vector2(-3, -6), tip + Vector2(0, -10.5), tip + Vector2(3, -6)]), col)
			draw_string(font, tip + Vector2(-1.5, -3), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(0.05, 0.04, 0.07))
		if pid == flash_pid and flash_t > 0.0:
			var k := 1.0 - flash_t / 1.2
			draw_arc(pos + Vector2(0, -6), 6.0 + 30.0 * k, 0, TAU, 40, Color(1, 1, 1, 1.0 - k), 2.0)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * (r if i % 2 == 0 else r * 0.45))
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(1, 1))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.7))
	draw_colored_polygon(pts, col)
