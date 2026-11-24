extends Node
## Autoload "Controls": defines every input action in code (keyboard, gamepad; touch
## buttons press these same actions). Runs before any scene so menus and gameplay share it.


## Web build, phones: on-screen keyboards type a word as an IME "composition" and Godot 4.3 shows it
## only from compositionupdate events, which some Android keyboards don't send, so a word appeared
## only once space finished it (issue #175 follow-up). This hook watches Godot's hidden IME element
## and, while a word is being composed, re-sends what is in it as a compositionupdate, so the text
## field shows each letter as it is typed. It also counts which typing events the browser sends;
## Diag.system_info() puts the counts in bug reports (web_typing) so a phone that still misbehaves
## shows why. Desktop keyboards don't compose, so nothing changes there.
const WEB_TYPING_HOOK := """
(function () {
	if (window.__lastInkTyping) return;
	var st = window.__lastInkTyping = { seen: {}, synced: 0 };
	function count(k) { st.seen[k] = (st.seen[k] || 0) + 1; }
	function hook(ime) {
		if (ime.__lastInkHooked) return;
		ime.__lastInkHooked = true;
		var composing = false;
		['compositionstart', 'compositionupdate', 'compositionend'].forEach(function (t) {
			ime.addEventListener(t, function (e) {
				if (!e.isTrusted) return;
				count(t);
				if (t === 'compositionstart') composing = true;
				if (t === 'compositionend') composing = false;
			}, true);
		});
		ime.addEventListener('keydown', function (e) {
			if (e.isTrusted) count(e.key === 'Unidentified' || e.keyCode === 229 ? 'keydown:ime' : 'keydown');
		}, true);
		ime.addEventListener('input', function (e) {
			count('input:' + (e.inputType || '?'));
			if (!composing || !e.isComposing) return;
			st.synced++;
			ime.dispatchEvent(new CompositionEvent('compositionupdate', { data: ime.textContent || '' }));
		}, false);
	}
	var tries = 0;
	(function find() {
		var ime = document.querySelector('div.ime');
		if (ime) hook(ime);
		else if (tries++ < 50) setTimeout(find, 200);
	})();
})();
"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		JavaScriptBridge.eval(WEB_TYPING_HOOK, true)
	_add_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_add_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_add_action("attack", [KEY_J, KEY_SPACE, KEY_Z], [JOY_BUTTON_A, JOY_BUTTON_X])
	_add_action("swap", [KEY_TAB, KEY_Q], [JOY_BUTTON_Y])
	_add_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	# Command clock: 1-4 pick pause/1x/2x/4x, shoulders step slower/faster.
	_add_action("clock_slower", [], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("clock_faster", [], [JOY_BUTTON_RIGHT_SHOULDER])
	for i in 4:
		_add_action("clock_speed_%d" % i, [KEY_1 + i, KEY_KP_1 + i], [])
	# Abilities in missions (issue #7): 1-4 (same keys as the clock, which is frozen out there),
	# gamepad LB / RB / LT / RT. Touch buttons press these too.
	_add_action("ability_1", [KEY_1, KEY_KP_1], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("ability_2", [KEY_2, KEY_KP_2], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("ability_3", [KEY_3, KEY_KP_3], [], JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_action("ability_4", [KEY_4, KEY_KP_4], [], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_action("ledger", [KEY_L], [JOY_BUTTON_BACK])
	_add_action("roster", [KEY_R], [JOY_BUTTON_Y])
	_add_action("buildings", [KEY_B], [JOY_BUTTON_LEFT_STICK])
	_add_action("govern", [KEY_G], [JOY_BUTTON_X])
	_add_action("expeditions", [KEY_E], [JOY_BUTTON_RIGHT_STICK])
	_add_action("research", [KEY_T], [])  # gamepad: through the menus
	_add_action("diplomacy", [KEY_F], [])  # gamepad: through the menus
	_add_action("bonds", [KEY_H], [])  # gamepad: through the menus
	_add_action("newcomers", [KEY_N], [])  # gamepad: through the menus
	_add_action("gear", [KEY_K], [])  # party gear and the shop (issue #15); gamepad: through the menus
	_add_action("armory", [KEY_M], [])  # Forge & Market (issue #112); rebindable; gamepad: through the menus
	_add_action("journal", [KEY_I], [])  # quest log, people, codex, history (issue #114); rebindable; gamepad: through the menus
	_add_action("quick_menu", [KEY_C], [JOY_BUTTON_BACK])  # missions only; Back is the ledger on the Command Table
	# Tabs in every tabbed screen (gear, Forge & Market, journal, quick menu): TabStrip draws these keys
	# beside the tab row. Menus own the input while open, so sharing Q / E / LB / RB with play is fine.
	_add_action("tab_prev", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action("tab_next", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_add_action("alert_go", [KEY_TAB], [], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	# Territory map camera (issue #53): + and - zoom, LT flips between the whole map and the open
	# regions, the right stick pans. The mouse wheel, dragging and pinching are handled by the map.
	_add_action("map_zoom_in", [KEY_EQUAL, KEY_KP_ADD], [])
	_add_action("map_zoom_out", [KEY_MINUS, KEY_KP_SUBTRACT], [])
	_add_action("map_zoom_toggle", [], [], JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_action("map_pan_left", [], [], JOY_AXIS_RIGHT_X, -1.0)
	_add_action("map_pan_right", [], [], JOY_AXIS_RIGHT_X, 1.0)
	_add_action("map_pan_up", [], [], JOY_AXIS_RIGHT_Y, -1.0)
	_add_action("map_pan_down", [], [], JOY_AXIS_RIGHT_Y, 1.0)  # go to the newest alert / the story goal (issue #22); not in missions
	# Menus use Godot's ui_* actions; also let WASD, J and the stick drive them.
	_extend("ui_up", [KEY_W], JOY_AXIS_LEFT_Y, -1.0)
	_extend("ui_down", [KEY_S], JOY_AXIS_LEFT_Y, 1.0)
	_extend("ui_accept", [KEY_J, KEY_Z], -1, 0.0)
	_extend("ui_cancel", [KEY_X], -1, 0.0)


func _add_action(action: String, keys: Array, buttons: Array, axis := -1, axis_value := 0.0) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.3)
	_extend(action, keys, axis, axis_value)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)


func _extend(action: String, keys: Array, axis: int, axis_value: float) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	if axis >= 0:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis
		jm.axis_value = axis_value
		InputMap.action_add_event(action, jm)


## Button prompts follow the device you last used (issue #23). window_input sees every
## event before any screen can mark it handled.
func _enter_tree() -> void:
	get_tree().root.window_input.connect(Prompts.note)
	# Godot's built-in ui_accept / ui_cancel have no gamepad buttons, so a pad could move
	# through menus but never pick or back out. A confirms and B backs out everywhere.
	_add_pad_button("ui_accept", JOY_BUTTON_A)
	_add_pad_button("ui_cancel", JOY_BUTTON_B)


func _add_pad_button(action: String, button: JoyButton) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return
	var jb := InputEventJoypadButton.new()
	jb.button_index = button
	InputMap.action_add_event(action, jb)
