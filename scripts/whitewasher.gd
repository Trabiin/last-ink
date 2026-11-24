class_name Whitewasher
extends Spitter
## Eraser Whitewasher (issues #28, #206): an Eraser with a bucket of lime and the Blank stirred in.
## Pattern: hangs back and flings globs like a Spitter. Every few seconds, when a hero is in range, it dips
## its brush instead (PAINT_WINDUP; the tell: a warning sign over its head, and the stripe's hatched zone on
## the ground where the paint will go) and slaps a stripe of whitewash across the way between them, a
## little in front of the hero (scripts/white_stripe.gd): walking through it slows and Erases. A hit while
## it dips knocks the brush away and nothing is painted. Up close it still panics and backs off.

const PAINT_EVERY := 6.5
const PAINT_FIRST := 3.0
const PAINT_WINDUP := 0.9
const PAINT_MIN := 34.0
const PAINT_MAX := 135.0
const STRIPE_LEN := 64.0
const STRIPE_W := 14.0
const STRIPE_LAST := 6.0
const STRIPE_AHEAD := 28.0  # how far in front of the hero (towards the Whitewasher) the stripe lands
const StripeScript := preload("res://scripts/white_stripe.gd")

## Extra state past Enemy.State.
enum { S_PAINT = 10 }

var paint_cd := PAINT_FIRST
var stripe: WhiteStripe = null


func _ready() -> void:
	super._ready()
	paint_cd = PAINT_FIRST + randf_range(0.0, 1.5)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	var pd := delta * Assists.pace()
	if state == S_PAINT:
		anim_t += pd
		flash_t = maxf(flash_t - pd, 0.0)
		taunt_t = maxf(taunt_t - pd, 0.0)
		state_t -= pd
		velocity = knockback
		knockback = knockback.move_toward(Vector2.ZERO, 700.0 * pd)
		_slide()
		if state_t <= 0.0:
			stripe = null  # it's down: the stripe looks after itself now
			_set_state(State.RECOVER, 0.6)
		queue_redraw()
		return
	paint_cd -= pd
	if paint_cd <= 0.0 and not state in [State.WINDUP, State.RECOVER, State.STAGGER] and target != null and not target.dead and stun_left() <= 0.0:
		var to := target.global_position - global_position
		if to.length() >= PAINT_MIN and to.length() <= PAINT_MAX:
			_start_paint(to)
			return
	super._physics_process(delta)


func _start_paint(to: Vector2) -> void:
	paint_cd = PAINT_EVERY + randf_range(-0.5, 1.0)
	facing = to.normalized()
	_set_state(S_PAINT, PAINT_WINDUP)
	if state != S_PAINT:
		return
	var s: WhiteStripe = StripeScript.new()
	s.length = STRIPE_LEN
	s.width = STRIPE_W
	s.warn = PAINT_WINDUP
	s.last = STRIPE_LAST
	s.erase_time = float(EnemyKinds.kind(Journal.kind_of(self)).get("inflict", {}).get("time", 3.0))
	var scene := get_tree().current_scene
	var floor_node: Node = scene.get("area") if scene != null and scene.get("area") != null else get_parent()
	floor_node.add_child(s)
	# Across the way in, a little in front of the hero (on top of them when they are close: step off).
	s.global_position = target.global_position - facing * minf(STRIPE_AHEAD, to.length() * 0.4)
	s.global_rotation = facing.orthogonal().angle()
	stripe = s
	Audio.sfx("burst", 0.7, -8.0, tr("A brush slaps whitewash down"))


func _set_state(s: int, t: float) -> void:
	var was := state
	super._set_state(s, t)
	if was == S_PAINT and state == State.STAGGER and stripe != null and is_instance_valid(stripe):
		stripe.cancel()  # knocked or stunned mid-dip: the brush never reaches the ground
		stripe = null


func _on_hit() -> void:
	if state == S_PAINT:
		paint_cd = maxf(paint_cd, 3.0)
		_set_state(State.STAGGER, 0.5)
		return
	super._on_hit()


func _on_death() -> void:
	if stripe != null and is_instance_valid(stripe):
		stripe.cancel()
	stripe = null
	super._on_death()


func _process(delta: float) -> void:
	if art == null or dying_t >= 0.0 or flash_t > 0.0 or state != S_PAINT:
		super._process(delta)
		return
	# Dipping the brush: a "paint" animation when the final art has one, else the start of the fling.
	var k := clampf(1.0 - state_t / PAINT_WINDUP, 0.0, 0.999)
	if art.has("paint"):
		art.apply_frame(sprite, "paint", art_row(), int(k * art.frames_of("paint")))
	else:
		art.apply_frame(sprite, "attack", art_row(), int(k * art.frames_of("attack") * 0.5))
	sprite.position = Vector2(randf_range(-0.6, 0.6), 0.5)
	queue_redraw()
	overlay.queue_redraw()


func _draw_overlay() -> void:
	super._draw_overlay()
	if dying_t < 0.0 and state == S_PAINT:
		Telegraph.alert(overlay, Vector2(-2, -14), 10)
