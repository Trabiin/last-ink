class_name Journal
extends RefCounted
## The journal (issue #114): quest log, people, codex and history, in one place to look things up.
## Opened with I (rebindable), from the menus in town, at the Command Table and mid-mission.
## The screen is scripts/journal_view.gd; this file works out what it shows.
##
##   Quests  - the main story's goals for the current chapter, each personal job or mission,
##             what every faction wants next, and the open missions and threats on the map,
##             each with its next step and a "show on map" target (Alerts targets).
##   People  - everyone met: the roster, visitors at the gate, rumoured recruits with how to
##             bring them in, and figures who never join (data/journal.json "figures").
##   Codex   - places, factions, enemies, the Blank and Ink colours (data/journal.json "codex"),
##             unlocked by meeting things, with live numbers from the other data files.
##   History - a recap per chapter so far, and a log of mission results and expedition reports.
##
## Words live in data/journal.json so each chapter adds its entries without code (see _comment).
## Saved state is Empire.journal: {"enemies": {kind: {"seen": day, "kills": n}},
## "log": [{"day", "kind", "title", "outcome", "lines", "province"}], "read": {entry id: true}}.
## Migration scripts/migrations/20261121_journal.gd fills it in for saves from before the journal.

const PATH := "res://data/journal.json"
const LOG_KEPT := 400  # history entries kept; a long campaign writes a few a day at most
const LOG_LINES := 6  # lines kept per history entry
const CATS := ["places", "factions", "enemies", "blank", "inks", "help"]
const CAT_NAMES := {"places": "Places", "factions": "Factions", "enemies": "Enemies", "blank": "The Blank", "inks": "Ink", "help": "Help & tips"}
## Condition keys the journal adds to Story.meets (see data/journal.json _comment).
const DEAL_WORDS := {"gift": "a gift", "intel": "intel", "trade": "a trade pact", "aid": "aid against surges", "cede": "they cede land"}
const OWN_KEYS := ["command", "region", "enemy_seen", "defeated", "erased_any", "plans", "ink"]

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = Loc.load_json(PATH)
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data


# ---------------------------------------------------------------- saved state

static func fresh() -> Dictionary:
	return {"enemies": {}, "log": [], "read": {}}


## The saved journal, cleaned up: unknown shapes are dropped, never trusted.
static func from_save(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	var en = d.get("enemies", {})
	if typeof(en) == TYPE_DICTIONARY:
		for k in en:
			var e = en[k]
			if typeof(e) == TYPE_DICTIONARY:
				out["enemies"][str(k)] = {"seen": int(e.get("seen", 0)), "kills": maxi(int(e.get("kills", 0)), 0)}
	var lg = d.get("log", [])
	if typeof(lg) == TYPE_ARRAY:
		for e in lg:
			if typeof(e) == TYPE_DICTIONARY and e.has("title"):
				out["log"].append(_entry(e))
		if out["log"].size() > LOG_KEPT:
			out["log"].resize(LOG_KEPT)
	var rd = d.get("read", {})
	if typeof(rd) == TYPE_DICTIONARY:
		for k in rd:
			out["read"][str(k)] = true
	return out


static func _entry(e: Dictionary) -> Dictionary:
	var lines := []
	for l in e.get("lines", []):
		if lines.size() < LOG_LINES:
			lines.append(str(l))
	return {"day": int(e.get("day", 0)), "kind": str(e.get("kind", "mission")), "title": str(e.get("title", "")),
		"outcome": str(e.get("outcome", "")), "lines": lines, "province": str(e.get("province", ""))}


static func _state() -> Dictionary:
	if typeof(Empire.journal) != TYPE_DICTIONARY or not Empire.journal.has("log"):
		Empire.journal = fresh()
	return Empire.journal


# ---------------------------------------------------------------- recording

## The enemy kind an actor counts as (data/enemies.json kinds, plus the bosses in BossFight.BOSSES).
static func kind_of(e: Node) -> String:
	if e.has_meta("kind"):
		return str(e.get_meta("kind"))
	if e is Auditor:
		return "auditor"
	return "nibbler"  # plain Enemy nodes are Nibblers (EnemyKinds.notice says the same)


## An enemy noticed the party.
static func saw(kind: String) -> void:
	var en: Dictionary = _state()["enemies"]
	if not en.has(kind):
		en[kind] = {"seen": Empire.day, "kills": 0}


static func defeated(kind: String) -> void:
	saw(kind)
	_state()["enemies"][kind]["kills"] = int(_state()["enemies"][kind]["kills"]) + 1


static func seen_enemy(kind: String) -> bool:
	return _state()["enemies"].has(kind)


static func kills(kind: String) -> int:
	return int(_state()["enemies"].get(kind, {}).get("kills", 0))


static func record(e: Dictionary) -> void:
	var lg: Array = _state()["log"]
	lg.push_front(_entry(e))
	if lg.size() > LOG_KEPT:
		lg.resize(LOG_KEPT)


## A mission's results screen was confirmed (main.gd): one history entry.
static func record_mission(r: Dictionary) -> void:
	var lines := []
	if str(r.get("objective", "")) != "":
		lines.append(str(r["objective"]))
	var pay := Missions.res_text(r.get("pay", {}))
	if pay != "":
		lines.append(Loc.t("Brought home: %s.") % pay)
	for l in r.get("lines", []):
		lines.append(str(l))
	record({"day": Empire.day, "kind": "mission", "title": str(r.get("name", Loc.t("Mission"))), "outcome": str(r.get("outcome", "")),
		"lines": lines, "province": str(r.get("province_id", ""))})


## An expedition came home (Empire._resolve_expedition): its report, kept for good.
static func record_expedition(rep: Dictionary) -> void:
	record({"day": int(rep.get("day", Empire.day)), "kind": "expedition", "title": str(rep.get("title", Loc.t("Expedition"))),
		"outcome": str(rep.get("outcome", "")), "lines": rep.get("lines", []),
		"province": str(Empire.job(str(rep.get("job", ""))).get("province", ""))})


static func log_entries(kind := "") -> Array:
	var lg: Array = _state()["log"]
	return lg if kind == "" else lg.filter(func(e): return e["kind"] == kind)


static func is_read(id: String) -> bool:
	return _state()["read"].has(id)


static func mark_read(id: String) -> void:
	_state()["read"][id] = true
	_unread_at = -100000


# ---------------------------------------------------------------- conditions

## Story.meets plus the journal's own keys (data/journal.json _comment).
static func meets(c: Dictionary) -> bool:
	if c.is_empty():
		return true
	if c.has("command") and bool(c["command"]) != Story.command_on():
		return false
	if c.has("region") and not Empire.region_open(str(c["region"])):
		return false
	if c.has("enemy_seen") and not seen_enemy(str(c["enemy_seen"])):
		return false
	if c.has("defeated") and kills(str(c["defeated"])) <= 0:
		return false
	if c.get("erased_any", false) and not _any_erased():
		return false
	if c.get("plans", false) and int(Empire.blank_plans.get("next", 0)) <= 0 and Empire.blank_plans.get("pressure", []).is_empty():
		return false
	if c.has("ink") and not str(c["ink"]) in known_inks():
		return false
	var rest := c.duplicate()
	for k in OWN_KEYS:
		rest.erase(k)
	return rest.is_empty() or Story.meets(rest)


static func _any_erased() -> bool:
	for p in Empire.territory().provinces:
		if p["owner"] == "erased" and Empire.province_open(p):
			return true
	return false


## Ink colours any field hero on the roster uses.
static func known_inks() -> Array:
	var out := []
	for id in Empire.roster_ids():
		for a in Abilities.for_ids(PartyPicker.hero_data(id).get("abilities", [])):
			var c := str(a.get("ink", ""))
			if c != "" and not c in out:
				out.append(c)
	return out


## Paragraphs whose "when" holds.
static func paragraphs(list: Array) -> Array:
	var out := []
	for p in list:
		if typeof(p) == TYPE_DICTIONARY and meets(p.get("when", {})):
			out.append(str(p.get("text", "")))
	return out


# ---------------------------------------------------------------- chapters

static func chapters() -> Array:
	return data().get("chapters", [])


## Chapters begun so far, in order.
static func chapters_started() -> Array:
	return chapters().filter(func(c): return meets(c.get("starts", {})))


## The chapter being played: the last one begun. Saves from before the story start in Act 1.
static func current_chapter() -> Dictionary:
	if not Story.active():
		for c in chapters():
			if c.get("id", "") == "act1":
				return c
	var st := chapters_started()
	return st[-1] if not st.is_empty() else {}


static func chapter_done(c: Dictionary) -> bool:
	return c.has("done") and meets(c["done"])


# ---------------------------------------------------------------- quests

## Every quest row: {"id", "section", "title", "state" (open|done|blocked|locked), "text" (what it is),
## "next" (the next step), "target" (Alerts target; {} = nowhere to go), "where" (province name), "days" (-1 = no clock)}.
static func quests() -> Array:
	var out := []
	out.append_array(story_quests())
	out.append_array(personal_quests())
	out.append_array(faction_quests())
	out.append_array(open_quests())
	return out


static func story_quests() -> Array:
	var out := []
	var ch := current_chapter()
	var ch_id: String = ch.get("id", "")
	var i := 0
	for g in Story.data().get("goals", []):
		i += 1
		if g.has("show") and not Story.meets(g["show"]):
			continue
		var gch := str(g.get("chapter", ch_id))
		if gch != ch_id:
			continue
		var done := Story.meets(g.get("done", {}))
		var target := {} if done else Alerts.goal_target(g.get("done", {}))
		var next := ""
		if not done:
			next = Prompts.fill(str(g.get("hint", "")))
			var why := _story_blocker(g.get("done", {}))
			if why != "" and next != "":
				next = Loc.t("%s. For now: %s.") % [next, why]
		out.append({"id": "story_%d" % i, "section": "story", "title": str(g.get("text", "")), "state": "done" if done else "open",
			"sub": ch.get("title", Loc.t("Main story")), "text": "", "next": next, "target": target, "where": _where(target), "days": -1})
	if not Story.active() and out.is_empty():
		out.append({"id": "story_none", "section": "story", "title": Loc.t("Hold the Marches"), "state": "open",
			"text": Loc.t("This campaign began before the story was written in, so Chapter 1 was skipped."),
			"next": Loc.t("Claim land, keep the Blank back and grow the town from the Command Table."), "target": {}, "where": "", "days": -1})
	return out


## What a story mission in the goal still needs (from its briefing blocker), or "".
static func _story_blocker(done: Dictionary) -> String:
	for id in done.get("cleared", []):
		var m := Missions.find(str(id))
		if m.is_empty() or Missions.cleared(str(id)):
			continue
		if m.has("needs"):
			var why := Story.blocker(m["needs"])
			if why != "":
				return why
		var after: String = m.get("after", "")
		if after != "" and not Missions.cleared(after):
			return Loc.t("clear %s first") % Missions.find(after).get("name", after)
	return ""


## Personal stories: one row per core character on the roster with a personal job or mission.
## Empire.personal_job(id) may name an expedition job (Guildhall, #50) or a mission (#113).
static func personal_quests() -> Array:
	var out := []
	for id in Empire.bond_ids():
		var pj := Empire.personal_job(id)
		if pj == "":
			continue
		var name := Empire.short_name(id)
		var rank := Empire.bond_rank(id)
		var m := Missions.find(pj)
		var j := Empire.job(pj) if m.is_empty() else {}
		var title: String = m.get("name", j.get("name", "?"))
		var row := {"id": "personal_" + id, "section": "personal", "title": "%s: %s" % [name, title], "state": "open",
			"text": str(m.get("brief", j.get("blurb", ""))), "next": "", "target": {}, "where": "", "days": -1}
		var pid := str(m.get("province", j.get("province", "")))
		var p := Empire.territory().find(pid)
		row["where"] = p.get("name", "")
		if Empire.personal_done(id):
			row["state"] = "done"
			row["next"] = Loc.t("Done. %s") % Empire.bond_next_text(id) if rank < Empire.BOND_MAX else Loc.t("Done, and the bond is as deep as it goes.")
			row["target"] = {"view": "bonds"} if Empire.bond_next_scene(id) > 0 else {}
		elif rank < 4:
			row["state"] = "locked"
			row["next"] = Loc.t("Opens at bond rank 4 with %s (now rank %d). Chat in town, give them a role they like, take them along.") % [name, rank]
			row["target"] = {"view": "bonds"}
		elif Empire.personal_lost(id) != "":
			row["state"] = "blocked"
			row["next"] = Loc.t("%s has been erased. Reclaim it to bring this back.") % Empire.personal_lost(id)
			row["target"] = {"province": pid}
		elif not m.is_empty():
			var listed := _offered(pid, pj)
			var why := str(listed.get("blocker", "")) if not listed.is_empty() else Loc.t("not on the map right now")
			row["state"] = "open" if why == "" else "blocked"
			var along := (Loc.t("with %s in the party") if PersonalMissions.is_field(id) else Loc.t("with %s along as an escort to keep alive")) % name
			row["next"] = (Loc.t("Play it from %s on the territory map, %s.") % [row["where"], along]) if why == "" else Loc.t("Can't start yet: %s.") % why
			row["target"] = {"province": pid, "mission": pj}
		elif not Empire.expedition_running(pj).is_empty():
			row["next"] = Loc.t("Under way. The squad is due back on day %d.") % int(ceil(float(Empire.expedition_running(pj)["finish"])))
			row["target"] = {"view": "expeditions"}
		else:
			var why := Empire.job_blocker(pj)
			if Empire.level_of("guildhall") <= 0:
				why = Loc.t("build the Guildhall first")
			row["state"] = "open" if why == "" else "blocked"
			row["next"] = (Loc.t("Send %s on it from the Guildhall board.") % name) if why == "" else Loc.t("Can't send it yet: %s.") % why
			row["target"] = {"view": "expeditions"} if Empire.level_of("guildhall") > 0 else {"view": "buildings"}
		out.append(row)
	return out


## The mission dict a province offers under this id right now ({} if none).
static func _offered(pid: String, mid: String) -> Dictionary:
	for m in Missions.list_for_province(pid):
		if m.get("id", "") == mid:
			return m
	return {}


## What each faction you know of wants next: the next standing tier and what it opens, then the
## request they have made of you, if any (scripts/faction_asks.gd).
static func faction_quests() -> Array:
	var out := []
	for fid in Empire.faction_ids():
		if not faction_known(fid):
			continue
		var f := Empire.faction(fid)
		var tier := Empire.tier_of(fid)
		var v := Empire.standing_of(fid)
		var row := {"id": "faction_" + fid, "section": "factions", "title": "%s: %s" % [f.get("short", fid), Empire.tier_name(tier)],
			"state": "open", "text": Loc.t("They want: %s") % f.get("wants", "?"), "next": "", "target": {"view": "diplomacy"},
			"where": Empire.territory().find(f.get("province", "")).get("name", ""), "days": -1}
		var nxt := _next_tier(tier)
		var steps := []
		if nxt == "":
			steps.append(Loc.t("Allied. They would cede %s if asked.") % row["where"] if f.has("deals") and f["deals"].has("cede") else Loc.t("Allied."))
			row["state"] = "done"
		else:
			var opens := []
			for k in Empire.DEAL_ORDER:
				if Empire.DEAL_TIER.get(k, "") == nxt and f.get("deals", {}).has(k):
					opens.append("\"%s\" (%s)" % [str(f["deals"][k].get("name", k)), Loc.t(DEAL_WORDS.get(k, k))])
			if nxt == "friendly" and f.has("perk"):
				opens.append(Loc.t("their perk: %s") % str(f["perk"].get("text", "")))
			steps.append(Loc.t("Next: %s at %d standing (now %d).") % [Empire.tier_name(nxt), Empire.tier_min(nxt), v])
			if not opens.is_empty():
				steps.append(Loc.t("That opens %s.") % "; ".join(opens))
			var env := Empire.envoy_of(fid)
			var rate := Empire.standing_rate(fid)
			if env == "":
				steps.append(Loc.t("Post an envoy with high %s (Roster).") % Loc.t(Empire.STAT_NAMES.get(f.get("respects", ""), "?")))
			else:
				steps.append(Loc.t("%s is your envoy: %+d a day.") % [Empire.short_name(env), rate])
			if f.get("deals", {}).has("gift"):
				steps.append(Loc.t("A gift (%s) buys standing faster.") % f["deals"]["gift"].get("name", "gift"))
		if Empire.trouble_text(fid) != "":
			steps.append(Empire.trouble_text(fid))
			row["state"] = "blocked"
		row["next"] = " ".join(steps)
		out.append(row)
		out.append_array(FactionAsks.rows(fid))  # what they asked of you (issue #131)
	return out


static func _next_tier(tier: String) -> String:
	var r := Empire.tier_rank(tier)
	return "" if r + 1 >= Empire.tier_data.size() else str(Empire.tier_data[r + 1]["id"])


## A faction is known once its home province's region is open.
static func faction_known(fid: String) -> bool:
	var p := Empire.territory().find(str(Empire.faction(fid).get("province", "")))
	return p.is_empty() or Empire.province_open(p)


## Missions on offer that are not story or personal, and timed threats: a surge gathering,
## Verity's plans. Timed ones first, soonest first.
static func open_quests() -> Array:
	var timed := []
	var rest := []
	if not Story.command_on():
		return []
	for p in Empire.territory().provinces:
		if not Empire.province_open(p):
			continue
		for m in Missions.list_for_province(p["id"]):
			var typ := str(m.get("type", ""))
			if m.get("story", false) or typ == "personal":
				continue
			var row := {"id": "mission_" + str(m.get("id", "")), "section": "open", "title": str(m.get("name", Loc.t("Mission"))),
				"state": "open" if str(m.get("blocker", "")) == "" else "blocked", "text": str(m.get("brief", "")),
				"next": "", "target": {"province": p["id"], "mission": str(m.get("id", ""))}, "where": p["name"], "days": -1,
				"type": typ if typ != "" else "patrol"}
			if str(m.get("blocker", "")) != "":
				row["next"] = Loc.t("Can't start yet: %s.") % m["blocker"]
			if typ == "defense":
				row["days"] = Empire.surge_days_left()
				row["next"] = Loc.t("Lands in %s if nobody holds the line. %s") % [_days(row["days"]), row["next"]]
			elif m.has("until_day"):
				row["days"] = maxi(int(m["until_day"]) - Empire.day, 0)
				row["next"] = Loc.t("Offered for %s more. %s") % [_days(row["days"]), row["next"]]
			elif row["next"] == "":
				row["next"] = Loc.t("Launch it from %s on the territory map.") % p["name"]
			row["next"] = str(row["next"]).strip_edges()
			(timed if row["days"] >= 0 else rest).append(row)
		for e in BlankPlans.on(p):
			var row2 := {"id": "plan_%s_%s" % [p["id"], e["label"]], "section": "open", "title": "%s: %s" % [p["name"], e["label"]],
				"state": "blocked", "text": Loc.t("The Blank is leaning on %s harder than its spread explains: +%d Fray a day.") % [p["name"], int(e["per_day"])],
				"next": Loc.t("%s left.%s") % [_days(int(e["days"])), (" " + str(e["note"]) + ".") if str(e["note"]) != "" else ""],
				"target": {"province": p["id"]}, "where": p["name"], "days": int(e["days"]), "type": "plan"}
			timed.append(row2)
	timed.sort_custom(func(a, b): return int(a["days"]) < int(b["days"]))
	# Repeatable patrols last: always there, never urgent.
	rest.sort_custom(func(a, b): return int(a["type"] == "patrol") < int(b["type"] == "patrol"))
	return timed + rest


static func _days(n: int) -> String:
	if n <= 0:
		return Loc.t("less than a day")
	return Loc.days(n)


static func _where(target: Dictionary) -> String:
	return Empire.territory().find(str(target.get("province", ""))).get("name", "")


# ---------------------------------------------------------------- people

## Everyone met, grouped: [{"id", "group" (roster|gate|lead|figure), "name", "title"}].
static func people() -> Array:
	var out := []
	for id in Empire.roster_ids():
		var r := Empire.recruit(id)
		out.append({"id": id, "group": "roster", "name": r.get("name", id), "title": r.get("title", "")})
	for id in Empire.lead_ids():
		var r := Empire.recruit(id)
		out.append({"id": id, "group": "gate" if Empire.is_visitor(id) else "lead", "name": r.get("name", id), "title": r.get("title", "")})
	for f in figures():
		out.append({"id": f["id"], "group": "figure", "name": f.get("name", ""), "title": f.get("title", "")})
	return out


static func figures() -> Array:
	return data().get("figures", []).filter(func(f): return meets(f.get("unlock", {})))


static func figure(id: String) -> Dictionary:
	for f in data().get("figures", []):
		if f.get("id", "") == id:
			return f
	return {}


## How many could still join that nobody has even heard of yet (no join hook = no rumour).
static func unheard_count() -> int:
	var n := 0
	for id in Empire.recruit_data:
		if not Empire.recruits.has(id) and Empire.join_hook(id).is_empty() and not Empire.recruit(id).get("start", false):
			n += 1
	return n


# ---------------------------------------------------------------- codex

## Every codex entry as the screen shows it, in data order within each category:
## {"id", "cat", "title", "unlocked", "new", "paras": [text], "facts": [[label, value]], "hint"}.
static func codex() -> Array:
	var out := []
	for c in data().get("codex", []):
		out.append(_codex_entry(c))
		if c.has("region"):  # each region's provinces follow it
			for p in Empire.territory().provinces:
				if p.get("region", "") == c["region"]:
					out.append(_province_entry(p))
	out.append_array(Help.codex_entries())  # every explainer and tip, from data/help.json (issue #115)
	return out


static func codex_in(cat: String) -> Array:
	return codex().filter(func(e): return e["cat"] == cat and (e["unlocked"] or e["hint"] != ""))


## Codex entries unlocked but not read yet. Cheap (no facts are built) and cached for half a second,
## since the Command Table asks every frame.
static var _unread := 0
static var _unread_at := -100000


static func unread_count() -> int:
	var now := Time.get_ticks_msec()
	if now - _unread_at < 500:
		return _unread
	_unread_at = now
	var n := 0
	for c in data().get("codex", []):
		if not is_read(str(c.get("id", ""))) and meets(_unlock(c)):
			n += 1
	for p in Empire.territory().provinces:
		if not is_read("place_" + str(p["id"])) and Empire.province_open(p):
			n += 1
	_unread = n
	return n


static func _unlock(c: Dictionary) -> Dictionary:
	if c.has("unlock"):
		return c["unlock"]
	if c.has("region"):
		return {"region": c["region"]}
	if c.has("faction"):
		var p := Empire.territory().find(str(Empire.faction(c["faction"]).get("province", "")))
		return {"region": p.get("region", "")} if not p.is_empty() else {}
	if c.has("enemy"):
		return {"enemy_seen": c["enemy"]}
	if c.has("ink"):
		return {"ink": c["ink"]}
	return {}


static func _codex_entry(c: Dictionary) -> Dictionary:
	var id: String = c.get("id", "")
	var ok := meets(_unlock(c))
	var e := {"id": id, "cat": str(c.get("cat", "")), "title": str(c.get("title", id)), "unlocked": ok,
		"new": ok and not is_read(id), "paras": [], "facts": [], "hint": "", "indent": 0}
	if not ok:
		if c.has("region"):  # a locked region is still rumoured on the map, under the fog
			var r := Empire.territory().region(c["region"])
			e["hint"] = Loc.t("Rumoured. %s (Chapter %d.)") % [r.get("hint", ""), int(r.get("chapter", 0))]
		elif c.has("enemy") and c.get("cat", "") == "enemies":
			e["hint"] = Loc.t("Not met yet.")
			e["title"] = "???"
		return e
	e["paras"].append(str(c.get("text", "")))
	e["paras"].append_array(paragraphs(c.get("more", [])))
	if c.has("enemy"):
		_enemy_facts(c, e)
	elif c.has("faction"):
		_faction_facts(str(c["faction"]), e)
	elif c.has("ink"):
		_ink_facts(str(c["ink"]), e)
	elif c.has("region"):
		var r := Empire.territory().region(c["region"])
		e["facts"].append([Loc.t("Mood"), str(r.get("mood", ""))])
		var held := 0
		var total := 0
		for p in Empire.territory().provinces:
			if p.get("region", "") == c["region"]:
				total += 1
				held += 1 if p["owner"] == "you" else 0
		e["facts"].append([Loc.t("Held"), Loc.n("%d of %d province", "%d of %d provinces", total) % [held, total]])
		if r.has("pressure"):
			e["facts"].append([Loc.t("Pressure"), Loc.t("%s: +%d Fray a day everywhere here") % [r["pressure"].get("label", ""), int(r["pressure"].get("per_day", 0))]])
	return e


static func _province_entry(p: Dictionary) -> Dictionary:
	var id: String = "place_" + str(p["id"])
	var ok := Empire.province_open(p)
	var e := {"id": id, "cat": "places", "title": str(p["name"]), "unlocked": ok, "new": ok and not is_read(id),
		"paras": [], "facts": [], "hint": "", "indent": 1}
	if not ok:
		return e
	e["paras"].append(str(p.get("blurb", "")))
	e["paras"].append_array(paragraphs(data().get("provinces", {}).get(p["id"], [])))
	var owner: String = p["owner"]
	var who := Loc.t("You") if owner == "you" else (Loc.t("Erased") if owner == "erased" else (Loc.t("Unclaimed") if owner == "free" else str(Empire.faction(owner).get("name", owner))))
	e["facts"].append([Loc.t("Held by"), who])
	if owner != "erased":
		e["facts"].append([Loc.t("Fray"), Loc.t("%d of 100") % int(p["fray"])])
	var gov := Empire.governor_of(p["id"]) if owner == "you" else ""
	if gov != "":
		e["facts"].append([Loc.t("Governor"), Empire.short_name(gov)])
	if p.has("favors"):
		e["facts"].append([Loc.t("Wants a governor with"), "%s. %s" % [Loc.t(Empire.STAT_NAMES.get(p["favors"], p["favors"])), p.get("favors_why", "")]])
	if not p.get("output", {}).is_empty():
		e["facts"].append([Loc.t("Yields a day"), Missions.res_text(p["output"])])
	if not p.get("sites", []).is_empty():
		e["facts"].append([Loc.t("Sites"), ", ".join(p["sites"])])
	var r: Dictionary = EnemyKinds.data().get("rosters", {})
	if r.has(p["id"]):
		var names := []
		for k in r[p["id"]]:
			names.append(EnemyKinds.kind(k).get("plural", k) if seen_enemy(k) else Loc.t("something unmet"))
		e["facts"].append([Loc.t("Out there"), ", ".join(_unique(names))])
	return e


static func _unique(a: Array) -> Array:
	var out := []
	for x in a:
		if not x in out:
			out.append(x)
	return out


static func _enemy_facts(c: Dictionary, e: Dictionary) -> void:
	var kind := str(c["enemy"])
	var k := EnemyKinds.kind(kind)
	var beaten := meets(c["defeat"]) if c.has("defeat") else kills(kind) > 0
	e["paras"].append(Loc.t("Habits: %s") % str(c.get("habits", "")))
	if beaten:
		e["paras"].append(Loc.t("Weakness: %s") % str(c.get("weakness", "")))
	else:
		e["paras"].append(Loc.t("Weakness: beat one to learn it."))
	if not k.is_empty():
		e["facts"].append([Loc.t("Toughness"), Loc.t("%d HP") % int(k.get("hp", 0))])
		if k.has("damage"):
			e["facts"].append([Loc.t("Hits for"), Loc.t("about %d") % int(k["damage"])])
		e["facts"].append([Loc.t("Speed"), Loc.t("fast") if float(k.get("speed", 40)) >= 60 else (Loc.t("quick") if float(k.get("speed", 40)) >= 44 else Loc.t("slow"))])
		if int(k.get("pack", 1)) > 1:
			e["facts"].append([Loc.t("Comes in"), Loc.t("packs of %d or so") % int(k["pack"])])
		e["facts"].append([Loc.t("Born of the Blank"), Loc.t("yes: pours out of surges and Blots too") if k.get("blank", false) else Loc.t("no")])
		var where := []
		var rosters: Dictionary = EnemyKinds.data().get("rosters", {})
		for pid in rosters:
			if rosters[pid].has(kind):
				var p := Empire.territory().find(pid)
				if not p.is_empty() and Empire.province_open(p):
					where.append(p["name"])
		if not where.is_empty():
			e["facts"].append([Loc.t("Found in"), ", ".join(where)])
	e["facts"].append([Loc.t("Beaten"), ("%d" % kills(kind)) if kills(kind) > 0 else (Loc.t("yes") if beaten else Loc.t("not yet"))])


static func _faction_facts(fid: String, e: Dictionary) -> void:
	var f := Empire.faction(fid)
	e["facts"].append([Loc.t("Standing"), "%d (%s)" % [Empire.standing_of(fid), Empire.tier_name(Empire.tier_of(fid))]])
	e["facts"].append([Loc.t("Wants"), str(f.get("wants", ""))])
	e["facts"].append([Loc.t("Respects"), Loc.t("%s in an envoy") % Loc.t(Empire.STAT_NAMES.get(f.get("respects", ""), "?"))])
	e["facts"].append([Loc.t("Home"), str(Empire.territory().find(f.get("province", "")).get("name", "?"))])
	if f.has("perk"):
		e["facts"].append([Loc.t("As friends"), str(f["perk"].get("text", ""))])


static func _ink_facts(color: String, e: Dictionary) -> void:
	var info: Dictionary = Abilities.data().get("inks", {}).get(color, {})
	if info.has("desc"):
		e["facts"].append([Loc.t("Nature"), str(info["desc"])])
	var users := []
	for id in Empire.roster_ids():
		for a in Abilities.for_ids(PartyPicker.hero_data(id).get("abilities", [])):
			if str(a.get("ink", "")) == color:
				users.append("%s (%s)" % [Empire.short_name(id), a.get("name", "")])
	if not users.is_empty():
		e["facts"].append([Loc.t("In your hands"), ", ".join(users)])


static func ink_color(color: String) -> Color:
	if color == "white":
		return Color("f2f0ea")
	return Color(str(Abilities.data().get("inks", {}).get(color, {}).get("color", "c9c3b6")))
