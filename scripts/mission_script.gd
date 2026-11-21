class_name MissionScript
extends MissionObjectives
## The "script" objective kind (issue #113): a hand-built mission played as a list of steps, used by the
## personal missions (data/personal.json, PersonalMissions). Objective hands it the mission's objective:
##   {"kind": "script", "steps": [...], "escort": "<recruit id>" (optional), "label": "..."}
##
## Steps (each may also carry "banter": [[who, text], ...] played at the top of the screen as it starts,
## "say": a HUD line, "creep": px/s the Blank's wall advances from then on, and "label": the HUD goal line):
##   talk   {"talk": id}                         a conversation in the dialogue box (skipped once seen)
##   goto   {"at": spot}                         walk there
##   clear  {"at": spot, "spawn": {kind: weight}, "count": n, "elite": {...}}  beat what turns up there
##   hold   {"at": spot, "seconds": s, "spawn": {...}, "every": s, "protect": {"name", "hp"}}  last it out
##   use    {"at": spot or [spots], "seconds": s, "by": "party" | "escort", "spawn", "every"}  work at it
##   exit   {}                                   walk back to where you came in
## spot: the name of an @spot line in the map (first entry), "start", or [x, y] in tiles.
## elite: {"kind": enemy kind, "name": "Big Wendel", "hp": x max HP, "damage": x damage}: a named enemy
## with a bar at the top of the screen. The escort fails the mission if they stay down for DOWN_LIMIT
## seconds; the party revives them by standing next to them with nothing close, like a fallen hero.

const DOWN_LIMIT := 20.0
const GOTO_RANGE := 30.0
const AROUND := [44.0, 78.0]
const MAX_ALIVE := 10

var steps: Array = []
var step := -1
var st := {}  # the running step
var step_t := 0.0
var spawn_wait := 0.0
var wave: Array = []  # the enemies a clear step is waiting on
var elite: Enemy = null
var elite_name := ""
var works: Array = []  # Cache nodes for a use step
var guarded: Guarded = null
var creep := 0.0
var escort: Escort = null
var down_t := 0.0
var talking := false
var overlay: Control


func setup(p_obj: Dictionary, p_main) -> void:
	obj = p_obj
	kind = "script"
	main = p_main
	steps = obj.get("steps", [])
	start_blank_x = main.blank.base_x
	exit_pos = main.area.party_start
	main.respawn_t = 1e9  # the steps decide who turns up, not the Blank's usual stream
	if obj.get("escort", "") != "":
		_spawn_escort(str(obj["escort"]))
	if restore.has("blank_x"):
		main.blank.base_x = float(restore["blank_x"])
		start_blank_x = maxf(start_blank_x, main.blank.base_x)
		Art.set_blank_x(main.blank.base_x)
	creep = float(restore.get("creep", 0.0))
	pointer = MissionObjectives.Pointer.new()
	pointer.obj = self
	main.hud.get_parent().add_child(pointer)
	overlay = Overlay.new()
	overlay.run = self
	main.hud.get_parent().add_child(overlay)
	_begin(int(restore.get("step", 0)))


func _spawn_escort(rid: String) -> void:
	var look: Dictionary = Empire.recruit(rid).get("look", {})
	escort = Escort.new()
	escort.hero_name = Empire.short_name(rid)
	escort.hero_id = rid
	escort.outfit = look.get("outfit", "archer")
	var cols := {}
	for k in look.get("colors", {}):
		cols[k] = Color(look["colors"][k])
	if not cols.is_empty():
		escort.colors = cols
	escort.move_speed = 64.0
	escort.party = main
	escort.position = main.area.party_start + Vector2(-14, 24)
	escort.add_to_group("heroes")
	main.entities.add_child(escort)
	escort.max_hp = int(obj.get("escort_hp", 70))
	escort.hp = escort.max_hp


## A step's spot in world pixels.
func spot(at) -> Vector2:
	if at is Array and at.size() == 2 and not (at[0] is String):
		return _tile(at)
	var name := str(at)
	if name == "start" or name == "":
		return main.area.party_start
	var list: Array = main.area.spots.get(name, [])
	if list.is_empty():
		push_warning("Mission script: no @spot %s in %s" % [name, main.map_path])
		return main.area.party_start
	var v: Vector2i = list[0]
	return Vector2(v.x * 16 + 8, v.y * 16 + 8)


func _begin(i: int) -> void:
	_cleanup()
	step = i
	step_t = 0.0
	if step >= steps.size():
		end_t = 1.6 - 0.8  # a short beat, then the results
		return
	st = steps[step]
	if st.has("creep"):
		creep = float(st["creep"])
	if st.has("banter"):
		main.banter.add(st["banter"])
	if st.has("say"):
		main.hud.say(str(st["say"]), 3.5)
	spawn_wait = float(st.get("first", 1.0))
	match str(st.get("do", "")):
		"talk":
			var id := str(st.get("talk", ""))
			if id == "" or Dialogue.is_seen("talk:" + id) or Dialogue.talk(id).is_empty():
				_begin(step + 1)
				return
			talking = true
			main.play_talk(id)
		"clear":
			var at := spot(st.get("at", "start"))
			for n in int(st.get("count", 3)):
				wave.append_array(_spawn_at(_around(at)))
			if st.has("elite"):
				_spawn_elite(st["elite"], at)
		"hold":
			if st.has("protect"):
				var pr: Dictionary = st["protect"]
				guarded = Guarded.new()
				guarded.label = str(pr.get("name", ""))
				guarded.max_hp = int(pr.get("hp", 80))
				guarded.hp = guarded.max_hp
				guarded.position = spot(st.get("at", "start"))
				main.entities.add_child(guarded)
		"use":
			var ats: Array = st["at"] if st.get("at") is Array and (st["at"] as Array).size() > 0 and st["at"][0] is String else [st.get("at", "start")]
			for a in ats:
				var c := Cache.new()
				c.style = "work"
				c.label = str(st.get("work_label", ""))
				c.open_time = float(st.get("seconds", 2.0))
				c.position = spot(a)
				main.entities.add_child(c)
				works.append(c)
			if st.get("by", "party") == "escort" and escort != null:
				escort.go_to(works[0].position + Vector2(0, 2))


func _cleanup() -> void:
	for c in works:
		if is_instance_valid(c):
			c.queue_free()
	works.clear()
	wave.clear()
	if guarded != null and is_instance_valid(guarded):
		guarded.queue_free()
	guarded = null
	if escort != null:
		escort.follow()
	talking = false


func _around(at: Vector2) -> Vector2:
	var p := at + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(AROUND[0], AROUND[1])
	return Vector2(clampf(p.x, 40.0, minf(main.world.x - 40.0, main.blank.edge_x(p.y) - 20.0)), clampf(p.y, 40.0, main.world.y - 40.0))


func _spawn_at(pos: Vector2) -> Array:
	var roster := {"enemies": st.get("spawn", {"nibbler": 1}), "province": main.mission.get("province", "")}
	var out := EnemyKinds.spawn(main.entities, pos, roster)
	for e in out:
		e.died.connect(main._on_enemy_died)
		if guarded != null:
			e.goal = guarded
	Fx.burst(main.entities, pos + Vector2(0, -6), [Color("3a3040"), Color("f3efe4")], 6, 40.0)
	return out


func _spawn_elite(d: Dictionary, at: Vector2) -> void:
	var roster := {"enemies": {str(d.get("kind", "enforcer")): 1}}
	var out := EnemyKinds.spawn(main.entities, at + Vector2(0, -20), roster, str(d.get("kind", "enforcer")))
	if out.is_empty():
		return
	elite = out[0]
	elite_name = str(d.get("name", "?"))
	elite.max_hp = int(elite.max_hp * float(d.get("hp", 3.0)))
	elite.hp = elite.max_hp
	if elite.get("damage") != null:
		elite.set("damage", int(int(elite.get("damage")) * float(d.get("damage", 1.4))))
	elite.xp = int(elite.xp * 4)
	elite.scale = Vector2(1.2, 1.2)
	elite.died.connect(main._on_enemy_died)
	wave.append(elite)
	for e in out.slice(1):
		e.died.connect(main._on_enemy_died)
		wave.append(e)


func on_kill() -> void:
	pass


func update(delta: float) -> void:
	if fail_why != "":
		return
	if end_t >= 0.0:
		end_t += delta
		_move_blank(260.0 * delta)
		return
	_update_escort(delta)
	if fail_why != "":
		return
	if creep > 0.0:
		_move_blank(-creep * delta)
		if escort != null and not escort.dead and main.blank.edge_x(escort.position.y) <= escort.position.x + 4.0:
			fail_why = tr("The white closed over %s.") % escort.hero_name
			return
	step_t += delta
	var done := false
	match str(st.get("do", "")):
		"talk":
			done = not main.dialogue_box.visible
		"goto":
			done = main.leader != null and main.leader.global_position.distance_to(spot(st.get("at", "start"))) < float(st.get("range", GOTO_RANGE))
		"clear":
			wave = wave.filter(func(e): return is_instance_valid(e) and not e.dead)
			done = wave.is_empty()
		"hold":
			_pressure(delta)
			if guarded != null:
				if guarded.hp <= 0:
					fail_why = str(st.get("fail", tr("%s did not hold.") % guarded.label.capitalize()))
					return
				if main.blank.edge_x(guarded.position.y) <= guarded.position.x + 4.0:
					fail_why = tr("The white swallowed %s.") % guarded.label
					return
			done = step_t >= float(st.get("seconds", 30.0))
		"use":
			_pressure(delta)
			var who: Array = [escort] if st.get("by", "party") == "escort" and escort != null else main.heroes.filter(func(h): return not h.dead)
			var all_done := true
			for c in works:
				(c as Cache).work(delta, who)
				all_done = all_done and (c as Cache).done
			done = all_done
		"exit":
			done = main.leader != null and main.leader.global_position.distance_to(exit_pos) < EXIT_RANGE \
				and (escort == null or escort.dead or escort.global_position.distance_to(exit_pos) < EXIT_RANGE * 2.5)
		_:
			done = true
	if done:
		if st.has("done_say"):
			main.hud.say(str(st["done_say"]), 3.0)
		if st.has("done_banter"):
			main.banter.add(st["done_banter"])
		_begin(step + 1)


## Keeps enemies coming during hold and use steps (spawn + every), from around the spot or the Blank's edge.
func _pressure(delta: float) -> void:
	if not st.has("spawn"):
		return
	spawn_wait -= delta
	if spawn_wait > 0.0:
		return
	spawn_wait = float(st.get("every", 4.0))
	if main.get_tree().get_nodes_in_group("enemies").size() >= MAX_ALIVE:
		return
	var at := spot(st.get("at", "start")) if not (st.get("at") is Array and st["at"].size() > 0 and st["at"][0] is String) else spot(st["at"][0])
	var pos := _edge_point(at.y, 90.0) if st.get("from", "around") == "edge" else _around(at)
	_spawn_at(pos)


func _update_escort(delta: float) -> void:
	if escort == null:
		return
	if not escort.dead:
		down_t = 0.0
		return
	down_t += delta
	var near_enemy := false
	for e in main.get_tree().get_nodes_in_group("enemies"):
		if (e as Node2D).global_position.distance_to(escort.global_position) < 110.0:
			near_enemy = true
			break
	if main.leader and not near_enemy and main.leader.global_position.distance_to(escort.global_position) < 28.0:
		escort.revive_progress += delta
		if escort.revive_progress >= Hero.REVIVE_TIME:
			escort.revive()
			escort.hp = maxi(escort.hp, escort.max_hp / 2)
			main.hud.say(tr("%s is back on their feet. Shaky, but walking.") % escort.hero_name, 2.5)
	else:
		escort.revive_progress = maxf(escort.revive_progress - delta, 0.0)
	if down_t > DOWN_LIMIT:
		fail_why = tr("%s went down and stayed down. You carried them home.") % escort.hero_name


func text() -> String:
	if end_t >= 0.0 or step >= steps.size():
		return tr("Done")
	var label := str(st.get("label", ""))
	match str(st.get("do", "")):
		"talk":
			return label
		"clear":
			var left := wave.filter(func(e): return is_instance_valid(e) and not e.dead).size()
			return tr("%s   (%d left)") % [label, left]
		"hold":
			var s := "%s   (%d s)" % [label, ceili(maxf(float(st.get("seconds", 30.0)) - step_t, 0.0))]
			if guarded != null:
				s += "   %s %d/%d" % [guarded.label, guarded.hp, guarded.max_hp]
			return s
		"use":
			if works.size() > 1:
				return "%s   (%d/%d)" % [label, works.filter(func(c): return c.done).size(), works.size()]
			var pct := int((works[0] as Cache).progress * 100.0) if not works.is_empty() else 0
			return "%s   (%d%%)" % [label, pct]
	return label


func target_pos():
	if end_t >= 0.0 or fail_why != "" or step >= steps.size():
		return null
	if escort != null and escort.dead:
		return escort.global_position
	match str(st.get("do", "")):
		"goto", "hold":
			return spot(st.get("at", "start"))
		"clear":
			if elite != null and is_instance_valid(elite) and not elite.dead:
				return elite.global_position
			for e in wave:
				if is_instance_valid(e) and not e.dead:
					return e.global_position
		"use":
			for c in works:
				if not c.done:
					return c.global_position
		"exit":
			return exit_pos
	return null


func exit_visible() -> bool:
	return end_t < 0.0 and step < steps.size() and str(st.get("do", "")) == "exit"


func result_info() -> Dictionary:
	return {"step": step}


func save_state() -> Dictionary:
	return {"step": maxi(step, 0), "blank_x": main.blank.base_x, "creep": creep}


## Something on the map the party has to keep standing during a hold step (a door, a tree, a stage).
## Enemies make for it and gnaw at it like a Defense wardstone.
class Guarded extends StaticBody2D:
	var label := ""
	var max_hp := 80
	var hp := 80
	var flash_t := 0.0

	func _ready() -> void:
		collision_layer = 0

	func nibble(amount: int) -> void:
		if hp <= 0:
			return
		hp = maxi(hp - amount, 0)
		flash_t = 0.15
		Fx.damage_number(get_parent(), global_position + Vector2(0, -30), str(amount), Color("8ad1ff"))

	func _process(delta: float) -> void:
		flash_t = maxf(flash_t - delta, 0.0)
		queue_redraw()

	func _draw() -> void:
		var ratio := float(hp) / max_hp
		draw_arc(Vector2(0, -4), 14.0, 0, TAU, 32, Color(0.55, 0.82, 1.0, 0.25 + 0.4 * ratio) if flash_t <= 0.0 else Access.flash(Color(0.55, 0.82, 1.0)), 1.5)
		draw_rect(Rect2(-14, -40, 28, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-14, -40, 28.0 * ratio, 3), Color("8ad1ff"))


## The named enemy's bar at the top of the screen, and the escort's health under the goal line.
class Overlay extends Control:
	var run  # MissionScript

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var vs := get_viewport_rect().size
		var f := ThemeDB.fallback_font
		var e: Enemy = run.elite
		if e != null and is_instance_valid(e) and not e.dead:
			var w := minf(vs.x * 0.5, 320.0)
			var r := Rect2((vs.x - w) / 2.0, 30.0, w, 6.0)
			draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(r.position, Vector2(w * float(e.hp) / e.max_hp, r.size.y)), Color("d9534f"))
			var nw := f.get_string_size(run.elite_name, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
			draw_string_outline(f, Vector2((vs.x - nw) / 2.0, 26.0), run.elite_name, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), 3, Color(0, 0, 0, 0.85))
			draw_string(f, Vector2((vs.x - nw) / 2.0, 26.0), run.elite_name, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), Color("ffe7a3"))
		var es: Escort = run.escort
		if es != null:
			var x := 8.0
			var y := vs.y - 58.0
			var txt := "%s%s" % [es.hero_name, tr("  DOWN: get to them") if es.dead else ""]
			draw_string_outline(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), 3, Color(0, 0, 0, 0.85))
			draw_string(f, Vector2(x, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color("ff9b8a") if es.dead else Color("f3efe4"))
			draw_rect(Rect2(x, y + 3, 80, 4), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(x, y + 3, 80.0 * float(es.hp) / maxf(es.max_hp, 1), 4), Color("9fe07a"))
			if es.dead:
				var left := maxf(DOWN_LIMIT - run.down_t, 0.0)
				draw_rect(Rect2(x, y + 9, 80.0 * left / DOWN_LIMIT, 2), Color("ff9b8a"))
