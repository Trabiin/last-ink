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
const BUSES := ["Master", "Music", "SFX"]

## Gameplay actions the player may rebind. Pause and the menu keys stay fixed so nobody can lock
## themselves out of the options screen.
const REMAPPABLE := [
	["move_up", "Move up"], ["move_down", "Move down"], ["move_left", "Move left"], ["move_right", "Move right"],
	["attack", "Attack / charge tech"], ["swap", "Swap hero"], ["quick_menu", "Quick menu"],
	["ability_1", "Ability 1"], ["ability_2", "Ability 2"], ["ability_3", "Ability 3"], ["ability_4", "Ability 4"],
	["alert_go", "Go to alert / goal"],  # only if that action exists (issue #22)
	["journal", "Journal"],  # quest log and codex (issue #114)
	["armory", "Forge & Market"],  # issue #112
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
static var tips := true  # first-visit explainers and first-time tips (issue #115); the story's unlocks always play
static var volumes := {"Master": 80, "Music": 70, "SFX": 80}  # percent, steps of 10
static var bindings := {}  # "<action>" -> {"key": physical keycode} and/or {"pad": {"b": button} | {"a": axis, "v": sign}}

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
	tips = bool(cfg.get_value("options", "tips", tips))
	for bus in BUSES:
		volumes[bus] = clampi(int(cfg.get_value("volume", bus, volumes[bus])), 0, 100)
	for f in FX:
		fx[f[0]] = clampi(int(cfg.get_value("fx", f[0], f[2])), 0, 100)
	var b = cfg.get_value("controls", "bindings", {})
	bindings = b if typeof(b) == TYPE_DICTIONARY else {}


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # keep what else lives there (Dialogue's text speed)
	cfg.set_value("options", "battle_speed", battle_speed_i)
	cfg.set_value("options", "difficulty", difficulty)
	cfg.set_value("options", "screen_shake", shake_i)
	cfg.set_value("options", "tips", tips)
	for bus in BUSES:
		cfg.set_value("volume", bus, volumes[bus])
	cfg.set_value("controls", "bindings", bindings)
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
	if difficulty == 1 or amount <= 0:
		return amount
	var m: Array = DIFFICULTY_MULT[difficulty]
	if target is Hero:
		return maxi(1, roundi(amount * float(m[0])))
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
	if _defaults.is_empty():
		for a in REMAPPABLE:
			var id: String = a[0]
			if InputMap.has_action(id):
				_defaults[id] = {"key": _primary_key(id), "pad": _primary_pad(id)}
	for a in REMAPPABLE:
		var id: String = a[0]
		var d: Dictionary = _defaults.get(id, {})
		var b: Dictionary = bindings.get(id, {})
		_set_key(id, int(b.get("key", d.get("key", -1))))
		_set_pad(id, b.get("pad", d.get("pad", {})))


static func reset_bindings() -> void:
	bindings = {}
	apply_bindings()
	save()


static func action_label(id: String) -> String:
	for a in REMAPPABLE:
		if a[0] == id:
			return a[1]
	return id


## Binds a key (physical keycode) to an action. If another rebindable action already uses that
## key as its main key, the two swap so nothing ends up with two jobs. Returns the swapped action.
static func bind_key(id: String, keycode: int) -> String:
	var swapped := ""
	var old := _primary_key(id)
	for a in REMAPPABLE:
		var other: String = a[0]
		if other != id and _primary_key(other) == keycode:
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
		if other != id and _primary_pad(other) == pad:
			_store(other, "pad", old)
			_set_pad(other, old)
			swapped = other
	_store(id, "pad", pad)
	_set_pad(id, pad)
	save()
	return swapped


static func key_name(id: String) -> String:
	var k := _primary_key(id)
	return "-" if k < 0 else OS.get_keycode_string(k)


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


static func _primary_key(id: String) -> int:
	if not InputMap.has_action(id):
		return -1
	for ev in InputMap.action_get_events(id):
		if ev is InputEventKey:
			return int(ev.physical_keycode)
	return -1


static func _primary_pad(id: String) -> Dictionary:
	if not InputMap.has_action(id):
		return {}
	for ev in InputMap.action_get_events(id):
		if ev is InputEventJoypadButton:
			return {"b": int(ev.button_index)}
		if ev is InputEventJoypadMotion:
			return {"a": int(ev.axis), "v": signf(ev.axis_value)}
	return {}


## Replaces the action's first key (alternates like the arrow keys stay).
static func _set_key(id: String, keycode: int) -> void:
	if keycode < 0 or not InputMap.has_action(id):
		return
	var events := InputMap.action_get_events(id)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	for i in events.size():
		if events[i] is InputEventKey:
			InputMap.action_erase_event(id, events[i])
			break
	InputMap.action_add_event(id, ev)
	_move_key_first(id, ev)


## Replaces the action's first gamepad input (button or axis), keeping the rest.
static func _set_pad(id: String, pad: Dictionary) -> void:
	if pad.is_empty() or not InputMap.has_action(id):
		return
	for ev in InputMap.action_get_events(id):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			InputMap.action_erase_event(id, ev)
			break
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
