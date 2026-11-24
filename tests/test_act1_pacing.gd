extends "res://tests/test_case.gd"
## Act 1 pacing (issue #190): the two Act 1 story missions wait for the empire. The Concord Answers needs
## 4 provinces held and 8 Renown, the Auditor needs 15 Renown and an Infirmary. Both sit on the map locked
## with what is missing, the story checklist names the goal in between, and the guard rail checks that a
## steady player no longer finishes Act 1 in a week.

const Bot := preload("res://tools/balance_bot.gd")

var Empire: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Empire.reset()
	Story.begin()
	for id in ["gristle", "ninefingers"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for m in ["meadow_prologue", "ch1_breakout"]:
		Empire.missions_cleared.append(m)
	for t in ["meadow_intro", "ch1_arrest", "ch1_takeover", "act1_rumours", "act1_writ"]:
		Dialogue.mark_seen("talk:" + t)
	_hold(["hollowmark", "meadow", "oldmill"])
	Empire.res["renown"] = 0


## Exactly these provinces are yours (the rest go back to free land).
func _hold(ids: Array) -> void:
	for p in Empire.territory().provinces:
		if p["id"] in ids:
			p["owner"] = "you"
		elif p["owner"] == "you":
			p["owner"] = "free"


func _listed(pid: String, mid: String) -> Dictionary:
	for m in Missions.list_for_province(pid):
		if m.get("id", "") == mid:
			return m
	return {}


func test_the_concord_waits_for_land_and_renown() -> void:
	var m := _listed("oldmill", "act1_concord")
	check(not m.is_empty(), "The Concord Answers is on the map once the writ is read")
	check_eq(str(m.get("blocker", "")), Loc.t("needs %d Renown") % 8, "locked until Hollowmark has some Renown")
	Empire.res["renown"] = 8
	check_eq(str(_listed("oldmill", "act1_concord").get("blocker", "")), Loc.t("hold %d provinces") % 4,
		"then it wants a fourth province")
	_hold(["hollowmark", "meadow", "oldmill", "saltreed"])
	check_eq(str(_listed("oldmill", "act1_concord").get("blocker", "")), "", "open with 4 provinces and 8 Renown")


func test_the_auditor_waits_for_an_infirmary_and_renown() -> void:
	Empire.missions_cleared.append("act1_concord")
	Dialogue.mark_seen("talk:act1_concord_after")
	Empire.res["renown"] = 15
	Empire.buildings["infirmary"] = 0
	var m := _listed("tithe", "auditor_duel")
	check(not m.is_empty(), "the Auditor is on the map after the Concord")
	check_eq(str(m.get("blocker", "")), Loc.t("build the %s") % Empire.building("infirmary")["name"],
		"locked until the Infirmary stands")
	Empire.buildings["infirmary"] = 1
	Empire.res["renown"] = 14
	check_eq(str(_listed("tithe", "auditor_duel").get("blocker", "")), Loc.t("needs %d Renown") % 15, "and 15 Renown")
	Empire.res["renown"] = 15
	check_eq(str(_listed("tithe", "auditor_duel").get("blocker", "")), "", "open with both")


func test_built_condition_names_the_level() -> void:
	Empire.buildings["forge"] = 1
	check_eq(Story.blocker({"built": {"forge": 2}}), Loc.t("raise the %s to level %d") % [Empire.building("forge")["name"], 2],
		"a higher level is asked for by number")
	Empire.buildings["forge"] = 2
	check(Story.meets({"built": {"forge": 2}}), "met at that level")


func test_the_goal_line_says_what_is_missing() -> void:
	var g := Alerts.goal()
	check(str(g.get("text", "")).begins_with("Make Hollowmark worth answering"), "the next goal is the Concord's gate (%s)" % g.get("text", ""))
	Empire.res["renown"] = 8
	_hold(["hollowmark", "meadow", "oldmill", "saltreed"])
	g = Alerts.goal()
	check(str(g.get("text", "")).begins_with("The Concord Answers"), "then the mission itself (%s)" % g.get("text", ""))
	check_eq(g.get("target", {}).get("mission", ""), "act1_concord", "and Tab goes to it")
	Empire.missions_cleared.append("act1_concord")
	Dialogue.mark_seen("talk:act1_concord_after")
	Empire.buildings["infirmary"] = 0
	g = Alerts.goal()
	check(str(g.get("text", "")).begins_with("Ready Hollowmark for the Auditor"), "then the Auditor's gate (%s)" % g.get("text", ""))
	check_eq(g.get("target", {}).get("view", ""), "buildings", "and Tab opens the Buildings screen")
	var shown := Story.goals().map(func(x): return x["text"])
	check(not shown.any(func(t): return str(t).begins_with("Make Hollowmark worth answering")),
		"the Concord's gate leaves the checklist once the Concord is done")


func test_a_steady_player_no_longer_finishes_act1_in_a_week() -> void:
	var bot = Bot.new("steady")
	seed(1000)
	bot.start()
	Empire.rng.seed = 1000
	var boss_day := -1
	for d in 40:
		bot.play_day()
		if Missions.cleared("auditor_duel"):
			boss_day = int(bot.log[-1]["day"])
			break
	check(boss_day > 0, "Act 1 can still be finished in 40 days")
	check(boss_day >= 10, "but not in a week (day %d)" % boss_day)
	check(boss_day <= 20, "and not dragged out either (day %d)" % boss_day)
