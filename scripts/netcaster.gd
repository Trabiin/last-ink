class_name Netcaster
extends Enemy
## Drowned Netter (issue #30, Chapter 4): a Trevail fisher who walked back out of the stopped sea still holding the
## net, and still fishing. What it catches now is people.
## Pattern: it hangs back at a net's throw (KEEP_MIN to KEEP_MAX) and circles. Every few seconds it stops and whirls
## the net over its head (WHIRL_TIME; the tell: a warning sign and a round danger zone on the ground where the net
## will land, following its target for the first part of the whirl and then fixed). The net comes down on that circle:
## whoever is still inside is caught (NET_TIME at NET_SLOW of their speed) and nicked. Then it has to haul the net
## back in (HAUL_TIME), slow and open. A hit while it whirls tangles the throw. Up close it backs off.

const KEEP_MIN := 52.0
const KEEP_MAX := 104.0
const WHIRL_TIME := 0.95
const WHIRL_TRACK := 0.55  # share of the whirl it still follows its target
const NET_R := 24.0
const NET_TIME := 1.8
const NET_SLOW := 0.15
const HAUL_TIME := 1.1
const CAST_EVERY := 3.4
const CAST_RANGE := 120.0
const ROPE := Color("c8b890")
const WET := Color("4a6a7a")

enum { S_WHIRL = 10, S_HAUL = 11 }

var damage := 5
var cast_cd := 1.4
var strafe := 1.0
var net_at := Vector2.ZERO
var net_mark: FloorMark = null
var noticed := false


func _ready() -> void:
	art_id = "netcaster"
	super._ready()
	cast_cd = 1.0 + randf_range(0.0, 1.5)
	strafe = 1.0 if randf() < 0.5 else -1.0


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192)
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	cast_cd -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO + 30.0)
	if target and not noticed:
		noticed = true
		EnemyKinds.notice(self)
	match state:
		S_WHIRL:
			if target and not target.dead and state_t > WHIRL_TIME * (1.0 - WHIRL_TRACK):
				net_at = net_at.move_toward(target.global_position, 140.0 * delta)
				if net_mark != null:
					net_mark.global_position = net_at
			facing = (net_at - global_position).normalized()
			if state_t <= 0.0:
				_throw()
		S_HAUL, State.RECOVER, State.STAGGER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		_:
			var tgt: Node2D = target
			if tgt == null and goal != null and is_instance_valid(goal):
				tgt = goal
			if tgt == null:
				if state_t <= 0.0:
					state_t = randf_range(0.8, 2.0)
					wander_dir = Vector2.ZERO if randf() < 0.35 else Vector2.RIGHT.rotated(randf() * TAU)
					if global_position.distance_to(home) > 90.0:
						wander_dir = (home - global_position).normalized()
				dir = wander_dir * 0.5
			else:
				var to := tgt.global_position - global_position
				var d := to.length()
				facing = to.normalized()
				if d < KEEP_MIN:
					dir = -facing
				elif d > KEEP_MAX:
					dir = facing
				else:
					dir = facing.orthogonal() * strafe * 0.6
					if randf() < delta * 0.4:
						strafe = -strafe
				if cast_cd <= 0.0 and d < CAST_RANGE and stun_left() <= 0.0:
					cast_cd = CAST_EVERY + randf_range(-0.4, 0.6)
					net_at = tgt.global_position
					_set_state(S_WHIRL, WHIRL_TIME)
					net_mark = FloorMark.put(self, _paint_net)
					net_mark.global_position = net_at
					Audio.sfx("cast", 0.75, -8.0, tr("A drowned netter whirls its net"))
	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)
	if state == S_WHIRL or state == S_HAUL:
		velocity = knockback
	_slide()
	queue_redraw()


## The net comes down: everyone inside is caught, slowed to a crawl and nicked.
func _throw() -> void:
	_end_net()
	Fx.ring(get_parent(), net_at, NET_R, ROPE)
	Audio.sfx("hit", 0.7, -4.0, tr("The net comes down"))
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead or h.global_position.distance_to(net_at) > NET_R + h.radius:
			continue
		catch(h)
	if goal != null and is_instance_valid(goal) and goal.global_position.distance_to(net_at) <= NET_R + 8.0:
		goal.nibble(damage)
	_set_state(S_HAUL, HAUL_TIME)


## Caught in the net: the hero wades at NET_SLOW of their speed for NET_TIME (Hero.mire_t), and takes a nick.
func catch(h: Hero) -> void:
	var gentle := 0.6 if Assists.gentle_blank() else 1.0
	h.mire_mult = minf(h.mire_mult, NET_SLOW) if h.mire_t > 0.0 else NET_SLOW
	h.mire_t = maxf(h.mire_t, NET_TIME * gentle)
	if h.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), net_at, 40.0):
		Status.struck(self, h)
	Fx.burst(get_parent(), h.global_position + Vector2(0, -8), [ROPE, WET], 8, 30.0)


func whirling() -> bool:
	return state == S_WHIRL and dying_t < 0.0


func hauling() -> bool:
	return state == S_HAUL and dying_t < 0.0


func lunge_damage() -> int:
	return damage


func _end_net() -> void:
	if net_mark != null and is_instance_valid(net_mark):
		net_mark.queue_free()
	net_mark = null


func _on_hit() -> void:
	if state == S_WHIRL:  # tangled: the throw is spoiled
		_end_net()
		cast_cd = maxf(cast_cd, 1.2)
		_set_state(State.STAGGER, 0.5)
		return
	_set_state(State.STAGGER, 0.35 if state != S_HAUL else maxf(state_t, 0.35))


func _on_death() -> void:
	_end_net()
	super._on_death()


func _exit_tree() -> void:
	_end_net()


func _paint_net(ci: CanvasItem) -> void:
	if state != S_WHIRL:
		return
	var k := clampf(1.0 - state_t / WHIRL_TIME, 0.0, 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
	Telegraph.circle(ci, Vector2.ZERO, NET_R, k)
	for i in 4:  # the mesh it will throw, criss-crossed
		var a := TAU * i / 8.0
		ci.draw_line(Vector2.RIGHT.rotated(a) * NET_R, Vector2.RIGHT.rotated(a + PI) * NET_R, Color(ROPE, 0.25 + 0.3 * k), 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if art == null or dying_t >= 0.0 or flash_t > 0.0 or not (state in [S_WHIRL, S_HAUL]):
		super._process(delta)
		return
	var row := Hero.dir_row(facing)
	if state == S_WHIRL:
		var n := art.frames_of("attack")
		art.apply_frame(sprite, "attack", row, int(anim_t * 10.0) % maxi(1, n / 2))  # the whirl: the first half of the throw, looped
	else:
		var n2 := art.frames_of("attack")
		art.apply_frame(sprite, "attack", row, n2 - 1)
	sprite.position = Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		return
	draw_shadow(5.0)
	if state == S_HAUL:  # the rope back to where the net fell
		var to := net_at - global_position
		var k := clampf(state_t / HAUL_TIME, 0.0, 1.0)
		draw_line(Vector2(0, -6), to * k, Color(ROPE, 0.8), 1.0)
	if art == null:
		draw_rect(Rect2(-5, -16, 10, 14), c(WET))


func _draw_overlay() -> void:
	super._draw_overlay()
	if dying_t >= 0.0:
		return
	if state == S_WHIRL:
		Telegraph.alert(overlay, Vector2(-2, -24), 10)
		var a := anim_t * 14.0  # the net going round over its head
		overlay.draw_arc(Vector2(0, -22), 8.0, a, a + 2.4, 8, ROPE, 1.5)
