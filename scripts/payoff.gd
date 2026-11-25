class_name Payoff
extends RefCounted
## What a mission changed, for the results screen (results_view.gd) to lead with before the numbers.
##
## Ojon (2026-11-25): the payoff felt weird because the results opened on numbers and the story beat landed later,
## somewhere else. So the results page now opens on what changed: the people you saved walking into town, the
## province's name turning back to ink, and one line from someone in the party. The numbers come after.
##
## A settled result (Missions.settle) may carry result["changed"]: an Array of entries the mission wrote itself
## (the Act 1 incidents and set pieces do). Each entry is a Dictionary:
##   {"kind": "people", "text": ..., "count": n, "from": "Millbrook"}   figures walk into Hollowmark (count: how many)
##   {"kind": "place",  "text": ..., "province_id": id}                 the province's name inks back in
##   {"kind": "lost",   "text": ..., "province_id": id}                 the name fades to white (or a plain line)
##   {"kind": "person", "text": ..., "who": recruit id}                 one named person walks in
##   {"kind": "line",   "text": ..., "who": speaker id}                 a party member's one line about it
## When a mission writes none, entries() makes them from what the result already says (Fray pushed back, a land
## reclaimed or granted, someone joining, a surge broken). Without a "line" entry it picks one from
## data/payoffs.json, spoken by someone who went. Ash is silent and never gets the line.

const PATH := "res://data/payoffs.json"
const KINDS := ["people", "place", "lost", "person", "line"]
## Which fallback line fits: the first kind found in this order.
const LINE_ORDER := ["people", "person", "place", "lost"]

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d = Loc.load_json(PATH)
		if d is Dictionary:
			_data = d
	return _data


## The entries to show for this result, in order, with exactly one "line" at the end when anyone can say it.
## party: who went (ids); left out, the current mission party.
static func entries(result: Dictionary, party = null) -> Array:
	var out := []
	var given = result.get("changed", [])
	if given is Array and not (given as Array).is_empty():
		for e in given:
			if e is Dictionary and str(e.get("kind", "")) in KINDS and str(e.get("text", "")) != "":
				out.append(e)
	else:
		out = derived(result)
	var has_line := out.any(func(e): return e["kind"] == "line")
	# The line goes last: the beat lands, then somebody says something about it.
	var lines := out.filter(func(e): return e["kind"] == "line")
	out = out.filter(func(e): return e["kind"] != "line")
	if has_line:
		out.append(lines[0])
	else:
		var ln := fallback_line(result, out, party if party is Array else _party())
		if not ln.is_empty():
			out.append(ln)
	return out


## Entries made from what a result already records, for missions that write none themselves.
static func derived(result: Dictionary) -> Array:
	var out := []
	var outcome := str(result.get("outcome", ""))
	var won := outcome == "success"
	var m: Dictionary = result.get("mission_dict", {})
	var pid := str(result.get("province_id", ""))
	var pname := str(result.get("province", ""))
	var first := bool(result.get("first_clear", false))
	if won:
		# Someone walks in: a rescue, or a story mission's recruit.
		var who := []
		if str(m.get("type", "")) == "rescue":
			var rid := str(m.get("objective", {}).get("who", ""))
			if rid != "" and not Empire.recruits.has(rid):
				who.append(rid)
		if first:
			for rid in m.get("on_success", {}).get("join", []):
				if not Empire.recruits.has(str(rid)) and not who.has(str(rid)):
					who.append(str(rid))
		for rid in who:
			var nm := str(Empire.recruit(rid).get("name", rid))
			out.append({"kind": "person", "who": rid, "text": Loc.t("%s walks into Hollowmark.") % nm})
		# The land: reclaimed from the white, raised to your flag, or pulled back from the Blank.
		var p := Empire.territory().find(pid)
		if str(m.get("type", "")) == "reclaim" and str(p.get("owner", "")) == "erased":
			out.append({"kind": "place", "province_id": pid, "text": Loc.t("%s is back on the map.") % pname})
		elif first and pid in m.get("on_success", {}).get("grant", []) and str(p.get("owner", "")) != "you":
			out.append({"kind": "place", "province_id": pid, "text": Loc.t("%s raises your flag.") % pname})
		elif str(m.get("type", "")) == "defense" and Empire.surge.get("id", "") == pid:
			out.append({"kind": "people", "count": 7, "from": pname, "stay": true,
				"text": Loc.t("The surge broke short of %s. Its people sleep in their own beds tonight.") % pname})
		elif int(result.get("fray", 0)) < 0 and pname != "":
			out.append({"kind": "place", "province_id": pid,
				"text": Loc.t("The white backs off %s. Fray %d to %d.") % [pname, int(result.get("fray_now", 0)),
					clampi(int(result.get("fray_now", 0)) + int(result["fray"]), 0, 99)]})
		if out.is_empty() and pname != "":
			out.append({"kind": "place", "province_id": pid, "faint": true,
				"text": Loc.t("The roads through %s are safe to walk for a while.") % pname})
	elif outcome == "retreat":
		out.append({"kind": "lost", "province_id": pid, "faint": true,
			"text": Loc.t("You pulled out. %s waits, and the Blank does not.") % pname if pname != "" else Loc.t("You pulled out.")})
	else:
		out.append({"kind": "lost", "province_id": pid,
			"text": Loc.t("Driven out. %s stays pale tonight.") % pname if pname != "" else Loc.t("Driven out.")})
	return out


## One line from someone who went, for the first kind of change (data/payoffs.json "heroes"). {} when nobody
## who went has a line for it (or only Ash went).
static func fallback_line(result: Dictionary, shown: Array, party: Array) -> Dictionary:
	var kind := "plain"
	for k in LINE_ORDER:
		if shown.any(func(e): return e["kind"] == k):
			kind = k
			break
	if kind == "place" and shown.all(func(e): return e.get("faint", false)):
		kind = "plain"  # a patrol's quiet road is not a re-inked province
	var lines: Dictionary = data().get("heroes", {})
	var speakers := []
	for id in party:
		if str(id) != "ash" and lines.has(str(id)) and (lines[str(id)] as Dictionary).has(kind):
			speakers.append(str(id))
	if speakers.is_empty():
		return {}
	# The same mission on the same day always gets the same speaker and line (reopening a save shows the same).
	var seed := absi(hash("%s|%d|%s" % [result.get("mission", ""), Empire.day, kind]))
	var who: String = speakers[seed % speakers.size()]
	var pool = lines[who][kind]
	var pick = pool[(seed / 7) % (pool as Array).size()] if pool is Array else pool
	var speaker := who
	var text := str(pick)
	if pick is Dictionary:  # {"who": "tally", "text": ...}: someone else answers for them
		speaker = str(pick.get("who", who))
		text = str(pick.get("text", ""))
	if text == "":
		return {}
	return {"kind": "line", "who": speaker, "text": text, "fallback": true}  # Loc.load_json translated it


static func _party() -> Array:
	return PartyPicker.mission_party(Empire.active_mission)


## The display name of a speaker, as the dialogue box writes it.
static func speaker_name(who: String) -> String:
	return Dialogue.display_name(who)
