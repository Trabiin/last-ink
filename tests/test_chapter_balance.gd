extends "res://tests/test_case.gd"
## Chapters 2 and 3 balance pass (issue #138): what the balance sim found once its bot could play
## past Act 1, and the guard rails that keep it fixed. See docs/BALANCE.md, "Chapters 2 and 3".

const Bot := preload("res://tools/balance_bot.gd")

var Empire: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Empire.reset()
	Story.begin()


func _ch2_open() -> void:
	for m in ["meadow_prologue", "ch1_breakout", "act1_concord", "auditor_duel"]:
		Empire.missions_cleared.append(m)
	for t in ["ch1_takeover", "act1_rumours", "act1_writ", "act1_concord_after", "act1_end", "ch2_bells"]:
		Dialogue.mark_seen("talk:" + t)
	Empire.open_region("abbey", true)


# ---------------------------------------------------------------- the Blank and the story

func test_a_province_with_a_story_mission_waiting_cannot_be_erased() -> void:
	_ch2_open()
	var p: Dictionary = Empire.territory().find("candlemere")  # The Wax Barges waits here
	check(Empire.story_holds(p), "Candleford holds while The Wax Barges waits")
	p["fray"] = 99
	p["scar"] = 3
	for i in 3:
		Empire._advance_blank()
	check(p["owner"] != "erased", "Candleford is still standing (owner %s)" % p["owner"])
	check_eq(int(p["fray"]), Empire.STORY_HOLD_FRAY, "it holds at the story line")
	var said: Array = Empire.fray_sources(p).map(func(s): return str(s[0]))
	check(said.any(func(t): return t.contains("story")), "the province panel says why (%s)" % str(said))
	Empire.missions_cleared.append("ch2_candleford")
	check(not Empire.story_holds(p), "once the story is done there, it can fall like anywhere else")


func test_story_missions_not_yet_reachable_do_not_hold_land() -> void:
	var p: Dictionary = Empire.territory().find("candlemere")
	check(not Empire.story_holds(p), "before Chapter 2's bells, Candleford is ordinary land")


func test_faction_seats_tend_their_own_land() -> void:
	_ch2_open()
	var p: Dictionary = Empire.territory().find("abbey")
	var kept: Array = Empire.fray_sources(p).filter(func(s): return str(s[0]).contains("Kept by"))
	check(kept.size() == 1 and int(kept[0][1]) == Empire.FRAY_FACTION_KEPT, "the Abbey keeps its own seat (%s)" % str(kept))


# ---------------------------------------------------------------- Chapter 3's way in

func test_the_terraces_can_be_claimed_from_afar() -> void:
	Empire.open_region("causeway", true)
	var t: Dictionary = Empire.territory().find("terraces")
	check(t.get("landing", false), "the Vauclair Terraces are the Causeway's landing")
	check(Empire.borders_yours("terraces"), "so they count as next to your land")
	check(not str(Empire.claim_blocker("terraces")).contains("Too far"), "no 'too far' once the region is open (%s)" % Empire.claim_blocker("terraces"))
	check(not Empire.borders_yours("inkmere"), "the Shallows still need a neighbour")
	t["owner"] = "you"
	check(Empire.borders_yours("inkmere"), "which the Terraces are")


func test_the_causeway_has_patrols() -> void:
	for pid in ["lanternquay", "inkmere", "terraces", "causeway"]:
		var found: Array = Missions.all().filter(func(m): return m.get("province", "") == pid and str(m.get("id", "")).ends_with("_patrol"))
		check(found.size() == 1, "%s has a patrol" % pid)


# ---------------------------------------------------------------- late joiners

func test_a_late_field_hero_arrives_seasoned() -> void:
	_ch2_open()
	Empire.open_region("causeway", true)
	for id in ["bran", "gristle", "ninefingers"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Progress.hero("ash")["level"] = 14
	Progress.hero("bran")["level"] = 13
	Progress.hero("gristle")["level"] = 12
	Progress.hero("ninefingers")["level"] = 9
	Empire.join_now("hortense")
	check_eq(Progress.level("hortense"), 12, "Hortense joins one under the best three field heroes' average (13)")
	check_eq(Armory.tier_of(Armory.weapon_now("hortense")), 4, "with a tier 4 weapon, one Forge upgrade from the Causeway's tier 5")
	check(not Armory.upgrade_recipe(Armory.weapon_now("hortense")).is_empty(), "and that upgrade is on the Forge's list")


func test_seasoning_never_lowers_anyone_and_skips_light_recruits() -> void:
	Progress.hero("bran")["level"] = 2
	Empire.recruits["bran"] = {"role": "idle", "target": "", "injured": 0}
	Progress.hero("ninefingers")["level"] = 7
	check_eq(Progress.seasoned_join("ninefingers"), "", "nothing to do for someone above the party")
	check_eq(Progress.level("ninefingers"), 7, "level kept")
	check_eq(Progress.seasoned_join("tobble"), "", "light recruits have no field level")
	check_eq(Armory.tier_of(Armory.weapon_now("ninefingers")), 1, "no weapon catch-up before Chapter 2")


# ---------------------------------------------------------------- enemies

func test_enemies_scale_with_the_region() -> void:
	_ch2_open()
	var holder := Node2D.new()
	tree.root.add_child(holder)
	var marches: Array = EnemyKinds.spawn(holder, Vector2.ZERO, {"enemies": {"sellsword": 1}, "province": "oldmill"}, "sellsword")
	var abbey: Array = EnemyKinds.spawn(holder, Vector2.ZERO, {"enemies": {"sellsword": 1}, "province": "quillpine"}, "sellsword")
	var base := int(EnemyKinds.kind("sellsword")["hp"])
	var sc: Dictionary = EnemyKinds.data()["region_scale"]["abbey"]
	check_eq(int(marches[0].max_hp), base, "a sellsword in the Marches is as written")
	check_eq(int(abbey[0].max_hp), int(round(base * float(sc["hp"]))), "and tougher in the Abbey")
	check(is_equal_approx(abbey[0].hit_mult(), float(sc["damage"])), "and hits harder there (%s)" % abbey[0].hit_mult())
	check(is_equal_approx(marches[0].hit_mult(), 1.0), "but not at home")
	holder.free()


func test_region_scale_rises_chapter_by_chapter() -> void:
	var sc: Dictionary = EnemyKinds.data()["region_scale"]
	var last := {"hp": 1.0, "damage": 1.0}
	for r in ["abbey", "causeway", "coast", "spire"]:
		check(sc.has(r), "%s has a scale" % r)
		for k in ["hp", "damage"]:
			check(float(sc[r][k]) > float(last[k]), "%s %s rises over the chapter before" % [r, k])
		last = sc[r]


# ---------------------------------------------------------------- loot

func test_raids_and_salvage_carry_the_regions_materials() -> void:
	_ch2_open()
	var mats: Dictionary = Armory.mats_data()["materials"]
	var pile: Dictionary = MissionTypes.with_region(MissionTypes.data()["salvage"]["pile"], Empire.territory().find("quillpine"), MissionTypes.data()["salvage"]["region_pile"])
	check(pile.keys().any(func(k): return str(mats.get(k, {}).get("region", "")) == "abbey"), "a salvage pile in the Abbey holds Abbey materials")
	var raid: Dictionary = MissionTypes.data()["raid"]
	check(raid["factions"].has("velvet"), "the Velvet Nobility can be raided")
	var guild_quay: Dictionary = MissionTypes.with_region(raid["factions"]["guild"]["cache"], Empire.territory().find("lanternquay"), raid["region_cache"], true)
	check(guild_quay.has("ink_pearl"), "a Guild barge on Lantern Quay carries Causeway goods")
	var abbey_own: Dictionary = MissionTypes.with_region(raid["factions"]["abbey"]["cache"], Empire.territory().find("abbey"), raid["region_cache"], true)
	check_eq(abbey_own, raid["factions"]["abbey"]["cache"], "the Abbey's own undercroft is not topped up")


# ---------------------------------------------------------------- the guard rail

## A steady player (the sim's bot) plays through both chapters at a pace close to Act 1's, and meets
## each boss in the level band its numbers were set for.
func test_a_steady_player_paces_chapters_2_and_3() -> void:
	var bot = Bot.new("steady")
	seed(1000)
	bot.start()
	Empire.rng.seed = 1000
	for d in 70:
		bot.play_day()
		if Missions.cleared("ch3_host"):
			break
	var a: Array = bot.story_days.get("auditor_duel", [])
	var b: Array = bot.story_days.get("ch2_abbot", [])
	var h: Array = bot.story_days.get("ch3_host", [])
	if not check(not a.is_empty() and not b.is_empty() and not h.is_empty(), "Act 1 to Chapter 3 finished in 70 days (%s)" % str(bot.story_days)):
		return
	check(int(b[0]) - int(a[0]) >= 10, "Chapter 2 is not over in a week (%d days)" % (int(b[0]) - int(a[0])))
	check(int(b[0]) - int(a[0]) <= 24, "nor dragged out (%d days)" % (int(b[0]) - int(a[0])))
	check(int(h[0]) - int(b[0]) >= 8 and int(h[0]) - int(b[0]) <= 24, "Chapter 3 takes 8 to 24 days (%d)" % (int(h[0]) - int(b[0])))
	check(int(b[1]) >= 11 and int(b[1]) <= 14, "the Abbot meets a level 11-14 party (%d)" % int(b[1]))
	check(int(h[1]) >= 13 and int(h[1]) <= 16, "the Host meets a level 13-16 party (%d)" % int(h[1]))
	# The Abbot's Forge gate (level 2 works tier 4-5): Abbey steel follows within a few days of him at most.
	check(bot.upgrades.any(func(u): return int(u[2]) == 4 and int(u[0]) <= int(b[0]) + 6), "a tier 4 weapon is forged by day %d (%s)" % [int(b[0]) + 6, str(bot.upgrades)])
