class_name Duellist
extends Enemy
## Bridge Duellist (issue #29, Chapter 3): the Causeway settles its quarrels on the bridges, and some duellists
## have been settling them so long they challenge anything that walks across.
## Pattern: its guard is up: hits from the front (within GUARD_DOT of where it faces) glance off the blade for
## GUARD_MULT of their damage ("Parried!"), unless it is stunned, beguiled or recovering. From DUEL_RANGE it
## salutes (SALUTE_TIME; the tell: blade raised to the face, a warning sign and an aim line) and then lunges
## twice, fast (LUNGE_TIME each, GAP between). After the second lunge it is open for RECOVER_TIME.
## Get round its side, or dodge the double lunge and hit it in the recovery; a stun or a charm opens the guard.

const DUEL_RANGE := 46.0
const SALUTE_TIME := 0.75
const DUEL_LUNGE_TIME := 0.18
const DUEL_LUNGE_SPEED := 230.0
const GAP := 0.22
const RECOVER_TIME := 1.0
const GUARD_DOT := 0.3
const GUARD_MULT := 0.3
const CIRCLE_SPEED := 0.55

enum { S_SALUTE = 10, S_GAP = 11, S_LUNGE2 = 12 }

var damage := 9
var noticed := false
var strafe := 1.0


func _ready() -> void:
	art_id = "duellist"
	super._ready()
	strafe = 1.0 if randf() < 0.5 else -1.0


## Is the blade up between it and a blow from `from`?
func guarding(from: Vector2) -> bool:
	if dead or dying_t >= 0.0 or stun_left() > 0.0 or charmed():
		return false
	if state in [State.RECOVER, State.LUNGE, S_LUNGE2, S_GAP]:
		return false
	var to_from := from - global_position
	return to_from.length() > 0.1 and facing.dot(to_from.normalized()) > GUARD_DOT


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if guarding(from) and invuln_t <= 0.0:
		amount = maxi(1, roundi(amount * GUARD_MULT))
		force *= 0.2
		Fx.burst(get_parent(), global_position + facing * 8.0 + Vector2(0, -10), [Color("e8eef8"), Color("9aa8c8")], 4, 50.0)
		Fx.damage_number(get_parent(), global_position + Vector2(0, -26), tr("Parried!"), Color("c8d4f0"))
		Audio.sfx("block", 1.4, -6.0, tr("A duellist parries"))
	return super.take_hit(amount, from, force)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	if not (state in [S_SALUTE, S_GAP, State.LUNGE, S_LUNGE2, State.CHASE]):
		super._physics_process(delta)  # wandering, staggered or recovering: Enemy's own handling
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192)
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	match state:
		S_SALUTE:
			if target and not target.dead:
				facing = (target.global_position - global_position).normalized()
			velocity = knockback
			knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
			_slide()
			if state_t <= 0.0:
				_lunge()
			queue_redraw()
			return
		State.LUNGE, S_LUNGE2:
			velocity = lunge_dir * DUEL_LUNGE_SPEED + knockback
			_slide()
			_check_lunge_hits()
			if state_t <= 0.0:
				if state == State.LUNGE:
					_set_state(S_GAP, GAP)
				else:
					_set_state(State.RECOVER, RECOVER_TIME)
			queue_redraw()
			return
		S_GAP:
			if target and not target.dead:
				facing = (target.global_position - global_position).normalized()
			velocity = Vector2.ZERO
			if state_t <= 0.0:
				lunge_dir = facing
				hit_this_lunge.clear()
				_set_state(S_LUNGE2, DUEL_LUNGE_TIME)
			queue_redraw()
			return
		State.CHASE:
			if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
				target = _find_target(AGGRO)
				if target == null:
					_set_state(State.WANDER, 0.0)
			if target:
				if not noticed:
					noticed = true
					EnemyKinds.notice(self)
				var to := target.global_position - global_position
				facing = to.normalized()
				var dir := facing
				if to.length() < DUEL_RANGE * 1.6:
					dir = (facing * 0.35 + facing.orthogonal() * strafe * CIRCLE_SPEED).normalized() * 0.7  # circling, blade up
					if randf() < delta * 0.5:
						strafe = -strafe
				if to.length() < DUEL_RANGE and stun_left() <= 0.0:
					_set_state(S_SALUTE, SALUTE_TIME)
					Audio.sfx("swing", 1.3, -8.0, tr("A duellist salutes"))
					return
				velocity = dir * move_speed + knockback
				knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
				_slide()
				queue_redraw()
				return


func _lunge() -> void:
	lunge_dir = facing
	hit_this_lunge.clear()
	_set_state(State.LUNGE, DUEL_LUNGE_TIME)


func lunge_damage() -> int:
	return damage


func _on_hit() -> void:
	if state in [State.LUNGE, S_LUNGE2]:
		return
	if state == S_SALUTE:  # caught mid-salute: the double lunge is off
		_set_state(State.STAGGER, 0.4)
		return
	if state == State.RECOVER:
		return  # already open; a hit does not reset its recovery
	_set_state(State.STAGGER, 0.25)


func _process(delta: float) -> void:
	if art == null or dying_t >= 0.0 or flash_t > 0.0 or not (state in [S_SALUTE, S_GAP, State.LUNGE, S_LUNGE2]):
		super._process(delta)
		return
	match state:
		S_SALUTE:
			if art.has("salute"):
				art.apply(sprite, "salute", art_row(), SALUTE_TIME - state_t)
			else:
				art.apply_frame(sprite, "attack", art_row(), 1)
		S_GAP:
			art.apply_frame(sprite, "attack", art_row(), 1)
		_:
			var n := art.frames_of("attack")
			art.apply_frame(sprite, "attack", art_row(), clampi(2 + int((1.0 - state_t / DUEL_LUNGE_TIME) * (n - 2)), 0, n - 1))
	sprite.position = Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		return
	draw_shadow(5.0)
	if state == S_SALUTE:
		Telegraph.aim(self, facing * 10.0, facing, 5, 10.0, 1.0 - state_t / SALUTE_TIME)


func _draw_overlay() -> void:
	super._draw_overlay()
	if dying_t >= 0.0:
		return
	if state == S_SALUTE:
		Telegraph.alert(overlay, Vector2(-2, -16), 10)
	elif guarding(global_position + facing * 10.0):  # the guard: a small blade drawn across its front
		var c := facing * 7.0 + Vector2(0, -9)
		var side := facing.orthogonal() * 5.0
		overlay.draw_line(c - side, c + side, Color(0.08, 0.05, 0.08, 0.8), 2.5)
		overlay.draw_line(c - side, c + side, Color("dfe6f5"), 1.0)
