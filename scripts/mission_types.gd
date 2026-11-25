class_name MissionTypes
extends RefCounted
## The mission types the Command Table offers on its own (#51, #113), built at runtime from the empire's
## state rather than written into data/missions.json:
##   Defense  - a surge is gathering against a province: go and hold the line.
##   Reclaim  - a province has been erased: push in, break its Blot, pay Ink to rewrite it.
##   Rescue   - someone the rumours talk about is stuck somewhere dangerous: fetch them in person.
##   Raid     - a faction's stores sit on land next to yours: grab them before the garrison comes (#113).
##   Salvage  - the Blank is eating a province: pull what it has not finished out of its edge (#113).
##   Personal - a bonded character's own story, at bond rank 4 (PersonalMissions, #113).
##
## Each one is an ordinary mission dict (the same shape Missions.launch takes) with an "objective" that
## Objective hands to MissionObjectives, plus "effects": the type's change to the empire, applied by
## apply() when the results screen settles the mission. Tuning lives in data/mission_types.json.

const DATA := "res://data/mission_types.json"
const MAP := "res://maps/frayed_meadow.txt"
## Each province's biome has a pool of maps (data/provinces.json "biomes"), three layouts each, made by
## tools/make_biomes.py. Every map lists its objective spots in @spot lines; vary() picks among them.
const RECLAIM_INK := 3
const RECLAIM_FRAY := 60  # what a rewritten province starts at: thin, but standing
const DEFENSE_FRAY := -5  # the line you held stays a little firmer
const TYPE_NAMES := {"defense": "Defence", "reclaim": "Reclaim", "rescue": "Rescue", "raid": "Raid",
	"salvage": "Salvage", "personal": "Personal"}
const TYPE_COLORS := {"defense": Color("ff8a6a"), "reclaim": Color("eeebe2"), "rescue": Color("8ad1ff"),
	"raid": Color("f0b54a"), "salvage": Color("9fe0b0"), "personal": Color("f29bd0")}

## Fallback spots for a map with no @spot lines (the original Frayed Meadow layout). The Blank's wall is at tile 69.
const WARD_AT := [50, 31]
const BLOT_AT := [64, 30]
const RESCUE_SPOTS := [[60, 9], [60, 50], [59, 22]]
const BLANK_SHIFT := 3  # the wall starts up to this many tiles east or west of the map's own column
const BLANK_GAP := 5  # ...but never closer than this to anything the mission needs

static var _data := {}



## What a Reclaim costs and leaves behind. The Abbey's Second Copy (research, issue #28) writes it back cheaper
## and stronger.
static func reclaim_ink() -> int:
	return RECLAIM_INK - (1 if Empire.has_research("second_copy") else 0)


static func reclaim_fray() -> int:
	return RECLAIM_FRAY - (15 if Empire.has_research("second_copy") else 0)

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = Loc.load_json(DATA)
		_data = parsed if parsed is Dictionary else {}
	return _data


## The map for a province's type missions: one from its biome's pool, the same all day for the same mission
## (so the briefing and the launch agree), and usually a different one on another day.
static func map_for(pid: String, salt := "") -> String:
	var pool := Empire.territory().map_pool(pid).filter(func(m): return ResourceLoader.exists(m) or FileAccess.file_exists(m))
	if pool.is_empty():
		return MAP
	return pool[absi(hash(pid + salt + str(Empire.day))) % pool.size()]


## A seeded dice roll for laying out one mission today: same id, same day, same layout.
static func _rng(id: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(id + ":" + str(Empire.day))
	return r


## Lays mission m out on a map from its province's pool (#113): which map, where its spots fall, where the Blank's
## wall starts and which spawn points wake up. Returns the spots picked ({"ward": [x, y], "caches": [[x, y]...], ...}).
## The layout goes in m["layout"] and main.gd applies it when the map loads.
static func vary(m: Dictionary, pid: String) -> Dictionary:
	var id: String = m.get("id", pid)
	if not m.has("map"):
		m["map"] = map_for(pid, id)
	var hdr := Area.header(m["map"])
	var sp: Dictionary = hdr.get("spots", {})
	var rng := _rng(id)
	var out := {}
	out["ward"] = _pick(sp.get("ward", []), rng, WARD_AT)
	out["blot"] = _pick(sp.get("blot", []), rng, BLOT_AT)
	out["rescue"] = _pick(sp.get("rescue", []), rng, RESCUE_SPOTS[rng.randi() % RESCUE_SPOTS.size()])
	var caches: Array = sp.get("cache", []).map(func(v): return [v.x, v.y])
	_shuffle(caches, rng)
	out["caches"] = caches
	var spawns: Array = sp.get("spawn", []).map(func(v): return [v.x, v.y])
	_shuffle(spawns, rng)
	var blank := int(hdr.get("blank", -1))
	var layout := {"spawns": spawns.slice(0, maxi(3, spawns.size() - rng.randi_range(1, 3)))}
	if blank > 0:
		layout["blank"] = blank + rng.randi_range(-BLANK_SHIFT, BLANK_SHIFT)
	m["layout"] = layout
	return out


## Makes sure the Blank's wall starts east of every spot the mission uses.
static func clear_blank(m: Dictionary, tiles: Array) -> void:
	var layout: Dictionary = m.get("layout", {})
	if not layout.has("blank"):
		return
	var east := 0
	for t in tiles:
		east = maxi(east, int(t[0]))
	layout["blank"] = maxi(int(layout["blank"]), east + BLANK_GAP)


static func _pick(opts: Array, rng: RandomNumberGenerator, fallback: Array) -> Array:
	if opts.is_empty():
		return fallback
	var v: Vector2i = opts[rng.randi() % opts.size()]
	return [v.x, v.y]


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## Every type-mission on offer for a province right now, each with a "blocker"
## ("" = it can be launched). Defense first: it has a deadline. Personal next: someone is waiting.
static func for_province(pid: String) -> Array:
	var p := Empire.territory().find(pid)
	if p.is_empty() or not Empire.province_open(p):
		return []
	var out := []
	if Empire.surge.get("id", "") == pid and p["owner"] != "erased":
		out.append(defense(p))
	out.append_array(PersonalMissions.for_province(pid))
	if p["owner"] == "erased":
		out.append(reclaim(p))
	for jid in Empire.job_ids():
		var j := Empire.job(jid)
		if j.get("kind", "") == "Rescue" and j.get("province", "") == pid and j.get("recruit", "") != "":
			out.append(rescue(jid))
	if raid_open(p) >= 0:
		out.append(raid(p))
	if salvage_open(p) >= 0:
		out.append(salvage(p))
	return out


# ---------------------------------------------------------------- Defense, Reclaim, Rescue (#51)

static func defense(p: Dictionary) -> Dictionary:
	var days := Empire.surge_days_left()
	var hard := clampi(int(p["fray"]) / 25, 0, 3)  # worn-thin land is harder to hold
	var m := {
		"id": "defense_" + p["id"], "type": "defense", "effects": true, "province": p["id"],
		"name": Loc.t("Defend %s") % p["name"], "threat": 2 + hard / 2 + (1 if days <= 1 else 0),
		"brief": Loc.n("The Blank is gathering against %s. Hold the wardstone until the surge breaks and it never lands. Every Nibbler you disperse pushes the white back a little. Lands in %d day if you do nothing.", "The Blank is gathering against %s. Hold the wardstone until the surge breaks and it never lands. Every Nibbler you disperse pushes the white back a little. Lands in %d days if you do nothing.", days) \
			% [p["name"], days],
		"rewards": {"renown": 1, "supplies": 4},
		"blocker": "",
	}
	var at := vary(m, p["id"])
	clear_blank(m, [at["ward"]])
	m["objective"] = {"kind": "defense", "seconds": 70 + 10 * hard, "ward": at["ward"], "ward_hp": 100,
		"creep": 3.0 + hard, "push": 7.0, "spawn_every": maxf(2.0, 3.2 - 0.3 * hard)}
	return m


static func reclaim(p: Dictionary) -> Dictionary:
	var blocker := ""
	var t := Empire.territory()
	var reachable := false
	for n in t.neighbors[p["index"]]:
		reachable = reachable or t.provinces[n]["owner"] != "erased"
	if not reachable:
		blocker = Loc.t("nothing standing borders it: reclaim a neighbour first")
	elif int(Empire.res.get("ink", 0)) < reclaim_ink():
		blocker = Loc.t("needs %d Ink to rewrite (you have %d)") % [reclaim_ink(), int(Empire.res.get("ink", 0))]
	var m := {
		"id": "reclaim_" + p["id"], "type": "reclaim", "effects": true, "province": p["id"],
		"name": Loc.t("Reclaim %s") % p["name"], "threat": 3,
		"brief": Loc.t("Push into the white and break the Blot that holds %s. It spits Nibblers while it lives. Win, and %d Ink rewrites the land: it comes back unclaimed at %d Fray.") \
			% [p["name"], reclaim_ink(), reclaim_fray()],
		"cost_text": Loc.t("%d Ink on success") % reclaim_ink(),
		"rewards": {"renown": 2},
		"blocker": blocker,
	}
	var at := vary(m, p["id"])
	m["objective"] = {"kind": "reclaim", "blot": at["blot"], "hp": 220, "spawn_every": 4.0}
	return m


static func rescue(jid: String) -> Dictionary:
	var j := Empire.job(jid)
	var rid: String = j["recruit"]
	var p := Empire.territory().find(j["province"])
	var blocker := ""
	if p.get("owner", "") == "erased":
		blocker = Loc.t("%s has been erased") % p.get("name", "?")
	elif not Empire.expedition_running(jid).is_empty():
		blocker = Loc.t("a squad is already out after them")
	var m := {
		"id": "rescue_" + rid, "type": "rescue", "effects": true, "province": j["province"], "job": jid,
		"name": Loc.t("Rescue: %s") % Empire.recruit(rid).get("name", rid), "threat": clampi(int(j.get("danger", 2)), 1, 5),
		"brief": Loc.t("%s Go yourself instead of sending a squad: find %s before the white closes over them, then bring them back to where you came in.") \
			% [j.get("blurb", ""), Empire.short_name(rid)],
		"rewards": _flat(j.get("reward", {})),
		"blocker": blocker,
	}
	var at := vary(m, str(j["province"]))
	clear_blank(m, [at["rescue"]])
	m["objective"] = {"kind": "rescue", "who": rid, "at": at["rescue"], "creep": 2.0, "guards": 4}
	return m


## Expedition rewards can be [min, max] ranges; a mission pays the middle.
static func _flat(r: Dictionary) -> Dictionary:
	var out := {}
	for k in r:
		out[k] = (int(r[k][0]) + int(r[k][1])) / 2 if r[k] is Array else int(r[k])
	return out


# ---------------------------------------------------------------- Raid and Salvage (#113)

## The last day a Raid or Salvage chance stays open in this province (-1 = none right now). Each province
## gets one every window.period days for window.open days, on its own phase, then rests after a visit.
static func window_until(kind: String, pid: String) -> int:
	if Empire.day < int(Empire.mission_ready.get(kind + ":" + pid, 0)):
		return -1
	var w: Dictionary = data().get("window", {})
	var period := maxi(int(w.get("period", 5)), 1)
	var open := clampi(int(w.get("open", 3)), 1, period)
	var pos := posmod(Empire.day + absi(hash(kind + pid)), period)
	if pos >= open:
		return -1
	return Empire.day + (open - 1 - pos)


## Can this faction-held province be raided now? Returns the last day it is offered, or -1.
static func raid_open(p: Dictionary) -> int:
	var fid := str(p.get("owner", ""))
	if not data().get("raid", {}).get("factions", {}).has(fid):
		return -1
	if not _borders_yours(p):
		return -1
	return window_until("raid", p["id"])


## Can the party go salvaging here now? Your land or unclaimed land the Blank is chewing on.
static func salvage_open(p: Dictionary) -> int:
	if not p.get("owner", "") in ["you", "free"]:
		return -1
	var t := Empire.territory()
	var near_white := false
	for n in t.neighbors[p["index"]]:
		near_white = near_white or t.provinces[n]["owner"] == "erased"
	if int(p.get("fray", 0)) < int(data().get("salvage", {}).get("min_fray", 35)) and not near_white:
		return -1
	if p["owner"] == "free" and not _borders_yours(p):
		return -1
	return window_until("salvage", p["id"])


static func _borders_yours(p: Dictionary) -> bool:
	var t := Empire.territory()
	for n in t.neighbors[p["index"]]:
		if t.provinces[n]["owner"] == "you":
			return true
	return false


static func raid(p: Dictionary) -> Dictionary:
	var cfg: Dictionary = data().get("raid", {})
	var fid := str(p["owner"])
	var fc: Dictionary = cfg["factions"][fid]
	var tier := Empire.tier_of(fid)
	var blocker := ""
	if Empire.tier_rank(tier) >= Empire.tier_rank("friendly"):
		blocker = Loc.t("the %s are %s: a raid would end that") % [Empire.faction(fid).get("short", fid), Empire.tier_name(tier)]
	var n := int(cfg.get("caches", 5))
	var need := int(cfg.get("need", 3))
	var threat := 2 + (1 if tier == "hostile" else 0) + (1 if int(p.get("fray", 0)) >= 50 else 0)
	var m := {
		"id": "raid_" + p["id"], "type": "raid", "effects": true, "province": p["id"], "faction": fid,
		"name": Loc.t("Raid: %s") % fc.get("name", "stores"), "threat": threat,
		"brief": str(fc.get("brief", Loc.t("Grab at least %d of the %s and get out."))) % [need, counted(str(fc.get("noun", "cache")), n)],
		"enemies": fc.get("guards", {"sellsword": 1}),
		"rewards": cfg.get("rewards", {}),
		"reward_text": Loc.t("%d to %s, each %s") % [need, counted(str(fc.get("noun", "cache")), n), _range_text(fc.get("cache", {}))],
		"cost_text": Loc.t("%s standing %d if unseen, %d once the alarm is up") % [Empire.faction(fid).get("short", fid), int(fc.get("quiet", -4)), int(fc.get("loud", -8))],
		"until_day": raid_open(p),
		"blocker": blocker,
	}
	var at := vary(m, p["id"])
	var caches: Array = at["caches"].slice(0, n)
	clear_blank(m, caches)
	m["objective"] = {"kind": "raid", "caches": caches, "need": mini(need, caches.size()), "seconds": float(cfg.get("seconds", 170)),
		"alarm_cap": float(cfg.get("alarm_cap", 45)), "open_time": float(cfg.get("open_time", 1.6)), "contents": with_region(fc.get("cache", {}), p, cfg.get("region_cache", {}), true),
		"per_cache": int(fc.get("per_cache", 2)), "alarm_seen": float(cfg.get("alarm_seen", 9.0)), "alarm_open": float(cfg.get("alarm_open", 14.0)),
		"alarm_fall": float(cfg.get("alarm_fall", 3.0)), "reinforce_every": float(cfg.get("reinforce_every", 6.5))}
	m["respawn"] = false  # the Blank does not pour out on a raid: the garrison is the danger
	return m


static func salvage(p: Dictionary) -> Dictionary:
	var cfg: Dictionary = data().get("salvage", {})
	var n := int(cfg.get("caches", 5))
	var need := int(cfg.get("need", 3))
	var fray := int(p.get("fray", 0))
	var m := {
		"id": "salvage_" + p["id"], "type": "salvage", "effects": true, "province": p["id"],
		"name": Loc.t("Salvage: %s") % p["name"], "threat": clampi(1 + fray / 30, 1, 4),
		"brief": str(cfg.get("brief", Loc.t("Salvage %s: %d of the %s."))) % [p["name"], need, counted("pile", n)],
		"rewards": cfg.get("rewards", {}),
		"reward_text": Loc.t("%d to %s, each %s (more right at the white)") % [need, counted("pile", n), _range_text(cfg.get("pile", {}))],
		"until_day": salvage_open(p),
		"blocker": "",
	}
	var at := vary(m, p["id"])
	# The piles nearest the Blank: the ones worth the risk.
	var caches: Array = at["caches"].duplicate()
	caches.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	caches = caches.slice(0, n)
	var layout: Dictionary = m["layout"]
	if layout.has("blank"):
		var east := 0
		for c in caches:
			east = maxi(east, int(c[0]))
		layout["blank"] = east + 4  # the white is right behind the best pile
	m["objective"] = {"kind": "salvage", "caches": caches, "need": mini(need, caches.size()),
		"open_time": float(cfg.get("open_time", 2.0)), "contents": with_region(cfg.get("pile", {}), p, cfg.get("region_pile", {})), "near_bonus": float(cfg.get("near_bonus", 1.0)),
		"creep": float(cfg.get("creep", 4.0)) + float(cfg.get("creep_per_fray", 0.6)) * fray / 10.0, "push": float(cfg.get("push", 4.0)), "grace": float(cfg.get("grace", 6.0))}
	return m


## A cache's or pile's contents plus the extras for the province's region (region_cache / region_pile,
## issue #138), so a raid or a salvage in the Abbey or on the Causeway turns up that chapter's Forge
## materials. only_if_missing: skip the extras when the contents already hold one of that region's
## materials (the Abbey's own undercroft is full of its silver already).
static func with_region(contents: Dictionary, p: Dictionary, extras: Dictionary, only_if_missing := false) -> Dictionary:
	var region := str(p.get("region", ""))
	var more: Dictionary = extras.get(region, {})
	if more.is_empty():
		return contents
	if only_if_missing:
		var mats: Dictionary = Armory.mats_data().get("materials", {})
		for k in contents:
			if str(mats.get(k, {}).get("region", "")) == region:
				return contents
	var out := contents.duplicate()
	for k in more:
		if not out.has(k):
			out[k] = more[k]
	return out


## {"gilt": [14, 22], "supplies": [2, 5]} -> "14-22 Gilt, 2-5 Supplies".
## "5 boxes": a raid's or salvage's loot count, by the noun id in data/mission_types.json.
static func counted(noun: String, amount: int) -> String:
	match noun:
		"box":
			return Loc.count("%d box", "%d boxes", amount)
		"crate":
			return Loc.count("%d crate", "%d crates", amount)
		"chest":
			return Loc.count("%d chest", "%d chests", amount)
		"pile":
			return Loc.count("%d pile", "%d piles", amount)
		"rack":
			return Loc.count("%d rack", "%d racks", amount)
	return Loc.count("%d cache", "%d caches", amount)


static func _range_text(d: Dictionary) -> String:
	var parts := []
	for k in ["gilt", "supplies", "ink", "insight", "renown"]:
		if not d.has(k):
			continue
		var v = d[k]
		var lo := int(v[0]) if v is Array else int(v)
		var hi := int(v[1]) if v is Array else int(v)
		var nm: String = Loc.t(Empire.RES_NAMES.get(k, k))
		parts.append(("%d %s" % [hi, nm]) if lo == hi else (Loc.t("up to %d %s") % [hi, nm]) if lo == 0 else ("%d-%d %s" % [lo, hi, nm]))
	var mats := d.keys().filter(func(k): return Armory.is_mat(str(k))).map(func(k): return Armory.mat_name(str(k)))
	if not mats.is_empty():  # Forge materials (issue #112)
		parts.append(Loc.t("some %s") % Loc.list(mats))
	return ", ".join(parts)


# ---------------------------------------------------------------- results

## What a settled mission does to the empire. outcome: "success", "retreat" or "wiped".
## Returns lines for the results screen. dry = only say what would happen (Missions.settle
## shows the lines before the player confirms; Missions.apply then calls this for real).
## m["info"] is what the objective reported at the end (the alarm on a raid, say).
static func apply(m: Dictionary, outcome: String, dry := false) -> Array:
	var lines := []
	var p := Empire.territory().find(m.get("province", ""))
	if p.is_empty():
		return lines
	var won := outcome == "success"
	var info: Dictionary = m.get("info", {})
	match m.get("type", ""):
		"defense":
			if won:
				if Empire.surge.get("id", "") == p["id"]:
					lines.append(Loc.t("The surge against %s broke before it landed.") % p["name"])
					if not dry:
						Empire.surge = {}
						Empire.next_surge_day = Empire.day + Empire.rng.randi_range(Empire.SURGE_GAP[0], Empire.SURGE_GAP[1])
				lines.append(Loc.t("%s's Fray %d (the line holds firmer).") % [p["name"], DEFENSE_FRAY])
				if not dry:
					p["fray"] = clampi(int(p["fray"]) + DEFENSE_FRAY, 0, 100)
			elif Empire.surge.get("id", "") == p["id"]:
				lines.append(Loc.n("The surge still lands on %s in %d day.", "The surge still lands on %s in %d days.", Empire.surge_days_left()) % [p["name"], Empire.surge_days_left()])
		"reclaim":
			if won and p["owner"] == "erased":
				lines.append(Loc.t("%d Ink rewrites %s: back on the map, unclaimed, Fray %d.") % [reclaim_ink(), p["name"], reclaim_fray()])
				lines.append(Loc.t("Claim it from the Command Table with a governor%s.") % Prompts.tag("govern"))
				if not dry:
					Empire.res["ink"] = maxi(int(Empire.res.get("ink", 0)) - reclaim_ink(), 0)
					p["owner"] = "free"
					p["fray"] = reclaim_fray()
					p["scar"] = 0
					Empire.notice.emit(Loc.t("%s has been reclaimed from the Blank.") % p["name"], false)
			elif not won:
				lines.append(Loc.t("The Blot still stands. %s stays erased. No Ink was spent.") % p["name"])
		"rescue":
			var rid: String = m.get("objective", {}).get("who", "")
			var jid: String = m.get("job", "")
			if won and rid != "" and not Empire.recruits.has(rid):
				if not dry:
					Empire.recruits[rid] = {"role": "idle", "target": "", "injured": 0}
					Empire._seasoned(rid)
				lines.append(Loc.t("%s joins your roster. Find them in Hollowmark or give them a job%s.") % [Empire.recruit(rid).get("name", rid), Prompts.tag("roster")])
				var j := Empire.job(jid)
				for fid in j.get("standing", {}):
					if not dry:
						Empire.change_standing(fid, int(j["standing"][fid]), j["name"], true)
					lines.append(Loc.t("%s standing %+d.") % [Empire.faction(fid).get("short", fid), int(j["standing"][fid])])
			elif not won:
				lines.append(Loc.t("%s is still out there. The rumour will keep.") % Empire.short_name(rid))
		"raid":
			lines.append_array(_apply_raid(m, p, outcome, info, dry))
		"salvage":
			var got := int(info.get("taken", 0))
			if won:
				lines.append(Loc.n("You pulled %d pile out of the white at %s.", "You pulled %d piles out of the white at %s.", got) % [got, p["name"]])
			elif got > 0:  # the fail reason already says what the white took
				lines.append(Loc.n("You had %d pile out, but not enough to make it worth the run.", "You had %d piles out, but not enough to make it worth the run.", got) % got)
			lines.append(Loc.n("Nothing more to pull out of %s for %d day.", "Nothing more to pull out of %s for %d days.", _cooldown()) % [p["name"], _cooldown()])
			if not dry:
				Empire.mission_ready["salvage:" + p["id"]] = Empire.day + _cooldown()
		"personal":
			lines.append_array(PersonalMissions.apply(m, outcome, dry))
	lines.append_array(FactionAsks.on_mission(m, outcome, dry))  # a faction's request (issue #131)
	return lines


static func _cooldown() -> int:
	return int(data().get("window", {}).get("cooldown", 4))


static func _apply_raid(m: Dictionary, p: Dictionary, outcome: String, info: Dictionary, dry: bool) -> Array:
	var lines := []
	var fid: String = m.get("faction", "")
	var fc: Dictionary = data().get("raid", {}).get("factions", {}).get(fid, {})
	var short: String = Empire.faction(fid).get("short", fid)
	var loud := bool(info.get("alarm", false)) or outcome == "wiped"
	var taken := int(info.get("taken", 0))
	if taken > 0 or loud:
		# They notice the stores gone either way; being seen makes it personal.
		var amount := int(fc.get("loud" if loud else "quiet", -4))
		lines.append(Loc.t("%s standing %+d (%s).") % [short, amount, Loc.t("they saw you") if loud else Loc.t("they suspect, but nobody saw a face")])
		if not dry:
			Empire.change_standing(fid, amount, Loc.t("Raid on %s") % p["name"], true)
	if outcome == "success":
		lines.append(Loc.n("You got away with %d cache from %s.", "You got away with %d caches from %s.", taken) % [taken, p["name"]])
		var rival: Dictionary = fc.get("rival", {})
		for rid in rival:
			lines.append(Loc.t("%s standing %+d (they enjoyed hearing about it).") % [Empire.faction(rid).get("short", rid), int(rival[rid])])
			if not dry:
				Empire.change_standing(rid, int(rival[rid]), Loc.t("Raid on the %s") % short, true)
	lines.append(Loc.n("%s will be watching their stores for %d day.", "%s will be watching their stores for %d days.", _cooldown()) % [short, _cooldown()])
	if not dry:
		Empire.mission_ready["raid:" + p["id"]] = Empire.day + _cooldown()
	return lines
