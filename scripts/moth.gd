class_name Moth
extends Enemy
## Letter-moth (issue #16): Gutterwoods moths folded out of unsent letters. They come in packs
## and are fragile. Pattern: flutter in a loose circle around their target, then one at a time
## stop, flash red for 0.4 s (the tell) and dive in a straight line. A swing as they arrive
## swats them; they bounce far when hit.

const ORBIT := 42.0
const DIVE_WINDUP := 0.4
const DIVE_TIME := 0.28
const DIVE_SPEED := 210.0

var damage := 4
var orbit_a := 0.0
var orbit_dir := 1.0
var dive_cd := 1.5
var noticed := false
var paper := Color("efe6cf")


func _ready() -> void:
	art_id = "moth"  # art pass sprite; falls back to the code-drawn letter if the set is missing
	super._ready()
	radius = 4.0
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 3.0
	sprite.visible = art != null
	if art != null:
		sprite.scale = Vector2(0.75, 0.75)  # a moth, not a bird: the drawn wingspan reads too big at full size
	orbit_a = randf() * TAU
	orbit_dir = 1.0 if randf() < 0.5 else -1.0
	dive_cd = randf_range(1.2, 2.8)
	paper = [Color("efe6cf"), Color("e8dcc0"), Color("f4efe4")][randi() % 3]


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192): timers run slower, _slide() moves slower
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO
	var tgt: Node2D = null
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO + 20.0)
	if target:
		tgt = target
		if not noticed:
			noticed = true
			EnemyKinds.notice(self)
	elif goal != null and is_instance_valid(goal):
		tgt = goal

	match state:
		State.WINDUP:
			if tgt:
				facing = (tgt.global_position - global_position).normalized()
			if state_t <= 0.0:
				lunge_dir = facing
				hit_this_lunge.clear()
				_set_state(State.LUNGE, DIVE_TIME)
		State.LUNGE:
			velocity = lunge_dir * DIVE_SPEED + knockback
			_slide()
			for h in get_tree().get_nodes_in_group("heroes"):
				var hero := h as Hero
				if hero and not hero.dead and not hit_this_lunge.has(hero) and hero.global_position.distance_to(global_position) < radius + hero.radius + 4.0:
					hit_this_lunge.append(hero)
					if hero.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), global_position, 120.0):
						Status.struck(self, hero)
			if goal != null and is_instance_valid(goal) and target == null and goal.global_position.distance_to(global_position) < 14.0 and not hit_this_lunge.has(goal):
				hit_this_lunge.append(goal)
				goal.nibble(damage)
			if state_t <= 0.0:
				_set_state(State.RECOVER, 0.5)
			return
		State.RECOVER, State.STAGGER:
			dir = -lunge_dir * 0.6  # flutter back out
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		_:
			if tgt == null:
				if state_t <= 0.0:
					state_t = randf_range(0.5, 1.2)
					wander_dir = Vector2.RIGHT.rotated(randf() * TAU)
					if global_position.distance_to(home) > 70.0:
						wander_dir = (home - global_position).normalized()
				dir = wander_dir * 0.4
			else:
				orbit_a += orbit_dir * delta * 1.6
				var want := tgt.global_position + Vector2.RIGHT.rotated(orbit_a) * ORBIT
				var to := want - global_position
				dir = to.normalized() * clampf(to.length() / 20.0, 0.3, 1.0)
				dir += Vector2(sin(anim_t * 7.0 + orbit_a), cos(anim_t * 5.0)) * 0.35  # erratic flutter
				facing = (tgt.global_position - global_position).normalized()
				dive_cd -= delta
				if dive_cd <= 0.0 and tgt.global_position.distance_to(global_position) < ORBIT + 20.0:
					dive_cd = randf_range(2.0, 3.4)
					_set_state(State.WINDUP, DIVE_WINDUP)

	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 500.0 * delta)
	_slide()


func _on_hit() -> void:
	_set_state(State.STAGGER, 0.4)
	knockback *= 1.6  # paper is light


func _on_death() -> void:
	Fx.burst(get_parent(), global_position + Vector2(0, -10), [paper, Color("15101a"), Color("b8a98a")], 10, 70.0)
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0


func _process(delta: float) -> void:
	if dying_t >= 0.0:
		dying_t += delta
		modulate.a = maxf(1.0 - dying_t * 4.0, 0.0)
		if dying_t > 0.25:
			queue_free()
			return
	if art != null:
		_process_moth_art()
	queue_redraw()
	overlay.queue_redraw()


## The drawn moth: flutters (idle) above its shadow, flashes red in the wind-up, dives (attack).
func _process_moth_art() -> void:
	var row := art_row()
	if state == State.WINDUP or state == State.LUNGE:
		var n := art.frames_of("attack") if art.has("attack") else 1
		var k := 0.25 if state == State.WINDUP else 0.4 + 0.6 * (1.0 - state_t / DIVE_TIME)
		if art.has("attack"):
			art.apply_frame(sprite, "attack", row, clampi(int(k * n), 0, n - 1))
	else:
		art.apply(sprite, "idle", row, anim_t + orbit_a)
	sprite.position = Vector2(0, -6.0 + sin(anim_t * 6.0 + orbit_a) * 1.5)
	if flash_t > 0.0:
		sprite.modulate = Color(1.25, 1.25, 1.25) if Access.reduce_flashing else Color(2, 2, 2)
	elif state == State.WINDUP and Access.strobe(anim_t, 8.0):  # reduced flashing: a steady red, no strobe
		sprite.modulate = Color(1.3, 0.6, 0.6) if Access.reduce_flashing else Color(1.6, 0.5, 0.5)
	else:
		sprite.modulate = Color.WHITE


func _draw() -> void:
	if dying_t < 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	var y := -11.0 + sin(anim_t * 6.0 + orbit_a) * 1.5
	if art != null:
		if state == State.WINDUP:
			Telegraph.alert(overlay, Vector2(-2, y - 9), 9)
		if hp < max_hp:
			UiSkin.field_bar(overlay, roundf(y - 12), 8, float(hp) / max_hp, "enemy", Access.danger_patterns and hp * 4 <= max_hp)
		return
	# A folded letter with flapping wings, hovering above its shadow.
	var flap := absf(sin(anim_t * (26.0 if state != State.WINDUP else 40.0)))
	var col := paper
	if flash_t > 0.0:
		col = Access.flash(paper)
	elif state == State.WINDUP and Access.strobe(anim_t, 8.0):
		col = Color("ff6b6b")
	var wing := 2.0 + 4.0 * flap
	var c := Vector2(0, y)
	overlay.draw_colored_polygon(PackedVector2Array([c, c + Vector2(-wing, -3), c + Vector2(-wing * 0.8, 2)]), col)
	overlay.draw_colored_polygon(PackedVector2Array([c, c + Vector2(wing, -3), c + Vector2(wing * 0.8, 2)]), col)
	# Body: a tiny sealed envelope, with a scrawl of ink.
	overlay.draw_rect(Rect2(c + Vector2(-1.5, -2), Vector2(3, 4)), Color("d9cba8"))
	overlay.draw_rect(Rect2(c + Vector2(-0.5, -1), Vector2(1, 1)), Color("8a1e2a"))
	overlay.draw_line(c + Vector2(-wing * 0.6, -1), c + Vector2(-1.5, 0), Color("15101a", 0.6), 1.0)
	if state == State.WINDUP:
		Telegraph.alert(overlay, Vector2(-2, y - 5), 9)
	if hp < max_hp:
		UiSkin.field_bar(overlay, roundf(y - 8), 8, float(hp) / max_hp, "enemy", Access.danger_patterns and hp * 4 <= max_hp)
