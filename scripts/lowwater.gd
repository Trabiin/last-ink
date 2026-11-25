class_name LowWater
extends Enemy
## Low Water (issue #30, Chapter 4 boss): the sea that pulled back from Halfwave Bay the night it stopped, gathered
## into one standing body at the bottom of the bay. It is everything the tide forgot to bring back in: wrecks, nets,
## the drowned, the shine on the water. It wants to come back in. It no longer remembers where the shore was.
##
## Its moves, all telegraphed:
##   Breaker  - it draws itself up and a long hatched lane opens towards its target; a wave rolls down the lane and
##              throws whoever is in it along it. Phase 2 sends two lanes in a V.
##   Spout    - it gathers brine and spits a fan of globs (scripts/ink_glob.gd) at its target; the aim lines show first.
##   Undertow - a dashed ring opens under its target; when it closes, the sand inside turns to a whirlpool for
##              POOL_TIME that drags whoever is in it to the middle and stings. Walk out of it.
##   Call     - it calls two Breakers up out of the sea bed (they are what it is made of).
## Phase 2 ("High Water", at half HP): a short untouchable beat as it rears up, then the Flood: it sinks into the sea
## bed (no hits land), the whole bay is hatched as water comes in, and two or three dry banks are marked. When the
## water lands, everyone not standing on a bank is hit hard. It comes back up at a marked spot near the party (a heavy
## hit to anyone close) and lies BEACHED for a moment: the window to hit it hardest. boss_fight.gd calls in Breakers
## in phase 2.
##
## Driven by boss_fight.gd like the Host: it wakes it, gives it the floor and the arena bounds, and watches
## phase_changed / dead.

signal phase_changed(phase: int)

enum Act { DORMANT, WALK, SWELL, ROLL, SPOUT, UNDERTOW, CALL, SINK, FLOOD, SURFACE, BEACHED, TRANSITION }

const MAX_HP := 1100
const PHASE2_AT := 0.5
const WALK_SPEED := 22.0
const SWELL_T := [1.15, 0.95]
const ROLL_T := 0.55
const LANE_LEN := 300.0
const LANE_W := 44.0
const V_SPREAD := 0.42  # radians either side for the phase 2 pair of lanes
const SPOUT_T := [0.8, 0.65]
const SPOUT_GLOBS := [4, 6]
const SPOUT_SPREAD := 0.7
const UNDERTOW_T := 1.1
const POOL_R := 52.0
const POOL_TIME := 2.6
const POOL_PULL := 46.0
const POOL_TICK := 0.5
const CALL_T := 0.9
const CALL_EVERY := 18.0
const CALLED_MAX := 2
const SINK_T := 0.7
const FLOOD_T := 2.6
const BANK_R := 30.0
const SURFACE_T := 0.85
const SURFACE_R := 44.0
const BEACHED_T := 2.2
const BEACHED_MULT := 1.3
const TRANSITION_T := 2.2
const SEA := Color("4a7a90")
const DEEP := Color("1e3a4a")
const FOAM := Color("e8f0ee")
const GlobScript := preload("res://scripts/ink_glob.gd")

var damage := 16  # the wave
var glob_damage := 7
var pool_damage := 3
var flood_damage := 22
var surface_damage := 16
var act: int = Act.DORMANT
var act_t := 0.0
var act_total := 1.0
var phase := 1
var aim_dir := Vector2.DOWN
var lanes: Array = []  # directions of the lanes being swelled / rolled
var lane_from := Vector2.ZERO
var rolled: Array = []  # heroes the current wave already hit
var call_t := 8.0
var since_flood := 0
var floor_node: Node
var arena := Rect2(0, 0, 576, 416)
var pool_at := Vector2.ZERO
var pool_t := 0.0
var pool_tick_t := 0.0
var pool_mark: FloorMark = null
var banks: Array = []  # dry spots during the Flood
var flood_mark: FloorMark = null
var surface_at := Vector2.ZERO
var surface_mark: FloorMark = null
var told_flood := false
var told_pool := false


func _ready() -> void:
	art_id = "lowwater"
	super._ready()
	number_color = Color("d0e8f0")
	boss = true  # no stuns, and it always knows where everyone is
	max_hp = MAX_HP
	hp = MAX_HP
	xp = 110
	radius = 13.0
	move_speed = WALK_SPEED
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 11.0


func wake() -> void:
	if act == Act.DORMANT:
		_go(Act.WALK, 0.8)


func _go(a: int, t: float) -> void:
	act = a
	act_t = t
	act_total = maxf(t, 0.01)


func ratio() -> float:
	return float(hp) / float(max_hp)


func submerged() -> bool:
	return act in [Act.SINK, Act.FLOOD, Act.SURFACE]


func untargetable() -> bool:
	return submerged()


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if act == Act.DORMANT or act == Act.TRANSITION or submerged():
		if not dead and flash_t <= 0.0 and not submerged():
			Fx.damage_number(get_parent(), global_position + Vector2(0, -56), tr("no effect"), Color(0.8, 0.8, 0.8))
			flash_t = 0.05
		return false
	if act == Act.BEACHED:
		amount = roundi(amount * BEACHED_MULT)  # stranded on the sand, all of it within reach
	var hit := super.take_hit(amount, from, force * 0.04)
	if hit and not dead and phase == 1 and ratio() <= PHASE2_AT:
		_start_phase2()
	return hit


func _on_hit() -> void:
	pass  # water does not flinch


func taunt(h: Hero, time: float) -> void:
	taunter = h
	taunt_t = time * 0.5


func _start_phase2() -> void:
	phase = 2
	_clear_marks()
	pool_t = 0.0
	_go(Act.TRANSITION, TRANSITION_T)
	Fx.ring(get_parent(), global_position + Vector2(0, -10), 90.0, FOAM)
	Fx.burst(get_parent(), global_position + Vector2(0, -36), [SEA, FOAM, DEEP], 30, 140.0)
	_shake(5.0)
	phase_changed.emit(2)


func _say(text: String) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.get("hud") != null:
		scene.hud.say(text, 3.5)


func _shake(n: float) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(n)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192): timers run slower, _slide() moves slower
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	taunt_t = maxf(taunt_t - delta, 0.0)
	act_t -= delta
	var dir := Vector2.ZERO
	if act != Act.DORMANT and (target == null or target.dead or taunt_t > 0.0):
		target = _find_target(2000.0)
	if act in [Act.WALK, Act.SPOUT, Act.SWELL, Act.ROLL]:
		call_t -= delta
	_update_pool(delta)
	match act:
		Act.DORMANT:
			pass
		Act.WALK:
			if target:
				var to := target.global_position - global_position
				facing = facing.slerp(to.normalized(), minf(1.0, delta * 3.0)).normalized()
				if to.length() > 90.0:
					dir = to.normalized()
			if act_t <= 0.0 and target:
				_choose()
		Act.SWELL:
			var k := 1.0 - act_t / act_total
			if k < 0.5 and target:  # it settles its aim halfway up
				aim_dir = aim_dir.slerp((target.global_position - global_position).normalized(), minf(1.0, delta * 6.0)).normalized()
				lanes = _lane_dirs()
			lane_from = global_position
			facing = aim_dir
			if act_t <= 0.0:
				rolled.clear()
				_go(Act.ROLL, ROLL_T)
				Audio.sfx("heavy", 0.5, -2.0, tr("A wave rolls down the bay"))
		Act.ROLL:
			_roll()
			if act_t <= 0.0:
				_go(Act.WALK, 0.8 if phase == 1 else 0.5)
		Act.SPOUT:
			if target and act_t > act_total * 0.4:
				aim_dir = aim_dir.slerp((target.global_position - global_position).normalized(), minf(1.0, delta * 6.0)).normalized()
			facing = aim_dir
			if act_t <= 0.0:
				_spout()
				_go(Act.WALK, 0.7 if phase == 1 else 0.45)
		Act.UNDERTOW:
			if act_t <= 0.0:
				_open_pool()
				_go(Act.WALK, 0.5)
		Act.CALL:
			if act_t <= 0.0:
				_call_breakers()
				call_t = CALL_EVERY
				_go(Act.WALK, 0.6)
		Act.SINK:
			if act_t <= 0.0:
				_begin_flood()
		Act.FLOOD:
			if act_t <= 0.0:
				_flood_lands()
		Act.SURFACE:
			if act_t <= 0.0:
				_surface()
		Act.BEACHED:
			if act_t <= 0.0:
				_go(Act.WALK, 0.4)
		Act.TRANSITION:
			if act_t <= 0.0:
				since_flood = 9  # opens phase 2 with the Flood
				_go(Act.WALK, 0.3)
	velocity = dir * move_speed * (1.2 if phase == 2 else 1.0) + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	if not submerged() and act != Act.BEACHED:
		_slide()
	queue_redraw()


func _choose() -> void:
	var dist := target.global_position.distance_to(global_position)
	since_flood += 1
	if phase == 2 and since_flood >= 4:
		since_flood = 0
		_go(Act.SINK, SINK_T)
		Audio.sfx("cast", 0.4, -2.0, tr("Low Water sinks into the sea bed"))
		return
	if call_t <= 0.0 and _called().size() < CALLED_MAX:
		_go(Act.CALL, CALL_T)
		Audio.sfx("alert", 0.5, -4.0, tr("Low Water calls the sea up"))
	elif pool_t <= 0.0 and randf() < 0.35:
		pool_at = target.global_position
		_go(Act.UNDERTOW, UNDERTOW_T)
		pool_mark = FloorMark.put(self, _paint_pool)
		pool_mark.global_position = pool_at
		Audio.sfx("cast", 0.6, -6.0, tr("The sand starts to turn"))
	elif dist > 60.0 and randf() < 0.55:
		aim_dir = (target.global_position - global_position).normalized()
		lanes = _lane_dirs()
		_go(Act.SWELL, SWELL_T[phase - 1])
		Audio.sfx("cast", 0.45, -4.0, tr("Low Water draws itself up"))
	else:
		aim_dir = (target.global_position - global_position).normalized()
		_go(Act.SPOUT, SPOUT_T[phase - 1])


func _lane_dirs() -> Array:
	if phase == 1:
		return [aim_dir]
	return [aim_dir.rotated(-V_SPREAD), aim_dir.rotated(V_SPREAD)]


## Is p (radius r) in the lane along d from lane_from? Returns how far along it is, or -1 outside.
func lane_pos(d: Vector2, p: Vector2, r := 0.0) -> float:
	var local := (p - lane_from).rotated(-d.angle())
	if local.x < -r or local.x > LANE_LEN + r or absf(local.y) > LANE_W / 2.0 + r:
		return -1.0
	return local.x


## The wave's crest runs down each lane over ROLL_T; whoever it reaches is hit once and thrown along it.
func _roll() -> void:
	var front := LANE_LEN * clampf(1.0 - act_t / act_total, 0.0, 1.0)
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead or rolled.has(h):
			continue
		for d in lanes:
			var along := lane_pos(d, h.global_position, h.radius)
			if along >= 0.0 and along <= front:
				rolled.append(h)
				h.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), h.global_position - (d as Vector2) * 12.0, 300.0)
				break


func _spout() -> void:
	var n: int = SPOUT_GLOBS[phase - 1]
	for i in n:
		var g: InkGlob = GlobScript.new()
		var a := -SPOUT_SPREAD + SPOUT_SPREAD * 2.0 * float(i) / float(maxi(n - 1, 1))
		g.dir = aim_dir.rotated(a)
		g.speed = 120.0 if phase == 1 else 140.0
		g.damage = roundi(glob_damage * hit_mult())
		g.range_left = 260.0
		g.kind = "lowwater"
		g.position = global_position + Vector2(0, -20)
		get_parent().add_child(g)
	Audio.sfx("burst", 0.6, -4.0, tr("Low Water spits brine"))


## The whirlpool opens where the ring was.
func _open_pool() -> void:
	pool_t = POOL_TIME
	pool_tick_t = POOL_TICK
	Fx.ring(get_parent(), pool_at, POOL_R, FOAM)
	if not told_pool:
		told_pool = true
		_say(tr("The sand is a whirlpool! Walk out of the ring before it drags you to the middle."))


func _update_pool(delta: float) -> void:
	if pool_t <= 0.0:
		return
	pool_t -= delta
	pool_tick_t -= delta
	var tick := pool_tick_t <= 0.0
	if tick:
		pool_tick_t = POOL_TICK
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead:
			continue
		var to := pool_at - h.global_position
		var d := to.length()
		if d > POOL_R:
			continue
		if d > 3.0:
			h.global_position += to.normalized() * POOL_PULL * delta * (0.6 if Assists.gentle_blank() else 1.0)
		if tick:
			h.take_hit(Empire.damage_to_party(roundi(pool_damage * hit_mult())), pool_at, 0.0)
	if pool_t <= 0.0:
		_end_mark("pool")


func _called() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e != self and not e.dead:
			out.append(e)
	return out


func _call_breakers() -> void:
	var scene := get_tree().current_scene
	var mission: Dictionary = scene.get("mission") if scene != null and scene.get("mission") is Dictionary else {}
	for side in [-1.0, 1.0]:
		var p := Vector2(arena.get_center().x + side * arena.size.x * 0.36, arena.position.y + arena.size.y * 0.5)
		for e in EnemyKinds.spawn(get_parent(), p, mission, "breaker"):
			Fx.burst(get_parent(), e.global_position + Vector2(0, -8), [SEA, FOAM], 10, 60.0)
			if scene != null and scene.has_method("_on_enemy_died"):
				e.died.connect(scene._on_enemy_died)


## Phase 2: it is under the sea bed, the water is coming in, and a few banks stay dry.
func _begin_flood() -> void:
	banks.clear()
	var heroes := get_tree().get_nodes_in_group("heroes").filter(func(n): return n is Hero and not (n as Hero).dead)
	var want := 3 if heroes.size() > 2 else 2
	var tries := 0
	while banks.size() < want and tries < 40:
		tries += 1
		var p := Vector2(randf_range(arena.position.x + 50, arena.end.x - 50), randf_range(arena.position.y + 70, arena.end.y - 40))
		var ok := true
		for b in banks:
			if (b as Vector2).distance_to(p) < BANK_R * 4.0:
				ok = false
		if ok:
			banks.append(p)
	_go(Act.FLOOD, FLOOD_T)
	flood_mark = FloorMark.put(self, _paint_flood)
	flood_mark.global_position = Vector2.ZERO
	if not told_flood:
		told_flood = true
		_say(tr("The tide is coming back in! Get onto one of the dry banks before it lands."))
	Audio.sfx("alert", 0.4, -2.0, tr("The tide comes in"))


func _flood_lands() -> void:
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead or on_bank(h.global_position):
			continue
		h.take_hit(Empire.damage_to_party(roundi(flood_damage * hit_mult())), h.global_position + Vector2(0, -20), 120.0)
	Fx.burst(get_parent(), arena.get_center(), [SEA, FOAM, DEEP], 40, 200.0)
	_shake(5.0)
	_end_mark("flood")
	# Up again next to whoever it wants, at a marked spot.
	var tp: Vector2 = target.global_position if target and not target.dead else arena.get_center()
	var off := Vector2.RIGHT.rotated(randf() * TAU) * 40.0
	surface_at = Vector2(clampf(tp.x + off.x, arena.position.x + 30, arena.end.x - 30), clampf(tp.y + off.y, arena.position.y + 50, arena.end.y - 24))
	surface_mark = FloorMark.put(self, _paint_surface)
	surface_mark.global_position = surface_at
	_go(Act.SURFACE, SURFACE_T)


func on_bank(p: Vector2) -> bool:
	for b in banks:
		if (b as Vector2).distance_to(p) <= BANK_R:
			return true
	return false


func _surface() -> void:
	_end_mark("surface")
	global_position = surface_at
	Fx.ring(get_parent(), global_position, SURFACE_R, FOAM)
	Fx.burst(get_parent(), global_position + Vector2(0, -10), [SEA, FOAM, DEEP], 26, 140.0)
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h and not h.dead and h.global_position.distance_to(global_position) < SURFACE_R + h.radius:
			h.take_hit(Empire.damage_to_party(roundi(surface_damage * hit_mult())), global_position, 280.0)
	_shake(4.0)
	Audio.sfx("heavy", 0.5, -2.0, tr("Low Water bursts up out of the sand"))
	_go(Act.BEACHED, BEACHED_T)


func beached() -> bool:
	return act == Act.BEACHED


func flooding() -> bool:
	return act == Act.FLOOD


func pool_open() -> bool:
	return pool_t > 0.0


func _end_mark(which: String) -> void:
	var m: FloorMark = {"pool": pool_mark, "flood": flood_mark, "surface": surface_mark}[which]
	if m != null and is_instance_valid(m):
		m.queue_free()
	match which:
		"pool":
			pool_mark = null
		"flood":
			flood_mark = null
		"surface":
			surface_mark = null


func _clear_marks() -> void:
	for w in ["pool", "flood", "surface"]:
		_end_mark(w)


func _on_death() -> void:
	_clear_marks()
	pool_t = 0.0
	super._on_death()
	for e in _called():  # the sea goes out with it
		(e as Enemy).take_hit(9999, global_position, 0.0)
	_shake(6.0)


func _exit_tree() -> void:
	_clear_marks()


# ---------------------------------------------------------------- painting on the floor

func _paint_pool(ci: CanvasItem) -> void:
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
	if act == Act.UNDERTOW:
		var k := clampf(1.0 - act_t / act_total, 0.0, 1.0)
		Telegraph.circle(ci, Vector2.ZERO, POOL_R, k)
	elif pool_t > 0.0:
		ci.draw_circle(Vector2.ZERO, POOL_R, Color(DEEP, 0.35))
		for i in 3:  # the turning water
			var a := anim_t * 3.0 + TAU * i / 3.0
			ci.draw_arc(Vector2.ZERO, POOL_R * (0.35 + 0.2 * i), a, a + 2.2, 16, Color(FOAM, 0.55), 1.5)
		Telegraph.circle(ci, Vector2.ZERO, POOL_R, 0.4)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_flood(ci: CanvasItem) -> void:
	if act != Act.FLOOD:
		return
	var k := clampf(1.0 - act_t / act_total, 0.0, 1.0)
	Telegraph.rect(ci, arena, k, k * 0.6, arena)
	for b in banks:  # the dry banks: sand-coloured, ringed, safe
		var p: Vector2 = b
		ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.6))
		ci.draw_circle(Vector2.ZERO, BANK_R, Color("d8c8a0"))
		ci.draw_arc(Vector2.ZERO, BANK_R, 0, TAU, 32, Color(Telegraph.INK, 0.8), 3.0)
		ci.draw_arc(Vector2.ZERO, BANK_R, 0, TAU, 32, Color("fff1b8"), 1.5)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_surface(ci: CanvasItem) -> void:
	if act != Act.SURFACE:
		return
	var k := clampf(1.0 - act_t / act_total, 0.0, 1.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	ci.draw_circle(Vector2.ZERO, SURFACE_R * (0.3 + 0.7 * k), Color(DEEP, 0.35))
	Telegraph.circle(ci, Vector2.ZERO, SURFACE_R, k)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if art == null:
		if dying_t >= 0.0:
			dying_t += delta
			modulate.a = clampf(1.0 - dying_t, 0.0, 1.0)
			if dying_t > 1.0:
				queue_free()
		queue_redraw()
		return
	var row := Hero.dir_row(aim_dir if act in [Act.SWELL, Act.ROLL, Act.SPOUT] else facing)
	sprite.position = Vector2.ZERO
	sprite.visible = not (act in [Act.FLOOD, Act.SURFACE]) and not (act == Act.SINK and act_t < act_total * 0.3)
	if dying_t >= 0.0:
		dying_t += delta
		var long := 2.4
		if art.has("death"):
			art.apply(sprite, "death", Hero.dir_row(Vector2.DOWN), dying_t)
		else:
			art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", row, 1)
			sprite.scale = Vector2(1.0 + 0.6 * dying_t / long, maxf(1.0 - dying_t / long, 0.05))  # running out flat
		modulate.a = clampf(1.0 - maxf(dying_t - long * 0.6, 0.0) / (long * 0.4), 0.0, 1.0)
		if dying_t > long:
			queue_free()
		return
	var k := clampf(1.0 - act_t / act_total, 0.0, 0.999)
	sprite.scale = Vector2.ONE
	if flash_t > 0.0 and art.has("hurt") and act != Act.TRANSITION:
		art.apply(sprite, "hurt", row, 0.12 - flash_t)
	else:
		match act:
			Act.SWELL:
				art.apply_frame(sprite, "attack", row, 0)
				sprite.scale = Vector2(1.0 - 0.1 * k, 1.0 + 0.25 * k)
				sprite.position = Vector2(randf_range(-0.6, 0.6), 0)
			Act.ROLL, Act.SPOUT:
				var n := art.frames_of("attack")
				art.apply_frame(sprite, "attack", row, int(k * float(n)))
			Act.UNDERTOW, Act.CALL, Act.TRANSITION:
				var key := "phase" if art.has("phase") else "idle"
				art.apply_frame(sprite, key, Hero.dir_row(Vector2.DOWN), int(k * float(art.frames_of(key))))
				sprite.position = Vector2(randf_range(-0.8, 0.8), 0)
			Act.SINK:
				art.apply_frame(sprite, "idle", row, 0)
				sprite.scale = Vector2(1.0 + 0.3 * k, maxf(1.0 - k, 0.05))
			Act.BEACHED:
				art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", row, 0)
				sprite.scale = Vector2(1.25, 0.75)
				sprite.position = Vector2(sin(anim_t * 20.0) * 0.8, 2.0)
			_:
				art.apply(sprite, "walk" if velocity.length() > 5.0 else "idle", row, anim_t)
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		draw_shadow(12.0 * modulate.a)
		return
	if act == Act.FLOOD or act == Act.SURFACE:
		return  # under the sea bed: only the marks show
	if act == Act.SWELL or act == Act.ROLL:  # the lanes the wave will take
		var k := clampf(1.0 - act_t / act_total, 0.0, 1.0)
		var from := lane_from - global_position
		for d in lanes:
			draw_set_transform(from, (d as Vector2).angle(), Vector2.ONE)
			if act == Act.SWELL:
				Telegraph.rect(self, Rect2(0, -LANE_W / 2.0, LANE_LEN, LANE_W), k, k)
			else:
				var front := LANE_LEN * k
				draw_rect(Rect2(0, -LANE_W / 2.0, front, LANE_W), Color(SEA, 0.35))
				draw_rect(Rect2(front - 6.0, -LANE_W / 2.0, 6.0, LANE_W), Color(FOAM, 0.85))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif act == Act.SPOUT:  # where the brine will fly
		var k2 := 1.0 - act_t / act_total
		var n: int = SPOUT_GLOBS[phase - 1]
		for i in n:
			var a := -SPOUT_SPREAD + SPOUT_SPREAD * 2.0 * float(i) / float(maxi(n - 1, 1))
			var d2 := aim_dir.rotated(a)
			Telegraph.aim(self, d2 * 16.0, d2, 4, 12.0, k2)
	draw_shadow(13.0)
	if art == null:
		draw_rect(Rect2(-13, -44, 26, 42), c(SEA))
		draw_rect(Rect2(-13, -46, 26, 4), c(FOAM))


func _draw_overlay() -> void:
	if dying_t >= 0.0 or act == Act.FLOOD or act == Act.SURFACE:
		return
	if act in [Act.SWELL, Act.SPOUT, Act.UNDERTOW, Act.CALL, Act.SINK, Act.TRANSITION]:
		Telegraph.alert(overlay, Vector2(-3, -70), 12)
	if act == Act.BEACHED:
		for i in 3:
			var a := anim_t * 5.0 + TAU * i / 3.0
			overlay.draw_circle(Vector2(cos(a) * 10.0, -58.0 + sin(a) * 3.0), 1.6, FOAM)
	if taunt_t > 0.0:
		overlay.draw_rect(Rect2(-1.5, -72, 3, 3), Color("f2a65a"))
