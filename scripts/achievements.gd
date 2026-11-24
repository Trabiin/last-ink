extends Node
## Achievements (autoload "Achievements", issue #150, docs/STEAM.md). The list is data/achievements.json.
##
## Unlocks belong to the player, not to a save: they live in user://achievements.cfg (with Steam
## Cloud, that file travels too) and every build has them, with or without Steam. With Steam running
## each unlock also goes to Steam (SteamLink.unlock), and Steam shows its own pop-up; without it the
## game shows a small banner of its own. When Steam starts, the two lists are merged both ways.
##
## How an achievement unlocks, by its fields in the JSON:
##   "when": {...}            a story condition (Journal.meets): looked at about once a second in play
##   "check": "name", "min"   one of the checks in _check() below, looked at the same way
##   "event": "name"          the game reports it: event(name) (mission results report theirs here)
##   "counter": "name", "min" a lifetime count across all saves: count(name, n)
##   "later": true            designed, waiting for content that isn't in the game yet; never unlocks
##
## Only a real story campaign counts (Story.active()): the test shortcuts' ready-made towns don't.
## Hard-only achievements need the difficulty never lowered, kept per save in Empire.feats.

signal unlocked(id: String)

const DATA := "res://data/achievements.json"
const FILE := "user://achievements.cfg"
const TEST_FILE := "user://test_run/achievements.cfg"
const CHECK_EVERY := 1.0
const HARD := 2  # Settings.DIFFICULTIES index

var path := FILE
var list: Array = []  # entries in file order
var groups: Array = []
var have := {}  # id -> unix time unlocked
var counters := {}  # name -> lifetime count
var _by_id := {}
var _t := 0.0
var _scene_id := 0
var _mission_low := HARD  # lowest difficulty seen during the current mission
var _banner: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # conversations pause the tree; checks still run
	if Diag.scripted:
		path = TEST_FILE  # the tests never touch the player's real achievements
	_load_data()
	load_file()
	SteamLink.started.connect(sync_with_steam)
	if SteamLink.active:
		sync_with_steam()
	Empire.expedition_returned.connect(_on_expedition)


func _load_data() -> void:
	var parsed = Loc.load_json(DATA)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Achievements: %s is missing or broken" % DATA)
		return
	list = parsed.get("achievements", [])
	groups = parsed.get("groups", [])
	_by_id = {}
	for a in list:
		_by_id[str(a["id"])] = a


func info(id: String) -> Dictionary:
	return _by_id.get(id, {})


func is_unlocked(id: String) -> bool:
	return have.has(id)


func live(a: Dictionary) -> bool:
	return not a.get("later", false)


# ---------------------------------------------------------------- the file

func load_file() -> void:
	have = {}
	counters = {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for id in cfg.get_section_keys("unlocked") if cfg.has_section("unlocked") else []:
		if _by_id.has(id):  # one removed from the list (before release) is simply forgotten
			have[id] = int(cfg.get_value("unlocked", id, 0))
	for k in cfg.get_section_keys("counters") if cfg.has_section("counters") else []:
		counters[k] = int(cfg.get_value("counters", k, 0))


func save_file() -> void:
	var cfg := ConfigFile.new()
	for id in have:
		cfg.set_value("unlocked", id, have[id])
	for k in counters:
		cfg.set_value("counters", k, counters[k])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if cfg.save(path) != OK:
		push_warning("Achievements: could not write %s" % path)


## Forgets everything (tests).
func clear_all() -> void:
	have = {}
	counters = {}
	save_file()


# ---------------------------------------------------------------- unlocking

func unlock(id: String) -> bool:
	var a := info(id)
	if a.is_empty() or have.has(id) or not live(a):
		return false
	have[id] = int(Time.get_unix_time_from_system())
	save_file()
	if not SteamLink.unlock(id):
		_show_banner(a)  # Steam shows its own pop-up
	unlocked.emit(id)
	return true


## Steam and this machine end up with the same list: ours go up, Steam's come down (a new PC, or
## achievements earned on the Deck).
func sync_with_steam() -> void:
	if not SteamLink.active:
		return
	var ids := []
	for a in list:
		ids.append(str(a["id"]))
	var theirs := SteamLink.achieved(ids)
	var changed := false
	for id in theirs:
		if not have.has(id):
			have[id] = int(Time.get_unix_time_from_system())
			changed = true
	for id in have:
		if not id in theirs:
			SteamLink.unlock(id)
	if changed:
		save_file()


## Whether progress counts right now: a story campaign, in Hollowmark, at the Command Table or on a mission.
func playing() -> bool:
	var tree := get_tree()
	var scene := tree.current_scene if tree else null
	if scene == null or not Story.active():
		return false
	return scene.scene_file_path in [Saves.HUB_SCENE, Saves.COMMAND_SCENE, Saves.GAME_SCENE]


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var sid := scene.get_instance_id() if scene else 0
	if sid != _scene_id:
		_scene_id = sid
		_mission_low = Settings.difficulty  # a new scene: a mission starts (or loads) fresh
	_t += delta
	if _t < CHECK_EVERY:
		return
	_t = 0.0
	if playing():
		note_difficulty()
		check_all()


## Remembers the lowest difficulty this save and this mission have been played on.
func note_difficulty() -> void:
	var d := Settings.difficulty
	_mission_low = mini(_mission_low, d)
	Empire.feats["lowest_difficulty"] = mini(int(Empire.feats.get("lowest_difficulty", d)), d)


## Looks at every "when" and "check" achievement. Cheap: a few dictionary lookups each.
func check_all() -> Array:
	var got := []
	for a in list:
		var id := str(a["id"])
		if have.has(id) or not live(a):
			continue
		var ok := false
		if a.has("when"):
			ok = Journal.meets(a["when"])
		elif a.has("check"):
			ok = _check(str(a["check"]), int(a.get("min", 0)))
		if ok and unlock(id):
			got.append(id)
	return got


func _check(name: String, n: int) -> bool:
	match name:
		"bond_rank":
			return Empire.bond_ids().any(func(id): return Empire.bond_rank(id) >= n)
		"all_bonds_bound":
			var cast: Array = Empire.bond_cast().keys()
			return cast.all(func(id): return Empire.recruits.has(id) and Empire.bond_rank(id) >= top_bond_rank())
		"romance":
			return Relationships.partner() != ""
		"truce":
			return Relationships.pairs().any(func(p): return str(p.get("kind", "")) == "truce")
		"personal_done":
			return Empire.bonds.keys().filter(func(id): return Empire.personal_done(id)).size() >= n
		"all_personal_done":
			var whos: Array = PersonalMissions.data().get("missions", []).map(func(d): return str(d.get("who", "")))
			return not whos.is_empty() and whos.all(func(w): return Empire.personal_done(w))
		"roster":
			return Empire.roster_ids().size() >= n
		"everyone_recruited":
			return Empire.recruit_data.keys().all(func(id): return Empire.recruits.has(id) or Betrayal.gone(id) or Betrayal.away(id) or Relationships.was_lost(id))
		"held":
			return Story.held() >= n
		"all_provinces":
			return Empire.territory().provinces.all(func(p): return p.get("owner", "") == "you")
		"top_building":
			return Empire.building_ids().any(func(b): return Empire.level_of(b) >= Empire.max_level(b))
		"all_buildings":
			return Empire.building_ids().all(func(b): return Empire.level_of(b) >= Empire.max_level(b))
		"all_research":
			return Empire.research_ids().all(func(r): return Empire.research_state(r) == "done")
		"allied":
			return Empire.faction_ids().any(func(f): return Empire.tier_of(f) == "allied")
		"max_level":
			var heroes: Dictionary = Progress.state().get("heroes", {})
			return heroes.keys().any(func(h): return int(heroes[h].get("level", 1)) >= Progress.max_level())
		"hungry":
			return Empire.hungry
		"betrayal_settled":
			return Empire.missions_cleared.any(func(m): return str(m).begins_with("betrayal_"))
	push_warning("Achievements: no check called '%s'" % name)
	return false


## A bond's last rank ("Bound").
func top_bond_rank() -> int:
	Empire.bond_cast()  # loads data/bonds.json
	return maxi(1, (Empire.bond_data.get("ranks", []) as Array).size() - 1)


## The game reports something happened: unlocks every live achievement waiting on that event.
func event(name: String) -> Array:
	var got := []
	if not Story.active():
		return got
	for a in list:
		if str(a.get("event", "")) == name and unlock(str(a["id"])):
			got.append(str(a["id"]))
	return got


## Adds to a lifetime counter; unlocks what it reaches, and shows Steam's progress pop-up on the way.
func count(name: String, n := 1) -> void:
	if n <= 0 or not Story.active():
		return
	var before := int(counters.get(name, 0))
	counters[name] = before + n
	for a in list:
		if str(a.get("counter", "")) != name or have.has(str(a["id"])):
			continue
		var goal := int(a.get("min", 1))
		if counters[name] >= goal:
			unlock(str(a["id"]))
		elif _crossed_step(before, counters[name], goal):
			SteamLink.progress(str(a["id"]), counters[name], goal)
	save_file()


## Steam's progress pop-up at every quarter of the way, not on every kill.
func _crossed_step(before: int, now: int, goal: int) -> bool:
	var step := maxi(1, goal / 4)
	return before / step != now / step


func progress_of(a: Dictionary) -> Array:
	if a.has("counter"):
		return [mini(int(counters.get(str(a["counter"]), 0)), int(a.get("min", 1))), int(a.get("min", 1))]
	return []


# ---------------------------------------------------------------- what the game reports

## A mission's settled result (Missions.apply calls this once per mission).
func mission_done(result: Dictionary) -> void:
	if not Story.active():
		return
	note_difficulty()
	var outcome := str(result.get("outcome", ""))
	var m: Dictionary = result.get("mission_dict", {})
	count("kills", int(result.get("kills", 0)))
	match outcome:
		"wiped":
			event("wiped")
		"retreat":
			count("retreats")
		"success":
			var kind := str(m.get("type", ""))
			if kind == "reclaim":
				event("reclaimed")
			elif kind == "defense":
				event("surge_broken")
			var boss := str(m.get("objective", {}).get("kind", "")) == "boss"
			if boss and not result.get("skipped", false):
				if int(result.get("downs", 0)) == 0:
					event("boss_flawless")
				if _mission_low >= HARD and Settings.difficulty >= HARD:
					event("boss_hard")
	check_all()


func _on_expedition(report: Dictionary) -> void:
	if str(report.get("outcome", "")) in ["success", "great"]:
		count("expeditions_won")


# ---------------------------------------------------------------- the banner

func unlocked_count() -> int:
	return have.size()


func _show_banner(a: Dictionary) -> void:
	if Diag.scripted:
		return
	if is_instance_valid(_banner):
		_banner.queue_free()
	_banner = CanvasLayer.new()
	_banner.layer = 120
	_banner.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_banner)
	var b := AchievementBanner.new()
	b.setup(tr("Achievement unlocked"), str(a.get("name", "")))
	_banner.add_child(b)
