class_name SaltWight
extends Enemy
## Salt Wight (issue #30, Chapter 4): someone who drowned off Halfwave Bay before the sea stopped, dried where they
## stood on the sea bed and walked ashore crusted white. Slow, stubborn, and very hard to keep down.
## Pattern: it shuffles in and lunges like a Nibbler, a heavy swing with a clear wind-up. The trick is its first death:
## it does not die, it crumbles into a heap of salt (the tell: a glittering mound with a ring round it that fills as it
## gathers itself). Break the heap with any hit before the ring closes (HEAP_TIME) and it is gone; leave it, and it
## stands back up at REFORM_SHARE of its health. It only gets the one heap. Ilse's White Ink unwrites it outright,
## heap or no heap.

const HEAP_TIME := 3.2
const REFORM_SHARE := 0.5
const SALT := Color("ece8dc")
const CRUST := Color("b8b0a0")

enum { S_HEAP = 10, S_RISE = 11 }

var damage := 9
var reformed := false
var crumbling := false
static var _told_heap := false  # the heap's HUD tip, once a session (like EnemyKinds.notice)


func _ready() -> void:
	art_id = "saltwight"
	super._ready()


func heaped() -> bool:
	return state == S_HEAP and not dead


## Allies break a heap first (scripts/ally_ai.gd reads this): it is about to stand up again.
func priority() -> int:
	return 1 if heaped() else 0


func lunge_damage() -> int:
	return damage


## A blow that would put it down the first time leaves it on 1 HP, and take_hit turns it into a heap.
func _adjust_damage(amount: int) -> int:
	amount = super._adjust_damage(amount)
	if not reformed and not erasing and state != S_HEAP and amount >= hp and hp > 1:
		crumbling = true
		return hp - 1
	return amount


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if dead:
		return false
	if state == S_HEAP:
		if amount <= 0:
			return false
		_shatter(from)
		return true
	var hit := super.take_hit(amount, from, force)
	if crumbling:
		crumbling = false
		_crumble()
	return hit


func _crumble() -> void:
	velocity = Vector2.ZERO
	knockback = Vector2.ZERO
	stun_until = 0
	_set_state(S_HEAP, HEAP_TIME)
	sprite.visible = art == null
	Fx.burst(get_parent(), global_position + Vector2(0, -6), [SALT, CRUST, Color.WHITE], 16, 60.0)
	Audio.sfx("burst", 0.6, -6.0, tr("A salt wight crumbles into a heap"))
	if not _told_heap:
		_told_heap = true
		var scene := get_tree().current_scene
		if scene != null and scene.get("hud") != null:
			scene.hud.say(tr("It crumbled into salt, but it is gathering itself. Hit the heap before the ring closes."), 3.5)


func _shatter(from: Vector2) -> void:
	reformed = true  # no second heap
	Fx.burst(get_parent(), global_position + Vector2(0, -4), [SALT, CRUST], 20, 90.0)
	Fx.damage_number(get_parent(), global_position + Vector2(0, -16), tr("broken"), Color.WHITE)
	knockback = (global_position - from).normalized() * 40.0 if global_position.distance_to(from) > 0.1 else Vector2.ZERO
	hp = 0
	dead = true
	Audio.hit(false, true)
	_on_death()
	died.emit(self)


func _rise() -> void:
	reformed = true
	hp = maxi(1, roundi(max_hp * REFORM_SHARE))
	sprite.visible = true
	Fx.burst(get_parent(), global_position + Vector2(0, -10), [SALT, CRUST], 12, 50.0)
	Audio.sfx("cast", 0.5, -6.0, tr("The salt wight stands up again"))
	_set_state(S_RISE, 0.5)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	if state == S_HEAP or state == S_RISE:
		var d := delta * Assists.pace()  # enemy speed assist (issue #192): the heap gathers more slowly
		anim_t += d
		flash_t = maxf(flash_t - d, 0.0)
		state_t -= d
		velocity = Vector2.ZERO
		if state_t <= 0.0:
			if state == S_HEAP:
				_rise()
			else:
				_set_state(State.CHASE, 0.0)
		queue_redraw()
		overlay.queue_redraw()
		return
	super._physics_process(delta)


func _set_state(s: int, t: float) -> void:
	if state == S_HEAP and s != S_RISE and s != S_HEAP and state_t > 0.0 and not dead:
		return  # a stun or a stagger does not stand a heap up early
	super._set_state(s, t)


func _on_hit() -> void:
	if state == S_HEAP or state == S_RISE:
		return
	super._on_hit()


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if state == S_HEAP and dying_t < 0.0:
		queue_redraw()
		overlay.queue_redraw()
		return
	if state == S_RISE and art != null and dying_t < 0.0:
		var k := clampf(1.0 - state_t / 0.5, 0.0, 1.0)
		art.apply_frame(sprite, "idle", art_row(), 0)
		sprite.scale = Vector2(lerpf(1.4, 1.0, k), lerpf(0.3, 1.0, k))
		queue_redraw()
		overlay.queue_redraw()
		return
	if sprite != null:
		sprite.scale = Vector2.ONE
	super._process(delta)


func _draw() -> void:
	if dying_t >= 0.0:
		return
	if state != S_HEAP:
		draw_shadow(5.0)
		return
	# The heap: a mound of salt with a glitter on it, and the ring it gathers itself by.
	var k := clampf(1.0 - state_t / HEAP_TIME, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mound := PackedVector2Array([Vector2(-10, 1), Vector2(-6, -5), Vector2(-1, -8 - 2.0 * k), Vector2(5, -5), Vector2(10, 1)])
	draw_colored_polygon(mound, c(SALT))
	draw_polyline(mound, Color(CRUST, 0.9), 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(anim_t * (2.0 if Access.reduce_flashing else 8.0))
	for i in 3:
		draw_rect(Rect2(Vector2(rng.randf_range(-7, 6), rng.randf_range(-6, -1)), Vector2(1, 1)), Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_arc(Vector2.ZERO, 16.0, -PI / 2.0, -PI / 2.0 + TAU * k, 32, Color(Telegraph.INK, 0.7), 3.0)
	draw_arc(Vector2.ZERO, 16.0, -PI / 2.0, -PI / 2.0 + TAU * k, 32, Color(Telegraph.SIGN if Access.danger_patterns else Telegraph.EDGE, 0.9), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	if state == S_HEAP and dying_t < 0.0:
		if state_t < HEAP_TIME * 0.4:  # nearly up: the warning sign
			Telegraph.alert(overlay, Vector2(-2, -16), 10)
		return
	super._draw_overlay()
