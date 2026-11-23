class_name OptionsView
extends Control
## The options screen (issue #14). Opened from the title screen, every pause menu and the quick
## menu's Options tab with OptionsView.popup(scene). Values are kept by Settings and saved as soon
## as they change, so there is no Apply button.
##
## Keyboard: Up/Down pick a row, Left/Right change it, J/Enter also steps it (or opens Controls),
##   X/Esc goes back. Gamepad: d-pad/stick, A, B. Mouse/touch: tap the < > arrows or a row.
## Controls page: pick an action, then press the new key or gamepad button (Esc or Start cancels).

signal closed

const GOLD := Color("ffd166")
const TEXT := Color(0.92, 0.9, 0.86)
const DIM := Color(0.55, 0.55, 0.58)
const SOFT := Color(0.68, 0.66, 0.64)
const GOOD := Color("9fe07a")
const PANEL := Color(0.06, 0.05, 0.09, 0.98)
const W := 440.0
const ROW_H := 22.0
const ROW_H_CONTROLS := 17.0  # the Controls page has more rows

var page := "main"  # "main", "controls", "fx", "display", "access", "assists" (issue #192) or "first" (the first-start page, issue #34)
var sel := 0
var listening := ""  # action id waiting for a new key/button
var note := ""
var note_t := 0.0
var _listen_frame := -1
var _opened_frame := -1
var _t := 0.0
var _rows: Array = []  # {"id", "label", "value", "detail", "kind": "cycle"|"slider"|"open"|"bind"|"button"|"header"}
var _row_rects: Array = []
var _left_rects: Array = []
var _right_rects: Array = []
var _panel := Rect2()
var _first_row := 0  # long pages at big text sizes scroll (issue #34): the first row shown


## Opens the options over whatever scene is running, on its own top layer. The returned view
## emits `closed` and frees itself when the player backs out.
static func popup(host: Node, first_page := "main") -> OptionsView:
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var view := OptionsView.new()
	layer.add_child(view)
	view.closed.connect(layer.queue_free)
	view.open(first_page)
	return view


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(first_page := "main") -> void:
	Settings.load_settings()
	Access.load_settings()
	visible = true
	page = first_page
	sel = 0
	listening = ""
	_opened_frame = Engine.get_process_frames()
	_rebuild()


func close() -> void:
	visible = false
	listening = ""
	closed.emit()


# ---------------------------------------------------------------- rows

func _rebuild() -> void:
	_rows = []
	if page == "main":
		_rows.append({"id": "battle_speed", "kind": "cycle", "label": tr("Battle speed"), "value": Settings.battle_speed_name(),
			"detail": tr("How fast fights run. The Command clock is not affected.")})
		_rows.append({"id": "difficulty", "kind": "cycle", "label": tr("Difficulty"), "value": Loc.t(Settings.DIFFICULTIES[Settings.difficulty]),
			"detail": Loc.t(Settings.DIFFICULTY_INFO[Settings.difficulty]) + tr("  Change it any time.")})
		_rows.append({"id": "assists_page", "kind": "open", "label": tr("Assists"), "value": tr("some on") if Assists.any_on() else tr("damage, enemy speed, skipping"),
			"detail": tr("Take less damage, slow enemies down, heal between fights, skip story fights, calm the Blank.")})
		_rows.append({"id": "text_speed", "kind": "cycle", "label": tr("Text speed"), "value": Dialogue.speed_name(),
			"detail": tr("Typewriter speed in conversations%s.") % ((tr(" (%s changes it there too)") % Prompts.key("swap")) if Prompts.key("swap") != "" else "")})
		_rows.append({"id": "shake", "kind": "cycle", "label": tr("Screen shake"), "value": Loc.t(Settings.SHAKES[Settings.shake_i]),
			"detail": tr("Camera shake on heavy hits and techs.")})
		if Loc.languages().size() > 1:  # issue #143: only once a translation ships
			var chosen := _language_choice()
			_rows.append({"id": "language", "kind": "cycle", "label": tr("Language"), "value": Loc.language_name(chosen),
				"detail": tr("Applies the next time the game starts.") if chosen != Loc.language() else ""})
		_rows.append({"id": "tips", "kind": "cycle", "label": tr("Tips"), "value": tr("On") if Settings.tips_enabled() else tr("Off"),
			"detail": tr("The cast explains each screen the first time it opens and speaks up when something new happens. Everything is also under Help in the menu.")})
		for bus in Settings.BUSES:
			if bus == "Voice" and not _has_voice():
				continue  # no recorded speech yet: nothing for the slider to change
			var label: String = {"Master": tr("Master volume"), "Music": tr("Music volume"), "SFX": tr("Sound effects volume"),
				"UI": tr("Menu sounds volume"), "Voice": tr("Voice volume")}[bus]
			_rows.append({"id": "vol:" + bus, "kind": "slider", "label": label, "value": "%d%%" % Settings.volumes[bus],
				"level": Settings.volumes[bus], "detail": ""})
		_rows.append({"id": "access_page", "kind": "open", "label": tr("Accessibility"), "value": tr("text, font, flashing, captions"),
			"detail": tr("Bigger text, a plainer font, calmer effects, danger and map markers, captions, less camera motion, toggle instead of hold, stick deadzone, dialogue log.")})
		_rows.append({"id": "controls", "kind": "open", "label": tr("Controls"), "value": tr("remap keys and buttons"),
			"detail": tr("Every key and gamepad button, menus included, and one-handed keyboard layouts.")})
		_rows.append({"id": "fx_page", "kind": "open", "label": tr("Visual effects"), "value": tr("shadows, clouds, mist, lamps"),
			"detail": ""})
		_rows.append({"id": "display_page", "kind": "open", "label": tr("Display"),
			"value": tr("window, size, vsync, frame cap") if DisplaySettings.is_desktop() else tr("fullscreen, scaling"),
			"detail": ""})
		if DisplaySettings.is_desktop():  # issue #145
			_rows.append({"id": "save_folder", "kind": Loc.t("open"), "label": tr("Save folder"), "value": "open",
				"detail": tr("Saves and settings live in %s") % _short_path(ProjectSettings.globalize_path("user://"))})
		_rows.append({"id": "back", "kind": "button", "label": tr("Back"), "value": "", "detail": ""})
	elif page == "display":
		_display_rows()
	elif page == "access":
		_access_rows(false)
	elif page == "assists":
		_assist_rows()
	elif page == "first":
		_access_rows(true)
	elif page == "fx":
		for f in Settings.FX:
			var v := Settings.fx_value(f[0])
			_rows.append({"id": "fx:" + f[0], "kind": "slider", "label": f[1], "value": tr("Off") if v == 0 else "%d%%" % v,
				"level": v, "detail": f[3]})
		_rows.append({"id": "fx_reset", "kind": "button", "label": tr("Reset effects"), "value": "", "detail": ""})
		_rows.append({"id": "fx_back", "kind": "button", "label": tr("Back"), "value": "", "detail": ""})
	else:
		_rows.append({"id": "layout", "kind": "cycle", "label": tr("Keyboard layout"), "value": Loc.t(Settings.LAYOUTS[Settings.layout]),
			"detail": Loc.t(Settings.LAYOUT_INFO[Settings.layout])})
		for a in Settings.REMAPPABLE:
			var id: String = a[0]
			if not InputMap.has_action(id):
				continue
			var head := Settings.group_title(id)
			if head != "":
				_rows.append({"id": "head:" + id, "kind": "header", "label": head})
			var key := Settings.key_name(id)
			var locked := Settings.locked_text(id)
			if locked != "":
				key = locked if key == "-" else "%s, %s" % [key, locked]
			var pad := Settings.pad_name(id)
			var locked_pad := Settings.locked_pad_text(id)
			if locked_pad != "":
				pad = locked_pad if pad == "-" else "%s, %s" % [pad, locked_pad]
			_rows.append({"id": id, "kind": "bind", "label": Loc.t(a[1]), "key": key, "pad": pad,
				"detail": tr("%s always works here too, so you can't lock yourself out.") % (" / ".join([locked, locked_pad])) if locked != "" else ""})
		_rows.append({"id": "reset", "kind": "button", "label": tr("Reset to defaults"), "value": "", "detail": ""})
		_rows.append({"id": "controls_back", "kind": "button", "label": tr("Back"), "value": "", "detail": ""})
	sel = clampi(sel, 0, _rows.size() - 1)
	if _rows[sel]["kind"] == "header":
		_move_sel(1)


## The Assists page (issue #192): what the fight asks of you, each on its own switch, next to difficulty.
func _assist_rows() -> void:
	var S := Assists
	S.load_settings()
	_rows.append({"id": "difficulty", "kind": "cycle", "label": tr("Difficulty"), "value": Loc.t(Settings.DIFFICULTIES[Settings.difficulty]),
		"detail": Loc.t(Settings.DIFFICULTY_INFO[Settings.difficulty])})
	_rows.append({"id": "as:damage", "kind": "cycle", "label": tr("Damage taken"), "value": "%d%%" % S.DAMAGE[S.damage_i],
		"detail": tr("How much damage your party takes, on top of the difficulty.")})
	_rows.append({"id": "as:pace", "kind": "cycle", "label": tr("Enemy speed"), "value": Loc.t(S.PACE_NAMES[S.pace_i]),
		"detail": tr("Enemies move, wind up and attack at %d%% speed. Your party is unaffected.") % roundi(S.PACE[S.pace_i] * 100.0)})
	_rows.append({"id": "as:recover", "kind": "cycle", "label": tr("Heal between fights"), "value": tr("On") if S.recover else tr("Off"),
		"detail": tr("A few seconds with no enemy near and your party's health fills back up.")})
	_rows.append({"id": "as:skip", "kind": "cycle", "label": tr("Skip story fights"), "value": tr("On") if S.skip_fights else tr("Off"),
		"detail": tr("Story missions get Skip this fight in the pause menu. Their conversations still play and the rewards are the same.")})
	_rows.append({"id": "as:blank", "kind": "cycle", "label": tr("Blank pressure"), "value": Loc.t(S.BLANK[S.blank_i]),
		"detail": Loc.t(S.BLANK_INFO[S.blank_i]) + tr(" On the Command Table.")})
	_rows.append({"id": "as:reset", "kind": "button", "label": tr("Reset assists"), "value": "",
		"detail": tr("Assists never lock anything: every ending, reward and scene stays open.")})
	_rows.append({"id": "assists_back", "kind": "button", "label": tr("Back"), "value": "",
		"detail": tr("Assists never lock anything: every ending, reward and scene stays open.")})


## Moves the highlight by dir, over the Controls page's headings.
func _move_sel(dir: int) -> void:
	for i in _rows.size():
		sel = posmod(sel + dir, _rows.size())
		if _rows[sel]["kind"] != "header":
			return


func _has_voice() -> bool:
	var a := get_node_or_null("/root/Audio")
	return a != null and a.has_method("has_voice") and a.has_voice()


## The Accessibility page (issue #34), and the short version the title screen shows the first time the
## game starts (first = true): the options that matter before the prologue, then Start.
func _access_rows(first: bool) -> void:
	var A := Access
	A.load_settings()
	_rows.append({"id": "a:text", "kind": "cycle", "label": tr("Text size"), "value": Loc.t(A.TEXT_SIZES[A.text_size]),
		"detail": Loc.t(A.TEXT_INFO[A.text_size])})
	_rows.append({"id": "a:font", "kind": "cycle", "label": tr("Font"), "value": tr("Readable") if A.readable_font else tr("Pixel"),
		"detail": Loc.t(A.FONT_INFO[1 if A.readable_font else 0])})
	_rows.append({"id": "a:flash", "kind": "cycle", "label": tr("Reduce flashing"), "value": tr("On") if A.reduce_flashing else tr("Off"),
		"detail": tr("Softens hit flashes, blinking, bright bursts and the Blank's flicker.") if A.reduce_flashing
			else tr("On: hit flashes, blinking tells, bright bursts and the Blank's flicker are softened or held still.")})
	if first:
		_rows.append({"id": "difficulty", "kind": "cycle", "label": tr("Difficulty"), "value": Loc.t(Settings.DIFFICULTIES[Settings.difficulty]),
			"detail": Loc.t(Settings.DIFFICULTY_INFO[Settings.difficulty]) + tr("  Change it any time.")})
	_rows.append({"id": "a:danger", "kind": "cycle", "label": tr("Danger markers"), "value": tr("Patterned") if A.danger_patterns else tr("Colour only"),
		"detail": tr("Where an attack will land is striped and outlined, and wind-ups show a warning sign, so nothing relies on red alone.") if A.danger_patterns
			else tr("Danger zones are a red wash only.")})
	if not first:
		_rows.append({"id": "a:map", "kind": "cycle", "label": tr("Map markings"), "value": tr("Shapes and numbers") if A.map_symbols else tr("Colour only"),
			"detail": tr("On the Command Table every owner has a shape, each province shows its Fray as a number and Unravelling land is hatched.") if A.map_symbols
				else tr("Owners and Fray show as colours on the map only.")})
	_rows.append({"id": "a:captions", "kind": "cycle", "label": tr("Captions"), "value": tr("On") if A.captions else tr("Off"),
		"detail": tr("Important sounds show as text: warning bells, a hero falling, the Blank's hum (with an arrow to where it comes from).")})
	_rows.append({"id": "a:tech", "kind": "cycle", "label": tr("Charged techs"), "value": Loc.t(A.TECH_MODES[A.tech_mode]),
		"detail": Loc.t(A.TECH_INFO[A.tech_mode])})
	if first:
		_rows.append({"id": "start", "kind": "button", "label": tr("Start"), "value": "",
			"detail": tr("Everything here and more is under Options > Accessibility, any time.")})
		return
	_rows.append({"id": "a:hold", "kind": "cycle", "label": tr("Hold to attack"), "value": tr("On") if A.hold_attack else tr("Off"),
		"detail": tr("Keep Attack held to swing again each time the gauge fills.")})
	var dz_level := roundi(100.0 * (A.deadzone - A.DEADZONE_MIN) / float(A.DEADZONE_MAX - A.DEADZONE_MIN))
	_rows.append({"id": "a:deadzone", "kind": "slider", "label": tr("Stick deadzone"), "value": "%d%%" % A.deadzone, "level": dz_level,
		"detail": tr("How far the stick must tilt before you move. Raise it if a worn stick drifts; lower it for small movements.")})
	_rows.append({"id": "a:auto", "kind": "cycle", "label": tr("Auto-advance dialogue"), "value": Loc.t(A.AUTO_ADVANCE[A.auto_advance]),
		"detail": tr("Conversations move on by themselves after each line. Any button still moves on at once.")})
	_rows.append({"id": "text_speed", "kind": "cycle", "label": tr("Text speed"), "value": Dialogue.speed_name(),
		"detail": tr("Typewriter speed in conversations.")})
	_rows.append({"id": "shake", "kind": "cycle", "label": tr("Screen shake"), "value": Loc.t(Settings.SHAKES[Settings.shake_i]),
		"detail": tr("Camera shake on heavy hits and techs.")})
	_rows.append({"id": "a:motion", "kind": "cycle", "label": tr("Camera motion"), "value": tr("Reduced") if A.reduce_motion else tr("Full"),
		"detail": tr("The camera sticks to your hero instead of gliding after them, and the map jumps instead of sweeping. The fog stops drifting.") if A.reduce_motion
			else tr("Reduced: the camera sticks to your hero, the map jumps instead of sweeping and the fog holds still.")})
	_rows.append({"id": "dialogue_log", "kind": "open", "label": tr("Dialogue log"), "value": tr("everything said so far"),
		"detail": tr("Also on %s while a conversation is open.") % Prompts.key("dialogue_log") if Prompts.key("dialogue_log") != "" else ""})
	_rows.append({"id": "a:reset", "kind": "button", "label": tr("Reset accessibility"), "value": "", "detail": ""})
	_rows.append({"id": "access_back", "kind": "button", "label": tr("Back"), "value": "", "detail": ""})


## The Display page (issue #145). Only what this platform can change.
func _display_rows() -> void:
	var D := DisplaySettings
	D.load_settings()
	var desk := D.is_desktop()
	_rows.append({"id": "d:mode", "kind": "cycle", "label": tr("Window mode") if desk else tr("Fullscreen"), "value": D.mode_name(),
		"detail": D.mode_info()})
	if desk:
		_rows.append({"id": "d:size", "kind": "cycle", "label": tr("Window size"), "value": D.size_name(),
			"detail": tr("Size of the window in windowed mode.") if D.mode == 0 else tr("Fullscreen uses the whole screen. Switch to Windowed to pick a size.")})
	_rows.append({"id": "d:scaling", "kind": "cycle", "label": tr("Scaling"), "value": Loc.t(D.SCALINGS[D.scaling]), "detail": Loc.t(D.SCALING_INFO[D.scaling])})
	if desk:
		_rows.append({"id": "d:vsync", "kind": "cycle", "label": tr("VSync"), "value": tr("On") if D.vsync else tr("Off"),
			"detail": tr("Matches the screen's refresh rate so the picture never tears. Off can feel snappier but may tear.")})
		_rows.append({"id": "d:fps", "kind": "cycle", "label": tr("Frame cap"), "value": D.fps_name(),
			"detail": tr("Limits frames per second to keep laptops cool and quiet. Off = as fast as the machine goes.")})
	_rows.append({"id": "d:background", "kind": "cycle", "label": tr("In the background"), "value": Loc.t(D.BACKGROUNDS[D.background]),
		"detail": Loc.t(D.BACKGROUND_INFO[D.background])})
	_rows.append({"id": "display_back", "kind": "button", "label": tr("Back"), "value": "", "detail": ""})


## A long folder path shortened for the footer (the home folder becomes ~).
func _short_path(p: String) -> String:
	var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	if home != "" and p.begins_with(home):
		p = "~" + p.substr(home.length())
	return p.trim_suffix("/")


## Left/right (step -1/+1) on a value row.
func _step(i: int, step: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	var id: String = _rows[i]["id"]
	if id.begins_with("d:"):
		DisplaySettings.step(id.substr(2), step)
		_rebuild()
		return
	if id.begins_with("a:"):
		_step_access(id.substr(2), step)
		_rebuild()
		return
	if id.begins_with("as:"):
		_step_assist(id.substr(3), step)
		_rebuild()
		return
	if id == "layout":
		Settings.apply_layout(clampi(Settings.layout + step, 0, Settings.LAYOUTS.size() - 1))
		_say(tr("Keyboard layout: %s") % Loc.t(Settings.LAYOUTS[Settings.layout]))
		_rebuild()
		return
	match id:
		"battle_speed":
			Settings.battle_speed_i = clampi(Settings.battle_speed_i + step, 0, Settings.BATTLE_SPEEDS.size() - 1)
			Settings.refresh_time_scale()
		"difficulty":
			Settings.difficulty = clampi(Settings.difficulty + step, 0, Settings.DIFFICULTIES.size() - 1)
		"text_speed":
			_set_text_speed(clampi(Dialogue.speed_index() + step, 0, Dialogue.SPEEDS.size() - 1))
		"shake":
			Settings.shake_i = clampi(Settings.shake_i + step, 0, Settings.SHAKES.size() - 1)
		"tips":  # issue #115
			Settings.tips = step > 0
		"language":  # issue #143
			var langs := Loc.languages()
			Loc.choose(langs[posmod(langs.find(_language_choice()) + step, langs.size())])
			_rebuild()
			return
		_:
			if id.begins_with("vol:"):
				var bus := id.substr(4)
				Settings.volumes[bus] = clampi(int(Settings.volumes[bus]) + step * 10, 0, 100)
				Settings.apply_audio()
			elif id.begins_with("fx:"):
				var fid := id.substr(3)
				Settings.fx[fid] = clampi(Settings.fx_value(fid) + step * 10, 0, 100)
			else:
				return
	Settings.save()
	_rebuild()


func _step_access(what: String, step: int) -> void:
	var A := Access
	match what:
		"text":
			A.text_size = clampi(A.text_size + step, 0, A.TEXT_SIZES.size() - 1)
		"flash":
			A.reduce_flashing = step > 0
		"danger":
			A.danger_patterns = step < 0  # left = Patterned, right = Colour only, in the order shown
		"tech":
			A.tech_mode = clampi(A.tech_mode + step, 0, A.TECH_MODES.size() - 1)
		"hold":
			A.hold_attack = step > 0
		"deadzone":
			A.deadzone = clampi(A.deadzone + step * 5, A.DEADZONE_MIN, A.DEADZONE_MAX)
			A.apply_deadzone()
		"auto":
			A.auto_advance = clampi(A.auto_advance + step, 0, A.AUTO_ADVANCE.size() - 1)
		"font":
			A.readable_font = step > 0
			A.apply_font()
		"map":
			A.map_symbols = step < 0  # left = Shapes and numbers, right = Colour only, in the order shown
		"motion":
			A.reduce_motion = step > 0
		"captions":
			A.captions = step > 0
	A.save()


func _step_assist(what: String, step: int) -> void:
	var S := Assists
	match what:
		"damage":
			S.damage_i = clampi(S.damage_i + step, 0, S.DAMAGE.size() - 1)
		"pace":
			S.pace_i = clampi(S.pace_i + step, 0, S.PACE.size() - 1)
		"recover":
			S.recover = step > 0
		"skip":
			S.skip_fights = step > 0
		"blank":
			S.blank_i = clampi(S.blank_i + step, 0, S.BLANK.size() - 1)
	S.save()


## Text speed stays where Dialogue has always kept it (user://settings.cfg, [dialogue]).
func _set_text_speed(i: int) -> void:
	Dialogue._speed = i
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	cfg.set_value("dialogue", "text_speed", i)
	cfg.save(Settings.PATH)


## Accept on a row.
func _activate(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	sel = i
	var r: Dictionary = _rows[i]
	match r["kind"]:
		"cycle":
			# Step forward, wrapping round, so one button is enough on touch and gamepad.
			var before := _value_index(r["id"])
			_step(i, 1)
			if _value_index(r["id"]) == before:
				_step(i, -999)
		"slider":
			_step(i, 1)
			if int(_rows[i].get("level", 0)) == int(r.get("level", 0)):
				_step(i, -10)
		"open":
			if r["id"] == "save_folder":
				_open_save_folder()
				return
			if r["id"] == "dialogue_log":
				DialogueLog.popup(get_parent())
				return
			page = {"fx_page": "fx", "display_page": "display", "access_page": "access", "assists_page": "assists"}.get(r["id"], "controls")
			sel = 0
			_rebuild()
		"bind":
			listening = r["id"]
			_listen_frame = Engine.get_process_frames()
		"button":
			match r["id"]:
				"back":
					close()
				"controls_back", "fx_back", "display_back", "access_back", "assists_back":
					_back()
				"as:reset":
					Assists.reset()
					_say(tr("Assists are back to the defaults."))
					_rebuild()
				"start":
					Access.finish_first_boot()
					close()
				"a:reset":
					Access.reset()
					_say(tr("Accessibility options are back to the defaults."))
					_rebuild()
				"fx_reset":
					for f in Settings.FX:
						Settings.fx[f[0]] = f[2]
					Settings.save()
					_say(tr("Visual effects are back to the defaults."))
					_rebuild()
				"reset":
					Settings.reset_bindings()
					_say(tr("Controls are back to the defaults."))
					_rebuild()


func _value_index(id: String) -> int:
	var D := DisplaySettings
	match id:
		"d:mode": return D.mode
		"d:size": return D.size_i
		"d:scaling": return D.scaling
		"d:vsync": return 1 if D.vsync else 0
		"d:fps": return D.fps_i
		"d:background": return D.background
		"battle_speed": return Settings.battle_speed_i
		"difficulty": return Settings.difficulty
		"text_speed": return Dialogue.speed_index()
		"shake": return Settings.shake_i
		"tips": return 1 if Settings.tips_enabled() else 0
		"language": return Loc.languages().find(_language_choice())
		"a:text": return Access.text_size
		"a:flash": return 1 if Access.reduce_flashing else 0
		"a:danger": return 0 if Access.danger_patterns else 1
		"a:tech": return Access.tech_mode
		"a:hold": return 1 if Access.hold_attack else 0
		"a:auto": return Access.auto_advance
		"a:font": return 1 if Access.readable_font else 0
		"a:map": return 0 if Access.map_symbols else 1
		"a:motion": return 1 if Access.reduce_motion else 0
		"a:captions": return 1 if Access.captions else 0
		"as:damage": return Assists.damage_i
		"as:pace": return Assists.pace_i
		"as:recover": return 1 if Assists.recover else 0
		"as:skip": return 1 if Assists.skip_fights else 0
		"as:blank": return Assists.blank_i
		"layout": return Settings.layout
	return -1


## The language saved for the next start (Loc.language() is the one running now).
func _language_choice() -> String:
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)
	var code := str(cfg.get_value("options", "language", Loc.language()))
	return code if code in Loc.languages() else Loc.language()


func _back() -> void:
	if listening != "":
		listening = ""
	elif page == "first":
		_activate(_rows.size() - 1)  # backing out of the first-start page is the same as Start
	elif page != "main":
		var from: String = {"controls": "controls", "fx": "fx_page", "display": "display_page", "access": "access_page", "assists": "assists_page"}[page]
		page = "main"
		_rebuild()
		sel = maxi(0, _rows.map(func(r): return r["id"]).find(from))
	else:
		close()


## Opens the folder with the saves and settings in the system's file manager (issue #145).
func _open_save_folder() -> void:
	var path := ProjectSettings.globalize_path("user://")
	if OS.shell_show_in_file_manager(path) != OK and OS.shell_open(path) != OK:
		_say(tr("Could not open it. The saves are in ") + _short_path(path))
		return
	_say(tr("Opened ") + _short_path(path))


func _say(s: String) -> void:
	note = s
	note_t = 3.0


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if listening != "":
		_listen(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position) and _rows[i]["kind"] != "header":
				sel = i
		return
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tap:
		_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_move_sel(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)  # the wheel scrolls long pages (issue #192)
	elif event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventScreenDrag:
		pass
	elif Engine.get_process_frames() == _opened_frame:
		pass  # the press that opened us
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_back()
	elif event.is_action_pressed("ui_down", true):
		_move_sel(1)
	elif event.is_action_pressed("ui_up", true):
		_move_sel(-1)
	elif event.is_action_pressed("ui_left", true) or _key(event, KEY_A):
		_step(sel, -1)
	elif event.is_action_pressed("ui_right", true) or _key(event, KEY_D):
		_step(sel, 1)
	elif event.is_action_pressed("ui_accept"):
		_activate(sel)
	if is_inside_tree():
		get_viewport().set_input_as_handled()  # nothing reaches the menu or the game underneath


func _key(event: InputEvent, k: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == k


func _listen(event: InputEvent) -> void:
	if Engine.get_process_frames() == _listen_frame:
		return
	var id := listening
	var swapped := ""
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			listening = ""
			return
		swapped = Settings.bind_key(id, int(event.physical_keycode))
		_say("%s: %s" % [Settings.action_label(id), Settings.key_name(id)])
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_START:
			listening = ""
			return
		swapped = Settings.bind_pad(id, {"b": int(event.button_index)})
		_say("%s: %s" % [Settings.action_label(id), Settings.pad_name(id)])
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		swapped = Settings.bind_pad(id, {"a": int(event.axis), "v": signf(event.axis_value)})
		_say("%s: %s" % [Settings.action_label(id), Settings.pad_name(id)])
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		listening = ""  # a tap cancels
		return
	else:
		return
	if swapped != "":
		_say(tr("%s  (swapped with %s)") % [note, Settings.action_label(swapped)])
	listening = ""
	_rebuild()


func _tap(p: Vector2) -> void:
	for i in _row_rects.size():
		if i < _left_rects.size() and (_left_rects[i] as Rect2).has_point(p):
			sel = i
			_step(i, -1)
			return
		if i < _right_rects.size() and (_right_rects[i] as Rect2).has_point(p):
			sel = i
			_step(i, 1)
			return
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(p):
			if _rows[i]["kind"] != "header":
				_activate(i)
			return
	if not _panel.grow(6).has_point(p):
		_back()


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if not visible:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	note_t = maxf(note_t - real, 0.0)
	queue_redraw()


func _str(font: Font, pos: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)


func _str_w(font: Font, s: String, fsize: int) -> float:
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x


func _marker(x: float, y: float) -> void:
	var mx := x + sin(_t * 5.0) * 1.5
	draw_circle(Vector2(mx, y - 4.0), 3.0, GOLD)
	draw_colored_polygon(PackedVector2Array([Vector2(mx - 2.6, y - 5.5), Vector2(mx + 2.6, y - 5.5), Vector2(mx, y - 10.5)]), GOLD)


## A small arrow above or below the rows: more that way.
func _scroll_mark(at: Vector2, dir: float) -> void:
	draw_colored_polygon(PackedVector2Array([at + Vector2(-4, 0), at + Vector2(4, 0), at + Vector2(0, 3.0 * dir)]), SOFT)


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, 0.75))
	var w := minf(W * (1.0 + (Access.text_scale() - 1.0) * 0.6), vs.x - 16.0)
	var row_h := Access.px(ROW_H_CONTROLS if page == "controls" else ROW_H)
	var min_h := Access.px(ROW_H_CONTROLS)
	var foot := Access.px(50.0)  # two lines of explanation and the hint line
	row_h = maxf(min_h, minf(row_h, floorf((vs.y - 52.0 - foot) / maxf(_rows.size(), 1))))  # long pages squeeze to fit
	var fit := maxi(1, int(floorf((vs.y - 52.0 - foot) / row_h)))  # ...and scroll when squeezing is not enough
	var shown := mini(_rows.size(), fit)
	if sel < _first_row:
		_first_row = sel
	elif sel >= _first_row + shown:
		_first_row = sel - shown + 1
	_first_row = clampi(_first_row, 0, maxi(_rows.size() - shown, 0))
	var h := 40.0 + shown * row_h + foot
	var ty := row_h / 2.0 + Access.px(3.0)  # text baseline inside a row
	_panel = Rect2((vs.x - w) / 2.0, maxf(6.0, (vs.y - h) / 2.0), w, minf(h, vs.y - 12.0))
	draw_rect(_panel, PANEL)
	draw_rect(_panel, Color(1, 1, 1, 0.18), false, 1.0)
	var x0 := _panel.position.x + 24.0
	var x1 := _panel.end.x - 14.0
	_str(font, Vector2(x0 - 8, _panel.position.y + 22), {"main": tr("Options"), "controls": tr("Controls"), "fx": tr("Visual effects"), "display": tr("Display"),
		"access": tr("Accessibility"), "assists": tr("Assists"), "first": tr("Before you start")}[page], 16, Color("f3f1ea"))
	if page == "controls":
		_str(font, Vector2(x1 - Access.px(168.0), _panel.position.y + 22), tr("Keyboard"), 9, SOFT)
		_str(font, Vector2(x1 - Access.px(70.0), _panel.position.y + 22), tr("Gamepad"), 9, SOFT)

	_row_rects.clear()
	_left_rects.clear()
	_right_rects.clear()
	var y := _panel.position.y + 40.0
	if _first_row > 0:
		_scroll_mark(Vector2(_panel.get_center().x, y - 3.0), -1.0)
	if _first_row + shown < _rows.size():
		_scroll_mark(Vector2(_panel.get_center().x, y + shown * row_h + 1.0), 1.0)
	for i in _rows.size():
		if i < _first_row or i >= _first_row + shown:
			_row_rects.append(Rect2())  # off the page: nothing to tap
			_left_rects.append(Rect2())
			_right_rects.append(Rect2())
			continue
		var r: Dictionary = _rows[i]
		var rr := Rect2(_panel.position.x + 4, y, w - 8, row_h - 2)
		_row_rects.append(rr)
		if r["kind"] == "header":  # a heading on the Controls page: not a row you can pick
			_left_rects.append(Rect2())
			_right_rects.append(Rect2())
			_str(font, Vector2(x0 - 8, y + ty), str(r["label"]), 9, SOFT)
			draw_line(Vector2(x0 - 8, y + row_h - 3), Vector2(x1, y + row_h - 3), Color(1, 1, 1, 0.12), 1.0)
			y += row_h
			continue
		var on_row := i == sel
		if on_row:
			draw_rect(rr, Color(1, 1, 1, 0.06))
			_marker(x0 - 12.0, y + ty)
		var col := GOLD if on_row else TEXT
		_str(font, Vector2(x0, y + ty), str(r["label"]), 11, col)
		match r["kind"]:
			"cycle", "slider":
				var vx := x1 - Access.px(150.0)
				var lr := Rect2(vx - 4, y, 18, row_h - 2)
				var rgt := Rect2(x1 - 14, y, 18, row_h - 2)
				_left_rects.append(lr)
				_right_rects.append(rgt)
				_str(font, Vector2(vx, y + ty), "<", 11, col)
				_str(font, Vector2(x1 - 8, y + ty), ">", 11, col)
				if r["kind"] == "slider":
					var bar := Rect2(vx + 14, y + ty - 7, 92, 6)
					draw_rect(bar, Color(1, 1, 1, 0.12))
					draw_rect(Rect2(bar.position, Vector2(bar.size.x * float(r["level"]) / 100.0, bar.size.y)), col)
					_str(font, Vector2(vx + 110, y + ty), str(r["value"]), 9, col)
				else:
					var vs_text := str(r["value"])
					var tw := _str_w(font, vs_text, 10)
					_str(font, Vector2(vx + 70 - tw / 2.0, y + ty), vs_text, 10, col)
			"open":
				_left_rects.append(Rect2())
				_right_rects.append(Rect2())
				var t := str(r["value"]) + "  >"
				_str(font, Vector2(x1 - _str_w(font, t, 9), y + ty), t, 9, col if on_row else SOFT)
			"bind":
				_left_rects.append(Rect2())
				_right_rects.append(Rect2())
				var waiting: bool = listening == r["id"]
				var kcol := col
				if waiting:
					var blink := Color(GOOD, 0.55 + 0.45 * sin(_t * 8.0))
					_str(font, Vector2(x1 - Access.px(168.0), y + ty), tr("press a key or button..."), 9, blink)
				else:
					_str(font, Vector2(x1 - Access.px(168.0), y + ty), str(r["key"]), 10, kcol)
					_str(font, Vector2(x1 - Access.px(70.0), y + ty), str(r["pad"]), 10, kcol)
			_:
				_left_rects.append(Rect2())
				_right_rects.append(Rect2())
		y += row_h

	# Footer: the highlighted row's explanation, a result, or how to drive it.
	var fy := _panel.end.y - Access.px(32.0)
	var detail := ""
	if sel < _rows.size():
		detail = str(_rows[sel].get("detail", ""))
	if note_t > 0.0:
		_str(font, Vector2(x0 - 8, fy), note, 9, GOOD)
	elif listening != "":
		_str(font, Vector2(x0 - 8, fy), tr("Press the new key or gamepad input for %s.  Esc / Start: cancel.") % Settings.action_label(listening), 9, SOFT)
	elif detail != "":
		draw_multiline_string(font, Vector2(x0 - 8, fy), detail, HORIZONTAL_ALIGNMENT_LEFT, w - 32, Access.fs(9), 2, SOFT)
	var hint := tr("Up/Down: pick    Left/Right: change    X/B: back") if page != "controls" \
		else (tr("Left/Right: change layout    X/B: back") if sel < _rows.size() and _rows[sel]["kind"] == "cycle"
			else tr("J/A: rebind (keyboard key or gamepad input)    X/B: back"))
	_str(font, Vector2(x0 - 8, fy + Access.px(23.0)), hint, 8, DIM)
