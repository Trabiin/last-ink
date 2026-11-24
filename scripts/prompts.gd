class_name Prompts
extends RefCounted
## Button prompts that match the device in use (issue #23).
## Controls (the autoload) feeds every input event to Prompts.note(); screens then ask
## Prompts.key("ui_accept") for "Enter", "A", "Cross"... or build a whole help line with
## Prompts.help(). Labels are read from the InputMap when drawn, so remapped keys show up.

const KEYS := "keys"  # keyboard and mouse
const PAD := "pad"
const TOUCH := "touch"

static var device := KEYS
static var pad_style := "xbox"  # xbox, playstation or nintendo (face button names)

const PAD_NAMES := {
	"xbox": {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_SHOULDER: "LB",
		JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3"},
	"playstation": {JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle", JOY_BUTTON_X: "Square",
		JOY_BUTTON_Y: "Triangle", JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options",
		JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_LEFT_STICK: "L3",
		JOY_BUTTON_RIGHT_STICK: "R3"},
	# Godot names buttons by position (A = bottom); Nintendo prints the letters swapped.
	"nintendo": {JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
		JOY_BUTTON_BACK: "-", JOY_BUTTON_START: "+", JOY_BUTTON_LEFT_SHOULDER: "L",
		JOY_BUTTON_RIGHT_SHOULDER: "R", JOY_BUTTON_LEFT_STICK: "L-stick", JOY_BUTTON_RIGHT_STICK: "R-stick"},
}
const TRIGGERS := {
	"xbox": ["LT", "RT"], "playstation": ["L2", "R2"], "nintendo": ["ZL", "ZR"],
}
const DPAD := {JOY_BUTTON_DPAD_UP: "Up", JOY_BUTTON_DPAD_DOWN: "Down",
	JOY_BUTTON_DPAD_LEFT: "Left", JOY_BUTTON_DPAD_RIGHT: "Right"}
const KEY_SHORT := {"Escape": "Esc", "Kp Enter": "Enter", "BackSpace": "Backspace", "Equal": "=", "Minus": "-"}
## Key names the engine gives in English (OS.get_keycode_string), shown through Loc.t so a catalogue
## can name them in its language. Letters, digits and F-keys stay as they are.
const KEY_NAMES := ["Space", "Enter", "Esc", "Tab", "Backspace", "Shift", "Ctrl", "Alt", "Up", "Down",
	"Left", "Right", "Delete", "Insert", "Home", "End", "PageUp", "PageDown", "CapsLock", "Pause", "Menu"]


## Called by Controls for every input event: remembers what the player last touched.
## Moving the mouse alone never flips away from pad or touch prompts.
static func note(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		device = KEYS
	elif event is InputEventMouseButton and event.pressed:
		device = KEYS
	elif event is InputEventScreenTouch and event.pressed:
		device = TOUCH
	elif (event is InputEventJoypadButton and event.pressed) \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		if device != PAD:
			pad_style = style_of(Input.get_joy_name(event.device))
		device = PAD


static func style_of(joy_name: String) -> String:
	var n := joy_name.to_lower()
	if n.contains("ps3") or n.contains("ps4") or n.contains("ps5") or n.contains("dualshock") \
			or n.contains("dualsense") or n.contains("sony") or n.contains("playstation"):
		return "playstation"
	if n.contains("nintendo") or n.contains("switch") or n.contains("pro controller") or n.contains("joy-con"):
		return "nintendo"
	return "xbox"


static func pad() -> bool:
	return device == PAD


static func touch() -> bool:
	return device == TOUCH


## A short name for the button that triggers this action on the current device.
## Empty when the action has nothing bound there (or on touch: you tap things instead).
static func key(action: String, on := "") -> String:
	var dev := device if on == "" else on
	if dev == TOUCH or not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		var s := _event_name(ev, dev)
		if s != "":
			return s
	return ""


## A keyboard key as players read it: short ("Esc") and, for named keys, in the game's language.
static func key_label(code: int) -> String:
	var s: String = OS.get_keycode_string(code)
	s = KEY_SHORT.get(s, s)
	return Loc.t(s) if s in KEY_NAMES else s


static func _event_name(ev: InputEvent, dev: String) -> String:
	if dev == KEYS and ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return key_label(code)
	if dev == PAD and ev is InputEventJoypadButton:
		if DPAD.has(ev.button_index):
			return Loc.t("D-pad %s") % Loc.t(str(DPAD[ev.button_index]))
		return Loc.t(str(PAD_NAMES[pad_style].get(ev.button_index, "")))
	if dev == PAD and ev is InputEventJoypadMotion:
		if ev.axis == JOY_AXIS_TRIGGER_LEFT:
			return TRIGGERS[pad_style][0]
		if ev.axis == JOY_AXIS_TRIGGER_RIGHT:
			return TRIGGERS[pad_style][1]
		return Loc.t("Stick")
	return ""


## The first non-empty key among several actions (e.g. ["research", "ui_cancel"]).
static func any_key(actions: Array) -> String:
	for a in actions:
		var s := key(a)
		if s != "":
			return s
	return ""


## A help line for the bottom of a screen. `parts` is a list of [what, verb] pairs, where
## `what` is an action name, a list of actions (keyboard shows them all, a pad the first one
## that is bound), or "updown" / "leftright" / "move" for the arrows or the stick.
## On touch the line is `touch_text` instead.
## Example: Prompts.help([["updown", "choose"], ["ui_accept", "pick"], ["ui_cancel", "close"]],
## "Tap a row, tap it again to act")
static func help(parts: Array, touch_text := "Tap to choose") -> String:
	if device == TOUCH:
		return Loc.t(touch_text)
	var out := PackedStringArray()
	for p in parts:
		var what = p[0]
		var label := ""
		match what:
			"updown":
				label = Loc.t("D-pad") if device == PAD else Loc.t("Up/Down")
			"leftright":
				label = Loc.t("D-pad Left/Right") if device == PAD else Loc.t("Left/Right")
			"move":
				label = Loc.t("Stick") if device == PAD else Loc.t("WASD")
			_:
				label = _keys_of(what if what is Array else [what])
		if label != "":
			out.append(Loc.t("%s %s", "key and what it does") % [label, Loc.t(str(p[1]))])
	return "   ".join(out)


static func _keys_of(actions: Array) -> String:
	var seen := PackedStringArray()
	for a in actions:
		var s := key(a)
		if s != "" and not seen.has(s):
			seen.append(s)
			if device == PAD:
				break
	return " / ".join(seen)


## "Enter" / "A" / "Tap": what to press to go on (story cards, results, prompts).
static func confirm() -> String:
	return Loc.t("Tap") if device == TOUCH else key("ui_accept")


## True for a left click or a finger touching down. Touch does not emulate the mouse in
## this project, so every tappable screen checks both.
static func tapped(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)


## The mouse wheel or a finger dragged over a list, in rows: +n moves the focus n rows down (wheel
## down, or the finger pushing the list up), -n up, 0 for any other event. `state` keeps the part of a
## drag that is still under a row. `inside`: whether the event is over the list; a drag keeps going
## wherever the finger wanders, as long as it started on the list. Lets a mouse or touch player reach
## rows scrolled out of sight.
static func list_steps(event: InputEvent, state: Dictionary, row_px: float, inside := true) -> int:
	if event is InputEventMouseButton and event.pressed and inside:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return 1
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			return -1
	elif event is InputEventScreenDrag:
		state["moved"] = float(state.get("moved", 0.0)) + absf(event.relative.y)
		if not state.get("on_list", false):
			return 0
		var d: float = float(state.get("drag", 0.0)) - event.relative.y
		var n := int(d / maxf(row_px, 1.0))
		state["drag"] = d - n * row_px
		return n
	elif event is InputEventScreenTouch and event.pressed:
		state["drag"] = 0.0
		state["moved"] = 0.0
		state["on_list"] = inside
	return 0


## Tap, tap again on a list a finger can also drag: a click picks a row at once, but a finger only
## counts when it lifts again on the same row without having dragged, so a drag never picks or acts.
## Pass the row under the pointer (-1 for none) and the focused row. Returns "focus" (move the focus
## there), "act" (it was already focused: do it) or "" (nothing yet).
static func list_tap(event: InputEvent, state: Dictionary, row: int, focused: int) -> String:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return "" if row < 0 else ("act" if row == focused else "focus")
	if event is InputEventScreenTouch:
		if event.pressed:
			state["down_row"] = row
			return ""
		var down: int = state.get("down_row", -1)
		state["down_row"] = -1
		if row < 0 or row != down or float(state.get("moved", 0.0)) >= 8.0:
			return ""
		return "act" if row == focused else "focus"
	return ""


## The row `d` steps from `from` in a list whose header rows (dictionaries with "head") are skipped.
## Without wrap it stops at either end, as wheels and drags should.
static func step_row(rows: Array, from: int, d: int, wrap := true) -> int:
	if rows.is_empty():
		return from
	var s := from
	for k in absi(d):
		var t := s
		for n in rows.size():
			t += signi(d)
			if wrap:
				t = posmod(t, rows.size())
			elif t < 0 or t >= rows.size():
				t = s
				break
			if not (rows[t] is Dictionary and (rows[t] as Dictionary).has("head")):
				break
		s = t
	return s


## Screens built from Godot controls (buttons, check boxes, text boxes: the report form, the playtest
## survey) never see a finger, because the project turns off "touch as mouse" for the game's own tap
## handling. They call this first thing in _input: a touch or drag on them is handed to the controls as
## the matching left-button mouse event, and the touch itself is used up. True when it did that.
static func touch_to_mouse(host: Control, event: InputEvent) -> bool:
	var vp := host.get_viewport()
	if vp == null:
		return false
	if event is InputEventScreenTouch:
		if event.index != 0:
			vp.set_input_as_handled()  # a second finger does nothing here
			return true
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = event.pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if event.pressed else 0
		mb.double_click = event.double_tap
		mb.position = event.position
		mb.global_position = event.position
		vp.set_input_as_handled()
		vp.push_input(mb, true)
		return true
	if event is InputEventScreenDrag:
		if event.index != 0:
			vp.set_input_as_handled()
			return true
		var mm := InputEventMouseMotion.new()
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm.position = event.position
		mm.global_position = event.position
		mm.relative = event.relative
		mm.velocity = event.velocity
		vp.set_input_as_handled()
		vp.push_input(mm, true)
		return true
	return false


## " (B)" after a screen's name in running text: its shortcut on this device, or nothing.
static func tag(action: String) -> String:
	var k := key(action)
	return "" if k == "" else " (%s)" % k


## Fills button tokens in text written in data files, for the device in use (issue #115):
##   {tag:action}   " (T)" after a name; on a pad with nothing bound " (via Menu)"; nothing on touch
##   {key:action}   "T" / "Y"; on a pad with nothing bound "the Menu button"; on touch "a tap"
##   {confirm}      "Enter" / "A" / "Tap"
##   {back}         "Esc" / "B" / "the back button"
##   {dev:keyboard text|pad text|touch text}   whichever matches the device (touch may be left out)
## Keys are read from the InputMap, so remapped controls show up. Text with no "{" is returned as is.
static func fill(text: String) -> String:
	if not "{" in text:
		return text
	var out := ""
	var i := 0
	while i < text.length():
		var open := text.find("{", i)
		if open < 0:
			out += text.substr(i)
			break
		var close := _closing(text, open)
		if close < 0:
			out += text.substr(i)
			break
		out += text.substr(i, open - i)
		out += _token(text.substr(open + 1, close - open - 1))
		i = close + 1
	return out


static func _token(tok: String) -> String:
	var colon := tok.find(":")
	var kind := tok if colon < 0 else tok.substr(0, colon)
	var arg := "" if colon < 0 else tok.substr(colon + 1)
	match kind:
		"tag":
			if device == TOUCH:
				return ""
			var k := key(arg)
			if k == "" and device == PAD:
				return Loc.t(" (via %s)") % key("pause")
			return "" if k == "" else " (%s)" % k
		"key":
			if device == TOUCH:
				return Loc.t("a tap")
			var k := key(arg)
			if k == "" and device == PAD:
				return Loc.t("the %s button") % key("pause")
			return k
		"confirm":
			return confirm()
		"back":
			return Loc.t("the back button") if device == TOUCH else key("ui_cancel")
		"dev":
			var parts := arg.split("|")
			var at := 1 if device == PAD else (2 if device == TOUCH else 0)
			if at >= parts.size():
				at = 0
			return fill(parts[at])  # the chosen part may hold tokens of its own
	return "{" + tok + "}"  # not a token: leave it alone


## The "}" that closes the "{" at `open`, counting nested pairs; -1 if it never closes.
static func _closing(text: String, open: int) -> int:
	var depth := 0
	for i in range(open, text.length()):
		var c := text[i]
		if c == "{":
			depth += 1
		elif c == "}":
			depth -= 1
			if depth == 0:
				return i
	return -1
