extends "res://tests/test_case.gd"
## Data checks (issue #110): every file in data/ parses, and every id it points at exists.
## A failure names the file and the entry, e.g. "missions.json gutterwoods_patrol: map ... missing".

const EXPRESSIONS := ["", "happy", "angry", "sad", "surprised", "smug"]
const OBJECTIVE_KINDS := ["kills", "boss", "defense", "reclaim", "rescue", "raid", "salvage", "script"]
const STEP_KINDS := ["talk", "goto", "clear", "hold", "use", "exit"]
const OWNERS := ["you", "free", "erased"]

var D := {}  # file name -> parsed JSON


func before_each() -> void:
	D = {}
	for f in DirAccess.get_files_at("res://data/"):
		if f.ends_with(".json"):
			D[f] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))


func _ids(arr: Array) -> Dictionary:
	var out := {}
	for e in arr:
		out[str(e["id"])] = e
	return out


func _unique(file: String, arr: Array) -> void:
	var seen := {}
	for e in arr:
		var id := str(e.get("id", ""))
		check(id != "", "%s: an entry has no id" % file)
		check(not seen.has(id), "%s: id %s used twice" % [file, id])
		seen[id] = true


func _recruits() -> Dictionary:
	return _ids(D["recruits.json"]["recruits"])


func _provinces() -> Dictionary:
	return _ids(D["provinces.json"]["provinces"])


func _talks() -> Dictionary:
	var t: Dictionary = D["dialogue.json"]["talks"].duplicate()
	t.merge(D["story.json"]["talks"])
	t.merge(D["personal.json"]["talks"])
	return t


func _speakers() -> Dictionary:
	var s := {"": true}
	for id in _recruits():
		s[id] = true
	for id in D["dialogue.json"]["speakers"]:
		s[id] = true
	for id in D["story.json"]["speakers"]:
		s[id] = true
	for id in D["personal.json"]["speakers"]:
		s[id] = true
	return s


func _res_keys(where: String, d: Dictionary, mats := false) -> void:  # mats: materials (#112) allowed too
	for k in d:
		check(Empire.RES_NAMES.has(k) or (mats and Armory.is_mat(k)), "%s: unknown resource '%s'" % [where, k])


func _lines(where: String, lines: Array) -> void:
	var speakers := _speakers()
	for l in lines:
		var a: Array = Dialogue.line(l)
		check(speakers.has(a[0]), "%s: unknown speaker '%s'" % [where, a[0]])
		check(a[2] in EXPRESSIONS, "%s: unknown expression '%s'" % [where, a[2]])
		check(str(a[1]).strip_edges() != "", "%s: empty line for '%s'" % [where, a[0]])


func _res(path: String) -> bool:
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


# ------------------------------------------------------------------ files

func test_every_data_file_parses() -> void:
	check(D.size() >= 18, "expected the data files, found %d" % D.size())
	for f in D:
		check(typeof(D[f]) == TYPE_DICTIONARY, "%s does not parse to a JSON object" % f)


# ------------------------------------------------------------------ people

func test_recruits() -> void:
	var rs: Array = D["recruits.json"]["recruits"]
	_unique("recruits.json", rs)
	var traits: Dictionary = D["recruits.json"]["traits"]
	var jobs := _ids(D["expeditions.json"]["jobs"])
	var factions := _ids(D["factions.json"]["factions"])
	var buildings := _ids(D["buildings.json"]["buildings"])
	var nodes := _ids(D["research.json"]["nodes"])
	var tiers := _ids(D["factions.json"]["tiers"])
	for r in rs:
		var id: String = r["id"]
		var w: String = "recruits.json " + id
		for t in r.get("traits", []):
			check(traits.has(t), "%s: unknown trait %s" % [w, t])
		for s in r.get("stats", {}):
			check(Empire.STAT_NAMES.has(s), "%s: unknown stat %s" % [w, s])
		check(_res("res://assets/portraits/%s.png" % id), "%s: no portrait assets/portraits/%s.png" % [w, id])
		check(D["sprites.json"]["sprites"].has(id), "%s: no sprite set in sprites.json" % w)
		var outfit := str(r.get("look", {}).get("outfit", ""))
		if outfit != "":
			check(_res("res://assets/characters/outfit_%s.png" % outfit), "%s: outfit %s has no image" % [w, outfit])
		var j: Dictionary = r.get("join", {})
		match str(j.get("type", "")):
			"":
				check(r.get("start", false) or jobs.values().any(func(x): return x.get("recruit", "") == id),
					"%s: not a starting recruit and has no way to join" % w)
			"rescue":
				check(jobs.has(j.get("job", "")), "%s: rescue job %s missing" % [w, j.get("job")])
			"claim":
				check(_provinces().has(j.get("province", "")), "%s: claim province %s missing" % [w, j.get("province")])
			"building":
				check(buildings.has(j.get("building", "")), "%s: building %s missing" % [w, j.get("building")])
			"standing":
				check(factions.has(j.get("faction", "")), "%s: faction %s missing" % [w, j.get("faction")])
				check(tiers.has(j.get("tier", "")), "%s: tier %s missing" % [w, j.get("tier")])
			"research":
				check(nodes.has(j.get("node", "")), "%s: research node %s missing" % [w, j.get("node")])
			"renown":
				check(int(j.get("amount", 0)) > 0, "%s: renown amount" % w)
			"bond":
				check(D["bonds.json"]["cast"].has(j.get("who", "")), "%s: bond with %s, who has no bond" % [w, j.get("who")])
			var other:
				check(false, "%s: unknown join type %s" % [w, other])
		_res_keys(w + " hire", r.get("hire", {}))


func test_field_heroes() -> void:
	var heroes: Dictionary = D["heroes.json"]["heroes"]
	var recruits := _recruits()
	var abilities: Dictionary = D["abilities.json"]["abilities"]
	var techs: Dictionary = D["techs.json"]["techs"]
	var gear: Dictionary = D["gear.json"]
	for id in heroes:
		var h: Dictionary = heroes[id]
		var w: String = "heroes.json " + id
		check(recruits.has(id), "%s: not a recruit" % w)
		check(str(recruits.get(id, {}).get("tier", "")) == "field", "%s: recruit tier is not field" % w)
		for a in h.get("abilities", []):
			check(abilities.has(a), "%s: unknown ability %s" % [w, a])
		check(AllyAI.PRESETS.has(AllyAI.preset_id(str(h.get("ai", "")))) and (AllyAI.PRESETS.has(h.get("ai", "")) or AllyAI.LEGACY.has(h.get("ai", ""))),
			"%s: unknown ai style %s" % [w, h.get("ai")])
		check(techs.has(id), "%s: no charged tech in techs.json" % w)
		check(gear["growth"].has(id), "%s: no level growth in gear.json" % w)
		var start := str(gear["start"]["gear"].get(id, ""))
		check(start != "", "%s: no starting weapon in gear.json" % w)
		if start != "":
			check(gear["items"].has(start), "%s: starting gear %s missing" % [w, start])
	for id in techs:
		check(heroes.has(id), "techs.json: %s is not a field hero" % id)
	for id in gear["growth"]:
		check(id == "_default" or heroes.has(id), "gear.json growth: %s is not a field hero" % id)
	for id in gear["start"]["gear"]:
		check(heroes.has(id), "gear.json start: %s is not a field hero" % id)


func test_gear_and_items() -> void:
	var gear: Dictionary = D["gear.json"]
	var heroes: Dictionary = D["heroes.json"]["heroes"]
	for id in gear["items"]:
		var it: Dictionary = gear["items"][id]
		var w: String = "gear.json item " + id
		if it.has("hero"):
			check(heroes.has(it["hero"]), "%s: hero %s is not a field hero" % [w, it["hero"]])
		check(str(it.get("name", "")) != "", "%s: no name" % w)
		check(str(it.get("blurb", "")) != "", "%s: no blurb" % w)
	for id in gear["drops"]["table"]:
		check(gear["items"].has(id), "gear.json drops: %s missing" % id)
	for id in gear["start"]["gear"]:
		var item: Dictionary = gear["items"].get(gear["start"]["gear"][id], {})
		check(str(item.get("hero", id)) == id, "gear.json start: %s gets %s, made for %s" % [id, gear["start"]["gear"][id], item.get("hero")])
	for id in D["items.json"]["items"]:
		check(str(D["items.json"]["items"][id].get("desc", "")) != "", "items.json %s: no description" % id)


func test_bonds() -> void:
	var b: Dictionary = D["bonds.json"]
	var recruits := _recruits()
	var buildings := _ids(D["buildings.json"]["buildings"])
	for id in b["cast"]:
		var c: Dictionary = b["cast"][id]
		var w: String = "bonds.json " + id
		check(recruits.has(id), "%s: not a recruit" % w)
		for role in c.get("likes", []) + c.get("dislikes", []):
			var parts := str(role).split(":")
			check(Empire.ROLE_NAMES.has(parts[0]), "%s: unknown role %s" % [w, role])
			if parts.size() > 1 and parts[0] == "staff":
				check(buildings.has(parts[1]), "%s: unknown building in %s" % [w, role])
		var ranks := {}
		for s in c.get("scenes", []):
			ranks[int(s["rank"])] = true
			_lines("%s rank %d scene" % [w, int(s["rank"])], s.get("lines", []))
			for ch in s.get("choice", []):
				_lines("%s rank %d choice" % [w, int(s["rank"])], ch.get("reply", []))
		for r in range(1, 6):
			check(ranks.has(r), "%s: no rank %d scene" % [w, r])
		for r in c.get("perks", {}):
			check(str(c["perks"][r].get("name", "")) != "", "%s: perk at rank %s has no name" % [w, r])


# ------------------------------------------------------------------ world

func test_provinces_and_factions() -> void:
	var ps: Array = D["provinces.json"]["provinces"]
	_unique("provinces.json", ps)
	var factions := _ids(D["factions.json"]["factions"])
	_unique("factions.json", D["factions.json"]["factions"])
	for p in ps:
		var w: String = "provinces.json " + str(p["id"])
		check(str(p["owner"]) in OWNERS or factions.has(p["owner"]), "%s: unknown owner %s" % [w, p["owner"]])
		check(Empire.STAT_NAMES.has(p.get("favors", "")), "%s: favours unknown stat %s" % [w, p.get("favors")])
		_res_keys(w + " output", p.get("output", {}))
	# Regions and biomes (issue #53).
	var pj: Dictionary = D["provinces.json"]
	var regions := _ids(pj.get("regions", []))
	_unique("provinces.json regions", pj.get("regions", []))
	check(not regions.is_empty(), "provinces.json: no regions")
	check(regions.values().any(func(r): return r.get("open", false)), "provinces.json: no region is open at the start")
	var biomes: Dictionary = pj.get("biomes", {})
	for rid in regions:
		var r: Dictionary = regions[rid]
		var w: String = "provinces.json region " + rid
		check(str(r.get("name", "")) != "" and str(r.get("hint", "")) != "", "%s: needs a name and a hint" % w)
		check(ps.any(func(p): return p.get("region", "") == rid), "%s: has no provinces" % w)
		var lp: Array = r.get("label", [0.5, 0.5])
		check(lp.size() == 2 and float(lp[0]) >= 0.0 and float(lp[0]) <= 1.0 and float(lp[1]) >= 0.0 and float(lp[1]) <= 1.0, "%s: label off the map" % w)
		if r.has("opens_when"):
			check(typeof(r["opens_when"]) == TYPE_DICTIONARY, "%s: opens_when must be Story conditions" % w)
	for bid in biomes:
		for m in biomes[bid].get("maps", []):
			check(FileAccess.file_exists("res://maps/%s.txt" % m), "provinces.json biome %s: map %s missing" % [bid, m])
	for p in ps:
		var w: String = "provinces.json " + str(p["id"])
		check(regions.has(p.get("region", "")), "%s: unknown region %s" % [w, p.get("region")])
		check(biomes.has(p.get("biome", "")), "%s: unknown biome %s" % [w, p.get("biome")])
		var pos: Array = p.get("pos", [])
		check(pos.size() == 2 and float(pos[0]) > 0.0 and float(pos[0]) < 1.0 and float(pos[1]) > 0.0 and float(pos[1]) < 1.0, "%s: pos off the map" % w)
	for b in D["story.json"].get("beats", []):
		for step in str(b.get("then", "")).split(",", false):
			if step.strip_edges().begins_with("open_region:"):
				check(regions.has(step.strip_edges().substr(12)), "story.json beat %s: opens unknown region %s" % [b.get("talk", "?"), step])
	for fid in factions:
		var f: Dictionary = factions[fid]
		var w: String = "factions.json " + fid
		check(_provinces().has(f.get("province", "")), "%s: province %s missing" % [w, f.get("province")])
		check(Empire.STAT_NAMES.has(f.get("respects", "")), "%s: respects unknown stat %s" % [w, f.get("respects")])
		for deal in f.get("deals", {}):
			check(deal in Empire.DEAL_ORDER, "%s: unknown deal %s" % [w, deal])
			_res_keys("%s deal %s cost" % [w, deal], f["deals"][deal].get("cost", {}))


func test_buildings_and_research() -> void:
	_unique("buildings.json", D["buildings.json"]["buildings"])
	for b in D["buildings.json"]["buildings"]:
		check(Empire.STAT_NAMES.has(b.get("stat", "")), "buildings.json %s: unknown stat %s" % [b["id"], b.get("stat")])
		for lv in b.get("levels", []):
			_res_keys("buildings.json %s cost" % b["id"], lv.get("cost", {}))
	var branches := _ids(D["research.json"]["branches"])
	_unique("research.json", D["research.json"]["nodes"])
	for n in D["research.json"]["nodes"]:
		check(branches.has(n.get("branch", "")), "research.json %s: unknown branch %s" % [n["id"], n.get("branch")])
		_res_keys("research.json %s cost" % n["id"], n.get("cost", {}))


func test_expeditions() -> void:
	var e: Dictionary = D["expeditions.json"]
	_unique("expeditions.json", e["jobs"])
	var recruits := _recruits()
	for j in e["jobs"]:
		var w: String = "expeditions.json " + str(j["id"])
		check(_provinces().has(j.get("province", "")), "%s: province %s missing" % [w, j.get("province")])
		for s in j.get("stats", {}):
			check(Empire.STAT_NAMES.has(s), "%s: unknown stat %s" % [w, s])
		_res_keys(w + " reward", j.get("reward", {}))
		if j.has("recruit") and str(j["recruit"]) != "":
			check(recruits.has(j["recruit"]), "%s: recruit %s missing" % [w, j["recruit"]])
		if j.has("who"):
			check(recruits.has(j["who"]), "%s: recruit %s missing" % [w, j["who"]])


func test_missions_and_enemies() -> void:
	var ms: Array = D["missions.json"]["missions"]
	_unique("missions.json", ms)
	var kinds: Dictionary = D["enemies.json"]["kinds"]
	var talks := _talks()
	for m in ms:
		var w: String = "missions.json " + str(m["id"])
		check(_provinces().has(m.get("province", "")), "%s: province %s missing" % [w, m.get("province")])
		check(FileAccess.file_exists(m.get("map", "")), "%s: map %s missing" % [w, m.get("map")])
		check(str(m.get("objective", {}).get("kind", "kills")) in OBJECTIVE_KINDS, "%s: unknown objective kind" % w)
		for k in m.get("enemies", {}):
			check(kinds.has(k), "%s: unknown enemy %s" % [w, k])
		_res_keys(w + " rewards", m.get("rewards", {}))
		_res_keys(w + " loot", m.get("loot", {}))
		if m.has("intro"):
			check(talks.has(m["intro"]), "%s: intro talk %s missing" % [w, m["intro"]])
		if m.has("scene"):
			check(ResourceLoader.exists(m["scene"]), "%s: scene %s missing" % [w, m["scene"]])
	for k in kinds:
		var info: Dictionary = kinds[k]
		check(EnemyKinds.SCRIPTS.has(info.get("script", k)), "enemies.json %s: no behaviour script" % k)
		check(D["sprites.json"]["sprites"].has(info.get("sprite", k)), "enemies.json %s: no sprite set %s" % [k, info.get("sprite", k)])
	for r in D["enemies.json"]["rosters"]:
		check(r == "default" or _provinces().has(r), "enemies.json roster %s: not a province" % r)
		for k in D["enemies.json"]["rosters"][r]:
			check(kinds.has(k), "enemies.json roster %s: unknown enemy %s" % [r, k])
	# A target is a province id or a rule that BlankPlans.pick_target() has a branch for.
	var picker := FileAccess.get_file_as_string("res://scripts/blank_plans.gd")
	for pl in D["blank.json"]["plans"]:
		var target := str(pl.get("target", ""))
		check(_provinces().has(target) or picker.contains("\"%s\":" % target),
			"blank.json %s: target %s is neither a province nor a rule in blank_plans.gd pick_target()" % [pl["id"], target])
		check(pl.get("counter", "") in ["", "governor", "lamp"], "blank.json %s: unknown counter %s" % [pl["id"], pl.get("counter")])


## Mission variety (issue #113): the Raid and Salvage tuning, the personal missions and the map pool.
func test_mission_types() -> void:
	var mt: Dictionary = D["mission_types.json"]
	var kinds: Dictionary = D["enemies.json"]["kinds"]
	var factions := _ids(D["factions.json"]["factions"])
	for fid in mt["raid"]["factions"]:
		var fc: Dictionary = mt["raid"]["factions"][fid]
		var w: String = "mission_types.json raid " + fid
		check(factions.has(fid), "%s: not a faction" % w)
		for k in fc.get("guards", {}):
			check(kinds.has(k), "%s: unknown guard %s" % [w, k])
		_res_keys(w + " cache", fc.get("cache", {}), true)
		for r in fc.get("rival", {}):
			check(factions.has(r), "%s: rival %s is not a faction" % [w, r])
		check(str(fc.get("brief", "")).count("%d") == 2, "%s: brief needs two %%d (need, caches)" % w)
	_res_keys("mission_types.json raid rewards", mt["raid"].get("rewards", {}))
	_res_keys("mission_types.json salvage pile", mt["salvage"].get("pile", {}), true)
	_res_keys("mission_types.json salvage rewards", mt["salvage"].get("rewards", {}))
	check(int(mt["raid"]["need"]) <= int(mt["raid"]["caches"]), "raid: needs more caches than there are")
	check(int(mt["salvage"]["need"]) <= int(mt["salvage"]["caches"]), "salvage: needs more piles than there are")


func test_personal_missions() -> void:
	var pm: Dictionary = D["personal.json"]
	_unique("personal.json", pm["missions"])
	var kinds: Dictionary = D["enemies.json"]["kinds"]
	var factions := _ids(D["factions.json"]["factions"])
	var recruits := _recruits()
	var talks := _talks()
	var who := {}
	for m in pm["missions"]:
		var w: String = "personal.json " + str(m["id"])
		var rid := str(m.get("who", ""))
		check(recruits.has(rid), "%s: who %s is not a recruit" % [w, rid])
		check(not who.has(rid), "%s: %s has two personal missions" % [w, rid])
		who[rid] = true
		check(D["bonds.json"]["cast"].has(rid), "%s: %s has no bond" % [w, rid])
		check(_provinces().has(m.get("province", "")), "%s: province %s missing" % [w, m.get("province")])
		check(FileAccess.file_exists(m.get("map", "")), "%s: map %s missing" % [w, m.get("map")])
		var spots: Dictionary = Area.header(m.get("map", "")).get("spots", {})
		for k in m.get("enemies", {}):
			check(kinds.has(k), "%s: unknown enemy %s" % [w, k])
		_res_keys(w + " rewards", m.get("rewards", {}))
		for fid in m.get("standing", {}):
			check(factions.has(fid), "%s: standing for unknown faction %s" % [w, fid])
		check(int(m.get("threat", 0)) >= 1 and int(m.get("threat", 0)) <= 5, "%s: threat must be 1-5" % w)
		var steps: Array = m.get("steps", [])
		check(steps.size() >= 4, "%s: too few steps for a mission" % w)
		check(steps.any(func(st): return st.get("do", "") == "exit") or steps[-1].get("do", "") == "talk", "%s: no way home" % w)
		for st in steps:
			var sw := "%s step %s" % [w, st.get("do", "?")]
			check(str(st.get("do", "")) in STEP_KINDS, "%s: unknown step" % sw)
			if st.get("do", "") == "talk":
				check(talks.has(st.get("talk", "")), "%s: talk %s missing" % [sw, st.get("talk")])
			else:
				check(str(st.get("label", "")) != "", "%s: no HUD label" % sw)
			var ats: Array = st["at"] if st.get("at") is Array and st["at"].size() > 0 and st["at"][0] is String else ([st["at"]] if st.has("at") and st["at"] is String else [])
			for a in ats:
				check(a == "start" or spots.has(a), "%s: map has no @spot %s" % [sw, a])
			for k in st.get("spawn", {}):
				check(kinds.has(k), "%s: unknown enemy %s" % [sw, k])
			if st.has("elite"):
				check(kinds.has(st["elite"].get("kind", "")), "%s: unknown elite kind" % sw)
			if st.get("by", "party") == "escort":
				check(recruits[rid].get("tier", "") != "field", "%s: a field hero is in the party, not an escort" % sw)
			for line in st.get("banter", []) + st.get("done_banter", []):
				_lines(sw + " banter", [line])
	for rid in D["bonds.json"]["cast"]:
		check(who.has(rid), "bonds.json %s: no personal mission in personal.json" % rid)


func test_map_pool_has_spots() -> void:
	for b in D["provinces.json"]["biomes"]:
		var pool: Array = D["provinces.json"]["biomes"][b].get("maps", [])
		check(pool.is_empty() or pool.size() >= 3, "biome %s: %d map layouts, want 3 or more" % [b, pool.size()])
		for mid in pool:
			var path := "res://maps/%s.txt" % mid
			check(FileAccess.file_exists(path), "biome %s: map %s missing" % [b, path])
			var sp: Dictionary = Area.header(path).get("spots", {})
			for k in ["ward", "blot", "rescue", "spawn"]:
				check(sp.has(k), "%s: no @spot %s" % [mid, k])
			check(sp.get("cache", []).size() >= 5, "%s: only %d cache spots" % [mid, sp.get("cache", []).size()])


# ------------------------------------------------------------------ words and pictures

func test_dialogue_and_story() -> void:
	var dl: Dictionary = D["dialogue.json"]
	var recruits := _recruits()
	var talks := _talks()
	for id in talks:
		var t = talks[id]
		_lines("talk " + id, t.get("lines", []) if typeof(t) == TYPE_DICTIONARY else t)
	for id in dl["first_talk"]:
		check(recruits.has(id), "dialogue.json first_talk: %s is not a recruit" % id)
		check(talks.has(dl["first_talk"][id]), "dialogue.json first_talk %s: talk %s missing" % [id, dl["first_talk"][id]])
	for id in dl["events"]:
		_lines("event " + id, dl["events"][id].get("lines", []))
	for map in dl["banter"]:
		check(FileAccess.file_exists("res://maps/%s.txt" % map), "dialogue.json banter: no map maps/%s.txt" % map)
		for z in dl["banter"][map]:
			_lines("banter %s %s" % [map, z.get("id", "?")], z.get("lines", []))
			for n in z.get("needs", []):
				check(recruits.has(n), "banter %s %s: needs unknown %s" % [map, z.get("id"), n])
	var missions := _ids(D["missions.json"]["missions"])
	for b in D["story.json"]["beats"]:
		check(talks.has(b.get("talk", "")), "story.json beat: talk %s missing" % b.get("talk"))
		var then := str(b.get("then", ""))
		if then.begins_with("launch:"):
			check(missions.has(then.trim_prefix("launch:")), "story.json beat %s: mission %s missing" % [b.get("talk"), then])
		_conditions("story.json beat " + str(b.get("talk")), b.get("when", {}), missions, talks, recruits)
	for g in D["story.json"]["goals"]:
		_conditions("story.json goal " + str(g.get("text")), g.get("done", {}), missions, talks, recruits)
		_conditions("story.json goal " + str(g.get("text")), g.get("show", {}), missions, talks, recruits)


func _conditions(w: String, c: Dictionary, missions: Dictionary, talks: Dictionary, recruits: Dictionary) -> void:
	for mid in c.get("cleared", []) + c.get("not_cleared", []):
		check(missions.has(mid), "%s: mission %s missing" % [w, mid])
	for tid in c.get("seen", []):
		check(talks.has(tid), "%s: talk %s missing" % [w, tid])
	for rid in c.get("joined", []):
		check(recruits.has(rid), "%s: recruit %s missing" % [w, rid])
	for pid in c.get("owns", []):
		check(_provinces().has(pid), "%s: province %s missing" % [w, pid])


func test_sprite_sets_have_their_frames() -> void:
	var sprites: Dictionary = D["sprites.json"]["sprites"]
	for id in sprites:
		var s: Dictionary = sprites[id]
		for anim in s.get("anims", {}):
			for dir in s["anims"][anim].get("dirs", []):
				var p := "res://assets/sprites/%s/%s_%s.png" % [id, anim, dir]
				check(ResourceLoader.exists(p), "sprites.json %s: %s missing" % [id, p])


func test_maps_load() -> void:
	for f in DirAccess.get_files_at("res://maps/"):
		if f.ends_with(".txt"):
			var text := FileAccess.get_file_as_string("res://maps/" + f)
			check(text.strip_edges() != "", "maps/%s is empty" % f)


# ------------------------------------------------------------------ finished art and text (issue #111)

## Everyone who can speak has a portrait, so the code-drawn safety-net bust never shows. Letters read
## aloud ("stage": "letter") stand on stage as a sheet of paper instead.
func test_every_speaker_has_a_portrait() -> void:
	var speakers := {}
	speakers.merge(D["dialogue.json"]["speakers"])
	speakers.merge(D["story.json"]["speakers"])
	speakers.merge(D["personal.json"]["speakers"])
	for id in _recruits():
		speakers[id] = {}
	for id in speakers:
		if str(speakers[id].get("stage", "")) == "letter":
			continue
		check(_res("res://assets/portraits/%s.png" % id), "speaker %s: no portrait assets/portraits/%s.png" % [id, id])


## Every building has an art pass sprite for every level, and the Command Table has its sprite.
func test_every_building_level_has_art() -> void:
	for b in D["buildings.json"]["buildings"]:
		var look := str(b.get("look", ""))
		if look == "table":
			check(_res("res://assets/props/command_table.png"), "buildings.json %s: no assets/props/command_table.png" % b["id"])
			continue
		for lv in range(1, b.get("levels", []).size() + 1):
			var p := "res://assets/buildings/%s_%d.png" % [look, lv]
			check(_res(p), "buildings.json %s: level %d has no art %s" % [b["id"], lv, p])


const UNFINISHED := "(?i)\\bMVP\\b|placeholder|later update|coming soon|not implemented|lorem ipsum|\\bTODO\\b|\\bTBD\\b"


func _scan_text(where: String, v, re: RegEx, what := "unfinished text") -> void:
	match typeof(v):
		TYPE_STRING:
			var m := re.search(v)
			check(m == null, "%s: %s '%s' in \"%s\"" % [where, what, m.get_string() if m else "", v.left(80)])
		TYPE_ARRAY:
			for i in v.size():
				_scan_text(where, v[i], re, what)
		TYPE_DICTIONARY:
			for k in v:
				if not str(k).begins_with("_"):  # _comment keys are notes for us, not for players
					_scan_text("%s.%s" % [where, k], v[k], re, what)


## Names AI models overuse, and names retired by the naming pass (#158). docs/NAMING.md section 1.1.
const BANNED_NAMES := "\\b(Elara|Elora|Seraphina|Seraphine|Lyra|Lysandra|Lysandre|Kael|Kaelen|Thorne|Vex|Vesper|Nyx|Aria|Aurora|Aurore|Elowen|Isolde|Rowan|Wren|Sable|Raven|Silas|Corvin|Corvus|Caelum|Orion|Zephyr|Nova|Ember|Sylas|Aldric|Eldric|Cedric|Alaric|Theron|Lucian|Damien|Valerius|Mira|Mirabel|Liora|Celeste|Selene|Astra|Calla|Ophelia|Vivienne|Evander|Thalia|Briar|Oriel|Kestrel|Morrigan|Velvette|Abeyance|Nightjar|Undermoss|Quoin|Hesper|Inkmere|Quillpine|Ledgerside|Saltgrave|Rosewine|Candlemere|Lampwick)\\b"


## No player-facing text uses a banned or retired name (docs/NAMING.md): data/ values and script strings.
func test_no_banned_names() -> void:
	var re := RegEx.create_from_string(BANNED_NAMES)
	for f in D:
		_scan_text(f, D[f], re, "banned name (docs/NAMING.md)")
	var lit := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string("res://scripts/" + f).split("\n"):
			n += 1
			if line.strip_edges().begins_with("#"):
				continue
			for m in lit.search_all(line):
				var bad := re.search(m.get_string())
				check(bad == null, "scripts/%s:%d: banned name '%s' (docs/NAMING.md)" % [f, n, bad.get_string() if bad else ""])


## No player-facing text says placeholder, MVP, "later update" and the like: in data/ (all values but
## _comment notes) and in string literals in scripts/ (comments are notes for us and are skipped).
func test_no_unfinished_text() -> void:
	var re := RegEx.create_from_string(UNFINISHED)
	for f in D:
		_scan_text(f, D[f], re)
	var lit := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string("res://scripts/" + f).split("\n"):
			n += 1
			var code := line.strip_edges()
			if code.begins_with("#"):
				continue
			for m in lit.search_all(line):
				var s := m.get_string()
				var bad := re.search(s)
				check(bad == null, "scripts/%s:%d: unfinished text '%s' in %s" % [f, n, bad.get_string() if bad else "", s.left(80)])
