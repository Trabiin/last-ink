extends "res://tests/test_case.gd"
## Chapter 4: The Sea Stops, the Unfinished Coast (issue #30). The end of Chapter 3 opens the coast, the beats play
## in order, each story and personal mission launches on its own map and runs its steps, Low Water plays its
## phases (the Flood and its dry banks), the four new enemies keep their tells and their openings, Ilse's kit does
## what its card says (Looking Glass, Unwrite in White Ink), the Harbour Moot pays its catch, the lighthouse starts
## the betrayal's foreshadowing, and old saves give Trevail to the Moot.

const MAIN := "res://scenes/main.tscn"
const HUB := "res://scenes/hub.tscn"
const CH4 := ["ch4_harbour", "ch4_mirror", "ch4_light", "ch4_lowwater"]
const PERSONAL := ["personal_ilse"]
const KINDS := ["breaker", "netcaster", "gannet", "saltwight"]
const HELD := ["meadow", "oldmill", "lampwick", "saltreed", "candlemere", "ossuary", "quillpine", "goldwash", "terraces", "lanternquay"]

var Empire: Node
var Saves: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	runner.clear_scratch()
	Saves.pending = {}
	Empire.reset()
	for t in Help.topics():
		Help.mark(t["id"])


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0
	Assists.pace_i = 0


## A story campaign that has just beaten the Host, holding eleven provinces with Hollowmark (Chapter 4's start).
func _ch3_done() -> void:
	Empire.reset()
	Story.begin()
	for pid in HELD:
		Empire.territory().find(pid)["owner"] = "you"
	for id in ["gristle", "ninefingers", "abeyance", "velvette", "hortense", "saffron", "nan"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for m in ["meadow_prologue", "ch1_breakout", "act1_concord", "auditor_duel", "ch2_candleford", "ch2_hall", "ch2_crypt", "ch2_abbot",
			"ch3_quay", "ch3_masquerade", "ch3_shallows", "ch3_wharf", "ch3_host"]:
		Empire.missions_cleared.append(m)
	for t in ["meadow_intro", "ch1_arrest", "ch1_takeover", "act1_rumours", "act1_writ", "act1_concord_after",
			"act1_end", "ch2_bells", "ch2_candleford_after", "ch2_hall_ready", "ch2_hall_after", "ch2_hild", "ch2_verity_after", "ch2_end",
			"ch3_invitation", "ch3_quay_after", "ch3_masquerade_after", "ch3_two_rapiers", "ch3_wharf_after", "ch3_end"]:
		Dialogue.mark_seen("talk:" + t)
	Empire.open_region("abbey", true)
	Empire.open_region("causeway", true)
	Empire.res["renown"] = 80


func _clear(ids: Array) -> void:
	for id in ids:
		if not id in Empire.missions_cleared:
			Empire.missions_cleared.append(id)


func _seen(ids: Array) -> void:
	for t in ids:
		Dialogue.mark_seen("talk:" + t)


func _inner(main: Node) -> MissionObjectives:
	return main.objective.inner if main.objective._inner_ready else null


func _offered(pid: String, id: String) -> Array:
	return Missions.list_for_province(pid).filter(func(m): return m["id"] == id)


# ---------------------------------------------------------------- data

func test_chapter_data_hangs_together() -> void:
	for id in CH4:
		var m := Missions.find(id)
		if not check(not m.is_empty(), "%s exists" % id):
			continue
		check(m.get("story", false), "%s is a story mission" % id)
		check(FileAccess.file_exists(str(m["map"])), "%s map %s exists" % [id, m["map"]])
		check_eq(Empire.territory().find(m["province"]).get("region", ""), "coast", "%s is on the coast" % id)
		check(int(m.get("gate", {}).get("renown", 0)) >= 60, "%s continues the Renown gates from Chapter 3" % id)
	for id in PERSONAL:
		var m := Missions.find(id)
		if check(not m.is_empty(), "%s exists" % id):
			check(FileAccess.file_exists(str(m["map"])), "%s map exists" % id)
	for kind in KINDS:
		check(EnemyKinds.data()["kinds"].has(kind), "enemy kind %s" % kind)
	check(BossFight.BOSSES.has("lowwater"), "Low Water is a boss")
	for t in ["lowwater_intro", "lowwater_phase2", "lowwater_outro"]:
		check(not Dialogue.talk(t).is_empty(), "Low Water's %s" % t)
	check_eq(Empire.faction("moot").get("province", ""), "saltgrave", "the Harbour Moot sit at Trevail")
	check_eq(Empire.territory().find("saltgrave").get("owner", ""), "moot", "and own it")
	for pid in ["saltgrave", "halfwave", "lighthouse"]:
		check(EnemyKinds.data()["rosters"].has(pid), "%s has its own roster" % pid)
	var pool: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/provinces.json"))["biomes"]["coast"]["maps"]
	check(pool.size() >= 3, "the coast biome has its patrol maps")
	for mp in pool:
		check(FileAccess.file_exists("res://maps/%s.txt" % mp), "coast map %s exists" % mp)
	var chapters: Array = Journal.data().get("chapters", []).map(func(c): return c["id"])
	check("ch4" in chapters, "the journal has a Chapter 4")
	for g in Story.data()["goals"]:
		if g.get("chapter", "") == "ch4":
			check(g.has("show"), "Chapter 4 goal '%s' stays hidden until its beat" % g["text"])
	check_eq(str(Empire.recruit("ilse").get("tier", "")), "field", "Ilse fights in the field")
	check(not Empire.bond_info("ilse").is_empty(), "Ilse has a bond")
	for id in ["kerra", "yann"]:
		check(not Empire.recruit(id).is_empty(), "%s is a recruit" % id)
	check(FileAccess.file_exists("res://assets/portraits/ilse.png"), "Ilse keeps her own portrait")


## The Chapter 4 betrayal hook (#186): the lighthouse starts the foreshadowing.
func test_lighthouse_starts_the_foreshadowing() -> void:
	check_eq(str(Missions.find("ch4_light").get("on_success", {}).get("betrayal", "")), "foreshadow", "ch4_light carries the hook")
	_ch3_done()
	check(not Betrayal.foreshadowing(), "no foreshadowing before the lighthouse")
	Missions.story_effects(Missions.find("ch4_light"))
	check(Betrayal.foreshadowing(), "relighting Polgarrow starts it")


# ---------------------------------------------------------------- story flow in town

func test_ch3_end_opens_the_coast() -> void:
	_ch3_done()
	check(not "coast" in Empire.regions_open, "the coast is under the fog before the tide comes")
	Empire.territory().find("lanternquay")["owner"] = "free"
	check_eq(Story.next_beat().get("talk", ""), "", "ten provinces: the sea waits for an eleventh")
	Empire.territory().find("lanternquay")["owner"] = "you"
	var hub := await goto(HUB, 20)
	if hub == null:
		return
	if not check(hub.dialogue_box.visible and hub.story_beat.get("talk", "") == "ch4_tide", "the piece of the sea arrives"):
		return
	hub.dialogue_box._close()
	await frames(3)
	check("coast" in Empire.regions_open, "the tide lifts the fog over the coast")
	check(hub.chapter_card.visible, "the Chapter 4 card shows")
	hub.chapter_card.hide()
	hub.chapter_card.closed.emit()
	await frames(3)
	check(not _offered("saltgrave", "ch4_harbour").is_empty(), "Trevail offers The Wave at Trevail")


func test_beats_play_in_order() -> void:
	_ch3_done()
	_seen(["ch4_tide"])
	Empire.open_region("coast", true)
	check_eq(Story.next_beat().get("talk", ""), "", "nothing until the harbour")
	_clear(["ch4_harbour"])
	check_eq(Story.next_beat().get("talk", ""), "ch4_harbour_after", "after the harbour")
	_seen(["ch4_harbour_after"])
	var mirror := _offered("halfwave", "ch4_mirror")
	if check(mirror.size() == 1, "the Knight in the Glass is on the map"):
		check(str(mirror[0].get("blocker", "")) != "", "locked until you hold Halfwave")
	Empire.territory().find("halfwave")["owner"] = "you"
	mirror = _offered("halfwave", "ch4_mirror")
	check(mirror.size() == 1 and str(mirror[0].get("blocker", "")) == "", "holding the bay opens the chapel")
	_clear(["ch4_mirror"])
	Empire.recruits["ilse"] = {"role": "idle", "target": "", "injured": 0}
	check_eq(Story.next_beat().get("talk", ""), "ch4_mirror_after", "after the chapel")
	_seen(["ch4_mirror_after"])
	var light := _offered("lighthouse", "ch4_light")
	if check(light.size() == 1, "the lighthouse is on the map"):
		check(str(light[0].get("blocker", "")) != "", "locked until somebody governs Halfwave")
	Empire.recruits["gristle"] = {"role": "governor", "target": "halfwave", "injured": 0}
	light = _offered("lighthouse", "ch4_light")
	check(light.size() == 1 and str(light[0].get("blocker", "")) == "", "a governor at Halfwave frees Kerra to guide you")
	_clear(["ch4_light"])
	check_eq(Story.next_beat().get("talk", ""), "ch4_light_after", "after the lighthouse")
	_seen(["ch4_light_after"])
	var next := str(Story.next_beat().get("talk", ""))
	check(next == "ch4_verity" or next == "", "Verity's interlude, or the betrayal letter first (%s)" % next)
	_seen(["ch4_verity"])
	var lw := _offered("halfwave", "ch4_lowwater")
	if check(lw.size() == 1, "Low Water is on the map"):
		check(str(lw[0].get("blocker", "")).contains("Neutral"), "locked until the Moot are Neutral (%s)" % lw[0].get("blocker", ""))
	Empire.change_standing("moot", 40, "test", true)
	lw = _offered("halfwave", "ch4_lowwater")
	check(lw.size() == 1 and str(lw[0].get("blocker", "")) == "", "Neutral opens the sea bed")
	_clear(["ch4_lowwater"])
	check_eq(Story.next_beat().get("talk", ""), "ch4_end", "the end of Chapter 4")


# ---------------------------------------------------------------- story effects and the Moot

func test_story_effects_apply() -> void:
	_ch3_done()
	Empire.open_region("coast", true)
	var before: int = Empire.standing_of("moot")
	Missions.story_effects(Missions.find("ch4_harbour"))
	check(Empire.standing_of("moot") > before, "the Moot remember who rang the boats home")
	Missions.story_effects(Missions.find("ch4_mirror"))
	check(Empire.recruits.has("ilse"), "Ilse joins after the chapel")
	Missions.story_effects(Missions.find("ch4_light"))
	check(Empire.recruits.has("kerra"), "Kerra joins after the lighthouse")


func test_friendly_moot_pays_the_catch() -> void:
	_ch3_done()
	Empire.open_region("coast", true)
	check_eq(Empire.moot_catch(), 0, "nothing while they are unfriendly")
	Empire.change_standing("moot", 120, "test", true)
	check_eq(Empire.moot_catch(), Empire.MOOT_CATCH, "a Friendly Moot puts Hollowmark on the catch list")
	var found := false
	for line in Empire.ledger():
		if str(line.get("label", "")).contains("Moot"):
			found = int(line.get("supplies", 0)) == Empire.MOOT_CATCH
	check(found, "and the ledger shows the salt fish")


func test_old_save_gives_trevail_to_the_moot() -> void:
	var r: Dictionary = Saves.parse(FileAccess.get_file_as_string("res://tests/fixtures/saves/20261127_chapter4__table_day78_after_ch3.json"))
	if not check_eq(r["status"], Saves.GOOD, "save from before Chapter 4 reads"):
		return
	Empire.from_dict(r["data"]["empire"])
	check_eq(Empire.territory().find("saltgrave")["owner"], "moot", "Trevail belongs to the Harbour Moot")
	check_eq(Empire.tier_of("moot"), "wary", "the Moot start Wary of inland folk")


# ---------------------------------------------------------------- missions in the real scene

func _launch(id: String) -> Node:
	var m := Missions.find(id)
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	check_eq(main.mission.get("id", ""), id, "%s running" % id)
	await frames(5)
	return main


## Walks a script mission's steps the quick way (as in test_chapter3.gd). Gannets in the air and Salt Wights in a
## heap are brought down for good.
func _walk_steps(main: Node, inner: MissionScript, id: String) -> void:
	var guard := 0
	while inner.step < inner.steps.size() and guard < 60 and not main.objective.failed():
		guard += 1
		var st: Dictionary = inner.st
		match str(st.get("do", "")):
			"talk":
				if main.dialogue_box.visible:
					main.dialogue_box._close()
			"goto":
				main.leader.global_position = inner.spot(st.get("at", "start"))
			"clear":
				for e in inner.wave.duplicate():
					if not is_instance_valid(e) or e.dead:
						continue
					if e is Gannet:
						(e as Gannet)._set_state(Gannet.S_STUCK, 1.0)
						e.collision_layer = (e as Gannet).base_layer
					e.take_hit(99999, e.global_position + Vector2(8, 0))
					if is_instance_valid(e) and not e.dead:
						e.take_hit(1, e.global_position + Vector2(8, 0))  # a Salt Wight's heap
			"hold":
				inner.step_t = float(st.get("seconds", 30.0))
			"use":
				for c in inner.works:
					c.progress = 1.0
					c.done = true
			"exit":
				main.leader.global_position = inner.exit_pos
		await frames(4)
	check(not main.objective.failed(), "%s did not fail on the way (%s)" % [id, main.objective.inner.fail_why if inner else ""])
	check(inner.step >= inner.steps.size(), "%s ran every step (stuck at %d: %s)" % [id, inner.step, inner.st])


func test_story_missions_run_their_steps() -> void:
	_ch3_done()
	Empire.open_region("coast", true)
	Empire.territory().find("halfwave")["owner"] = "you"
	Empire.recruits["gristle"] = {"role": "governor", "target": "halfwave", "injured": 0}
	_seen(["ch4_tide", "ch4_harbour_after", "ch4_mirror_after"])
	for id in ["ch4_harbour", "ch4_mirror", "ch4_light"]:
		var main := await _launch(id)
		if main == null:
			continue
		var inner := _inner(main) as MissionScript
		if not check(inner != null, "%s runs as a script" % id):
			continue
		await _walk_steps(main, inner, id)
		main._show_results("success")
		await frames(3)
		main._on_results_confirmed()
		await wait_scene(HUB)
		check(Missions.cleared(id), "%s cleared" % id)
	for id in ["ilse", "kerra"]:
		check(Empire.recruits.has(id), "%s came home" % id)


func test_personal_mission_runs_its_steps() -> void:
	_ch3_done()
	Empire.open_region("coast", true)
	Empire.join_now("ilse")
	for id in PERSONAL:
		var main := await _launch(id)
		if main == null:
			continue
		var inner := _inner(main) as MissionScript
		if not check(inner != null, "%s runs as a script" % id):
			continue
		await _walk_steps(main, inner, id)
		main._show_results("success")
		await frames(3)
		main._on_results_confirmed()
		await wait_scene(HUB)
		check(Missions.cleared(id), "%s cleared" % id)


func test_lowwater_fight() -> void:
	_ch3_done()
	Empire.open_region("coast", true)
	_clear(["ch4_harbour", "ch4_mirror", "ch4_light"])
	Empire.change_standing("moot", 40, "test", true)
	Progress.award(PartyPicker.mission_party(), Progress.xp_to_reach(15))
	var main := await _launch("ch4_lowwater")
	if main == null:
		return
	if main.dialogue_box.visible:
		main.dialogue_box._close()
	await frames(30)
	var lw: LowWater = null
	for e in main.entities.get_children():
		if e is LowWater:
			lw = e
	if not check(lw != null, "Low Water lies at the bottom of the bay"):
		return
	check(not lw.take_hit(10, lw.global_position + Vector2(10, 0)), "asleep: no effect")
	main.leader.global_position = lw.global_position + Vector2(0, 90)  # walk up: it wakes
	for i in 30:
		if main.dialogue_box.visible:
			break
		await frames(2)
	check(main.dialogue_box.visible, "the bay speaks when it wakes (lowwater_intro)")
	main.dialogue_box._close()
	await frames(10)
	check(lw.act != LowWater.Act.DORMANT, "and it rises")

	# The swell: a hero in the lane is hit once as the crest reaches them, one beside it is not.
	var hero: Hero = main.leader
	for h in main.heroes:
		if h != hero:
			h.set_physics_process(false)
			h.global_position = lw.global_position + Vector2(-200, -40)
	hero.global_position = lw.global_position + Vector2(0, 100)
	lw.target = hero
	lw.aim_dir = Vector2.DOWN
	lw.lanes = [Vector2.DOWN]
	lw.lane_from = lw.global_position
	lw.rolled.clear()
	var hp0 := hero.hp
	lw._go(LowWater.Act.ROLL, 0.01)
	await _physics(3)
	check(hero.hp < hp0, "the swell rolls over whoever stays in its lane (%d -> %d)" % [hp0, hero.hp])
	check(lw.lane_pos(Vector2.DOWN, lw.global_position + Vector2(LowWater.LANE_W + 10.0, 100.0)) < 0.0, "a step to the side is out of the lane")

	# The undertow: the whirlpool drags a hero towards its middle.
	lw._go(LowWater.Act.WALK, 5.0)
	hero.knockback = Vector2.ZERO
	hero.velocity = Vector2.ZERO
	await _physics(20)
	hero.knockback = Vector2.ZERO
	lw.pool_at = hero.global_position + Vector2(30, 0)
	lw._open_pool()
	var d0 := hero.global_position.distance_to(lw.pool_at)
	await _physics(10)
	check(hero.global_position.distance_to(lw.pool_at) < d0, "the whirlpool pulls (%.1f -> %.1f)" % [d0, hero.global_position.distance_to(lw.pool_at)])
	lw.pool_t = 0.0

	# Phase 2 at half.
	lw.hp = int(lw.max_hp * 0.45)
	lw.take_hit(1, lw.global_position + Vector2(10, 0))
	await frames(6)
	check_eq(lw.phase, 2, "below half the tide turns")
	check(main.dialogue_box.visible, "the phase change has its scene (lowwater_phase2)")
	main.dialogue_box._close()
	await frames(4)
	check(not lw.take_hit(10, lw.global_position + Vector2(10, 0)), "untouchable while it rears")
	lw.act_t = 0.0
	await frames(4)

	# The Flood: under the sand it cannot be hit; a hero on a dry bank is spared, one in the water is not.
	lw._begin_flood()
	check(lw.untargetable(), "under the sea bed it is out of reach")
	check(lw.banks.size() >= 2, "a few banks stay dry (%d)" % lw.banks.size())
	hero.global_position = lw.banks[0]
	var spared := hero.hp
	lw._flood_lands()
	check_eq(hero.hp, spared, "standing on a dry bank, the flood misses you")
	check_eq(lw.act, LowWater.Act.SURFACE, "then it surfaces at a marked spot")
	lw.act_t = 0.0
	for i in 20:
		if lw.act == LowWater.Act.BEACHED:
			break
		await _physics(1)
	check_eq(lw.act, LowWater.Act.BEACHED, "and lies beached")
	var hp1 := lw.hp
	lw.take_hit(10, lw.global_position + Vector2(10, 0))
	check(hp1 - lw.hp > 10, "beached, it takes more (%d)" % (hp1 - lw.hp))

	for i in 40:
		if lw.dead:
			break
		if lw.act == LowWater.Act.TRANSITION or lw.untargetable():
			lw.act_t = 0.0
		else:
			lw.take_hit(99999, lw.global_position + Vector2(10, 0))
		await frames(10)
	check(lw.dead, "Low Water comes apart")
	for i in 60:
		if main.dialogue_box.visible:
			break
		await frames(10)
	check(main.dialogue_box.visible, "the tide comes home (lowwater_outro)")
	main.dialogue_box._close()
	for i in 100:
		if main.objective.done() or main.results_view.visible:
			break
		await frames(10)
	check(main.objective.done() or main.results_view.visible, "beating Low Water wins the fight")
	if not main.results_view.visible:
		main._show_results("success")
		await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)
	check(Missions.cleared("ch4_lowwater"), "Low Water is cleared")


# ---------------------------------------------------------------- the new enemies

## A quiet patrol: no other enemies, nothing respawning, allies benched (as in test_chapter3.gd).
func _arena() -> Node:
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	if main.dialogue_box.visible:
		main.dialogue_box._close()
	main.respawn_t = 1e9
	for e in main.entities.get_children():
		if e is Enemy:
			e.queue_free()
	await frames(2)
	for h in main.heroes:
		Status.clear_all(h)
		h.set_meta("status_immune", {})
		if h != main.leader:
			h.set_physics_process(false)
			h.velocity = Vector2.ZERO
			h.knockback = Vector2.ZERO
			h.global_position = main.leader.global_position + Vector2(-120, 0)
	return main


func _spawn(main: Node, kind: String, at: Vector2) -> Enemy:
	var pack: Array = EnemyKinds.spawn(main.entities, at, {}, kind)
	for extra in pack.slice(1):
		extra.queue_free()
	var e: Enemy = pack[0]
	e.global_position = at
	return e


func _physics(n: int) -> void:
	for i in n:
		await tree.physics_frame


func test_kinds_have_their_own_scripts() -> void:
	for kind in KINDS + ["lowwater"]:
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % kind)
		check(src != "", "%s has a script" % kind)
		check(not "\"!\"" in src, "%s draws its tell through Telegraph" % kind)
		check("Assists.pace()" in src, "%s honours the enemy speed assist" % kind)
		var entry := {}
		for j in Journal.data().get("codex", []):
			if str(j.get("enemy", "")) == kind:
				entry = j
		check(not entry.is_empty() and str(entry.get("habits", "")) != "" and str(entry.get("weakness", "")) != "", "%s has codex habits and weakness" % kind)
	for kind in KINDS:
		check(EnemyKinds.SCRIPTS.has(kind), "%s is a spawnable script" % kind)


func test_breaker_rears_crashes_down_its_lane_and_puddles() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var b: Breaker = _spawn(main, "breaker", hero.global_position + Vector2(50, 0))
	await frames(2)
	b.target = hero
	b.rear_cd = 0.0
	b._set_state(Enemy.State.CHASE, 0.0)
	for i in 10:
		await tree.physics_frame
		if b.rearing():
			break
	if not check(b.rearing(), "close in: it rears up (the tell)"):
		return
	check(b.in_lane(hero.global_position, hero.radius), "and its lane runs through the hero")
	var hp0 := hero.hp
	b.state_t = 0.0
	for i in 40:
		await tree.physics_frame
		if b.puddled():
			break
	check(hero.hp < hp0, "the crash lands on whoever stayed in the lane (%d -> %d)" % [hp0, hero.hp])
	check(b.puddled(), "then it lies as a puddle: the window")
	var hp1 := b.hp
	b.take_hit(10, b.global_position + Vector2(-8, 0))
	check(hp1 - b.hp > 10, "a puddle takes extra (%d)" % (hp1 - b.hp))


func test_breaker_lane_misses_whoever_steps_aside() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var b: Breaker = _spawn(main, "breaker", hero.global_position + Vector2(50, 0))
	await frames(2)
	b.target = hero
	b.rear_cd = 0.0
	b._set_state(Enemy.State.CHASE, 0.0)
	for i in 10:
		await tree.physics_frame
		if b.rearing():
			break
	if not check(b.rearing(), "it rears"):
		return
	b.set_physics_process(false)
	hero.global_position += Vector2(0, Breaker.LANE_W + 30.0)
	var hp0 := hero.hp
	b._crash()
	check_eq(hero.hp, hp0, "stepped out of the lane: no crash")


func test_netcaster_ring_catches_and_a_hit_spoils_the_throw() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var n: Netcaster = _spawn(main, "netcaster", hero.global_position + Vector2(80, 0))
	await frames(2)
	n.target = hero
	n.cast_cd = 0.0
	n._set_state(Enemy.State.CHASE, 0.0)
	for i in 20:
		await tree.physics_frame
		if n.whirling():
			break
	if not check(n.whirling(), "in range: it whirls the net (the tell)"):
		return
	n.take_hit(5, n.global_position + Vector2(-8, 0))
	check(not n.whirling(), "a hit while it whirls spoils the throw")
	var hp0 := hero.hp
	n.catch(hero)
	check(hero.mire_t > 0.0 and hero.mire_mult < 1.0, "a hero in the ring is caught and slowed")
	check(hero.hp <= hp0, "the net itself does not hurt more than its blow")


func test_gannet_cannot_be_hit_aloft_and_sticks_after_its_dive() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var g: Gannet = _spawn(main, "gannet", hero.global_position + Vector2(40, 0))
	await frames(2)
	check(g.airborne() and g.untargetable(), "it starts in the air")
	check(not g.take_hit(20, hero.global_position), "a blow goes through air")
	g.target = hero
	g.state_t = 0.0
	for i in 20:
		await tree.physics_frame
		if g.state == Gannet.S_MARK:
			break
	if not check_eq(g.state, Gannet.S_MARK, "it hangs over the hero (the tell)"):
		return
	check(g.dive_at.distance_to(hero.global_position) < 4.0, "right where the hero stood")
	var hp0 := hero.hp
	g.state_t = 0.0
	for i in 20:
		await tree.physics_frame
		if g.stuck():
			break
	check(g.stuck(), "it dives and sticks in the sand")
	check(hero.hp < hp0, "stabbing whoever stayed under the mark (%d -> %d)" % [hp0, hero.hp])
	check(not g.untargetable(), "stuck, it can be hit")
	check(g.take_hit(5, g.global_position + Vector2(10, 0)), "and is")


func test_gannet_dive_misses_whoever_steps_out() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var g: Gannet = _spawn(main, "gannet", hero.global_position + Vector2(40, 0))
	await frames(2)
	g.target = hero
	g.state_t = 0.0
	for i in 20:
		await tree.physics_frame
		if g.state == Gannet.S_MARK:
			break
	if not check_eq(g.state, Gannet.S_MARK, "it marks"):
		return
	hero.global_position += Vector2(0, Gannet.DIVE_R + 30.0)
	var hp0 := hero.hp
	g.state_t = 0.0
	for i in 20:
		await tree.physics_frame
		if g.stuck():
			break
	check_eq(hero.hp, hp0, "stepped out of the mark: no stab")


func test_salt_wight_heaps_once_and_a_hit_breaks_the_heap() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var w: SaltWight = _spawn(main, "saltwight", hero.global_position + Vector2(40, 0))
	await frames(2)
	w.take_hit(99999, w.global_position + Vector2(-8, 0))
	check(not w.dead and w.heaped(), "the first fall leaves a heap of salt (the tell)")
	check_eq(w.priority(), 1, "allies go for the heap first")
	w.invuln_t = 0.0
	check(w.take_hit(1, w.global_position + Vector2(-8, 0)), "a hit on the heap lands")
	check(w.dead, "and breaks it for good")


func test_salt_wight_stands_up_again_if_left() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var w: SaltWight = _spawn(main, "saltwight", hero.global_position + Vector2(80, 0))
	await frames(2)
	w.take_hit(99999, w.global_position + Vector2(-8, 0))
	if not check(w.heaped(), "heaped"):
		return
	w.state_t = 0.0
	await _physics(3)
	check(not w.heaped() and not w.dead, "left alone, it stands up again")
	check_eq(w.hp, roundi(w.max_hp * SaltWight.REFORM_SHARE), "at half its health")
	w.invuln_t = 0.0
	w.state = Enemy.State.CHASE
	w.take_hit(99999, w.global_position + Vector2(-8, 0))
	check(w.dead, "and the second fall is the last")


# ---------------------------------------------------------------- Ilse

func test_ilse_has_a_full_kit() -> void:
	check(not SkillTree.branches("ilse").is_empty(), "Ilse has a skill tree")
	check_eq(Techs.list("ilse").size(), 5, "Ilse has five charged techs")
	var ab: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes.json"))["heroes"]["ilse"].get("abilities", [])
	check(ab.size() >= 2 and Abilities.for_ids(ab).size() == ab.size(), "Ilse has her abilities (%s)" % [ab])
	var unwrite: Dictionary = Abilities.for_ids(["unwrite"])[0]
	check_eq(str(unwrite.get("ink", "")), "white", "Unwrite is White Ink")
	check(not Missions.find("personal_ilse").is_empty(), "Ilse has a personal mission")
	check("ilse" in JSON.parse_string(FileAccess.get_file_as_string("res://data/relationships.json"))["romance"]["cast"], "and can fall for Ash")


func test_unwrite_takes_the_weak_off_the_page_and_spares_bosses() -> void:
	var main := await _arena()
	if main == null:
		return
	Empire.join_now("ilse")
	var hero: Hero = main.leader
	hero.facing = Vector2.RIGHT
	var weak: Enemy = _spawn(main, "sellsword", hero.global_position + Vector2(40, 0))
	var strong: Enemy = _spawn(main, "sellsword", hero.global_position + Vector2(70, 0))
	var heap: SaltWight = _spawn(main, "saltwight", hero.global_position + Vector2(55, 30))
	var boss: Enemy = _spawn(main, "sellsword", hero.global_position + Vector2(85, 0))
	await frames(2)
	weak.hp = int(weak.max_hp * 0.2)
	boss.boss = true
	boss.max_hp = 1000
	boss.hp = 100
	heap.take_hit(99999, heap.global_position + Vector2(-8, 0))
	heap.global_position = hero.global_position + Vector2(55, 0)
	var a: Dictionary = Abilities.for_ids(["unwrite"])[0]
	Abilities._unwrite(hero, a, main.entities)
	await frames(2)
	check(weak.dead and weak.erasing, "the weak one is taken off the page")
	check(heap.dead, "a heap of salt is unwritten outright")
	check(not strong.dead and strong.hp < strong.max_hp, "a healthy one only takes the damage")
	check(not boss.dead, "a boss is never unwritten")
