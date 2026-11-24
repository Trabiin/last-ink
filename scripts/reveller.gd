class_name Reveller
extends Enemy
## Masked Reveller (issue #29, Chapter 3): a masquerade guest who has worn the mask too long.
## Pattern: circles at a waltz's distance (KEEP_MIN to KEEP_MAX), then rises on its toes (RISE_TIME; the tell:
## a warning sign over its head and a chevron lane on the floor along the line it will take) and spins
## straight down that line (SPIN_TIME at SPIN_SPEED), cutting everyone it passes. It cannot turn mid-spin, and
## at the end it is dizzy for DIZZY_TIME: the window to hit it. Step out of the lane, then punish.

const KEEP_MIN := 44.0
const KEEP_MAX := 96.0
const RISE_TIME := 0.65
const SPIN_TIME := 0.6
const SPIN_SPEED := 210.0
const DIZZY_TIME := 1.1
const SPIN_EVERY := 3.2

enum { S_RISE = 10, S_SPIN = 11, S_DIZZY = 12 }

var damage := 8
var spin_cd := 1.4
var spin_dir := Vector2.RIGHT
var strafe := 1.0
var noticed := false


func _ready() -> void:
	art_id = "reveller"
	super._ready()
	spin_cd = 1.0 + randf_range(0.0, 1.6)  # a pair does not spin in step
	strafe = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192)
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	spin_cd -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO)
	if target and not noticed:
		noticed = true
		EnemyKinds.notice(self)
	match state:
		S_RISE:
			if target and not target.dead:
				spin_dir = (target.global_position - global_position).normalized()
				facing = spin_dir
			if state_t <= 0.0:
				hit_this_lunge.clear()
				_set_state(S_SPIN, SPIN_TIME)
		S_SPIN:
			velocity = spin_dir * SPIN_SPEED + knockback
			_slide()
			_check_lunge_hits()
			if state_t <= 0.0 or get_slide_collision_count() > 0:
				_set_state(S_DIZZY, DIZZY_TIME)
			queue_redraw()
			return
		S_DIZZY, State.RECOVER, State.STAGGER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		_:
			if target == null:
				if goal != null and is_instance_valid(goal):
					var to_goal := goal.global_position - global_position
					dir = to_goal.normalized() if to_goal.length() > 16.0 else Vector2.ZERO
					nibble_t -= delta
					if to_goal.length() <= 18.0 and nibble_t <= 0.0:
						nibble_t = 1.0
						goal.nibble(DAMAGE)
				elif state_t <= 0.0:
					state_t = randf_range(0.8, 2.0)
					wander_dir = Vector2.ZERO if randf() < 0.35 else Vector2.RIGHT.rotated(randf() * TAU)
					if global_position.distance_to(home) > 90.0:
						wander_dir = (home - global_position).normalized()
				if dir == Vector2.ZERO:
					dir = wander_dir * 0.5
			else:
				var to := target.global_position - global_position
				var d := to.length()
				facing = to.normalized()
				if d < KEEP_MIN:
					dir = -facing
				elif d > KEEP_MAX:
					dir = facing
				else:
					dir = facing.orthogonal() * strafe * 0.7  # circling, as if to music
					if randf() < delta * 0.35:
						strafe = -strafe
				if spin_cd <= 0.0 and d < KEEP_MAX + 20.0 and stun_left() <= 0.0:
					spin_cd = SPIN_EVERY + randf_range(-0.4, 0.6)
					spin_dir = facing
					_set_state(S_RISE, RISE_TIME)
	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	_slide()
	queue_redraw()


func lunge_damage() -> int:
	return damage


func spinning() -> bool:
	return state == S_SPIN and dying_t < 0.0


func dizzy() -> bool:
	return state == S_DIZZY and dying_t < 0.0


func _on_hit() -> void:
	if state == S_SPIN:
		return  # mid-waltz: it does not stop for a scratch
	if state == S_RISE:
		spin_cd = maxf(spin_cd, 1.0)  # caught on its toes: the spin is spoiled
	_set_state(State.STAGGER, 0.35 if state != S_DIZZY else maxf(state_t, 0.35))


func _process(delta: float) -> void:
	if art == null or dying_t >= 0.0 or flash_t > 0.0 or not (state in [S_RISE, S_SPIN, S_DIZZY]):
		super._process(delta)
		if art == null and state == S_SPIN:
			sprite.rotation = anim_t * 24.0
		elif sprite != null:
			sprite.rotation = 0.0
		return
	match state:
		S_RISE:
			art.apply_frame(sprite, "attack", art_row(), 0)
			sprite.position = Vector2(0, -2.0 * (1.0 - state_t / RISE_TIME))  # up on its toes
		S_SPIN:
			# The waltz turn: the "spin" animation once the art has one, else the sprite turned through every row.
			if art.has("spin"):
				art.apply(sprite, "spin", art_row(), anim_t)
			else:
				art.apply_frame(sprite, "walk", posmod(int(anim_t * 16.0), 8), int(anim_t * 10.0) % maxi(art.frames_of("walk"), 1))
			sprite.position = Vector2.ZERO
		S_DIZZY:
			art.apply(sprite, "idle", art_row(), anim_t)
			sprite.position = Vector2(sin(anim_t * 7.0) * 1.5, 0)
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		return
	draw_shadow(5.0)
	if state == S_RISE:  # the lane it is about to spin down
		Telegraph.aim(self, spin_dir * 12.0, spin_dir, 9, 14.0, 1.0 - state_t / RISE_TIME)


func _draw_overlay() -> void:
	super._draw_overlay()
	if dying_t >= 0.0:
		return
	if state == S_RISE:
		Telegraph.alert(overlay, Vector2(-2, -16), 10)
	elif state == S_DIZZY:  # dizzy: three little dots circling the head
		for i in 3:
			var a := anim_t * 5.0 + TAU * i / 3.0
			overlay.draw_circle(Vector2(cos(a) * 6.0, -22.0 + sin(a) * 2.0), 1.2, Color("f3ead2"))
