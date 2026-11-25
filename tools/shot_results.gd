extends SceneTree
## Screenshots of the results ledger and the Command Table clock (scratch helper, not exported: tools/*).
##   xvfb-run -a godot --path . -s tools/shot_results.gd -- out=/tmp/r what=results|people|lost|menu|clock|assist t=4.0

var frame := 0
var args := {}
var t_shot := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _process(delta: float) -> bool:
	frame += 1
	var what := str(args.get("what", "results"))
	if frame == 2:
		var empire = root.get_node("Empire")
		empire.reset()
		var dlg = load("res://scripts/dialogue.gd")
		for k in dlg.data().get("talks", {}):
			dlg.mark_seen("talk:" + str(k))
		var help = load("res://scripts/help.gd")
		for t in help.topics():
			help.mark(str(t.get("id", "")))
		for id in ["bran", "gristle", "odile"]:
			empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
		load("res://scripts/assists.gd").reset()
		if what == "assist":
			var A = load("res://scripts/assists.gd")
			A.allow_pause = true
			A.half_clock = true
			A.save()
		if what in ["menu", "clock", "assist"]:
			change_scene_to_file("res://scenes/command.tscn")
		else:
			var m: Dictionary = load("res://scripts/missions.gd").find("meadow_patrol").duplicate()
			empire.active_mission = m
			change_scene_to_file("res://scenes/main.tscn")
	if frame == 40:
		var cur := current_scene
		if what == "menu":
			cur._open_menu()
		elif what in ["results", "people", "lost"]:
			var M = load("res://scripts/missions.gd")
			var r: Dictionary = M.settle(cur.mission, "wiped" if what == "lost" else "success", {"gilt": 4, "supplies": 2}, {"kills": 12, "time": 96.0, "objective": "Disperse Nibblers"})
			if what == "people":
				r["changed"] = [
					{"kind": "people", "count": 11, "from": "Millbrook", "text": "Eleven people from Millbrook walk into Hollowmark, carrying what the Concord left them."},
					{"kind": "place", "province_id": "meadow", "text": "Frayed Meadow comes back into ink."},
					{"kind": "line", "who": "odile", "text": "I have entered all eleven by name. The Concord had them down as 'sundry'."},
				]
			cur.get_tree().paused = true
			cur.results_view.open(r)
			if args.has("skip"):
				cur.results_view._skip = true
			t_shot = float(args.get("t", "6.0"))
	if frame > 40 and t_shot > 0.0:
		t_shot -= delta
		if t_shot <= 0.0:
			_save()
			quit()
	if frame == 80 and what in ["menu", "clock", "assist"]:
		_save()
		quit()
	return false


func _save() -> void:
	var img := root.get_texture().get_image()
	img.save_png(str(args.get("out", "/tmp/shot.png")))
	print("saved ", args.get("out"))
