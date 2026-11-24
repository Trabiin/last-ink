class_name Relationships
extends RefCounted
## Romance, rivalries, friendships and fates (issue #116, DESIGN.md 5.10). Data: data/relationships.json.
##
## Romance: after their rank 3 scene, a character in romance.cast wants one more word (the "moment" scene,
## played like a rank scene with the key MOMENT). Its choice decides it: a romance, or friends for good.
## One romance at a time; saying yes to someone else ends the current one. The partner's perk counts like a
## bond perk, their daily chats change and their rank 5 scene is the romantic version.
##
## Pairs: friends and rivals posted together (party, the same building's staff, the same expedition) change
## expedition odds, building output and mission stats, and nudge both bonds with Ash a little each day.
## Rivals who work together long enough make peace (a truce), which changes the pair for good.
##
## Fates: per person, what happened to them over the campaign (missions fought, injuries, lost in the white,
## personal mission tries, the choices Ash made in their scenes, the climax betrayal: scripts/betrayal.gd). Epilogues (scripts/epilogues.gd) read them.
##
## State lives in Empire.relations (saved; see fresh()). Every function here is static.

const MOMENT := 35  # the romance moment's scene key: it plays between rank 3 and rank 4
const KINDS := {"friends": "Friends", "rivals": "Rivals", "truce": "Truce"}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/relationships.json", FileAccess.READ)
		_data = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file()) if f else {}
	return _data


## A new campaign's state.
static func fresh() -> Dictionary:
	return {"partner": "", "romance": {}, "ended_seen": {}, "pairs": {}, "fates": {}, "betrayal": Betrayal.fresh()}


## Cleans a saved state up (unknown keys and ids are kept harmlessly; wrong types are replaced).
static func from_save(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	out["partner"] = str(d.get("partner", ""))
	for k in ["romance", "ended_seen", "pairs", "fates"]:
		if typeof(d.get(k)) == TYPE_DICTIONARY:
			out[k] = d[k]
	out["betrayal"] = Betrayal.from_save(d.get("betrayal"))  # issue #186
	if out["partner"] != "" and str(out["romance"].get(out["partner"], "")) != "partner":
		out["partner"] = ""  # a partner the romance table doesn't agree with: trust the table
	return out


static func _st() -> Dictionary:
	if typeof(Empire.relations) != TYPE_DICTIONARY or not Empire.relations.has("fates"):
		Empire.relations = from_save(Empire.relations)
	return Empire.relations


# ---------------------------------------------------------------- romance

static func romance_cast() -> Dictionary:
	return data().get("romance", {}).get("cast", {})


static func can_romance(id: String) -> bool:
	return romance_cast().has(id)


## The current partner's id, or "".
static func partner() -> String:
	return str(_st()["partner"])


## "partner", "ex", "friends" (Ash said no), or "" (not asked yet / can't be romanced).
static func romance_of(id: String) -> String:
	return str(_st()["romance"].get(id, ""))


## Is their moment scene waiting? After the rank 3 scene, once the bond is far enough along.
static func moment_ready(id: String) -> bool:
	if not can_romance(id) or not Empire.has_bond(id) or romance_of(id) != "":
		return false
	var rank := Empire.bond_rank(id)
	if rank < 3:
		return false
	return rank >= 4 or Empire.bond_points(id) >= int(data()["romance"].get("moment_points", 38))


## The moment scene, as bond_scene() returns scenes. A romantic choice says what it costs when Ash is
## already with someone else.
static func moment_scene(id: String) -> Dictionary:
	var m: Dictionary = romance_cast().get(id, {}).get("moment", {})
	if m.is_empty():
		return {}
	var sc := m.duplicate(true)
	sc["rank"] = MOMENT
	var cur := partner()
	if cur != "" and cur != id:
		for c in sc.get("choice", []):
			if c.get("romance", false):
				c["label"] = Loc.t("%s   (ends it with %s)") % [c["label"], Empire.short_name(cur)]
	return sc


## The rank 5 scene to play or replay: the romantic one while they are Ash's partner, or if that is the
## one Ash saw. {} = use the normal one.
static func rank5_scene(id: String) -> Dictionary:
	var v: Dictionary = romance_cast().get(id, {}).get("rank5", {})
	if v.is_empty():
		return {}
	var saw := str(fate(id)["choices"].get("5v", ""))
	if saw == "romance" or (saw == "" and romance_of(id) == "partner"):
		return v
	return {}


## The moment's choice was made. Returns the romance perk when it started one ({} otherwise).
static func decide(id: String, choice: Dictionary) -> Dictionary:
	if not can_romance(id) or romance_of(id) != "":
		return {}
	var st := _st()
	if not choice.get("romance", false):
		st["romance"][id] = "friends"
		_history(Loc.t("%s and Ash: friends") % Empire.short_name(id), [Loc.t("%s asked. Ash said no, kindly. They are friends, and it stays that way.") % Empire.short_name(id)])
		return {}
	var cur := partner()
	if cur != "" and cur != id:
		end_romance(cur)
	st["romance"][id] = "partner"
	st["partner"] = id
	_history(Loc.t("%s and Ash") % Empire.short_name(id), [Loc.t("It's a romance. Everyone will guess. Nobody will be told.")])
	return romance_cast()[id].get("perk", {})


## Ends the current romance with `id`: the bond takes a knock, and they say their piece next time.
static func end_romance(id: String) -> void:
	var st := _st()
	if romance_of(id) != "partner":
		return
	st["romance"][id] = "ex"
	if str(st["partner"]) == id:
		st["partner"] = ""
	Empire.bond_gain(id, int(data()["romance"].get("ended_bond", -6)), "", true)
	Empire.notice.emit(Loc.t("%s heard about Ash's new romance. It's over between them.") % Empire.short_name(id), true)
	_history(Loc.t("%s and Ash: over") % Empire.short_name(id), [Loc.t("Ash took up with someone else. %s found out the way everyone does: from everyone.") % Empire.short_name(id)])


## The ex's piece, the first time Ash talks to them after it ended ([] when there is nothing to say).
## Marks it said.
static func take_ended_lines(id: String) -> Array:
	var st := _st()
	if romance_of(id) != "ex" or st["ended_seen"].has(id):
		return []
	st["ended_seen"][id] = true
	return romance_cast().get(id, {}).get("ended", [])


## A daily chat line for the partner, or "" for anyone else.
static func talk_line(id: String, i: int) -> String:
	if romance_of(id) != "partner":
		return ""
	var ls: Array = romance_cast()[id].get("talk", [])
	return str(ls[i % ls.size()]) if not ls.is_empty() else ""


## The partner's perk as a bond perk ({"id", "rank", "name", "desc", "effect", "romance": true}), or {}.
static func partner_perk() -> Dictionary:
	var p := partner()
	if p == "" or not Empire.has_bond(p):
		return {}
	var pk: Dictionary = romance_cast().get(p, {}).get("perk", {}).duplicate()
	if pk.is_empty():
		return {}
	pk["id"] = p
	pk["rank"] = 0
	pk["romance"] = true
	return pk


## One line for the Bonds screen: where things stand romantically ("" for those who can't be romanced).
static func status_text(id: String) -> String:
	if not can_romance(id):
		return ""
	match romance_of(id):
		"partner":
			var pk: Dictionary = romance_cast()[id].get("perk", {})
			return Loc.t("Romance: with Ash. %s: %s") % [pk.get("name", ""), pk.get("desc", "")]
		"ex":
			return Loc.t("Romance: over. Ash chose someone else.")
		"friends":
			return Loc.t("Romance: Ash said no. Friends, for good.")
	if Empire.bond_rank(id) < 3:
		return Loc.t("Romance: could become more, once you're close (after their rank 3 scene).")
	if moment_ready(id):
		return Loc.t("Romance: they have something to ask Ash.")
	return Loc.t("Romance: something's on their mind. Grow the bond a little more.")


# ---------------------------------------------------------------- pairs

static func _key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


## Every pair as it stands now: {"key", "ids", "kind" (friends, rivals or truce), "name", "text", "effects",
## "banter", "days", "truce_days"}. joined_only: both of them on the roster.
static func pairs(joined_only := true) -> Array:
	var out := []
	for p in data().get("pairs", []):
		var ids: Array = p["ids"]
		if joined_only and not (Empire.recruits.has(ids[0]) and Empire.recruits.has(ids[1])):
			continue
		out.append(_resolve(p))
	return out


static func _resolve(p: Dictionary) -> Dictionary:
	var k := _key(p["ids"][0], p["ids"][1])
	var ps: Dictionary = _st()["pairs"].get(k, {})
	var r := {"key": k, "ids": p["ids"], "kind": p.get("kind", "friends"), "name": p.get("name", ""), "text": p.get("text", ""),
		"effects": p.get("effects", {}), "banter": p.get("banter", []), "days": int(ps.get("days", 0)),
		"truce_days": int(p.get("truce", {}).get("days", 0))}
	if r["kind"] == "rivals" and bool(ps.get("truce", false)) and p.has("truce"):
		var t: Dictionary = p["truce"]
		r["kind"] = "truce"
		for f in ["name", "text", "effects", "banter"]:
			if t.has(f):
				r[f] = t[f]
	return r


## The pair these two make, as pairs() lists it, or {}.
static func pair_between(a: String, b: String) -> Dictionary:
	for p in data().get("pairs", []):
		if (p["ids"][0] == a and p["ids"][1] == b) or (p["ids"][0] == b and p["ids"][1] == a):
			return _resolve(p)
	return {}


## "friends", "rivals", "truce" or "" for two people.
static func pair_state(a: String, b: String) -> String:
	return str(pair_between(a, b).get("kind", ""))


## Pairs with both people in `ids`.
static func pairs_among(ids: Array) -> Array:
	return pairs().filter(func(p): return p["ids"][0] in ids and p["ids"][1] in ids)


## Everyone `id` has a pair with: [pair, other id].
static func pairs_of(id: String) -> Array:
	var out := []
	for p in pairs(false):
		if id in p["ids"]:
			out.append([p, p["ids"][1] if p["ids"][0] == id else p["ids"][0]])
	return out


static func pct(f: float) -> String:
	return "%d%%" % int(round(absf(f) * 100.0))


## "expeditions +5%, building output -1, in the party +2 damage and 10% more damage taken, bond -1 a day"
static func effect_text(e: Dictionary) -> String:
	var parts := []
	if e.has("expedition"):
		parts.append(Loc.t("expeditions %+d%%") % int(e["expedition"]))
	if e.has("building"):
		parts.append(Loc.t("building output %+d") % int(e["building"]))
	var pe: Dictionary = e.get("party", {})
	var pp := []
	if pe.has("damage"):
		pp.append(Loc.t("%+d damage") % int(pe["damage"]))
	if pe.has("hp"):
		pp.append(Loc.t("%+d max HP") % int(pe["hp"]))
	if pe.has("power_rate"):
		pp.append(Loc.t("gauge %s %s") % [pct(float(pe["power_rate"])), Loc.t("faster") if float(pe["power_rate"]) > 0 else Loc.t("slower")])
	if pe.has("revive"):
		pp.append(Loc.t("revives %s faster") % pct(float(pe["revive"])))
	if pe.has("guard"):
		pp.append(Loc.t("%s %s damage taken") % [pct(float(pe["guard"])), Loc.t("less") if float(pe["guard"]) > 0 else Loc.t("more")])
	if not pp.is_empty():
		parts.append(Loc.t("in the party %s") % Loc.list(pp))
	if e.has("bond"):
		parts.append(Loc.t("bond %+d a day") % int(e["bond"]))
	return ", ".join(parts)


## "Rivals: Quill and Tobble (The bar tab)"
static func pair_title(p: Dictionary) -> String:
	return Loc.t("%s: %s and %s (%s)") % [Loc.t(KINDS.get(p["kind"], "?")), Empire.short_name(p["ids"][0]), Empire.short_name(p["ids"][1]), p["name"]]


## Lines for an assign screen: [text, good] for every pair among `ids`, with what it does in `context`
## ("party", "building", "expedition"; "" = everything).
static func notes(ids: Array, context := "") -> Array:
	var out := []
	for p in pairs_among(ids):
		var e: Dictionary = p["effects"]
		var shown := {}
		match context:
			"party":
				for k in ["party", "bond"]:
					if e.has(k):
						shown[k] = e[k]
			"building":
				for k in ["building", "bond"]:
					if e.has(k):
						shown[k] = e[k]
			"expedition":
				for k in ["expedition", "bond"]:
					if e.has(k):
						shown[k] = e[k]
			_:
				shown = e
		var fx := effect_text(shown)
		out.append(["%s%s" % [pair_title(p), (": " + fx) if fx != "" else ""], p["kind"] != "rivals"])
	return out


## One string for a preview line ("" when no pairs).
static func notes_text(ids: Array, context := "") -> String:
	return "  ".join(notes(ids, context).map(func(n): return n[0] + "."))


## Expedition odds lines: [[text, mod]] for every pair on the squad.
static func expedition_mods(squad: Array) -> Array:
	var out := []
	for p in pairs_among(squad):
		var m := int(p["effects"].get("expedition", 0))
		if m != 0:
			out.append([Loc.t("%s (%s and %s)") % [p["name"], Empire.short_name(p["ids"][0]), Empire.short_name(p["ids"][1])], m])
	return out


## Added to a building's staff output (hurt people don't work, so they don't bicker either).
static func building_mod(staff: Array) -> int:
	var working := staff.filter(func(r): return int(Empire.recruits.get(r, {}).get("injured", 0)) == 0)
	var t := 0
	for p in pairs_among(working):
		t += int(p["effects"].get("building", 0))
	return t


## What pairs in the party do on a mission: {"damage", "hp", "guard", "power_rate", "revive", "lines"}.
static func party_effects(ids: Array) -> Dictionary:
	var b := {"damage": 0, "hp": 0, "guard": 0.0, "power_rate": 0.0, "revive": 0.0, "lines": []}
	for p in pairs_among(ids):
		var pe: Dictionary = p["effects"].get("party", {})
		if pe.is_empty():
			continue
		for k in ["damage", "hp"]:
			b[k] += int(pe.get(k, 0))
		for k in ["guard", "power_rate", "revive"]:
			b[k] += float(pe.get(k, 0.0))
		b["lines"].append("%s (%s)" % [effect_text({"party": pe}).trim_prefix("in the party "), p["name"]])
	return b


## Who works beside whom today: lists of ids posted together (the party, each building's staff, each squad).
static func postings() -> Array:
	var out := [Empire.party_ids()]
	for bid in Empire.building_data:
		var s := Empire.staff_of(bid)
		if s.size() >= 2:
			out.append(s)
	for e in Empire.expeditions:
		out.append(e.get("squad", []))
	return out


## Dawn: pairs posted together nudge their bonds, and rivals count towards a truce.
static func daily() -> void:
	var done := {}
	for group in postings():
		for p in pairs_among(group):
			if done.has(p["key"]):
				continue
			done[p["key"]] = true
			var b := int(p["effects"].get("bond", 0))
			if b != 0:
				for id in p["ids"]:
					Empire.bond_gain(id, b, "", true)
			if p["kind"] == "rivals" and p["truce_days"] > 0:
				var ps: Dictionary = _st()["pairs"].get(p["key"], {"days": 0, "truce": false})
				ps["days"] = int(ps.get("days", 0)) + 1
				_st()["pairs"][p["key"]] = ps
				if ps["days"] >= p["truce_days"]:
					_make_truce(p)


static func _make_truce(p: Dictionary) -> void:
	var ps: Dictionary = _st()["pairs"][p["key"]]
	ps["truce"] = true
	var t := pair_between(p["ids"][0], p["ids"][1])
	Empire.notice.emit(Loc.t("%s and %s have made peace: %s. (Bonds: H)") % [Empire.short_name(p["ids"][0]), Empire.short_name(p["ids"][1]), t["name"]], false)
	_history(Loc.t("%s and %s: %s") % [Empire.short_name(p["ids"][0]), Empire.short_name(p["ids"][1]), t["name"]], [t["text"], Loc.t("From now on: %s.") % effect_text(t["effects"])])


## A banter exchange from a pair among `present` ([] if none), for the start of a mission.
static func banter_for(present: Array) -> Array:
	var opts := []
	for p in pairs_among(present):
		for ex in p["banter"]:
			opts.append(ex)
	if opts.is_empty():
		return []
	return opts[randi() % opts.size()]


## The same, as one line for a written report: Quill: "..." Tobble: "...".
static func banter_quote(squad: Array) -> String:
	var ex := banter_for(squad)
	if ex.is_empty():
		return ""
	return Loc.t("On the road: %s") % " ".join(ex.map(func(l): return "%s: \"%s\"" % [Empire.short_name(str(l[0])), str(l[1])]))


# ---------------------------------------------------------------- fates

## What happened to someone so far. Missing fields read as zero/empty.
static func fate(id: String) -> Dictionary:
	var fs: Dictionary = _st()["fates"]
	if not fs.has(id) or typeof(fs[id]) != TYPE_DICTIONARY:
		fs[id] = {}
	var f: Dictionary = fs[id]
	for k in ["missions", "wins", "injuries", "lost_day", "personal_tries", "personal_day"]:
		if not f.has(k):
			f[k] = 0
	if not f.has("lost_where"):
		f["lost_where"] = ""
	if not f.has("betrayal"):
		f["betrayal"] = ""  # issue #186: "", "betrayed", "redeemed", "let_go" or "faked" (scripts/betrayal.gd)
	if typeof(f.get("choices")) != TYPE_DICTIONARY:
		f["choices"] = {}
	return f


static func note_mission(ids: Array, outcome: String) -> void:
	for id in ids:
		var f := fate(id)
		f["missions"] = int(f["missions"]) + 1
		if outcome == "success":
			f["wins"] = int(f["wins"]) + 1


static func note_injury(id: String) -> void:
	var f := fate(id)
	f["injuries"] = int(f["injuries"]) + 1


static func note_lost(id: String, where: String) -> void:
	var f := fate(id)
	f["lost_day"] = Empire.day
	f["lost_where"] = where


static func note_choice(id: String, rank: int, pick: int, variant := "") -> void:
	var f := fate(id)
	f["choices"][str(rank)] = pick
	if variant != "":
		f["choices"]["%dv" % rank] = variant


static func note_personal(id: String, success: bool) -> void:
	var f := fate(id)
	f["personal_tries"] = int(f["personal_tries"]) + 1
	if success and int(f["personal_day"]) == 0:
		f["personal_day"] = Empire.day


static func was_lost(id: String) -> bool:
	return int(fate(id)["lost_day"]) > 0 and not Empire.recruits.has(id)


## Everyone lost on an expedition, in the order they were lost.
static func lost_ids() -> Array:
	var out := []
	for id in _st()["fates"]:
		if was_lost(str(id)):
			out.append(str(id))
	out.sort_custom(func(a, b): return int(fate(a)["lost_day"]) < int(fate(b)["lost_day"]))
	return out


## Facts for the journal's People page: [label, value].
static func fate_facts(id: String) -> Array:
	var out := []
	var f := fate(id)
	if int(f["missions"]) > 0:
		out.append([Loc.t("Missions with Ash"), Loc.t("%d (%d won)") % [int(f["missions"]), int(f["wins"])]])
	if int(f["injuries"]) > 0:
		out.append([Loc.t("Badly hurt"), Loc.n("%d time", "%d times", int(f["injuries"])) % int(f["injuries"])])
	if can_romance(id) and romance_of(id) != "":
		out.append([Loc.t("With Ash"), {"partner": Loc.t("a romance"), "ex": Loc.t("it's over"), "friends": "friends"}[romance_of(id)]])
	for pr in pairs_of(id):
		if Empire.recruits.has(pr[1]):
			out.append([Loc.t(KINDS.get(pr[0]["kind"], "")), "%s (%s)" % [Empire.short_name(pr[1]), pr[0]["name"]]])
	return out


static func _history(title: String, lines: Array) -> void:
	Journal.record({"day": Empire.day, "kind": "bond", "title": title, "lines": lines})
