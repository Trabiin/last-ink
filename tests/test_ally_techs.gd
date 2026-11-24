extends "res://tests/test_case.gd"
## Allies firing charged techs (issue #108, scripts/ally_techs.gd; this file is issue #124). For every
## field hero, in a real mission against a stunned crowd: the ally charges and fires its tech under each
## AI preset, "On my call" never fires on its own, "Unleash" fires within a few seconds, and taking
## control mid-charge never lets the tech go, and a stunned crowd just out of reach never gets a wasted
## charge (#161). Also: the tech mode survives a save, and the scoring that
## picks among several techs (#24) works for every hero. tools/ai_tech_sim.gd stays as the long soak.

const MAIN := "res://scenes/main.tscn"
const PRESETS := ["aggressive", "balanced", "distance", "support"]
const FIRE_WAIT := 6000  # ms an ally gets to line up, charge and fire (charges take 0.8 to 2 s)
const CALL_WAIT := 3500  # ms an ally on "On my call" is watched to make sure it holds
## The fights run FAST times quicker than real time: physics ticks FAST times as often, each the same
## 1/60 s step, so the game logic sees exactly what it would at normal speed. Waits are in game time.
const FAST := 3

var Empire: Node
var D := {}


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	Empire.reset()
	D = JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes.json"))
	Engine.physics_ticks_per_second = 60 * FAST
	Engine.max_physics_steps_per_frame = 8 * FAST
	Engine.time_scale = FAST


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 8


## A mission with Ash and `id` in the party (Bran when the ally is Ash himself), every opening talk
## seen. Returns [main, ally] with the leader made untouchable, or [] if the mission didn't start.
func _field(id: String) -> Array:
	Empire.reset()
	for k in Dialogue.data().get("talks", {}):
		Dialogue.mark_seen("talk:" + str(k))
	var other := id if id != "ash" else "bran"
	for rid in Empire.recruits:  # a new campaign starts with Bran in the party: only Ash and `id` go
		if Empire.recruits[rid]["role"] == "party":
			Empire.recruits[rid]["role"] = "idle"
	for rid in ["ash", other]:
		Empire.recruits[rid] = {"role": "party", "target": "", "injured": 0}
	Empire.active_mission = Missions.find("meadow_patrol").duplicate(true)
	var main := await goto(MAIN, 20)
	if main == null or main.leader == null:
		return []
	if tree.paused:  # an opening line: close it
		main.dialogue_box.visible = false
		tree.paused = false
	if id == "ash":
		for h in main.heroes:
			if (h as Hero).hero_id == "bran":
				main.take_control(h)
	var ally: Hero = null
	for h in main.heroes:
		if (h as Hero).hero_id == id:
			ally = h
	if ally == null or ally.controlled:
		return []
	main.respawn_t = 1e9
	Engine.time_scale = FAST  # the mission set it back to the battle speed on entry
	return [main, ally]


func _clear_enemies(main: Node) -> void:
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	main.respawn_t = 1e9
	await frames(2)


## Puts the ally back to a clean slate beside the leader: full HP and gauge, no charge, no order.
func _reset(main: Node, ally: Hero, preset: String, mode := "auto") -> void:
	Techs.cancel(ally)
	var lead: Hero = main.leader
	lead.invuln_t = 999.0
	lead.hp = lead.max_hp
	ally.ai_style = preset
	AllyTechs.set_mode(ally, mode)
	ally.hp = ally.max_hp
	ally.invuln_t = 999.0  # nothing breaks the charge: this checks the decision, not the dodge
	ally.power = 1.0
	ally.ai_tech_cd = 0.0
	ally.ai_tech_order_t = 0.0
	ally.ai_think_t = 0.0
	ally.ai_tech_promise = false
	ally.tech_flash_t = 0.0
	ally.global_position = lead.global_position + Vector2(24, 0)
	ally.facing = Vector2.RIGHT


## Four tough, stunned enemies bunched where the ally's tech reaches: a moment every preset should take.
## The crowd keeps pace with the ally (as a pressing crowd would; stunned ones can't), so these tests
## check the decision, the charge and the release, not the chase.
func _crowd(main: Node, ally: Hero) -> Array:
	await _clear_enemies(main)
	var ts := AllyTechs.techs_of(ally)
	var stand := AllyTechs.standoff(ts[0]) if not ts.is_empty() else 30.0
	# Where the crowd stands relative to the ally. Kept as an offset, not a spot: the ally keeps moving while
	# the crowd spawns (a frame can hold many physics steps on a slow machine), and an offset taken from a
	# spot fixed before that would leave the crowd out of reach for good (seen on CI, and under load here).
	var rel := Vector2(maxf(stand, 22.0), 0)
	var at: Vector2 = ally.global_position + rel
	var es := []
	for attempt in 12:
		if es.size() >= 4:
			break
		main._spawn_enemy(at)
		await frames(1)
		es = tree.get_nodes_in_group("enemies").filter(func(x): return not x.is_queued_for_deletion() and not x.dead)
	es = es.slice(0, 4)
	for i in es.size():
		var e: Enemy = es[i]
		e.max_hp = 9999
		e.hp = 9999
		e.set_meta("offset", rel + Vector2((i % 2) * 5.0 - 2.5, floorf(i / 2.0) * 5.0 - 2.5))
		e.global_position = ally.global_position + e.get_meta("offset")
		e.velocity = Vector2.ZERO
		e.stun(30.0)
	return es


## Holds the crowd at its place beside the ally, topped up so it outlasts the ally's swings.
func _press(ally: Hero) -> void:
	for e in tree.get_nodes_in_group("enemies"):
		if not e.dead and e.has_meta("offset"):
			e.hp = maxi(e.hp, 500)
			e.global_position = ally.global_position + e.get_meta("offset")
			e.knockback = Vector2.ZERO


## One physics step: returns the game time it covered, in ms. Waits count game time, not the wall clock,
## so a slow or busy machine (a CI runner, software rendering) that can't keep up with FAST still gives
## the ally the same time to act instead of less.
func _step() -> float:
	await tree.physics_frame
	return 1000.0 * Engine.time_scale / Engine.physics_ticks_per_second


## Waits up to ms for the ally's tech to go off. Returns the seconds it took, or -1. While waiting,
## keeps the crowd pressing and records whether the ally ever started an AI charge (meta "charged").
func _wait_fire(ally: Hero, ms: int, on_charge := Callable()) -> float:
	var game_ms := 0.0
	var prev := ally.tech_flash_t
	ally.set_meta("charged", false)
	while game_ms < ms:
		game_ms += await _step()
		if not is_instance_valid(ally):
			return -1.0
		if ally.ai_charging:
			ally.set_meta("charged", true)
			if on_charge.is_valid():
				on_charge.call()
				on_charge = Callable()
		_press(ally)
		if ally.tech_flash_t > prev + 0.1:
			return game_ms / 1000.0
		prev = ally.tech_flash_t
	return -1.0


# ------------------------------------------------------------------ every field hero as an ally

## One mission per hero (they take a second or two to load), every check on it in turn.
func test_every_field_hero_as_an_ally() -> void:
	for id in D["heroes"]:
		var f := await _field(id)
		if not check(not f.is_empty(), "%s in the field as an ally" % id):
			continue
		var main: Node = f[0]
		var ally: Hero = f[1]
		if not check(not AllyTechs.techs_of(ally).is_empty(), "%s knows a tech" % id):
			continue
		await _presets_fire(main, ally)
		await _call_holds_and_unleash_fires(main, ally)
		await _hand_over_never_fires(main, ally)
		await _scoring_covers_every_tech(main, ally)
		await _stunned_out_of_reach(main, ally)


## Under each AI preset the ally charges and fires at a crowd in reach.
func _presets_fire(main: Node, ally: Hero) -> void:
	for preset in PRESETS:
		_reset(main, ally, preset)
		await _crowd(main, ally)
		var took := await _wait_fire(ally, FIRE_WAIT)
		check(took >= 0.0, "%s/%s fires its tech at a crowd (charged: %s)" % [ally.hero_id, preset, ally.get_meta("charged")])


## "On my call" never fires on its own; "Unleash" fires within a few seconds and the mode stays.
func _call_holds_and_unleash_fires(main: Node, ally: Hero) -> void:
	var id := ally.hero_id
	_reset(main, ally, "aggressive", "call")
	check_eq(Empire.ai_techs.get(id), "call", "%s: the mode is kept for the next mission" % id)
	await _crowd(main, ally)
	var took := await _wait_fire(ally, CALL_WAIT)
	check(took < 0.0 and not ally.get_meta("charged"), "%s on my call never charges or fires by itself" % id)
	ally.power = 1.0  # it swung while it waited; an order still needs a full gauge
	check_eq(AllyTechs.order_blocker(ally), "", "%s can be ordered" % id)
	AllyTechs.order(ally)
	check_eq(AllyTechs.state_text(ally), "ordered", "%s: the menu shows the order" % id)
	took = await _wait_fire(ally, FIRE_WAIT)
	if check(took >= 0.0, "%s unleashes on order" % id):
		check(ally.ai_tech_order_t <= 0.0, "%s: the order is spent once fired" % id)
		check_eq(AllyTechs.mode_of(ally), "call", "%s: back to waiting for the call" % id)
	AllyTechs.set_mode(ally, "auto")


## The player takes the ally over the moment it starts charging: the tech never goes off by itself.
func _hand_over_never_fires(main: Node, ally: Hero) -> void:
	var id := ally.hero_id
	var was: Hero = main.leader
	_reset(main, ally, "aggressive")
	await _crowd(main, ally)
	var took := await _wait_fire(ally, FIRE_WAIT, func(): main.take_control(ally))
	if not check(ally.get_meta("charged"), "%s starts a charge" % id):
		return
	check(ally.controlled, "%s is under the player's control" % id)
	check(took < 0.0, "%s does not fire after the hand-over" % id)
	took = await _wait_fire(ally, 1200)  # nor a moment later
	check(took < 0.0, "%s does not fire late after the hand-over" % id)
	check(not ally.charging and not ally.ai_charging, "%s: the charge was dropped" % id)
	check(ally.power >= 1.0, "%s keeps its gauge" % id)
	main.take_control(was)
	await frames(2)
	check(not ally.controlled and was.controlled, "%s: control goes back" % id)


## The scoring has to work for every tech a hero can learn (#24), not just the first one: with all
## five known, each scores against a crowd at its own standoff, and pick() chooses one of them.
func _scoring_covers_every_tech(main: Node, ally: Hero) -> void:
	var id := ally.hero_id
	Skills.add_weapon(id, 100000)
	var ts := AllyTechs.techs_of(ally)
	check_eq(ts.size(), 5, "%s: all five techs under AI" % id)
	_reset(main, ally, "balanced")
	var es := await _crowd(main, ally)
	var best := AllyTechs.pick(ally, "balanced", main.leader, 14.0)
	check(not best["tech"].is_empty() and best["score"] > 0.0, "%s: a tech is worth it against a crowd" % id)
	check(best["tech"] in ts, "%s: one it knows" % id)
	for t in ts:
		var stand := AllyTechs.standoff(t)
		check(stand > 0.0, "%s/%s: a standoff distance" % [id, t.get("id")])
		for i in es.size():
			(es[i] as Enemy).global_position = ally.global_position + Vector2(maxf(stand, 22.0) + (i % 2) * 5.0 - 2.5, floorf(i / 2.0) * 5.0 - 2.5)
		var aim := AllyTechs.best_aim(ally, t, "balanced", main.leader, 0.0, false)
		check(aim["score"] > 0.0, "%s/%s: scores against a crowd at its standoff" % [id, t.get("id")])


## Issue #161: a stunned crowd just past the tech's reach (inside the 14 px "they keep coming" slack,
## but stunned, so they never come). Under every preset the ally either leaves it alone or walks in
## and fires; it must never plant its feet, charge, hold and give up (about 3 s wasted, again and again).
func _stunned_out_of_reach(main: Node, ally: Hero) -> void:
	var id := ally.hero_id
	for preset in PRESETS:
		_reset(main, ally, preset)
		var es := await _crowd(main, ally)
		var t: Dictionary = AllyTechs.techs_of(ally)[0]
		var gap := AllyTechs._span(t) + 5.0 + 8.0  # enemy radius 5: 8 px out of reach
		for i in es.size():
			var e: Enemy = es[i]
			e.global_position = ally.global_position + Vector2(gap + (i % 2) * 3.0, floorf(i / 2.0) * 6.0 - 3.0)
			e.remove_meta("offset")  # stunned: they stay where they are
			e.velocity = Vector2.ZERO
			e.knockback = Vector2.ZERO
			e.invuln_t = 0.0  # a swing during setup leaves them flashing, and a flashing enemy scores nothing
		# The crowd was in reach while it spawned: an ally that started a charge on it then is now chasing
		# a crowd that jumped away, which says nothing about the decision under test (and failed whenever
		# its think tick fell inside the setup frames). Start the watch from a clean slate.
		Techs.cancel(ally)
		ally.power = 1.0
		ally.ai_tech_cd = 0.0
		ally.ai_think_t = 0.0
		ally.ai_tech_promise = false
		if preset == "balanced":  # the scoring itself: slack counts for enemies that can come, not stunned ones
			var here := ally.global_position
			var lead: Hero = main.leader
			var stunned: float = AllyTechs.score(ally, t, here, Vector2.RIGHT, preset, lead, es, 14.0)["score"]
			check(stunned <= 0.0, "%s: a stunned crowd 8 px out of reach scores nothing (%.2f)" % [id, stunned])
			for e in es:
				(e as Enemy).stun_until = 0
			var free: float = AllyTechs.score(ally, t, here, Vector2.RIGHT, preset, lead, es, 14.0)["score"]
			check(free > 0.0, "%s: the same crowd on its feet counts (it keeps coming)" % id)
			for e in es:
				(e as Enemy).stun(30.0)
		var w := await _watch(ally, 4500)
		check(w["abandoned"] == 0, "%s/%s: no charge wasted on a stunned crowd out of reach (started %d, fired %d, gave up %d)" \
			% [id, preset, w["started"], w["fired"], w["abandoned"]])


## Watches the ally for ms of game time: charges it starts, techs it fires, charges it drops unfired.
func _watch(ally: Hero, ms: int) -> Dictionary:
	var out := {"started": 0, "fired": 0, "abandoned": 0}
	var game_ms := 0.0
	var was := false
	var prev := ally.tech_flash_t
	while game_ms < ms:
		game_ms += await _step()
		if not is_instance_valid(ally):
			break
		for e in tree.get_nodes_in_group("enemies"):
			if not e.dead:
				e.hp = maxi(e.hp, 500)
		var fired := ally.tech_flash_t > prev + 0.1
		prev = ally.tech_flash_t
		if fired:
			out["fired"] += 1
		if ally.ai_charging and not was:
			out["started"] += 1
		elif was and not ally.ai_charging and not fired:
			out["abandoned"] += 1
		was = ally.ai_charging
	return out


# ------------------------------------------------------------------ saves and scoring

func test_tech_modes_survive_a_save() -> void:
	Empire.ai_techs = {"bran": "call", "odile": "auto"}
	var d = JSON.parse_string(JSON.stringify(Empire.to_dict()))
	Empire.reset()
	check(Empire.ai_techs.is_empty(), "a new campaign starts with no modes")
	Empire.from_dict(d)
	check_eq(Empire.ai_techs.get("bran"), "call", "Bran stays on my call")
	check_eq(Empire.ai_techs.get("odile"), "auto", "Odile stays on auto")
	(d as Dictionary).erase("ai_techs")  # a save from before #108
	Empire.from_dict(d)
	check(Empire.ai_techs.is_empty(), "an old save gives everyone Auto")
