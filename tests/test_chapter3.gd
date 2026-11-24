extends "res://tests/test_case.gd"
## Chapter 3: Masquerade, the Velvet Causeway (issue #29). The end of Chapter 2 opens the Causeway, the beats
## play in order, each story and personal mission launches on its own map and runs its steps, the Host plays
## its phases, the four new enemies keep their tells and their openings, the three new heroes' kits do what
## their cards say, and Hortense's spy reveal stays a decoy: she is never the betrayer.

const MAIN := "res://scenes/main.tscn"
const HUB := "res://scenes/hub.tscn"
const CH3 := ["ch3_quay", "ch3_masquerade", "ch3_shallows", "ch3_wharf", "ch3_host"]
const PERSONAL := ["personal_hortense", "personal_saffron", "personal_nan"]
const HEROES := ["hortense", "saffron", "nan"]
const KINDS := ["reveller", "duellist", "inkeel", "lamplighter"]

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


## A story campaign that has just beaten the Abbot, holding eight provinces (Chapter 3's start).
func _ch2_done() -> void:
	Empire.reset()
	Story.begin()
	for pid in ["meadow", "oldmill", "lampwick", "saltreed", "candlemere", "ossuary", "quillpine"]:
		Empire.territory().find(pid)["owner"] = "you"
	for id in ["gristle", "ninefingers", "abeyance", "velvette"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for m in ["meadow_prologue", "ch1_breakout", "act1_concord", "auditor_duel", "ch2_candleford", "ch2_hall", "ch2_crypt", "ch2_abbot"]:
		Empire.missions_cleared.append(m)
	for t in ["meadow_intro", "ch1_arrest", "ch1_takeover", "act1_rumours", "act1_writ", "act1_concord_after",
			"act1_end", "ch2_bells", "ch2_candleford_after", "ch2_hall_ready", "ch2_hall_after", "ch2_hild", "ch2_verity_after"]:
		Dialogue.mark_seen("talk:" + t)
	Empire.open_region("abbey", true)


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
	for id in CH3:
		var m := Missions.find(id)
		if not check(not m.is_empty(), "%s exists" % id):
			continue
		check(m.get("story", false), "%s is a story mission" % id)
		check(FileAccess.file_exists(str(m["map"])), "%s map %s exists" % [id, m["map"]])
		check_eq(Empire.territory().find(m["province"]).get("region", ""), "causeway", "%s is on the Causeway" % id)
	for id in PERSONAL:
		var m := Missions.find(id)
		if check(not m.is_empty(), "%s exists" % id):
			check(FileAccess.file_exists(str(m["map"])), "%s map exists" % id)
	for kind in KINDS:
		check(EnemyKinds.data()["kinds"].has(kind), "enemy kind %s" % kind)
	check(BossFight.BOSSES.has("host"), "the Host is a boss")
	for t in ["host_intro", "host_phase2", "host_outro"]:
		check(not Dialogue.talk(t).is_empty(), "the Host's %s" % t)
	check_eq(Empire.faction("velvet").get("province", ""), "causeway", "the Velvet Nobility sit on the Causeway")
	check_eq(Empire.territory().find("causeway").get("owner", ""), "velvet", "and own it")
	var chapters: Array = Journal.data().get("chapters", []).map(func(c): return c["id"])
	check("ch3" in chapters, "the journal has a Chapter 3")
	for g in Story.data()["goals"]:
		if g.get("chapter", "") == "ch3":
			check(g.has("show"), "Chapter 3 goal '%s' stays hidden until its beat" % g["text"])
	for id in HEROES:
		check_eq(str(Empire.recruit(id).get("tier", "")), "field", "%s fights in the field" % id)
		check(not Empire.bond_info(id).is_empty(), "%s has a bond" % id)


## The decoy (#29, #186): Hortense spies for the Concord in the story, and that is the whole of it. She is never
## on the betrayal list, so no score, foreshadowing or lock can ever pick her.
func test_hortense_is_never_the_betrayer() -> void:
	check(not Betrayal.is_candidate("hortense"), "Hortense is not a betrayal candidate")
	_ch2_done()
	Empire.recruits["hortense"] = {"role": "idle", "target": "", "injured": 0}
	var ranked: Array = Betrayal.ranking().map(func(r): return r["id"])
	check(not "hortense" in ranked, "and never ranked as one")
	check(Betrayal.top() != "hortense", "or leads them")


# ---------------------------------------------------------------- story flow in town

func test_ch2_end_opens_the_causeway() -> void:
	_ch2_done()
	_seen(["ch2_end"])
	check(not "causeway" in Empire.regions_open, "the Causeway is under the fog before the invitation")
	Empire.territory().find("quillpine")["owner"] = "free"
	check_eq(Story.next_beat().get("talk", ""), "", "seven provinces: the invitation waits for an eighth")
	Empire.territory().find("goldwash")["owner"] = "you"
	var hub := await goto(HUB, 20)
	if hub == null:
		return
	if not check(hub.dialogue_box.visible and hub.story_beat.get("talk", "") == "ch3_invitation", "the invitation plays"):
		return
	hub.dialogue_box._close()
	await frames(3)
	check("causeway" in Empire.regions_open, "the invitation lifts the fog over the Causeway")
	check(hub.chapter_card.visible, "the Chapter 3 card shows")
	hub.chapter_card.hide()
	hub.chapter_card.closed.emit()
	await frames(3)
	check(not _offered("lanternquay", "ch3_quay").is_empty(), "Lantern Quay offers The Singer on the Quay")


func test_beats_play_in_order() -> void:
	_ch2_done()
	Empire.territory().find("goldwash")["owner"] = "you"
	_seen(["ch2_end", "ch3_invitation"])
	Empire.open_region("causeway", true)
	check_eq(Story.next_beat().get("talk", ""), "", "nothing until the quay")
	_clear(["ch3_quay"])
	check_eq(Story.next_beat().get("talk", ""), "ch3_quay_after", "after the quay")
	_seen(["ch3_quay_after"])
	var masq := _offered("causeway", "ch3_masquerade")
	if check(masq.size() == 1, "the Masquerade is on the map"):
		check(str(masq[0].get("blocker", "")) != "", "locked until you hold the Terraces")
	check(_offered("inkmere", "ch3_shallows").size() == 1, "the Shallows (optional) are open")
	Empire.territory().find("terraces")["owner"] = "you"
	masq = _offered("causeway", "ch3_masquerade")
	check(masq.size() == 1 and str(masq[0].get("blocker", "")) == "", "the Terraces open the door")
	_clear(["ch3_masquerade"])
	Empire.recruits["hortense"] = {"role": "idle", "target": "", "injured": 0}
	check_eq(Story.next_beat().get("talk", ""), "ch3_masquerade_after", "after the masquerade")
	_seen(["ch3_masquerade_after"])
	check_eq(Story.next_beat().get("talk", ""), "ch3_two_rapiers", "Fauvette and Hortense have their scene")
	_seen(["ch3_two_rapiers"])
	_clear(["ch3_wharf"])
	check_eq(Story.next_beat().get("talk", ""), "ch3_wharf_after", "after the wharf")
	_seen(["ch3_wharf_after"])
	var host := _offered("causeway", "ch3_host")
	if check(host.size() == 1, "the Host is on the map"):
		check(str(host[0].get("blocker", "")).contains("Neutral"), "locked until the Nobility are Neutral (%s)" % host[0].get("blocker", ""))
	Empire.change_standing("velvet", 40, "test", true)
	host = _offered("causeway", "ch3_host")
	check(host.size() == 1 and str(host[0].get("blocker", "")) == "", "Neutral opens the stairs")
	_clear(["ch3_host"])
	check_eq(Story.next_beat().get("talk", ""), "ch3_end", "the end of Chapter 3")
	_seen(["ch3_end"])
	var showing := Story.goals().map(func(g): return g["text"])
	check("Hold twelve provinces" in showing, "Chapter 3's open goals show after its end")


func test_two_rapiers_needs_both() -> void:
	_ch2_done()
	Empire.recruits.erase("velvette")
	Empire.territory().find("goldwash")["owner"] = "you"
	Empire.open_region("causeway", true)
	_seen(["ch2_end", "ch3_invitation", "ch3_quay_after", "ch3_masquerade_after"])
	_clear(["ch3_quay", "ch3_masquerade"])
	Empire.recruits["hortense"] = {"role": "idle", "target": "", "injured": 0}
	check(Story.next_beat().get("talk", "") != "ch3_two_rapiers", "no Fauvette, no scene")


# ---------------------------------------------------------------- story effects

func test_story_effects_apply() -> void:
	_ch2_done()
	Empire.open_region("causeway", true)
	Missions.story_effects(Missions.find("ch3_quay"))
	check(Empire.recruits.has("saffron"), "Saffron joins after the quay")
	var before: int = Empire.standing_of("velvet")
	Missions.story_effects(Missions.find("ch3_masquerade"))
	check(Empire.recruits.has("hortense"), "Hortense joins after the masquerade")
	check_eq(Empire.standing_of("velvet"), before + 8, "the Nobility remember you danced")
	Missions.story_effects(Missions.find("ch3_shallows"))
	check(Empire.recruits.has("nan"), "Nan (and Tally) join after the Shallows")
	var concord: int = Empire.standing_of("concord")
	Missions.story_effects(Missions.find("ch3_wharf"))
	check(Empire.standing_of("concord") < concord, "the wharf costs you with the Concord")


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


## Walks a script mission's steps the quick way (as in test_chapter2.gd).
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
					if is_instance_valid(e) and not e.dead:
						if e.has_method("untargetable") and e is InkEel:
							(e as InkEel)._set_state(InkEel.S_UP, 1.0)
							e.collision_layer = e.base_layer
						e.take_hit(99999, e.global_position + Vector2(8, 0))
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
	_ch2_done()
	Empire.territory().find("goldwash")["owner"] = "you"
	Empire.territory().find("terraces")["owner"] = "you"
	Empire.open_region("causeway", true)
	_seen(["ch2_end", "ch3_invitation", "ch3_quay_after", "ch3_masquerade_after"])
	for id in ["ch3_quay", "ch3_masquerade", "ch3_shallows", "ch3_wharf"]:
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
	for id in HEROES:
		check(Empire.recruits.has(id), "%s came home" % id)


func test_personal_missions_run_their_steps() -> void:
	_ch2_done()
	Empire.open_region("causeway", true)
	for id in HEROES:
		Empire.join_now(id)
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


func test_host_fight() -> void:
	_ch2_done()
	Empire.open_region("causeway", true)
	_clear(["ch3_quay", "ch3_masquerade", "ch3_wharf"])
	Empire.change_standing("velvet", 40, "test", true)
	Progress.award(PartyPicker.mission_party(), Progress.xp_to_reach(12))
	var main := await _launch("ch3_host")
	if main == null:
		return
	if main.dialogue_box.visible:
		main.dialogue_box._close()
	await frames(30)
	var host: Host = null
	for e in main.entities.get_children():
		if e is Host:
			host = e
	if not check(host != null, "the Host is at the table"):
		return
	check(not host.take_hit(10, host.global_position + Vector2(10, 0)), "asleep at the table: no effect")
	main.leader.global_position = host.global_position + Vector2(0, 90)  # walk up: it wakes
	for i in 30:
		if main.dialogue_box.visible:
			break
		await frames(2)
	check(main.dialogue_box.visible, "it speaks when it wakes (host_intro)")
	main.dialogue_box._close()
	await frames(10)
	check(host.act != Host.Act.DORMANT, "and gets up")

	# The speech: a fan of words that fly.
	host.target = main.leader
	host.aim_dir = Vector2.DOWN
	host._go(Host.Act.SPEECH, 0.01)
	await frames(4)
	var words := 0
	for n in main.entities.get_children():
		if n is HostWord:
			words += 1
	check(words >= Host.SPEECH_WORDS[0], "the speech is a volley of words (%d)" % words)

	# The breath: a guest in reach is swallowed and heals it.
	var guest: Enemy = EnemyKinds.spawn(main.entities, host.global_position + Vector2(0, 20), {}, "reveller")[0]
	guest.global_position = host.global_position + Vector2(0, 20)
	host.hp = int(host.max_hp * 0.7)
	var before := host.hp
	host._go(Host.Act.INHALE, 1.0)
	await frames(6)
	check(host.hp > before, "a swallowed guest heals it (%d -> %d)" % [before, host.hp])
	check(not is_instance_valid(guest) or guest.dead, "the guest is gone")
	host._go(Host.Act.WALK, 0.5)

	# Phase 2 at half.
	host.hp = int(host.max_hp * 0.45)
	host.take_hit(1, host.global_position + Vector2(10, 0))
	await frames(6)
	check_eq(host.phase, 2, "below half it unmasks")
	check(main.dialogue_box.visible, "the phase change has its scene (host_phase2)")
	main.dialogue_box._close()
	await frames(4)
	check(not host.take_hit(10, host.global_position + Vector2(10, 0)), "untouchable while it unmasks")
	host.act_t = 0.0
	await frames(4)

	# The gulp: in the air it cannot be targeted, it lands, and stuck in the floor it takes more.
	host._start_gulp()
	check(host.untargetable(), "in the air it is out of reach")
	for i in 120:
		if host.act == Host.Act.STUCK:
			break
		await frames(2)
	check_eq(host.act, Host.Act.STUCK, "it lands and sticks")
	for i in 40:
		if host.dead:
			break
		if host.act == Host.Act.TRANSITION or host.untargetable():
			host.act_t = 0.0
		else:
			host.take_hit(99999, host.global_position + Vector2(10, 0))
		await frames(10)
	check(host.dead, "the Host goes down")
	for i in 60:
		if main.dialogue_box.visible:
			break
		await frames(10)
	check(main.dialogue_box.visible, "its last words (host_outro)")
	main.dialogue_box._close()
	for i in 100:
		if main.objective.done() or main.results_view.visible:
			break
		await frames(10)
	check(main.objective.done() or main.results_view.visible, "beating the Host wins the fight")
	if not main.results_view.visible:
		main._show_results("success")
		await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)
	check(Missions.cleared("ch3_host"), "the Host is cleared")


# ---------------------------------------------------------------- the new enemies

## A quiet patrol: no other enemies, nothing respawning, allies benched (as in test_ch2_enemies.gd).
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
	for kind in KINDS + ["host"]:
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % kind)
		check(src != "", "%s has a script" % kind)
		check(not "\"!\"" in src, "%s draws its tell through Telegraph" % kind)
		if kind == "lamplighter":  # moves as a Spitter (which honours the assist); its own part is the lantern's flight
			src = FileAccess.get_file_as_string("res://scripts/thrown_lantern.gd")
		check("Assists.pace()" in src, "%s honours the enemy speed assist" % kind)
		var entry := {}
		for j in Journal.data().get("codex", []):
			if str(j.get("enemy", "")) == kind:
				entry = j
		check(not entry.is_empty() and str(entry.get("habits", "")) != "" and str(entry.get("weakness", "")) != "", "%s has codex habits and weakness" % kind)
	for kind in KINDS:
		check(EnemyKinds.SCRIPTS.has(kind), "%s is a spawnable script" % kind)


func test_reveller_rises_spins_and_gets_dizzy() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var r: Reveller = _spawn(main, "reveller", hero.global_position + Vector2(70, 0))
	await frames(2)
	r.target = hero
	r.spin_cd = 0.0
	r._set_state(Enemy.State.CHASE, 0.0)
	for i in 10:
		await tree.physics_frame
		if r.state == Reveller.S_RISE:
			break
	check_eq(r.state, Reveller.S_RISE, "in range and ready: it rises on its toes (the tell)")
	r.state_t = 0.0
	await _physics(2)
	check(r.spinning(), "then spins down the lane")
	r.take_hit(1, r.global_position + Vector2(-8, 0))
	check(r.spinning(), "a scratch does not stop the waltz")
	r.state_t = 0.0
	await _physics(2)
	check(r.dizzy(), "and ends dizzy: the window")


func test_duellist_parries_from_the_front_not_the_side() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var d: Duellist = _spawn(main, "duellist", hero.global_position + Vector2(140, 0))
	await frames(2)
	d.set_physics_process(false)
	d.facing = Vector2.LEFT
	d._set_state(Enemy.State.CHASE, 0.0)
	var front := d.global_position + Vector2(-20, 0)
	var side := d.global_position + Vector2(0, 20)
	check(d.guarding(front), "guard up against a blow from the front")
	check(not d.guarding(side), "open from the side")
	var hp0 := d.hp
	d.take_hit(20, front)
	var parried := hp0 - d.hp
	d.invuln_t = 0.0
	d.flash_t = 0.0
	d._set_state(Enemy.State.CHASE, 0.0)
	d.facing = Vector2.LEFT
	var hp1 := d.hp
	d.take_hit(20, side)
	var landed := hp1 - d.hp
	check(parried < landed, "a parried blow does less (%d vs %d)" % [parried, landed])
	d.invuln_t = 0.0
	d._set_state(Enemy.State.RECOVER, 1.0)
	check(not d.guarding(front), "recovering after the double lunge, the guard is down")
	d._set_state(Enemy.State.CHASE, 0.0)
	d.stun(1.0)
	check(not d.guarding(front), "a stun opens the guard")


func test_duellist_salutes_then_lunges_twice() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var d: Duellist = _spawn(main, "duellist", hero.global_position + Vector2(36, 0))
	await frames(2)
	d.target = hero
	d._set_state(Enemy.State.CHASE, 0.0)
	for i in 10:
		await tree.physics_frame
		if d.state == Duellist.S_SALUTE:
			break
	check_eq(d.state, Duellist.S_SALUTE, "close in: it salutes (the tell)")
	d.state_t = 0.0
	await _physics(2)
	check_eq(d.state, Enemy.State.LUNGE, "the first lunge")
	d.state_t = 0.0
	await _physics(2)
	check_eq(d.state, Duellist.S_GAP, "a breath")
	d.state_t = 0.0
	await _physics(2)
	check_eq(d.state, Duellist.S_LUNGE2, "the second lunge")
	d.state_t = 0.0
	await _physics(2)
	check_eq(d.state, Enemy.State.RECOVER, "then it is open")


func test_ink_eel_cannot_be_hit_under_the_ink() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var eel: InkEel = _spawn(main, "inkeel", hero.global_position + Vector2(50, 0))
	await frames(2)
	check(eel.submerged() and eel.untargetable(), "it starts under the ink")
	check(not eel.take_hit(20, hero.global_position), "a blow goes through water")
	check(hero._nearest_enemy(hero.global_position, 200.0) != eel, "and nobody aims at it")
	eel.target = hero
	eel.under_t = 0.0
	for i in 20:
		await tree.physics_frame
		if eel.state == InkEel.S_RING:
			break
	if not check_eq(eel.state, InkEel.S_RING, "close enough: a ring opens under the hero (the tell)"):
		return
	check(eel.ring_at.distance_to(hero.global_position) < 4.0, "right where the hero stood")
	var hp0 := hero.hp
	eel.state_t = 0.0
	await _physics(2)
	check_eq(eel.state, InkEel.S_UP, "it bursts up through the ring")
	check(hero.hp < hp0, "biting whoever stayed in it (%d -> %d)" % [hp0, hero.hp])
	check(not eel.untargetable(), "up on the surface it can be hit")
	check(eel.take_hit(5, eel.global_position + Vector2(10, 0)), "and is")


func test_ink_eel_ring_misses_whoever_steps_out() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var eel: InkEel = _spawn(main, "inkeel", hero.global_position + Vector2(40, 0))
	await frames(2)
	eel.target = hero
	eel.under_t = 0.0
	for i in 20:
		await tree.physics_frame
		if eel.state == InkEel.S_RING:
			break
	if not check_eq(eel.state, InkEel.S_RING, "a ring opens"):
		return
	hero.global_position += Vector2(0, InkEel.BITE_R + 30.0)
	var hp0 := hero.hp
	eel.state_t = 0.0
	await _physics(2)
	check_eq(hero.hp, hp0, "stepped out of the ring: no bite")


func test_lamplighter_lantern_lands_where_the_hero_stood() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var l: Enemy = _spawn(main, "lamplighter", hero.global_position + Vector2(90, 0))
	await frames(2)
	l.target = hero
	l.call("_spit")
	await frames(1)
	var lantern: ThrownLantern = null
	for n in main.area.get_children():
		if n is ThrownLantern:
			lantern = n
	if not check(lantern != null, "a lantern is in the air"):
		return
	check(lantern.global_position.distance_to(hero.global_position) < 20.0, "aimed at the hero's spot")
	var hp0 := hero.hp
	lantern.t = lantern.flight
	await frames(3)
	check(hero.hp < hp0, "standing in the circle burns (%d -> %d)" % [hp0, hero.hp])


# ---------------------------------------------------------------- the new heroes' kits

func test_heroes_have_full_kits() -> void:
	for id in HEROES:
		check(not SkillTree.branches(id).is_empty(), "%s has a skill tree" % id)
		check_eq(Techs.list(id).size(), 5, "%s has five charged techs" % id)
		var ab: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes.json"))["heroes"][id].get("abilities", [])
		check(ab.size() >= 2 and Abilities.for_ids(ab).size() == ab.size(), "%s has their abilities (%s)" % [id, ab])


func test_charm_beguiles_and_bosses_shrug_it_off() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var e: Enemy = _spawn(main, "sellsword", hero.global_position + Vector2(30, 0))
	await frames(2)
	e.charm(2.0, hero, 1.5)
	check(e.charmed() and e.charmed_by(hero), "beguiled by her")
	check(e.stun_left() > 0.0, "it stops fighting")
	var b: Enemy = _spawn(main, "sellsword", hero.global_position + Vector2(-30, 0))
	await frames(1)
	b.boss = true
	b.charm(2.0, hero, 1.5)
	check(not b.charmed(), "a boss is flattered for a moment and carries on")


func test_small_print_weakens_hits() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var e: Enemy = _spawn(main, "sellsword", hero.global_position + Vector2(30, 0))
	await frames(2)
	var base := e.hit_mult()
	e.weaken(3.0, 0.6, 0.7)
	check(e.weakened(), "under the Small Print")
	check(e.hit_mult() < base, "its hits deal less (%.2f -> %.2f)" % [base, e.hit_mult()])
