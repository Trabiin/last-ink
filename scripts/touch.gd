extends Control
## On-screen controls for touch devices: a floating stick on the left half,
## Attack and Swap buttons on the right, plus one button per ability of the hero you control
## (when party is set: missions). They feed the normal input actions.

var stick_index := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var button_touches := {}  # touch index -> action name
const STICK_R := 34.0
const BTN_ATTACK_R := 30.0
const BTN_SWAP_R := 20.0
const BTN_ABILITY_R := 16.0
const ABILITY_ANGLES := [195.0, 230.0, 265.0, 300.0]  # around the Attack button
var party  # main.gd in missions (null in town: no ability buttons)


## In town there is nobody to swap to and no quick menu, and Hollowmark's own Menu button
## sits top-right, so only the stick and a Talk button show (issue #23).
func _in_town() -> bool:
	return party == null


func _ability_count() -> int:
	if party == null or party.leader == null:
		return 0
	return mini(party.leader.abilities.size(), ABILITY_ANGLES.size())


func _ability_center(i: int) -> Vector2:
	return _attack_center() + Vector2.RIGHT.rotated(deg_to_rad(ABILITY_ANGLES[i])) * 60.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available()


func _attack_center() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 50, vs.y - 70)


func _pause_center() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 22, 22)


func _menu_center() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 54, 22)


func _swap_center() -> Vector2:
	var vs := get_viewport_rect().size
	return Vector2(vs.x - 110, vs.y - 40)


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton:
		if visible:
			release_all()
			visible = false
		return
	if event is InputEventScreenTouch:
		visible = true
		var pos: Vector2 = event.position
		if event.pressed:
			if pos.distance_to(_attack_center()) < BTN_ATTACK_R + 10.0:
				button_touches[event.index] = "attack"
				Input.action_press("attack")
			elif _ability_at(pos) >= 0:
				var act := "ability_%d" % (_ability_at(pos) + 1)
				button_touches[event.index] = act
				Input.action_press(act)
			elif not _in_town() and pos.distance_to(_pause_center()) < 18.0:
				button_touches[event.index] = "pause"
				Input.action_press("pause")
			elif not _in_town() and pos.distance_to(_menu_center()) < 16.0 and InputMap.has_action("quick_menu"):
				button_touches[event.index] = "quick_menu"
				Input.action_press("quick_menu")
			elif not _in_town() and pos.distance_to(_swap_center()) < BTN_SWAP_R + 10.0:
				button_touches[event.index] = "swap"
				Input.action_press("swap")
			elif pos.x < get_viewport_rect().size.x * 0.5 and stick_index == -1:
				stick_index = event.index
				stick_origin = pos
				stick_pos = pos
		else:
			if button_touches.has(event.index):
				Input.action_release(button_touches[event.index])
				button_touches.erase(event.index)
			if event.index == stick_index:
				stick_index = -1
				_apply_stick(Vector2.ZERO)
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == stick_index:
		stick_pos = event.position
		var v: Vector2 = (stick_pos - stick_origin) / STICK_R
		if v.length() > 1.0:
			v = v.normalized()
		_apply_stick(v)
		queue_redraw()


func _ability_at(pos: Vector2) -> int:
	for i in _ability_count():
		if pos.distance_to(_ability_center(i)) < BTN_ABILITY_R + 6.0:
			return i
	return -1


func _process(_delta: float) -> void:
	if visible and _ability_count() > 0:
		queue_redraw()  # cooldowns and Ink change every frame


func _apply_stick(v: Vector2) -> void:
	_set_axis("move_left", "move_right", v.x)
	_set_axis("move_up", "move_down", v.y)


func _set_axis(neg: String, pos: String, value: float) -> void:
	if value < -0.15:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > 0.15:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func release_all() -> void:
	for a in button_touches.values():
		Input.action_release(a)
	button_touches.clear()
	stick_index = -1
	_apply_stick(Vector2.ZERO)


func _draw() -> void:
	var a := _attack_center()
	draw_circle(a, BTN_ATTACK_R, Color(1, 1, 1, 0.18 if not button_touches.values().has("attack") else 0.4))
	draw_arc(a, BTN_ATTACK_R, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)
	var a_label := tr("TALK") if _in_town() else tr("ATTACK")
	var alw := ThemeDB.fallback_font.get_string_size(a_label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
	draw_string(ThemeDB.fallback_font, a + Vector2(-alw / 2.0, 4), a_label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), Color(1, 1, 1, 0.8))
	if not _in_town():
		_draw_mission_buttons()
	_draw_stick()


## Swap, abilities, pause and the quick menu: missions only.
func _draw_mission_buttons() -> void:
	var s := _swap_center()
	draw_circle(s, BTN_SWAP_R, Color(1, 1, 1, 0.18 if not button_touches.values().has("swap") else 0.4))
	draw_arc(s, BTN_SWAP_R, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)
	draw_string(ThemeDB.fallback_font, s + Vector2(-12, 4), tr("SWAP"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), Color(1, 1, 1, 0.8))
	for i in _ability_count():
		var hero: Hero = party.leader
		var ab: Dictionary = hero.abilities[i]
		var ready := Abilities.blocker(hero, i) == ""
		var col := Abilities.color_of(ab)
		var ac := _ability_center(i)
		var held := button_touches.values().has("ability_%d" % (i + 1))
		draw_circle(ac, BTN_ABILITY_R, Color(col, 0.4 if held else (0.22 if ready else 0.08)))
		draw_arc(ac, BTN_ABILITY_R, 0, TAU, 24, Color(col, 0.8 if ready else 0.3), 1.5)
		var cd: float = hero.cooldowns[i]
		if cd > 0.0:
			draw_arc(ac, BTN_ABILITY_R - 3.0, -PI / 2.0, -PI / 2.0 + TAU * cd / float(ab.get("cooldown", 1.0)), 20, Color(1, 1, 1, 0.5), 2.0)
		var label := str(ab.get("short", ab.get("name", "?"))).substr(0, 8)
		var lw := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
		draw_string(ThemeDB.fallback_font, ac + Vector2(-lw / 2.0, 3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(1, 1, 1, 0.9 if ready else 0.45))
	var pc := _pause_center()
	draw_circle(pc, 13.0, Color(1, 1, 1, 0.18))
	draw_rect(Rect2(pc + Vector2(-4, -5), Vector2(3, 10)), Color(1, 1, 1, 0.8))
	draw_rect(Rect2(pc + Vector2(1, -5), Vector2(3, 10)), Color(1, 1, 1, 0.8))
	var mc := _menu_center()  # quick menu: three lines
	draw_circle(mc, 13.0, Color(1, 1, 1, 0.18))
	for i in 3:
		draw_rect(Rect2(mc + Vector2(-5, -5 + i * 4), Vector2(10, 2)), Color(1, 1, 1, 0.8))


func _draw_stick() -> void:
	if stick_index != -1:
		draw_circle(stick_origin, STICK_R, Color(1, 1, 1, 0.12))
		draw_arc(stick_origin, STICK_R, 0, TAU, 32, Color(1, 1, 1, 0.4), 1.5)
		var knob := stick_origin + (stick_pos - stick_origin).limit_length(STICK_R)
		draw_circle(knob, 12.0, Color(1, 1, 1, 0.35))
	else:
		var vs := get_viewport_rect().size
		draw_string(ThemeDB.fallback_font, Vector2(24, vs.y - 50), tr("drag here to move"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), Color(1, 1, 1, 0.35))
