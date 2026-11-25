extends "res://tests/test_case.gd"
## Weapon and Ink skill levels (issue #24): the tech and Ink data, skill points and levels, tiers,
## the Barracks drill, the save step, every tech firing in a real mission, the ally AI choosing among
## techs, and the menus that show it all.

const MAIN := "res://scenes/main.tscn"
const COMMAND := "res://scenes/command.tscn"
## Keys a tech may have (a typo in data/techs.json fails here instead of silently doing nothing).
const TECH_KEYS := ["id", "name", "desc", "color", "fx", "sound", "mult", "reach", "arc", "offset", "knock", "step",
	"hits", "every", "last", "chain", "chain_gap", "chain_delay", "delay", "spread", "knives", "stun", "mark", "mark_mult",
	"execute", "taunt", "guard", "guard_time", "vanish", "crit", "heal", "shield", "shield_time", "ink", "leech", "leech_cap",
	"charm", "weaken", "song", "song_boost"]
const SOUND_KEYS := ["tone", "sweep", "noise", "len", "ring", "thump"]
const KNIFE_KEYS := ["count", "arc", "speed", "range", "mult", "pierce", "knock"]

var Empire: Node
var D := {}


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	Empire.reset()
	for f in ["techs.json", "abilities.json", "heroes.json", "gear.json"]:
		D[f] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0


# ------------------------------------------------------------------ data

func test_every_hero_has_five_techs() -> void:
	var techs: Dictionary = D["techs.json"]["techs"]
	var heroes: Dictionary = D["heroes.json"]["heroes"]
	var stages: Array = D["techs.json"]["stage_hold"]
	check_eq(stages.size(), 5, "a hold time for each of the five techs")
	for i in range(1, stages.size()):
		check(float(stages[i]) > float(stages[i - 1]), "stage_hold rises")
	var seen := {}
	var looks := {}
	for hero in heroes:
		var list: Array = techs.get(hero, [])
		check_eq(list.size(), 5, "%s has five techs" % hero)
		for t in list:
			var w: String = "techs.json %s/%s" % [hero, t.get("id", "?")]
			check(str(t.get("id", "")) != "", w + ": id")
			check(not seen.has(t["id"]), w + ": id used twice")
			seen[t["id"]] = true
			check(not Techs.find(t["id"]).is_empty(), w + ": Techs.find knows it")
			for k in t:
				check(k in TECH_KEYS, "%s: unknown key %s" % [w, k])
			for k in ["name", "desc", "color", "fx", "sound", "reach", "arc"]:
				check(t.has(k), "%s: missing %s" % [w, k])
			check(str(t.get("fx", "")) in TechFx.MOTIFS, "%s: fx %s is not a motif in tech_fx.gd" % [w, t.get("fx")])
			check(Color.html_is_valid(str(t.get("color", ""))), w + ": colour")
			var snd: Dictionary = t.get("sound", {})
			for k in SOUND_KEYS:
				check(snd.has(k), "%s: sound needs %s" % [w, k])
			check(float(t.get("mult", 0)) > 0.0 or t.has("knives"), w + ": no blast and no knives")
			for k in t.get("last", {}):
				check(k in TECH_KEYS, "%s: unknown key %s in last" % [w, k])
			for k in t.get("knives", {}):
				check(k in KNIFE_KEYS, "%s: unknown knife key %s" % [w, k])
			if int(t.get("hits", 1)) > 1:
				check(float(t.get("every", 0)) > 0.0, w + ": several hits need every")
			if int(t.get("chain", 1)) > 1:
				check(float(t.get("chain_gap", 0)) > 0.0, w + ": a chain needs chain_gap")
			looks[str(t["fx"]) + str(t["color"])] = true
	for hero in techs:
		check(heroes.has(hero), "techs.json: %s is not a field hero" % hero)
	check_eq(looks.size(), seen.size(), "every tech looks different (fx + colour)")
	# Saved picks must name real techs: a save with a cut tech reads as "by hold length".
	Empire.recruits["bran"] = {"role": "party", "target": "", "injured": 0}
	Progress.hero("bran")["tech"] = "no_such_tech"
	check_eq(Skills.pick("bran"), "", "an unknown pick reads as by hold length")


func test_abilities_have_ink_colours_and_tiers() -> void:
	var ab: Dictionary = D["abilities.json"]
	check_eq((ab["inks"] as Dictionary).keys(), Skills.INKS, "the six Ink colours, in order (white is Ilse's alone)")
	check_eq((ab["ink_skill"]["xp"] as Array).size(), 4, "points for levels 2 to 5")
	for id in ab["abilities"]:
		var a: Dictionary = ab["abilities"][id]
		var w: String = "abilities.json " + id
		check(str(a.get("ink", "")) in Skills.INKS, w + ": ink colour")
		check(a.get("tiers", {}).has("2") and a.get("tiers", {}).has("4"), w + ": tiers 2 and 4")
		for lvl in [1, 2, 3, 4, 5]:
			var at := Abilities.at_level(Abilities.get_def(id), lvl)
			var text := Abilities.desc_of(at)
			check(text.find("{") < 0 and text.find("}") < 0, "%s: description at level %d has an unfilled {key}: %s" % [w, lvl, text])
		for tier in a.get("tiers", {}):
			for k in a["tiers"][tier]:
				var v = a["tiers"][tier][k]
				if a.has(k) and typeof(a[k]) != TYPE_BOOL:
					# Smaller is stronger for waits, slows and Small Print's damage multiplier.
					var lower_better: bool = k in ["cooldown", "every", "slow"] or (k == "mult" and a.get("kind", "") == "weaken")
					check(float(v) <= float(a[k]) if lower_better else float(v) >= float(a[k]), "%s tier %s: %s gets weaker" % [w, tier, k])


# ------------------------------------------------------------------ levels

func test_weapon_skill_teaches_techs() -> void:
	Empire.recruits["ninefingers"] = {"role": "party", "target": "", "injured": 0}
	check_eq(Skills.weapon_level("ash"), 1, "starts at level 1")
	check_eq(Skills.known_techs("ash").size(), 1, "knows its first tech")
	check_eq(Skills.known_techs("ash")[0]["id"], "full_stop", "the tech from before skills")
	var ups := Skills.add_weapon("ash", Skills.weapon_to_next(1))
	check_eq(ups, [2], "one level")
	check_eq(Skills.known_techs("ash").size(), 2, "level 2 knows two")
	ups = Skills.add_weapon("ash", 100000)
	check_eq(ups, [3, 4, 5], "levels to the top")
	check_eq(Skills.known_techs("ash").size(), 5, "level 5 knows all five")
	check_eq(Skills.add_weapon("ash", 50), [], "nothing past the top")
	check_eq(Skills.swing_points(1.0), 2, "full swing")
	check_eq(Skills.swing_points(0.6), 1, "half swing")
	check_eq(Skills.swing_points(0.2), 0, "weak swing")
	# Picking a tech, and the charge it uses.
	Skills.set_pick("ash", "ellipsis")
	check_eq(Skills.pick("ash"), "ellipsis", "pick kept")
	Skills.set_pick("ninefingers", "concord_breaker")
	check_eq(Skills.pick("ninefingers"), "", "a tech Daro doesn't know yet can't be picked")
	check(Techs.charge_time(Techs.find("the_end")) > Techs.charge_time(Techs.find("full_stop")), "later techs charge longer")


func test_barracks_drill_stops_at_the_cap() -> void:
	Empire.recruits["bran"] = {"role": "idle", "target": "", "injured": 0}
	Empire.buildings["barracks"] = 2
	for i in 200:
		Progress.dawn()
	check_eq(Skills.weapon_level("bran"), Skills.barracks_cap(), "drill reaches the cap")
	check(int(Skills.weapon("bran").get("xp", 0)) < Skills.weapon_to_next(Skills.barracks_cap()), "and stops short of the next level")
	check_eq(Skills.weapon_level("ash"), 1, "Ash is in the party, not drilling")
	Skills.add_weapon("bran", 100000)
	check_eq(Skills.weapon_level("bran"), 5, "real fights go past it")


func test_ink_skill_raises_tiers_and_cuts_cooldowns() -> void:
	var base := Abilities.get_def("cleave")
	Empire.recruits["bran"] = {"role": "party", "target": "", "injured": 0}
	var a1: Dictionary = Abilities.for_ids(["cleave"], "bran")[0]
	check_eq(int(a1["tier"]), 1, "tier 1 at Red 1")
	check_eq(int(a1["damage"]), int(base["damage"]), "base damage")
	check_eq(Skills.add_ink("bran", "red", Skills.ink_to_next(1)), [2], "Red 2")
	var a2: Dictionary = Abilities.for_ids(["cleave"], "bran")[0]
	check_eq(int(a2["tier"]), 2, "tier 2 at Red 2")
	check_eq(int(a2["damage"]), int(base["tiers"]["2"]["damage"]), "tier 2 damage")
	Skills.add_ink("bran", "red", 100000)
	var a5: Dictionary = Abilities.for_ids(["cleave"], "bran")[0]
	check_eq(int(a5["tier"]), 3, "tier 3 at Red 4+")
	check(float(a5["cooldown"]) < float(base["cooldown"]), "Red 5 cooldown is shorter")
	check(float(a5.get("stun", 0)) > 0.0, "tier 3 Cleave stuns")
	check_eq(Skills.ink_level("bran", "blue"), 1, "other colours untouched")
	check_eq(Skills.colors_of("bran"), ["red", "blue"], "Bran's colours")
	check(Abilities.next_tier_text(a1).begins_with("at Red 2"), "menus say what comes next")
	check_eq(Abilities.next_tier_text(a5), "", "nothing after the top tier")


# ------------------------------------------------------------------ saves

func test_old_saves_seed_skills_from_levels() -> void:
	var Saves := autoload("Saves")
	var r: Dictionary = Saves.parse(FileAccess.get_file_as_string("res://tests/fixtures/saves/20261120_weapon_ink_skills__table_day23_veterans.json"))
	if not check_eq(r["status"], Saves.GOOD, "fixture loads"):
		return
	var heroes: Dictionary = r["data"]["empire"]["progress"]["heroes"]
	check_eq(int(heroes["ash"]["weapon"]["level"]), 3, "a level 11 veteran starts at weapon 3 (the drill cap)")
	check_eq(int(heroes["odile"]["weapon"]["level"]), 2, "a level 4 hero starts at weapon 2")
	check_eq(int(heroes["bran"]["inks"]["red"]["level"]), 3, "Ink colours they use are seeded too")
	check(not heroes["bran"]["inks"].has("gold"), "colours they never used stay at 1")
	check_eq(str(heroes["ash"]["tech"]), "", "techs chosen by hold length")
	Empire.from_dict(r["data"]["empire"])
	check_eq(Skills.weapon_level("ninefingers"), 3, "Daro's skill survives loading")
	check_eq(Skills.known_techs("ninefingers").size(), 3, "and Daro knows three techs")
	check_eq(Empire.ai_techs.get("ninefingers", ""), "call", "ally tech mode kept")


# ------------------------------------------------------------------ in a mission

func _mission() -> Node:
	Empire.reset()
	for id in ["bran", "ninefingers"]:
		Empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
	Dialogue.mark_seen("talk:meadow_intro")
	Empire.active_mission = Missions.find("meadow_patrol").duplicate(true)
	return await goto(MAIN, 20)


func _clear_enemies() -> void:
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	await frames(2)


## Every one of the 40 techs fires from a real hero at a real enemy without errors, and lands.
func test_every_tech_fires_and_lands() -> void:
	var main := await _mission()
	if not check(main != null and main.leader != null, "mission running"):
		return
	var h: Hero = main.leader
	h.invuln_t = 999.0
	var home := h.global_position
	var missed := []
	for hero in D["techs.json"]["techs"]:
		for td in D["techs.json"]["techs"][hero]:
			await _clear_enemies()
			var t := Techs.find(td["id"])
			h.global_position = home
			h.facing = Vector2.RIGHT
			if not (t.get("spread", []) as Array).is_empty():  # a V of thrusts: aim one prong at it (a small Moth fits between)
				h.facing = Vector2.RIGHT.rotated(-deg_to_rad(float(t["spread"][0])))
			h.dead = false
			h.hp = h.max_hp
			var stand := AllyTechs.standoff(t)
			var es := []
			for attempt in 5:
				main._spawn_enemy(home + Vector2(stand, 0))
				await frames(1)
				es = tree.get_nodes_in_group("enemies").filter(func(x): return not x.is_queued_for_deletion())
				if not es.is_empty():
					break
			if es.is_empty():
				missed.append(td["id"] + " (no enemy)")
				continue
			var e: Enemy = es[0]
			e.max_hp = 9999
			e.hp = 9999
			e.global_position = home + Vector2(stand, 0)
			e.stun(3.0)  # stands still for the test
			Techs.fire(h, t)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 1300:  # delayed and chained blasts go off within about a second
				await tree.process_frame
			if is_instance_valid(e) and e.hp >= 9999:
				missed.append(td["id"])
	check(missed.is_empty(), "techs that hit nothing: %s" % [missed])
	check(tree.get_nodes_in_group("enemies").size() <= 4, "no runaway spawning")


func test_skill_up_in_a_mission_teaches_and_toasts() -> void:
	var main := await _mission()
	if not check(main != null and main.leader != null, "mission running"):
		return
	var h: Hero = main.leader
	h.gain_skill("weapon", "", Skills.weapon_to_next(1))
	check_eq(Skills.weapon_level(h.hero_id), 2, "weapon level 2 mid-mission")
	check(main.hud.banter_text.find("learned") >= 0, "a toast says what was learned: " + main.hud.banter_text)
	check_eq(Techs.charge_options(h).size(), 2, "the new tech is chargeable right away")
	var bran: Hero = null
	for x in main.heroes:
		if (x as Hero).hero_id == "bran":
			bran = x
	if check(bran != null, "Bran in the party"):
		var cd_before := float(bran.abilities[0]["cooldown"])
		bran.gain_skill("ink", "red", 100000)
		check_eq(int(bran.abilities[0]["tier"]), 3, "Bran's Cleave moved up a tier on the spot")
		check(float(bran.abilities[0]["cooldown"]) < cd_before, "and its cooldown shrank")
	main._show_results("success")
	await frames(3)
	var lines: Array = main.results_view.result.get("lines", [])
	check(lines.any(func(l): return str(l).begins_with("Skills:")), "results list the skills gained")


## Ally AI picks among every tech it knows (#108 + #24), and charges the chosen one for its own time.
func test_allies_choose_among_known_techs() -> void:
	var main := await _mission()
	if not check(main != null, "mission running"):
		return
	var daro: Hero = null
	for x in main.heroes:
		if (x as Hero).hero_id == "ninefingers":
			daro = x
	if not check(daro != null, "Daro in the party"):
		return
	Skills.add_weapon("ninefingers", 100000)
	check_eq(AllyTechs.techs_of(daro).size(), 5, "all five under AI")
	await _clear_enemies()
	for i in 5:  # a crowd all round Daro: The Wheel's kind of moment
		main._spawn_enemy(daro.global_position + Vector2.from_angle(i * TAU / 5.0) * 30.0)
	await frames(1)
	var best := AllyTechs.pick(daro, "aggressive", main.leader, 14.0)
	check(not best["tech"].is_empty(), "a tech is worth it")
	check(best["tech"]["hero"] == "ninefingers", "one of Daro's own")
	Skills.set_pick("ninefingers", "skewer")
	check_eq(AllyTechs.techs_of(daro).size(), 1, "a pick limits the AI to that tech")
	check_eq(AllyTechs.techs_of(daro)[0]["id"], "skewer", "the picked one")


func test_menus_show_skills() -> void:
	var main := await _mission()
	if not check(main != null, "mission running"):
		return
	Skills.add_weapon("ash", Skills.weapon_to_next(1) + Skills.weapon_to_next(2))
	main.open_quick_menu()
	await frames(2)
	var qm = main.quick_menu
	qm._set_tab(QuickMenu.TABS.find("Techs"))
	await frames(2)
	check_eq(qm.rows.size(), main.heroes.size(), "a Techs row per hero")
	qm._pick_row(0)
	await frames(2)
	check(qm.sub.size() >= 6, "by hold length + five techs")
	var ell := -1
	for i in qm.sub.size():
		if qm.sub[i]["id"] == "pick:ellipsis":
			ell = i
	if check(ell >= 0, "Ellipsis listed"):
		qm._pick_sub(ell)
		check_eq(Skills.pick("ash"), "ellipsis", "picked from the quick menu")
	qm.close()
	await frames(2)
	# The Gear screen's Skills tab, at the Command Table.
	var cmd := await goto(COMMAND, 15)
	if not check(cmd != null, "Command Table"):
		return
	cmd.gear_view.open("town")
	cmd.gear_view._set_tab("skills")
	await frames(3)
	check(cmd.gear_view._tech_rects.size() == 5, "five tech rows drawn")
	cmd.gear_view._pick_tech(0)
	check_eq(Skills.pick(cmd.gear_view._hero_id()), "full_stop", "Enter on a tech picks it")
	cmd.gear_view._pick_tech(0)
	check_eq(Skills.pick(cmd.gear_view._hero_id()), "", "and again goes back to by hold length")
	cmd.gear_view.close()


## The shapes behind multi-hit, chained, spread and knife techs.
func test_blast_shapes() -> void:
	var o := Vector2.ZERO
	var liq := Techs.blasts(Techs.find("liquidation"), o, Vector2.RIGHT)
	check_eq(liq.size(), 3, "Liquidation: three blasts")
	check(float(liq[2]["p"].get("stun", 0)) > 0.0 and float(liq[0]["p"].get("stun", 0)) == 0.0, "only the last one stuns")
	var ell := Techs.blasts(Techs.find("ellipsis"), o, Vector2.RIGHT)
	check_eq(ell.size(), 3, "Ellipsis: three full stops")
	check(ell[2]["at"].x > ell[0]["at"].x and ell[2]["time"] > ell[0]["time"], "marching forward, one after another")
	var twin := Techs.blasts(Techs.find("twin_prongs"), o, Vector2.RIGHT)
	check_eq(twin.size(), 2, "Twin Prongs: two lines")
	check(absf(twin[0]["dir"].angle_to(twin[1]["dir"])) > 0.3, "in a V")
	check_eq(Techs.blasts(Techs.find("knife_storm"), o, Vector2.RIGHT).size(), 0, "Knife Storm is all knives")
	var writ := Techs.blasts(Techs.find("writ_of_erasure"), o, Vector2.RIGHT)
	check(float(writ[0]["time"]) > 0.0, "the Writ goes off after a delay")
