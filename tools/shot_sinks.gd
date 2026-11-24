extends SceneTree
## Screenshots of the late economy screens (issue #189), for review (tools/* is not exported).
##   xvfb-run -a godot --path . --resolution 1280x720 -s tools/shot_sinks.gd -- out=/tmp/sinks days=70
## Plays a steady campaign on paper (tools/balance_bot.gd) for `days`, then opens the Command Table and
## saves out_buildings.png, out_feast.png, out_research.png and out_research_end.png.


var frame := 0
var args := {}
var cmd: Node
var step := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [str(args.get("out", "/tmp/sinks")), name])
	print("saved ", name)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 2:
		var dlg = load("res://scripts/dialogue.gd")
		var bot = load("res://tools/balance_bot.gd").new("steady")  # loaded late: it needs the autoloads
		seed(1000)
		bot.start()
		root.get_node("Empire").rng.seed = 1000
		for d in int(args.get("days", "70")):
			bot.play_day()
		for k in dlg.data().get("talks", {}):
			dlg.mark_seen("talk:" + str(k))
		for t in load("res://scripts/help.gd").topics():  # no onboarding cards over the screens
			dlg.mark_seen("help:" + str(t["id"]))
		var e = root.get_node("Empire")
		e.set_speed(0)
		if args.has("short"):
			e.sinks["short"] = ["ink"]
		change_scene_to_file("res://scenes/command.tscn")
	elif frame == 30:
		cmd = current_scene
		cmd.buildings_view.open("scriptorium")
	elif frame == 40:
		_shot("buildings")
		cmd.buildings_view.close()
		cmd.buildings_view.open("")
		cmd.buildings_view.sel = 8  # the tavern feast
		cmd.buildings_view.focus = 1
		cmd.buildings_view._follow_sel()
	elif frame == 50:
		_shot("feast")
		cmd.buildings_view.sel = cmd.buildings_view._rows().size() - 1
		cmd.buildings_view.focus = 0
		cmd.buildings_view._follow_sel()
	elif frame == 60:
		_shot("lamps")
		cmd.buildings_view.close()
		cmd.research_view.open()
	elif frame == 70:
		_shot("research")
		cmd.research_view.sel = cmd.research_view._rows.size() - 1
		cmd.research_view._follow_sel()
	elif frame == 80:
		_shot("research_end")
		return true
	return false
