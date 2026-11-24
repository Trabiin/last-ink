class_name PersonalMissions
extends RefCounted
## Personal missions (issue #113): at bond rank 4 each core character's story becomes a short, hand-built
## mission on the Command Table, and rank 5 waits until it is done. Field heroes are forced into the party
## (it is their fight); core staff come along as an escort the party has to keep alive.
##
## data/personal.json: speakers and talks (merged into Dialogue.data(), like data/story.json), and one
## mission per character: who, province, map (a set-piece map from tools/make_personal.py), brief, threat,
## enemies, rewards, standing, xp and the steps MissionScript plays (see scripts/mission_script.gd).
## The mission dict this builds has type "personal", "who", and "force" (field) or "escort" (staff).

const PATH := "res://data/personal.json"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = Loc.load_json(PATH)
		_data = parsed if parsed is Dictionary else {}
	return _data


## The raw entry from data/personal.json for a character ({} when they have none).
static func def_for(who: String) -> Dictionary:
	for d in data().get("missions", []):
		if d.get("who", "") == who:
			return d
	return {}


## The mission id for a character ("" when they have none).
static func id_for(who: String) -> String:
	return str(def_for(who).get("id", ""))


## The launchable mission for an id ({} when it is not a personal mission).
static func mission(id: String) -> Dictionary:
	for d in data().get("missions", []):
		if d.get("id", "") == id:
			return build(str(d["who"]))
	return {}


static func is_field(who: String) -> bool:
	return Empire.recruit(who).get("tier", "") == "field"


## "locked", "offered", "blocked", "lost", "done", or "" when they have no personal mission.
static func state(who: String) -> String:
	var d := def_for(who)
	if d.is_empty():
		return ""
	if Empire.personal_done(who):
		return "done"
	if not Empire.has_bond(who) or Empire.bond_rank(who) < 4:
		return "locked"
	if Empire.territory().find(d.get("province", "")).get("owner", "") == "erased":
		return "lost"
	return "blocked" if blocker(who) != "" else "offered"


## Why it can't be launched right now ("" = it can).
static func blocker(who: String) -> String:
	var name := Empire.short_name(who)
	if not Empire.recruits.has(who):
		return Loc.t("%s is not with you") % name
	if is_field(who):
		var b := PartyPicker.blocker(who)
		if b != "":
			return Loc.t("%s can't come: %s. Free them in the Roster first") % [name, b]
	elif Empire.role_of(who) == "expedition":
		return Loc.t("%s is away on an expedition") % name
	elif int(Empire.recruits[who].get("injured", 0)) > 0:
		return Loc.t("%s is injured") % name
	return ""


## The mission as the Command Table offers it.
static func build(who: String) -> Dictionary:
	var d := def_for(who)
	if d.is_empty():
		return {}
	var m := d.duplicate(true)
	m["type"] = "personal"
	m["effects"] = true
	m["story"] = false
	m["blocker"] = blocker(who)
	if is_field(who):
		m["force"] = who
	else:
		m["escort"] = who
	var obj := {"kind": "script", "steps": d.get("steps", []), "label": d.get("label", Loc.t("See it through"))}
	if not is_field(who):
		obj["escort"] = who
	m["objective"] = obj
	m.erase("steps")
	return m


## Every personal mission waiting in this province (offered or blocked), for the Command Table.
static func for_province(pid: String) -> Array:
	var out := []
	for d in data().get("missions", []):
		if d.get("province", "") != pid:
			continue
		var st := state(str(d["who"]))
		if st == "offered" or st == "blocked":
			out.append(build(str(d["who"])))
	return out


## Results of a personal mission: on success the bond's last step opens (rank 5 scene), standing moves.
static func apply(m: Dictionary, outcome: String, dry := false) -> Array:
	var lines := []
	var who: String = m.get("who", "")
	var name := Empire.short_name(who)
	if not dry:
		Relationships.note_personal(who, outcome == "success")  # fates for the epilogues (issue #116)
	if outcome == "success":
		if not dry and Empire.has_bond(who):
			Empire._bond(who)["personal_done"] = true  # a bond nobody has talked to yet has no record until now
			Empire.bond_gain(who, 999, "", true)
		lines.append(Loc.t("%s has something to tell Ash. (Bonds: H, or find them in Hollowmark.)") % name)
		var st: Dictionary = m.get("standing", {})
		for fid in st:
			if not dry:
				Empire.change_standing(fid, int(st[fid]), str(m.get("name", "")), true)
			lines.append(Loc.t("%s standing %+d.") % [Empire.faction(fid).get("short", fid), int(st[fid])])
	else:
		lines.append(Loc.t("It isn't finished. %s is still waiting at %s when you are ready to go again.") \
			% [name, Empire.territory().find(m.get("province", "")).get("name", "?")])
	return lines
