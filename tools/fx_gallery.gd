extends SceneTree
## Every code-drawn effect on one screen, for judging the pixel FX layer (scripts/fx_layer.gd):
##   xvfb-run -a godot --fixed-fps 60 --resolution 1280x720 --path . -s tools/fx_gallery.gd -- out=/tmp/fx.png age=6
## age: how many frames (at 60 fps) after spawning the shot is taken. Each cell is labelled. nofx=1 leaves the
## FX layer out (effects draw straight on the world, as before), for side by side comparisons.

var frame := 0
var args := {}
var main: Node
const SPAWN := 40
const COLS := 6
const CELL := Vector2(52, 42)
const ROWS := [
	["burst", "slash", "sweep", "line", "beam", "seal"],
	["shock", "spiral", "pillar", "shards", "splash", "stars"],
	["coins", "petals", "fx_sweep", "fx_lunge", "fx_ring", "fx_burst"],
	["fx_disc", "trail", "full_trail", "leader", "shield", "thrust"],
]
const COLORS := ["e8c66a", "7fa8ec", "c2622d", "e89a8a", "9fd18b", "c9a0e8"]


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		var empire = root.get_node("Empire")
		empire.reset()
		var dlg = load("res://scripts/dialogue.gd")
		for k in dlg.data().get("talks", {}):
			dlg.mark_seen("talk:" + str(k))
		dlg.mark_seen("hint:mission")
		empire.day_t = float(args.get("day", "0.45"))
		for id in empire.recruits:
			if empire.recruits[id]["role"] == "party":
				empire.recruits[id]["role"] = "idle"
		for id in str(args.get("party", "ash,bran,gristle")).split(","):
			empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
		var m: Dictionary = load("res://scripts/missions.gd").find("meadow_patrol").duplicate()
		empire.active_mission = m
		change_scene_to_file("res://scenes/main.tscn")
	if frame == 20:
		main = current_scene
		main.set_process(false)  # main steers the camera after the leader; the gallery holds it still
		main.set_physics_process(false)
		for e in main.get_tree().get_nodes_in_group("enemies"):
			e.queue_free()
		if args.has("nofx"):
			for c in main.get_children():
				if c.name == "FxLayer":
					c.queue_free()
		for c in main.find_children("*", "CanvasLayer", true, false):
			if c.name != "FxLayer":
				c.visible = false
	if frame >= 20 and frame <= SPAWN and main != null:
		var base := _base()
		for i in main.heroes.size():  # the party off to one side, out of the cells
			main.heroes[i].global_position = base + Vector2(-60 - 20 * i, 160)
		main.camera.global_position = base + CELL * Vector2(COLS, ROWS.size()) / 2.0 - CELL / 2.0
		main.camera.reset_smoothing()
	var shot_at := SPAWN + int(args.get("age", "6"))
	if args.has("beam") and frame >= shot_at - 30 and frame <= shot_at and (shot_at - frame) % 6 == 0:
		# beam=1 age=30: the long-line motif alone at full size, one row per age (0, 6 ... 30 frames old, top down)
		var k := (shot_at - frame) / 6
		var col := Color(["5a6ea8", "fff0a0", "ff4060", "8fb0ff", "5a6ea8", "fff0a0"][k])
		load("res://scripts/tech_fx.gd").spawn(main.entities, "beam", _base() + Vector2(-20, k * 28 - 10), Vector2.RIGHT.rotated(-0.12), 92.0, deg_to_rad(7), col)
	if frame == SPAWN and not args.has("beam"):
		_spawn_all()
	if frame == SPAWN + int(args.get("age", "6")):
		var img := root.get_texture().get_image()
		img.save_png(str(args.get("out", "/tmp/fx.png")))
		print("saved ", args.get("out", "/tmp/fx.png"))
		quit()
	return false


func _base() -> Vector2:
	return Vector2(30, 14) * 16.0


func _spawn_all() -> void:
	var base := _base()
	var heroes: Array = main.heroes
	var FxS = load("res://scripts/fx.gd")
	var TechS = load("res://scripts/tech_fx.gd")
	for r in ROWS.size():
		for c in ROWS[r].size():
			var kind: String = ROWS[r][c]
			var at := base + Vector2(c, r) * CELL
			var col := Color(COLORS[(r * COLS + c) % COLORS.size()])
			var dir := Vector2.RIGHT.rotated(-0.5)
			match kind:
				"fx_sweep":
					FxS.sweep(main.entities, at, dir.angle(), deg_to_rad(70), 20.0, col)
				"fx_lunge":
					FxS.sweep(main.entities, at - dir * 10.0, dir.angle(), deg_to_rad(10), 24.0, col)
				"fx_ring":
					FxS.ring(main.entities, at, 22.0, col)
				"fx_burst":
					FxS.burst(main.entities, at, [col, col.lightened(0.4), Color.WHITE], 18, 70.0)
				"fx_disc":
					FxS.sweep(main.entities, at, 0.0, PI, 16.0, col)
				"trail", "full_trail", "thrust", "leader", "shield":
					pass  # the party: placed below
				_:
					TechS.spawn(main.entities, kind, at, dir, 18.0, PI if kind in ["burst", "shock", "spiral", "pillar", "splash", "stars", "coins", "petals", "seal"] else 0.6, col)
	# The party fills the hero cells: hero 3 swings (full power with full=1, a thrust with thrust=1), hero 1
	# wears the swap marker, hero 2 is shielded and guarding.
	if heroes.size() >= 3:
		for h in heroes:
			h.set_physics_process(false)
			h.facing = Vector2.RIGHT
			h.swing_t = 0.0
		var sw = heroes[2]
		var cell := 2 if args.has("full") else (5 if args.has("thrust") else 1)
		sw.global_position = base + Vector2(cell, 3) * CELL + Vector2(-4, 10)
		sw.trail_thrust = args.has("thrust")
		sw.swing_power = 1.0 if args.has("full") else 0.5
		sw.swing_t = 0.24 * float(args.get("swing", "0.45"))
		var lead = heroes[0]
		lead.global_position = base + Vector2(3, 3) * CELL + Vector2(0, 10)
		if "leader_cue_t" in lead:
			lead.leader_cue_t = 1.1 * float(args.get("cue", "0.8"))
		var sh = heroes[1]
		sh.global_position = base + Vector2(4, 3) * CELL + Vector2(0, 10)
		sh.shield_hp = 10
		sh.guard_t = 2.0
	var font := ThemeDB.fallback_font
	var labels := Node2D.new()
	labels.z_index = 60
	main.entities.add_child(labels)
	labels.draw.connect(func():
		for r2 in ROWS.size():
			for c2 in ROWS[r2].size():
				labels.draw_string(font, base + Vector2(c2, r2) * CELL + Vector2(-24, -14), ROWS[r2][c2], HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(1, 1, 1, 0.8)))
