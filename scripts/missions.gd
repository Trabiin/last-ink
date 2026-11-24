class_name Missions
extends RefCounted
## Missions on the territory map (issue #5): which mission a province offers, launching it,
## and settling the results when the party comes home.
##
## A mission is a plain Dictionary (see data/missions.json). Missions can also be built at
## runtime (a Defense mission for a surge, say) and passed straight to launch().
## While one is being played it lives in Empire.active_mission (saved with the mission scene,
## not with the empire: the clock is frozen until the party is back).

const PATH := "res://data/missions.json"
const MISSION_SCENE := "res://scenes/main.tscn"
const DEFAULT := "meadow_prologue"  # New Game drops you straight into this one
const OUTCOME_TITLES := {"success": "Mission complete", "retreat": "Retreated", "wiped": "Driven out"}

static var _data: Array = []


static func all() -> Array:
	if _data.is_empty():
		var parsed = Loc.load_json(PATH)
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed.get("missions", [])
	return _data


## A mission by id: data/missions.json first, then the personal missions (data/personal.json, #113).
static func find(id: String) -> Dictionary:
	for m in all():
		if m["id"] == id:
			return m
	return PersonalMissions.mission(id)


## A character's personal mission as the Command Table offers it ({} when they have none), issue #113.
static func personal_for(who: String) -> Dictionary:
	return PersonalMissions.build(who)


## "locked" (bond rank under 4), "offered" (can launch), "blocked" (offered but something is in the way,
## see its "blocker"), "lost" (its province is erased) or "done". "" when they have no personal mission.
static func personal_state(who: String) -> String:
	return PersonalMissions.state(who)


## What kind of mission this is, for the briefing: "Story", "Boss", "Patrol", "Defense", "Raid"...
static func type_name(m: Dictionary) -> String:
	if m.has("type"):
		return Loc.t(MissionTypes.TYPE_NAMES.get(m["type"], str(m["type"]).capitalize()))
	if m.get("objective", {}).get("kind", "") == "boss":
		return Loc.t("Boss")
	return Loc.t("Story") if m.get("story", false) else Loc.t("Patrol")


## How dangerous it is, 1 (light) to 5 (deadly): the mission's own "threat", else a guess from the land.
static func threat(m: Dictionary) -> int:
	if m.has("threat"):
		return clampi(int(m["threat"]), 1, 5)
	var p := Empire.territory().find(m.get("province", ""))
	return clampi(1 + int(p.get("fray", 0)) / 30, 1, 5)


## "3/5, Stiff" for the briefing.
static func threat_text(m: Dictionary) -> String:
	var n := threat(m)
	var names: Array = MissionTypes.data().get("threat_names", [])
	return "%d/5, %s" % [n, str(names[n]) if n < names.size() else ""]


## The reward line for the briefing: a type's own description, else the fixed rewards.
static func reward_text(m: Dictionary) -> String:
	var fixed := res_text(m.get("rewards", {}))
	if m.has("reward_text"):
		return str(m["reward_text"]) + ((Loc.t(", plus ") + fixed + Loc.t(" on success")) if fixed != "" else "")
	return fixed


static func cleared(id: String) -> bool:
	return id in Empire.missions_cleared


## Whether the map offers this mission right now.
static func offered(m: Dictionary) -> bool:
	if m.get("story", false) and cleared(m["id"]):
		return false
	var after: String = m.get("after", "")
	if after != "" and not cleared(after):
		return false
	if m.has("needs") and not Story.meets(m["needs"]):  # story conditions (issue #18)
		return false
	var p := Empire.territory().find(m.get("province", ""))
	# "in_blank" missions happen inside the white (the betrayer's home written as words, issue #186).
	return not p.is_empty() and (p["owner"] != "erased" or m.get("in_blank", false)) and Empire.province_open(p)


## The mission a province offers, or {} when there is none. Story missions come first.
static func for_province(pid: String) -> Dictionary:
	var ms := list_for_province(pid)
	return ms[0] if not ms.is_empty() else {}


## Everything a province offers, best first: story missions, then the runtime Defense,
## Reclaim and Rescue missions (MissionTypes, issue #51), then repeatable ones like patrols.
## A mission with a non-empty "blocker" is shown but cannot be launched yet.
static func list_for_province(pid: String) -> Array:
	var story := []
	var repeat := []
	for m in all():
		if m.get("province", "") == pid and offered(m):
			(story if m.get("story", false) else repeat).append(_gated(m) if m.get("story", false) else _varied(m))
	return story + MissionTypes.for_province(pid) + repeat


## A story mission with "gate" conditions is on the map as soon as it is offered, but locked with the first
## missing condition as its blocker (issue #28: "put a governor in Candleford", "needs Neutral standing").
static func _gated(m: Dictionary) -> Dictionary:
	if not m.has("gate"):
		return m
	var g := m.duplicate()
	g["blocker"] = Story.blocker(m["gate"])
	return g


## A repeatable mission (a patrol) laid out fresh from its province's map pool each day (#113), so the tenth
## patrol does not play like the first. Story missions keep their hand-made maps.
static func _varied(m: Dictionary) -> Dictionary:
	var v := m.duplicate(true)
	v.erase("map")
	MissionTypes.vary(v, str(m.get("province", "")))
	return v


## The mission being played, falling back to the right Meadow mission for New Game and for
## saves made before missions existed.
static func current() -> Dictionary:
	if not Empire.active_mission.is_empty():
		return Empire.active_mission
	var m := find(DEFAULT)
	if cleared(DEFAULT):
		m = for_province("meadow")
		if m.is_empty():
			m = find("meadow_patrol")
	return m


## Sets the mission and loads its map. The caller autosaves first (Command does in _leave).
static func launch(m: Dictionary) -> void:
	Empire.active_mission = m.duplicate(true)
	Saves.pending = {}
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	tree.change_scene_to_file(m.get("scene", MISSION_SCENE))


## "40 Gilt, 15 Supplies, 2 Ink" (empty string for nothing).
static func res_text(d: Dictionary) -> String:
	var parts := []
	for k in ["gilt", "supplies", "ink", "renown", "insight"]:
		if int(d.get(k, 0)) != 0:
			parts.append("%d %s" % [int(d[k]), Loc.t(Empire.RES_NAMES.get(k, k))])
	var other := Armory.found_text(d)  # Forge materials and field items (issue #112)
	if other != "":
		parts.append(other)
	return ", ".join(parts)


## Rolls one kill's pickup from the mission's loot table. Returns {} for nothing.
static func roll_loot(m: Dictionary) -> Dictionary:
	var out := {}
	var table: Dictionary = m.get("loot", {})
	for k in table:
		var row: Array = table[k]
		if randf() < float(row[0]):
			out[k] = randi_range(int(row[1]), int(row[2]))
	return out


## Works out what the party brings home. Nothing is paid until apply().
## outcome: "success", "retreat" or "wiped".
static func settle(m: Dictionary, outcome: String, found: Dictionary, stats: Dictionary) -> Dictionary:
	var pay := {}
	if outcome != "wiped":  # the wiped-out party drops everything it picked up
		for k in found:
			pay[k] = int(pay.get(k, 0)) + int(found[k])
	var fray := 0
	if outcome == "success":
		var r: Dictionary = m.get("rewards", {})
		for k in r:
			pay[k] = int(pay.get(k, 0)) + int(r[k])
		fray = int(m.get("fray", 0))
	var p := Empire.territory().find(m.get("province", ""))
	var md := m.duplicate(true)
	md["info"] = stats.get("info", {})  # how it went (caches taken, the alarm), for the type's effects (#113)
	return {
		"outcome": outcome, "title": Loc.t(OUTCOME_TITLES.get(outcome, outcome)),
		"mission": m.get("id", ""), "name": m.get("name", Loc.t("Mission")),
		"province": p.get("name", ""), "province_id": p.get("id", ""),
		"fray": fray, "fray_now": int(p.get("fray", 0)),
		"found": found.duplicate(), "pay": pay,
		"first_clear": outcome == "success" and not cleared(m.get("id", "")),
		"kills": int(stats.get("kills", 0)), "time": float(stats.get("time", 0.0)),
		"downs": int(stats.get("downs", 0)), "skipped": bool(stats.get("skipped", false)),  # achievements (#150)
		"objective": stats.get("objective", ""),
		"rewards": m.get("rewards", {}) if outcome == "success" else {},
		"lines": _effect_lines(md, outcome, stats),  # mission-type effects, issue #51
		"mission_dict": md,
	}


static func _effect_lines(m: Dictionary, outcome: String, stats: Dictionary) -> Array:
	var lines := []
	if str(stats.get("fail", "")) != "":
		lines.append(str(stats["fail"]))
	if outcome == "success" and not cleared(str(m.get("id", ""))):
		lines.append_array(story_effects(m, true))
	if m.get("effects", false):
		lines.append_array(MissionTypes.apply(m, outcome, true))
	return lines


## A story mission's lasting effects on its first success (issue #28), from its "on_success":
##   grant: [province ids]   the province raises your flag (it still wants a governor)
##   join: [recruit ids]     that person joins the roster straight from the mission
##   standing: {faction: n}  standing changes with those factions
##   betrayal: "foreshadow" | "lock" | "con_home"   the climax betrayal's chapter hooks (issue #186)
## dry_run only describes them, for the results screen. Returns the lines either way.
static func story_effects(m: Dictionary, dry_run := false) -> Array:
	var lines := []
	var fx: Dictionary = m.get("on_success", {})
	for pid in fx.get("grant", []):
		var p := Empire.territory().find(str(pid))
		if p.is_empty() or p.get("owner", "") == "you":
			continue
		lines.append(Loc.t("%s raises your flag. It needs a governor.") % p["name"])
		if not dry_run:
			p["owner"] = "you"
			Empire.notice.emit(Loc.t("%s is yours. Put a governor in it from the Command Table.") % p["name"], false)
	for rid in fx.get("join", []):
		if Empire.recruits.has(str(rid)) or Empire.recruit(str(rid)).is_empty():
			continue
		lines.append(Loc.t("%s joins your roster.") % Empire.recruit(str(rid)).get("name", rid))
		if not dry_run:
			Empire.join_now(str(rid))
	var st: Dictionary = fx.get("standing", {})
	for fid in st:
		if Empire.faction(fid).is_empty():
			continue
		lines.append(Loc.t("%s standing %+d.") % [Empire.faction(fid).get("short", fid), int(st[fid])])
		if not dry_run:
			Empire.change_standing(fid, int(st[fid]), str(m.get("name", "")), true)
	match str(fx.get("betrayal", "")):
		"foreshadow":
			if not dry_run:
				Betrayal.begin_foreshadowing()
		"lock":
			if not dry_run:
				Betrayal.lock()
		"con_home":
			lines.append(Loc.t("Bran is back on the roster, with a receipt."))
			if not dry_run:
				Betrayal.con_home()
	return lines


## Pays out a settled result and marks the mission cleared.
static func apply(result: Dictionary) -> void:
	var pay: Dictionary = result["pay"]
	for k in pay:
		if not Armory.bank(k, int(pay[k])):  # materials and field items go to the town stores (issue #112)
			Empire.gain(k, int(pay[k]))
	if result["outcome"] == "success" and not cleared(result["mission"]):
		story_effects(result.get("mission_dict", {}))  # before it counts as cleared: effects pay once
		Empire.missions_cleared.append(result["mission"])
	var p := Empire.territory().find(result.get("province_id", ""))
	if not p.is_empty() and p["owner"] != "erased" and int(result["fray"]) != 0:
		p["fray"] = clampi(int(p["fray"]) + int(result["fray"]), 0, 99)
	# Mission types with effects beyond rewards (issue #51): surges broken, land rewritten, people found.
	var m: Dictionary = result.get("mission_dict", {})
	if m.get("effects", false):
		MissionTypes.apply(m, result["outcome"])
	Satchel.restock(true)  # free rations and the town stores repack the satchel (issues #6, #112)
	Empire.active_mission = {}
	Empire.last_mission = result
	Relationships.note_mission(PartyPicker.mission_party(m), str(result["outcome"]))  # fates for the epilogues (issue #116)
	Achievements.mission_done(result)  # issue #150


## Pays out, autosaves in Hollowmark and walks the party home.
static func go_home(result: Dictionary) -> void:
	apply(result)
	Saves.pending = {}
	Saves.save("auto", {"scene": Saves.HUB_SCENE, "area_name": Loc.t("Hollowmark")})
	var tree := Engine.get_main_loop() as SceneTree
	tree.paused = false
	tree.change_scene_to_file(Saves.HUB_SCENE)
