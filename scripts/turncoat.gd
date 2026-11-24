class_name Turncoat
extends Enemy
## The betrayer, fought with their own kit (issue #186, docs/DESIGN.md section 10 "The betrayal"). Chapter 6:
## midway through the Margin, the companion who took the Vacancy's deal stands in their home written as words
## and fights Ash with everything they fought beside Ash with. Driven by boss_fight.gd (boss "turncoat", the
## mission's objective names "who"), like the Auditor and the Abbot.
##
## Each kit mirrors the hero's own abilities and tech (data/abilities.json, data/techs.json) as boss moves with
## clear tells, so a player who fought beside them knows what is coming:
##   Ottoline  Chucking Out (a shoulder charge down a wide lane), Last Orders (both fists into the floor: a
##             ring round her), tech Through the Door (one huge punch, a slow wedge).
##   Daro      Long Thrust (a long narrow lunge), Pike Sweep (a wide wedge up close), tech Skewer (a line the
##             length of the arena; two in phase 2, Twin Prongs).
##   Odile     Levy (a ring that drains and heals her), Audit (a seal on the ground: whoever stands in it
##             takes half again from her for a while), tech Final Demand (a great seal lands where you stand
##             and Audits whoever it misses).
## Phase 2 at half health: the Vacancy writes them over (a short untouchable beat, the phase2 talk), their tech
## joins the moves and everything comes a little faster. They never die: at zero they go down on one knee
## and the boss fight's outro asks Ash's gesture.
##
## The tell that it isn't quite them: a black bar over the eyes, like a redacted word, and static at the edges.

signal phase_changed(phase: int)

enum Act { DORMANT, WALK, WIND, DASH, TRANSITION }

const PHASE2_AT := 0.5
const TRANSITION_T := 2.0
const INK := Color("15101a")
const PAPER := Color("ebe7dc")
## who -> hp, walk speed, basic swing (reach px, half-angle rad, damage, wind-up s), the two ability moves, the
## tech, and the colour of their tells (their trail colour).
const KITS := {
	"ottoline": {
		"hp": 980, "speed": 44.0, "swing": [34.0, 0.75, 13, 0.6], "color": "f07ab8",
		"moves": ["chucking_out", "last_orders"], "tech": "through_the_door",
	},
	"ninefingers": {
		"hp": 820, "speed": 52.0, "swing": [50.0, 0.32, 12, 0.5], "color": "e8c65a",
		"moves": ["long_thrust", "pike_sweep"], "tech": "skewer",
	},
	"odile": {
		"hp": 780, "speed": 44.0, "swing": [36.0, 0.9, 10, 0.55], "color": "e8c45a",
		"moves": ["levy", "audit"], "tech": "final_demand",
	},
}
## move -> shape and numbers. lane: a dash of `len` px, `w` wide. ring: radius around them. wedge: reach and
## half-angle in front. seal: a circle of radius `r` where the target stands. line: from them across the arena.
## wind: seconds of tell (phase 1, phase 2). Damage is before Empire.damage_to_party.
const MOVES := {
	"chucking_out": {"shape": "lane", "len": 130.0, "w": 26.0, "damage": 17, "knock": 430.0, "wind": [0.95, 0.75], "name": "Chucking Out"},
	"last_orders": {"shape": "ring", "r": 58.0, "damage": 13, "knock": 220.0, "wind": [1.05, 0.85], "name": "Last Orders"},
	"through_the_door": {"shape": "wedge", "reach": 62.0, "half": 0.5, "damage": 26, "knock": 620.0, "wind": [1.3, 1.15], "name": "Through the Door"},
	"long_thrust": {"shape": "lane", "len": 165.0, "w": 14.0, "damage": 16, "knock": 260.0, "wind": [0.85, 0.7], "name": "Long Thrust"},
	"pike_sweep": {"shape": "wedge", "reach": 58.0, "half": 0.85, "damage": 13, "knock": 280.0, "wind": [0.8, 0.65], "name": "Pike Sweep"},
	"skewer": {"shape": "line", "w": 16.0, "damage": 21, "knock": 300.0, "wind": [1.1, 0.95], "name": "Skewer"},
	"levy": {"shape": "ring", "r": 72.0, "damage": 9, "knock": 80.0, "wind": [1.0, 0.85], "heal": 3.0, "name": "Levy"},
	"audit": {"shape": "seal", "r": 52.0, "damage": 0, "knock": 0.0, "wind": [0.9, 0.75], "audit": 6.0, "name": "Audit"},
	"final_demand": {"shape": "seal", "r": 48.0, "damage": 23, "knock": 320.0, "wind": [1.15, 1.0], "audit": 6.0, "audit_r": 96.0, "name": "Final Demand"},
}
const AUDIT_MULT := 1.5
const DASH_SPEED := 340.0

var who := "ottoline"
var kit := {}
var act: int = Act.DORMANT
var act_t := 0.0
var act_total := 1.0
var phase := 1
var move := ""  # the move being wound up or thrown ("swing" for the plain attack)
var aim_dir := Vector2.DOWN
var aim_at := Vector2.ZERO  # where a seal lands
var dash_left := 0.0
var hit_this: Array = []
var floor_node: Node
var arena := Rect2(0, 0, 576, 416)
var tech_t := 6.0
var since_move := 0  # plain swings since the last ability
var audited := {}  # Hero -> seconds left: takes AUDIT_MULT from this fight's hits
var tint := Color.WHITE
var face_y := -22.0


func _ready() -> void:
	kit = KITS.get(who, KITS["ottoline"])
	art_id = who
	super._ready()
	boss = true  # shrugs off stuns and always knows where everyone is, as the Auditor and the Abbot do
	max_hp = int(kit["hp"])
	hp = max_hp
	xp = 100
	radius = 9.0
	move_speed = float(kit["speed"])
	tint = Color(kit["color"])
	number_color = Color(0.92, 0.9, 0.86)
	if art != null and art.face_rect.size != Vector2i.ZERO:
		face_y = float(art.face_rect.position.y) + float(art.face_rect.size.y) * 0.52 - art.feet.y
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 7.0


func wake() -> void:
	if act == Act.DORMANT:
		_go(Act.WALK, 0.6)


func _go(a: int, t: float) -> void:
	act = a
	act_t = t
	act_total = maxf(t, 0.01)


func ratio() -> float:
	return float(hp) / float(max_hp)


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if act == Act.DORMANT or act == Act.TRANSITION or dying_t >= 0.0:
		if not dead and flash_t <= 0.0 and act == Act.TRANSITION:
			Fx.damage_number(get_parent(), global_position + Vector2(0, -44), tr("no effect"), Color(0.8, 0.8, 0.8))
			flash_t = 0.05
		return false
	var hit := super.take_hit(amount, from, force * 0.12)
	if hit and not dead and phase == 1 and ratio() <= PHASE2_AT:
		_start_phase2()
	return hit


func _on_hit() -> void:
	pass  # no stagger: they know this fight too well to flinch


func _start_phase2() -> void:
	phase = 2
	_go(Act.TRANSITION, TRANSITION_T)
	tech_t = 2.5
	Fx.burst(get_parent(), global_position + Vector2(0, -24), [PAPER, INK], 22, 110.0)
	phase_changed.emit(2)


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	delta *= Assists.pace()  # enemy speed assist (issue #192)
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	taunt_t = maxf(taunt_t - delta, 0.0)
	act_t -= delta
	for h in audited.keys():
		audited[h] = float(audited[h]) - delta
		if audited[h] <= 0.0 or not is_instance_valid(h):
			audited.erase(h)
	if act != Act.DORMANT and (target == null or target.dead or taunt_t > 0.0):
		target = _find_target(2000.0)
	if phase == 2 and act == Act.WALK:
		tech_t -= delta
	var dir := Vector2.ZERO
	match act:
		Act.WALK:
			if target:
				var to := target.global_position - global_position
				facing = facing.slerp(to.normalized(), minf(1.0, delta * 5.0)).normalized()
				if to.length() > float(kit["swing"][0]) * 0.8:
					dir = to.normalized()
				if act_t <= 0.0:
					_choose()
		Act.WIND:
			var k := 1.0 - act_t / act_total
			if k < 0.6 and target:  # they track you for most of the tell, then commit
				aim_dir = aim_dir.slerp((target.global_position - global_position).normalized(), minf(1.0, delta * 6.0)).normalized()
				if MOVES.get(move, {}).get("shape", "") == "seal":
					aim_at = aim_at.lerp(target.global_position, minf(1.0, delta * 5.0))
			facing = aim_dir
			if act_t <= 0.0:
				_release()
		Act.DASH:
			facing = aim_dir
			dir = aim_dir
			var step := DASH_SPEED * delta
			dash_left -= step
			_lane_hits(MOVES[move])
			if dash_left <= 0.0 or act_t <= 0.0:
				_go(Act.WALK, 0.8 if phase == 1 else 0.55)
		Act.TRANSITION:
			if act_t <= 0.0:
				_go(Act.WALK, 0.3)
	var speed := move_speed * (1.15 if phase == 2 else 1.0)
	if act == Act.DASH:
		speed = DASH_SPEED
	velocity = dir * speed + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	_slide()
	if act == Act.DASH:  # a charge stops at the arena's edge
		global_position = global_position.clamp(arena.position + Vector2(10, 20), arena.end - Vector2(10, 4))
	queue_redraw()


## Next move: the tech when it is ready (phase 2), an ability every couple of swings or when the target is out
## of reach, else a plain swing.
func _choose() -> void:
	var dist := target.global_position.distance_to(global_position)
	var moves: Array = kit["moves"]
	if phase == 2 and tech_t <= 0.0:
		tech_t = randf_range(8.0, 10.5)
		_wind(str(kit["tech"]))
	elif since_move >= 2 or dist > 110.0:
		since_move = 0
		_wind(_best_move(moves, dist))
	elif dist <= float(kit["swing"][0]) + 14.0:
		since_move += 1
		_wind("swing")
	else:
		_go(Act.WALK, 0.35)


## The ability that fits the range: a ring or wedge up close, a lane or seal from afar.
func _best_move(moves: Array, dist: float) -> String:
	var near := []
	var far := []
	for m in moves:
		var shape: String = MOVES[m]["shape"]
		(near if shape in ["ring", "wedge"] else far).append(m)
	if dist < 70.0 and not near.is_empty():
		return near[randi() % near.size()] if randf() < 0.75 or far.is_empty() else far[0]
	return far[randi() % far.size()] if not far.is_empty() else near[0]


func _wind(m: String) -> void:
	move = m
	hit_this.clear()
	if target:
		aim_dir = (target.global_position - global_position).normalized()
		aim_at = target.global_position
	var wind: float = float(kit["swing"][3]) if m == "swing" else float(MOVES[m]["wind"][phase - 1])
	_go(Act.WIND, wind)
	if m != "swing":
		Audio.sfx("burst", 0.25)


func _release() -> void:
	if move == "swing":
		var sw: Array = kit["swing"]
		Fx.sweep(get_parent(), global_position + Vector2(0, -10), aim_dir.angle(), float(sw[1]), float(sw[0]), tint)
		_wedge_hits(float(sw[0]), float(sw[1]), int(sw[2]), 220.0)
		_go(Act.WALK, 0.55 if phase == 1 else 0.4)
		return
	var mv: Dictionary = MOVES[move]
	match str(mv["shape"]):
		"lane":
			dash_left = float(mv["len"])
			_go(Act.DASH, float(mv["len"]) / DASH_SPEED + 0.1)
			Fx.burst(get_parent(), global_position + Vector2(0, -10), [tint, PAPER], 10, 80.0)
			return
		"wedge":
			Fx.sweep(get_parent(), global_position + Vector2(0, -10), aim_dir.angle(), float(mv["half"]), float(mv["reach"]), tint)
			_wedge_hits(float(mv["reach"]), float(mv["half"]), int(mv["damage"]), float(mv["knock"]))
			_shake(3.0 if move == "through_the_door" else 1.5)
		"ring":
			Fx.ring(get_parent(), global_position + Vector2(0, -4), float(mv["r"]), tint)
			var drained := 0
			for hero: Hero in _heroes():
				if hero.global_position.distance_to(global_position) < float(mv["r"]) + hero.radius:
					if _hurt(hero, int(mv["damage"]), float(mv["knock"]), global_position):
						drained += int(mv["damage"])
			if mv.has("heal") and drained > 0:  # Levy: what they pay, she keeps
				var gain := int(drained * float(mv["heal"]))
				hp = mini(hp + gain, max_hp if phase == 2 else maxi(hp, int(max_hp * PHASE2_AT) + 1))
				Fx.damage_number(get_parent(), global_position + Vector2(0, -46), "+%d" % gain, tint)
			_shake(2.0)
		"seal":
			Fx.ring(get_parent(), aim_at, float(mv["r"]), tint)
			Fx.burst(get_parent(), aim_at + Vector2(0, -6), [tint, INK, PAPER], 16, 90.0)
			for hero: Hero in _heroes():
				var d := hero.global_position.distance_to(aim_at)
				if d < float(mv["r"]) + hero.radius and int(mv["damage"]) > 0:
					_hurt(hero, int(mv["damage"]), float(mv["knock"]), aim_at)
				elif d < float(mv.get("audit_r", mv["r"])) + hero.radius:
					audited[hero] = float(mv["audit"])
			if int(mv["damage"]) <= 0:
				for hero: Hero in _heroes():
					if hero.global_position.distance_to(aim_at) < float(mv["r"]) + hero.radius:
						audited[hero] = float(mv["audit"])
			_shake(2.5 if int(mv["damage"]) > 0 else 0.0)
		"line":
			var offsets := [0.0] if phase == 1 else [-18.0, 18.0]  # Twin Prongs in phase 2
			for off in offsets:
				var side := aim_dir.orthogonal() * float(off)
				Fx.sweep(get_parent(), global_position + side + Vector2(0, -10), aim_dir.angle(), 0.04, 320.0, tint)
				for hero: Hero in _heroes():
					var rel := hero.global_position - (global_position + side)
					var along := rel.dot(aim_dir)
					if along > -6.0 and absf(rel.dot(aim_dir.orthogonal())) < float(mv["w"]) / 2.0 + hero.radius:
						_hurt(hero, int(mv["damage"]), float(mv["knock"]), global_position)
			_shake(2.0)
	_go(Act.WALK, 0.85 if phase == 1 else 0.6)


func _heroes() -> Array:
	var out := []
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero != null and not hero.dead and not hit_this.has(hero):
			out.append(hero)
	return out


## One hit on a hero: once per move, half as much again on anyone this fight has Audited.
func _hurt(hero: Hero, damage: int, knock: float, from: Vector2) -> bool:
	if hit_this.has(hero):
		return false
	hit_this.append(hero)
	var amount := float(damage) * (AUDIT_MULT if audited.has(hero) else 1.0)
	return hero.take_hit(Empire.damage_to_party(int(round(amount))), from, knock)


func _wedge_hits(reach: float, half: float, damage: int, knock: float) -> void:
	for hero: Hero in _heroes():
		var to := hero.global_position - global_position
		if to.length() < reach + hero.radius and absf(aim_dir.angle_to(to)) <= half:
			_hurt(hero, damage, knock, global_position)


func _lane_hits(mv: Dictionary) -> void:
	for hero: Hero in _heroes():
		if hero.global_position.distance_to(global_position) < float(mv["w"]) / 2.0 + hero.radius + 6.0:
			_hurt(hero, int(mv["damage"]), float(mv["knock"]), global_position - aim_dir * 8.0)


func _shake(amount: float) -> void:
	if amount <= 0.0:
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("shake"):
		scene.shake(amount)


## Zero health: they go down on one knee and stay there for the outro and Ash's gesture. Not a death.
func _on_death() -> void:
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0
	audited.clear()
	Fx.burst(get_parent(), global_position + Vector2(0, -20), [PAPER, INK], 18, 90.0)
	_shake(4.0)


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if art == null:
		queue_redraw()
		return
	var row := Hero.dir_row(aim_dir if act == Act.WIND or act == Act.DASH else facing)
	sprite.position = Vector2.ZERO
	if dying_t >= 0.0:
		dying_t += delta
		var key := "ko" if art.has("ko") else "hurt"
		var n := art.frames_of(key)
		art.apply_frame(sprite, key, Hero.dir_row(Vector2.DOWN), mini(int(dying_t * 8.0), n - 1))
		sprite.modulate = Color.WHITE
		queue_redraw()
		overlay.queue_redraw()
		return
	var k := clampf(1.0 - act_t / act_total, 0.0, 0.999)
	if flash_t > 0.0 and art.has("hurt") and act == Act.WALK:
		art.apply(sprite, "hurt", row, 0.12 - flash_t)
	else:
		match act:
			Act.WIND:
				var key := "attack" if move == "swing" else ("tech" if move == str(kit["tech"]) and art.has("tech") else ("cast" if art.has("cast") else "attack"))
				# Hold the first frames through the tell, then play the rest as it lands.
				var n := art.frames_of(key)
				art.apply_frame(sprite, key, row, clampi(int(k * float(n) * 0.5), 0, n - 1))
				sprite.position = Vector2(randf_range(-0.6, 0.6), 0) if k > 0.5 else Vector2.ZERO
			Act.DASH:
				var n := art.frames_of("attack")
				art.apply_frame(sprite, "attack", row, n - 2)
			Act.TRANSITION:
				art.apply_frame(sprite, "hurt" if art.has("hurt") else "idle", Hero.dir_row(Vector2.DOWN), 1)
				sprite.position = Vector2(randf_range(-1.0, 1.0), 0)
			_:
				art.apply(sprite, "walk" if velocity.length() > 5.0 else "idle", row, anim_t)
	# Written over: a shade paler than life, flickering to paper while the Vacancy rewrites them.
	if act == Act.TRANSITION and not Access.reduce_flashing:
		sprite.modulate = Color(1.5, 1.5, 1.5) if fmod(anim_t, 0.2) < 0.1 else Color(0.9, 0.9, 0.92)
	else:
		sprite.modulate = Color(0.94, 0.93, 0.95)
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	draw_shadow(9.0)
	if dying_t >= 0.0 or act != Act.WIND:
		return
	var k := 1.0 - act_t / act_total
	var edge := Color(Telegraph.EDGE, 0.5 + 0.4 * k)
	var fill := Color(1, 0.3, 0.3, 0.1 + 0.2 * k)
	if move == "swing":
		_draw_wedge(float(kit["swing"][0]), float(kit["swing"][1]), fill, edge)
		return
	var mv: Dictionary = MOVES[move]
	match str(mv["shape"]):
		"lane":
			var lane := Rect2(0, -float(mv["w"]) / 2.0, float(mv["len"]), float(mv["w"]))
			draw_set_transform(Vector2.ZERO, aim_dir.angle(), Vector2.ONE)
			draw_rect(lane, fill)
			draw_rect(lane, edge, false, 1.0)
			draw_rect(Rect2(lane.position, Vector2(lane.size.x * k, lane.size.y)), Color(tint, 0.25))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"wedge":
			_draw_wedge(float(mv["reach"]), float(mv["half"]), fill, edge)
		"ring":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.8))
			Telegraph.circle(self, Vector2.ZERO, float(mv["r"]), k)
			draw_arc(Vector2.ZERO, float(mv["r"]) * k, 0, TAU, 40, Color(tint, 0.9), 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"seal":
			var c := aim_at - global_position
			draw_set_transform(c, 0.0, Vector2(1.0, 0.8))
			Telegraph.circle(self, Vector2.ZERO, float(mv["r"]), k)
			draw_arc(Vector2.ZERO, float(mv["r"]) * 0.55, 0, TAU, 24, Color(tint, 0.5 + 0.4 * k), 1.5)
			if mv.has("audit_r"):
				draw_arc(Vector2.ZERO, float(mv["audit_r"]), 0, TAU, 48, Color(tint, 0.35), 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"line":
			var offsets := [0.0] if phase == 1 else [-18.0, 18.0]
			draw_set_transform(Vector2.ZERO, aim_dir.angle(), Vector2.ONE)
			for off in offsets:
				var r := Rect2(0, float(off) - float(mv["w"]) / 2.0, 320.0, float(mv["w"]))
				draw_rect(r, fill)
				draw_rect(r, edge, false, 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wedge(reach: float, half: float, fill: Color, edge: Color) -> void:
	draw_set_transform(Vector2.ZERO, aim_dir.angle(), Vector2(1.0, 0.85))
	var pts := PackedVector2Array([Vector2.ZERO])
	for i in 13:
		pts.append(Vector2.RIGHT.rotated(-half + half * 2.0 * i / 12.0) * reach)
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([Vector2.ZERO]), edge, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	if dying_t >= 0.0:
		return
	# The redaction bar over the eyes (not from behind), and static at the edges: written over.
	var row := Hero.dir_row(facing)
	if row != 3 and row != 4 and row != 5:
		var side := 0.0 if row == 0 else (2.0 if row in [1, 2] else -2.0)
		overlay.draw_rect(Rect2(Vector2(-5.5 + side, face_y - 1.5), Vector2(11, 3)), INK)
	var rng := RandomNumberGenerator.new()
	rng.seed = static_seed + int(anim_t * (2.0 if Access.reduce_flashing else 10.0))
	for i in 4:
		var p := Vector2(rng.randf_range(-11, 11), rng.randf_range(-34, 0))
		overlay.draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.9) if i % 2 else Color(0, 0, 0, 0.7))
	# Audited heroes carry a little seal over their heads while it lasts.
	for h in audited:
		if is_instance_valid(h):
			var at: Vector2 = (h as Node2D).global_position - global_position + Vector2(0, -34)
			overlay.draw_circle(at, 3.0, Color(tint, 0.9))
			overlay.draw_arc(at, 3.0, 0, TAU, 12, INK, 1.0)
	if act == Act.WIND:
		Telegraph.alert(overlay, Vector2(-3, face_y - 22.0), 11)
		if move != "swing":  # the move's name over their head, in their colour: you have seen it a hundred times
			var f := ThemeDB.fallback_font
			var s: String = tr(str(MOVES[move]["name"]))
			var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
			var at := Vector2(-w / 2.0, face_y - 30.0)
			overlay.draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), 2, Color(0, 0, 0, 0.8))
			overlay.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), tint.lightened(0.3))
	if taunt_t > 0.0:
		overlay.draw_rect(Rect2(-1.5, face_y - 26.0, 3, 3), Color("f2a65a"))
