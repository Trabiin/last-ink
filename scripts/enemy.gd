class_name Enemy
extends Actor
## "Nibbler": a small hungry scrap of the Blank. Wanders, chases, and lunges
## after a clear wind-up so the player can always dodge by moving.

enum State { WANDER, CHASE, WINDUP, LUNGE, RECOVER, STAGGER }

const AGGRO := 110.0
const LOSE := 200.0
const LUNGE_RANGE := 30.0
const WINDUP_TIME := 0.5
const LUNGE_TIME := 0.22
const LUNGE_SPEED := 190.0
const DAMAGE := 6

var state: int = State.WANDER
var state_t := 0.0
var wander_dir := Vector2.ZERO
var target: Hero
var lunge_dir := Vector2.ZERO
var hit_this_lunge: Array = []
var home := Vector2.ZERO
var static_seed := 0
var sprite: Sprite2D
var overlay: Node2D
var dying_t := -1.0
## Something to go and eat when no hero is close (a Defense mission's wardstone). Needs nibble(amount).
var goal: Node2D = null
var nibble_t := 0.0
var xp := 3  # shared by the party when it falls (issue #15)
## Hold the Line (abilities.gd): for taunt_t seconds this enemy goes for taunter and nobody else.
var taunter: Hero = null
var taunt_t := 0.0
## Bosses shrug off stuns and can always find a hero, even one who has slipped out of sight (Lamps Out).
var boss := false
## Stuns (Last Orders, Chucking Out) and Audit marks run on the clock, so every subclass's own state
## machine honours them without extra bookkeeping (see stun(), mark(), _set_state, _adjust_damage).
var stun_until := 0
var mark_until := 0
var mark_mult := 1.0
## Rallied by a Reader reading a name aloud (scripts/reader.gd, issue #206): hits land harder until then (msec).
var rally_until := 0
const RALLY_MULT := 1.35
## Beguiled by Hortense (abilities.gd kind "charm", Chapter 3): it stands gazing at her (a stun on the clock, so every
## subclass honours it) and her hits on it land charm_mult times as hard. Bosses only flinch.
var charm_until := 0
var charm_by: Node = null
var charm_mult := 1.0
## Signed up to Nan's Small Print (kind "weaken"): its hits deal weak_mult of their damage and it moves at
## slow_by of its speed until then (msec).
var weak_until := 0
var weak_mult := 1.0
var slow_by := 1.0

## Art pass sprite set (scripts/sprite_set.gd) by id; subclasses with their own drawing set "" before super._ready().
var art_id := "nibbler"
var art: SpriteSet

## Puny's green slime, recolored into a scrap of the Blank: paper-white with an ink-black core.
const SLIME_COLORS := {"body": Color("e4e1d8"), "core": Color("15101a"), "shine": Color("ffffff")}


func _ready() -> void:
	max_hp = 28
	move_speed = 40.0
	radius = 5.0
	super._ready()
	collision_layer = 4
	number_color = Color.WHITE
	add_to_group("enemies")
	home = global_position
	static_seed = randi()
	sprite = Sprite2D.new()
	sprite.texture = Art.SLIME
	sprite.hframes = 15
	sprite.offset = Vector2(0, -4)
	sprite.material = Art.recolor_material("slime", SLIME_COLORS)
	add_child(sprite)
	if has_meta("art"):  # data/enemies.json "sprite": a kind that reuses a script with its own art
		art_id = str(get_meta("art"))
	art = SpriteSet.of(art_id) if art_id != "" else null
	if art != null:
		sprite.material = null  # the art pass sprite replaces the recoloured slime
		sprite.offset = Vector2.ZERO
	overlay = Node2D.new()
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	var marks := StatusMarks.new()  # stun stars and Audit seal, above whatever the subclass draws
	marks.enemy = self
	add_child(marks)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192): timers run slower, _slide() moves slower
	anim_t += delta
	flash_t = max(flash_t - delta, 0.0)
	state_t -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO

	match state:
		State.WANDER:
			if state_t <= 0.0:
				state_t = randf_range(0.8, 2.0)
				wander_dir = Vector2.ZERO if randf() < 0.35 else Vector2.RIGHT.rotated(randf() * TAU)
				if global_position.distance_to(home) > 90.0:
					wander_dir = (home - global_position).normalized()
			dir = wander_dir * 0.5
			if goal != null and is_instance_valid(goal):
				var to_goal := goal.global_position - global_position
				dir = to_goal.normalized() if to_goal.length() > 16.0 else Vector2.ZERO
				facing = to_goal.normalized()
				nibble_t -= delta
				if to_goal.length() <= 18.0 and nibble_t <= 0.0:
					nibble_t = 1.0
					goal.nibble(DAMAGE)
			target = _find_target(AGGRO)
			if target:
				EnemyKinds.notice(self)  # first sighting: its tip (scarecrows, sellswords) and its journal entry
				_set_state(State.CHASE, 0.0)
		State.CHASE:
			if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
				target = _find_target(AGGRO)
				if target == null:
					_set_state(State.WANDER, 0.0)
			if target:
				var to := target.global_position - global_position
				dir = to.normalized()
				facing = dir
				if to.length() < LUNGE_RANGE:
					_set_state(State.WINDUP, WINDUP_TIME)
		State.WINDUP:
			if target and not target.dead:
				facing = (target.global_position - global_position).normalized()
			if state_t <= 0.0:
				lunge_dir = facing
				hit_this_lunge.clear()
				_set_state(State.LUNGE, LUNGE_TIME)
		State.LUNGE:
			velocity = lunge_dir * LUNGE_SPEED + knockback
			_slide()
			_check_lunge_hits()
			if state_t <= 0.0:
				_set_state(State.RECOVER, 0.7)
			queue_redraw()
			return
		State.RECOVER, State.STAGGER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)

	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	_slide()
	queue_redraw()


## move_and_slide() at the enemy speed assist's pace. Every enemy moves through this.
func _slide() -> void:
	var pace := Assists.pace() * (slow_by if weakened() else 1.0)  # Small Print drags its feet too
	if pace >= 1.0:
		move_and_slide()
		return
	velocity *= pace
	move_and_slide()
	velocity /= pace  # what the slide did to it (walls), back at full scale for the enemy's own logic


func _set_state(s: int, t: float) -> void:
	var left := stun_left()
	if left > 0.0:  # a stunned enemy stays stunned whatever its own logic asks for
		s = State.STAGGER
		t = maxf(t, left)
	state = s
	state_t = t


static func _now() -> int:
	return Time.get_ticks_msec()


func stun_left() -> float:
	return maxf(float(stun_until - _now()) / 1000.0, 0.0)


func marked() -> bool:
	return mark_until > _now()


## Seeing stars for t seconds: no chasing, no lunges. Bosses only flinch.
func stun(t: float) -> void:
	if dead or t <= 0.0:
		return
	if boss:
		t = minf(t, 0.25)
	stun_until = maxi(stun_until, _now() + int(t * 1000.0))
	_set_state(State.STAGGER, t)


## Audit: takes mult times damage from everything for t seconds.
func mark(t: float, mult: float) -> void:
	if dead:
		return
	mark_until = maxi(mark_until, _now() + int(t * 1000.0))
	mark_mult = maxf(mult, 1.0)


## Is a Reader's reading spurring this one on? (scripts/reader.gd)
func rallied() -> bool:
	return rally_until > _now()


## Spurs it on for t seconds (a Reader reading nearby).
func rally(t: float) -> void:
	if not dead:
		rally_until = maxi(rally_until, _now() + int(t * 1000.0))


## What its hits deal on top of their base damage (a Reader's rally, Nan's Small Print).
func hit_mult() -> float:
	return (RALLY_MULT if rallied() else 1.0) * (weak_mult if weakened() else 1.0)


## Beguiled for t seconds by a hero (Hortense): it stops fighting, and by's hits on it land mult times as hard.
## Bosses are flattered for a moment and carry on.
func charm(t: float, by: Node, mult := 1.5) -> void:
	if dead or t <= 0.0:
		return
	if boss:
		stun(0.25)
		return
	charm_until = maxi(charm_until, _now() + int(t * 1000.0))
	charm_by = by
	charm_mult = maxf(mult, 1.0)
	stun(t)
	if taunter != null:
		taunt_t = 0.0


func charmed() -> bool:
	return charm_until > _now() and not dead


## Is this one beguiled by h right now (her hits land harder)?
func charmed_by(h: Node) -> bool:
	return charmed() and charm_by == h


## Small Print: for t seconds its hits deal mult of their damage and it moves at slow of its speed.
## Bosses read the contract more carefully: half the effect.
func weaken(t: float, mult: float, slow := 1.0) -> void:
	if dead or t <= 0.0:
		return
	if boss:
		mult = lerpf(1.0, mult, 0.5)
		slow = lerpf(1.0, slow, 0.5)
	weak_until = maxi(weak_until, _now() + int(t * 1000.0))
	weak_mult = clampf(mult, 0.1, 1.0)
	slow_by = clampf(slow, 0.2, 1.0)


func weakened() -> bool:
	return weak_until > _now() and not dead


## Out of reach for now (an Ink Eel under the ink): heroes and allies do not pick it as a target.
func untargetable() -> bool:
	return false


## Unwritten by White Ink (Ilse's Unwrite, abilities.gd kind "unwrite", Chapter 4): taken off the page outright, with
## no last tricks (a Salt Wight does not crumble into a heap first). Callers keep bosses out.
var erasing := false


func erase_out() -> void:
	if dead:
		return
	erasing = true
	invuln_t = 0.0
	Fx.burst(get_parent(), global_position + Vector2(0, -8), [Color.WHITE, Color("f4f2ec"), Color("c8c4bc")], 18, 70.0)
	Fx.damage_number(get_parent(), global_position + Vector2(0, -24), Loc.t("Unwritten"), Color("f4f2ec"))
	hp = 0  # no damage number and no difficulty scaling: it is simply not there any more
	dead = true
	Audio.hit(false, true)
	_on_death()
	died.emit(self)


## A Salt Wight's heap (scripts/saltwight.gd): down but not gone, waiting to stand up again unless it is broken.
func heaped() -> bool:
	return false


## How much its lunge deals before the party's armour (kinds with a "damage" stat override this).
func lunge_damage() -> int:
	return DAMAGE


## How badly the ally AI wants to hit this one right now (scripts/ally_ai.gd): 0 = like any other enemy,
## 1 = break what it is doing (a Reader reading), 2 = it has hold of a hero (a Penitent's grab).
func priority() -> int:
	return 0


func _adjust_damage(amount: int) -> int:
	if marked():
		return roundi(amount * mark_mult)
	return amount


## Drop everything and go for this hero for a while.
func taunt(h: Hero, time: float) -> void:
	taunter = h
	taunt_t = time
	target = h
	if state == State.WANDER:
		_set_state(State.CHASE, 0.0)


func _find_target(dist: float) -> Hero:
	if taunt_t > 0.0 and taunter != null and is_instance_valid(taunter) and not taunter.dead:
		return taunter
	var best: Hero = null
	var best_d := dist
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or (hero.hidden() and not boss):
			continue
		var d := hero.global_position.distance_to(global_position)
		if Status.warded_from(self, hero, d) and not boss:
			continue  # a Ward Candle: Blank-born things leave them be unless they're right there (issue #112)
		if d < best_d:
			best_d = d
			best = hero
	return best


func _check_lunge_hits() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or hit_this_lunge.has(hero):
			continue
		if hero.global_position.distance_to(global_position) < radius + hero.radius + 4.0:
			hit_this_lunge.append(hero)
			if hero.take_hit(Empire.damage_to_party(roundi(lunge_damage() * hit_mult())), global_position, 200.0):
				Status.struck(self, hero)  # what this kind inflicts (data/enemies.json, issue #112)


func _on_hit() -> void:
	# Getting hit interrupts a wind-up (rewarding aggression) but not a lunge in progress.
	if state != State.LUNGE:
		_set_state(State.STAGGER, 0.35)


func _on_death() -> void:
	Fx.burst(get_parent(), global_position + Vector2(0, -6), [Color.WHITE, Color("d9d9d9"), Color.BLACK], 16, 80.0)
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0


func _process(delta: float) -> void:
	if art != null:
		_process_art(delta)
		return
	# Slime sheet: 0-2 squish, 3-5 hop, 6 hurt flash, 7-8 land, 10-14 burst.
	var f := 0
	if dying_t >= 0.0:
		dying_t += delta
		f = 10 + int(dying_t * 14.0)
		if f > 14:
			queue_free()
			return
	elif flash_t > 0.0:
		f = 6
	else:
		match state:
			State.WINDUP:
				f = 2
			State.LUNGE:
				f = 3 + clampi(int((1.0 - state_t / LUNGE_TIME) * 3.0), 0, 2)
			State.RECOVER:
				f = 7 if state_t > 0.45 else 8
			_:
				f = [0, 1, 2, 1][int(anim_t * 6.0) % 4]
	sprite.frame = f
	sprite.position = Vector2(randf_range(-0.7, 0.7), 0) if state == State.WINDUP else Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


## Art pass version of _process: the state picks the animation; lunges follow their timer.
func _process_art(delta: float) -> void:
	if dying_t >= 0.0:
		dying_t += delta
		if art.has("death"):
			if dying_t > art.duration("death") + 0.1:
				queue_free()
				return
			art.apply(sprite, "death", art_row(), dying_t)
		else:
			# No drawn death: it crumples flat and fades out like a scrap of paper (the burst is Fx).
			const CRUMPLE := 0.35
			if dying_t > CRUMPLE:
				queue_free()
				return
			var k := dying_t / CRUMPLE
			art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", art_row(), 1)
			sprite.scale = Vector2(1.0 + 0.4 * k, 1.0 - 0.8 * k)
			sprite.modulate.a = 1.0 - k
		queue_redraw()
		return
	elif flash_t > 0.0 and art.has("hurt"):
		art.apply(sprite, "hurt", art_row(), 0.12 - flash_t)
	else:
		match state:
			State.WINDUP:
				art.apply_frame(sprite, "attack", art_row(), 1)
			State.LUNGE:
				var n := art.frames_of("attack")
				art.apply_frame(sprite, "attack", art_row(), clampi(2 + int((1.0 - state_t / LUNGE_TIME) * (n - 2)), 0, n - 1))
			_:
				art.apply(sprite, "walk" if velocity.length() > 8.0 else "idle", art_row(), anim_t)
	sprite.position = Vector2(randf_range(-0.7, 0.7), 0) if state == State.WINDUP else Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


## Which way the sprite looks: where it is moving, else where it faces.
func art_row() -> int:
	var v := velocity if velocity.length() > 8.0 and state != State.LUNGE else facing
	return Hero.dir_row(v)


func _draw() -> void:
	if dying_t < 0.0:
		draw_shadow(5.0)


func _draw_overlay() -> void:
	if dying_t >= 0.0:
		return
	# Static flecks: the Blank leaking out of it.
	var rng := RandomNumberGenerator.new()
	rng.seed = static_seed + int(anim_t * (2.0 if Access.reduce_flashing else 12.0))  # reduced flashing: the flecks drift, not flicker
	for i in 3:
		var p := Vector2(rng.randf_range(-8, 8), rng.randf_range(-12, 2))
		overlay.draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.9) if i % 2 else Color(0, 0, 0, 0.7))
	if rallied():  # spurred on by a Reader: two small chevrons over the head, pointing up
		Telegraph.rally(overlay, Vector2(0, -21))
	if taunt_t > 0.0:  # Hold the Line: a little orange tag shows who it is locked onto
		overlay.draw_rect(Rect2(-1.5, -19, 3, 3), Color("f2a65a"))
	if state == State.WINDUP:
		Telegraph.alert(overlay, Vector2(-2, -12), 10)
	if hp < max_hp:
		UiSkin.field_bar(overlay, -14, 12, float(hp) / max_hp, "enemy", Access.danger_patterns and hp * 4 <= max_hp)
