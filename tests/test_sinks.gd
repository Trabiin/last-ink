extends "res://tests/test_case.gd"
## The late economy (issue #189, scripts/sinks.gd): building levels 4 and 5 with upkeep, beacons, research with
## ranks and chapter branches, feasts, Ink lessons and hurrying the builders, plus a long balance guard rail.

const Bot := preload("res://tools/balance_bot.gd")


func _staff(bid: String) -> String:
	for id in Empire.roster_ids():
		if Empire.role_of(id) == "idle" and not Empire.recruit(id).get("locked_party", false) and Empire.assign(id, "staff", bid):
			return id
	return ""


func _dawn() -> void:
	Empire._settle()


func test_levels_4_and_5_open_with_their_chapters() -> void:
	Empire.reset()
	for id in Empire.building_ids():
		check_eq(Empire.max_level(id), 5, "%s has five levels" % id)
		check(not Sinks.building_upkeep(id, 3).is_empty() == false, "%s level 3 costs no upkeep" % id)
		check(not Sinks.building_upkeep(id, 4).is_empty(), "%s level 4 costs upkeep" % id)
	Empire.buildings["guildhall"] = 3
	Empire.res["gilt"] = 5000
	Empire.res["supplies"] = 500
	Empire.res["ink"] = 500
	check(Empire.build_blocker("guildhall").contains("Chapter 2"), "level 4 waits for Chapter 2 (%s)" % Empire.build_blocker("guildhall"))
	Empire.open_region("abbey", true)
	check_eq(Empire.build_blocker("guildhall"), "", "Chapter 2 opens level 4")
	Empire.buildings["guildhall"] = 4
	check(Empire.build_blocker("guildhall").contains("Chapter 3"), "level 5 waits for Chapter 3")
	Empire.open_region("causeway", true)
	check_eq(Empire.build_blocker("guildhall"), "", "Chapter 3 opens level 5")


func test_upkeep_is_paid_at_dawn_and_unpaid_upkeep_drops_a_tier() -> void:
	Empire.reset()
	Empire.open_region("abbey", true)
	Empire.buildings["scriptorium"] = 4
	check(_staff("scriptorium") != "", "someone reads")
	var l3 := int(Empire.building_effect("scriptorium", 3, Empire.staff_of("scriptorium"))["insight"])
	var l4 := int(Empire.current_effect("scriptorium")["insight"])
	check(l4 > l3, "level 4 does more than level 3 (%d > %d)" % [l4, l3])
	var line := {}
	for l in Empire.ledger():
		if "level 4+" in str(l["label"]):
			line = l
	var up := Sinks.building_upkeep("scriptorium")
	check_eq(int(line.get("ink", 0)), -int(up["ink"]), "the ledger shows the Ink upkeep")
	check_eq(int(line.get("gilt", 0)), -int(up["gilt"]), "and the Gilt upkeep")
	Empire.res["ink"] = 0
	_dawn()
	check(Sinks.is_short(), "no Ink at dawn: upkeep unpaid")
	check(int(Empire.res["ink"]) >= 0, "Ink never goes below zero for upkeep (%d)" % int(Empire.res["ink"]))
	check_eq(int(Empire.current_effect("scriptorium")["insight"]), l3, "the Scriptorium works as level 3 meanwhile")
	Empire.res["ink"] = 50
	_dawn()
	check(not Sinks.is_short(), "a dawn that pays clears it")
	check_eq(int(Empire.current_effect("scriptorium")["insight"]), l4, "back to level 4")


func test_ranked_studies_cost_more_and_stack() -> void:
	Empire.reset()
	Empire.buildings["scriptorium"] = 3
	_staff("scriptorium")
	for id in ["arms_whetstone", "arms_leather", "arms_steel"]:
		Empire.research_done.append(id)
	Empire.res["insight"] = 1000
	Empire.res["ink"] = 100
	check(Empire.research_blocker("arms_study") != "", "the study waits for Tempered Edges")
	Empire.research_done.append("arms_temper")
	var base_dmg := int(Empire.mission_boosts()["damage"])
	var c0 := int(Empire.research_cost("arms_study")["insight"])
	var d0 := Empire.research_days("arms_study")
	check(Empire.start_research("arms_study"), "the study starts")
	Empire._advance_research(100.0)
	check_eq(Empire.research_rank("arms_study"), 1, "rank 1")
	check_eq(Empire.research_state("arms_study"), "available", "it stays open for the next rank")
	check(int(Empire.research_cost("arms_study")["insight"]) > c0, "the next rank costs more")
	check(Empire.research_days("arms_study") > d0, "and takes longer")
	check_eq(int(Empire.mission_boosts()["damage"]), base_dmg + 1, "rank 1: +1 damage")
	for i in 4:
		check(Empire.start_research("arms_study"), "rank %d starts" % (i + 2))
		Empire._advance_research(100.0)
	check_eq(Empire.research_rank("arms_study"), 5, "rank 5")
	check_eq(Empire.research_state("arms_study"), "done", "every rank studied")
	check_eq(int(Empire.mission_boosts()["damage"]), base_dmg + 5, "five ranks: +5 damage")
	check(Empire.research_blocker("arms_study") != "", "no sixth rank")


func test_research_mods_reach_the_game() -> void:
	Empire.reset()
	var surge := Empire.surge_fray()
	Empire.research_ranks["ward_study"] = 3
	check_eq(Empire.surge_fray(), surge - 3, "Readings of the Edge rank 3: surges 3 lighter")
	Empire.research_ranks["ward_study"] = 0
	Empire.research_done.append("log_relays")
	Empire.buildings["guildhall"] = 1
	check_eq(Empire.expedition_slots(), 2, "Relay Riders: one more expedition")
	Empire.research_done.append("ink_study")
	Empire.research_ranks["ink_study"] = 5
	check_eq(Empire.damage_to_party(100), 90, "Marginal Inks rank 5: 10% less damage")
	var claim := int(Empire.claim_cost("meadow")["gilt"])
	Empire.research_done.append("cw_charts")
	check_eq(int(Empire.claim_cost("meadow")["gilt"]), int(floor(claim * 0.8)), "Ink-Lake Charts: claims 20% cheaper")
	var coast := {}
	for p in Empire.territory().provinces:
		if p.get("region", "") == "coast":
			coast = p
	Empire.open_region("coast", true)
	var with_sea := Empire.fray_rate(coast)
	Empire.research_done.append("co_seawalls")
	check_eq(Empire.fray_rate(coast), with_sea - 1, "Sea-Walls stop the coast's own pressure")


func test_chapter_branches_hide_until_their_region_opens() -> void:
	Empire.reset()
	for b in ["causeway", "coast", "spire"]:
		check(Empire.research_branch_lock(b) != "", "%s research waits for its region" % b)
	check(Empire.research_blocker("cw_masks") != "", "Masked Envoys can't be studied yet")
	Empire.buildings["scriptorium"] = 1
	_staff("scriptorium")
	Empire.res["insight"] = 100
	Empire.open_region("causeway", true)
	check_eq(Empire.research_branch_lock("causeway"), "", "Chapter 3 opens the Causeway branch")
	check_eq(Empire.research_blocker("cw_masks"), "", "Masked Envoys can be studied")
	for id in Empire.research_ids():
		var n := Empire.research_node(id)
		check(n.has("effect") and n.has("blurb") and n.has("name"), "%s has its text" % id)
		for need in n.get("needs", []):
			check(Empire.research_node(need).get("branch", "") == n["branch"], "%s needs a node of its own branch" % id)


func test_beacons_need_research_cost_more_in_later_regions_and_burn_ink() -> void:
	Empire.reset()
	Empire.res["gilt"] = 1000
	Empire.res["ink"] = 100
	Empire.res["supplies"] = 100
	Empire.lamps["hollowmark"] = 2
	check(Empire.lamp_blocker("hollowmark").contains("Beacon Script"), "level 3 needs Beacon Script (%s)" % Empire.lamp_blocker("hollowmark"))
	Empire.research_done.append("ward_beacons")
	check_eq(Empire.lamp_blocker("hollowmark"), "", "then it can be built")
	var home_cost := int(Empire.lamp_next("hollowmark")["cost"]["gilt"])
	var abbey_lamp := Sinks.lamp_cost("abbey", {"gilt": 30, "ink": 2})
	check(int(abbey_lamp["gilt"]) > 30, "a lamp in Chapter 2's region costs more (%d)" % int(abbey_lamp["gilt"]))
	check_eq(int(Sinks.lamp_cost("hollowmark", {"gilt": 30})["gilt"]), 30, "but not at home")
	check(home_cost >= 90, "a beacon is dear (%d Gilt)" % home_cost)
	Empire.lamps["hollowmark"] = 3
	var lit := Empire.fray_rate(Empire.territory().find("hollowmark"))
	var line := {}
	for l in Empire.ledger():
		if "Beacon" in str(l["label"]):
			line = l
	check_eq(int(line.get("ink", 0)), -1, "a beacon burns 1 Ink a day")
	Empire.res["ink"] = 0
	_dawn()
	check_eq(Sinks.lamp_working_level("hollowmark"), 2, "unfed, it burns as level 2")
	check(Empire.fray_rate(Empire.territory().find("hollowmark")) > lit, "and holds back less Fray")


func test_feasts() -> void:
	Empire.reset()
	Empire.res["gilt"] = 1000
	Empire.res["supplies"] = 1000
	check(Sinks.feast_blocker() != "", "no feasts before the end of Act 1")
	Empire.missions_cleared.append(Sinks.FEAST_UNLOCK)
	check_eq(Sinks.feast_blocker(), "", "after the Auditor, the tavern can feast")
	var heads := Empire.recruits.size()
	check_eq(int(Sinks.feast_cost()["supplies"]), maxi(Sinks.FEAST_PER_HEAD["supplies"] * heads, Sinks.FEAST_MIN["supplies"]), "Supplies for every mouth")
	var bonded := Empire.bond_ids().filter(func(id): return Empire.recruits.has(id))
	var who: String = bonded[0] if not bonded.is_empty() else ""
	var before := Empire.bond_points(who) if who != "" else 0
	Empire.recruits["tobble"]["injured"] = 3
	var home := Empire.territory().find("hollowmark")
	home["fray"] = 20
	var hp := int(Empire.mission_boosts()["hp"])
	check(Sinks.hold_feast(), "the feast is held")
	if who != "":
		check_eq(Empire.bond_points(who), before + Sinks.FEAST_BOND, "bonds grow")
	check_eq(int(Empire.recruits["tobble"]["injured"]), 1, "injuries heal two days")
	check_eq(int(home["fray"]), 12, "Hollowmark breathes")
	check_eq(int(Empire.mission_boosts()["hp"]), hp + Sinks.FEAST_FED_HP, "the party leaves fed")
	check(Sinks.feast_blocker() != "", "the tavern needs a few days")
	Empire.day += Sinks.FEAST_GAP
	check(not Sinks.fed(), "full bellies wear off")
	check_eq(Sinks.feast_blocker(), "", "and then it can feast again")


func test_ink_lessons_teach_benched_heroes_from_spare_ink() -> void:
	Empire.reset()
	Empire.missions_cleared.append(Sinks.FEAST_UNLOCK)
	Empire.buildings["scriptorium"] = 2
	_staff("scriptorium")
	var bench := ""
	for id in Empire.recruit_data:
		if Empire.recruit_data[id].get("tier", "") == "field" and not Empire.recruits.has(id) and not Skills.colors_of(id).is_empty():
			bench = id
			break
	if not check(bench != "", "a field hero to teach"):
		return
	Empire.recruits[bench] = {"role": "idle", "target": "", "injured": 0}
	var pupils := Sinks.lesson_pupils()
	check(pupils.any(func(p): return p[0] == bench), "a benched hero gets lessons")
	check(not pupils.any(func(p): return Empire.role_of(p[0]) == "party"), "the party learns in the field instead")
	Empire.res["ink"] = Sinks.LESSON_FLOOR
	check(Sinks.lesson_pupils(true).is_empty(), "no lessons from the last %d Ink" % Sinks.LESSON_FLOOR)
	Empire.res["ink"] = 200
	var col: String = pupils.filter(func(p): return p[0] == bench)[0][1]
	var xp := Skills.ink_xp(bench, col) + (Skills.ink_level(bench, col) - 1) * 1000
	Empire.ledger()
	var before_ink := int(Empire.res["ink"])
	_dawn()
	check(Skills.ink_xp(bench, col) + (Skills.ink_level(bench, col) - 1) * 1000 > xp, "the lesson teaches colour points")
	check(int(Empire.res["ink"]) < before_ink + int(Empire.daily_net()["ink"]) + 10, "and costs Ink")
	Sinks.set_lessons(false)
	check(Sinks.lesson_pupils().is_empty(), "lessons can be switched off")


func test_hurrying_the_builders() -> void:
	Empire.reset()
	Empire.res["gilt"] = 1000
	Empire.res["supplies"] = 100
	check(Sinks.hurry_blocker() != "", "nothing to hurry")
	check(Empire.start_build("barracks"), "the builders start")
	var finish := float(Empire.construction["finish"])
	var gilt := int(Empire.res["gilt"])
	var cost := Sinks.hurry_cost()
	check(Sinks.hurry(), "extra hands")
	check(is_equal_approx(float(Empire.construction["finish"]), finish - 1.0), "a day sooner")
	check_eq(int(Empire.res["gilt"]), gilt - int(cost["gilt"]), "for Gilt")
	check(Sinks.hurry(), "hurried again")
	check(Sinks.hurry_blocker() != "", "until it is almost done")


func test_late_economy_survives_a_save() -> void:
	Empire.reset()
	Empire.research_ranks["ward_study"] = 2
	Empire.sinks["feast_day"] = 9
	Empire.sinks["lessons"] = false
	Empire.sinks["short"] = ["ink"]
	var d: Dictionary = JSON.parse_string(JSON.stringify(Empire.to_dict()))
	Empire.from_dict(d)
	check_eq(Empire.research_rank("ward_study"), 2, "ranks are kept")
	check_eq(int(Empire.sinks["feast_day"]), 9, "the last feast is remembered")
	check(not Sinks.lessons_on(), "the lessons switch is kept")
	check(Sinks.is_short(), "unpaid upkeep is kept until the next dawn")
	d.erase("sinks")
	d.erase("research_ranks")
	Empire.from_dict(d)
	check_eq(Empire.research_rank("ward_study"), 0, "an older save starts with no ranks")
	check(Sinks.lessons_on() and not Sinks.is_short(), "and a fresh late economy")


## The long guard rail behind tools/balance_sim.gd: a steady player 80 days in has spent what Act 1 left
## piling up (issue #189).
func test_nothing_piles_up_after_act_1() -> void:
	var bot = Bot.new("steady")
	seed(1000)
	bot.start()
	Empire.rng.seed = 1000
	for d in 80:
		bot.play_day()
	var last: Dictionary = bot.log[-1]
	check(last["hollowmark"], "Hollowmark stands")
	check(last["insight"] <= 150, "Insight is spent (%d)" % last["insight"])
	check(last["ink"] <= 120, "Ink is spent (%d)" % last["ink"])
	check(last["supplies"] <= 600, "Supplies are spent (%d)" % last["supplies"])
	check(last["gilt"] <= 1500, "Gilt is spent (%d)" % last["gilt"])
	check(bot.feasts > 0, "the bot feasts (%d)" % bot.feasts)
	check(Empire.research_rank("ward_study") + Empire.research_rank("log_study") + Empire.research_rank("ink_study") + Empire.research_rank("arms_study") > 0, "and studies ranks")
