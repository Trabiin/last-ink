class_name Spitter
extends Enemy
## Spitter (issue #16): a bloated scrap of the Blank that hangs back and spits globs.
## Pattern: keeps 60-110 px from its target, circling; every couple of seconds it stops and
## swells for 0.7 s (the tell: it grows, shakes and shows a faint aim line), then spits a slow
## glob at where the hero stood. Sidestep, then close in: up close it panics and backs off.

const KEEP_MIN := 60.0
const KEEP_MAX := 110.0
const SPIT_WINDUP := 0.7
const SPIT_EVERY := 2.3
const ShotScript := preload("res://scripts/ink_glob.gd")

var damage := 7
var spit_cd := 1.2
var strafe := 1.0
var aim := Vector2.ZERO
var noticed := false

const SPIT_COLORS := {"body": Color("cbc6d3"), "core": Color("4a0f22"), "shine": Color("ffffff")}


func _ready() -> void:
	art_id = "spitter"
	super._ready()
	if art == null:
		sprite.material = Art.recolor_material("slime", SPIT_COLORS)
		sprite.scale = Vector2(1.15, 1.15)
	strafe = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192): timers run slower, _slide() moves slower
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	spit_cd -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO
	var tgt: Node2D = null
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO + 30.0)
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
				aim = tgt.global_position - global_position
				facing = aim.normalized()
			if state_t <= 0.0:
				_spit()
				_set_state(State.RECOVER, 0.55)
		State.RECOVER, State.STAGGER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		_:
			if tgt == null:
				if state_t <= 0.0:
					state_t = randf_range(0.8, 2.0)
					wander_dir = Vector2.ZERO if randf() < 0.4 else Vector2.RIGHT.rotated(randf() * TAU)
					if global_position.distance_to(home) > 90.0:
						wander_dir = (home - global_position).normalized()
				dir = wander_dir * 0.5
			else:
				var to := tgt.global_position - global_position
				var d := to.length()
				facing = to.normalized()
				if d < KEEP_MIN:
					dir = -facing * 1.2  # too close: scuttle back
				elif d > KEEP_MAX:
					dir = facing
				else:
					dir = facing.orthogonal() * strafe * 0.6
					if randf() < delta * 0.4:
						strafe = -strafe
				if spit_cd <= 0.0 and d < KEEP_MAX + 30.0:
					spit_cd = SPIT_EVERY + randf_range(-0.3, 0.4)
					aim = to
					_set_state(State.WINDUP, SPIT_WINDUP)

	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	_slide()


func _spit() -> void:
	var shot: InkGlob = ShotScript.new()
	shot.kind = Journal.kind_of(self)  # what the glob inflicts (Status, issue #112)
	shot.position = global_position + Vector2(0, -6)
	shot.dir = aim.normalized() if aim.length() > 0.1 else facing
	shot.damage = roundi(damage * hit_mult())  # a Reader's rally (issue #206)
	if target == null and goal != null and is_instance_valid(goal):
		shot.goal = goal
	get_parent().add_child(shot)


func _on_hit() -> void:
	# A hit during the swell chokes the spit off.
	_set_state(State.STAGGER, 0.35)
	spit_cd = maxf(spit_cd, 0.8)


func _process(delta: float) -> void:
	if art != null:
		_process_spitter_art(delta)
		return
	var f := 0
	if dying_t >= 0.0:
		dying_t += delta
		f = 10 + int(dying_t * 14.0)
		if f > 14:
			queue_free()
			return
	elif flash_t > 0.0:
		f = 6
	elif state == State.WINDUP:
		f = 2
	elif state == State.RECOVER:
		f = 7 if state_t > 0.3 else 8
	else:
		f = [0, 1, 2, 1][int(anim_t * 5.0) % 4]
	sprite.frame = f
	var swell := 1.15
	if state == State.WINDUP:
		swell += 0.35 * (1.0 - state_t / SPIT_WINDUP)
	sprite.scale = Vector2(swell, swell)
	sprite.position = Vector2(randf_range(-0.8, 0.8), 0) if state == State.WINDUP else Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


## Art pass: the spit animation's first two thirds are the swell (wind-up), the rest the spit.
func _process_spitter_art(delta: float) -> void:
	if dying_t >= 0.0 or flash_t > 0.0 or not (state in [State.WINDUP, State.RECOVER]):
		_process_art(delta)
		return
	var n := art.frames_of("attack")
	var i := 0
	if state == State.WINDUP:
		i = int((1.0 - state_t / SPIT_WINDUP) * float(n) * 0.66)
	else:
		i = int(float(n) * 0.66) + int((0.6 - clampf(state_t, 0.0, 0.6)) * 10.0)
		if i >= n:
			art.apply(sprite, "idle", art_row(), anim_t)
			sprite.position = Vector2.ZERO
			queue_redraw()
			overlay.queue_redraw()
			return
	art.apply_frame(sprite, "attack", art_row(), clampi(i, 0, n - 1))
	sprite.position = Vector2(randf_range(-0.8, 0.8), 0) if state == State.WINDUP else Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t < 0.0:
		draw_shadow(6.0)
		if state == State.WINDUP and aim.length() > 0.1:  # faint aim line along the ground
			var n := aim.normalized()
			var k := 1.0 - state_t / SPIT_WINDUP
			Telegraph.aim(self, n * 12.0, n, 6, 12.0, k)
