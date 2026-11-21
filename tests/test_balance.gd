extends "res://tests/test_case.gd"
## Balance guard rails (issue #35). A scripted player (tools/balance_bot.gd) runs the Command layer
## day by day, fighting missions on paper, and the economy has to stay inside the bands below.
## The long runs and the full report are tools/balance_sim.gd (docs/BALANCE.md).

const Bot := preload("res://tools/balance_bot.gd")


func _run(policy: String, days: int, s := 1000):
	var bot = Bot.new(policy)
	seed(s)
	bot.start()
	Empire.rng.seed = s
	for d in days:
		bot.play_day()
		if not bot.log[-1]["hollowmark"]:
			break
	return bot


func _hungry_days(bot) -> int:
	return bot.log.filter(func(x): return x["hungry"]).size()


func _at(bot, day: int) -> Dictionary:
	for snap in bot.log:
		if int(snap["day"]) >= day:
			return snap
	return bot.log[-1]


func test_a_steady_player_holds_on_without_piling_up_supplies() -> void:
	var bot = _run("steady", 40)
	var last: Dictionary = bot.log[-1]
	check(last["hollowmark"], "Hollowmark stands after 40 days")
	check(_hungry_days(bot) <= 3, "almost never hungry (%d days)" % _hungry_days(bot))
	var d20 := _at(bot, 20)
	check(d20["supplies"] < 300, "Supplies do not pile up by day 20 (%d)" % d20["supplies"])
	check(d20["net_supplies"] <= 10, "Supplies grow gently by day 20 (%+d a day)" % d20["net_supplies"])
	check(d20["gilt"] < 600, "Gilt is still worth spending by day 20 (%d)" % d20["gilt"])
	check(Missions.cleared("auditor_duel"), "Act 1 can be finished")
	check(d20["buildings"] >= 6, "something gets built (%d levels by day 20)" % d20["buildings"])


func test_party_levels_follow_the_curve() -> void:
	var bot = Bot.new("steady")
	seed(1000)
	bot.start()
	var boss_lv := 0
	for d in 40:
		bot.play_day()
		if boss_lv == 0 and Missions.cleared("auditor_duel"):
			boss_lv = bot.log[-1]["level"]
	check(boss_lv >= 5 and boss_lv <= 9, "the Auditor is met around level 6 to 8 (Lv %d)" % boss_lv)
	var lv40: int = bot.log[-1]["level"]
	check(lv40 <= 15, "level 20 is still far off on day 40 (Lv %d)" % lv40)
	check(lv40 >= 9, "but the party keeps growing (Lv %d)" % lv40)


func test_a_casual_player_is_not_starved() -> void:
	var bot = _run("casual", 40)
	check(bot.log[-1]["hollowmark"], "Hollowmark stands")
	check(_hungry_days(bot) <= 3, "almost never hungry (%d days)" % _hungry_days(bot))


func test_doing_nothing_loses_slowly() -> void:
	var bot = _run("idle", 60)
	var lost := -1
	for snap in bot.log:
		if not snap["hollowmark"]:
			lost = snap["day"]
			break
	check(lost > 0, "a player who does nothing loses Hollowmark")
	check(lost >= 15, "but not within two weeks (day %d)" % lost)


func test_fighters_eat_field_rations() -> void:
	Empire.reset()
	var fighters := Empire.field_count()
	check(fighters >= 2, "Ash and Bran are fighters")
	var line := {}
	for l in Empire.ledger():
		if "Field rations" in str(l["label"]):
			line = l
	check_eq(int(line.get("supplies", 0)), -Empire.FIELD_RATIONS * fighters, "one extra Supply a day per fighter")


func test_hunger_has_teeth() -> void:
	Empire.reset()
	var home := Empire.territory().find("hollowmark")
	var fed := Empire.fray_rate(home)
	Empire.hungry = true
	check_eq(Empire.fray_rate(home), fed - Empire.FRAY_TENDED, "hungry people stop tending the land")
	check(Empire.fray_sources(home).any(func(s): return "hungry" in str(s[0])), "and the province panel says why")
	Empire.hungry = false
	Empire.buildings["scriptorium"] = 1
	var reader := ""
	for id in Empire.roster_ids():
		if Empire.assign(id, "staff", "scriptorium"):
			reader = id
			break
	check(reader != "", "someone reads at the Scriptorium")
	var pace := float(Empire.research_pace()["pace"])
	Empire.hungry = true
	check(is_equal_approx(float(Empire.research_pace()["pace"]), pace * Empire.HUNGRY_RESEARCH), "study slows while hungry")
	var bonded := Empire.bond_ids().filter(func(id): return Empire.recruits.has(id))
	if check(not bonded.is_empty(), "someone on the roster has a bond"):
		var id: String = bonded[0]
		Empire.bond_gain(id, 5)
		var before := Empire.bond_points(id)
		Empire.recruits[id]["role"] = "idle"
		Empire._advance_bonds()
		check(Empire.bond_points(id) < before, "tempers go: bonds slip while hungry")


func test_xp_to_reach() -> void:
	check_eq(Progress.xp_to_reach(1), 0, "level 1 is free")
	check_eq(Progress.xp_to_reach(3), Progress.xp_to_next(1) + Progress.xp_to_next(2), "levels add up")
	Empire.reset()
	Progress.award(["ash"], Progress.xp_to_reach(6))
	check_eq(Progress.level("ash"), 6, "the boss test's XP lands on level 6")


func test_f3_shows_the_performance_readout() -> void:
	var diag := autoload("Diag")
	var overlay: CanvasLayer = null
	for c in diag.get_children():
		if c is CanvasLayer and c.has_method("text"):
			overlay = c
	if not check(overlay != null, "Diag carries the F3 overlay"):
		return
	check(not overlay.visible, "off by default")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.pressed = true
	overlay._input(ev)
	check(overlay.visible, "F3 shows it")
	await frames(3)
	var t: String = overlay.text()
	check("fps" in t and "draw calls" in t and "VRAM" in t, "it reads fps, draw calls and memory: " + t.replace("\n", " | "))
	overlay._input(ev)
	check(not overlay.visible, "F3 again hides it")
