extends Control
## HUD for Hollowmark: day and clock, resources, what the attack button would do,
## talk lines, dawn toasts and Blank notices. Tap or click Roster and Menu on touch screens.

var hub  # hub.gd
var banter_text := ""
var banter_t := 0.0
var sign_text := ""
var toast_text := ""
var toast_warn := ""
var toast_t := 0.0
var notices: Array = []  # [text, warning, time left]
var help_t := 10.0
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	# The walk hint shows once per save; after that only on F1.
	if Dialogue.is_seen("hint:hub"):
		help_t = 0.0
	else:
		Dialogue.mark_seen("hint:hub")


func say(text: String, duration := 3.5) -> void:
	banter_text = text
	banter_t = duration


func toast(text: String, warn := "") -> void:
	toast_text = text
	toast_warn = warn
	toast_t = 3.5


## A one-off line from town (not from the Empire): shown in the alert tray, never kept (issue #22).
func notice(text: String, warning: bool) -> void:
	Alerts.inst().say(text, warning)


func _process(delta: float) -> void:
	banter_t = maxf(banter_t - delta, 0.0)
	toast_t = maxf(toast_t - delta, 0.0)
	help_t = maxf(help_t - delta, 0.0)
	for n in notices:
		n[2] -= delta
	notices = notices.filter(func(n): return n[2] > 0.0)
	queue_redraw()


func _vs() -> Vector2:
	return get_viewport_rect().size


func roster_rect() -> Rect2:
	return Rect2(_vs().x - 112, 6, 58, 16)


func buildings_rect() -> Rect2:
	return Rect2(_vs().x - 186, 6, 70, 16)


func menu_rect() -> Rect2:
	return Rect2(_vs().x - 50, 6, 44, 16)


## Taps and clicks on the two buttons. Touch does not emulate the mouse in this project.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		help_t = 0.0 if help_t > 0.0 else 10.0
		return
	if hub == null or get_tree().paused or hub.roster_view.visible or hub.buildings_view.visible \
			or hub.expedition_view.visible or hub.research_view.visible or hub.diplomacy_view.visible \
			or hub.bonds_view.visible or hub.scene_view.visible or hub.newcomers_view.visible:
		return
	var pos := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	if pos == Vector2.INF:
		return
	if roster_rect().has_point(pos):
		hub.roster_view.open()
		get_viewport().set_input_as_handled()
	elif buildings_rect().has_point(pos):
		hub.buildings_view.open()
		get_viewport().set_input_as_handled()
	elif menu_rect().has_point(pos):
		hub.open_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not hub.target.is_empty() and _prompt_rect().has_point(pos):
		hub._use(hub.target)
		get_viewport().set_input_as_handled()


func _text(pos: Vector2, s: String, size := 10, col := Color.WHITE, outline := true) -> void:
	if outline:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), 3, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)


func _centered(y: float, s: String, size := 10, col := Color.WHITE, outline := true) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
	_text(Vector2((_vs().x - w) / 2.0, y), s, size, col, outline)


func _button(r: Rect2, label: String) -> void:
	UiSkin.panel(self, r, "button")
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
	draw_string(font, r.position + Vector2((r.size.x - w) / 2.0, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color(0.85, 0.82, 0.76))


func _prompt_rect() -> Rect2:
	var vs := _vs()
	return Rect2(vs.x / 2.0 - 90, vs.y - 34, 180, 20)


func _draw() -> void:
	if hub == null:
		return
	if (hub.dialogue_box and hub.dialogue_box.visible) or (hub.chapter_card and hub.chapter_card.visible):
		return  # conversations and story cards have the screen to themselves
	var vs := _vs()
	# Top-left: where, when, how fast.
	UiSkin.panel(self, Rect2(6, 6, 226, 38), "ledger")
	_text(Vector2(13, 21), tr("Hollowmark"), 10, Color("f3efe4"), false)
	var spd: int = Empire.SPEEDS[Empire.speed]
	var clock := tr("Day %d   %s   %s") % [Empire.day, Empire.clock_text(), Loc.t("paused") if spd == 0 else "%dx" % spd]
	_text(Vector2(80, 21), clock, 9, Color(0.78, 0.75, 0.7) if spd > 0 else Color("ffb36b"), false)
	var x := 13.0
	for k in Empire.RESOURCES:
		var s := "%s %d" % [Loc.t(Empire.RES_NAMES[k]), int(Empire.res[k])]
		var col := Color("ff9b8a") if k == "supplies" and Empire.hungry else Color(0.85, 0.83, 0.78)
		if UiSkin.draw_icon(self, k, Rect2(x - 1, 25, 11, 11)):
			x += 12.0
		_text(Vector2(x, 34), s, 8, col, false)
		x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x + 10.0
	_button(roster_rect(), (tr("Roster  %s") % Prompts.key("roster")).strip_edges())
	_button(buildings_rect(), (tr("Buildings  %s") % Prompts.key("buildings")).strip_edges())
	_button(menu_rect(), tr("Menu"))

	# What the attack button does right now.
	if not hub.target.is_empty():
		var key := tr("Tap") if hub.touch_active() else Prompts.key("attack")
		var r := _prompt_rect()
		UiSkin.panel(self, r, "button")
		var label := "%s:  %s" % [key, hub.target["label"]]
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		draw_string(font, r.position + Vector2((r.size.x - w) / 2.0, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), Color("ffd166"))

	if banter_t > 0.0:
		var a := clampf(banter_t / 0.4, 0.0, 1.0)
		var lines := _wrap_lines(banter_text, 420.0, 10)
		var y := vs.y - 70.0 - 13.0 * (lines.size() - 1)
		UiSkin.panel(self, Rect2(vs.x / 2.0 - 220, y - 13, 440, 13.0 * lines.size() + 8), "ledger", Color(1, 1, 1, a))
		for line in lines:
			_centered(y, line, 10, Color(1, 1, 1, a))
			y += 13.0
	if sign_text != "":
		UiSkin.sign(self, vs, vs.y * 0.3, sign_text)
	if toast_t > 0.0:
		var a2 := clampf(toast_t / 0.5, 0.0, 1.0)
		_centered(64, toast_text, 13, Color(1, 0.95, 0.85, a2))
		if toast_warn != "":
			_centered(80, toast_warn, 9, Color(1, 0.6, 0.5, a2))
	# The story goal, alerts and notices are drawn by the alert tray (alert_tray.gd, issue #22).
	if help_t > 0.0 and not hub.touch_active():
		var a4 := clampf(help_t, 0.0, 1.0)
		_text(Vector2(vs.x - Access.px(236.0), 36), tr("Walk: WASD / arrows / stick"), 8, Color(1, 1, 1, a4))
		_text(Vector2(vs.x - Access.px(236.0), 36 + Access.px(11.0)), tr("Talk / use: %s") % Prompts.key("attack"), 8, Color(1, 1, 1, a4))
		if Prompts.pad():  # issue #23: the prompts follow the device in use
			_text(Vector2(vs.x - Access.px(236.0), 36 + Access.px(22.0)), tr("Clock: %s / %s   Menu: %s") % [Prompts.key("clock_slower"), Prompts.key("clock_faster"), Prompts.key("pause")], 8, Color(1, 1, 1, a4))
			_text(Vector2(vs.x - Access.px(236.0), 36 + Access.px(33.0)), tr("Roster %s  Buildings %s  Expeditions %s") % [Prompts.key("roster"), Prompts.key("buildings"), Prompts.key("expeditions")], 8, Color(1, 1, 1, a4))
			_text(Vector2(vs.x - Access.px(236.0), 36 + Access.px(44.0)), tr("Everything else: the Menu"), 8, Color(1, 1, 1, a4))
		else:  # read from the InputMap, so remapped keys show (issue #115)
			_text(Vector2(vs.x - Access.px(236.0), 36 + Access.px(22.0)), tr("Clock: %s-%s   Menu: %s   Journal: %s") % [Prompts.key("clock_speed_0"), Prompts.key("clock_speed_3"),
				Prompts.key("pause"), Prompts.key("journal")], 8, Color(1, 1, 1, a4))
			var keys := PackedStringArray()
			for a in [["roster", tr("Roster")], ["buildings", tr("Buildings")], ["research", tr("Research")], ["diplomacy", tr("Factions")], ["bonds", tr("Bonds")], ["newcomers", tr("Newcomers")]]:
				if Prompts.key(a[0]) != "" and Help.is_open(a[0]):
					keys.append("%s %s" % [a[1], Prompts.key(a[0])])
			_text(Vector2(vs.x - Access.px(236.0), 36 + Access.px(33.0)), "  ".join(keys), 8, Color(1, 1, 1, a4))
			_text(Vector2(vs.x - Access.px(236.0), 36 + Access.px(44.0)), tr("F1: show or hide this   Help: in the Menu"), 8, Color(1, 1, 1, a4))


func _wrap_lines(s: String, width: float, size: int) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for word in s.split(" "):
		var test := word if cur == "" else cur + " " + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x > width and cur != "":
			out.append(cur)
			cur = word
		else:
			cur = test
	if cur != "":
		out.append(cur)
	return out
