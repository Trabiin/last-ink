class_name Enforcer
extends Enemy
## Tithe Enforcer (issue #16): a Concord heavy in iron and gilt, carrying a Ledger as a shield.
## Pattern: walks in slowly and does not flinch from single hits (it staggers every third).
## In reach, it raises the Ledger for 0.9 s while a red ring fills on the ground (the tell),
## then stamps it down: a big hit to everyone in the ring. Hits from the front are halved by
## the shield, so circle round him or have an ally pull him (Hold the Line works).

const SLAM_RANGE := 30.0
const SLAM_WINDUP := 0.9
const SLAM_R := 30.0
const SLAM_AHEAD := 14.0
const POISE := 3

var damage := 13
var poise := POISE
var noticed := false
var doll: Array[Sprite2D] = []

const LOOK := {"skin": Color("dcb08a"), "metal": Color("57525e"), "cloth": Color("c9a53a"), "boots": Color("221c24")}


func _ready() -> void:
	art_id = "enforcer"  # art pass sprite; falls back to the recoloured paper doll if the set is missing
	super._ready()
	radius = 7.0
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 6.0
	number_color = Color("ffe7a3")
	if art != null:
		return
	sprite.visible = false
	# Paper doll like the heroes: Puny body + soldier outfit, recolored Concord iron and gilt.
	for layer in [[Art.BODY, "body"], [Art.OUTFITS["soldier"], "soldier"]]:
		var s := Sprite2D.new()
		s.texture = layer[0]
		s.hframes = 24
		s.vframes = 8
		s.offset = Vector2(0, -7)
		s.scale = Vector2(1.15, 1.15)
		s.material = Art.recolor_material(layer[1], LOOK)
		add_child(s)
		doll.append(s)
	move_child(overlay, -1)


## Heavy: knocked back a little, and the Ledger soaks half of anything from the front.
func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	var to_from := from - global_position
	var front := to_from.length() > 0.1 and facing.dot(to_from.normalized()) > 0.35
	if front and not dead and invuln_t <= 0.0:
		amount = maxi(1, amount / 2)
		Fx.burst(get_parent(), global_position + facing * 7.0 + Vector2(0, -9), [Color("ffe7a3"), Color("c9a53a")], 5, 40.0)
	return super.take_hit(amount, from, force * (0.15 if front else 0.4))


func _on_hit() -> void:
	poise -= 1
	if poise <= 0:
		poise = POISE
		_set_state(State.STAGGER, 0.6)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192): timers run slower, _slide() moves slower
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	state_t -= delta
	taunt_t = maxf(taunt_t - delta, 0.0)
	var dir := Vector2.ZERO
	var tgt: Node2D = null
	if target == null or target.dead or target.global_position.distance_to(global_position) > LOSE:
		target = _find_target(AGGRO)
	if target:
		tgt = target
		if not noticed:
			noticed = true
			EnemyKinds.notice(self)
	elif goal != null and is_instance_valid(goal):
		tgt = goal

	match state:
		State.WINDUP:
			if state_t <= 0.0:
				_slam()
				_set_state(State.RECOVER, 1.0)
		State.RECOVER, State.STAGGER:
			if state_t <= 0.0:
				_set_state(State.CHASE, 0.0)
		_:
			if tgt == null:
				if state_t <= 0.0:
					state_t = randf_range(1.0, 2.4)
					wander_dir = Vector2.ZERO if randf() < 0.5 else Vector2.RIGHT.rotated(randf() * TAU)
					if global_position.distance_to(home) > 80.0:
						wander_dir = (home - global_position).normalized()
				dir = wander_dir * 0.5
			else:
				var to := tgt.global_position - global_position
				# Turns slowly: that is what lets you get behind him.
				facing = facing.slerp(to.normalized(), minf(1.0, delta * 2.2)).normalized()
				if to.length() > SLAM_RANGE - 6.0:
					dir = to.normalized()
				else:
					_set_state(State.WINDUP, SLAM_WINDUP)

	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	_slide()


func _slam() -> void:
	var at := global_position + facing * SLAM_AHEAD
	Fx.ring(get_parent(), at, SLAM_R, Color("ff6b6b"))
	Fx.burst(get_parent(), at, [Color("c9a53a"), Color("57525e"), Color.WHITE], 14, 90.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(3.0)
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero and not hero.dead and hero.global_position.distance_to(at) < SLAM_R + hero.radius:
			if hero.take_hit(Empire.damage_to_party(damage), at, 260.0):
				Status.struck(self, hero)  # the slam stuns (data/enemies.json, issue #112)
	if target == null and goal != null and is_instance_valid(goal) and goal.global_position.distance_to(at) < SLAM_R + 8.0:
		goal.nibble(damage)


func _on_death() -> void:
	Fx.burst(get_parent(), global_position + Vector2(0, -8), [Color("c9a53a"), Color("57525e"), Color("efe6cf")], 18, 90.0)
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0


func _process(delta: float) -> void:
	if art != null:
		_process_enforcer_art(delta)
		return
	var col := 0
	if dying_t >= 0.0:
		dying_t += delta
		col = 23
		modulate.a = maxf(1.0 - maxf(dying_t - 0.4, 0.0) * 3.0, 0.0)
		if dying_t > 0.8:
			queue_free()
			return
	elif flash_t > 0.0:
		col = 19
	elif state == State.WINDUP:
		col = 4  # Ledger raised
	elif state == State.RECOVER and state_t > 0.75:
		col = 6  # just stamped down
	elif state == State.STAGGER:
		col = 19
	elif velocity.length() > 5.0:
		col = int(anim_t * 6.0) % 4
	for s in doll:
		s.frame = Hero.dir_row(facing) * 24 + col
		s.position = Vector2(randf_range(-0.6, 0.6), 0) if state == State.WINDUP else Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


## The drawn Enforcer: the slam's 8 frames run over the wind-up (Ledger rising) and the stamp.
func _process_enforcer_art(delta: float) -> void:
	var row := art_row()
	sprite.position = Vector2.ZERO
	if dying_t >= 0.0:
		dying_t += delta
		var d := art.duration("death") if art.has("death") else 0.5
		if art.has("death"):
			art.apply(sprite, "death", row, dying_t)
		modulate.a = maxf(1.0 - maxf(dying_t - d, 0.0) * 3.0, 0.0)
		if dying_t > d + 0.35:
			queue_free()
			return
	elif flash_t > 0.0 or state == State.STAGGER:
		art.apply(sprite, "hurt", row, 0.6 - state_t if state == State.STAGGER else 0.12 - flash_t)
	elif state == State.WINDUP:
		var n := art.frames_of("attack")
		var k := 1.0 - state_t / SLAM_WINDUP
		art.apply_frame(sprite, "attack", row, clampi(int(k * (n - 2)), 0, n - 3))
		sprite.position = Vector2(randf_range(-0.6, 0.6), 0)
	elif state == State.RECOVER and state_t > 0.7:
		var n := art.frames_of("attack")
		art.apply_frame(sprite, "attack", row, n - 2 if state_t > 0.85 else n - 1)
	else:
		art.apply(sprite, "walk" if velocity.length() > 5.0 else "idle", row, anim_t)
	queue_redraw()
	overlay.queue_redraw()


## Facing drives the sprite, not movement: he turns slowly, and his back is the weak side.
func art_row() -> int:
	return Hero.dir_row(facing)


func _draw() -> void:
	if dying_t >= 0.0:
		return
	if state == State.WINDUP:  # the red ring fills in on the ground before the stamp
		var k := 1.0 - state_t / SLAM_WINDUP
		var at := facing * SLAM_AHEAD
		draw_set_transform(at, 0.0, Vector2(1.0, 0.55))
		Telegraph.circle(self, Vector2.ZERO, SLAM_R, k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_shadow(7.0)


func _draw_overlay() -> void:
	if dying_t >= 0.0:
		return
	var top := 10.0 if art != null else 0.0  # the drawn Enforcer stands taller than the paper doll
	if art == null:
		# The Ledger: a gilt-edged book held out in front (drawn in front when facing down/sideways).
		var p := facing * 7.0 + Vector2(0, -8)
		overlay.draw_rect(Rect2(p - Vector2(3, 4), Vector2(6, 8)), Color("3b2a1e"))
		overlay.draw_rect(Rect2(p - Vector2(3, 4), Vector2(6, 8)), Color("c9a53a"), false, 1.0)
	if taunt_t > 0.0:
		overlay.draw_rect(Rect2(-1.5, -26 - top, 3, 3), Color("f2a65a"))
	if state == State.WINDUP:
		Telegraph.alert(overlay, Vector2(-2, -22 - top), 10)
	if hp < max_hp:
		overlay.draw_rect(Rect2(-8, -24 - top, 16, 2), Color(0, 0, 0, 0.6))
		overlay.draw_rect(Rect2(-8, -24 - top, 16.0 * hp / max_hp, 2), Color("ffd166"))
