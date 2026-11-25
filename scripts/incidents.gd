class_name Incidents
extends RefCounted
## Incidents: requests with a face and a deadline (Ojon 2026-11-25, "I don't feel anything about the choices").
## Someone asks (a lamplighter, a mother, Gristle, Daro), the request is on the territory map for a few days,
## and if nobody goes, what was at stake is lost for good: people, a province's safety, a friend's trust. Some
## come in pairs that open on the same day ("rival"): answering one leaves the other unanswered.
##
## Data: data/incidents.json (its _comment has the fields). Talks and speakers there merge into Dialogue.data().
## State: Empire.incidents = {"open": {id: last day}, "done": [ids], "ignored": [ids], "people": {group: {"saved", "lost"}}}.
## Hooks: Empire.tick -> check() (opens and lapses them), Missions.list_for_province -> for_province() (the
## mission on the map), Missions.apply -> record() (done, rival lapses, people counted), Story.next_beat ->
## beats() (the ask, the thanks and the consequence play in town), Story.meets "incident"/"saved"/"lost".
## People from story set pieces (missions.json "people") are counted here too, so later beats can ask
## "did Millbrook get out?".

const PATH := "res://data/incidents.json"
const ID_PREFIX := "incident_"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = Loc.load_json(PATH)
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed
	return _data


static func all() -> Array:
	return data().get("incidents", [])


static func find(id: String) -> Dictionary:
	for i in all():
		if i.get("id", "") == id:
			return i
	return {}


static func fresh() -> Dictionary:
	return {"open": {}, "done": [], "ignored": [], "people": {}}


static func from_save(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	for k in ["open", "people"]:
		if typeof(d.get(k)) == TYPE_DICTIONARY:
			out[k] = (d[k] as Dictionary).duplicate(true)
	for k in ["done", "ignored"]:
		if typeof(d.get(k)) == TYPE_ARRAY:
			out[k] = (d[k] as Array).duplicate()
	# Ids that are no longer in the data are dropped (cut content never breaks a save).
	for id in out["open"].keys():
		if find(str(id)).is_empty():
			out["open"].erase(id)
	return out


static func st() -> Dictionary:
	if typeof(Empire.incidents) != TYPE_DICTIONARY or Empire.incidents.is_empty():
		Empire.incidents = fresh()
	return Empire.incidents


## "open", "done", "ignored" or "" (not yet).
static func state(id: String) -> String:
	var s := st()
	if s["open"].has(id):
		return "open"
	if id in s["done"]:
		return "done"
	if id in s["ignored"]:
		return "ignored"
	return ""


## Story condition "incident": {id: "open" | "done" | "ignored" | "closed" (done or ignored) | "none"}.
static func blocker(c) -> String:
	if typeof(c) != TYPE_DICTIONARY:
		return ""
	for id in c:
		var want := str(c[id])
		var now := state(str(id))
		var ok := now == want or (want == "closed" and now in ["done", "ignored"]) or (want == "none" and now == "")
		if not ok:
			return Loc.t("the story is not there yet")
	return ""


## {"saved": n, "lost": n} for a group of people (incidents and story set pieces).
static func people(group: String) -> Dictionary:
	var p: Dictionary = st()["people"].get(group, {})
	return {"saved": int(p.get("saved", 0)), "lost": int(p.get("lost", 0))}


static func _add_people(group: String, saved: int, lost: int) -> void:
	var all_p: Dictionary = st()["people"]
	var p: Dictionary = all_p.get(group, {"saved": 0, "lost": 0})
	p["saved"] = int(p.get("saved", 0)) + saved
	p["lost"] = int(p.get("lost", 0)) + lost
	all_p[group] = p


## Everyone the campaign got out, and everyone it lost, across every group.
static func totals() -> Dictionary:
	var out := {"saved": 0, "lost": 0}
	for g in st()["people"]:
		out["saved"] += int(st()["people"][g].get("saved", 0))
		out["lost"] += int(st()["people"][g].get("lost", 0))
	return out


## Every tick: open incidents whose time has come, and let lapse the ones nobody answered in time.
## Only story campaigns get them (they hang off story beats).
static func check() -> void:
	if not Story.active() or not Story.command_on():
		return
	var s := st()
	for i in all():
		var id := str(i.get("id", ""))
		if state(id) != "":
			continue
		if not Story.meets(i.get("when", {})):
			continue
		s["open"][id] = Empire.day + int(i.get("open_days", 3))
		Empire.notice.emit(Loc.t("%s: %s") % [str(i.get("asker_name", "")), str(i.get("notice", i.get("name", "")))], true)
	for id in s["open"].keys():
		if Empire.day > int(s["open"][id]):
			lapse(str(id))


## Nobody went: what was at stake is lost. Also what happens to a rival when the other one is answered.
static func lapse(id: String) -> void:
	var s := st()
	if not s["open"].has(id):
		return
	s["open"].erase(id)
	s["ignored"].append(id)
	var i := find(id)
	var fx: Dictionary = i.get("ignored", {})
	for pid in fx.get("fray", {}):
		var p := Empire.territory().find(str(pid))
		if not p.is_empty() and p.get("owner", "") != "erased":
			p["fray"] = clampi(int(p["fray"]) + int(fx["fray"][pid]), 0, 99)
	for g in fx.get("lost", {}):
		_add_people(str(g), 0, int(fx["lost"][g]))
	for k in fx.get("res", {}):
		Empire.gain(str(k), maxi(int(fx["res"][k]), -int(Empire.res.get(k, 0))))
	for fid in fx.get("standing", {}):
		if not Empire.faction(str(fid)).is_empty():
			Empire.change_standing(str(fid), int(fx["standing"][fid]), str(i.get("name", "")), true)
	for rid in fx.get("bond", {}):
		if Empire.recruits.has(str(rid)):
			Empire.bond_gain(str(rid), int(fx["bond"][rid]), str(i.get("name", "")), true)
	var hurt := int(fx.get("injure", 0))
	if hurt > 0:
		var idle := Empire.recruits.keys().filter(func(r): return r != "ash" and Empire.role_of(r) in ["idle", "party", "building"])
		idle.sort()
		for n in mini(hurt, idle.size()):
			Empire.recruits[idle[n]]["injured"] = maxi(int(Empire.recruits[idle[n]]["injured"]), int(fx.get("injure_days", 3)))
	Empire.notice.emit(str(fx.get("notice", Loc.t("%s went unanswered.") % str(i.get("name", id)))), true)


## The request as a mission on the territory map ({} when it isn't open). Its own mission fields plus who asks,
## what is at stake, what lapsing costs, the days left and the rival it would leave unanswered.
static func mission(id: String) -> Dictionary:
	var i := find(id)
	if i.is_empty() or state(id) != "open":
		return {}
	var m: Dictionary = (i.get("mission", {}) as Dictionary).duplicate(true)
	m["id"] = ID_PREFIX + id
	m["incident"] = id
	m["name"] = str(i.get("name", id))
	m["province"] = str(i.get("province", ""))
	m["type"] = "request"
	m["asker_name"] = str(i.get("asker_name", ""))
	m["stakes"] = str(i.get("stakes", ""))
	m["if_ignored"] = str(i.get("if_ignored", ""))
	m["days_left"] = int(st()["open"][id]) - Empire.day
	var rival := str(i.get("rival", ""))
	if rival != "" and state(rival) == "open":
		m["rival_name"] = str(find(rival).get("name", rival))
	m["blocker"] = ""
	var p := Empire.territory().find(m["province"])
	if p.is_empty() or p.get("owner", "") == "erased":
		m["blocker"] = Loc.t("%s has been erased") % p.get("name", "?")
	return m


static func for_province(pid: String) -> Array:
	var out := []
	for id in st()["open"]:
		if str(find(str(id)).get("province", "")) == pid:
			var m := mission(str(id))
			if not m.is_empty():
				out.append(m)
	return out


## Every request open right now, soonest deadline first (the map tags and the journal).
static func open_missions() -> Array:
	var out := []
	for id in st()["open"]:
		var m := mission(str(id))
		if not m.is_empty():
			out.append(m)
	out.sort_custom(func(a, b): return int(a["days_left"]) < int(b["days_left"]))
	return out


## A mission came home (Missions.apply): count its people, close the request it answered, and lapse its rival.
static func record(result: Dictionary) -> void:
	for c in result.get("changed", []):
		var g := str(c.get("group", ""))
		if g == "":
			continue
		if str(c.get("kind", "")) == "people":
			_add_people(g, int(c.get("count", 0)), 0)
		elif str(c.get("kind", "")) == "lost":
			_add_people(g, 0, int(c.get("count", 0)))
	var m: Dictionary = result.get("mission_dict", {})
	var id := str(m.get("incident", ""))
	if id == "" or result.get("outcome", "") != "success" or state(id) != "open":
		return
	var s := st()
	s["open"].erase(id)
	s["done"].append(id)
	var i := find(id)
	var fx: Dictionary = i.get("done", {})
	for rid in fx.get("bond", {}):
		if Empire.recruits.has(str(rid)):
			Empire.bond_gain(str(rid), int(fx["bond"][rid]), str(i.get("name", "")), true)
	for fid in fx.get("standing", {}):
		if not Empire.faction(str(fid)).is_empty():
			Empire.change_standing(str(fid), int(fx["standing"][fid]), str(i.get("name", "")), true)
	var rival := str(i.get("rival", ""))
	if rival != "" and state(rival) == "open":
		lapse(rival)


## Town beats from the incidents: the ask when one opens, then the thanks or the consequence. Same shape as
## story.json beats; Story.next_beat plays them after the story's own.
static func beats() -> Array:
	var out := []
	for i in all():
		var id := str(i.get("id", ""))
		var now := state(id)
		if now == "open" and str(i.get("ask", "")) != "":
			out.append({"talk": str(i["ask"]), "when": {}})
		elif now == "done" and str(i.get("done_talk", "")) != "":
			out.append({"talk": str(i["done_talk"]), "when": i.get("done_when", {})})
		elif now == "ignored" and str(i.get("ignored_talk", "")) != "":
			out.append({"talk": str(i["ignored_talk"]), "when": {}})
	return out
