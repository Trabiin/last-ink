class_name Copyist
extends Enemy
## Copyist (issue #28, Chapter 2): a scribe-monk of Saint Ledger's the Blank has half eaten, still copying.
## Pattern: keeps 80-140 px from its target. Every few seconds it kneels and raises its quill (the tell:
## it shakes, and a dotted line with a red wash marks a strip of floor through where the hero stands, a
## row or a column), then copies the strip out of the world: for a few seconds the floor there is blank
## paper and standing on it hurts (StruckLine, the Auditor's ink line, but a short strip). Hitting it
## while it kneels spoils the line. Up close it shuffles away, so the answer is to step off the strip and
## run it down.

const KEEP_MIN := 80.0
const KEEP_MAX := 140.0
const CAST_WINDUP := 0.9
const CAST_EVERY := 4.2
const LINE_LEN := 160.0
const LINE_W := 20.0
const LINE_WARN := 1.0
const LINE_LAST := 3.0

var damage := 4  # each tick of the copied-out strip
var cast_cd := 1.6
var strafe := 1.0
var noticed := false
var aim_at := Vector2.ZERO  # where the strip will be centred
var aim_horiz := true


func _ready() -> void:
	art_id = "copyist"
	super._ready()
	strafe = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	cast_cd -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO + 40.0)
	if target and not noticed:
		noticed = true
		EnemyKinds.notice(self)

	match state:
		State.WINDUP:
			if state_t <= 0.0:
				_copy_out()
				_set_state(State.RECOVER, 0.6)
		State.RECOVER, State.STAGGER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		_:
			if target == null:
				if goal != null and is_instance_valid(goal):
					var tg := goal.global_position - global_position
					dir = tg.normalized() if tg.length() > 40.0 else Vector2.ZERO
				else:
					if state_t <= 0.0:
						state_t = randf_range(1.0, 2.2)
						wander_dir = Vector2.ZERO if randf() < 0.5 else Vector2.RIGHT.rotated(randf() * TAU)
						if global_position.distance_to(home) > 80.0:
							wander_dir = (home - global_position).normalized()
					dir = wander_dir * 0.4
			else:
				var to := target.global_position - global_position
				var d := to.length()
				facing = to.normalized()
				if d < KEEP_MIN:
					dir = -facing
				elif d > KEEP_MAX:
					dir = facing
				else:
					dir = facing.orthogonal() * strafe * 0.4
					if randf() < delta * 0.3:
						strafe = -strafe
				if cast_cd <= 0.0 and d < KEEP_MAX + 40.0:
					cast_cd = CAST_EVERY + randf_range(-0.4, 0.6)
					aim_at = target.global_position
					aim_horiz = absf(to.x) > absf(to.y)  # the strip runs across the line between them
					aim_horiz = not aim_horiz if randf() < 0.3 else aim_horiz
					_set_state(State.WINDUP, CAST_WINDUP)

	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	move_and_slide()
	queue_redraw()


func _strip() -> Rect2:
	if aim_horiz:
		return Rect2(aim_at.x - LINE_LEN / 2.0, aim_at.y - LINE_W / 2.0, LINE_LEN, LINE_W)
	return Rect2(aim_at.x - LINE_W / 2.0, aim_at.y - LINE_LEN / 2.0, LINE_W, LINE_LEN)


func _copy_out() -> void:
	var l := StruckLine.new()
	l.rect = _strip()
	l.warn = LINE_WARN
	l.last = LINE_LAST
	l.damage = damage
	var scene := get_tree().current_scene
	var floor_node: Node = scene.get("area") if scene != null and scene.get("area") != null else get_parent()
	floor_node.add_child(l)
	Fx.burst(get_parent(), global_position + Vector2(0, -14), [Color.BLACK, Color("ebe7dc")], 8, 50.0)


func _on_hit() -> void:
	# A hit while it kneels spoils the line.
	_set_state(State.STAGGER, 0.4)
	cast_cd = maxf(cast_cd, 1.0)


func _process(delta: float) -> void:
	if art == null:
		super._process(delta)
		return
	if dying_t >= 0.0 or flash_t > 0.0 or state != State.WINDUP:
		_process_art(delta)
		return
	# Kneeling over the page: the cast animation when the final art has one, else a held idle frame, shaking.
	var k := clampf(1.0 - state_t / CAST_WINDUP, 0.0, 0.999)
	if art.has("cast"):
		art.apply_frame(sprite, "cast", art_row(), int(k * art.frames_of("cast")))
	else:
		art.apply_frame(sprite, "idle", art_row(), 0)
	sprite.position = Vector2(randf_range(-0.8, 0.8), 1.0)
	queue_redraw()
	overlay.queue_redraw()


## The wind-up tell drawn above the floor: the quill's aim, a faint line from the monk to the strip.
func _draw() -> void:
	if dying_t < 0.0:
		draw_shadow(6.0)
	if state == State.WINDUP and dying_t < 0.0:
		var k := clampf(1.0 - state_t / CAST_WINDUP, 0.0, 1.0)
		draw_line(Vector2(0, -14), aim_at - global_position, Color(0.08, 0.06, 0.1, 0.25 + 0.35 * k), 1.0)
		draw_circle(Vector2(0, -26), 2.0 + 2.0 * k, Color(0.92, 0.9, 0.84, 0.8))
