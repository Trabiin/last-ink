class_name FactionAsks
extends RefCounted
## Faction asks (issue #131): favours the factions ask of you (the Guild, the Coven, the Concord, and from Chapter 2 the
## Abbey and the Erasers, issue #28).
##
## Each faction you know of makes one request at a time (data/factions.json "asks", rules in
## "ask_rules"). It arrives at dawn as a notice that goes to Diplomacy (F), where you accept or
## refuse it. Refusing, or leaving the offer unanswered, costs a little standing. Once accepted it
## has a deadline: do it in time for the reward, miss it and the faction makes you pay.
##
## Kinds: expedition (a job on the Guildhall board that only exists while the ask is accepted),
## raid (win a Raid on the target faction's land), salvage, fray (keep your land by their home under
## a Fray line until the deadline), lamp (light a Wardlamp by their home), deliver (hand resources
## over from Diplomacy), shun (hold no trade pact with a rival until the deadline).
##
## State lives in Empire.asks (saved with the empire; scripts/migrations/20261123_faction_asks.gd):
##   {"next": {faction: day the next offer may come (0 = not scheduled yet)},
##    "offers": {faction: {"id", "day", "until"}},
##    "active": {faction: {"id", "day", "until", "provinces": [ids watched by a fray ask], "warned"}},
##    "ended": {ask id: day it last ended}, "effects": [{"kind" (ward|hex), "faction", "pid", "per_day", "until"}],
##    "log": [{"day", "faction", "id", "outcome" (done|failed|refused|lapsed)}] newest first}
##
## Empire calls dawn() at dawn and check() every frame of the clock; Missions/MissionTypes call
## on_mission(), Empire._resolve_expedition calls on_expedition(). Diplomacy and the journal read
## rows()/progress_text()/target().

const LOG_KEPT := 24
const RES_ORDER := ["gilt", "supplies", "ink", "insight", "renown"]
const KIND_WORDS := {"expedition": "Expedition", "raid": "Raid", "salvage": "Salvage", "fray": "Hold the line",
	"lamp": "Wardlamp", "deliver": "Hand over", "shun": "Promise"}
const OUTCOME_WORDS := {"done": "done", "failed": "failed", "refused": "refused", "lapsed": "left unanswered"}

static var _asks := {}  # ask id -> ask Dictionary (with "faction" added)
static var _rules := {}
static var _help = null  # the onboarding Help class script, false when this build has none


# ---------------------------------------------------------------- data

static func _load() -> void:
	if not _asks.is_empty():
		return
	var parsed = Loc.load_json("res://data/factions.json")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_rules = parsed.get("ask_rules", {})
	for fa in parsed.get("factions", []):
		for a in fa.get("asks", []):
			var d: Dictionary = a.duplicate(true)
			d["faction"] = fa["id"]
			_asks[str(a["id"])] = d


static func rules() -> Dictionary:
	_load()
	return _rules


static func ask(id: String) -> Dictionary:
	_load()
	return _asks.get(id, {})


static func ids() -> Array:
	_load()
	return _asks.keys()


static func asks_of(fid: String) -> Array:
	_load()
	return _asks.values().filter(func(a): return a["faction"] == fid)


static func _range(key: String, fallback: Array) -> Array:
	var v = rules().get(key, fallback)
	return v if v is Array and v.size() == 2 else fallback


# ---------------------------------------------------------------- state

static func fresh() -> Dictionary:
	return {"next": {}, "offers": {}, "active": {}, "ended": {}, "effects": [], "log": []}


static func from_save(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	_load()
	var nx = d.get("next", {})
	if typeof(nx) == TYPE_DICTIONARY:
		for fid in nx:
			out["next"][str(fid)] = int(nx[fid])
	for key in ["offers", "active"]:
		var src = d.get(key, {})
		if typeof(src) != TYPE_DICTIONARY:
			continue
		for fid in src:
			var e = src[fid]
			if typeof(e) != TYPE_DICTIONARY or ask(str(e.get("id", ""))).is_empty() or ask(str(e["id"]))["faction"] != str(fid):
				continue  # an ask that no longer exists: let the faction ask something else
			var row := {"id": str(e["id"]), "day": int(e.get("day", 1)), "until": int(e.get("until", 1))}
			if key == "active":
				var ps = e.get("provinces", [])
				row["provinces"] = (ps as Array).map(func(x): return str(x)) if ps is Array else []
				row["warned"] = bool(e.get("warned", false))
			out[key][str(fid)] = row
	var en = d.get("ended", {})
	if typeof(en) == TYPE_DICTIONARY:
		for id in en:
			out["ended"][str(id)] = int(en[id])
	var effects = d.get("effects", [])
	for e in effects if effects is Array else []:
		if typeof(e) == TYPE_DICTIONARY and str(e.get("kind", "")) in ["ward", "hex"]:
			out["effects"].append({"kind": str(e["kind"]), "faction": str(e.get("faction", "")), "pid": str(e.get("pid", "")),
				"per_day": int(e.get("per_day", 0)), "until": int(e.get("until", 0))})
	var lg = d.get("log", [])
	for e in lg if lg is Array else []:
		if typeof(e) == TYPE_DICTIONARY:
			out["log"].append({"day": int(e.get("day", 1)), "faction": str(e.get("faction", "")), "id": str(e.get("id", "")),
				"outcome": str(e.get("outcome", ""))})
	return out


static func state() -> Dictionary:
	if typeof(Empire.asks) != TYPE_DICTIONARY or not Empire.asks.has("offers"):
		Empire.asks = fresh()
	return Empire.asks


static func offer_of(fid: String) -> Dictionary:
	var o: Dictionary = state()["offers"].get(fid, {})
	return {} if o.is_empty() else _join(ask(o["id"]), o)


static func active_of(fid: String) -> Dictionary:
	var a: Dictionary = state()["active"].get(fid, {})
	return {} if a.is_empty() else _join(ask(a["id"]), a)


## The ask's data with its saved state on top.
static func _join(data: Dictionary, st: Dictionary) -> Dictionary:
	var out := data.duplicate()
	for k in st:
		out[k] = st[k]
	return out


static func is_active(id: String) -> bool:
	var a := ask(id)
	return not a.is_empty() and str(state()["active"].get(a["faction"], {}).get("id", "")) == id


# ---------------------------------------------------------------- where an ask points

## Your provinces (or, with any_owner, every open province not erased) that border a faction's home.
static func near_home(fid: String, any_owner := false) -> Array:
	var t := Empire.territory()
	var home := t.find(str(Empire.faction(fid).get("province", "")))
	if home.is_empty():
		return []
	var out := []
	for n in t.neighbors[home["index"]]:
		var p: Dictionary = t.provinces[n]
		if p["owner"] == "you" or (any_owner and p["owner"] != "erased" and Empire.province_open(p)):
			out.append(p["id"])
	return out


## Target faction land that borders yours (where a raid can be offered).
static func raid_targets(target: String) -> Array:
	var t := Empire.territory()
	var out := []
	for p in t.provinces:
		if p["owner"] != target or not Empire.province_open(p):
			continue
		for n in t.neighbors[p["index"]]:
			if t.provinces[n]["owner"] == "you":
				out.append(p["id"])
				break
	return out


static func _salvage_spots(a: Dictionary) -> Array:
	var t := Empire.territory()
	var min_fray := int(MissionTypes.data().get("salvage", {}).get("min_fray", 35))
	var pool: Array = near_home(a["faction"], true) if a.get("near", true) else t.provinces.map(func(p): return p["id"])
	var out := []
	for pid in pool:
		var p := t.find(pid)
		if not p["owner"] in ["you", "free"] or not Empire.province_open(p):
			continue
		var near_white := false
		var near_you: bool = p["owner"] == "you"
		for n in t.neighbors[p["index"]]:
			near_white = near_white or t.provinces[n]["owner"] == "erased"
			near_you = near_you or t.provinces[n]["owner"] == "you"
		if near_you and (int(p["fray"]) >= min_fray or near_white):
			out.append(pid)
	return out


## Where "go there" leads for an accepted ask ({} = Diplomacy is the place).
static func target(fid: String) -> Dictionary:
	var a := active_of(fid)
	if a.is_empty():
		return {"view": "diplomacy"} if not offer_of(fid).is_empty() else {}
	match str(a.get("kind", "")):
		"expedition":
			return {"view": "expeditions"}
		"raid":
			for pid in raid_targets(str(a["target"])):
				var m := _offered_mission(pid, "raid_" + pid)
				if not m.is_empty():
					return {"province": pid, "mission": m["id"]}
			var rt := raid_targets(str(a["target"]))
			return {"province": rt[0]} if not rt.is_empty() else {"province": str(Empire.faction(str(a["target"])).get("province", ""))}
		"salvage":
			for pid in _salvage_spots(a):
				var m := _offered_mission(pid, "salvage_" + pid)
				if not m.is_empty():
					return {"province": pid, "mission": m["id"]}
			var sp := _salvage_spots(a)
			return {"province": sp[0]} if not sp.is_empty() else {"province": str(Empire.faction(fid).get("province", ""))}
		"fray", "lamp":
			var worst := ""
			for pid in _watched(a):
				var p := Empire.territory().find(pid)
				if a["kind"] == "lamp" and (int(Empire.lamps.get(pid, 0)) > 0 or Empire.lamp_jobs.has(pid)):
					continue
				if worst == "" or int(p["fray"]) > int(Empire.territory().find(worst)["fray"]):
					worst = pid
			return {"province": worst} if worst != "" else {"province": str(Empire.faction(fid).get("province", ""))}
	return {"view": "diplomacy"}


static func _offered_mission(pid: String, mid: String) -> Dictionary:
	for m in Missions.list_for_province(pid):
		if m.get("id", "") == mid and str(m.get("blocker", "")) == "":
			return m
	return {}


## The provinces a fray or lamp ask is about.
static func _watched(a: Dictionary) -> Array:
	if a.has("provinces") and not (a["provinces"] as Array).is_empty():
		return (a["provinces"] as Array).filter(func(pid): return Empire.territory().find(pid).get("owner", "") == "you")
	return near_home(a["faction"])


# ---------------------------------------------------------------- offering

## Why this ask can't be offered right now ("" = it can).
static func offer_blocker(a: Dictionary) -> String:
	var fid: String = a["faction"]
	if not Empire.at_least(fid, str(a.get("tier", "hostile"))):
		return Loc.t("needs %s standing") % Empire.tier_name(str(a.get("tier", "hostile")))
	if a.has("below") and Empire.at_least(fid, str(a["below"])):
		return Loc.t("only below %s") % Empire.tier_name(str(a["below"]))
	var ended = state()["ended"].get(a["id"], null)
	if ended != null:
		if int(a.get("repeat", 0)) <= 0:
			return Loc.t("asked once already")
		if Empire.day < int(ended) + int(a["repeat"]):
			return Loc.t("asked recently")
	match str(a.get("kind", "")):
		"expedition":
			if Empire.level_of("guildhall") <= 0:
				return Loc.t("no Guildhall to send a squad from")
			var j := Empire.job(str(a.get("job", "")))
			if j.is_empty():
				return Loc.t("no such job")
			if Empire.territory().find(str(j.get("province", ""))).get("owner", "") == "erased":
				return Loc.t("the place is erased")
		"raid":
			var tg := str(a.get("target", ""))
			if Empire.at_least(tg, "friendly"):
				return Loc.t("the %s are friends") % Empire.faction(tg).get("short", tg)
			if raid_targets(tg).is_empty():
				return Loc.t("no %s land next to yours") % Empire.faction(tg).get("short", tg)
		"salvage":
			if _salvage_spots(a).is_empty():
				return Loc.t("nothing to salvage")
		"fray":
			var ps := near_home(fid)
			if ps.is_empty():
				return Loc.t("none of your land is next to theirs")
			for pid in ps:
				if int(Empire.territory().find(pid)["fray"]) > int(a.get("max", 40)) - 10:
					return Loc.t("your land there is already too frayed")
		"lamp":
			var ps2 := near_home(fid)
			if ps2.is_empty():
				return Loc.t("none of your land is next to theirs")
			for pid in ps2:
				if int(Empire.lamps.get(pid, 0)) > 0 or Empire.lamp_jobs.has(pid):
					return Loc.t("a lamp already burns there")
		"shun":
			if not Empire.faction_data.has(str(a.get("rival", ""))):
				return Loc.t("no such rival")
	return ""


static func offerable(fid: String) -> Array:
	return asks_of(fid).filter(func(a): return offer_blocker(a) == "")


## A faction makes an offer. Returns false if that ask can't be offered now.
static func offer(fid: String, id: String) -> bool:
	var a := ask(id)
	if a.is_empty() or a["faction"] != fid or offer_blocker(a) != "":
		return false
	var days := int(rules().get("offer_days", 3))
	state()["offers"][fid] = {"id": id, "day": Empire.day, "until": Empire.day + days}
	var fa := Empire.faction(fid)
	_say(Loc.t("The %s ask a favour: %s. Answer in Diplomacy%s within %d days.") % [fa.get("short", fid), a["name"], Prompts.tag("diplomacy"), days],
		false, {"view": "diplomacy"})
	return true


static func _schedule(fid: String, gap: Array) -> void:
	state()["next"][fid] = Empire.day + Empire.rng.randi_range(int(gap[0]), int(gap[1]))


## True when the factions can ask anything: the map is yours, and the faction is known.
static func can_ask(fid: String) -> bool:
	return Story.command_on() and _diplomacy_open() and Journal.faction_known(fid) and not Empire.faction(fid).is_empty()


## In a story campaign Diplomacy stays shut until the story opens it (onboarding, issue #115:
## Help.is_open). Looked up by name so this works with or without that class in the build.
static func _diplomacy_open() -> bool:
	if _help == null:
		_help = false
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == "Help":
				_help = load(str(c["path"]))
	return true if not _help is Script else bool(_help.call("is_open", "diplomacy"))


# ---------------------------------------------------------------- answering

## Why an offer can't be accepted right now ("" = it can).
static func accept_blocker(fid: String) -> String:
	var o := offer_of(fid)
	if o.is_empty():
		return Loc.t("nothing on offer")
	if not active_of(fid).is_empty():
		return Loc.t("you already owe the %s a favour") % Empire.faction(fid).get("short", fid)
	return ""


## Accepts the faction's offer. Returns what happened, for the screen to say ("" = couldn't).
static func accept(fid: String) -> String:
	if accept_blocker(fid) != "":
		return ""
	var a := offer_of(fid)
	state()["offers"].erase(fid)
	var row := {"id": a["id"], "day": Empire.day, "until": Empire.day + int(a.get("days", 5)), "provinces": [], "warned": false}
	if a["kind"] in ["fray", "lamp"]:
		row["provinces"] = near_home(fid)
	state()["active"][fid] = row
	var fa := Empire.faction(fid)
	var said := Loc.t("Accepted: %s. %s left.") % [a["name"], _days(int(a.get("days", 5)))]
	if a["kind"] == "shun":
		var rival := str(a["rival"])
		if rival in Empire.pacts:
			Empire.pacts.erase(rival)
			Empire.change_standing(rival, int(a.get("rival_hit", -4)), Loc.t("You broke off the trade pact for the %s") % fa.get("short", fid), true)
			_log_diplo(rival, Loc.t("Trade pact torn up: you promised the %s") % fa.get("short", fid), 0)
			said += Loc.t(" Your trade pact with the %s is torn up.") % Empire.faction(rival).get("short", rival)
	_log_diplo(fid, Loc.t("Accepted their request: ") + a["name"], 0)
	return said


static func refuse(fid: String) -> String:
	var o := offer_of(fid)
	if o.is_empty():
		return ""
	_close_offer(fid, "refused")
	return Loc.t("Refused: %s.") % o["name"]


static func _close_offer(fid: String, outcome: String) -> void:
	var o := offer_of(fid)
	state()["offers"].erase(fid)
	state()["ended"][o["id"]] = Empire.day
	_schedule(fid, _range("gap", [3, 5]))
	var why := Loc.t("Refused their request") if outcome == "refused" else Loc.t("Ignored their request")
	var hit := int(o.get("refuse", -2))
	_log(fid, o["id"], outcome)
	if hit != 0:
		Empire.change_standing(fid, hit, "%s: %s" % [why, o["name"]], outcome == "refused")
	else:
		_log_diplo(fid, "%s: %s" % [why, o["name"]], 0)


## Why a deliver ask can't be handed over yet ("" = it can).
static func deliver_blocker(fid: String) -> String:
	var a := active_of(fid)
	if a.is_empty() or a["kind"] != "deliver":
		return Loc.t("nothing to hand over")
	if not Empire.can_afford(a.get("cost", {})):
		return Loc.t("not enough ") + Empire._missing(a.get("cost", {}))
	return ""


static func deliver(fid: String) -> String:
	if deliver_blocker(fid) != "":
		return ""
	var a := active_of(fid)
	Empire.spend(a.get("cost", {}))
	return _complete(fid, Loc.t("Handed over %s.") % Empire.cost_text(a.get("cost", {})))


# ---------------------------------------------------------------- the clock

## Dawn (Empire._advance_diplomacy): offers lapse, deadlines land, warnings go out, new offers come.
static func dawn() -> void:
	var st := state()
	st["effects"] = (st["effects"] as Array).filter(func(e): return int(e["until"]) > Empire.day)
	for fid in Empire.faction_ids():
		if not can_ask(fid):
			continue
		var o := offer_of(fid)
		if not o.is_empty() and Empire.day >= int(o["until"]):
			_close_offer(fid, "lapsed")
			Empire.notice.emit(Loc.t("The %s took your silence as a no: %s.") % [Empire.faction(fid).get("short", fid), o["name"]], true)
		var a := active_of(fid)
		if not a.is_empty():
			if Empire.day >= int(a["until"]):
				_deadline(fid)
			elif int(a["until"]) - Empire.day <= int(rules().get("warn_days", 1)) and not a.get("warned", false):
				st["active"][fid]["warned"] = true
				_say(Loc.t("%s left on the %s's request: %s.") % [_days(int(a["until"]) - Empire.day), Empire.faction(fid).get("short", fid), a["name"]],
					true, target(fid))
		if not st["offers"].has(fid) and not st["active"].has(fid):
			if int(st["next"].get(fid, 0)) <= 0:
				_schedule(fid, _range("first", [2, 4]))
			elif Empire.day >= int(st["next"][fid]):
				var pool := offerable(fid)
				if pool.is_empty():
					st["next"][fid] = Empire.day + 1  # nothing fits yet: ask again tomorrow
				else:
					offer(fid, pool[Empire.rng.randi_range(0, pool.size() - 1)]["id"])


## A deadline arrives. Fray asks held all the way succeed; a squad still out gets to come home first.
static func _deadline(fid: String) -> void:
	var a := active_of(fid)
	match str(a["kind"]):
		"fray":
			_complete(fid, Loc.t("Held every acre at %d Fray or less.") % int(a.get("max", 40)))
			return
		"shun":
			_complete(fid, Loc.t("Kept your word: no pact with the %s.") % Empire.faction(str(a["rival"])).get("short", "?"))
			return
		"expedition":
			if not Empire.expedition_running(str(a.get("job", ""))).is_empty():
				return  # the squad is still out: their report settles it
	_fail(fid, Loc.t("The deadline passed."))


## Every frame the clock runs (cheap: at most one ask per faction). Things that can happen any time.
static func check() -> void:
	var st := state()
	for fid in st["active"].keys():
		var a := active_of(fid)
		if a.is_empty():
			st["active"].erase(fid)
			continue
		match str(a["kind"]):
			"lamp":
				for pid in _watched(a):
					if int(Empire.lamps.get(pid, 0)) > 0:
						_complete(fid, Loc.t("A Wardlamp burns in %s.") % Empire.territory().find(pid)["name"])
						break
			"fray":
				var watched: Array = a.get("provinces", [])
				for pid in watched:
					var p := Empire.territory().find(pid)
					if p.get("owner", "") == "erased":
						_fail(fid, Loc.t("%s was erased.") % p.get("name", "?"))
						break
					if p.get("owner", "") == "you" and int(p["fray"]) > int(a.get("max", 40)):
						_fail(fid, Loc.t("%s frayed past %d.") % [p["name"], int(a.get("max", 40))])
						break
			"shun":
				if str(a["rival"]) in Empire.pacts:
					_fail(fid, Loc.t("You signed a trade pact with the %s.") % Empire.faction(str(a["rival"])).get("short", "?"))


# ---------------------------------------------------------------- missions and expeditions

## A mission settled (MissionTypes.apply). Lines for the results screen; dry = only say what would happen.
static func on_mission(m: Dictionary, outcome: String, dry := false) -> Array:
	var lines := []
	if outcome != "success":
		return lines
	var typ := str(m.get("type", ""))
	for fid in state()["active"].keys():
		var a := active_of(fid)
		var hit := false
		if typ == "raid" and a.get("kind", "") == "raid" and str(m.get("faction", "")) == str(a.get("target", "")):
			hit = true
		elif typ == "salvage" and a.get("kind", "") == "salvage":
			hit = not a.get("near", true) or str(m.get("province", "")) in near_home(fid, true)
		if not hit:
			continue
		lines.append(Loc.t("The %s's request is done: %s. %s") % [Empire.faction(fid).get("short", fid), a["name"], reward_text(a) + "."])
		if not dry:
			_complete(fid, "", true)
	return lines


## A squad came home from a job (Empire._resolve_expedition). Lines for the report.
static func on_expedition(jid: String, success: bool) -> Array:
	var lines := []
	var j := Empire.job(jid)
	var id := str(j.get("ask", ""))
	if id == "" or not is_active(id):
		return lines
	var fid: String = ask(id)["faction"]
	var a := active_of(fid)
	if success:
		lines.append(Loc.t("The %s's request is done: %s.") % [Empire.faction(fid).get("short", fid), reward_text(a)])
		_complete(fid, "", true)
	elif Empire.day >= int(a["until"]):
		lines.append(Loc.t("The deadline for the %s's request has passed.") % Empire.faction(fid).get("short", fid))
		_fail(fid, Loc.t("The squad came back empty-handed after the deadline."))
	else:
		lines.append(Loc.t("The %s still want it done: %s left to try again.") % [Empire.faction(fid).get("short", fid), _days(int(a["until"]) - Empire.day)])
	return lines


## Should this expedition job be on the Guildhall board? Request-only jobs show while their ask is accepted.
static func job_listed(j: Dictionary) -> bool:
	var id := str(j.get("ask", ""))
	return id == "" or is_active(id) or not Empire.expedition_running(str(j.get("id", ""))).is_empty()


## The active shun ask a new trade pact with this faction would break ({} = none).
static func pact_breaks(rival: String) -> Dictionary:
	for fid in state()["active"]:
		var a := active_of(fid)
		if a.get("kind", "") == "shun" and str(a.get("rival", "")) == rival:
			return a
	return {}


# ---------------------------------------------------------------- endings

static func _complete(fid: String, why := "", quiet := false) -> String:
	var a := active_of(fid)
	if a.is_empty():
		return ""
	_end(fid, a, "done")
	var paid := _pay(fid, a)
	var short: String = Empire.faction(fid).get("short", fid)
	var text := "%s%s" % [(why + " ") if why != "" else "", str(a.get("done_text", ""))]
	_log_diplo(fid, Loc.t("Request done: %s") % a["name"], 0)
	var line := Loc.t("The %s's request is done: %s.%s") % [short, a["name"], (" " + paid + ".") if paid != "" else ""]
	if not quiet:
		_say(line, false, {"view": "diplomacy"})
	return text.strip_edges()


static func _fail(fid: String, why: String) -> void:
	var a := active_of(fid)
	if a.is_empty():
		return
	_end(fid, a, "failed")
	var f: Dictionary = a.get("fail", {})
	var bits := []
	var short: String = Empire.faction(fid).get("short", fid)
	if int(f.get("standing", 0)) != 0:
		Empire.change_standing(fid, int(f["standing"]), Loc.t("Failed their request: %s") % a["name"], true)
		bits.append(Loc.t("%s standing %+d") % [short, int(f["standing"])])
	if int(f.get("fine", 0)) > 0:
		var g := mini(int(f["fine"]), int(Empire.res["gilt"]))
		Empire.res["gilt"] -= g
		if g > 0:
			bits.append(Loc.t("they took %d Gilt") % g)
	if f.get("trouble", false) and not Empire.faction(fid).get("trouble", {}).is_empty():
		Empire._set_trouble_day(fid, mini(Empire.trouble_day(fid), Empire.day + 1))
		bits.append(Loc.t("expect trouble at dawn"))
	if f.has("hex"):
		for pid in near_home(fid):
			_effect("hex", fid, pid, int(f["hex"].get("per_day", 2)), int(f["hex"].get("days", 3)))
		if not near_home(fid).is_empty():
			bits.append(Loc.t("a hex on your land by their home (+%d Fray a day for %d days, a Wardlamp burns it off)") % [int(f["hex"].get("per_day", 2)), int(f["hex"].get("days", 3))])
	_log_diplo(fid, Loc.t("Failed their request: %s. %s") % [a["name"], why], 0, true)
	_say(Loc.t("The %s's request failed: %s. %s%s") % [short, a["name"], why, (" " + ", ".join(bits).substr(0, 1).to_upper() + ", ".join(bits).substr(1) + ".") if not bits.is_empty() else ""],
		true, {"view": "diplomacy"})


static func _end(fid: String, a: Dictionary, outcome: String) -> void:
	state()["active"].erase(fid)
	state()["ended"][a["id"]] = Empire.day
	_schedule(fid, _range("gap", [3, 5]))
	_log(fid, a["id"], outcome)


## Pays an ask's reward. Returns what was paid, as one line.
static func _pay(fid: String, a: Dictionary) -> String:
	var rw: Dictionary = a.get("reward", {})
	var bits := []
	if int(rw.get("standing", 0)) != 0:
		Empire.change_standing(fid, int(rw["standing"]), Loc.t("Request done: %s") % a["name"], true)
		bits.append(Loc.t("%s standing %+d") % [Empire.faction(fid).get("short", fid), int(rw["standing"])])
	for k in RES_ORDER:
		if int(rw.get(k, 0)) != 0:
			Empire.gain(k, int(rw[k]))
			bits.append("+%d %s" % [int(rw[k]), Loc.t(Empire.RES_NAMES[k])])
	var mats: Dictionary = rw.get("mats", {})
	for m in mats:
		if Armory.is_mat(str(m)):
			Armory.add_mat(str(m), int(mats[m]))
			bits.append("+%d %s" % [int(mats[m]), Armory.mat_name(str(m))])
	if rw.has("boon"):
		var b: Dictionary = rw["boon"]
		var days := int(b.get("days", 5))
		match str(b.get("kind", "")):
			"intel":
				Empire.intel_until = maxi(Empire.intel_until, Empire.day + days)
			"truce":
				Empire._set_trouble_day(fid, maxi(Empire.trouble_day(fid), Empire.day + days))
			"ward":
				for pid in near_home(fid):
					_effect("ward", fid, pid, int(b.get("per_day", -1)), days)
		bits.append(boon_text(fid, b))
	var rid := str(rw.get("recruit", ""))
	if rid != "" and not Empire.recruits.has(rid) and not Empire.visitors.has(rid) and Empire.recruit_data.has(rid):
		Empire.visitors[rid] = Empire.day
		var r := Empire.recruit(rid)
		Empire.notice.emit(Loc.t("%s, %s, is waiting at Hollowmark's south gate. Talk to them in town, or open Newcomers%s.") % [r["name"], r.get("title", ""), Prompts.tag("newcomers")], false)
		Empire.lead_arrived.emit(rid)
		bits.append(Loc.t("%s comes to Hollowmark") % r["name"])
	return ", ".join(bits)


static func _effect(kind: String, fid: String, pid: String, per_day: int, days: int) -> void:
	var st := state()
	for e in st["effects"]:
		if e["kind"] == kind and e["faction"] == fid and e["pid"] == pid:
			e["until"] = maxi(int(e["until"]), Empire.day + days)
			e["per_day"] = per_day
			return
	st["effects"].append({"kind": kind, "faction": fid, "pid": pid, "per_day": per_day, "until": Empire.day + days})


## Lines for Empire.fray_sources(): wards and hexes a faction left on a province.
static func fray_sources(p: Dictionary) -> Array:
	var out := []
	for e in state()["effects"]:
		if e["pid"] != p["id"] or int(e["until"]) <= Empire.day:
			continue
		var left := int(e["until"]) - Empire.day
		var short: String = Empire.faction(e["faction"]).get("short", e["faction"])
		if e["kind"] == "ward":
			out.append([Loc.t("%s wards (%dd)") % [short, left], int(e["per_day"])])
		elif int(Empire.lamps.get(p["id"], 0)) > 0:
			out.append([Loc.t("%s hex (%dd, burnt off by Wardlamp)") % [short, left], 0])
		else:
			out.append([Loc.t("%s hex (%dd, a Wardlamp burns it off)") % [short, left], int(e["per_day"])])
	return out


# ---------------------------------------------------------------- words

static func _days(n: int) -> String:
	if n <= 0:
		return Loc.t("less than a day")
	return Loc.t("%d day%s") % [n, "" if n == 1 else "s"]


static func boon_text(fid: String, b: Dictionary) -> String:
	var days := int(b.get("days", 5))
	match str(b.get("kind", "")):
		"intel":
			return Loc.t("+1 day of surge warning for %d days") % days
		"truce":
			return Loc.t("no %s trouble for %d days") % [Empire.faction(fid).get("short", fid), days]
		"ward":
			return Loc.t("your land by the %s's home frays %d less a day for %d days") % [Empire.faction(fid).get("short", fid), absi(int(b.get("per_day", -1))), days]
	return ""


## "+10 standing, +35 Gilt, +1 Renown": what doing it pays.
static func reward_text(a: Dictionary) -> String:
	var rw: Dictionary = a.get("reward", {})
	var bits := []
	if int(rw.get("standing", 0)) != 0:
		bits.append(Loc.t("%+d standing") % int(rw["standing"]))
	for k in RES_ORDER:
		if int(rw.get(k, 0)) != 0:
			bits.append("+%d %s" % [int(rw[k]), Loc.t(Empire.RES_NAMES[k])])
	var mats: Dictionary = rw.get("mats", {})
	for m in mats:
		bits.append("+%d %s" % [int(mats[m]), Armory.mat_name(str(m))])
	if rw.has("boon"):
		bits.append(boon_text(a["faction"], rw["boon"]))
	if str(rw.get("recruit", "")) != "" and not Empire.recruits.has(str(rw["recruit"])):
		bits.append(Loc.t("someone new comes to Hollowmark"))
	return ", ".join(bits)


## What missing the deadline costs.
static func fail_text(a: Dictionary) -> String:
	var f: Dictionary = a.get("fail", {})
	var bits := []
	if int(f.get("standing", 0)) != 0:
		bits.append(Loc.t("%+d standing") % int(f["standing"]))
	if int(f.get("fine", 0)) > 0:
		bits.append(Loc.t("they take %d Gilt") % int(f["fine"]))
	if f.get("trouble", false):
		bits.append(Loc.t("%s trouble at the next dawn") % Empire.faction(str(a.get("faction", "concord"))).get("short", Loc.t("Concord")))
	if f.has("hex"):
		bits.append(Loc.t("a hex: +%d Fray a day for %d days on your land by their home") % [int(f["hex"].get("per_day", 2)), int(f["hex"].get("days", 3))])
	return ", ".join(bits) if not bits.is_empty() else Loc.t("nothing but their opinion of you")


## What the ask wants you to do, in one sentence.
static func task_text(a: Dictionary) -> String:
	var fid: String = a["faction"]
	match str(a.get("kind", "")):
		"expedition":
			var j := Empire.job(str(a.get("job", "")))
			return Loc.t("Send a squad on \"%s\" from the Guildhall%s (%s).") % [j.get("name", "?"), Prompts.tag("expeditions"), Empire.territory().find(str(j.get("province", ""))).get("name", "?")]
		"raid":
			return Loc.t("Win a Raid on %s land from the territory map.") % Empire.faction(str(a["target"])).get("short", "?")
		"salvage":
			return Loc.t("Win a Salvage mission %s.") % (Loc.t("next to the %s's home") % Empire.faction(fid).get("short", fid) if a.get("near", true) else Loc.t("anywhere"))
		"fray":
			return Loc.t("Keep every province of yours next to %s at %d Fray or less until the deadline.") % [Empire.territory().find(str(Empire.faction(fid).get("province", ""))).get("name", "?"), int(a.get("max", 40))]
		"lamp":
			return Loc.t("Light a Wardlamp in a province of yours next to %s (Command Table).") % Empire.territory().find(str(Empire.faction(fid).get("province", ""))).get("name", "?")
		"deliver":
			return Loc.t("Hand over %s from Diplomacy before the deadline.") % Empire.cost_text(a.get("cost", {}))
		"shun":
			return Loc.t("Hold no trade pact with the %s until the deadline.") % Empire.faction(str(a["rival"])).get("short", "?")
	return ""


## Where an accepted ask stands right now, in one sentence.
static func progress_text(fid: String) -> String:
	var a := active_of(fid)
	if a.is_empty():
		return ""
	var left := int(a["until"]) - Empire.day
	match str(a["kind"]):
		"expedition":
			var jid := str(a.get("job", ""))
			var e := Empire.expedition_running(jid)
			if not e.is_empty():
				return Loc.t("A squad is out on it, due back on day %d.") % int(ceil(float(e["finish"])))
			var why := Empire.job_blocker(jid)
			return Loc.t("On the Guildhall board now.") if why == "" else Loc.t("Can't send it yet: %s.") % why
		"raid":
			var t := target(fid)
			if t.has("mission"):
				return Loc.t("A raid is on offer at %s right now.") % Empire.territory().find(t["province"]).get("name", "?")
			var rt := raid_targets(str(a["target"]))
			if rt.is_empty():
				return Loc.t("No %s land borders yours right now.") % Empire.faction(str(a["target"])).get("short", "?")
			return Loc.t("No raid on offer this minute; chances open every few days at %s.") % Empire.territory().find(rt[0]).get("name", "?")
		"salvage":
			var t2 := target(fid)
			if t2.has("mission"):
				return Loc.t("A salvage run is on offer at %s right now.") % Empire.territory().find(t2["province"]).get("name", "?")
			return Loc.t("No salvage run on offer this minute; they open every few days on frayed land.")
		"fray":
			var parts := []
			for pid in _watched(a):
				var p := Empire.territory().find(pid)
				parts.append("%s %d" % [p["name"], int(p["fray"])])
			return (Loc.t("Fray now: %s (line: %d). Holds for %s more.") % [", ".join(parts), int(a.get("max", 40)), _days(left)]) if not parts.is_empty() else Loc.t("None of your land is next to theirs any more.")
		"lamp":
			for pid in _watched(a):
				if Empire.lamp_jobs.has(pid):
					return Loc.t("A lamp is going up in %s.") % Empire.territory().find(pid)["name"]
			return Loc.t("No lamp lit or going up yet.")
		"deliver":
			var why2 := deliver_blocker(fid)
			return (Loc.t("Ready to hand over. %s on it in Diplomacy.") % Prompts.confirm()) if why2 == "" else Loc.t("Can't hand it over yet: %s.") % why2
		"shun":
			return Loc.t("Promise kept so far. Holds for %s more.") % _days(left)
	return ""


# ---------------------------------------------------------------- journal and log

## Journal rows for one faction (Journal.faction_quests): the offer waiting, the ask accepted, and
## asks that ended in the last few days.
static func rows(fid: String) -> Array:
	var out := []
	var short: String = Empire.faction(fid).get("short", fid)
	var where: String = Empire.territory().find(str(Empire.faction(fid).get("province", ""))).get("name", "")
	var o := offer_of(fid)
	if not o.is_empty():
		out.append({"id": "ask_" + o["id"], "section": "factions", "title": Loc.t("%s ask: %s") % [short, o["name"]], "state": "open",
			"text": str(o.get("text", "")), "where": where, "days": maxi(int(o["until"]) - Empire.day, 0),
			"next": Loc.t("Answer in Diplomacy%s. Do it for %s. Refusing costs %d standing; so does leaving it unanswered. %s") % [Prompts.tag("diplomacy"), reward_text(o), absi(int(o.get("refuse", -2))), task_text(o)],
			"target": {"view": "diplomacy"}})
	var a := active_of(fid)
	if not a.is_empty():
		var t := target(fid)
		var tpid := str(t.get("province", Empire.job(str(a.get("job", ""))).get("province", "")))
		var tw: String = Empire.territory().find(tpid).get("name", where)
		out.append({"id": "ask_" + a["id"], "section": "factions", "title": "%s: %s" % [short, a["name"]], "state": "open",
			"text": str(a.get("text", "")), "where": tw, "days": maxi(int(a["until"]) - Empire.day, 0),
			"next": Loc.t("%s %s Pays %s. Missing it: %s.") % [task_text(a), progress_text(fid), reward_text(a), fail_text(a)],
			"target": t})
	for e in state()["log"]:
		if e["faction"] != fid or Empire.day - int(e["day"]) > 3 or not e["outcome"] in ["done", "failed"]:
			continue
		var d := ask(e["id"])
		if d.is_empty():
			continue
		out.append({"id": "ask_%s_%d" % [e["id"], int(e["day"])], "section": "factions", "title": "%s: %s" % [short, d["name"]],
			"state": "done" if e["outcome"] == "done" else "blocked", "text": str(d.get("done_text" if e["outcome"] == "done" else "fail_text", "")),
			"where": where, "days": -1, "target": {},
			"next": (Loc.t("Done on day %d.") if e["outcome"] == "done" else Loc.t("Failed on day %d.")) % int(e["day"])})
	return out


static func _log(fid: String, id: String, outcome: String) -> void:
	var lg: Array = state()["log"]
	lg.push_front({"day": Empire.day, "faction": fid, "id": id, "outcome": outcome})
	if lg.size() > LOG_KEPT:
		lg.resize(LOG_KEPT)
	if outcome in ["done", "failed"]:
		var a := ask(id)
		Journal.record({"day": Empire.day, "kind": "faction", "title": "%s: %s" % [Empire.faction(fid).get("short", fid), a.get("name", id)],
			"outcome": "success" if outcome == "done" else "fail",
			"lines": [str(a.get("text", "")), str(a.get("done_text" if outcome == "done" else "fail_text", ""))],
			"province": str(Empire.faction(fid).get("province", ""))})


static func _log_diplo(fid: String, text: String, change: int, trouble := false) -> void:
	var e := {"day": Empire.day, "faction": fid, "text": text, "change": change}
	if trouble:
		e["trouble"] = true
	Empire.diplo_log.push_front(e)
	if Empire.diplo_log.size() > Empire.DIPLO_LOG_KEPT:
		Empire.diplo_log.resize(Empire.DIPLO_LOG_KEPT)


## A notice that goes somewhere: the Alerts tray picks it up with this target.
static func _say(text: String, warning: bool, tgt: Dictionary) -> void:
	var tray := Alerts.inst()  # made before the notice, so the tray hears it
	Empire.notice.emit(text, warning)
	if not tgt.is_empty():
		tray._retarget(tgt)
