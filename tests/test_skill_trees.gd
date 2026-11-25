extends "res://tests/test_case.gd"
## Per-hero skill trees (issue #25): the data, Skill Points, learning in order, bond gates, one capstone,
## unlearning for Gilt, what nodes do to stats and abilities, the save step and cleaning, every kind of
## passive working in a real mission, the ally AI's focus, and the screen from the Gear screen and the
## quick menu.

const MAIN := "res://scenes/main.tscn"
const COMMAND := "res://scenes/command.tscn"
const FIXTURE := "res://tests/fixtures/saves/20261121_skill_trees__table_day27_veterans.json"
const MOD_KEYS := ["add", "mult", "set", "set_missing"]
const NODE_KEYS := ["id", "name", "cost", "desc", "flavor", "bond", "bonds", "effects", "capstone"]
## Riders an ability may get from a tree that its kind's code in abilities.gd actually reads.
const RIDERS := {
	"arc": ["poison", "leech", "mark", "mark_mult", "taunt"],
	"dash": ["poison", "leech", "mark", "mark_mult", "taunt"],
	"bolt": ["poison", "leech", "mark", "mark_mult", "pierce"],
	"heal": ["ink_gift", "poison_area", "shield", "shield_time"],
	"taunt": ["self_shield"],
	"vanish": ["heal"],
	"drain": ["ink_ratio", "leech"],
	"mark": ["damage", "stun"],
	"parry": ["aoe"],
	# Chapter 3 kinds (#29)
	"charm": ["mark", "mark_mult"],
	"blink": ["vanish", "poison", "leech", "mark", "mark_mult", "taunt"],
	"song": ["heal"],
	"conjure": ["song", "poison", "leech", "mark", "mark_mult"],
	"weaken": ["damage"],
	"shadow": ["weaken_hits", "poison", "leech", "mark", "mark_mult"],
	# Chapter 4 kinds (#30)
	"unwrite": ["pierce_heal"],
}

var Empire: Node
var D := {}


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	Empire.reset()
	for f in ["skill_trees.json", "abilities.json", "heroes.json", "bonds.json"]:
		D[f] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0


func _join(ids: Array, role := "idle") -> void:
	for id in ids:
		Empire.recruits[id] = {"role": role, "target": "", "injured": 0}


## Levels a hero up to lvl through the real XP path.
func _level(id: String, lvl: int) -> void:
	while Progress.level(id) < lvl:
		Progress.award([id], Progress.xp_to_next(Progress.level(id)))


# ------------------------------------------------------------------ data

func test_every_field_hero_has_a_full_tree() -> void:
	var trees: Dictionary = D["skill_trees.json"]["trees"]
	var heroes: Dictionary = D["heroes.json"]["heroes"]
	var abilities: Dictionary = D["abilities.json"]["abilities"]
	var seen := {}
	for hero in heroes:
		if not check(trees.has(hero), "%s has a skill tree" % hero):
			continue
		var t: Dictionary = trees[hero]
		var w: String = "skill_trees.json " + hero
		check(not (t.get("root", {}) as Dictionary).is_empty(), w + ": a root")
		var br: Array = t.get("branches", [])
		check_eq(br.size(), 2, w + ": two branches")
		var all := [t["root"]]
		var total := int(t["root"].get("cost", 1))
		var caps := []
		for b in br:
			check(str(b.get("name", "")) != "" and str(b.get("blurb", "")) != "", "%s/%s: name and blurb" % [w, b.get("id")])
			check(Color.html_is_valid(str(b.get("color", ""))), "%s/%s: colour" % [w, b.get("id")])
			var nodes: Array = b.get("nodes", [])
			check_eq(nodes.size(), 5, "%s/%s: five nodes" % [w, b.get("id")])
			var playstyle := 0
			for i in nodes.size():
				var n: Dictionary = nodes[i]
				all.append(n)
				total += int(n.get("cost", 1))
				check_eq(bool(n.get("capstone", false)), i == nodes.size() - 1, "%s: only the last node is the capstone" % n.get("id"))
				var e: Dictionary = n.get("effects", {})
				if e.has("abilities") or e.has("perks") or e.has("ai"):
					playstyle += 1
			# Issue #25: nodes change how a hero plays, not only stats.
			check(playstyle >= 4, "%s/%s: at least four nodes change how the hero plays (%d)" % [w, b.get("id"), playstyle])
			caps.append(int(nodes.back().get("cost", 1)))
			# Bond gates: the deeper nodes, never the first ones.
			check(not nodes[0].has("bond") and not nodes[0].has("bonds"), "%s/%s: the first node is open" % [w, b.get("id")])
			check(nodes.back().has("bond") or nodes.back().has("bonds"), "%s/%s: the capstone needs a bond" % [w, b.get("id")])
		for n in all:
			var nid: String = str(n.get("id", ""))
			check(nid != "" and not seen.has(nid), "%s: node id %s unique" % [w, nid])
			seen[nid] = true
			for k in n:
				check(k in NODE_KEYS, "%s: unknown key %s" % [nid, k])
			check(int(n.get("cost", 0)) >= 1 and int(n.get("cost", 0)) <= 3, nid + ": cost 1 to 3")
			check(str(n.get("desc", "")) != "" and str(n.get("flavor", "")) != "", nid + ": desc and flavor")
			if n.has("bond"):
				check(hero != "ash" and D["bonds.json"]["cast"].has(hero), nid + ": a bond gate on someone with a bond")
				check(int(n["bond"]) >= 1 and int(n["bond"]) <= 5, nid + ": bond rank 1-5")
			if n.has("bonds"):
				check((n["bonds"] as Array).size() == 2, nid + ": bonds is [rank, count]")
			var e: Dictionary = n.get("effects", {})
			check(not e.is_empty(), nid + ": does something")
			for k in e:
				check(k in ["stats", "abilities", "perks", "ai"], "%s: unknown effect %s" % [nid, k])
			for k in e.get("stats", {}):
				check(k in Progress.STAT_ORDER, "%s: unknown stat %s" % [nid, k])
			for k in e.get("perks", {}):
				check(TreePerks.PERKS.has(k), "%s: perk %s is not handled in tree_perks.gd" % [nid, k])
			if e.get("perks", {}).has("kill_reset"):
				check(str(e["perks"]["kill_reset"]) in heroes[hero]["abilities"], nid + ": kill_reset names one of the hero's abilities")
			if e.has("ai"):
				check(TreePerks.FOCUS.has(str(e["ai"].get("focus", ""))), nid + ": ai focus")
			for aid in e.get("abilities", {}):
				if not check(aid in heroes[hero]["abilities"], "%s: %s is not one of %s's abilities" % [nid, aid, hero]):
					continue
				var kind: String = str(abilities[aid]["kind"])
				for op in e["abilities"][aid]:
					check(op in MOD_KEYS, "%s: unknown ability change %s" % [nid, op])
					for k in e["abilities"][aid][op]:
						var known: bool = abilities[aid].has(k) or k in ["cooldown", "cost", "ai", "stun"] or k in RIDERS.get(kind, [])
						check(known, "%s: %s (%s) does nothing with %s" % [nid, aid, kind, k])
		# Everything but one capstone fits in the points a max-level hero has.
		var max_points := (Progress.max_level() - 1) * int(D["skill_trees.json"]["points"]["per_level"])
		check(total - caps.min() <= max_points, "%s: a max-level hero can learn all but one capstone (%d of %d)" % [w, total - caps.min(), max_points])
	for hero in trees:
		check(heroes.has(hero), "skill_trees.json: %s is not a field hero" % hero)


func test_tree_text_fills_in() -> void:
	_join(["bran", "gristle", "ninefingers", "ottoline", "jessamy", "odile", "velvette"])
	for hero in D["skill_trees.json"]["trees"]:
		for n in SkillTree.all_nodes(hero):
			Progress.hero(hero)["tree"] = []
			Progress.hero(hero)["tree"].append(str(n["id"]))
			for a in Abilities.for_ids(PartyPicker.hero_data(hero).get("abilities", []), hero):
				var text := Abilities.desc_of(a)
				check(text.find("{") < 0 and text.find("}") < 0, "%s with %s: unfilled {key}: %s" % [a["id"], n["id"], text])
				check(float(a["cooldown"]) >= 1.0 and int(a["cost"]) >= 0, "%s with %s: sane cost and cooldown" % [a["id"], n["id"]])
		Progress.hero(hero)["tree"] = []


# ------------------------------------------------------------------ points, learning, unlearning

func test_points_come_from_levels() -> void:
	check_eq(SkillTree.points_total("ash"), 0, "level 1: no points")
	_level("ash", 5)
	check_eq(SkillTree.points_total("ash"), 4, "one per level past 1")
	check_eq(SkillTree.points_free("ash"), 4, "all free")
	check(SkillTree.can_spend("ash"), "something to learn")
	check("ash" in SkillTree.unspent_ids(), "listed as having points to spend")


func test_learning_in_order_with_gates_and_one_capstone() -> void:
	_join(["bran"], "party")
	_level("bran", 20)
	check(SkillTree.blocker("bran", "bran_client_protection").begins_with("learn"), "a branch needs the root first")
	check(SkillTree.learn("bran", "bran_clause_one"), "root learned")
	check(not SkillTree.learn("bran", "bran_thick_hide"), "can't skip a step")
	for n in ["bran_client_protection", "bran_thick_hide", "bran_clause_four"]:
		check(SkillTree.learn("bran", n), n + " learned")
	check(SkillTree.blocker("bran", "bran_hold_the_bill").begins_with("needs Bran bond"), "step 4 waits for the bond")
	Empire.bonds["bran"] = {"points": 40, "rank": 3, "talk_day": 0, "personal_done": false}
	check(SkillTree.learn("bran", "bran_hold_the_bill"), "Familiar or closer: learned")
	check(SkillTree.learn("bran", "bran_paid_in_blood"), "Trusted: the capstone")
	for n in ["bran_hazard_pay", "bran_itemised_violence", "bran_cleave_clause", "bran_renegotiation"]:
		check(SkillTree.learn("bran", n), n + " learned")
	check(SkillTree.blocker("bran", "bran_highest_bidder").begins_with("holds"), "one capstone per hero")
	check_eq(SkillTree.points_spent("bran"), 18, "18 points spent")
	check_eq(SkillTree.points_free("bran"), 1, "one left over at level 20")
	# Ash's gates count bonds with the others.
	_level("ash", 20)
	for n in ["ash_first_draft", "ash_generous_hand", "ash_footnotes", "ash_second_draft"]:
		SkillTree.learn("ash", n)
	check(SkillTree.blocker("ash", "ash_marginalia").begins_with("needs 2 bonds"), "Ash needs two bonds")
	_join(["gristle"])
	Empire.bonds["gristle"] = {"points": 20, "rank": 2, "talk_day": 0, "personal_done": false}
	check(SkillTree.learn("ash", "ash_marginalia"), "two Familiar bonds open it")


func test_unlearning_costs_gilt_and_only_at_home() -> void:
	_join(["odile"], "party")
	_level("odile", 6)
	for n in ["odile_double_entry", "odile_penalty_clause", "odile_itemised", "odile_late_fees"]:
		check(SkillTree.learn("odile", n), n)
	check_eq(SkillTree.points_free("odile"), 0, "all five points spent")
	var cost := SkillTree.respec_cost("odile")
	check_eq(cost, 30 + 10 * 5, "base plus per point")
	check(SkillTree.respec_blocker("odile", true) != "", "not on a mission")
	Empire.res["gilt"] = cost - 1
	check(not SkillTree.respec("odile"), "not without the Gilt")
	Empire.res["gilt"] = cost + 5
	check(SkillTree.respec("odile"), "unlearned")
	check_eq(int(Empire.res["gilt"]), 5, "paid")
	check_eq(SkillTree.points_free("odile"), 5, "every point back")
	check(SkillTree.learn("odile", "odile_double_entry") and SkillTree.learn("odile", "odile_fair_share"), "spent the other way")


# ------------------------------------------------------------------ effects

func test_nodes_change_stats_and_abilities() -> void:
	_join(["bran"], "party")
	_level("bran", 12)
	var before := Progress.stats("bran")
	var cleave0: Dictionary = Abilities.for_ids(["cleave"], "bran")[0]
	for n in ["bran_clause_one", "bran_hazard_pay", "bran_itemised_violence", "bran_cleave_clause"]:
		SkillTree.learn("bran", n)
	var after := Progress.stats("bran")
	check_eq(int(after["hp"]) - int(before["hp"]), 10, "Clause One: +10 HP")
	check_eq(int(after["damage"]) - int(before["damage"]), 2, "Hazard Pay: +2 damage")
	var cleave: Dictionary = Abilities.for_ids(["cleave"], "bran")[0]
	check_eq(int(cleave["arc"]), int(cleave0["arc"]) + 20, "Cleave Clause: wider")
	check_eq(float(cleave.get("leech", 0)), 0.3, "and it heals Bran")
	check(Abilities.desc_of(cleave).find("Heals the user for 30%") >= 0, "the description says so: " + Abilities.desc_of(cleave))
	check_eq(cleave.get("tree", []), ["Cleave Clause"], "menus can name the node")
	check_eq(SkillTree.perks("bran").get("kill_gilt", 0.0), 2.0, "Itemised Violence: a perk")
	# Ability AI rules can change too (Client Protection: Hold the Line as soon as one enemy closes in).
	Progress.hero("bran")["tree"] = ["bran_clause_one", "bran_client_protection"]
	var hold: Dictionary = Abilities.for_ids(["hold_the_line"], "bran")[0]
	check_eq(int(hold["ai"]["count"]), 1, "the ally uses it sooner")
	check_eq(SkillTree.focus("bran"), "", "no focus yet")
	Progress.hero("bran")["tree"] = ["bran_clause_one", "bran_client_protection", "bran_thick_hide", "bran_clause_four"]
	check_eq(SkillTree.focus("bran"), "leader_threat", "Clause Four: guards the leader")


# ------------------------------------------------------------------ saves

func test_save_step_and_cleaning() -> void:
	var Saves := autoload("Saves")
	var r: Dictionary = Saves.parse(FileAccess.get_file_as_string(FIXTURE))
	if not check_eq(r["status"], Saves.GOOD, "fixture loads"):
		return
	var heroes: Dictionary = r["data"]["empire"]["progress"]["heroes"]
	for id in heroes:
		check_eq(heroes[id].get("tree"), [], id + ": an empty tree after the step")
	Empire.from_dict(r["data"]["empire"])
	check_eq(SkillTree.points_free("bran"), 9, "a level 10 veteran has 9 points waiting")
	check(SkillTree.learn("bran", "bran_clause_one"), "and can spend them")
	check_eq(Empire.bond_rank("bran"), 3, "bond kept, so Bran's deeper nodes are open")
	# Round trip, and a save edited by hand or from a build with other nodes.
	SkillTree.learn("bran", "bran_hazard_pay")
	var d: Dictionary = Empire.to_dict()
	d["progress"]["heroes"]["bran"]["tree"] = ["bran_clause_one", "no_such_node", "bran_hazard_pay", "bran_renegotiation",
		"gristle_warm_hands", "bran_hazard_pay"]
	d["progress"]["heroes"]["gristle"]["tree"] = ["gristle_same_bottle"]
	Empire.from_dict(JSON.parse_string(JSON.stringify(d)))
	check_eq(SkillTree.learned("bran"), ["bran_clause_one", "bran_hazard_pay"], "unknown, out-of-order, other heroes' and repeated nodes dropped")
	check_eq(SkillTree.learned("gristle"), [], "a node without its root is dropped")
	d["progress"]["heroes"]["odile"]["tree"] = ["odile_double_entry", "odile_penalty_clause", "odile_itemised"]
	Empire.from_dict(JSON.parse_string(JSON.stringify(d)))
	check_eq(SkillTree.learned("odile"), ["odile_double_entry"], "no more than the level pays for (level 2: 1 point)")


# ------------------------------------------------------------------ in a mission

func _mission(party: Array) -> Node:
	Empire.reset()
	_join(party, "party")
	Dialogue.mark_seen("talk:meadow_intro")
	Empire.active_mission = Missions.find("meadow_patrol").duplicate(true)
	return await goto(MAIN, 20)


func _hero(main: Node, id: String) -> Hero:
	for h in main.heroes:
		if (h as Hero).hero_id == id:
			return h
	return null


func _enemy(main: Node, at: Vector2, hp := 200) -> Enemy:
	for attempt in 5:
		main._spawn_enemy(at)
		await frames(1)
		var es := tree.get_nodes_in_group("enemies").filter(func(x): return not x.is_queued_for_deletion() and not x.dead)
		for x in es:
			if not x.has_meta("test_used"):
				var e: Enemy = x
				e.set_meta("test_used", true)
				e.max_hp = hp
				e.hp = hp
				e.global_position = at
				e.stun(5.0)
				return e
	return null


func _clear(main: Node) -> void:
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	main.respawn_t = 1e9
	await frames(2)


func test_perks_in_a_real_fight() -> void:
	var main := await _mission(["bran", "gristle"])
	if not check(main != null and main.leader != null, "mission running"):
		return
	await _clear(main)
	main.mission["loot"] = {}  # only the tree's Gilt lands in the loot
	var ash: Hero = main.leader
	var bran := _hero(main, "bran")
	var gristle := _hero(main, "gristle")
	if not check(bran != null and gristle != null, "party in the field"):
		return
	# Bodyguard: Bran beside Ash takes 30% of what Ash would.
	bran.perks = {"bodyguard": 0.3}
	bran.global_position = ash.global_position + Vector2(20, 0)
	ash.invuln_t = 0.0
	bran.invuln_t = 0.0
	var a0 := ash.hp
	var b0 := bran.hp
	ash.take_hit(20, ash.global_position + Vector2(-10, 0), 0.0)
	check(bran.hp < b0, "Bran took part of it")
	check(a0 - ash.hp < 20, "Ash took less: %d" % (a0 - ash.hp))
	bran.perks = {}
	# Evade: always misses when the chance is 1.
	ash.perks = {"evade": 1.0}
	ash.invuln_t = 0.0
	a0 = ash.hp
	ash.take_hit(10, ash.global_position + Vector2(-10, 0))
	check_eq(ash.hp, a0, "missed")
	# Last stand: a killing blow leaves 1 HP, once.
	ash.perks = {}
	ash.last_stand_left = 1
	ash.invuln_t = 0.0
	ash.take_hit(9999, ash.global_position)
	check(not ash.dead and ash.hp == 1, "Not today: on 1 HP")
	check_eq(ash.last_stand_left, 0, "used up")
	ash.hp = ash.max_hp
	ash.invuln_t = 0.0
	# Guard aura: Gristle with aura_guard beside Ash.
	gristle.perks = {"aura_guard": 0.5}
	gristle.global_position = ash.global_position + Vector2(0, 20)
	bran.global_position = ash.global_position + Vector2(300, 0)
	a0 = ash.hp
	ash.take_hit(20, ash.global_position + Vector2(-10, 0), 0.0)
	var with_aura := a0 - ash.hp
	gristle.perks = {}
	ash.invuln_t = 0.0
	a0 = ash.hp
	ash.take_hit(20, ash.global_position + Vector2(-10, 0), 0.0)
	check(with_aura < a0 - ash.hp, "the aura cut the hit (%d vs %d)" % [with_aura, a0 - ash.hp])
	ash.hp = ash.max_hp
	ash.invuln_t = 999.0
	# Thorns: the enemy that hits back takes some.
	var e := await _enemy(main, ash.global_position + Vector2(14, 0))
	if check(e != null, "an enemy"):
		ash.perks = {"thorns": 0.5}
		ash.invuln_t = 0.0
		var e0 := e.hp
		ash.take_hit(10, e.global_position, 0.0)
		check(e.hp < e0, "thorns hurt the attacker")
		ash.perks = {}
		ash.invuln_t = 999.0
	await _clear(main)
	# Damage bonuses: wounded enemies take more.
	e = await _enemy(main, ash.global_position + Vector2(14, 0), 100)
	if check(e != null, "an enemy"):
		e.hp = 20
		ash.perks = {"dmg_wounded": 1.0}
		TreePerks.strike(ash, e, 4, ash.global_position, 0.0)
		check_eq(e.hp, 12, "double damage under 35%")
	await _clear(main)
	# Kill rewards: Gilt into the loot, Ink, gauge, and a reset cooldown.
	e = await _enemy(main, ash.global_position + Vector2(14, 0), 5)
	if check(e != null, "an enemy"):
		ash.perks = {"kill_gilt": 3, "kill_ink": 4, "kill_gauge": 1, "kill_reset": "strikethrough"}
		ash.ink = 0.0
		ash.power = 0.0
		ash.cooldowns[1] = 3.0
		var g0 := int(main.found.get("gilt", 0))
		TreePerks.strike(ash, e, 50, ash.global_position, 0.0)
		check(e.dead, "killed")
		check_eq(int(main.found.get("gilt", 0)) - g0, 3, "Gilt into the loot")
		check_eq(int(ash.ink), 4, "Ink back")
		check_eq(ash.power, 1.0, "gauge full")
		check_eq(ash.cooldowns[1], 0.0, "Strikethrough ready again")
		ash.perks = {}
	await _clear(main)
	# Leech heals, swing stun stuns.
	e = await _enemy(main, ash.global_position + Vector2(14, 0), 200)
	if check(e != null, "an enemy"):
		ash.hp = 10
		ash.perks = {"leech": 0.5, "swing_stun": 0.6}
		ash.swing_power = 1.0
		e.stun_until = 0
		TreePerks.strike(ash, e, 20, ash.global_position, 0.0, {}, "swing")
		check(ash.hp > 10, "leech healed Ash")
		check(e.stun_left() > 0.3, "a full swing stunned it")
		ash.perks = {}
	await _clear(main)
	# Poison ticks, and a poison kill pays the poisoner.
	e = await _enemy(main, ash.global_position + Vector2(330, 0), 3)  # out of everyone's reach: only the poison
	if check(e != null, "an enemy"):
		gristle.perks = {"kill_ink": 5}
		gristle.ink = 0.0
		gristle.ink_regen = 0.0
		TreePerks.poison(e, 2.0, 4.0, gristle)
		check(TreePerks.poisoned(e), "poisoned")
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 2600 and is_instance_valid(e) and not e.dead:
			await tree.process_frame
		check(not is_instance_valid(e) or e.dead, "the poison finished it")
		await frames(2)
		check_eq(int(gristle.ink), 5, "the kill was Gristle's")
	# Revives go faster near a reviver.
	gristle.perks = {"revive_speed": 1.0}
	bran.dead = true
	bran.global_position = gristle.global_position + Vector2(10, 0)
	check_eq(TreePerks.revive_mult(bran, main.heroes), 2.0, "twice as fast beside Gristle")
	bran.dead = false


## Issue #136: tree poison is the shared poison status (scripts/status.gd), not a ticker of its own.
func test_tree_poison_is_the_shared_status() -> void:
	var main := await _mission(["gristle"])
	if not check(main != null and main.leader != null, "mission running"):
		return
	await _clear(main)
	main.mission["loot"] = {}  # only the tree's Gilt lands in the loot
	var ash: Hero = main.leader
	var gristle := _hero(main, "gristle")
	if not check(gristle != null, "Gristle in the field"):
		return
	ash.invuln_t = 999.0
	gristle.invuln_t = 999.0
	var e := await _enemy(main, ash.global_position + Vector2(330, 0), 200)  # out of everyone's reach
	if not check(e != null, "an enemy"):
		return
	e.stun_until = 0  # free to act, so a stagger would show
	e._set_state(Enemy.State.WANDER, 1.0)
	TreePerks.poison(e, 4.0, 3.0, gristle)
	check(Status.has(e, "poison"), "the poison is the shared status")
	check(TreePerks.poisoned(e), "and TreePerks reads it back")
	check(e.get_node_or_null("TreePoison") == null, "no ticker of the tree's own on the enemy")
	check(TreePerks.damage_bonus(gristle, e) == 0.0, "no bonus without the perk")
	gristle.perks = {"dmg_poisoned": 0.5}
	check_eq(TreePerks.damage_bonus(gristle, e), 0.5, "dmg_poisoned sees the shared poison")
	gristle.perks = {}
	# Ticks hurt but never stagger, flash or knock it back.
	var hp0 := e.hp
	var staggered := false
	var flashed := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1600 and is_instance_valid(e) and not e.dead:
		staggered = staggered or e.state == Enemy.State.STAGGER
		flashed = flashed or e.flash_t > 0.0
		await tree.process_frame
	if check(is_instance_valid(e) and not e.dead, "still standing"):
		check(e.hp <= hp0 - 4, "the poison ticked (%d -> %d)" % [hp0, e.hp])
		check(not staggered, "no stagger from a poison tick")
		check(not flashed, "no hit flash from a poison tick")
		check_eq(e.get_meta("status_source", null), gristle, "the ticks are credited to Gristle")
		# Re-applying keeps the stronger dose and refreshes the time; a cure clears it like any poison.
		TreePerks.poison(e, 1.0, 5.0, gristle)
		check_eq(float(Status._all(e)["poison"]["dps"]), 4.0, "the stronger dose stays")
		check(Status.left(e, "poison") > 4.5, "the time is refreshed")
		check_eq(Status.cure(e, ["poison"]), 1, "a cure removes it")
		check(not TreePerks.poisoned(e), "and it is gone")
	# A dead or missing enemy is ignored.
	TreePerks.poison(null, 4.0, 3.0, gristle)
	await _clear(main)
	# A poison kill pays the poisoner's kill rewards.
	e = await _enemy(main, ash.global_position + Vector2(330, 0), 2)
	if check(e != null, "a second enemy"):
		gristle.perks = {"kill_gilt": 4}
		var g0 := int(main.found.get("gilt", 0))
		TreePerks.poison(e, 4.0, 3.0, gristle)
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 1500 and is_instance_valid(e) and not e.dead:
			await tree.process_frame
		check(not is_instance_valid(e) or e.dead, "the poison finished it")
		await frames(2)
		check_eq(int(main.found.get("gilt", 0)) - g0, 4, "the kill paid Gristle's kill_gilt")
	gristle.perks = {}
	await _clear(main)
	# Bosses keep their own rules: the Auditor is untouchable while dormant, poison or not.
	var aud: Enemy = load("res://scripts/auditor.gd").new()
	aud.position = ash.global_position + Vector2(330, 0)
	main.entities.add_child(aud)
	aud.floor_node = main.area
	aud.arena = Rect2(Vector2(24, 24), main.world - Vector2(48, 40))
	await frames(2)
	var a0 := aud.hp
	TreePerks.poison(aud, 6.0, 2.0, gristle)
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 1200:
		await tree.process_frame
	check_eq(aud.hp, a0, "a dormant Auditor shrugs off poison")
	aud.queue_free()
	await frames(1)


func test_learning_mid_mission_takes_effect_at_once() -> void:
	var main := await _mission(["bran", "gristle"])
	if not check(main != null, "mission running"):
		return
	var bran := _hero(main, "bran")
	_level("bran", 8)
	var hp0 := bran.max_hp
	var before := Progress.bonus("bran")
	SkillTree.learn("bran", "bran_clause_one")
	SkillTree.refresh_live(bran, before)
	check_eq(bran.max_hp - hp0, 10, "+10 HP on the spot")
	before = Progress.bonus("bran")
	SkillTree.learn("bran", "bran_hazard_pay")
	SkillTree.learn("bran", "bran_itemised_violence")
	SkillTree.learn("bran", "bran_cleave_clause")
	SkillTree.refresh_live(bran, before)
	check_eq(float(bran.abilities[0].get("leech", 0)), 0.3, "Cleave Clause on the Cleave in hand")
	check_eq(float(bran.perks.get("kill_gilt", 0)), 2.0, "perks live")
	before = Progress.bonus("bran")
	SkillTree.learn("bran", "bran_renegotiation")  # needs bond 2: refused
	check(not SkillTree.knows("bran", "bran_renegotiation"), "bond gate holds mid-mission too")


func test_ally_focus_picks_targets() -> void:
	var main := await _mission(["velvette", "bran"])
	if not check(main != null, "mission running"):
		return
	await _clear(main)
	var vel := _hero(main, "velvette")
	var near := await _enemy(main, main.leader.global_position + Vector2(30, 0), 100)
	var hurt := await _enemy(main, main.leader.global_position + Vector2(80, 0), 100)
	if not check(near != null and hurt != null and vel != null, "two enemies and Fauvette"):
		return
	hurt.hp = 20
	vel.global_position = main.leader.global_position
	vel.ai_focus = ""
	check_eq(AllyAI.focus_target(vel, vel.global_position, 200.0, main.leader), near, "no focus: the nearest")
	vel.ai_focus = "wounded"
	check_eq(AllyAI.focus_target(vel, vel.global_position, 200.0, main.leader), hurt, "Killing Blow: the wounded one")
	hurt.hp = 100
	near.mark(5.0, 1.5)
	vel.ai_focus = "marked"
	check_eq(AllyAI.focus_target(vel, vel.global_position, 200.0, main.leader), near, "marked first")
	near.target = main.leader
	vel.ai_focus = "leader_threat"
	check_eq(AllyAI.focus_target(vel, vel.global_position, 200.0, main.leader), near, "whatever is on the leader")


# ------------------------------------------------------------------ screens

func test_tree_screen_from_gear_and_quick_menu() -> void:
	var main := await _mission(["bran", "gristle"])
	if not check(main != null, "mission running"):
		return
	_level("bran", 6)
	main.open_quick_menu()
	await frames(2)
	var qm = main.quick_menu
	qm._set_tab(QuickMenu.TABS.find("Tree"))
	await frames(2)
	check_eq(qm.rows.size(), main.heroes.size(), "a Tree row per hero")
	var bi := -1
	for i in qm.rows.size():
		if qm.rows[i]["id"] == "bran":
			bi = i
	if not check(bi >= 0, "Bran's row"):
		return
	check(str(qm.rows[bi]["right"]).find("5 Skill Points") >= 0, "points to spend shown: " + str(qm.rows[bi]["right"]))
	qm._pick_row(bi)
	await frames(3)
	check(tree.paused, "the fight pauses under the tree")
	var tvs := main.find_children("*", "SkillTreeView", true, false)
	if not check(tvs.size() == 1, "the tree screen opened"):
		return
	var tv: SkillTreeView = tvs[0]
	check_eq(tv.hero_id(), "bran", "on Bran")
	check_eq(tv.sel, "bran_clause_one", "cursor on the first node to learn")
	tv._act()
	check(SkillTree.knows("bran", "bran_clause_one"), "Enter learns it")
	tv._step("up")
	check_eq(tv.sel, "bran_client_protection", "up climbs into the first branch")
	tv._step("right")
	check_eq(tv.sel, "bran_hazard_pay", "right crosses to the other branch")
	tv._step("down")
	tv._step("down")
	check_eq(tv.sel, SkillTreeView.RESET, "down from the root reaches Unlearn")
	tv._act()
	check(SkillTree.knows("bran", "bran_clause_one"), "no unlearning on a mission")
	await frames(2)
	check(not tv._node_rects.is_empty(), "nodes drawn")
	tv.close()
	await frames(3)
	check(not tree.paused, "closing goes back to the fight")
	# The Gear screen's Tree tab, at the Command Table, with unlearning.
	var cmd := await goto(COMMAND, 15)
	if not check(cmd != null, "Command Table"):
		return
	cmd.gear_view.open("town")
	await frames(2)
	check(cmd.gear_view._tabs().has("tree"), "a Tree tab")
	check(cmd.gear_view._tree_label().begins_with("Tree"), "labelled")
	cmd.gear_view._set_tab("tree")
	await frames(3)
	var tv2: SkillTreeView = cmd.gear_view._tree
	if not check(tv2 != null and tv2.visible, "the tree opens over the Gear screen"):
		return
	while tv2.hero_id() != "bran":
		tv2._set_hero(posmod(tv2.hero_i + 1, tv2._ids.size()))
	Empire.res["gilt"] = 500
	tv2.sel = SkillTreeView.RESET
	tv2._act()
	check(SkillTree.knows("bran", "bran_clause_one"), "the first press only asks")
	tv2._act()
	check(SkillTree.learned("bran").is_empty(), "the second unlearns")
	check_eq(int(Empire.res["gilt"]), 500 - 40, "for 40 Gilt")
	await frames(2)
	tv2.close()
	await frames(2)
	check(cmd.gear_view._tree == null and cmd.gear_view.visible, "back on the Gear screen")
	cmd.gear_view.close()
