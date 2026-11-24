extends RefCounted
## A scripted player for the balance sim (issue #35). It plays the Command layer the way a steady
## player would, one day at a time, through the same Empire calls the screens use, and fights
## missions on paper (kills, loot rolls, XP and rewards, as main.gd pays them) instead of in a scene.
##
## Policies (what kind of player):
##   idle    plays the story only: no jobs, no buildings, no missions. How fast the Blank wins.
##   casual  posts governors, builds, studies, feasts, one mission every other day. No expeditions or diplomacy.
##   steady  everything, one mission a day, Wardlamps where Fray climbs, claims when it can afford them.
##   rush    like steady, but claims every province it can and never builds lamps.
##
## Used by tools/balance_sim.gd (the long runs and the report) and tests/test_balance.gd (the guard rails).

const POLICIES := ["idle", "casual", "steady", "rush"]
const RESERVE := {"gilt": 40, "supplies": 15}  # what a careful player keeps back for upkeep and surprises
const KILLS_DEFAULT := 14

var policy := "steady"
var log := []  # one Dictionary per day (see snapshot())
var events := []  # [day, text] for firsts: buildings, research, claims, erasures, story
var missions_run := 0
var forge_gilt := 0
var feasts := 0
var hurries := 0
const FEAST_SUPPLIES := 120  # a feast only when the larder holds at least this much
const SELL_ABOVE := 300  # Supplies past this go to the Market
var missions_by_type := {}
var _seen_built := {}


func _init(p := "steady") -> void:
	policy = p


## A fresh story campaign on the morning after the takeover, like a player who has just finished
## Chapter 1 (the prologue and the breakout are paid as main.gd would pay them).
func start() -> void:
	Empire.reset()
	Story.begin()
	for id in ["meadow_prologue", "ch1_breakout"]:
		_fight(Missions.find(id))
	_story()
	Empire.set_speed(1)


## Plays one day: the morning's decisions, a mission, then the clock runs to the next dawn.
func play_day() -> void:
	_story()
	if policy != "idle":
		_hire()
		_bonds()
		_party()
		_governors()
		_claims()
		_staff()
		_build()
		_research()
		_forge()
		_feast()
		_sell_surplus()
		if policy in ["steady", "rush"]:
			_lamps()
			_expeditions()
			_diplomacy()
		_story()
		var cadence := 2 if policy == "casual" else 1
		if Empire.day % cadence == 0:
			var m := pick_mission()
			if not m.is_empty():
				_fight(m)
	_story()
	var before := Empire.day
	Empire.set_speed(1)
	while Empire.day == before:
		Empire.tick(Empire.DAY_SECONDS * (1.0 - Empire.day_t) + 0.01)
	_note_changes()
	log.append(snapshot())


func snapshot() -> Dictionary:
	var t := Empire.territory()
	var held := 0
	var erased := 0
	var fray_max := 0
	var fray_sum := 0
	for p in t.provinces:
		if not Empire.province_open(p):
			continue
		if p["owner"] == "you":
			held += 1
			fray_max = maxi(fray_max, int(p["fray"]))
			fray_sum += int(p["fray"])
		elif p["owner"] == "erased":
			erased += 1
	var lv := []
	for id in Empire.party_ids():
		lv.append(Progress.level(id))
	var net := Empire.daily_net()
	return {
		"day": Empire.day, "gilt": int(Empire.res["gilt"]), "supplies": int(Empire.res["supplies"]), "ink": int(Empire.res["ink"]),
		"renown": int(Empire.res.get("renown", 0)), "insight": int(Empire.res.get("insight", 0)),
		"net_gilt": int(net["gilt"]), "net_supplies": int(net["supplies"]), "net_ink": int(net["ink"]),
		"held": held, "erased": erased, "fray_max": fray_max, "fray_avg": (fray_sum / held) if held > 0 else 0,
		"hungry": Empire.hungry, "roster": Empire.recruits.size(), "level": lv.max() if not lv.is_empty() else 0,
		"level_min": lv.min() if not lv.is_empty() else 0, "ash": Progress.level("ash"),
		"buildings": _building_levels(), "research": Empire.research_done.size(),
		"hollowmark": t.find("hollowmark").get("owner", "") == "you", "missions": missions_run,
	}


func _building_levels() -> int:
	var n := 0
	for id in Empire.buildings:
		n += int(Empire.buildings[id])
	return n


# ---------------------------------------------------------------- story

## Plays every story beat that is due, as walking into town would (talks have no side effects
## beyond being seen; "open_region:" steps are applied the way hub.gd does).
func _story() -> void:
	for i in 10:
		var b := Story.next_beat()
		if b.is_empty() or b.get("repeat", false):
			return
		Dialogue.mark_seen("talk:" + str(b["talk"]))
		events.append([Empire.day, "story: " + str(b["talk"])])
		for step in str(b.get("then", "")).split(",", false):
			if step.strip_edges().begins_with("open_region:"):
				Empire.open_region(step.strip_edges().substr(12))


# ---------------------------------------------------------------- people

func _free(id: String) -> bool:
	var st: Dictionary = Empire.recruits[id]
	return st["role"] == "idle" and int(st["injured"]) <= 0 and not Empire.recruit(id).get("locked_party", false)


func _idle() -> Array:
	return Empire.roster_ids().filter(func(id): return _free(id))


func _hire() -> void:
	for id in Empire.visitors.keys():
		var eats := Empire.UPKEEP_SUPPLIES + (Empire.FIELD_RATIONS if Empire.recruit(id).get("tier", "") == "field" else 0)
		if int(Empire.daily_net()["supplies"]) - eats < 0 and int(Empire.res["supplies"]) < 60:
			continue  # a careful player does not hire mouths the kitchen cannot feed
		if Empire.hire_blocker(id) == "" and _affordable_with_reserve(Empire.hire_cost(id)):
			Empire.hire(id)
			events.append([Empire.day, "hired " + id])


func _bonds() -> void:
	var talked := 0
	for id in Empire.bond_ids():
		if talked < 3 and Empire.recruits.has(id) and Empire.bond_talk(id) > 0:
			talked += 1
	for id in Empire.bond_ready_ids():
		var rank := Empire.bond_next_scene(id)
		if rank > 0 and Empire.bond_scene_blocker(id) == "":
			Empire.finish_bond_scene(id, rank, 0)


## Ash plus the two highest-level field heroes who are free.
func _party() -> void:
	var field := Empire.roster_ids().filter(func(id): return Empire.recruit(id).get("tier", "") == "field")
	field.sort_custom(func(a, b): return Progress.level(a) > Progress.level(b))
	for id in Empire.party_ids():
		if int(Empire.recruits[id]["injured"]) > 0 and not Empire.recruit(id).get("locked_party", false):
			Empire.assign(id, "idle")
	for id in field:
		if Empire.party_ids().size() >= Empire.PARTY_SIZE:
			break
		if Empire.role_of(id) != "party" and _free(id):
			Empire.assign(id, "party")


func _governors() -> void:
	for p in Empire.territory().provinces:
		if p["owner"] != "you" or Empire.governor_of(p["id"]) != "":
			continue
		var best := ""
		var score := -999
		for id in _idle():
			var s := Empire.governor_score(id, p["id"])
			if s > score:
				best = id
				score = s
		if best != "":
			Empire.assign(best, "governor", p["id"])


func _staff() -> void:
	var order := ["scriptorium", "forge", "market", "inkworks", "guildhall", "command_table", "infirmary", "barracks"]
	for bid in order:
		if Empire.level_of(bid) <= 0:
			continue
		while Empire.staff_of(bid).size() < Empire.slots_of(bid):
			var idle := _idle()
			if idle.is_empty():
				return
			if not Empire.assign(idle[0], "staff", bid):
				break


func _claims() -> void:
	var limit := 99 if policy == "rush" else Empire.HOLD_FREE
	for p in Empire.territory().provinces:
		if p["owner"] != "free" or not Empire.province_open(p) or Story.held() >= limit:
			continue
		if Empire.claim_blocker(p["id"]) != "":
			continue
		var cost := Empire.claim_cost(p["id"])
		if not _affordable_with_reserve(cost):
			continue
		if policy != "rush" and int(p["fray"]) >= 60 and Story.held() >= _gate_held():
			continue  # a careful player does not buy land that is about to go, unless the story asks for land
		var best := ""
		var score := -999
		for id in _idle():
			var s := Empire.governor_score(id, p["id"])
			if s > score:
				best = id
				score = s
		if best != "" and Empire.claim(p["id"], best):
			events.append([Empire.day, "claimed " + str(p["id"])])


# ---------------------------------------------------------------- spending

func _affordable_with_reserve(cost: Dictionary) -> bool:
	for k in cost:
		if int(Empire.res.get(k, 0)) - int(cost[k]) < int(RESERVE.get(k, 0)):
			return false
	return true


const HURRY_ABOVE := 300  # Gilt a player keeps before paying to hurry the builders


func _build() -> void:
	if not Empire.construction.is_empty():
		# Spare Gilt buys extra hands (issue #189): one hurry a day while the purse is full.
		if policy != "casual" and int(Empire.res["gilt"]) > HURRY_ABOVE and Sinks.hurry_blocker() == "" and _affordable_with_reserve(Sinks.hurry_cost()):
			Sinks.hurry()
			hurries += 1
		return
	# Roughly what the help cards steer a new player to: income and study first, then the rest.
	var order := ["scriptorium", "guildhall", "inkworks", "market", "barracks", "infirmary", "command_table", "forge"]
	if policy == "casual":
		order = ["market", "scriptorium", "barracks", "inkworks", "infirmary", "guildhall", "command_table", "forge"]
	# A story mission locked behind a building (issue #190) goes first: the briefing and the goal line say so.
	var wanted := _gate_buildings()
	for bid in wanted:
		var wl := Empire.next_level(bid)
		if wl.is_empty() or Empire.build_blocker(bid) != "":
			continue
		if _affordable_with_reserve(wl["cost"]):
			Empire.start_build(bid)
		return  # save up for it rather than spend on something else
	for pass_i in 5:  # first raise everything to 1, then 2, then 3; 4 and 5 once the chapters open them (issue #189)
		for bid in order:
			if Empire.level_of(bid) != pass_i:
				continue
			var nl := Empire.next_level(bid)
			if nl.is_empty() or Empire.build_blocker(bid) != "" or not _affordable_with_reserve(nl["cost"]):
				continue
			Empire.start_build(bid)
			return


## Provinces a story mission on the map wants held before it opens (0 for none, issue #190).
func _gate_held() -> int:
	var n := 0
	for m in Missions.all():
		if m.get("story", false) and m.has("gate") and Missions.offered(m):
			n = maxi(n, int(m["gate"].get("held", 0)))
	return n


## Buildings a story mission on the map is still waiting for (its "gate", issue #190).
func _gate_buildings() -> Array:
	var out := []
	for m in Missions.all():
		if not m.get("story", false) or not m.has("gate") or not Missions.offered(m):
			continue
		var built: Dictionary = m["gate"].get("built", {})
		for bid in built:
			if Empire.level_of(bid) < int(built[bid]) and not bid in out:
				out.append(bid)
	return out


func _research() -> void:
	if Empire.research_active != "":
		return
	var best := ""
	var cost := 99999
	for id in Empire.research_ids():
		if Empire.research_blocker(id) != "":
			continue
		var c := int(Empire.research_cost(id).get("insight", 0))
		if c < cost:
			best = id
			cost = c
	if best != "":
		Empire.start_research(best)


## Weapon upgrades at the Forge for the party, the main Gilt sink after buildings (issue #112).
func _forge() -> void:
	if Armory.forge_level() <= 0:
		return
	for id in Empire.party_ids():
		var r := Armory.upgrade_recipe(Armory.weapon_now(id))
		if r.is_empty() or Armory.craft_blocker(r) != "" or not _affordable_with_reserve({"gilt": int(r["gilt"])}):
			continue
		if Armory.start(r):
			events.append([Empire.day, "forge " + str(r["result"])])
			forge_gilt += int(r["gilt"])


## A feast when the larder is well stocked and nothing is short (issue #189): what a player does with
## spare Supplies once Act 1 is over.
func _feast() -> void:
	if Sinks.feast_blocker() != "" or int(Empire.res["supplies"]) < FEAST_SUPPLIES:
		return
	if _affordable_with_reserve(Sinks.feast_cost()) and Sinks.hold_feast():
		feasts += 1


## A full granary goes to the Market (issue #189); the Gilt goes on to the builders.
func _sell_surplus() -> void:
	for i in 20:
		if int(Empire.res["supplies"]) <= SELL_ABOVE or not Sinks.sell_supplies():
			return


func _lamps() -> void:
	for p in Empire.territory().provinces:
		if p["owner"] != "you" or Empire.fray_rate(p) <= 0 and int(p["fray"]) < 40:
			continue
		var nl := Empire.lamp_next(p["id"])
		if nl.is_empty() or Empire.lamp_blocker(p["id"]) != "" or not _affordable_with_reserve(nl["cost"]):
			continue
		Empire.start_lamp(p["id"])


func _expeditions() -> void:
	for jid in Empire.job_ids():
		if Empire.job_blocker(jid) != "":
			continue
		var pool := Empire.roster_ids().filter(func(id): return _free(id) and Empire.squad_blocker(id) == "")
		if pool.size() < Empire.SQUAD_MIN:
			return
		pool.sort_custom(func(a, b): return Empire.job_strength(jid, a) > Empire.job_strength(jid, b))
		var squad := pool.slice(0, Empire.SQUAD_MIN)
		while squad.size() < mini(Empire.SQUAD_MAX, pool.size()) and int(Empire.expedition_odds(jid, squad)["chance"]) < 70:
			squad.append(pool[squad.size()])
		if int(Empire.expedition_odds(jid, squad)["chance"]) < 60:
			continue
		if not _affordable_with_reserve(Empire.expedition_cost(jid, squad.size())):
			continue
		if Empire.send_expedition(jid, squad):
			events.append([Empire.day, "expedition " + jid])


func _diplomacy() -> void:
	if not Help.is_open("diplomacy"):
		return
	for fid in Empire.faction_ids():
		if Empire.envoy_of(fid) == "" and Empire.standing_rate(fid) <= 0:
			var idle := _idle()
			if idle.size() <= 1:  # keep one spare for a claim
				break
			var best: String = idle[0]
			for id in idle:
				if int(Empire.envoy_effect(id, fid)["drift"]) > int(Empire.envoy_effect(best, fid)["drift"]):
					best = id
			Empire.assign(best, "envoy", fid)
		for kind in ["trade", "aid"]:
			var d := Empire.deal(fid, kind)
			if not d.is_empty() and Empire.deal_blocker(fid, kind) == "" and _affordable_with_reserve(d.get("cost", {})):
				Empire.make_deal(fid, kind)


# ---------------------------------------------------------------- missions on paper

## The mission a steady player would pick today: hold a surge on your land, then the story, then
## take erased land back, people to rescue, raids and salvage, then a patrol where Fray is worst.
func pick_mission() -> Dictionary:
	var t := Empire.territory()
	var offers := []
	for p in t.provinces:
		if not Empire.province_open(p):
			continue
		for m in Missions.list_for_province(p["id"]):
			if str(m.get("blocker", "")) != "":
				continue
			offers.append([_priority(m, p), m])
	if offers.is_empty():
		return {}
	offers.sort_custom(func(a, b): return a[0] > b[0])
	return offers[0][1]


func _priority(m: Dictionary, p: Dictionary) -> float:
	var kind := str(m.get("type", m.get("objective", {}).get("kind", "")))
	var mine: bool = p["owner"] == "you"
	if kind == "defense":
		return 100.0 if mine else 20.0
	if m.get("story", false):
		return 90.0
	if kind == "reclaim":
		return 70.0 if Empire.borders_yours(p["id"]) else 5.0
	if kind == "rescue":
		return 60.0
	if m.has("personal") or kind == "personal":
		return 55.0
	if kind in ["raid", "salvage"]:
		return 40.0
	return float(p["fray"]) / 3.0 + (10.0 if mine else 0.0)


## Fights a mission on paper and pays it out the way main.gd and the results screen do.
func _fight(m: Dictionary) -> void:
	if m.is_empty():
		return
	Empire.active_mission = m.duplicate(true)
	Empire.mission_kills_bonded = 0
	var party := PartyPicker.mission_party(m)
	var obj: Dictionary = m.get("objective", {})
	var kills := int(obj.get("count", KILLS_DEFAULT)) if str(obj.get("kind", "")) == "kills" else KILLS_DEFAULT
	if str(obj.get("kind", "")) == "boss":
		kills = 8
	var found := {}
	var xp := 0
	for i in kills:
		var got := Missions.roll_loot(m)
		for k in got:
			found[k] = int(found.get(k, 0)) + int(got[k])
		var kind := EnemyKinds.pick(m)
		var mats := Armory.roll_mats(kind, m)
		for k2 in mats:
			found[k2] = int(found.get(k2, 0)) + int(mats[k2])
		xp += int(EnemyKinds.kind(kind).get("xp", 3))
		Empire.bond_fought(i + 1, party)
	if str(obj.get("kind", "")) == "boss":
		xp += 60
	Progress.award(party, xp)
	var r := Missions.settle(m, "success", found, {"kills": kills, "time": 300.0, "info": {}})
	Progress.award(party, Progress.mission_xp(m))
	Missions.apply(r)
	missions_run += 1
	var tk := str(m.get("type", obj.get("kind", "?")))
	missions_by_type[tk] = int(missions_by_type.get(tk, 0)) + 1


# ---------------------------------------------------------------- firsts

func _note_changes() -> void:
	for id in Empire.buildings:
		var lv := int(Empire.buildings[id])
		if lv > int(_seen_built.get(id, -1)):
			if _seen_built.has(id):
				events.append([Empire.day, "%s level %d" % [id, lv]])
			_seen_built[id] = lv
