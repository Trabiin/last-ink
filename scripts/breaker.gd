class_name Breaker
extends Enemy
## Breaker (issue #30, Chapter 4): one crest of the sea that stopped mid-wave at Trevail, walking up the beach on its
## own. Slow, heavy, and in no hurry.
## Pattern: it rolls towards its target. In reach, it rears up tall (REAR_TIME; the tell: a warning sign over it and
## a hatched lane on the sand as long and as wide as the wave it is about to be) and crashes down that lane: everyone
## in it is hit and thrown along it. The crash spends it: it lies at the far end as a flat puddle of sea for
## PUDDLE_TIME, slow to gather itself and taking PUDDLE_MULT damage, then stands back up. Hits while it rears do not
## stop it. Step out of the lane, then hit the puddle.

const REACH := 74.0  # how close it wants to be before it rears
const LANE_LEN := 92.0
const LANE_W := 22.0
const REAR_TIME := 0.95
const CRASH_TIME := 0.16
const PUDDLE_TIME := 1.7
const PUDDLE_MULT := 1.5
const REFORM_TIME := 0.45
const REAR_EVERY := 2.6
const SEA := Color("5a8aa0")
const FOAM := Color("e8f0f0")

enum { S_REAR = 10, S_CRASH = 11, S_PUDDLE = 12, S_REFORM = 13 }

var damage := 11
var rear_cd := 1.2
var lane_dir := Vector2.RIGHT
var lane_from := Vector2.ZERO
var noticed := false


func _ready() -> void:
	art_id = "breaker"
	super._ready()
	rear_cd = 0.8 + randf_range(0.0, 1.2)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192)
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	rear_cd -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO)
	if target and not noticed:
		noticed = true
		EnemyKinds.notice(self)
	match state:
		S_REAR:
			if target and not target.dead and state_t > REAR_TIME * 0.45:  # it settles its aim halfway up
				lane_dir = lane_dir.slerp((target.global_position - global_position).normalized(), minf(1.0, delta * 5.0)).normalized()
			lane_from = global_position
			facing = lane_dir
			if state_t <= 0.0:
				_crash()
			queue_redraw()
		S_CRASH:
			if state_t <= 0.0:
				_set_state(S_PUDDLE, PUDDLE_TIME)
			queue_redraw()
			return
		S_PUDDLE:
			if state_t <= 0.0:
				_set_state(S_REFORM, REFORM_TIME)
		S_REFORM:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		State.STAGGER, State.RECOVER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		_:
			var tgt: Node2D = target
			if tgt == null and goal != null and is_instance_valid(goal):
				tgt = goal
			if tgt == null:
				if state_t <= 0.0:
					state_t = randf_range(1.0, 2.2)
					wander_dir = Vector2.ZERO if randf() < 0.4 else Vector2.RIGHT.rotated(randf() * TAU)
					if global_position.distance_to(home) > 90.0:
						wander_dir = (home - global_position).normalized()
				dir = wander_dir * 0.5
			else:
				var to := tgt.global_position - global_position
				facing = to.normalized()
				if to.length() > REACH * 0.7:
					dir = facing
				if to.length() <= REACH and rear_cd <= 0.0 and stun_left() <= 0.0:
					rear_cd = REAR_EVERY + randf_range(-0.3, 0.5)
					lane_dir = facing
					lane_from = global_position
					_set_state(S_REAR, REAR_TIME)
					Audio.sfx("cast", 0.55, -6.0, tr("A breaker rears up"))
	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	if state != S_PUDDLE and state != S_REFORM:
		_slide()
	else:
		velocity = Vector2.ZERO
	queue_redraw()


## The wave comes down along the lane: everyone in it is hit and thrown along it, and the breaker spreads out at
## the far end as a puddle.
func _crash() -> void:
	lane_from = global_position
	var hit_goal := false
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead or not in_lane(h.global_position, h.radius):
			continue
		if h.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), h.global_position - lane_dir * 10.0, 260.0):
			Status.struck(self, h)
	if goal != null and is_instance_valid(goal) and in_lane(goal.global_position, 8.0):
		hit_goal = true
		goal.nibble(damage)
	var end := lane_from + lane_dir * LANE_LEN * 0.7
	var free := move_and_collide(end - global_position, true)  # test first: it stops at a wall
	global_position = end if free == null else global_position + (end - global_position) * 0.4
	Fx.burst(get_parent(), global_position, [FOAM, SEA, Color.WHITE], 18, 110.0)
	Fx.sweep(get_parent(), lane_from + Vector2(0, -4), lane_dir.angle(), deg_to_rad(12), LANE_LEN, FOAM)
	Audio.sfx("heavy", 0.6, -2.0, tr("The wave crashes down") if not hit_goal else tr("The wave crashes into the wardstone"))
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(2.5)
	hit_this_lunge.clear()
	_set_state(S_CRASH, CRASH_TIME)


## Is point p (with radius r) inside the lane it is rearing over / crashing down?
func in_lane(p: Vector2, r := 0.0) -> bool:
	var local := (p - lane_from).rotated(-lane_dir.angle())
	return local.x >= -r and local.x <= LANE_LEN + r and absf(local.y) <= LANE_W / 2.0 + r


func rearing() -> bool:
	return state == S_REAR and dying_t < 0.0


func puddled() -> bool:
	return state == S_PUDDLE and dying_t < 0.0


func lunge_damage() -> int:
	return damage


func _adjust_damage(amount: int) -> int:
	amount = super._adjust_damage(amount)
	return roundi(amount * PUDDLE_MULT) if state == S_PUDDLE else amount


func _on_hit() -> void:
	if state in [S_REAR, S_CRASH, S_PUDDLE, S_REFORM]:
		return  # a wave does not flinch, and a puddle has nothing to flinch with
	_set_state(State.STAGGER, 0.3)


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if art == null or dying_t >= 0.0 or not (state in [S_REAR, S_CRASH, S_PUDDLE, S_REFORM]):
		if sprite != null:
			sprite.scale = Vector2.ONE
		super._process(delta)
		return
	var row := Hero.dir_row(lane_dir)
	match state:
		S_REAR:
			var k := clampf(1.0 - state_t / REAR_TIME, 0.0, 1.0)
			art.apply_frame(sprite, "attack", row, 0 if k < 0.6 else mini(1, art.frames_of("attack") - 1))
			sprite.scale = Vector2(1.0 - 0.12 * k, 1.0 + 0.3 * k)  # drawing itself up tall
			sprite.position = Vector2(randf_range(-0.6, 0.6), 0)
		S_CRASH:
			var n := art.frames_of("attack")
			art.apply_frame(sprite, "attack", row, n - 1)
			sprite.scale = Vector2(1.25, 0.7)
			sprite.position = Vector2.ZERO
		S_PUDDLE:
			art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", row, 0)
			sprite.scale = Vector2(1.5, 0.35)  # spread flat on the sand
			sprite.position = Vector2(0, 2)
		S_REFORM:
			var k2 := clampf(1.0 - state_t / REFORM_TIME, 0.0, 1.0)
			art.apply_frame(sprite, "idle", row, 0)
			sprite.scale = Vector2(lerpf(1.5, 1.0, k2), lerpf(0.35, 1.0, k2))
			sprite.position = Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		return
	if state == S_PUDDLE or state == S_REFORM:
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 13.0, Color(SEA, 0.55))
		draw_arc(Vector2.ZERO, 13.0, 0, TAU, 24, Color(FOAM, 0.7), 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_shadow(7.0)
	if state == S_REAR:  # the lane it is about to crash down
		var k := clampf(1.0 - state_t / REAR_TIME, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, lane_dir.angle(), Vector2.ONE)
		Telegraph.rect(self, Rect2(0, -LANE_W / 2.0, LANE_LEN, LANE_W), k, k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if art == null:
		draw_rect(Rect2(-7, -18, 14, 16), c(SEA))
		draw_rect(Rect2(-7, -20, 14, 3), c(FOAM))


func _draw_overlay() -> void:
	super._draw_overlay()
	if dying_t >= 0.0:
		return
	if state == S_REAR:
		Telegraph.alert(overlay, Vector2(-2, -26), 10)
	elif state == S_PUDDLE:  # foam bubbles: it is open
		for i in 3:
			var a := anim_t * 4.0 + TAU * i / 3.0
			overlay.draw_circle(Vector2(cos(a) * 7.0, -4.0 + sin(a) * 1.5), 1.2, FOAM)
