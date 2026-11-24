extends Node
## Steam (autoload "SteamLink", issue #150, docs/STEAM.md). The only script that talks to GodotSteam.
##
## GodotSteam is a GDExtension that registers an engine singleton named "Steam". It is only in Steam
## builds (CI fetches it, tools/fetch_godotsteam.sh); web, itch.io and plain desktop builds don't have
## it, and then everything here is a quiet no-op. The singleton is looked up at run time and called by
## name, so this script compiles and runs the same with or without the extension. (The autoload can't
## be called "Steam": that is the extension's own name.)
##
## Steam starts only when all of these hold: the extension is loaded, the build isn't the web build,
## the command line has no --no-steam, and there is an app id (data/steam.json "app_id", or the
## SteamAppId that the Steam client sets when it launches the game). Running without the Steam client
## just logs one line and carries on.
##
##   SteamLink.active                 true once Steam started
##   SteamLink.api()                  the GodotSteam singleton (null without Steam), for other Steam calls
##   SteamLink.unlock(api_name)       achievement; stored to Steam at once
##   SteamLink.achieved()             achievement api names Steam says this account has
##   SteamLink.progress(api_name, n, max)   Steam's "12 / 25" progress pop-up
##   SteamLink.set_presence(state, vars)    Rich Presence, see data/steam.json "presence"
##   SteamLink.on_deck()              running on a Steam Deck
##   signal overlay_toggled(open)     the Steam overlay opened or closed (the game pauses, see _on_overlay)
##
## Tests swap in a fake singleton with use_api() (tests/test_steam.gd).

signal overlay_toggled(open: bool)
signal started

const DATA := "res://data/steam.json"
const SINGLETON := "Steam"
const PRESENCE_EVERY := 5.0  # seconds between looks at what the player is doing
const INIT_OK_EX := 0  # steamInitEx(): k_ESteamAPIInitResult_OK
const INIT_OK_OLD := 1  # steamInit() in older GodotSteam: 1 = started

var active := false
var status := "off"  # why Steam is or isn't running, for logs, bug reports and the tests
var _api: Object = null
var _data := {}
var _presence_t := 0.0
var _presence := {}  # last values sent, so unchanged presence isn't resent
var _paused_by_overlay := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # callbacks and the overlay pause must run while paused
	_data = _load_data()
	start()


func _load_data() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func app_id() -> int:
	var env := OS.get_environment("SteamAppId")
	if env.is_valid_int() and int(env) > 0:
		return int(env)
	return int(_data.get("app_id", 0))


## Starts Steam if it can (see the top of the file). Safe to call again: does nothing once active.
func start() -> bool:
	if active:
		return true
	if OS.has_feature("web"):
		status = "web build"  # no-tr: logs and Steam keys
		return false
	if "--no-steam" in OS.get_cmdline_args() or "--no-steam" in OS.get_cmdline_user_args():
		status = "turned off on the command line"  # no-tr: logs and Steam keys
		return false
	if not Engine.has_singleton(SINGLETON):
		status = "no GodotSteam in this build"  # no-tr: logs and Steam keys
		return false
	var id := app_id()
	if id <= 0:
		status = "no Steam app id yet (data/steam.json)"  # no-tr: logs and Steam keys
		return false
	_api = Engine.get_singleton(SINGLETON)
	OS.set_environment("SteamAppId", str(id))  # no-tr: env var; GodotSteam's documented way to pick the app without a steam_appid.txt
	OS.set_environment("SteamGameId", str(id))  # no-tr: logs and Steam keys
	var ok := false
	var why := ""
	if _api.has_method("steamInitEx"):
		var r = _api.call("steamInitEx")
		ok = typeof(r) == TYPE_DICTIONARY and int(r.get("status", -1)) == INIT_OK_EX
		why = str(r.get("verbal", r)) if typeof(r) == TYPE_DICTIONARY else str(r)
	elif _api.has_method("steamInit"):
		var r = _api.call("steamInit")
		ok = typeof(r) == TYPE_DICTIONARY and int(r.get("status", -1)) == INIT_OK_OLD
		why = str(r.get("verbal", r)) if typeof(r) == TYPE_DICTIONARY else str(r)
	if not ok:
		_api = null
		status = "Steam didn't start: %s" % why  # no-tr: log line; the client isn't running, or this account doesn't own the game
		print("Steam: %s" % status)
		return false
	_begin()
	return true


## Uses `fake` as the Steam singleton (tests). It must answer the same methods GodotSteam does.
func use_api(fake: Object) -> void:
	stop()
	_api = fake
	if fake != null:
		_begin()


func stop() -> void:
	if _api != null and _overlay_connected():
		_api.disconnect("overlay_toggled", _on_overlay_signal)
	if active and _api != null and _api.has_method("clearRichPresence"):
		_api.call("clearRichPresence")
	active = false
	_api = null
	_presence = {}
	status = "off"


func _begin() -> void:
	active = true
	status = "on (app %d)" % app_id() if app_id() > 0 else "on"  # no-tr: logs and Steam keys
	if _api.has_method("requestCurrentStats"):  # gone from newer Steamworks SDKs, which load stats by themselves
		_api.call("requestCurrentStats")
	if _api.has_signal("overlay_toggled") and not _overlay_connected():
		_api.connect("overlay_toggled", _on_overlay_signal)
	_presence = {}
	_presence_t = PRESENCE_EVERY  # send presence on the next frame
	print("Steam: %s" % status)
	started.emit()


func _overlay_connected() -> bool:
	return _api.has_signal("overlay_toggled") and _api.is_connected("overlay_toggled", _on_overlay_signal)


func api() -> Object:
	return _api if active else null


func _process(delta: float) -> void:
	if not active:
		return
	if _api.has_method("run_callbacks"):
		_api.call("run_callbacks")
	_presence_t += delta
	if _presence_t >= PRESENCE_EVERY:
		_presence_t = 0.0
		update_presence()


func on_deck() -> bool:
	if active and _api.has_method("isSteamRunningOnSteamDeck"):
		return bool(_api.call("isSteamRunningOnSteamDeck"))
	return OS.get_environment("SteamDeck") == "1"


# ---------------------------------------------------------------- achievements

func unlock(api_name: String) -> bool:
	if not active:
		return false
	_api.call("setAchievement", api_name)
	_api.call("storeStats")
	return true


## Achievement api names this account already has on Steam, out of `names`.
func achieved(names: Array) -> Array:
	var out := []
	if not active or not _api.has_method("getAchievement"):
		return out
	for n in names:
		var r = _api.call("getAchievement", str(n))
		if typeof(r) == TYPE_DICTIONARY and bool(r.get("achieved", false)):
			out.append(str(n))
	return out


## Steam's own "12 / 25" pop-up for a counting achievement (not the unlock itself).
func progress(api_name: String, current: int, max_value: int) -> void:
	if active and _api.has_method("indicateAchievementProgress") and current > 0 and current < max_value:
		_api.call("indicateAchievementProgress", api_name, current, max_value)


# ---------------------------------------------------------------- rich presence

## What the player is doing right now: [state, {var: value}]. state is a key of data/steam.json
## presence.states ("menu", "hub", "command", "mission", "boss").
func current_activity() -> Array:
	var tree := get_tree()
	var scene := tree.current_scene if tree else null
	var path := scene.scene_file_path if scene else ""
	var chapter := _chapter_key()
	if path == Saves.HUB_SCENE:
		return ["hub", {"chapter": chapter}]
	if path == Saves.COMMAND_SCENE:
		return ["command", {"chapter": chapter}]
	if path == Saves.GAME_SCENE:
		var m: Dictionary = Empire.active_mission if not Empire.active_mission.is_empty() else Missions.current()
		var boss := str(m.get("objective", {}).get("kind", "")) == "boss"
		var place := str(m.get("name", "")) if boss else str(Empire.territory().find(str(m.get("province", ""))).get("name", ""))
		if place == "":
			place = str(m.get("name", ""))
		return ["boss" if boss else "mission", {"chapter": chapter, "place": _plain(place)}]
	return ["menu", {}]


func _chapter_key() -> String:
	var id := str(Journal.current_chapter().get("id", ""))
	var known: Dictionary = _data.get("presence", {}).get("chapters", {})
	return id if known.has(id) else "prologue"


## Steam shows the place as typed: keep it short and on one line.
func _plain(s: String) -> String:
	s = s.replace("\n", " ").strip_edges()
	if s.begins_with("Boss: "):  # no-tr: the mission title prefix in data/missions.json
		s = s.substr(6)
	return s.left(60)


func update_presence() -> void:
	if not active:
		return
	var a := current_activity()
	set_presence(a[0], a[1])


## Sends Rich Presence: Steam shows "#Status_<state>" from the uploaded localization file
## (steam/rich_presence_english.vdf), filling %chapter% and %place% from vars.
func set_presence(state: String, vars: Dictionary) -> void:
	if not active:
		return
	var want := {"steam_display": "#Status_" + state}  # no-tr: logs and Steam keys
	for k in vars:
		want[k] = str(vars[k])
	want["status"] = presence_text(state, vars)  # plain text for Steam's "view game info" box
	if want == _presence:
		return
	if _api.has_method("clearRichPresence"):
		_api.call("clearRichPresence")
	for k in want:
		_api.call("setRichPresence", k, want[k])
	_presence = want


## The English presence line, as friends see it.
func presence_text(state: String, vars: Dictionary) -> String:
	var p: Dictionary = _data.get("presence", {})
	var text := str(p.get("states", {}).get(state, ""))
	text = text.replace("{chapter}", str(p.get("chapters", {}).get(str(vars.get("chapter", "")), "")))
	return text.replace("{place}", str(vars.get("place", "")))


## The Rich Presence localization file Steamworks wants (tools/steam_files.gd writes it; tests check
## the committed copy matches). States become #Status_<state>, chapters #Chapter_<id>.
func presence_vdf() -> String:
	var p: Dictionary = _data.get("presence", {})
	var lines := ['"lang"', "{", '\t"english"', "\t{", '\t\t"tokens"', "\t\t{"]
	var states: Dictionary = p.get("states", {})
	for s in states:
		var t := str(states[s]).replace("{chapter}", "{#Chapter_%chapter%}").replace("{place}", "%place%")
		lines.append('\t\t\t"#Status_%s"\t"%s"' % [s, t.replace('"', "'")])  # no-tr: logs and Steam keys
	var chapters: Dictionary = p.get("chapters", {})
	for c in chapters:
		lines.append('\t\t\t"#Chapter_%s"\t"%s"' % [c, str(chapters[c]).replace('"', "'")])  # no-tr: logs and Steam keys
	lines.append_array(["\t\t}", "\t}", "}"])
	return "\n".join(lines) + "\n"


func presence_chapters() -> Dictionary:
	return _data.get("presence", {}).get("chapters", {})


# ---------------------------------------------------------------- overlay

func _on_overlay_signal(open: bool, _user_initiated := false, _app_id := 0) -> void:
	_on_overlay(open)


## The overlay covers the game: pause like losing focus does (a fight opens its pause menu and leaves
## it up), whatever the "in the background" option says. Closing it unpauses only what it paused.
func _on_overlay(open: bool) -> void:
	overlay_toggled.emit(open)
	var tree := get_tree()
	if tree == null:
		return
	if open:
		if tree.paused:
			return
		var scene := tree.current_scene
		if scene and scene.has_method("pause_for_focus_loss"):
			scene.pause_for_focus_loss()
		else:
			tree.paused = true
			_paused_by_overlay = true
	elif _paused_by_overlay:
		_paused_by_overlay = false
		tree.paused = false
