class_name Epilogues
extends RefCounted
## Epilogues (issue #116): one card per person at the ending (#32), picked from their bond and fate.
## Data: data/epilogues.json (see its _comment for the "when" keys). The ending plays them with
## scripts/epilogue_view.gd: EpilogueView.play(Epilogues.cards()).

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/epilogues.json", FileAccess.READ)
		_data = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file()) if f else {}
	return _data


## Variants for someone: their own list, or the default one.
static func variants(id: String) -> Array:
	var c: Dictionary = data().get("cast", {})
	return c.get(id, c.get("default", []))


## The cards, in order: the core cast who joined (bond order), then the rest of the roster, then those the
## white took. Ash gets none (the ending is Ash's). Each: {"id", "name", "text", "color", "lost"}.
static func cards() -> Array:
	var ids := []
	for id in Empire.bond_ids():
		ids.append(id)
	for id in Empire.roster_ids():
		if not id in ids and id != "ash":
			ids.append(id)
	for id in Relationships.lost_ids():
		if not id in ids:
			ids.append(id)
	var out := []
	for id in ids:
		var t := text_for(id)
		if t != "":
			out.append({"id": id, "name": Empire.recruit(id).get("name", id), "text": t, "lost": Relationships.was_lost(id),
				"color": Empire.bond_info(id).get("color", "c9c3b6")})
	return out


## The epilogue text for one person ("" if none fits, which tests rule out).
static func text_for(id: String) -> String:
	for v in variants(id):
		if meets(id, v.get("when", {})):
			var r := Empire.recruit(id)
			return str(v["text"]).replace("{name}", str(r.get("name", id))).replace("{short}", Empire.short_name(id))
	return ""


static func meets(id: String, w: Dictionary) -> bool:
	var f := Relationships.fate(id)
	for k in w:
		var v = w[k]
		match k:
			"romance":
				var r := Relationships.romance_of(id)
				if (r if r != "" else "none") != str(v):
					return false
			"rank_min":
				if Empire.bond_rank(id) < int(v):
					return false
			"rank_max":
				if Empire.bond_rank(id) > int(v):
					return false
			"personal":
				var done := Empire.personal_done(id)
				var lost := not done and Empire.personal_job(id) != "" and Empire.personal_lost(id) != ""
				if (str(v) == "done" and not done) or (str(v) == "open" and done) or (str(v) == "lost" and not lost):
					return false
			"home":
				var p := Empire.territory().find(PersonalMissions.def_for(id).get("province", ""))
				if p.is_empty() or (str(v) == "erased") != (p.get("owner", "") == "erased"):
					return false
			"missions_min":
				if int(f["missions"]) < int(v):
					return false
			"injuries_min":
				if int(f["injuries"]) < int(v):
					return false
			"choice":
				if not f["choices"].has(str(int(v.get("rank", 0)))) or int(f["choices"][str(int(v.get("rank", 0)))]) != int(v.get("pick", -1)):
					return false
			"lost":
				if Relationships.was_lost(id) != bool(v):
					return false
			"pair":
				var other := str(v.get("with", ""))
				if not Empire.recruits.has(other) or Relationships.pair_state(id, other) != str(v.get("state", "")):
					return false
			"betrayal":
				var b := Betrayal.outcome(id)
				if (b if b != "" else "none") != str(v):
					return false
			_:
				push_warning("epilogues.json: unknown condition '%s' for %s" % [k, id])
				return false
	# Someone the white took only ever matches a variant that asks about it.
	if Relationships.was_lost(id) and not w.has("lost"):
		return variants(id).filter(func(x): return x.get("when", {}).has("lost")).is_empty()
	return true
