class_name Gannet
extends Enemy
## Half-Gannet (issue #30, Chapter 4): a seabird the Blank got half of, in flocks over Polgarrow. The half that is
## left still dives for fish. It no longer checks whether they are fish.
## Pattern: it circles high over its target (no hits land up there, nothing collides). Every few seconds it picks the
## spot where the hero stands and hangs over it (MARK_TIME; the tell: a round danger zone on the ground under its
## shadow), then folds and drops on that spot (DIVE_TIME), stabbing everything in DIVE_R. Its beak goes into the sand
## and it is stuck there for STUCK_TIME: on the ground, slow, open. Then it climbs again. Never stand under the mark;
## hit it while it is stuck.

const HIGH := 34.0  # how high it flies, in px above its shadow
const CIRCLE_R := 46.0
const CIRCLE_MIN := 1.8
const CIRCLE_MAX := 3.0
const MARK_TIME := 0.8
const DIVE_TIME := 0.2
const DIVE_R := 16.0
const STUCK_TIME := 1.5
const CLIMB_TIME := 0.45
const WHITE := Color("f0eee8")
const SLATE := Color("5a6470")

enum { S_CIRCLE = 10, S_MARK = 11, S_DIVE = 12, S_STUCK = 13, S_CLIMB = 14 }

var damage := 9
var dive_at := Vector2.ZERO
var dive_from := Vector2.ZERO
var dive_mark: FloorMark = null
var orbit := 0.0
var noticed := false
var base_layer := 4
var struck_goal := false


func _ready() -> void:
	art_id = "gannet"
	super._ready()
	base_layer = collision_layer
	orbit = randf() * TAU
	_take_off()


func airborne() -> bool:
	return state in [S_CIRCLE, S_MARK, S_DIVE, S_CLIMB] and dying_t < 0.0


func stuck() -> bool:
	return state == S_STUCK and dying_t < 0.0


func untargetable() -> bool:
	return airborne()


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if airborne():
		return false  # up in the wind: the blow goes through air
	return super.take_hit(amount, from, force)


func _take_off() -> void:
	collision_layer = 0
	_set_state(S_CIRCLE, randf_range(CIRCLE_MIN, CIRCLE_MAX))


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192)
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO + 40.0)
	if target and not noticed:
		noticed = true
		EnemyKinds.notice(self)
	var tgt: Node2D = target
	if tgt == null and goal != null and is_instance_valid(goal):
		tgt = goal
	match state:
		S_CIRCLE:
			var centre: Vector2 = tgt.global_position if tgt != null else home
			orbit += delta * 1.6
			var want := centre + Vector2(cos(orbit), sin(orbit) * 0.6) * CIRCLE_R
			global_position = global_position.move_toward(want, move_speed * 2.2 * delta)
			facing = Vector2(-sin(orbit), cos(orbit) * 0.6).normalized()
			if state_t <= 0.0 and tgt != null and stun_left() <= 0.0:
				dive_at = tgt.global_position
				struck_goal = false
				_set_state(S_MARK, MARK_TIME)
				dive_mark = FloorMark.put(self, _paint_mark)
				dive_mark.global_position = dive_at
				Audio.sfx("cast", 1.3, -10.0, tr("A gannet folds its wings"))
			elif state_t <= 0.0:
				state_t = 0.6
		S_MARK:
			global_position = global_position.move_toward(dive_at, move_speed * 2.0 * delta)
			facing = (dive_at - global_position).normalized() if dive_at.distance_to(global_position) > 1.0 else Vector2.DOWN
			if state_t <= 0.0:
				dive_from = global_position
				_set_state(S_DIVE, DIVE_TIME)
		S_DIVE:
			global_position = dive_from.lerp(dive_at, clampf(1.0 - state_t / DIVE_TIME, 0.0, 1.0))
			if state_t <= 0.0:
				_land()
		S_STUCK:
			if state_t <= 0.0:
				_set_state(S_CLIMB, CLIMB_TIME)
				collision_layer = 0
		S_CLIMB:
			if state_t <= 0.0:
				_take_off()
		State.STAGGER, State.RECOVER:
			if state_t <= 0.0:
				_set_state(S_CLIMB, CLIMB_TIME)
				collision_layer = 0
		_:
			_take_off()
	velocity = knockback if state == S_STUCK else Vector2.ZERO
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	if state == S_STUCK:
		_slide()
	queue_redraw()


## Beak first into the sand: everyone on the spot is stabbed, and it is stuck there.
func _land() -> void:
	_end_mark()
	global_position = dive_at
	collision_layer = base_layer
	Fx.burst(get_parent(), global_position, [Color("d8c8a0"), WHITE, SLATE], 12, 70.0)
	Audio.sfx("hit", 0.9, -4.0, tr("The gannet hits the sand"))
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead or h.global_position.distance_to(global_position) > DIVE_R + h.radius:
			continue
		if h.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), global_position, 170.0):
			Status.struck(self, h)
	if goal != null and is_instance_valid(goal) and not struck_goal and goal.global_position.distance_to(global_position) < DIVE_R + 10.0:
		struck_goal = true
		goal.nibble(damage)
	_set_state(S_STUCK, STUCK_TIME)


func lunge_damage() -> int:
	return damage


func _end_mark() -> void:
	if dive_mark != null and is_instance_valid(dive_mark):
		dive_mark.queue_free()
	dive_mark = null


func _on_hit() -> void:
	if state == S_STUCK:
		state_t = maxf(state_t, 0.35)  # a blow keeps its beak in the sand a moment longer
		return
	_set_state(State.STAGGER, 0.3)


func _on_death() -> void:
	_end_mark()
	super._on_death()


func _exit_tree() -> void:
	_end_mark()


func _paint_mark(ci: CanvasItem) -> void:
	if state != S_MARK and state != S_DIVE:
		return
	var k := clampf(1.0 - state_t / MARK_TIME, 0.0, 1.0) if state == S_MARK else 1.0
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	Telegraph.circle(ci, Vector2.ZERO, DIVE_R, k)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## How high above its shadow the bird is drawn right now.
func height() -> float:
	match state:
		S_CIRCLE, S_MARK:
			return HIGH
		S_DIVE:
			return HIGH * clampf(state_t / DIVE_TIME, 0.0, 1.0)
		S_CLIMB:
			return HIGH * clampf(1.0 - state_t / CLIMB_TIME, 0.0, 1.0)
	return 0.0


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	var up := height()
	if overlay != null:
		overlay.position = Vector2(0, -up)  # the HP bar and the tells ride with the bird
	if art == null or dying_t >= 0.0:
		super._process(delta)
		if sprite != null and dying_t < 0.0:
			sprite.position.y = -up
		return
	var row := Hero.dir_row(facing)
	match state:
		S_STUCK:
			art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", Hero.dir_row(Vector2.DOWN), 0)
			sprite.rotation = 0.0
			sprite.position = Vector2(sin(anim_t * 24.0) * 0.6, 2.0)  # tugging at its beak
		S_DIVE, S_MARK:
			art.apply_frame(sprite, "attack", row, 0 if state == S_MARK else mini(1, art.frames_of("attack") - 1))
			sprite.position = Vector2(0, -up)
		_:
			if flash_t > 0.0 and art.has("hurt"):
				art.apply(sprite, "hurt", row, 0.12 - flash_t)
			else:
				art.apply(sprite, "walk" if art.has("walk") else "idle", row, anim_t)
			sprite.position = Vector2(0, -up)
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		return
	var up := height()
	draw_shadow(lerpf(5.0, 3.0, up / HIGH))  # the shadow on the sand shows where it is
	if art == null:
		draw_rect(Rect2(-6, -8 - up, 12, 5), c(WHITE))
		draw_rect(Rect2(-1, -6 - up, 6, 2), c(SLATE))


func _draw_overlay() -> void:
	if dying_t >= 0.0:
		return
	super._draw_overlay()
	if state == S_MARK:
		Telegraph.alert(overlay, Vector2(-2, -16), 10)
	elif state == S_STUCK:
		for i in 3:
			var a := anim_t * 5.0 + TAU * i / 3.0
			overlay.draw_circle(Vector2(cos(a) * 6.0, -18.0 + sin(a) * 2.0), 1.2, WHITE)
