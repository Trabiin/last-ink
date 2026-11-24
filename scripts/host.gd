class_name Host
extends Enemy
## The Host (issue #29, Chapter 3 boss): the guest nobody invited, who sat down at the head of the masquerade's
## table the night the Blank came and never left. Mostly mouth. While it eats, the ink stays off the bridges.
##
## Its moves, all telegraphed:
##   Bite     - up close it opens wide (a red wedge on the floor in front of it) and snaps it shut.
##   Speech   - it shouts a volley of words (scripts/host_word.gd) in a fan; the aim lines show the fan first.
##   Inhale   - it breathes in (a widening ring round it, a warning sign): every hero inside PULL_R slides
##              towards the mouth, and any guest it reaches is swallowed and HEALS it. At the end of the breath
##              it gulps: heroes right at the mouth are bitten. Walk away from it; kill the guests first.
##   Call     - it rings for the next course and two revellers come to the table (they are what it swallows).
## Phase 2 ("Second Helpings", at half HP): a short untouchable beat as it tears its masks off, then a
## harder inhale, faster speech, and the Gulp: it jumps (gone from the floor: no hits land), a shadow marks
## where it will come down, it lands on that spot (a heavy hit to everyone close) and is stuck in the floor
## for STUCK_T: the window to hit it hardest. boss_fight.gd calls in more revellers in phase 2.
##
## Driven by boss_fight.gd like the Abbot: it wakes the Host, gives it the floor and the arena bounds, and
## watches phase_changed / dead.

signal phase_changed(phase: int)

enum Act { DORMANT, WALK, BITE, SPEECH, INHALE, CALL, GULP_UP, GULP_DOWN, STUCK, TRANSITION }

const MAX_HP := 900
const PHASE2_AT := 0.5
const WALK_SPEED := 24.0
const BITE_RANGE := 58.0
const BITE_REACH := 66.0
const BITE_HALF := 0.75
const BITE_T := [0.85, 0.65]
const SPEECH_T := [0.75, 0.6]
const SPEECH_WORDS := [5, 7]
const SPEECH_SPREAD := 0.9  # radians either side of the aim
const INHALE_T := [2.0, 2.6]
const PULL_R := 150.0
const PULL := [48.0, 72.0]  # px/s a hero slides towards the mouth at the edge of the breath (more up close)
const SWALLOW_R := 30.0
const SWALLOW_HEAL := 0.05  # of max HP, per guest swallowed
const GULP_R := 32.0
const CALL_T := 0.9
const CALL_EVERY := 16.0
const GUESTS_MAX := 3
const JUMP_T := 1.0
const LAND_R := 44.0
const STUCK_T := 1.6
const TRANSITION_T := 2.2
const WINE := Color("8a2a4a")
const GOLD := Color("e0c070")
const CREAM := Color("f3ead2")
const WordScript := preload("res://scripts/host_word.gd")

var damage := 15  # the bite
var word_damage := 6
var gulp_damage := 12
var land_damage := 18
var act: int = Act.DORMANT
var act_t := 0.0
var act_total := 1.0
var phase := 1
var aim_dir := Vector2.DOWN
var bite_hit: Array = []
var call_t := 6.0
var since_inhale := 0
var floor_node: Node
var arena := Rect2(0, 0, 576, 416)
var land_at := Vector2.ZERO
var land_mark: FloorMark = null
var told_swallow := false
var told_inhale := false


func _ready() -> void:
	art_id = "host"
	super._ready()
	number_color = Color("ffd0d8")
	boss = true  # no stuns, and it always knows where everyone is
	max_hp = MAX_HP
	hp = MAX_HP
	xp = 100
	radius = 12.0
	move_speed = WALK_SPEED
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 10.0


func wake() -> void:
	if act == Act.DORMANT:
		_go(Act.WALK, 0.8)


func _go(a: int, t: float) -> void:
	act = a
	act_t = t
	act_total = maxf(t, 0.01)


func ratio() -> float:
	return float(hp) / float(max_hp)


func untargetable() -> bool:
	return act == Act.GULP_UP or act == Act.GULP_DOWN


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if act in [Act.DORMANT, Act.TRANSITION, Act.GULP_UP, Act.GULP_DOWN]:
		if not dead and flash_t <= 0.0 and act != Act.GULP_UP and act != Act.GULP_DOWN:
			Fx.damage_number(get_parent(), global_position + Vector2(0, -60), tr("no effect"), Color(0.8, 0.8, 0.8))
			flash_t = 0.05
		return false
	if act == Act.STUCK:
		amount = roundi(amount * 1.25)  # stuck in the floor, mouth full of parquet
	var hit := super.take_hit(amount, from, force * 0.04)
	if hit and not dead and phase == 1 and ratio() <= PHASE2_AT:
		_start_phase2()
	return hit


func _on_hit() -> void:
	pass  # it does not flinch; it chews


func taunt(h: Hero, time: float) -> void:
	taunter = h
	taunt_t = time * 0.5


func _start_phase2() -> void:
	phase = 2
	_go(Act.TRANSITION, TRANSITION_T)
	Fx.ring(get_parent(), global_position + Vector2(0, -10), 80.0, WINE)
	Fx.burst(get_parent(), global_position + Vector2(0, -40), [WINE, GOLD, CREAM], 30, 130.0)  # masks flying off
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(5.0)
	phase_changed.emit(2)


func _say(text: String) -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.get("hud") != null:
		scene.hud.say(text, 3.5)


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
	if act in [Act.WALK, Act.BITE, Act.SPEECH]:
		call_t -= delta
	match act:
		Act.DORMANT:
			pass
		Act.WALK:
			if target:
				var to := target.global_position - global_position
				facing = facing.slerp(to.normalized(), minf(1.0, delta * 3.0)).normalized()
				if to.length() > BITE_RANGE * 0.8:
					dir = to.normalized()
			if act_t <= 0.0 and target:
				_choose()
		Act.BITE:
			var k := 1.0 - act_t / act_total
			if k < 0.55 and target:
				aim_dir = aim_dir.slerp((target.global_position - global_position).normalized(), minf(1.0, delta * 7.0)).normalized()
			facing = aim_dir
			if act_t <= 0.0:
				_bite()
				_go(Act.WALK, 0.8 if phase == 1 else 0.5)
		Act.SPEECH:
			if target and act_t > act_total * 0.4:
				aim_dir = aim_dir.slerp((target.global_position - global_position).normalized(), minf(1.0, delta * 6.0)).normalized()
			facing = aim_dir
			if act_t <= 0.0:
				_speak()
				_go(Act.WALK, 0.7 if phase == 1 else 0.45)
		Act.INHALE:
			_breathe_in(delta)
			if act_t <= 0.0:
				_gulp()
				since_inhale = 0
				_go(Act.WALK, 1.0)
		Act.CALL:
			if act_t <= 0.0:
				_call_guests()
				call_t = CALL_EVERY
				_go(Act.WALK, 0.6)
		Act.GULP_UP:
			if act_t <= 0.0:
				global_position = land_at
				_go(Act.GULP_DOWN, 0.18)
		Act.GULP_DOWN:
			if act_t <= 0.0:
				_land()
				_go(Act.STUCK, STUCK_T)
		Act.STUCK:
			if act_t <= 0.0:
				_go(Act.WALK, 0.4)
		Act.TRANSITION:
			if act_t <= 0.0:
				since_inhale = 9  # opens phase 2 with a breath
				_go(Act.WALK, 0.3)
	velocity = dir * move_speed * (1.25 if phase == 2 else 1.0) + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	if act != Act.GULP_UP and act != Act.GULP_DOWN:
		_slide()
	queue_redraw()


func _choose() -> void:
	var dist := target.global_position.distance_to(global_position)
	since_inhale += 1
	if call_t <= 0.0 and _guests().size() < GUESTS_MAX:
		_go(Act.CALL, CALL_T)
		Audio.sfx("alert", 0.6, -4.0, tr("A bell rings for the next course"))
	elif since_inhale >= (4 if phase == 1 else 3):
		_go(Act.INHALE, INHALE_T[phase - 1])
		Audio.sfx("cast", 0.5, -2.0, tr("The Host breathes in"))
		if not told_inhale:
			told_inhale = true
			_say(tr("It's breathing in! Walk away from the mouth, and keep the guests away from it."))
	elif phase == 2 and randf() < 0.3:
		_start_gulp()
	elif dist < BITE_RANGE + 10.0:
		aim_dir = (target.global_position - global_position).normalized()
		bite_hit.clear()
		_go(Act.BITE, BITE_T[phase - 1])
	elif dist > 70.0 or randf() < 0.4:
		aim_dir = (target.global_position - global_position).normalized()
		_go(Act.SPEECH, SPEECH_T[phase - 1])
	else:
		_go(Act.WALK, 0.4)


func _bite() -> void:
	Fx.sweep(get_parent(), global_position + Vector2(0, -10), aim_dir.angle(), BITE_HALF, BITE_REACH, CREAM)
	Audio.sfx("heavy", 0.7, -2.0, tr("The Host bites"))
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or bite_hit.has(hero):
			continue
		var to := hero.global_position - global_position
		if to.length() < BITE_REACH + hero.radius and absf(aim_dir.angle_to(to)) <= BITE_HALF:
			bite_hit.append(hero)
			hero.take_hit(Empire.damage_to_party(roundi(damage * hit_mult())), global_position, 230.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(2.0)


func _speak() -> void:
	var n: int = SPEECH_WORDS[phase - 1]
	var words: Array = HostWord.WORDS.duplicate()
	words.shuffle()
	for i in n:
		var w: HostWord = WordScript.new()
		var a := -SPEECH_SPREAD + SPEECH_SPREAD * 2.0 * float(i) / float(maxi(n - 1, 1))
		w.word = str(words[i % words.size()])
		w.kind = "host"
		w.position = global_position + Vector2(0, -24)
		w.dir = aim_dir.rotated(a)
		w.speed = 115.0 if phase == 1 else 135.0
		w.range_left = 240.0
		w.damage = roundi(word_damage * hit_mult())
		get_parent().add_child(w)
	Audio.sfx("talk", 0.45, -2.0, tr("The Host shouts a volley of words"))


## The breath: heroes slide towards the mouth (harder up close), guests in reach are swallowed and heal it.
func _breathe_in(delta: float) -> void:
	var pull: float = PULL[phase - 1]
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead:
			continue
		var to := global_position - hero.global_position
		var d := to.length()
		if d > PULL_R or d < 4.0:
			continue
		var strength := pull * (1.6 - d / PULL_R)
		hero.global_position += to.normalized() * strength * delta * (0.6 if Assists.gentle_blank() else 1.0)
	for e in _guests():
		var g := e as Enemy
		var d := g.global_position.distance_to(global_position)
		if d <= PULL_R:
			g.global_position = g.global_position.move_toward(global_position, pull * 1.3 * delta)
		if d <= SWALLOW_R:
			_swallow(g)


func _swallow(g: Enemy) -> void:
	g.dead = true
	g.remove_from_group("enemies")
	g.collision_layer = 0
	Fx.burst(get_parent(), g.global_position + Vector2(0, -10), [WINE, CREAM], 10, 60.0)
	g.queue_free()
	var heal := roundi(max_hp * SWALLOW_HEAL)
	hp = mini(max_hp, hp + heal)
	Fx.damage_number(get_parent(), global_position + Vector2(0, -64), "+%d" % heal, Color("8fe08f"))
	Audio.sfx("burst", 0.5, -2.0, tr("The Host swallows a guest"))
	if not told_swallow:
		told_swallow = true
		_say(tr("It ate a guest and healed. Kill the revellers before they reach the mouth."))


func _gulp() -> void:
	Fx.ring(get_parent(), global_position + Vector2(0, -6), GULP_R, CREAM)
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero and not hero.dead and hero.global_position.distance_to(global_position) < GULP_R + hero.radius:
			hero.take_hit(Empire.damage_to_party(roundi(gulp_damage * hit_mult())), global_position, 260.0)


func _guests() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e != null and e != self and not e.dead:
			out.append(e)
	return out


func _call_guests() -> void:
	var scene := get_tree().current_scene
	var mission: Dictionary = scene.get("mission") if scene != null and scene.get("mission") is Dictionary else {}
	for side in [-1.0, 1.0]:
		var p := Vector2(arena.get_center().x + side * arena.size.x * 0.4, arena.position.y + arena.size.y * 0.55)
		for e in EnemyKinds.spawn(get_parent(), p, mission, "reveller"):
			Fx.burst(get_parent(), e.global_position + Vector2(0, -10), [WINE, GOLD], 8, 50.0)
			if scene != null and scene.has_method("_on_enemy_died"):
				e.died.connect(scene._on_enemy_died)


func _start_gulp() -> void:
	var tp: Vector2 = target.global_position if target else global_position
	land_at = Vector2(clampf(tp.x, arena.position.x + 24, arena.end.x - 24), clampf(tp.y, arena.position.y + 40, arena.end.y - 16))
	_go(Act.GULP_UP, JUMP_T)
	Fx.burst(get_parent(), global_position + Vector2(0, -10), [WINE, CREAM], 16, 90.0)
	Audio.sfx("heavy", 0.5, -2.0, tr("The Host leaps"))
	if floor_node != null:
		land_mark = FloorMark.put(self, _paint_landing)
		land_mark.global_position = land_at


func _land() -> void:
	if land_mark != null and is_instance_valid(land_mark):
		land_mark.queue_free()
	land_mark = null
	Fx.ring(get_parent(), global_position, LAND_R, WINE)
	Fx.burst(get_parent(), global_position + Vector2(0, -6), [WINE, GOLD, CREAM], 24, 140.0)
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero and not hero.dead and hero.global_position.distance_to(global_position) < LAND_R + hero.radius:
			hero.take_hit(Empire.damage_to_party(roundi(land_damage * hit_mult())), global_position, 280.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(5.0)


func _paint_landing(ci: CanvasItem) -> void:
	if act != Act.GULP_UP and act != Act.GULP_DOWN:
		return
	var k := clampf(1.0 - act_t / act_total, 0.0, 1.0) if act == Act.GULP_UP else 1.0
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	ci.draw_circle(Vector2.ZERO, LAND_R * (0.3 + 0.7 * k), Color(0, 0, 0, 0.3))
	Telegraph.circle(ci, Vector2.ZERO, LAND_R, k)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _on_death() -> void:
	if land_mark != null and is_instance_valid(land_mark):
		land_mark.queue_free()
	super._on_death()
	for e in _guests():  # the party is over: the last guests sit down where they stand
		(e as Enemy).take_hit(9999, global_position, 0.0)
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(6.0)


func _exit_tree() -> void:
	if land_mark != null and is_instance_valid(land_mark):
		land_mark.queue_free()


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
	var row := Hero.dir_row(aim_dir if act in [Act.BITE, Act.SPEECH] else facing)
	sprite.position = Vector2.ZERO
	sprite.visible = act != Act.GULP_UP or act_t > act_total * 0.8
	if dying_t >= 0.0:
		dying_t += delta
		var long := 2.4
		if art.has("death"):
			art.apply(sprite, "death", Hero.dir_row(Vector2.DOWN), dying_t)
		else:
			art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", row, 1)
			sprite.scale = Vector2(1.0 + 0.5 * dying_t / long, maxf(1.0 - dying_t / long, 0.05))
		modulate.a = clampf(1.0 - maxf(dying_t - long * 0.6, 0.0) / (long * 0.4), 0.0, 1.0)
		if dying_t > long:
			queue_free()
		return
	if flash_t > 0.0 and art.has("hurt") and act != Act.TRANSITION:
		art.apply(sprite, "hurt", row, 0.12 - flash_t)
	else:
		var k := clampf(1.0 - act_t / act_total, 0.0, 0.999)
		match act:
			Act.BITE:
				var n := art.frames_of("attack")
				art.apply_frame(sprite, "attack", row, int(k * float(n)))
			Act.SPEECH:
				var key := "sweep" if art.has("sweep") else "attack"
				art.apply_frame(sprite, key, row, int(k * float(art.frames_of(key))))
			Act.INHALE:
				var key := "inhale" if art.has("inhale") else ("sweep" if art.has("sweep") else "idle")
				art.apply_frame(sprite, key, row, mini(int(k * 3.0), art.frames_of(key) - 1))
				sprite.position = Vector2(randf_range(-0.7, 0.7), 0)
			Act.TRANSITION, Act.CALL:
				var key := "phase" if art.has("phase") else "idle"
				art.apply_frame(sprite, key, Hero.dir_row(Vector2.DOWN), int(k * float(art.frames_of(key))))
				sprite.position = Vector2(randf_range(-0.8, 0.8), 0)
			Act.GULP_UP:
				var key := "gulp" if art.has("gulp") else ("phase" if art.has("phase") else "idle")
				art.apply_frame(sprite, key, row, mini(int(k * 4.0), art.frames_of(key) - 1))
				sprite.position = Vector2(0, -k * 90.0)
			Act.STUCK:
				art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", row, 0)
				sprite.position = Vector2(sin(anim_t * 30.0) * 0.8, 2.0)
			_:
				art.apply(sprite, "walk" if velocity.length() > 5.0 else "idle", row, anim_t)
	sprite.scale = Vector2(1.0 + (0.08 * sin(anim_t * 10.0) if act == Act.INHALE else 0.0), 1.0)
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		draw_shadow(12.0 * modulate.a)
		return
	if act == Act.GULP_UP or act == Act.GULP_DOWN:
		return  # in the air: only the landing mark shows
	if act == Act.BITE:  # the wedge the jaws will close on
		var k := 1.0 - act_t / act_total
		draw_set_transform(Vector2.ZERO, aim_dir.angle(), Vector2(1.0, 0.85))
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in 11:
			pts.append(Vector2.RIGHT.rotated(-BITE_HALF + BITE_HALF * 2.0 * i / 10.0) * BITE_REACH)
		draw_colored_polygon(pts, Color(1, 0.3, 0.3, 0.1 + 0.2 * k))
		draw_polyline(pts + PackedVector2Array([Vector2.ZERO]), Color(Telegraph.EDGE, 0.5 + 0.4 * k), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif act == Act.SPEECH:  # where the words will fly
		var k := 1.0 - act_t / act_total
		var n: int = SPEECH_WORDS[phase - 1]
		for i in n:
			var a := -SPEECH_SPREAD + SPEECH_SPREAD * 2.0 * float(i) / float(maxi(n - 1, 1))
			var d := aim_dir.rotated(a)
			Telegraph.aim(self, d * 16.0, d, 4, 12.0, k)
	elif act == Act.INHALE:  # how far the breath reaches, drawing in
		var k := 1.0 - act_t / act_total
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.7))
		Telegraph.aura(self, Vector2.ZERO, PULL_R, k)
		draw_arc(Vector2.ZERO, PULL_R * (1.0 - k * 0.8), 0, TAU, 40, Color(CREAM, 0.6), 1.5)
		Telegraph.circle(self, Vector2.ZERO, GULP_R, k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_shadow(12.0)
	if art == null:
		draw_rect(Rect2(-12, -48, 24, 46), WINE)


func _draw_overlay() -> void:
	if dying_t >= 0.0 or act == Act.GULP_UP or act == Act.GULP_DOWN:
		return
	if act in [Act.INHALE, Act.TRANSITION, Act.CALL, Act.SPEECH]:
		Telegraph.alert(overlay, Vector2(-3, -82), 12)
	if act == Act.STUCK:
		for i in 3:
			var a := anim_t * 5.0 + TAU * i / 3.0
			overlay.draw_circle(Vector2(cos(a) * 10.0, -70.0 + sin(a) * 3.0), 1.6, CREAM)
	if taunt_t > 0.0:
		overlay.draw_rect(Rect2(-1.5, -84, 3, 3), Color("f2a65a"))
