class_name Auditor
extends Enemy
## The Auditor (issue #17): the Concord's answer to an unregistered town. A tall clerk in black
## and parchment who "strikes people out" with a quill the size of a lance. Ends Act 1.
##
## He never flinches from single hits. Everything he does is telegraphed:
##   Lance thrust - he aims (a red lane on the ground follows the target, then locks and
##                  brightens), then lunges the full length of it. Step sideways out of the lane.
##                  The nib sticks in the ground afterwards: that is your opening (+50% damage).
##   Ink line     - he raises the quill and a dotted line with a red wash marks a whole row or
##                  column of the arena. Then the pen sweeps across and the floor there is erased
##                  for a few seconds (StruckLine): standing on it hurts.
## Phase 2 ("Final Notice", at half HP): a short invulnerable beat, then faster wind-ups,
## thrusts in chains of three, crossed or triple ink lines, and clerks (Nibblers) called in by
## the boss fight (boss_fight.gd).
##
## Driven by boss_fight.gd, which wakes him up (dormant = false), tells him where to draw lines
## (floor) and the arena bounds, and watches phase_changed / dead.

signal phase_changed(phase: int)

enum Act { DORMANT, WALK, AIM, THRUST, STUCK, LINES, TRANSITION }

const MAX_HP := 700
const PHASE2_AT := 0.5
const SCALE := 2.0  # whole pixels; the big art pass replaces this doll
const WALK_SPEED := 36.0
const THRUST_LEN := 150.0
const THRUST_SPEED := 560.0
const THRUST_WIDTH := 16.0
const AIM_T := [1.0, 0.8]  # wind-up per phase
const CHAIN_AIM_T := 0.6  # wind-up of the 2nd and 3rd thrust in a phase-2 chain
const LOCK_AT := 0.5  # share of the wind-up during which the lane still follows the target
const STUCK_T := [1.3, 0.95]
const LINE_WARN := [1.15, 0.95]
const LINE_LAST := [4.0, 4.6]
const LINE_W := 22.0
const CAST_T := 0.7
const TRANSITION_T := 2.2
const OPENING_MULT := 1.5

const LOOK := {"skin": Color("e6dccd"), "metal": Color("26222c"), "cloth": Color("efe6cf"), "boots": Color("15101a")}
const QUILL := Color("f2eee2")
const QUILL_SHADE := Color("c9c2b0")

var damage := 12  # a thrust; ink lines use line_damage
var line_damage := 4
var act: int = Act.DORMANT
var act_t := 0.0
var phase := 1
var chain := 0  # thrusts still to come in a phase-2 chain
var aim_dir := Vector2.DOWN
var aim_total := 0.85
var thrust_left := 0.0
var thrust_hit: Array = []
var actions_since_lines := 0
var floor_node: Node  # where StruckLines go (the Area, under the entities)
var arena := Rect2(0, 0, 576, 416)
var doll: Array[Sprite2D] = []
var told_opening := false


func _ready() -> void:
	art_id = "auditor"  # art pass sprite (boss about twice a hero's height); falls back to the paper doll and code-drawn quill
	super._ready()
	boss = true  # no stuns, and it always knows where everyone is
	max_hp = MAX_HP
	hp = MAX_HP
	xp = 80
	radius = 10.0
	move_speed = WALK_SPEED
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 8.0
	number_color = Color("ffe7a3")
	if art != null:
		return
	sprite.visible = false
	for layer in [[Art.BODY, "body"], [Art.OUTFITS["soldier"], "soldier"]]:
		var s := Sprite2D.new()
		s.texture = layer[0]
		s.hframes = 24
		s.vframes = 8
		s.offset = Vector2(0, -7)
		s.scale = Vector2(SCALE, SCALE)
		s.position = Vector2(0, -5)
		s.material = Art.recolor_material(layer[1], LOOK)
		add_child(s)
		doll.append(s)
	move_child(overlay, -1)


func wake() -> void:
	if act == Act.DORMANT:
		_go(Act.WALK, 0.6)


func _go(a: int, t: float) -> void:
	act = a
	act_t = t


func ratio() -> float:
	return float(hp) / float(max_hp)


## Untouchable while dormant and during the phase change; the nib stuck in the ground is the opening.
func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if act == Act.DORMANT or act == Act.TRANSITION:
		if not dead and flash_t <= 0.0:
			Fx.damage_number(get_parent(), global_position + Vector2(0, -40), tr("no effect"), Color(0.8, 0.8, 0.8))
			flash_t = 0.05
		return false
	if act == Act.STUCK:
		amount = roundi(amount * OPENING_MULT)
	var hit := super.take_hit(amount, from, force * (0.15 if act == Act.STUCK else 0.05))
	if hit and not dead and phase == 1 and ratio() <= PHASE2_AT:
		_start_phase2()
	return hit


func _on_hit() -> void:
	pass  # no stagger: a boss finishes what he starts


func taunt(h: Hero, time: float) -> void:
	# Hold the Line still works on him, but only changes who he aims at next.
	taunter = h
	taunt_t = time * 0.5


func _start_phase2() -> void:
	phase = 2
	chain = 0
	_go(Act.TRANSITION, TRANSITION_T)
	Fx.ring(get_parent(), global_position + Vector2(0, -10), 60.0, Color("15101a"))
	Fx.burst(get_parent(), global_position + Vector2(0, -24), [Color.BLACK, QUILL, Color("ff6b6b")], 26, 120.0)
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
	var dir := Vector2.ZERO
	if act != Act.DORMANT and (target == null or target.dead or taunt_t > 0.0):
		target = _find_target(2000.0)

	match act:
		Act.DORMANT:
			pass
		Act.WALK:
			if target:
				var to := target.global_position - global_position
				facing = facing.slerp(to.normalized(), minf(1.0, delta * 4.0)).normalized()
				if to.length() > 40.0:
					dir = to.normalized()
			if act_t <= 0.0 and target:
				_choose()
		Act.AIM:
			var k := 1.0 - act_t / aim_total
			if target and k < LOCK_AT:
				var want := (target.global_position - global_position).normalized()
				aim_dir = aim_dir.slerp(want, minf(1.0, delta * 10.0)).normalized()
			facing = aim_dir
			if k > 0.35:
				_allies_sidestep()
			if act_t <= 0.0:
				thrust_hit.clear()
				thrust_left = THRUST_LEN
				_go(Act.THRUST, THRUST_LEN / THRUST_SPEED + 0.05)
		Act.THRUST:
			var before := global_position
			velocity = aim_dir * THRUST_SPEED
			_slide()
			thrust_left -= global_position.distance_to(before)
			_thrust_hits(before, global_position)
			if thrust_left <= 0.0 or act_t <= 0.0 or global_position.distance_to(before) < 1.0:
				_end_thrust()
			queue_redraw()
			return
		Act.STUCK:
			if act_t <= 0.0:
				_go(Act.WALK, randf_range(0.5, 0.8) if phase == 1 else randf_range(0.3, 0.5))
		Act.LINES:
			if act_t <= 0.0:
				_go(Act.WALK, 1.0 if phase == 1 else 0.6)
		Act.TRANSITION:
			if act_t <= 0.0:
				actions_since_lines = 9  # opens phase 2 with lines
				_go(Act.WALK, 0.3)

	velocity = dir * move_speed * (1.25 if phase == 2 else 1.0) + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	_slide()
	queue_redraw()


func _choose() -> void:
	var dist := target.global_position.distance_to(global_position)
	var need_lines := 2 if phase == 1 else 1
	if actions_since_lines >= need_lines or (dist > 180.0 and randf() < 0.6):
		_cast_lines()
	elif dist < 200.0:
		chain = 2 if phase == 2 else 0
		_aim(AIM_T[phase - 1])
	else:
		_go(Act.WALK, 0.4)


func _aim(t: float) -> void:
	aim_total = t
	if target:
		aim_dir = (target.global_position - global_position).normalized()
	_go(Act.AIM, t)


func _end_thrust() -> void:
	actions_since_lines += 1
	Fx.burst(get_parent(), global_position + aim_dir * 30.0, [Color.BLACK, QUILL], 10, 70.0)
	if chain > 0 and target:
		chain -= 1
		_aim(CHAIN_AIM_T)
		return
	_go(Act.STUCK, STUCK_T[phase - 1])
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(2.5)
	if not told_opening and scene != null and scene.get("hud") != null:
		told_opening = true
		scene.hud.say(tr("His nib is stuck in the ground. Hit him now!"), 3.0)


## Allies the player is not steering read the lane too, and step out of it sideways.
func _allies_sidestep() -> void:
	var a := global_position
	var b := a + aim_dir * (THRUST_LEN + 24.0)
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or hero.controlled:
			continue
		var q := Geometry2D.get_closest_point_to_segment(hero.global_position, a, b)
		var off := hero.global_position - q
		if off.length() < THRUST_WIDTH / 2.0 + hero.radius + 4.0:
			var side := aim_dir.orthogonal()
			hero.knockback = side * (1.0 if off.dot(side) >= 0.0 else -1.0) * 130.0


func _thrust_hits(a: Vector2, b: Vector2) -> void:
	var tip_b := b + aim_dir * 24.0  # the quill reaches past his body
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or thrust_hit.has(hero):
			continue
		var q := Geometry2D.get_closest_point_to_segment(hero.global_position, a, tip_b)
		if q.distance_to(hero.global_position) < THRUST_WIDTH / 2.0 + hero.radius:
			thrust_hit.append(hero)
			if hero.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), q - aim_dir * 8.0, 260.0):
				Status.struck(self, hero)  # the quill Erases (issue #112)


## Strikes rows/columns of the arena out of the record.
func _cast_lines() -> void:
	actions_since_lines = 0
	_go(Act.LINES, CAST_T)
	if target == null or floor_node == null:
		return
	var tp := target.global_position
	if phase == 1:
		if randf() < 0.5:
			_line(true, tp.y)
		else:
			_line(false, tp.x)
	elif randf() < 0.5:  # a cross through whoever he is after
		_line(true, tp.y)
		_line(false, tp.x)
	else:  # three in a row, with gaps to stand in
		var horiz := randf() < 0.5
		var c := tp.y if horiz else tp.x
		var off := randf_range(-20.0, 20.0)
		for i in [-1, 0, 1]:
			_line(horiz, c + off + i * 64.0)
	Fx.burst(get_parent(), global_position + Vector2(0, -50), [Color.BLACK, QUILL], 12, 60.0)


func _line(horiz: bool, at: float) -> void:
	var l := StruckLine.new()
	if horiz:
		at = clampf(at, arena.position.y + LINE_W / 2.0, arena.end.y - LINE_W / 2.0)
		l.rect = Rect2(arena.position.x, at - LINE_W / 2.0, arena.size.x, LINE_W)
	else:
		at = clampf(at, arena.position.x + LINE_W / 2.0, arena.end.x - LINE_W / 2.0)
		l.rect = Rect2(at - LINE_W / 2.0, arena.position.y, LINE_W, arena.size.y)
	l.warn = LINE_WARN[phase - 1]
	l.last = LINE_LAST[phase - 1]
	l.damage = line_damage
	floor_node.add_child(l)


func _on_death() -> void:
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0
	act = Act.STUCK
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(6.0)


func _process(delta: float) -> void:
	if art != null:
		_process_art_boss(delta)
		return
	var col := 0
	if dying_t >= 0.0:
		dying_t += delta
		col = 23
		if fmod(dying_t, 0.25) < delta:  # pages tear loose as he is struck out
			Fx.burst(get_parent(), global_position + Vector2(randf_range(-10, 10), randf_range(-40, -5)), [Color.BLACK, QUILL, Color("efe6cf")], 8, 80.0)
		modulate.a = clampf(1.0 - maxf(dying_t - 1.2, 0.0) * 1.2, 0.0, 1.0)
		if dying_t > 2.2:
			queue_free()
			return
	elif flash_t > 0.0:
		col = 19
	else:
		match act:
			Act.AIM, Act.LINES:
				col = 4
			Act.THRUST, Act.STUCK:
				col = 6
			Act.TRANSITION:
				col = 19 if fmod(anim_t, 0.3) < 0.15 else 4
			Act.WALK:
				col = int(anim_t * 5.0) % 4 if velocity.length() > 5.0 else 0
	for s in doll:
		s.frame = Hero.dir_row(facing) * 24 + col
		var shake := (act == Act.AIM and act_t / aim_total < 1.0 - LOCK_AT) or act == Act.TRANSITION
		s.position = Vector2(randf_range(-0.8, 0.8), -5) if shake else Vector2(0, -5)
	queue_redraw()
	overlay.queue_redraw()


## The drawn Auditor: each act picks an animation and runs it on that act's own timer, so the
## telegraphs (aim, raised quill, phase change) line up with the frames.
func _process_art_boss(delta: float) -> void:
	var row := Hero.dir_row(aim_dir if act == Act.AIM or act == Act.THRUST or act == Act.STUCK else facing)
	sprite.position = Vector2.ZERO
	if dying_t >= 0.0:
		dying_t += delta
		art.apply(sprite, "death", Hero.dir_row(Vector2.DOWN), dying_t)
		if fmod(dying_t, 0.25) < delta:  # pages tear loose as he is struck out
			Fx.burst(get_parent(), global_position + Vector2(randf_range(-10, 10), randf_range(-60, -5)), [Color.BLACK, QUILL, Color("efe6cf")], 8, 80.0)
		modulate.a = clampf(1.0 - maxf(dying_t - 1.4, 0.0) * 1.2, 0.0, 1.0)
		if dying_t > 2.4:
			queue_free()
			return
	elif flash_t > 0.0 and act != Act.TRANSITION:
		art.apply(sprite, "hurt", row, 0.12 - flash_t)
	else:
		var n := art.frames_of("attack")
		match act:
			Act.AIM:  # quill drawn back over the wind-up
				var k := clampf(1.0 - act_t / aim_total, 0.0, 1.0)
				art.apply_frame(sprite, "attack", row, int(k * 2.99))
				if k < 1.0 - LOCK_AT:
					sprite.position = Vector2(randf_range(-0.8, 0.8), 0)
			Act.THRUST:
				var k := clampf(1.0 - act_t / (THRUST_LEN / THRUST_SPEED + 0.05), 0.0, 1.0)
				art.apply_frame(sprite, "attack", row, 3 + int(k * (n - 4)))
			Act.STUCK:
				art.apply_frame(sprite, "attack", row, n - 1)
			Act.LINES:
				var m := art.frames_of("sweep")
				art.apply_frame(sprite, "sweep", row, int(clampf(1.0 - act_t / CAST_T, 0.0, 0.999) * m))
			Act.TRANSITION:
				var m := art.frames_of("phase")
				art.apply_frame(sprite, "phase", Hero.dir_row(Vector2.DOWN), int(clampf(1.0 - act_t / TRANSITION_T, 0.0, 0.999) * m))
				sprite.position = Vector2(randf_range(-0.8, 0.8), 0)
			_:
				art.apply(sprite, "walk" if velocity.length() > 5.0 else "idle", row, anim_t)
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		draw_shadow(11.0 * modulate.a)
		return
	if act == Act.AIM:  # the lane on the ground: follows the target, then locks and brightens
		var k := 1.0 - act_t / aim_total
		var locked := k >= LOCK_AT
		var len := THRUST_LEN + 24.0
		draw_set_transform(Vector2.ZERO, aim_dir.angle(), Vector2.ONE)
		var r := Rect2(0, -THRUST_WIDTH / 2.0, len, THRUST_WIDTH)
		Telegraph.rect(self, r, minf(k / LOCK_AT, 1.0), 1.0 if locked else 0.1)
		if locked:
			draw_line(Vector2(0, 0), Vector2(len, 0), Color(1, 0.8, 0.8, 0.6), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_shadow(11.0)


func _draw_overlay() -> void:
	if dying_t >= 0.0 and dying_t > 0.6:
		return
	if art != null:  # the sprite carries the hat and the quill; only the tells are drawn
		if dying_t < 0.0 and (act == Act.LINES or act == Act.TRANSITION):
			Telegraph.alert(overlay, Vector2(-3, -64), 12)
		if taunt_t > 0.0:
			overlay.draw_rect(Rect2(-1.5, -66, 3, 3), Color("f2a65a"))
		if phase == 2 and dying_t < 0.0:  # ink drips from the nib
			var tip := facing * 15.0 + Vector2(0, -14)
			overlay.draw_rect(Rect2(tip + Vector2(-0.5, fmod(anim_t * 30.0, 8.0)), Vector2(1, 2)), Color("8a1f2a"))
		return
	# Hat first: a tall black clerk's stovepipe with a parchment band.
	var head := Vector2(0, -35)
	overlay.draw_rect(Rect2(head + Vector2(-6, -1), Vector2(12, 2)), Color("15101a"))
	overlay.draw_rect(Rect2(head + Vector2(-4, -10), Vector2(8, 10)), Color("1d1922"))
	overlay.draw_rect(Rect2(head + Vector2(-4, -4), Vector2(8, 2)), Color("efe6cf"))
	# The quill: carried upright when walking, levelled like a lance to aim and thrust.
	var dir := (facing + Vector2(0, -1.8)).normalized()
	var hand := Vector2(facing.x * 9.0, -16.0 + facing.y * 3.0)
	var base := hand - dir * 14.0
	match act:
		Act.AIM:
			dir = aim_dir
			var k := clampf(1.0 - act_t / aim_total, 0.0, 1.0)
			base = hand - dir * (14.0 + 10.0 * k)  # drawn back
		Act.THRUST:
			dir = aim_dir
			base = hand - dir * 4.0
		Act.STUCK:
			dir = (aim_dir + Vector2(0, 0.9)).normalized()  # nib in the dirt
			base = hand - dir * 10.0
		Act.LINES:
			dir = Vector2(facing.x * 0.3, -1).normalized()  # raised high
			base = hand + Vector2(0, -6) - dir * 10.0
	_draw_quill(base, dir, 44.0)
	if act == Act.LINES or act == Act.TRANSITION:
		Telegraph.alert(overlay, Vector2(-3, -52), 12)
	if taunt_t > 0.0:
		overlay.draw_rect(Rect2(-1.5, -52, 3, 3), Color("f2a65a"))


func _draw_quill(base: Vector2, dir: Vector2, length: float) -> void:
	var side := dir.orthogonal()
	var tip := base + dir * length
	# Feather vane along the back two thirds, tapering towards the nib.
	var vane := PackedVector2Array([
		base, base + side * 3.0 + dir * 6.0, base + side * 5.5 + dir * 18.0,
		base + side * 4.0 + dir * 28.0, base + dir * 32.0,
		base - side * 2.5 + dir * 22.0, base - side * 2.0 + dir * 8.0,
	])
	overlay.draw_colored_polygon(vane, QUILL)
	overlay.draw_polyline(vane + PackedVector2Array([vane[0]]), QUILL_SHADE, 1.0)
	overlay.draw_line(base - dir * 3.0, tip - dir * 8.0, Color("8a8070"), 1.0)  # the shaft
	var nib := PackedVector2Array([tip - dir * 9.0 + side * 2.5, tip, tip - dir * 9.0 - side * 2.5])
	overlay.draw_colored_polygon(nib, Color("15101a"))
	if phase == 2:  # dripping
		var dy := fmod(anim_t * 30.0, 8.0)
		overlay.draw_rect(Rect2(tip + Vector2(-0.5, dy), Vector2(1, 2)), Color("8a1f2a"))
