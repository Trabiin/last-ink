class_name MissionObjectives
extends RefCounted
## The objective kinds behind the Defense, Reclaim and Rescue missions (#51) and the Raid and Salvage
## missions (#113). Objective hands a mission's "objective" dict here when its kind is one of KINDS,
## and forwards its hooks.
##
## They are built from a few shared pieces, so a new type is mostly a new combination:
##   - a creeping Blank: the white wall moves west at "creep" px/s (kills can push it back),
##   - spawning: Nibblers on a timer, from the Blank's edge or around a point,
##   - a thing to protect (Wardstone), break (Blot) or find (a recruit waiting to be rescued),
##   - caches to pry open (Cache): a faction's strongboxes, or piles of goods at the Blank's edge,
##   - an alarm and a garrison clock (Raid): guards who see you raise it; full alarm calls reinforcements,
##   - an exit to walk back to, and a pointer at the screen edge to whatever matters next.

const KINDS := ["defense", "reclaim", "rescue", "raid", "salvage"]
const GRACE_SPEED := 70.0  # px/s: a hero's walk with a little slack for fences and trees
const EnemyScript := preload("res://scripts/enemy.gd")
const BlotScript := preload("res://scripts/blot.gd")
const WardScript := preload("res://scripts/wardstone.gd")
const HeroScript := preload("res://scripts/hero.gd")
const MAX_SPAWNED := 12
const FIND_RANGE := 24.0
const EXIT_RANGE := 26.0

var kind := ""
var obj := {}
var main  # main.gd
var phase := 0  # rescue: 0 = find them, 1 = bring them back
var time_left := 0.0
var spawn_t := 1.5
var start_blank_x := 0.0
var end_t := -1.0  # counts up once the goal is met: a beat to watch the Blank let go
var fail_why := ""
var ward: Wardstone
var blot: Blot
var captive: Hero
var exit_pos := Vector2.ZERO
var pointer: Control
# Raid / Salvage (#113)
var caches: Array = []  # Cache nodes
var taken := 0
var alarm := 0.0  # 0-100; at 100 the alarm is raised for good
var raised := false
var reinforce_t := 0.0
var need := 0
var grace := 0.0  # salvage: seconds before the white starts to move (enough to reach the nearest pile)
var restore := {}  # state from a mid-mission save, applied once the world exists


static func handles(k: String) -> bool:
	return k in KINDS


func setup(p_obj: Dictionary, p_main) -> void:
	obj = p_obj
	kind = obj.get("kind", "")
	main = p_main
	start_blank_x = main.blank.base_x
	exit_pos = main.area.party_start
	match kind:
		"defense":
			time_left = float(obj.get("seconds", 75))
			ward = WardScript.new()
			ward.max_hp = int(obj.get("ward_hp", 100))
			ward.hp = ward.max_hp
			ward.position = _tile(obj["ward"])
			main.entities.add_child(ward)
		"reclaim":
			blot = BlotScript.new()
			blot.total_hp = int(obj.get("hp", 220))
			blot.position = _tile(obj["blot"])
			main.entities.add_child(blot)
			spawn_t = 3.0
		"rescue":
			var rid: String = obj.get("who", "")
			var look: Dictionary = Empire.recruit(rid).get("look", {})
			captive = HeroScript.new()
			captive.hero_name = Empire.short_name(rid)
			captive.hero_id = rid  # picks their art pass sprite if they have one (else the paper doll)
			captive.outfit = look.get("outfit", "archer")
			var cols := {}
			for k in look.get("colors", {}):
				cols[k] = Color(look["colors"][k])
			if not cols.is_empty():
				captive.colors = cols
			captive.move_speed = 66.0
			captive.position = _tile(obj["at"])
			captive.facing = Vector2.LEFT
			main.entities.add_child(captive)
			captive.set_physics_process(false)  # stuck where they are until Ash turns up
			for i in int(obj.get("guards", 4)):
				_spawn(captive.position + Vector2.RIGHT.rotated(TAU * i / 4.0 + 0.4) * 46.0)
		"raid", "salvage":
			need = int(obj.get("need", 3))
			time_left = float(obj.get("seconds", 0.0))
			var done_list: Array = restore.get("done", [])
			var gone_list: Array = restore.get("gone", [])
			var tiles: Array = obj.get("caches", [])
			for i in tiles.size():
				var c := Cache.new()
				c.style = "crate" if kind == "raid" else "pile"
				c.open_time = float(obj.get("open_time", 1.6))
				c.position = _tile(tiles[i])
				c.done = i in done_list
				c.gone = i in gone_list
				main.entities.add_child(c)
				caches.append(c)
				if kind == "raid" and not c.done:
					for g in int(obj.get("per_cache", 2)):
						for e in _spawn(c.position + Vector2(randf_range(-30, 30), randf_range(14, 26)) * (1 if g % 2 == 0 else -1)):
							e.set_meta("post", c.position)
			if kind == "salvage":  # time to walk to the nearest pile, plus a breath, before the white moves
				var near := INF
				for c in caches:
					near = minf(near, exit_pos.distance_to((c as Cache).position))
				grace = float(restore.get("grace", near / GRACE_SPEED + float(obj.get("grace", 6.0))))
			taken = int(restore.get("taken", 0))
			alarm = float(restore.get("alarm", 0.0))
			raised = bool(restore.get("raised", false))
			if restore.has("time_left"):
				time_left = float(restore["time_left"])
			if restore.has("blank_x"):
				main.blank.base_x = float(restore["blank_x"])
				Art.set_blank_x(main.blank.base_x)
	pointer = Pointer.new()
	pointer.obj = self
	main.hud.get_parent().add_child(pointer)


func _tile(t: Array) -> Vector2:
	return Vector2(int(t[0]) * 16 + 8, int(t[1]) * 16 + 8)


func on_kill() -> void:
	if kind == "defense" or kind == "salvage":
		_move_blank(float(obj.get("push", 7.0)))  # every Nibbler dispersed gives back a little ground


func update(delta: float) -> void:
	if fail_why != "":
		return
	if end_t >= 0.0:
		end_t += delta
		_move_blank(260.0 * delta)  # the white pulls back east
		return
	match kind:
		"defense":
			time_left -= delta
			_move_blank(-float(obj.get("creep", 3.0)) * delta)
			_spawn_timer(delta, float(obj.get("spawn_every", 3.0)), func(): return _edge_point(ward.position.y, 160.0), true)
			if ward.hp <= 0:
				fail_why = tr("The wardstone broke. The surge will land.")
			elif main.blank.edge_x(ward.position.y) <= ward.position.x + 8.0:
				fail_why = tr("The Blank swallowed the wardstone.")
			elif time_left <= 0.0:
				time_left = 0.0
				end_t = 0.0
				main.hud.say(tr("The surge breaks. The white goes quiet."), 3.0)
		"reclaim":
			if blot.dead:
				end_t = 0.0
				main.hud.say(tr("The Blot bursts. The Blank lets go of the land."), 3.0)
				return
			_spawn_timer(delta, float(obj.get("spawn_every", 4.0)), func(): return blot.position + Vector2(randf_range(-30, -14), randf_range(-26, 26)), false)
		"rescue":
			if phase == 0:
				_move_blank(-float(obj.get("creep", 2.6)) * delta)
				if main.blank.edge_x(captive.position.y) <= captive.position.x + 6.0:
					fail_why = tr("The white closed over %s before you got there.") % captive.hero_name
				elif main.leader and main.leader.global_position.distance_to(captive.global_position) < FIND_RANGE:
					phase = 1
					captive.party = main
					captive.set_physics_process(true)  # follows the leader and fights like an ally
					main.hud.say(tr("%s: \"Took you long enough. Which way is out?\"") % captive.hero_name, 3.5)
			elif main.leader and main.leader.global_position.distance_to(exit_pos) < EXIT_RANGE:
				end_t = 1.6  # nothing to watch here: done right away
		"raid":
			_update_raid(delta)
		"salvage":
			_update_salvage(delta)


# ---------------------------------------------------------------- Raid and Salvage (#113)

func _workers() -> Array:
	return main.heroes.filter(func(h): return not h.dead)


func _open_cache(c: Cache) -> void:
	taken += 1
	var got := {}
	var contents: Dictionary = obj.get("contents", {})
	var mult := 1.0
	if kind == "salvage":  # the nearer the white, the richer the pickings
		var gap := maxf(main.blank.edge_x(c.position.y) - c.position.x, 0.0)
		mult = 1.0 + float(obj.get("near_bonus", 1.0)) * (1.0 - clampf(gap / 320.0, 0.0, 1.0))
	for k in contents:
		var v = contents[k]
		var n := randi_range(int(v[0]), int(v[1])) if v is Array else int(v)
		n = int(round(n * mult))
		if n > 0:
			got[k] = n
			main.found[k] = int(main.found.get(k, 0)) + n
	main.found_flash = 1.5
	var txt := Missions.res_text(got)
	Fx.damage_number(main.entities, c.position + Vector2(0, -30), txt if txt != "" else Loc.t("empty"), Color("ffe7a3"))
	if taken == need:
		main.hud.say(tr("That's enough. Get back to where you came in (or grab more first)."), 3.5)
		Audio.sfx("alert", 1.0, 0.0, tr("Chime: enough loot"))
	if kind == "raid":
		_raise(float(obj.get("alarm_open", 14.0)))


func _raise(amount: float) -> void:
	if raised:
		return
	alarm = minf(alarm + amount, 100.0)
	if alarm >= 100.0:
		raised = true
		time_left = minf(time_left, float(obj.get("alarm_cap", 45.0)))
		reinforce_t = 1.5
		main.hud.say(tr("The alarm is up! The garrison is coming. Grab what you can and run."), 3.5)
		Audio.sfx("alert", 1.0, 0.0, tr("Alarm bell: the garrison is coming"))


func _update_raid(delta: float) -> void:
	time_left -= delta
	for c in caches:
		if (c as Cache).work(delta, _workers()):
			_open_cache(c)
	# Guards who have spotted the party raise the alarm; out of sight, it settles back down.
	var seen := 0
	for e in main.get_tree().get_nodes_in_group("enemies"):
		if not e.dead and e.get("target") != null and is_instance_valid(e.target):
			seen += 1
	if seen > 0:
		_raise(float(obj.get("alarm_seen", 9.0)) * delta * minf(seen, 3))
	elif not raised:
		alarm = maxf(alarm - float(obj.get("alarm_fall", 3.0)) * delta, 0.0)
	if raised:
		reinforce_t -= delta
		if reinforce_t <= 0.0:
			reinforce_t = float(obj.get("reinforce_every", 6.5))
			if main.get_tree().get_nodes_in_group("enemies").size() < MAX_SPAWNED:
				for e in _spawn(_far_spawn()):
					e.target = main.leader  # they know where you are
	if taken >= need and main.leader and main.leader.global_position.distance_to(exit_pos) < EXIT_RANGE:
		end_t = 1.6
		main.hud.say(tr("Out, with %d cache%s. Nobody followed. Yet.") % [taken, "" if taken == 1 else "s"], 3.0)
	elif time_left <= 0.0:
		time_left = 0.0
		fail_why = tr("The garrison closed in. You dropped everything and ran.")


## A spawn point well away from the party (reinforcements come from somewhere you aren't).
func _far_spawn() -> Vector2:
	var best := Vector2(main.world.x * 0.7, main.world.y / 2.0)
	var best_d := -1.0
	for p in main.area.spawns:
		var d: float = (p as Vector2).distance_to(main.leader.global_position) if main.leader else 0.0
		if d > best_d and d < 520.0:
			best_d = d
			best = p
	return best


func _update_salvage(delta: float) -> void:
	if grace > 0.0:
		grace -= delta
		if grace <= 0.0:
			main.hud.say(tr("The white starts to move."), 2.5)
		return
	_move_blank(-float(obj.get("creep", 4.0)) * delta)
	_spawn_timer(delta, 5.0, func(): return _edge_point(main.leader.global_position.y if main.leader else main.world.y / 2.0, 140.0), false)
	var left := 0
	for c in caches:
		var cc := c as Cache
		if cc.done or cc.gone:
			continue
		if main.blank.edge_x(cc.position.y) <= cc.position.x + 6.0:
			cc.swallow()
			main.hud.say(tr("The white swallowed a pile."), 2.0)
			continue
		if cc.work(delta, _workers()):
			_open_cache(cc)
			continue
		left += 1
	if taken >= need:
		if main.leader and main.leader.global_position.distance_to(exit_pos) < EXIT_RANGE:
			end_t = 1.6
			main.hud.say(tr("Out with %d pile%s. The white can have the rest.") % [taken, "" if taken == 1 else "s"], 3.0)
	elif taken + left < need:
		fail_why = tr("The white took the rest before you could reach it.")


func _move_blank(dx: float) -> void:
	var b = main.blank
	var limit: float = main.world.x + 80.0 if end_t >= 0.0 else start_blank_x
	b.base_x = clampf(b.base_x + dx, 120.0, maxf(limit, start_blank_x))
	Art.set_blank_x(b.base_x)


func _edge_point(y: float, spread: float) -> Vector2:
	var yy := clampf(y + randf_range(-spread, spread), 40.0, main.world.y - 40.0)
	return Vector2(main.blank.edge_x(yy) - 14.0, yy)


func _spawn_timer(delta: float, every: float, where: Callable, to_ward: bool) -> void:
	spawn_t -= delta
	if spawn_t > 0.0:
		return
	spawn_t = every
	if main.get_tree().get_nodes_in_group("enemies").size() >= MAX_SPAWNED:
		return
	for e in _spawn(where.call(), true):  # out of the Blank: only Blank-born kinds
		if to_ward:
			e.goal = ward


## One roll of the mission's enemy roster (#16): usually one enemy, a pack for letter-moths.
func _spawn(pos: Vector2, blank_only := false) -> Array:
	var out := EnemyKinds.spawn(main.entities, pos, main.mission, "", blank_only)
	for e in out:
		e.died.connect(main._on_enemy_died)
	Fx.burst(main.entities, pos + Vector2(0, -6), [Color.WHITE, Color.BLACK], 8, 50.0)
	return out


func done() -> bool:
	return end_t >= 1.5


func failed() -> bool:
	return fail_why != ""


func fail_text() -> String:
	return fail_why


func text() -> String:
	match kind:
		"defense":
			return tr("Hold the wardstone: %d s   (stone %d/%d)") % [ceili(time_left), ward.hp, ward.max_hp]
		"reclaim":
			return tr("Break the Blot   (%d/%d)") % [blot.hp, blot.max_hp] if not blot.dead else tr("The Blot is broken")
		"rescue":
			if phase == 0:
				var gap := maxf(main.blank.edge_x(captive.position.y) - captive.position.x, 0.0)
				return tr("Find %s before the white does   (%d paces)") % [captive.hero_name, int(gap / 4.0)]
			return tr("Bring %s back to where you came in") % captive.hero_name
		"raid":
			var clock := "%d:%02d" % [int(time_left) / 60, int(time_left) % 60]
			var a := tr("ALARM") if raised else tr("alarm %d%%") % int(alarm)
			if taken >= need:
				return tr("Get out with it: %d cache%s   (%s, %s)") % [taken, "" if taken == 1 else "s", a, clock]
			return tr("Take the caches: %d/%d   (%s, %s)") % [taken, need, a, clock]
		"salvage":
			if taken >= need:
				return tr("Get back with it: %d pile%s   (or grab more)") % [taken, "" if taken == 1 else "s"]
			if grace > 0.0:
				return tr("Pull piles out of the white: %d/%d   (it moves in %ds)") % [taken, need, ceili(grace)]
			return tr("Pull piles out of the white: %d/%d") % [taken, need]
	return ""


## Where the edge pointer aims, or null when nothing needs pointing at.
func target_pos():
	if end_t >= 0.0 or fail_why != "":
		return null
	match kind:
		"defense":
			return ward.global_position
		"reclaim":
			return blot.global_position
		"rescue":
			return captive.global_position if phase == 0 else exit_pos
		"raid", "salvage":
			if taken >= need:
				return exit_pos
			var best = null
			var best_d := 1e9
			for c in caches:
				var cc := c as Cache
				if cc.done or cc.gone or main.leader == null:
					continue
				var d := cc.global_position.distance_to(main.leader.global_position)
				if d < best_d:
					best_d = d
					best = cc.global_position
			return best
	return null


## Draws the exit ring in the world (rescue once they are found, raid and salvage once enough is taken).
## Called by Pointer each frame.
func exit_visible() -> bool:
	if end_t >= 0.0:
		return false
	return (kind == "rescue" and phase == 1) or (kind in ["raid", "salvage"] and taken >= need)


## What the results screen and MissionTypes.apply need to know about how it went.
func result_info() -> Dictionary:
	var lost := 0
	for c in caches:
		lost += 1 if (c as Cache).gone else 0
	return {"taken": taken, "alarm": raised, "lost": lost}


## Mid-mission saves (#113): enough to put the caches, the alarm and the clock back as they were, so a reload
## never refills a strongbox. Older kinds keep restarting from the top, as before.
func save_state() -> Dictionary:
	if not kind in ["raid", "salvage"]:
		return {}
	var done_list := []
	var gone_list := []
	for i in caches.size():
		if (caches[i] as Cache).done:
			done_list.append(i)
		if (caches[i] as Cache).gone:
			gone_list.append(i)
	return {"done": done_list, "gone": gone_list, "taken": taken, "alarm": alarm, "raised": raised,
		"time_left": time_left, "blank_x": main.blank.base_x, "grace": grace}


## A small HUD arrow at the screen edge pointing at the objective, plus the exit ring.
class Pointer extends Control:
	var obj  # MissionObjectives
	var t := 0.0

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var xf := get_viewport().get_canvas_transform()
		var vs := get_viewport_rect().size
		if obj.exit_visible():
			var ep: Vector2 = xf * obj.exit_pos
			var r := (13.0 + sin(t * 4.0) * 1.5) * xf.get_scale().x
			draw_arc(ep, r, 0, TAU, 32, Color("ffd166"), 2.0)
			_label(ep + Vector2(0, -r - 4), tr("EXIT"))
		var tp = obj.target_pos()
		if tp == null:
			return
		var sp: Vector2 = xf * (tp as Vector2)
		var margin := 18.0
		var inner := Rect2(Vector2(margin, margin + 40), vs - Vector2(margin * 2, margin * 2 + 80))
		if inner.has_point(sp):
			var bob := sin(t * 5.0) * 2.0
			var tip := sp + Vector2(0, -34 * xf.get_scale().y / 2.0 - 12 + bob)
			draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-5, -7), tip + Vector2(5, -7)]), Color("ffd166"))
			return
		var c := vs / 2.0
		var d := (sp - c).normalized()
		var k := minf(absf((inner.size.x / 2.0) / d.x) if absf(d.x) > 0.001 else 1e9, absf((inner.size.y / 2.0) / d.y) if absf(d.y) > 0.001 else 1e9)
		var at := c + d * k
		var a := d.angle()
		var pts := PackedVector2Array([at + Vector2(14, 0).rotated(a), at + Vector2(-8, -10).rotated(a), at + Vector2(-8, 10).rotated(a)])
		draw_colored_polygon(pts, Color("ffd166", 0.8 + 0.2 * sin(t * 6.0)))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.8), 1.5)

	func _label(pos: Vector2, s: String) -> void:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
		draw_string_outline(f, pos - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), 3, Color(0, 0, 0, 0.8))
		draw_string(f, pos - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color("ffd166"))
