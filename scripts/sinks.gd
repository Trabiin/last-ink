class_name Sinks
extends RefCounted
## The late economy (issue #189): what Gilt, Supplies, Ink and Insight are for once Act 1 is over.
##
## - Building levels 4 and 5 (data/buildings.json): each opens with the chapter that opens its region
##   of the map, and costs upkeep every dawn. If the dawn's payout leaves a resource short, the upkeep
##   for it is not paid and every level 4+ building (and every level 3 beacon) works one tier down,
##   as level 3 (a beacon as level 2), until a dawn that pays.
## - Level 3 Wardlamps (beacons): need Beacon Script (research), burn 1 Ink a day. Lamps cost more in
##   later regions (wardlamp.region_cost).
## - Hurrying the builders: pay extra hands to bring the job on the Hollowmark site a day sooner. The
##   one building crew is what limits how fast Gilt turns into buildings, so this is where spare Gilt goes.
## - Selling Supplies at the Market: a full granary goes to the traders in lots, for a little Gilt
##   (more with a charming trader), and the Gilt goes on to the builders.
## - Feasts at the tavern: once Act 1 is over, every few days. Supplies and Gilt per head; bonds,
##   healing, a breather for Hollowmark and a fed party.
## - Ink lessons at the Scriptorium: once Act 1 is over, with the Scriptorium at level 2 and someone at the
##   desks, every benched field hero is taught one of their Ink colours each dawn (LESSON_INK Ink for
##   LESSON_POINTS colour points), up to colour level LESSON_CAP; the last levels still come from real fights,
##   like the Barracks drill. Lessons only spend Ink above LESSON_FLOOR. A switch on the Scriptorium.
## - Research (data/research.json): a fourth node per branch, studies with ranks, and chapter branches;
##   the "mods" numbers are summed by Empire.research_mod().
##
## State lives in Empire.sinks (saved with the empire):
##   {"feast_day": day of the last feast (-99 = never), "fed_until": the day the party's full bellies
##    wear off, "short": resources the last dawn could not pay upkeep in, "told": one-time notices given,
##    "lessons": Ink lessons switched on}

const FEAST_GAP := 6  # days between feasts
const FEAST_PER_HEAD := {"supplies": 4, "gilt": 3}
const FEAST_MIN := {"supplies": 20, "gilt": 20}
const FEAST_BOND := 2  # bond points for everyone with a bond
const FEAST_HEAL := 2  # days off every injury
const FEAST_FRAY := 8  # off Hollowmark's Fray
const FEAST_FED_DAYS := 3
const FEAST_FED_HP := 10  # party max HP on missions while fed
const FEAST_UNLOCK := "auditor_duel"  # the end of Act 1
const LATE_LEVEL := 4  # building levels from here on cost upkeep and open with a region
const UPKEEP_KEYS := ["gilt", "supplies", "ink"]
const LESSON_INK := 2  # Ink a pupil's lesson costs
const LESSON_POINTS := 2  # Ink colour points it teaches (spending Ink on an ability teaches 1 a point)
const LESSON_CAP := 3  # lessons teach a colour up to this level
const LESSON_FLOOR := 30  # lessons leave at least this much Ink in store
const LESSON_LEVEL := 2  # Scriptorium level that teaches

## Pupils the ledger promised lessons to at the start of this dawn (filled by ledger_lines, paid by settle).
static var _lesson_cache: Array = []


static func fresh() -> Dictionary:
	return {"feast_day": -99, "fed_until": 0, "short": [], "told": [], "lessons": true}


static func from_save(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	out["feast_day"] = int(d.get("feast_day", -99))
	out["fed_until"] = int(d.get("fed_until", 0))
	for k in d.get("short", []):
		if str(k) in UPKEEP_KEYS:
			out["short"].append(str(k))
	for k in d.get("told", []):
		out["told"].append(str(k))
	out["lessons"] = bool(d.get("lessons", true))
	return out


static func state() -> Dictionary:
	if Empire.sinks.is_empty():
		Empire.sinks = fresh()
	return Empire.sinks


# ---------------------------------------------------------------- building levels 4 and 5

## The level a building works at today: its real level, or level 3 while upkeep went unpaid.
static func working_level(id: String) -> int:
	var lv := Empire.level_of(id)
	if lv >= LATE_LEVEL and is_short():
		return LATE_LEVEL - 1
	return lv


static func is_short() -> bool:
	return not state()["short"].is_empty()


static func level_spec(id: String, level: int) -> Dictionary:
	var levels: Array = Empire.building(id).get("levels", [])
	return levels[level - 1] if level >= 1 and level <= levels.size() else {}


## The region a building level waits for ("" = none), and why it is locked ("" = open).
static func level_lock(id: String, level: int) -> String:
	var rid := str(level_spec(id, level).get("region", ""))
	if rid == "" or Empire.region_open(rid):
		return ""
	return region_lock_text(rid)


## "opens with Chapter 2 (Saint Ledger's Abbey)" for a region that is still closed.
static func region_lock_text(rid: String) -> String:
	var r := Empire.territory().region(rid)
	return Loc.t("opens with Chapter %d (%s)") % [int(r.get("chapter", 0)), str(r.get("name", rid))]


static func building_upkeep(id: String, level := -1) -> Dictionary:
	if level < 0:
		level = Empire.level_of(id)
	return level_spec(id, level).get("upkeep", {})


static func _lamp_spec(level: int) -> Dictionary:
	var levels: Array = Empire.lamp_data.get("levels", [])
	return levels[level - 1] if level >= 1 and level <= levels.size() else {}


## The level a Wardlamp burns at today: a beacon without its Ink burns as level 2.
static func lamp_working_level(pid: String) -> int:
	var lv := int(Empire.lamps.get(pid, 0))
	if not _lamp_spec(lv).get("upkeep", {}).is_empty() and "ink" in state()["short"]:
		return lv - 1
	return lv


## What a Wardlamp level waits for in research ("" = nothing).
static func lamp_lock(level: int) -> String:
	var rid := str(_lamp_spec(level).get("research", ""))
	if rid == "" or Empire.has_research(rid):
		return ""
	return Loc.t("needs %s (research)") % Empire.research_node(rid).get("name", rid)


## Lamp costs grow with the chapter of the province's region (issue #189): Gilt and Ink only.
static func lamp_cost(pid: String, cost: Dictionary) -> Dictionary:
	var p := Empire.territory().find(pid)
	var ch := int(Empire.territory().region_of(p).get("chapter", 1)) if not p.is_empty() else 1
	var mult := 1.0 + float(Empire.lamp_data.get("region_cost", 0.0)) * maxi(ch - 1, 0)
	if mult <= 1.0:
		return cost
	var c := cost.duplicate()
	for k in ["gilt", "ink"]:
		if c.has(k):
			c[k] = int(ceil(int(c[k]) * mult))
	return c


## Everything the late economy costs at dawn: [{"label", "gilt", "supplies", "ink", "note"}] for the ledger.
static func ledger_lines() -> Array:
	var lines := upkeep_lines()
	_lesson_cache = lesson_pupils(true)
	if not _lesson_cache.is_empty():
		lines.append({"label": Loc.n("Ink lessons (%d pupil)", "Ink lessons (%d pupils)", _lesson_cache.size()) % _lesson_cache.size(), "gilt": 0, "supplies": 0,
			"ink": -LESSON_INK * _lesson_cache.size(), "note": Loc.t("Scriptorium")})
	return lines


## The upkeep lines alone: level 4+ buildings and beacons.
static func upkeep_lines() -> Array:
	var lines := []
	var tot := {"gilt": 0, "supplies": 0, "ink": 0}
	var names := []
	for id in Empire.building_ids():
		var up := building_upkeep(id)
		if up.is_empty():
			continue
		names.append("%s %d" % [Empire.building(id)["name"], Empire.level_of(id)])
		for k in UPKEEP_KEYS:
			tot[k] += int(up.get(k, 0))
	if not names.is_empty():
		lines.append({"label": Loc.t("Upkeep: level 4+ buildings (%d)") % names.size(), "gilt": -tot["gilt"], "supplies": -tot["supplies"],
			"ink": -tot["ink"], "note": Loc.t("works as level 3 while unpaid") if is_short() else ""})
	var beacons := 0
	var lamp_ink := 0
	for pid in Empire.lamps:
		var up: Dictionary = _lamp_spec(int(Empire.lamps[pid])).get("upkeep", {})
		if not up.is_empty() and Empire.territory().find(pid).get("owner", "") == "you":
			beacons += 1
			lamp_ink += int(up.get("ink", 0))
	if beacons > 0:
		lines.append({"label": Loc.t("Beacon oil (%d level 3 Wardlamps)") % beacons, "gilt": 0, "supplies": 0, "ink": -lamp_ink,
			"note": Loc.t("burn as level 2 while unpaid") if "ink" in state()["short"] else ""})
	return lines


## Upkeep due at dawn, per resource.
static func upkeep_total() -> Dictionary:
	var tot := {"gilt": 0, "supplies": 0, "ink": 0}
	for line in upkeep_lines():
		for k in UPKEEP_KEYS:
			tot[k] -= int(line[k])
	return tot


## Dawn, after the ledger is paid (Empire._settle): upkeep that left a resource below zero goes
## unpaid instead (the resource stays at what was left), and the late levels work one tier down until
## the next dawn that pays. Supplies run out the usual way (hunger) and count as short too.
static func settle(was_hungry: bool) -> void:
	var pupils := _lesson_cache.duplicate()
	_lesson_cache = []
	if not pupils.is_empty() and int(Empire.res.get("ink", 0)) < 0:  # the dawn ran dry: no lessons today
		Empire.res["ink"] = int(Empire.res["ink"]) + mini(-int(Empire.res["ink"]), LESSON_INK * pupils.size())
		pupils = []
	_teach(pupils)
	var due := upkeep_total()
	var short := []
	for k in ["gilt", "ink"]:
		if int(due[k]) > 0 and int(Empire.res.get(k, 0)) < 0:
			Empire.res[k] = int(Empire.res[k]) + mini(-int(Empire.res[k]), int(due[k]))  # the unpaid part goes back
			short.append(k)
	if int(due["supplies"]) > 0 and was_hungry:
		short.append("supplies")
	var before: Array = state()["short"]
	state()["short"] = short
	if not short.is_empty() and before.is_empty():
		var names := short.map(func(k): return Loc.t(Empire.RES_NAMES[k]))
		Empire.notice.emit(Loc.t("Not enough %s for upkeep: level 4 and 5 buildings work as level 3 (and beacons as level 2) until a dawn that pays.") % Loc.list(names), true)
	elif short.is_empty() and not before.is_empty():
		Empire.notice.emit(Loc.t("Upkeep paid again: every building works at its full level."), false)


# ---------------------------------------------------------------- hurrying the builders

const HURRY_SHARE := {"gilt": 0.3, "supplies": 0.4}  # of the level's own cost, per day brought forward
const HURRY_MIN := {"gilt": 15, "supplies": 4}
const HURRY_LEFT := 0.25  # a job can't be hurried once less than this many days are left


## What bringing the current building job forward a day costs ({} when nothing is being built).
static func hurry_cost() -> Dictionary:
	var c: Dictionary = Empire.construction
	if c.is_empty():
		return {}
	var spec := level_spec(str(c["id"]), Empire.level_of(str(c["id"])) + 1)
	var base: Dictionary = spec.get("cost", {})
	var out := {}
	for k in HURRY_SHARE:
		out[k] = maxi(int(ceil(int(base.get(k, 0)) * float(HURRY_SHARE[k]))), int(HURRY_MIN[k]))
	return out


static func hurry_blocker() -> String:
	var c: Dictionary = Empire.construction
	if c.is_empty():
		return Loc.t("nothing is being built")
	if float(c["finish"]) - (Empire.day + Empire.day_t) <= HURRY_LEFT:
		return Loc.t("almost done already")
	if not Empire.can_afford(hurry_cost()):
		return Loc.t("not enough %s") % Empire._missing(hurry_cost())
	return ""


## Pays for extra hands: the job finishes a day sooner (but never in the past).
static func hurry() -> bool:
	if hurry_blocker() != "":
		return false
	Empire.spend(hurry_cost())
	var c: Dictionary = Empire.construction
	var now := Empire.day + Empire.day_t
	c["finish"] = maxf(float(c["finish"]) - 1.0, now + 0.02)
	c["start"] = minf(float(c["start"]), now - 0.01)
	return true


# ---------------------------------------------------------------- selling Supplies at the Market

const SELL_LOT := 25  # Supplies a sale moves
const SELL_PRICE := 0.4  # Gilt a Supply, before the traders haggle (Market discount = their markup here)


static func sell_gilt() -> int:
	var disc := float(Armory.market_effect().get("discount", 0.0))
	return int(floor(SELL_LOT * SELL_PRICE * (1.0 + disc)))


static func sell_blocker() -> String:
	if Empire.level_of("market") <= 0:
		return Loc.t("build the Market first")
	if int(Armory.market_effect().get("stalls", 0)) <= 0:
		return Loc.t("the Market needs a trader")
	if int(Empire.res.get("supplies", 0)) < SELL_LOT:
		return Loc.t("not enough Supplies")
	return ""


static func sell_supplies() -> bool:
	if sell_blocker() != "":
		return false
	var g := sell_gilt()
	Empire.spend({"supplies": SELL_LOT})
	Empire.gain("gilt", g)
	return true


# ---------------------------------------------------------------- Ink lessons

static func lessons_open() -> bool:
	return feast_open() and Empire.level_of("scriptorium") >= LESSON_LEVEL


static func lessons_on() -> bool:
	return bool(state().get("lessons", true))


static func set_lessons(on: bool) -> void:
	state()["lessons"] = on


## Why nobody is being taught ("" = lessons run).
static func lessons_blocker() -> String:
	if not feast_open():
		return Loc.t("after Act 1")
	if Empire.level_of("scriptorium") < LESSON_LEVEL:
		return Loc.t("needs the Scriptorium at level %d") % LESSON_LEVEL
	if int(Empire.current_effect("scriptorium").get("insight", 0)) <= 0:
		return Loc.t("needs someone at the desks")
	if not lessons_on():
		return Loc.t("switched off")
	return ""


## Who gets a lesson at the next dawn: [[hero id, colour], ...]. Benched field heroes (not in the party),
## each in their lowest colour still under LESSON_CAP. afford: only as many as the Ink above the floor pays for.
static func lesson_pupils(afford := false) -> Array:
	var out := []
	if lessons_blocker() != "":
		return out
	for id in Progress.field_ids():
		if not Empire.recruits.has(id) or Empire.role_of(id) == "party":
			continue
		var best := ""
		for c in Skills.colors_of(id):
			if Skills.ink_level(id, c) < LESSON_CAP and (best == "" or Skills.ink_level(id, c) < Skills.ink_level(id, best)):
				best = c
		if best != "":
			out.append([id, best])
	if afford:
		var can := maxi(int(Empire.res.get("ink", 0)) - LESSON_FLOOR, 0) / LESSON_INK
		out = out.slice(0, mini(out.size(), can))
	return out


static func _teach(pupils: Array) -> void:
	for p in pupils:
		for lvl in Skills.add_ink(p[0], p[1], LESSON_POINTS):
			Empire.notice.emit(Loc.t("%s's %s reached level %d at the Scriptorium's lessons.") % [Empire.short_name(p[0]), Skills.ink_name(p[1]), lvl], false)


static func lessons_text() -> String:
	return Loc.n("Every dawn each benched field hero gets an Ink lesson: %d Ink for %d point in their weakest colour, up to level %d. Lessons only use Ink above %d.", "Every dawn each benched field hero gets an Ink lesson: %d Ink for %d points in their weakest colour, up to level %d. Lessons only use Ink above %d.", LESSON_POINTS) \
		% [LESSON_INK, LESSON_POINTS, LESSON_CAP, LESSON_FLOOR]


# ---------------------------------------------------------------- feasts

static func feast_open() -> bool:
	return Missions.cleared(FEAST_UNLOCK)


static func feast_cost() -> Dictionary:
	var heads := Empire.recruits.size()
	var out := {}
	for k in FEAST_PER_HEAD:
		out[k] = maxi(int(FEAST_PER_HEAD[k]) * heads, int(FEAST_MIN[k]))
	return out


static func feast_ready_day() -> int:
	return int(state()["feast_day"]) + FEAST_GAP


static func feast_blocker() -> String:
	if not feast_open():
		return Loc.t("after Act 1")
	if Empire.day < feast_ready_day():
		var d := feast_ready_day() - Empire.day
		return Loc.n("the tavern is still clearing up (%d more day)", "the tavern is still clearing up (%d more days)", d) % d
	if not Empire.can_afford(feast_cost()):
		return Loc.t("not enough %s") % Empire._missing(feast_cost())
	return ""


static func fed() -> bool:
	return int(state()["fed_until"]) >= Empire.day


## What a feast would do, in one line for the preview.
static func feast_text() -> String:
	return Loc.t("Everyone with a bond +%d, injuries heal %s, Hollowmark Fray -%d, and the party leaves on missions with +%d max HP for %s.") \
		% [FEAST_BOND, Loc.days(FEAST_HEAL), FEAST_FRAY, FEAST_FED_HP, Loc.days(FEAST_FED_DAYS)]


static func hold_feast() -> bool:
	if feast_blocker() != "":
		return false
	Empire.spend(feast_cost())
	state()["feast_day"] = Empire.day
	state()["fed_until"] = Empire.day + FEAST_FED_DAYS - 1
	for id in Empire.bond_ids():
		if Empire.recruits.has(id):
			Empire.bond_gain(id, FEAST_BOND, Loc.t("the feast"), true)
	for id in Empire.recruits:
		var st: Dictionary = Empire.recruits[id]
		st["injured"] = maxi(int(st["injured"]) - FEAST_HEAL, 0)
	var home := Empire.territory().find("hollowmark")
	if not home.is_empty() and home["owner"] == "you":
		home["fray"] = maxi(int(home["fray"]) - FEAST_FRAY, 0)
	Empire.notice.emit(Loc.t("A feast at the tavern. Hollowmark eats, drinks and sings badly until dawn."), false)
	return true


# ---------------------------------------------------------------- one-time notices

## Dawn: tell the player once when something new opens up.
static func dawn() -> void:
	var told: Array = state()["told"]
	if not "feast" in told and feast_open():
		told.append("feast")
		Empire.notice.emit(Loc.t("With the Auditor gone, the tavern can host feasts again. Buildings screen%s, Tavern feast.") % Prompts.tag("buildings"), false)
	for lv in [4, 5]:
		var key := "level_%d" % lv
		if key in told:
			continue
		var opened := false
		for id in Empire.building_ids():
			if not level_spec(id, lv).is_empty() and level_lock(id, lv) == "":
				opened = true
				break
		if opened:
			told.append(key)
			Empire.notice.emit(Loc.t("Your builders can raise Hollowmark's buildings to level %d now. Bigger buildings cost upkeep every day.") % lv, false)
