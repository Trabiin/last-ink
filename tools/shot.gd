extends SceneTree
## Screenshot helper for art review (not exported: tools/* is excluded).
##   xvfb-run -a godot --path . -s tools/shot.gd -- out=/tmp/x.png scene=mission party=ash,bran,gristle,ninefingers frames=90
## scene: mission (Frayed Meadow patrol), town (Hollowmark), command (Command Table), picker: scene=command act=picker.
## Autoloads exist only after the first frame, so setup happens in _process.

var frame := 0
var args := {}
var shots: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("collisions"):  # collisions=1: draw every collision shape (footprint review, data/footprints.json)
		debug_collisions_hint = true


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		var empire = root.get_node("Empire")
		empire.reset()
		if args.has("font"):  # font=PixelifySans.ttf: try a UI font from assets/fonts for the whole run
			var ff: FontFile = load("res://assets/fonts/" + str(args["font"]))
			ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			ff.hinting = TextServer.HINTING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ThemeDB.fallback_font = ff
		var dlg = load("res://scripts/dialogue.gd")  # loaded late: class scripts need the autoloads
		for k in dlg.data().get("talks", {}):
			dlg.mark_seen("talk:" + str(k))  # no opening conversation in the way
		if args.has("fx"):  # fx=mist:80,vignette:0 sets Options > Visual effects sliders for this run
			var st = load("res://scripts/settings.gd")
			for pair in str(args["fx"]).split(","):
				var kv := pair.split(":")
				st.fx[kv[0]] = int(kv[1])
		if args.has("day"):
			empire.day_t = float(args["day"])  # 0.5 noon, 0.75 dusk, 0.9 night
		var party: PackedStringArray = str(args.get("party", "ash,bran,gristle")).split(",")
		for id in empire.recruits:
			if empire.recruits[id]["role"] == "party":
				empire.recruits[id]["role"] = "idle"
		for id in party:
			empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
		if args.has("levels"):  # every Hollowmark building at this level, and the Wardlamp lit
			for id in empire.building_ids():
				if id != "wardlamp":
					empire.buildings[id] = int(args["levels"])
			empire.lamps["hollowmark"] = clampi(int(args["levels"]) - 1, 1, 2)
		if args.has("build"):  # build=barracks:0.5: that building under construction, half done
			var bp := str(args["build"]).split(":")
			var now: float = empire.day + empire.day_t
			var pr := float(bp[1]) if bp.size() > 1 else 0.5
			empire.construction = {"id": bp[0], "start": now - pr, "finish": now - pr + 1.0}
		if args.has("xp"):  # xp=40: every party hero that much XP into level 1 (part-filled XP bars)
			var prog = load("res://scripts/progress.gd")
			for id in party:
				prog.hero(id)["xp"] = int(args["xp"])
		var scene := str(args.get("scene", "mission"))
		if scene == "mission":
			var m: Dictionary = load("res://scripts/missions.gd").find(str(args.get("mission", "meadow_patrol"))).duplicate()
			if args.has("map"):  # map=gutterwoods: the mission on another map in maps/
				m["map"] = "res://maps/%s.txt" % args["map"]
			empire.active_mission = m
			change_scene_to_file("res://scenes/main.tscn")
		elif scene == "command":  # the Command Table: act=call:gear_view.open:town opens a screen on it
			change_scene_to_file("res://scenes/command.tscn")
		elif scene == "title":
			change_scene_to_file("res://scenes/title.tscn")
		elif scene == "town":
			if args.has("map"):  # map=mockup_town: another layout in maps/
				load("res://scripts/hub.gd").map_override = "res://maps/%s.txt" % args["map"]
			change_scene_to_file("res://scenes/hub.tscn")
	var total := int(args.get("frames", "90"))
	if args.has("at") and frame == 20:
		var cur := current_scene
		if cur != null and "heroes" in cur:
			var xy: PackedStringArray = str(args["at"]).split(",")
			var pos := Vector2(float(xy[0]), float(xy[1])) * 16.0
			for h in cur.heroes:
				h.global_position = pos
			cur.camera.global_position = pos
			cur.camera.reset_smoothing()
			if args.has("enemies"):
				for i in int(args["enemies"]):
					cur._spawn_enemy(pos + Vector2(60 + 24 * i, -30 + 30 * (i % 3)))
			if args.has("kinds"):  # kinds=moth,enforcer: one of each, in a row east of the party
				var i := 0
				for k in str(args["kinds"]).split(","):
					load("res://scripts/enemy_kinds.gd").spawn(cur.entities, pos + Vector2(50 + 36 * i, -10 + 24 * (i % 2)), cur.mission, k)
					i += 1
	if args.has("hp") and frame == 25 and current_scene != null and "heroes" in current_scene:
		var fr: PackedStringArray = str(args["hp"]).split(",")  # hp=0.8,0.4,0.15: each hero's HP fraction
		for i in current_scene.heroes.size():
			var h = current_scene.heroes[i]
			h.hp = maxi(1, roundi(h.max_hp * float(fr[mini(i, fr.size() - 1)])))
		for e in current_scene.get_tree().get_nodes_in_group("enemies"):
			e.hp = maxi(1, roundi(e.max_hp * 0.55))
	if args.has("walk") and frame == 21:  # walk=left (up/down/right): Ash walks that way until the shot, into a wall
		Input.action_press("move_" + str(args["walk"]))
	if args.has("zoom") and frame == 22 and current_scene != null and "camera" in current_scene:
		current_scene.camera.zoom = Vector2.ONE * float(args["zoom"])  # wider overview shots
		current_scene.camera.reset_smoothing()
	if args.has("spread") and frame >= total - 40 and frame <= total - 10:
		_spread()
	if frame == 2 and args.has("portraits"):
		_swap_portraits(str(args["portraits"]))
	if frame == total - int(args.get("lead", "30")) and args.has("act"):
		_act(str(args["act"]))
		for pair in str(args.get("set", "")).split(",", false):  # set=gear_view.tab:skills: a property on the opened screen
			var kv := pair.split(":", true, 1)
			var path := kv[0].split(".")
			var obj: Object = current_scene
			for j in path.size() - 1:
				obj = obj.get(path[j])
			var v = kv[1]
			obj.set(path[path.size() - 1], (v == "true") if v in ["true", "false"] else (int(v) if v.is_valid_int() else v))
	if frame == total - 25 and args.has("talk") and current_scene != null and "dialogue_box" in current_scene:
		# talk=quill_first opens that conversation in town (portraits=DIR works here too, see _swap_portraits).
		var dlg = load("res://scripts/dialogue.gd")
		dlg._speed = 3  # instant text
		current_scene.dialogue_box.play(str(args["talk"]))
		for i in int(args.get("skip", "0")):  # skip=1: start on the next line
			current_scene.dialogue_box._shown = 99999.0
			current_scene.dialogue_box._advance()
	if frame == total - 1 and args.has("nohud") and current_scene != null:  # clean ground for UI mockups
		for c in current_scene.find_children("*", "CanvasLayer", true, false):
			c.visible = false
	if frame == total:
		var img := root.get_texture().get_image()
		img.save_png(str(args.get("out", "/tmp/shot.png")))
		print("saved ", args.get("out", "/tmp/shot.png"))
		quit()
	return false


## portraits=DIR: every <id>.png in DIR stands in for that character's portrait on every screen (dialogue,
## help card, bond scenes, epilogues, the journal sketch), for style trials, without touching assets/portraits.
func _swap_portraits(dir_path: String) -> void:
	var dlg = load("res://scripts/dialogue.gd")
	var scn = load("res://scripts/scene_view.gd")
	for f in DirAccess.open(dir_path).get_files():
		if not f.ends_with(".png"):
			continue
		var id := f.get_basename()
		var tex := ImageTexture.create_from_image(Image.load_from_file(dir_path.path_join(f)))
		for ex in ["", "happy", "angry", "sad", "surprised", "smug", "hurt", "worried", "laugh"]:  # every expression
			dlg._portraits["%s|%s" % [id, ex]] = tex
			scn._portraits["res://assets/portraits/%s.png" % (id if ex == "" else id + "_" + ex)] = tex


## Small staged moments for screenshots: "swing" makes every hero swing, "spread" fans them out.
func _act(what: String) -> void:
	var cur := current_scene
	if what.begins_with("call:"):  # act=call:quick_menu.open or call:open_menu: open a screen for a UI shot
		var parts := what.substr(5).split(":")
		var path := parts[0].split(".")
		var obj: Object = cur
		for j in path.size() - 1:
			obj = obj.get(path[j])
		obj.callv(path[path.size() - 1], Array(parts.slice(1)))
		return
	if what.begins_with("popup:"):  # act=popup:help_view opens an overlay screen (its static popup) for a UI shot
		var bits := what.substr(6).split(":")
		var scr = load("res://scripts/%s.gd" % bits[0])
		var a := [cur] + Array(bits.slice(1))
		scr.callv("popup" if scr.has_method("popup") else "open", a)
		return
	if what.begins_with("log:"):  # act=log:quill_first: that talk's lines written into the dialogue log, then the log
		for t in what.substr(4).split(","):
			for l in load("res://scripts/dialogue.gd").talk(t):
				load("res://scripts/dialogue_log.gd").add(str(l[0]), str(l[1]))
		load("res://scripts/dialogue_log.gd").popup(cur)
		return
	if what.begins_with("help:"):  # act=help:gear: that help talk on its card (the voice's portrait at the left)
		load("res://scripts/help_card.gd").ensure(cur)
		load("res://scripts/help.gd").play(what.substr(5), cur)
		return
	if what.begins_with("bond:") and cur != null and "bonds_view" in cur:  # act=bond:bran:1: that rank scene
		var b := what.substr(5).split(":")
		cur.bonds_view.open(b[0])
		cur.bonds_view.scene_view.play(b[0], int(b[1]) if b.size() > 1 else 1, true)
		return
	if what.begins_with("epilogue:"):  # act=epilogue:bran,gristle: those epilogue cards over the scene
		var cards := []
		var emp := root.get_node("Empire")  # autoloads are not known to a -s script at compile time
		for id in what.substr(9).split(","):
			cards.append({"id": id, "name": emp.recruit(id).get("name", id), "text": load("res://scripts/epilogues.gd").text_for(id),
				"lost": false, "color": emp.bond_info(id).get("color", "c9c3b6")})
		var ev = load("res://scripts/epilogue_view.gd").new()
		var layer := CanvasLayer.new()
		layer.layer = 50
		cur.add_child(layer)
		layer.add_child(ev)
		ev.play(cards)
		return
	if what == "picker" and cur != null and "party_picker" in cur:  # act=picker on scene=command: the party picker
		cur.party_picker.open(load("res://scripts/missions.gd").find(str(args.get("mission", "meadow_patrol"))))
		return
	if cur == null or not ("heroes" in cur):
		return
	var i := 0
	for h in cur.heroes:
		if what == "swing":
			h.facing = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT][i % 3]
			h.try_attack()
		elif what == "hurt":
			h.flash_t = 0.5
			h.invuln_t = 0.7
		i += 1


## Holds the party in a loose row so each hero is visible (the AI otherwise bunches them up).
func _spread() -> void:
	var cur := current_scene
	if cur == null or not ("heroes" in cur) or cur.heroes.is_empty():
		return
	var base: Vector2 = cur.heroes[0].global_position if not has_meta("base") else get_meta("base")
	set_meta("base", base)
	var offs := [Vector2.ZERO, Vector2(-34, -6), Vector2(34, -6)]
	for i in cur.heroes.size():
		cur.heroes[i].global_position = base + offs[i % 3]
		cur.heroes[i].velocity = Vector2.ZERO
