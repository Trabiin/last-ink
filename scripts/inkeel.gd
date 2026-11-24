class_name InkEel
extends Enemy
## Ink Eel (issue #29, Chapter 3): an eel made of the ink lake, with half-finished words under its skin.
## Pattern: it swims under the ground (no hits land, nothing collides) towards its target. Close enough, it
## picks the spot where the hero stands and a dark ring opens there (RING_TIME; the tell, a round danger zone
## filling in). Then it bursts up through the ring biting everything inside (BITE_R), and stays on the surface
## for SURFACE_TIME, slow and open, before it dives again. Never stand in a ring; hit it while it is up.

const RING_TIME := 0.85
const BITE_R := 18.0
const SURFACE_TIME := 1.7
const DIVE_TIME := 0.35
const SWIM_SPEED_MULT := 1.4
const RISE_RANGE := 70.0
const UNDER_MIN := 1.2  # it stays under at least this long between bites

enum { S_UNDER = 10, S_RING = 11, S_UP = 12, S_DIVE = 13 }

var damage := 8
var under_t := 0.0
var ring_at := Vector2.ZERO
var ring: FloorMark = null
var noticed := false
var bit := false
var base_layer := 4


func _ready() -> void:
	art_id = "inkeel"
	super._ready()
	base_layer = collision_layer
	_dive_now()


func submerged() -> bool:
	return state in [S_UNDER, S_RING] and dying_t < 0.0


func untargetable() -> bool:
	return submerged()


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if submerged():
		return false  # under the ink: the blow goes through water
	return super.take_hit(amount, from, force)


func _dive_now() -> void:
	under_t = UNDER_MIN
	collision_layer = 0
	_set_state(S_UNDER, 0.0)
	sprite.visible = false


func _surface() -> void:
	collision_layer = base_layer
	sprite.visible = true
	global_position = ring_at
	_end_ring()
	bit = false
	_set_state(S_UP, SURFACE_TIME)
	Fx.burst(get_parent(), global_position, [Color("2a2048"), Color("6a5a9a"), Color("15101a")], 12, 70.0)
	Audio.sfx("burst", 0.7, -6.0, tr("An ink eel bursts out of the ground"))
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead or h.global_position.distance_to(global_position) > BITE_R + h.radius:
			continue
		if h.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), global_position, 190.0):
			Status.struck(self, h)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192)
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO + 20.0)
	if target and not noticed:
		noticed = true
		EnemyKinds.notice(self)
	var dir := Vector2.ZERO
	match state:
		S_UNDER:
			under_t -= delta
			var tgt: Node2D = target
			if tgt == null and goal != null and is_instance_valid(goal):
				tgt = goal
			if tgt != null:
				var to := tgt.global_position - global_position
				dir = to.normalized() * SWIM_SPEED_MULT
				facing = to.normalized()
				if to.length() < RISE_RANGE and under_t <= 0.0 and stun_left() <= 0.0:
					ring_at = tgt.global_position
					_set_state(S_RING, RING_TIME)
					ring = FloorMark.put(self, _paint_ring)
					ring.global_position = ring_at
			else:
				if state_t <= 0.0:
					state_t = randf_range(1.0, 2.0)
					wander_dir = Vector2.RIGHT.rotated(randf() * TAU) if global_position.distance_to(home) < 90.0 else (home - global_position).normalized()
				dir = wander_dir * 0.6
		S_RING:
			global_position = global_position.move_toward(ring_at, move_speed * SWIM_SPEED_MULT * 2.0 * delta)
			if state_t <= 0.0:
				_surface()
			queue_redraw()
			return
		S_UP:
			if target and not target.dead:
				facing = (target.global_position - global_position).normalized()
				dir = facing * 0.25  # slithers a little on the surface
			if goal != null and is_instance_valid(goal) and not bit and goal.global_position.distance_to(global_position) < BITE_R + 10.0:
				bit = true
				goal.nibble(damage)
			if state_t <= 0.0:
				_set_state(S_DIVE, DIVE_TIME)
		S_DIVE:
			if state_t <= 0.0:
				_dive_now()
		State.STAGGER, State.RECOVER:
			if state_t <= 0.0:
				_set_state(S_DIVE, DIVE_TIME)
		_:
			_set_state(S_DIVE, DIVE_TIME)
	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	_slide()
	queue_redraw()


func _on_hit() -> void:
	if state == S_UP:
		_set_state(State.STAGGER, maxf(state_t, 0.3))  # flinches, then dives when it would have anyway


func _set_state(s: int, t: float) -> void:
	if submerged() and stun_left() > 0.0:
		s = State.STAGGER  # a stun (Last Orders, a charm) drags it up out of the ink
	super._set_state(s, t)
	if state == State.STAGGER and sprite != null and not sprite.visible:
		collision_layer = base_layer
		sprite.visible = true
		_end_ring()


func _end_ring() -> void:
	if ring != null and is_instance_valid(ring):
		ring.queue_free()
	ring = null


func _on_death() -> void:
	_end_ring()
	super._on_death()


func _exit_tree() -> void:
	_end_ring()


func _paint_ring(ci: CanvasItem) -> void:
	if state != S_RING:
		return
	var k := clampf(1.0 - state_t / RING_TIME, 0.0, 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	ci.draw_circle(Vector2.ZERO, BITE_R * (0.4 + 0.6 * k), Color(0.1, 0.07, 0.2, 0.55))
	Telegraph.circle(ci, Vector2.ZERO, BITE_R, k)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _process(delta: float) -> void:
	if dying_t < 0.0 and state in [S_UNDER, S_RING]:
		queue_redraw()  # only the ripple shows
		return
	if art == null or dying_t >= 0.0 or flash_t > 0.0 or not (state in [S_UP, S_DIVE]):
		super._process(delta)
		return
	if state == S_DIVE:
		if art.has("dive"):
			art.apply(sprite, "dive", art_row(), DIVE_TIME - state_t)
		else:
			art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", art_row(), 1)
		sprite.scale = Vector2(1.0, clampf(state_t / DIVE_TIME, 0.2, 1.0))
	else:
		var since := SURFACE_TIME - state_t
		var n := art.frames_of("attack")
		if since < 0.35 and n > 0:
			art.apply_frame(sprite, "attack", art_row(), clampi(int(since / 0.35 * n), 0, n - 1))
		else:
			art.apply(sprite, "idle", art_row(), anim_t)
		sprite.scale = Vector2.ONE
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		return
	if state in [S_UNDER, S_RING]:  # a ripple moving through the ground, with a fin of ink
		var r := 5.0 + sin(anim_t * 6.0) * 1.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, r, 0, TAU, 16, Color(0.1, 0.07, 0.2, 0.6), 1.5)
		draw_arc(Vector2.ZERO, r + 4.0, 0, TAU, 16, Color(0.1, 0.07, 0.2, 0.3), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_colored_polygon(PackedVector2Array([Vector2(-2, 0), Vector2(0, -4), Vector2(2, 0)]), Color("2a2048"))
		return
	draw_shadow(5.0)


func _draw_overlay() -> void:
	if state in [S_UNDER, S_RING]:
		return
	super._draw_overlay()
