extends "res://tests/test_case.gd"
## Chapter 2 enemies' own moves (issue #206): the Penitent's grab and hold, the Reader's reading that spurs
## other Erasers on, the Whitewasher's stripe that slows and Erases. Each move is driven to its tell, played
## out in a real mission scene (timers hurried where waiting would only cost frames), and then broken the
## way the codex says it can be.

const MAIN := "res://scenes/main.tscn"

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
	Access.danger_patterns = true


## A quiet patrol: no other enemies, nothing respawning, every hero clear of statuses, allies benched.
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
			# Benched: the ally AI would rush in and break holds, readings and brush dips on its own timing,
			# which made these checks depend on where it happened to stand. Parked behind the leader, still
			# close enough for AllyAI.urgent_target to be asked about.
			h.set_physics_process(false)
			h.velocity = Vector2.ZERO
			h.knockback = Vector2.ZERO
			h.global_position = main.leader.global_position + Vector2(-120, 0)
	return main


func _spawn(main: Node, kind: String, at: Vector2) -> Enemy:
	var pack: Array = EnemyKinds.spawn(main.entities, at, {}, kind)
	for extra in pack.slice(1):  # spawn() rolls a pack: keep one
		extra.queue_free()
	var e: Enemy = pack[0]
	e.global_position = at  # a pack is spread round a ring 10 px out: put this one exactly where asked
	return e


func _physics(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _ally(main: Node) -> Hero:
	for h in main.heroes:
		if h != main.leader and not h.dead:
			return h
	return null


func test_kinds_have_their_own_scripts() -> void:
	for kind in ["penitent", "reader", "whitewasher"]:
		var info := EnemyKinds.kind(kind)
		check_eq(str(info.get("script", kind)), kind, "%s runs its own behaviour" % kind)
		check(EnemyKinds.SCRIPTS.has(kind), "%s is a spawnable script" % kind)
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % kind)
		check(not "\"!\"" in src, "%s draws its tell through Telegraph" % kind)
		check("Assists.pace()" in src, "%s honours the enemy speed assist" % kind)
		var entry := {}
		for j in Journal.data().get("codex", []):
			if str(j.get("enemy", "")) == kind:
				entry = j
		check(not entry.is_empty() and str(entry.get("habits", "")) != "" and str(entry.get("weakness", "")) != "", "%s has codex habits and weakness" % kind)
	check_eq(str(EnemyKinds.kind("reader").get("faction", "")), "erasers", "Readers are Erasers")
	check_eq(str(EnemyKinds.kind("whitewasher").get("faction", "")), "erasers", "Whitewashers are Erasers")


func test_penitent_grabs_and_lets_go_when_an_ally_hits_it() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var p: Penitent = _spawn(main, "penitent", hero.global_position + Vector2(20, 0))
	await frames(2)
	p.global_position = hero.global_position + Vector2(20, 0)  # well inside its reach, whatever the first frames did
	p.target = hero
	p.grab_cd = 0.0
	p._set_state(Enemy.State.CHASE, 0.0)
	await _physics(2)
	check_eq(p.state, Penitent.S_HUNCH, "in reach and ready: it hunches (the tell)")
	p.state_t = 0.0
	for i in 30:
		await tree.physics_frame
		if p.state == Penitent.S_HOLD:
			break
	if not check_eq(p.state, Penitent.S_HOLD, "the hands close on the hero"):
		return
	check(p.held == hero and Status.has(hero, "stun"), "the hero is held fast")
	check_eq(p.priority(), 2, "a hold is the most urgent thing on the field")
	var ally := _ally(main)
	if ally != null:
		check(AllyAI.urgent_target(ally, hero, 170.0) == p, "allies drop everything to break the hold")
	var hp_before := hero.hp
	p.hold_left = 1.0
	p.wipe_t = 0.0
	await _physics(3)
	check(hero.hp < hp_before, "the hold wipes a little off (%d -> %d)" % [hp_before, hero.hp])
	p.take_hit(1, hero.global_position + Vector2(0, -30))  # a friend's swing
	check(p.held == null and not Status.has(hero, "stun"), "a hit from someone else makes it let go")
	check_eq(p.state, Enemy.State.STAGGER, "and it reels")
	check(p.state_t >= 1.0, "for long enough to punish (%.2f s)" % p.state_t)
	check(not Status.has(hero, "erase"), "a broken hold doesn't Erase")
	check(Status.immune(hero, "stun"), "a moment's immunity: no grab straight after")


func test_penitent_hold_runs_out_and_wipes() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var p: Penitent = _spawn(main, "penitent", hero.global_position + Vector2(14, 0))
	await frames(2)
	p.facing = Vector2.LEFT
	p._take_hold(hero)
	check(p.held == hero, "caught")
	hero.hp = 3
	p.wipe_t = 0.0
	await _physics(2)
	check(hero.hp >= 1 and not hero.dead, "the wiping never kills")
	p.hold_left = 0.01
	await _physics(2)
	check(p.held == null and not Status.has(hero, "stun"), "the hold ends on its own")
	check(Status.has(hero, "erase"), "and leaves the hero Erased")
	# A hero proof against stuns (a trinket, or straight after one) can't be held: it grabs air.
	var q: Penitent = _spawn(main, "penitent", hero.global_position + Vector2(-14, 0))
	await frames(2)
	q.facing = Vector2.RIGHT
	q._take_hold(hero)
	check(q.held == null, "no hold on a hero who has just shaken one off")
	# Dying, being stunned or leaving the scene mid-hold always frees the hero.
	hero.set_meta("status_immune", {})
	q._take_hold(hero)
	check(q.held == hero, "caught again once the immunity is gone")
	q.stun(1.0)
	check(q.held == null and not Status.has(hero, "stun"), "a stunned Penitent lets go")
	hero.set_meta("status_immune", {})
	q._set_state(Enemy.State.CHASE, 0.0)
	q.stun_until = 0
	q._take_hold(hero)
	q.take_hit(9999, hero.global_position + Vector2(0, -30))
	check(not Status.has(hero, "stun"), "a dead Penitent lets go")


func test_reader_spurs_erasers_and_is_interrupted() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var r: Reader = _spawn(main, "reader", hero.global_position + Vector2(70, 0))
	var w: Whitewasher = _spawn(main, "whitewasher", hero.global_position + Vector2(90, 30))
	var n: Enemy = _spawn(main, "nibbler", hero.global_position + Vector2(80, -20))
	await frames(2)
	w.paint_cd = 99.0
	r.target = hero
	r.read_cd = 0.0
	r._set_state(Enemy.State.CHASE, 0.0)
	await _physics(2)
	if not check(r.reading(), "a few strides off, it stops to read a name"):
		return
	check(r.name_text != "", "it has a name to read")
	check(r.ring != null and is_instance_valid(r.ring), "its voice's reach shows on the floor")
	await _physics(2)
	check(w.rallied(), "a Whitewasher in earshot is spurred on")
	check(not n.rallied(), "a Nibbler isn't an Eraser and doesn't care")
	check(not r.rallied(), "the Reader doesn't spur itself")
	check(w.hit_mult() > 1.0, "spurred Erasers hit harder")
	check_eq(r.priority(), 1, "allies go for a Reader that is reading")
	r.take_hit(1, hero.global_position)
	check(not r.reading(), "a hit cuts the reading off")
	check_eq(r.state, Enemy.State.STAGGER, "and staggers it")
	await frames(2)
	check(r.ring == null, "the ring goes with the reading")
	# Read to the end: the spur lingers and the lunge that follows hits harder.
	w.rally_until = 0
	r.stun_until = 0
	r.read_cd = 0.0
	r.global_position = hero.global_position + Vector2(70, 0)
	r._set_state(Enemy.State.CHASE, 0.0)
	await _physics(2)
	check(r.reading(), "it starts again")
	var plain := r.damage
	r.state_t = 0.0
	await _physics(2)
	check(not r.reading() and r.named_t > 0.0, "a finished name sends it in")
	check(r.lunge_damage() > plain, "the lunge after a finished name hits harder (%d > %d)" % [r.lunge_damage(), plain])
	check(r.move_speed > r.base_speed, "and it comes on fast")
	check(float(w.rally_until - Time.get_ticks_msec()) > 1500.0, "the spur outlasts the reading")


func test_whitewasher_stripe_slows_and_erases() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var w: Whitewasher = _spawn(main, "whitewasher", hero.global_position + Vector2(90, 0))
	await frames(2)
	w.spit_cd = 99.0
	w.target = hero
	w.paint_cd = 0.0
	w._set_state(Enemy.State.CHASE, 0.0)
	await _physics(2)
	if not check_eq(w.state, Whitewasher.S_PAINT, "it dips its brush"):
		return
	var s: WhiteStripe = w.stripe
	if not check(s != null and is_instance_valid(s), "the stripe's warning is on the ground"):
		return
	check(s.get_parent() == main.area, "on the floor, under everyone")
	var between := (s.global_position - hero.global_position).dot(Vector2.RIGHT)
	check(between > 0.0 and between < 40.0, "across the way in, just in front of the hero (%.0f px)" % between)
	hero.global_position = s.global_position
	await _physics(2)
	check(not Status.has(hero, "erase"), "the warning itself does nothing")
	s.t = s.warn + WhiteStripe.SWEEP
	hero.global_position = s.global_position
	await _physics(2)
	check(Status.has(hero, "erase"), "walking through wet whitewash Erases")
	check(hero.mire_t > 0.0 and hero.mire_mult < 1.0, "and drags at the feet")
	var off := s.global_position + Vector2.from_angle(s.global_rotation).orthogonal() * 30.0
	check(not s.covers(off, hero.radius), "it is a short stripe: one step to the side clears it")
	# A hit while it dips knocks the brush away: nothing is painted.
	w.paint_cd = 0.0
	w.stun_until = 0
	w._set_state(Enemy.State.CHASE, 0.0)
	hero.global_position = w.global_position + Vector2(-90, 0)
	await _physics(2)
	if check_eq(w.state, Whitewasher.S_PAINT, "it dips again"):
		var s2: WhiteStripe = w.stripe
		w.take_hit(1, hero.global_position)
		await frames(2)
		check(not is_instance_valid(s2), "a hit mid-dip spoils the stripe")


func test_telegraphs_draw_in_both_styles() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var p: Penitent = _spawn(main, "penitent", hero.global_position + Vector2(40, 0))
	var r: Reader = _spawn(main, "reader", hero.global_position + Vector2(80, 20))
	var w: Whitewasher = _spawn(main, "whitewasher", hero.global_position + Vector2(100, -20))
	await frames(2)
	p.target = hero
	p._set_state(Penitent.S_HUNCH, 0.5)
	r.target = hero
	r._start_reading()
	w.target = hero
	w._start_paint(hero.global_position - w.global_position)
	for patterns in [true, false]:
		Access.danger_patterns = patterns
		for e in [p, r, w]:
			e.queue_redraw()
			e.overlay.queue_redraw()
		await frames(3)
	check(true, "drawn without errors")


## The hold runs on real time: with the enemy speed assist on, the hunch is slower to read but the hold is no longer.
func test_pace_assist_never_lengthens_a_hold() -> void:
	var main := await _arena()
	if main == null:
		return
	var hero: Hero = main.leader
	var p: Penitent = _spawn(main, "penitent", hero.global_position + Vector2(14, 0))
	await frames(2)
	Assists.pace_i = 2
	p.facing = Vector2.LEFT
	p._take_hold(hero)
	var start := p.hold_left
	await _physics(6)
	var spent := start - p.hold_left
	check(absf(spent - 6.0 / Engine.physics_ticks_per_second) < 0.02, "the hold counts down at full speed (%.3f s in 6 ticks)" % spent)
