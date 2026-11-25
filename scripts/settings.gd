class_name Settings
extends RefCounted
## Player options (issue #14): battle speed, difficulty, screen shake, volume and control
## remapping. Everything is static so any scene can read it without an autoload, the same way
## Dialogue does. Values live per device in user://settings.cfg (on the web build that is the
## browser's storage), next to the text speed Dialogue already keeps there.
##
## apply_all() runs once from the title screen: it loads the file, makes the audio buses and puts
## saved key bindings on top of the defaults Controls defined. The options screen is OptionsView.

const PATH := "user://settings.cfg"

const BATTLE_SPEEDS := [0.75, 0.9, 1.0, 1.1, 1.25]
const DIFFICULTIES := ["Story", "Normal", "Hard"]
const DIFFICULTY_INFO := [
	"Enemies hit half as hard and fall faster. For the story and the town.",
	"The fight as designed.",
	"Enemies hit much harder and take a bit more to put down.",
]
## [damage heroes take, damage enemies take] per difficulty.
const DIFFICULTY_MULT := [[0.5, 1.25], [1.0, 1.0], [1.4, 0.85]]
const SHAKES := ["Off", "Low", "Full"]
const SHAKE_MULT := [0.0, 0.45, 1.0]
const BUSES := ["Master", "Music", "SFX", "UI", "Voice"]  # UI and Voice: issue #192

## Every action the player may rebind (issue #192: all of them, menu keys too), in the order the Controls
## page lists them. Menu keys and pause keep a fallback nobody can rebind away (LOCKED), so the options
## screen can always be reached and left: the arrow keys, Enter, Escape, the d-pad, A, B and Start.
const REMAPPABLE := [
	["move_up", "Move up"], ["move_down", "Move down"], ["move_left", "Move left"], ["move_right", "Move right"],
	["attack", "Attack / charge tech"], ["swap", "Swap hero"], ["quick_menu", "Quick menu"],
	["ability_1", "Ability 1"], ["ability_2", "Ability 2"], ["ability_3", "Ability 3"], ["ability_4", "Ability 4"],
	["alert_go", "Go to alert / goal"],  # only if that action exists (issue #22)
	["journal", "Journal"],  # quest log and codex (issue #114)
	["armory", "Forge & Market"],  # issue #112
	["roster", "Roster"], ["buildings", "Buildings"], ["govern", "Governors"], ["expeditions", "Expeditions"],
	["research", "Research"], ["diplomacy", "Diplomacy"], ["bonds", "Bonds"], ["newcomers", "Newcomers"],
	["gear", "Party gear"], ["ledger", "Daily ledger"],
	["clock_slower", "Clock slower"], ["clock_faster", "Clock faster"],
	["clock_speed_0", "Clock: 1x"], ["clock_speed_1", "Clock: 2x"], ["clock_speed_2", "Clock: 4x"], ["clock_speed_3", "Clock: stop (assist)"],
	["map_zoom_in", "Map zoom in"], ["map_zoom_out", "Map zoom out"], ["map_zoom_toggle", "Map: whole / regions"],
	["map_pan_up", "Map pan up"], ["map_pan_down", "Map pan down"], ["map_pan_left", "Map pan left"], ["map_pan_right", "Map pan right"],
	["ui_up", "Menu up"], ["ui_down", "Menu down"], ["ui_left", "Menu left"], ["ui_right", "Menu right"],
	["tab_prev", "Previous tab"], ["tab_next", "Next tab"],
	["ui_accept", "Confirm"], ["ui_cancel", "Back / cancel"], ["pause", "Pause menu"],
	["dialogue_log", "Dialogue log"],  # made by DialogueLog.ensure_action (issue #34)
]

## Where an action is used, for the Controls page's headings and for clashes: two actions only swap keys
## when both can be pressed in the same place (see clash()).
##   move   moving: town, missions, the Command Table   hero  Attack: town (talk) and missions
##   field  missions only                               manage  town and the Command Table
##   menu   menus, conversations and pause
const GROUPS := {
	"move_up": "move", "move_down": "move", "move_left": "move", "move_right": "move", "attack": "hero",
	"swap": "field", "quick_menu": "field", "ability_1": "field", "ability_2": "field", "ability_3": "field", "ability_4": "field",
	"ui_up": "menu", "ui_down": "menu", "ui_left": "menu", "ui_right": "menu", "ui_accept": "menu", "ui_cancel": "menu",
	"tab_prev": "menu", "tab_next": "menu", "pause": "menu", "dialogue_log": "menu",
}
const GROUP_TITLES := {"move": "Moving and fighting", "manage": "Town and Command Table", "menu": "Menus and conversations"}

## Keys and pad inputs that never leave these actions, whatever the player binds: the way back.
const LOCKED_KEYS := {
	"ui_up": [KEY_UP], "ui_down": [KEY_DOWN], "ui_left": [KEY_LEFT], "ui_right": [KEY_RIGHT],
	"ui_accept": [KEY_ENTER, KEY_KP_ENTER], "ui_cancel": [KEY_ESCAPE], "pause": [KEY_ESCAPE],
}
const LOCKED_PAD := {
	"ui_up": [JOY_BUTTON_DPAD_UP], "ui_down": [JOY_BUTTON_DPAD_DOWN], "ui_left": [JOY_BUTTON_DPAD_LEFT],
	"ui_right": [JOY_BUTTON_DPAD_RIGHT], "ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B], "pause": [JOY_BUTTON_START],
}

## One-handed keyboard layouts (issue #192): everything needed in a fight and in menus under one hand.
## The rest stays as it is (and can still be picked with the mouse). Applied over the defaults.
const LAYOUTS := ["Default", "One hand (left)", "One hand (right)"]
const LAYOUT_INFO := [
	"Keys as designed: move with WASD or the arrows, attack with J.",
	"Move with WASD, attack and confirm with Space, swap with Tab, the quick menu on C, abilities on 1 to 4, back with Q, tabs on E and R, the log on the key above Tab.",
	"Move with the arrows, attack and confirm with Enter, swap with Shift, the quick menu on /, abilities on , . ; ' and back with Backspace, tabs on [ and ].",
]
const LAYOUT_KEYS := [
	{},
	{"move_up": KEY_W, "move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "attack": KEY_SPACE, "swap": KEY_TAB,
		"quick_menu": KEY_C, "ability_1": KEY_1, "ability_2": KEY_2, "ability_3": KEY_3, "ability_4": KEY_4,
		"ui_up": KEY_W, "ui_down": KEY_S, "ui_left": KEY_A, "ui_right": KEY_D,
		"ui_accept": KEY_SPACE, "ui_cancel": KEY_Q, "tab_prev": KEY_E, "tab_next": KEY_R, "dialogue_log": KEY_QUOTELEFT},
	{"move_up": KEY_UP, "move_down": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT, "attack": KEY_ENTER,
		"swap": KEY_SHIFT, "quick_menu": KEY_SLASH, "ability_1": KEY_COMMA, "ability_2": KEY_PERIOD,
		"ability_3": KEY_SEMICOLON, "ability_4": KEY_APOSTROPHE, "ui_accept": KEY_ENTER, "ui_cancel": KEY_BACKSPACE,
		"tab_prev": KEY_BRACKETLEFT, "tab_next": KEY_BRACKETRIGHT, "dialogue_log": KEY_BACKSLASH, "pause": KEY_P},
]

## Scene effects (docs/ART_STYLE.md "Sitting in the world"), each a 0-100 slider on the options screen's
## Visual effects page. Read live by Ambience and the lamps, so changes show at once.
## [id, label, default, explanation]
const FX := [
	["shadows", "Cast shadows", 100, "Shadows thrown to the right by buildings and props (light from the top left)."],
	["clouds", "Cloud shadows", 100, "Cloud shadows drifting over the ground by day."],
	["cloud_size", "Cloud size", 50, "Bigger or smaller clouds."],
	["wind", "Cloud speed", 40, "How fast the clouds drift."],
	["mist", "Ground mist", 50, "Low mist, thickest at dawn, dusk and night."],
	["vignette", "Vignette", 40, "Darker screen edges that pull the eye to the middle."],
	["lamp_shadows", "Lamp shadows", 100, "Lamps and your lantern cast shadows off props after dark. 0 = off."],
	["lamp_glow", "Lamp brightness", 60, "How strongly lamps and your lantern light things up."],
]

static var fx := {}  # id -> 0..100
static var battle_speed_i := 2
static var difficulty := 1
static var shake_i := 2
static var rumble_i := 2  # Rumble.LEVELS: Off, Light, Full (issue #149)
static var tips := true  # first-visit explainers and first-time tips (issue #115); the story's unlocks always play
static var volumes := {"Master": 80, "Music": 70, "SFX": 80, "UI": 70, "Voice": 90}  # percent, steps of 10
static var bindings := {}  # "<action>" -> {"key": physical keycode} and/or {"pad": {"b": button} | {"a": axis, "v": sign}}
static var layout := 0  # LAYOUTS: the keyboard layout the bindings started from (issue #192)

## Set by the mission scene so battle speed only ever touches fights (the Command clock and town
## run on real time). slowed = the quick menu has time crawling at 10%.
static var in_battle := false
static var slowed := false

static var _loaded := false
static var _defaults := {}  # action -> {"key": ..., "pad": ...} as Controls first defined them


# ---------------------------------------------------------------- load / save

static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	battle_speed_i = clampi(int(cfg.get_value("options", "battle_speed", battle_speed_i)), 0, BATTLE_SPEEDS.size() - 1)
	difficulty = clampi(int(cfg.get_value("options", "difficulty", difficulty)), 0, DIFFICULTIES.size() - 1)
	shake_i = clampi(int(cfg.get_value("options", "screen_shake", shake_i)), 0, SHAKES.size() - 1)
	rumble_i = clampi(int(cfg.get_value("options", "rumble", rumble_i)), 0, Rumble.LEVELS.size() - 1)
	tips = bool(cfg.get_value("options", "tips", tips))
	for bus in BUSES:
		volumes[bus] = clampi(int(cfg.get_value("volume", bus, volumes[bus])), 0, 100)
	for f in FX:
		fx[f[0]] = clampi(int(cfg.get_value("fx", f[0], f[2])), 0, 100)
	var b = cfg.get_value("controls", "bindings", {})
	bindings = b if typeof(b) == TYPE_DICTIONARY else {}
	layout = clampi(int(cfg.get_value("controls", "layout", layout)), 0, LAYOUTS.size() - 1)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # keep what else lives there (Dialogue's text speed)
	cfg.set_value("options", "battle_speed", battle_speed_i)
	cfg.set_value("options", "difficulty", difficulty)
	cfg.set_value("options", "screen_shake", shake_i)
	cfg.set_value("options", "rumble", rumble_i)
	cfg.set_value("options", "tips", tips)
	for bus in BUSES:
		cfg.set_value("volume", bus, volumes[bus])
	cfg.set_value("controls", "bindings", bindings)
	cfg.set_value("controls", "layout", layout)
	for f in FX:
		cfg.set_value("fx", f[0], fx_value(f[0]))
	cfg.save(PATH)


## Explainers and tips on? (Help screen and Options; per device, like the other options.)
static func tips_enabled() -> bool:
	load_settings()
	return tips


static func set_tips(on: bool) -> void:
	load_settings()
	tips = on
	save()


## A scene effect's slider, 0..100 (the default when the player never touched it).
static func fx_value(id: String) -> int:
	load_settings()
	if not fx.has(id):
		for f in FX:
			if f[0] == id:
				fx[id] = f[2]
	return int(fx.get(id, 0))


## The same as 0..1.
static func fxf(id: String) -> float:
	return fx_value(id) / 100.0


## Title screen calls this on start. Safe to call again.
static func apply_all() -> void:
	load_settings()
	apply_audio()
	apply_bindings()
	DisplaySettings.apply()  # window mode, size, vsync, frame cap, focus handling (issue #145)
	Access.apply()  # stick deadzone and the other accessibility options (issue #34)


# ---------------------------------------------------------------- battle speed and difficulty

static func battle_speed() -> float:
	load_settings()
	return BATTLE_SPEEDS[battle_speed_i]


static func battle_speed_name() -> String:
	return "%sx" % str(battle_speed()).trim_suffix(".0") if battle_speed() != 1.0 else Loc.t("1x (normal)")


## Puts Engine.time_scale where it belongs right now. slow = the quick menu's slow motion factor.
static func refresh_time_scale(slow := 0.1) -> void:
	if not in_battle:
		Engine.time_scale = 1.0
		return
	Engine.time_scale = battle_speed() * (slow if slowed else 1.0)


## Scales a hit by difficulty before armour and shields see it (Actor.take_hit).
static func difficulty_damage(target: Node, amount: int) -> int:
	load_settings()
	if amount <= 0:
		return amount
	var m: Array = DIFFICULTY_MULT[difficulty]
	if target is Hero:  # the difficulty, then the damage-taken assist (issue #192)
		return Assists.hero_damage(amount if difficulty == 1 else maxi(1, roundi(amount * float(m[0]))))
	if difficulty == 1:
		return amount
	if target is Enemy:
		return maxi(1, roundi(amount * float(m[1])))
	return amount


# ---------------------------------------------------------------- screen shake

static func shake_scale() -> float:
	load_settings()
	return SHAKE_MULT[shake_i]


# ---------------------------------------------------------------- volume

## Makes sure the Music and SFX buses exist (children of Master) and sets every bus's volume.
static func apply_audio() -> void:
	load_settings()
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
		var v: int = volumes[bus]
		AudioServer.set_bus_mute(idx, v <= 0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v / 100.0, 0.0001)))


# ---------------------------------------------------------------- control remapping

## Remembers the bindings Controls defined, then lays the saved ones on top.
static func apply_bindings() -> void:
	load_settings()
	DialogueLog.ensure_action()  # so the log key can be rebound before any conversation made it
	if _defaults.is_empty():
		for a in REMAPPABLE:
			var id: String = a[0]
			if InputMap.has_action(id):
				_defaults[id] = {"key": _primary_key(id), "pad": _primary_pad(id)}
	for a in REMAPPABLE:
		var id: String = a[0]
		var d: Dictionary = _defaults.get(id, {})
		var b: Dictionary = bindings.get(id, {})
		# Untouched actions keep their events in Controls' order (the prompts show the first one).
		var key := int(b.get("key", d.get("key", -1)))
		if b.has("key") or _primary_key(id) != key:
			_set_key(id, key)
		var pad: Dictionary = b.get("pad", d.get("pad", {}))
		if b.has("pad") or _primary_pad(id) != pad:
			_set_pad(id, pad)


static func reset_bindings() -> void:
	bindings = {}
	layout = 0
	apply_bindings()
	save()


## Starts the bindings over from a keyboard layout (LAYOUTS). Gamepad bindings are kept.
static func apply_layout(i: int) -> void:
	load_settings()
	layout = clampi(i, 0, LAYOUTS.size() - 1)
	for id in bindings.keys():
		(bindings[id] as Dictionary).erase("key")
	apply_bindings()  # every key back to its default first
	var keys: Dictionary = LAYOUT_KEYS[layout]
	for id in keys:
		if InputMap.has_action(id):
			_store(id, "key", int(keys[id]))
			_set_key(id, int(keys[id]))
	save()


## Can a and b be pressed in the same place, so that one key for both would do two things at once?
## Moving and Attack are used in town and in missions; mission keys and town/table keys never meet;
## menu keys only clash with other menu keys (Confirm shares J with Attack on purpose).
static func clash(a: String, b: String) -> bool:
	var ga := group_of(a)
	var gb := group_of(b)
	if ga == gb:
		return true
	if ga == "menu" or gb == "menu":
		return false
	return ga in ["move", "hero"] or gb in ["move", "hero"]


static func group_of(id: String) -> String:
	return GROUPS.get(id, "manage")


## The heading a row of the Controls page starts, or "" (the first action of each group in REMAPPABLE).
static func group_title(id: String) -> String:
	var g := group_of(id)
	g = "move" if g in ["hero", "field"] else g
	for a in REMAPPABLE:
		var other: String = a[0]
		if not InputMap.has_action(other):
			continue
		var og := group_of(other)
		og = "move" if og in ["hero", "field"] else og
		if og == g:
			return Loc.t(GROUP_TITLES[g]) if other == id else ""
	return ""


static func action_label(id: String) -> String:
	for a in REMAPPABLE:
		if a[0] == id:
			return a[1]
	return id


## Binds a key (physical keycode) to an action. If another rebindable action that can be pressed in the
## same place (clash) already uses that key as its main key, the two swap so nothing ends up with two
## jobs. Returns the swapped action.
static func bind_key(id: String, keycode: int) -> String:
	var swapped := ""
	var old := _primary_key(id)
	for a in REMAPPABLE:
		var other: String = a[0]
		if other != id and clash(id, other) and _primary_key(other) == keycode:
			_store(other, "key", old)
			_set_key(other, old)
			swapped = other
	_store(id, "key", keycode)
	_set_key(id, keycode)
	save()
	return swapped


## Same for a gamepad button ({"b": index}) or trigger/stick direction ({"a": axis, "v": -1|1}).
static func bind_pad(id: String, pad: Dictionary) -> String:
	var swapped := ""
	var old := _primary_pad(id)
	for a in REMAPPABLE:
		var other: String = a[0]
		if other != id and clash(id, other) and _primary_pad(other) == pad:
			_store(other, "pad", old)
			_set_pad(other, old)
			swapped = other
	_store(id, "pad", pad)
	_set_pad(id, pad)
	save()
	return swapped


static func key_name(id: String) -> String:
	var k := _primary_key(id)
	return "-" if k < 0 else Prompts.key_label(k)


static func pad_name(id: String) -> String:
	return pad_text(_primary_pad(id))


const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_GUIDE: "Home",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}


static func pad_text(pad: Dictionary) -> String:
	if pad.has("b"):
		return Loc.t(PAD_BUTTONS.get(int(pad["b"]), Loc.t("Button %d") % int(pad["b"])))
	if pad.has("a"):
		var ax := int(pad["a"])
		var neg: bool = float(pad.get("v", 1.0)) < 0.0
		match ax:
			JOY_AXIS_TRIGGER_LEFT: return Loc.t("LT")
			JOY_AXIS_TRIGGER_RIGHT: return Loc.t("RT")
			JOY_AXIS_LEFT_X: return Loc.t("L stick left") if neg else Loc.t("L stick right")
			JOY_AXIS_LEFT_Y: return Loc.t("L stick up") if neg else Loc.t("L stick down")
			JOY_AXIS_RIGHT_X: return Loc.t("R stick left") if neg else Loc.t("R stick right")
			JOY_AXIS_RIGHT_Y: return Loc.t("R stick up") if neg else Loc.t("R stick down")
		return Loc.t("Axis %d") % ax
	return "-"


static func _store(id: String, kind: String, value) -> void:
	var b: Dictionary = bindings.get(id, {})
	b[kind] = value
	bindings[id] = b


## Godot's own ui_* keys carry a keycode, ours a physical keycode.
static func _code(ev: InputEventKey) -> int:
	return int(ev.physical_keycode) if ev.physical_keycode != 0 else int(ev.keycode)


static func _locked_key(id: String, ev: InputEvent) -> bool:
	return ev is InputEventKey and _code(ev) in LOCKED_KEYS.get(id, [])


static func _locked_pad(id: String, ev: InputEvent) -> bool:
	if ev is InputEventJoypadButton:
		return int(ev.button_index) in LOCKED_PAD.get(id, [])
	# The menu directions keep the left stick as well as the d-pad.
	return ev is InputEventJoypadMotion and id in ["ui_up", "ui_down", "ui_left", "ui_right"] \
		and int(ev.axis) in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]


## The key the Controls page shows and a rebind replaces: the first one that is not a locked fallback.
static func _primary_key(id: String) -> int:
	if not InputMap.has_action(id):
		return -1
	for ev in InputMap.action_get_events(id):
		if ev is InputEventKey and not _locked_key(id, ev):
			return _code(ev)
	return -1


static func _primary_pad(id: String) -> Dictionary:
	if not InputMap.has_action(id):
		return {}
	for ev in InputMap.action_get_events(id):
		if _locked_pad(id, ev):
			continue
		if ev is InputEventJoypadButton:
			return {"b": int(ev.button_index)}
		if ev is InputEventJoypadMotion:
			return {"a": int(ev.axis), "v": signf(ev.axis_value)}
	return {}


## The locked fallback keys of an action as text ("Up", "Enter"): shown beside the binding.
static func locked_text(id: String) -> String:
	var names := []
	for k in LOCKED_KEYS.get(id, []):
		if k != KEY_KP_ENTER:
			names.append(Prompts.key_label(k))
	return " / ".join(names)


## The same for the locked gamepad fallback ("D-pad up", "A").
static func locked_pad_text(id: String) -> String:
	var names := []
	for b in LOCKED_PAD.get(id, []):
		names.append(pad_text({"b": b}))
	return " / ".join(names)


## Replaces the action's first key that is not a locked fallback (alternates like the arrow keys stay).
## keycode -1 takes the key away (it went to another action in a swap and nothing came back).
static func _set_key(id: String, keycode: int) -> void:
	if not InputMap.has_action(id):
		return
	var events := InputMap.action_get_events(id)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	for i in events.size():
		if events[i] is InputEventKey and not _locked_key(id, events[i]):
			InputMap.action_erase_event(id, events[i])
			break
	if keycode < 0 or keycode in LOCKED_KEYS.get(id, []):
		return  # binding the fallback itself: it is already there
	InputMap.action_add_event(id, ev)
	_move_key_first(id, ev)


## Replaces the action's first gamepad input (button or axis) that is not a locked fallback, keeping the rest.
static func _set_pad(id: String, pad: Dictionary) -> void:
	if not InputMap.has_action(id):
		return
	for ev in InputMap.action_get_events(id):
		if (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) and not _locked_pad(id, ev):
			InputMap.action_erase_event(id, ev)
			break
	if pad.is_empty() or (pad.has("b") and int(pad["b"]) in LOCKED_PAD.get(id, [])):
		return
	var nev: InputEvent
	if pad.has("b"):
		var jb := InputEventJoypadButton.new()
		jb.button_index = int(pad["b"]) as JoyButton
		nev = jb
	else:
		var jm := InputEventJoypadMotion.new()
		jm.axis = int(pad["a"]) as JoyAxis
		jm.axis_value = float(pad.get("v", 1.0))
		nev = jm
	_put_first(id, nev)


## InputMap only appends, so rebuild the list with the new key in front (it is the one we show).
static func _move_key_first(id: String, ev: InputEvent) -> void:
	_put_first(id, ev)


static func _put_first(id: String, ev: InputEvent) -> void:
	var rest := InputMap.action_get_events(id).filter(func(e): return e != ev)
	InputMap.action_erase_events(id)
	InputMap.action_add_event(id, ev)
	for e in rest:
		InputMap.action_add_event(id, e)
