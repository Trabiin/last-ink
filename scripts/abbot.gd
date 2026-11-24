class_name Abbot
extends Enemy
## The Abbot Who Copied Himself (issue #28, Chapter 2 boss). Abbot Wulfstan of Saint Ledger's set his monks to
## copy the Ledger so the world could be written back after the Blank, and in the end copied himself.
## The fight is "many copies, one real".
##
## The garth fills with paper copies of him (AbbotCopy, below). They walk a half-beat behind him and copy
## short strips of floor out of the world; a hit tears one up, but only hits on the real Abbot count.
## The tell: only the real Abbot's hands drip ink. Every so often the whole garth flashes white and he
## RE-COPIES: every figure trades places in a burst of paper, and any copies you tore up come back.
## His own moves, all telegraphed:
##   Crozier sweep - up close he draws the crozier back (a red wedge on the ground) and sweeps it round.
##   Copy out     - he writes in the air and a whole row or column of the garth is struck out, like the
##                  Auditor's ink line (StruckLine). Phase 2: a cross, or three in a row with gaps.
##   Illumination - phase 2 only: a gold ring grows round him, then the gilt bursts outwards. Get clear.
## Phase 2 ("The Second Copy", at half HP): a short untouchable beat, then more copies (5), faster
## re-copies, illumination, and penitents called in by the boss fight (boss_fight.gd).
##
## Driven by boss_fight.gd like the Auditor: it wakes him (dormant = false), gives him the floor to draw
## lines on and the arena bounds, and watches phase_changed / dead.

signal phase_changed(phase: int)

enum Act { DORMANT, WALK, SWING, LINES, RECOPY, ILLUMINATE, TRANSITION }

const MAX_HP := 820
const PHASE2_AT := 0.5
const WALK_SPEED := 30.0
const SWING_RANGE := 56.0
const SWING_REACH := 72.0
const SWING_HALF := 1.1  # radians either side of his aim
const SWING_T := [0.85, 0.7]
const LINE_W := 22.0
const LINE_WARN := [1.15, 0.95]
const LINE_LAST := [3.5, 4.0]
const CAST_T := 0.7
const RECOPY_EVERY := [13.0, 9.5]
const RECOPY_T := 1.1
const COPIES := [3, 5]
const ILLUM_T := 1.3
const ILLUM_R := 96.0
const TRANSITION_T := 2.2
const INK := Color("15101a")
const PAPER := Color("ebe7dc")
const GILT := Color("e0b04a")

var damage := 13  # the crozier
var line_damage := 4
var illum_damage := 16
var act: int = Act.DORMANT
var act_t := 0.0
var act_total := 1.0
var phase := 1
var aim_dir := Vector2.DOWN
var swing_hit: Array = []
var actions := 0  # since the last struck line
var recopy_t := 6.0
var floor_node: Node
var arena := Rect2(0, 0, 576, 416)
var copies: Array = []
var told_copy := false
var is_copy := false  # an AbbotCopy (the same script, so the art and the walk match his exactly)
var master: Abbot = null
var copy_line_t := 4.0


func _ready() -> void:
	art_id = "abbot"
	super._ready()
	number_color = Color("ffe7a3")
	if is_copy:
		max_hp = 26
		hp = max_hp
		xp = 1
		radius = 9.0
		move_speed = WALK_SPEED * 0.9
		modulate = Color(0.92, 0.92, 0.96, 0.9)  # a shade paler than him; the ink drip is the real tell
		return
	boss = true  # no stuns, and it always knows where everyone is
	max_hp = MAX_HP
	hp = MAX_HP
	xp = 90
	radius = 10.0
	move_speed = WALK_SPEED
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 8.0


func wake() -> void:
	if act == Act.DORMANT and not is_copy:
		_spawn_copies(COPIES[0])
		_go(Act.WALK, 0.8)


func _go(a: int, t: float) -> void:
	act = a
	act_t = t
	act_total = maxf(t, 0.01)


func ratio() -> float:
	return float(hp) / float(max_hp)


## Untouchable while dormant, re-copying or changing phase. A copy just tears.
func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if is_copy:
		if master != null and is_instance_valid(master) and (master.act == Act.RECOPY or master.act == Act.TRANSITION):
			return false
		var torn := super.take_hit(amount, from, force * 0.3)
		if torn and master != null and is_instance_valid(master):
			master._copy_hit()
		return torn
	if act == Act.DORMANT or act == Act.TRANSITION or act == Act.RECOPY:
		if not dead and flash_t <= 0.0:
			Fx.damage_number(get_parent(), global_position + Vector2(0, -60), tr("no effect"), Color(0.8, 0.8, 0.8))
			flash_t = 0.05
		return false
	var hit := super.take_hit(amount, from, force * 0.05)
	if hit and not dead and phase == 1 and ratio() <= PHASE2_AT:
		_start_phase2()
	return hit


## The first time someone tears up a copy, the HUD says how to find the real one.
func _copy_hit() -> void:
	if told_copy:
		return
	told_copy = true
	var scene := get_tree().current_scene
	if scene != null and scene.get("hud") != null:
		scene.hud.say(tr("That one was a copy. Only the real Abbot's hands drip ink."), 3.5)


func _on_hit() -> void:
	pass  # no stagger for him or his copies: paper does not flinch


func taunt(h: Hero, time: float) -> void:
	taunter = h
	taunt_t = time * (1.0 if is_copy else 0.5)


func _start_phase2() -> void:
	phase = 2
	_go(Act.TRANSITION, TRANSITION_T)
	for c in copies:
		if is_instance_valid(c):
			c.phase = 2
	Fx.ring(get_parent(), global_position + Vector2(0, -10), 70.0, INK)
	Fx.burst(get_parent(), global_position + Vector2(0, -34), [PAPER, INK, GILT], 30, 130.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(5.0)
	phase_changed.emit(2)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192): timers run slower, _slide() moves slower
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	taunt_t = maxf(taunt_t - delta, 0.0)
	act_t -= delta
	if is_copy:
		_copy_process(delta)
		return
	var dir := Vector2.ZERO
	if act != Act.DORMANT and (target == null or target.dead or taunt_t > 0.0):
		target = _find_target(2000.0)
	if act == Act.WALK or act == Act.SWING or act == Act.LINES or act == Act.ILLUMINATE:
		recopy_t -= delta

	match act:
		Act.DORMANT:
			pass
		Act.WALK:
			if target:
				var to := target.global_position - global_position
				facing = facing.slerp(to.normalized(), minf(1.0, delta * 4.0)).normalized()
				if to.length() > SWING_RANGE * 0.8:
					dir = to.normalized()
			if recopy_t <= 0.0:
				_begin_recopy()
			elif act_t <= 0.0 and target:
				_choose()
		Act.SWING:
			var k := 1.0 - act_t / act_total
			if k < 0.5 and target:
				aim_dir = aim_dir.slerp((target.global_position - global_position).normalized(), minf(1.0, delta * 8.0)).normalized()
			facing = aim_dir
			if act_t <= 0.0:
				_swing()
				actions += 1
				_go(Act.WALK, 0.7 if phase == 1 else 0.45)
		Act.LINES:
			if act_t <= 0.0:
				_go(Act.WALK, 0.9 if phase == 1 else 0.6)
		Act.ILLUMINATE:
			if act_t <= 0.0:
				_burst_gilt()
				actions += 1
				_go(Act.WALK, 0.8)
		Act.RECOPY:
			if act_t <= 0.0:
				_shuffle()
				recopy_t = RECOPY_EVERY[phase - 1]
				_go(Act.WALK, 0.5)
		Act.TRANSITION:
			if act_t <= 0.0:
				actions = 9  # opens phase 2 with lines
				_begin_recopy()

	velocity = dir * move_speed * (1.2 if phase == 2 else 1.0) + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	_slide()
	queue_redraw()


func _choose() -> void:
	var dist := target.global_position.distance_to(global_position)
	var need_lines := 2 if phase == 1 else 1
	if phase == 2 and actions >= 2 and randf() < 0.45:
		_go(Act.ILLUMINATE, ILLUM_T)
	elif actions >= need_lines or (dist > 170.0 and randf() < 0.5):
		_cast_lines()
	elif dist < SWING_RANGE + 10.0:
		aim_dir = (target.global_position - global_position).normalized()
		swing_hit.clear()
		_go(Act.SWING, SWING_T[phase - 1])
	else:
		_go(Act.WALK, 0.4)


func _swing() -> void:
	Fx.sweep(get_parent(), global_position + Vector2(0, -8), aim_dir.angle(), SWING_HALF, SWING_REACH, GILT)
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or swing_hit.has(hero):
			continue
		var to := hero.global_position - global_position
		if to.length() < SWING_REACH + hero.radius and absf(aim_dir.angle_to(to)) <= SWING_HALF:
			swing_hit.append(hero)
			hero.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), global_position, 230.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(2.0)


## Strikes rows/columns of the garth out of the world (the Auditor's StruckLine).
func _cast_lines() -> void:
	actions = 0
	_go(Act.LINES, CAST_T)
	if target == null or floor_node == null:
		return
	var tp := target.global_position
	if phase == 1:
		_line(randf() < 0.5, tp)
	elif randf() < 0.5:
		_line(true, tp)
		_line(false, tp)
	else:
		var horiz := randf() < 0.5
		var off := randf_range(-20.0, 20.0)
		for i in [-1, 0, 1]:
			_line(horiz, tp + (Vector2(0, off + i * 64.0) if horiz else Vector2(off + i * 64.0, 0)))
	Fx.burst(get_parent(), global_position + Vector2(0, -60), [INK, PAPER], 12, 60.0)


func _line(horiz: bool, at: Vector2) -> void:
	var l := StruckLine.new()
	if horiz:
		var y := clampf(at.y, arena.position.y + LINE_W / 2.0, arena.end.y - LINE_W / 2.0)
		l.rect = Rect2(arena.position.x, y - LINE_W / 2.0, arena.size.x, LINE_W)
	else:
		var x := clampf(at.x, arena.position.x + LINE_W / 2.0, arena.end.x - LINE_W / 2.0)
		l.rect = Rect2(x - LINE_W / 2.0, arena.position.y, LINE_W, arena.size.y)
	l.warn = LINE_WARN[phase - 1]
	l.last = LINE_LAST[phase - 1]
	l.damage = line_damage
	floor_node.add_child(l)


func _burst_gilt() -> void:
	Fx.ring(get_parent(), global_position + Vector2(0, -6), ILLUM_R, GILT)
	Fx.burst(get_parent(), global_position + Vector2(0, -30), [GILT, PAPER], 24, 140.0)
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero and not hero.dead and hero.global_position.distance_to(global_position) < ILLUM_R + hero.radius:
			hero.take_hit(Empire.damage_to_party(roundi(illum_damage * hit_mult())), global_position, 260.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(3.5)


# ---------------------------------------------------------------- copies

func _begin_recopy() -> void:
	_go(Act.RECOPY, RECOPY_T)
	Audio.sfx("burst", 0.4)


## Copies torn up since the last re-copy come back, then every figure trades places.
func _shuffle() -> void:
	copies = copies.filter(func(c): return is_instance_valid(c) and not c.dead)
	var want: int = COPIES[phase - 1]
	_spawn_copies(want - copies.size())
	var figures: Array = [self]
	figures.append_array(copies)
	var spots: Array = figures.map(func(f): return f.global_position)
	spots.shuffle()
	for i in figures.size():
		var f: Node2D = figures[i]
		Fx.burst(get_parent(), f.global_position + Vector2(0, -30), [PAPER, INK], 10, 70.0)
		f.global_position = spots[i]
		Fx.burst(get_parent(), f.global_position + Vector2(0, -30), [PAPER, INK], 10, 70.0)


func _spawn_copies(n: int) -> void:
	for i in maxi(n, 0):
		var c: Abbot = (get_script() as Script).new()
		c.is_copy = true
		c.master = self
		c.phase = phase
		c.floor_node = floor_node
		c.arena = arena
		c.copy_line_t = randf_range(2.5, 5.0)
		var ang := TAU * (float(i) + randf()) / float(maxi(n, 1))
		var p := global_position + Vector2.RIGHT.rotated(ang) * randf_range(70.0, 130.0)
		c.position = Vector2(clampf(p.x, arena.position.x + 20, arena.end.x - 20), clampf(p.y, arena.position.y + 30, arena.end.y - 10))
		get_parent().add_child(c)
		c.facing = Vector2.DOWN
		c.set_meta("kind", "abbot_copy")  # no loot, no kill count, no journal entry: it is only paper
		copies.append(c)
		Fx.burst(get_parent(), c.position + Vector2(0, -30), [PAPER, INK], 12, 70.0)


## A copy: keeps its distance, walks a half-beat behind the real one, and copies short strips of floor out.
func _copy_process(delta: float) -> void:
	if master == null or not is_instance_valid(master) or master.dead:
		_die_quietly()
		return
	var dir := Vector2.ZERO
	var frozen: bool = master.act == Act.RECOPY or master.act == Act.TRANSITION or master.act == Act.DORMANT
	if not frozen:
		if target == null or target.dead or taunt_t > 0.0:
			target = _find_target(2000.0)
		copy_line_t -= delta
		if target:
			var to := target.global_position - global_position
			facing = facing.slerp(to.normalized(), minf(1.0, delta * 3.0)).normalized()
			if to.length() > 130.0:
				dir = to.normalized()
			elif to.length() < 70.0:
				dir = -to.normalized()
			if copy_line_t <= 0.0 and act == Act.WALK:
				copy_line_t = randf_range(5.0, 7.0) if phase == 1 else randf_range(3.5, 5.0)
				aim_dir = to
				_go(Act.LINES, 1.0)
		if act == Act.LINES and act_t <= 0.0:
			_copy_strip()
			_go(Act.WALK, 0.5)
		elif act == Act.DORMANT:
			_go(Act.WALK, 0.3)
	velocity = dir * move_speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	_slide()
	queue_redraw()


func _copy_strip() -> void:
	if floor_node == null or target == null:
		return
	var l := StruckLine.new()
	var c := target.global_position
	var horiz := absf(aim_dir.x) > absf(aim_dir.y)
	l.rect = Rect2(c.x - 70.0, c.y - 10.0, 140.0, 20.0) if horiz else Rect2(c.x - 10.0, c.y - 70.0, 20.0, 140.0)
	l.warn = 1.1
	l.last = 2.6
	l.damage = 3
	floor_node.add_child(l)


func _die_quietly() -> void:
	if dead:
		return
	dead = true
	Fx.burst(get_parent(), global_position + Vector2(0, -30), [PAPER, Color("d9d4c8")], 14, 80.0)
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0


func _on_death() -> void:
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0
	if is_copy:
		Fx.burst(get_parent(), global_position + Vector2(0, -30), [PAPER, Color("d9d4c8"), INK], 18, 90.0)
		return
	for c in copies:  # his copies fold up into blank sheets with him
		if is_instance_valid(c):
			c._die_quietly()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(6.0)


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if art == null:  # no sprite set at all: a plain stand-in shape so the fight still reads
		if dying_t >= 0.0:
			dying_t += delta
			modulate.a = clampf(1.0 - dying_t, 0.0, 1.0)
			if dying_t > 1.0:
				queue_free()
		queue_redraw()
		return
	var row := Hero.dir_row(aim_dir if act == Act.SWING else facing)
	sprite.position = Vector2.ZERO
	if dying_t >= 0.0:
		dying_t += delta
		var long := 2.4 if not is_copy else 0.5
		if art.has("death") and not is_copy:
			art.apply(sprite, "death", Hero.dir_row(Vector2.DOWN), dying_t)
		else:
			art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", row, 1)
			sprite.scale = Vector2(1.0 + 0.5 * dying_t / long, maxf(1.0 - dying_t / long, 0.05))
		if not is_copy and fmod(dying_t, 0.25) < delta:  # pages blow loose
			Fx.burst(get_parent(), global_position + Vector2(randf_range(-12, 12), randf_range(-60, -5)), [PAPER, INK], 8, 80.0)
		modulate.a = clampf(1.0 - maxf(dying_t - long * 0.6, 0.0) / (long * 0.4), 0.0, 1.0)
		if dying_t > long:
			queue_free()
		return
	var t := anim_t - (0.12 if is_copy else 0.0)  # copies move a half-beat behind him
	if flash_t > 0.0 and art.has("hurt") and act != Act.TRANSITION:
		art.apply(sprite, "hurt", row, 0.12 - flash_t)
	else:
		var k := clampf(1.0 - act_t / act_total, 0.0, 0.999)
		match act:
			Act.SWING:
				var n := art.frames_of("attack")
				art.apply_frame(sprite, "attack", row, int(k * float(n)))
			Act.LINES:
				var key := "sweep" if art.has("sweep") else "attack"
				art.apply_frame(sprite, key, row, int(k * float(art.frames_of(key))))
			Act.TRANSITION, Act.RECOPY:
				var key := "phase" if art.has("phase") else "idle"
				art.apply_frame(sprite, key, Hero.dir_row(Vector2.DOWN), int(k * float(art.frames_of(key))))
				sprite.position = Vector2(randf_range(-0.8, 0.8), 0)
			Act.ILLUMINATE:
				art.apply_frame(sprite, "idle", row, 0)
				sprite.position = Vector2(randf_range(-0.6, 0.6), 0)
			_:
				art.apply(sprite, "walk" if velocity.length() > 5.0 else "idle", row, t)
	if master != null and is_instance_valid(master) and master.act == Act.RECOPY:
		sprite.modulate = Color(1.6, 1.6, 1.6) if not Access.reduce_flashing else Color(1.2, 1.2, 1.2)
	elif act == Act.RECOPY:
		sprite.modulate = Color(1.6, 1.6, 1.6) if not Access.reduce_flashing else Color(1.2, 1.2, 1.2)
	else:
		sprite.modulate = Color.WHITE
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		draw_shadow(11.0 * modulate.a)
		return
	if not is_copy:
		if act == Act.SWING:  # the wedge the crozier will sweep
			var k := 1.0 - act_t / act_total
			draw_set_transform(Vector2.ZERO, aim_dir.angle(), Vector2(1.0, 0.85))
			var pts := PackedVector2Array([Vector2.ZERO])
			for i in 13:
				pts.append(Vector2.RIGHT.rotated(-SWING_HALF + SWING_HALF * 2.0 * i / 12.0) * SWING_REACH)
			draw_colored_polygon(pts, Color(1, 0.3, 0.3, 0.1 + 0.2 * k))
			draw_polyline(pts + PackedVector2Array([Vector2.ZERO]), Color(Telegraph.EDGE, 0.5 + 0.4 * k), 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif act == Act.ILLUMINATE:
			var k := 1.0 - act_t / act_total
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.8))
			Telegraph.circle(self, Vector2.ZERO, ILLUM_R, k)
			draw_arc(Vector2.ZERO, ILLUM_R * k, 0, TAU, 40, Color(GILT, 0.9), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif act == Act.LINES:  # a copy about to copy a strip: its quill hand glows
		draw_circle(Vector2(0, -58), 3.0, Color(PAPER, 0.8))
	draw_shadow(11.0 if not is_copy else 9.0)
	if art == null:  # stand-in shape for a build without the sprite set
		draw_rect(Rect2(-9, -52, 18, 50), Color("5a1e22") if not is_copy else Color("c8c0b0"))


func _draw_overlay() -> void:
	if dying_t >= 0.0:
		return
	if not is_copy:  # the tell: ink drips from the real Abbot's hands
		for side in [-1.0, 1.0]:
			var hand := Vector2(side * 11.0 + facing.x * 4.0, -30.0)
			var dy := fmod(anim_t * 24.0 + (4.0 if side > 0 else 0.0), 14.0)
			overlay.draw_rect(Rect2(hand + Vector2(-1, dy), Vector2(2, 3)), INK)
			overlay.draw_rect(Rect2(hand + Vector2(-0.5, 0), Vector2(1, minf(dy, 4.0))), Color(INK, 0.7))
		if act == Act.LINES or act == Act.TRANSITION or act == Act.RECOPY or act == Act.ILLUMINATE:
			Telegraph.alert(overlay, Vector2(-3, -80), 12)
	if taunt_t > 0.0:
		overlay.draw_rect(Rect2(-1.5, -82, 3, 3), Color("f2a65a"))
