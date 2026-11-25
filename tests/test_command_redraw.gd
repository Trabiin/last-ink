extends "res://tests/test_case.gd"
## The Command Table redraws only what changed (issue #191): the map, labels, overlay and panel stay
## as they were drawn while nothing happens, and redraw when the selection, the resources, a setting
## or the camera changes. Only the small moving layers (fog, static, pulses) draw every frame.

const COMMAND := "res://scenes/command.tscn"

var Empire: Node
var counts := {}


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	autoload("Saves").pending = {}
	Empire.reset()
	for t in Help.topics():
		Help.mark(str(t.get("id", "")))  # no first-time card pausing the table
	Empire.set_speed(0)


func after_each() -> void:
	tree.paused = false
	Empire.set_speed(Empire.SPEED_1X)


func _watch(layers: Dictionary) -> void:
	for name in layers:
		counts[name] = 0
		(layers[name] as CanvasItem).draw.connect(func(): counts[name] += 1)


func _zero() -> void:
	for k in counts:
		counts[k] = 0


func test_idle_table_does_not_redraw() -> void:
	var cmd := await goto(COMMAND, 20)
	if not check(cmd != null and cmd.scene_file_path == COMMAND, "command table running"):
		return
	_watch({"paint": cmd.paint_canvas, "map": cmd.map_canvas, "selected": cmd.sel_canvas, "labels": cmd.labels_canvas,
		"overlay": cmd.overlay, "fog": cmd.fog_canvas})
	await frames(40)  # the camera settles and the first checks run
	_zero()
	await frames(45)  # more than one of the twice-a-second checks, at headless speed
	for k in ["paint", "map", "selected", "labels", "overlay"]:
		check_eq(counts[k], 0, "%s is not redrawn while nothing changes" % k)
	check(counts["fog"] >= 40, "the fog drifts every frame")
	var a0: float = cmd.sel_canvas.self_modulate.a
	await frames(5)
	check(cmd.sel_canvas.self_modulate.a != a0 or Engine.get_process_frames() == 0, "the gold outline pulses without redrawing")

	# Selecting another province redraws its outline, the labels and the panel.
	_zero()
	cmd.selected = (cmd.selected + 1) % cmd.territory.provinces.size()
	await frames(2)
	for k in ["selected", "labels", "overlay"]:
		check(counts[k] >= 1, "%s redrawn after a new selection" % k)
	check_eq(counts["paint"], 0, "the painting is not redrawn for a selection")

	# A resource change reaches the bar.
	await frames(2)
	_zero()
	Empire.res["gilt"] = int(Empire.res["gilt"]) + 7
	await frames(2)
	check(counts["overlay"] >= 1, "the overlay redrawn after gilt changed")

	# A setting changed from the options menu reaches the map's marks.
	await frames(2)
	_zero()
	Access.map_symbols = not Access.map_symbols
	await frames(2)
	check(counts["labels"] >= 1, "the labels redrawn after a map setting changed")
	Access.map_symbols = not Access.map_symbols

	# Zooming moves every map layer.
	await frames(2)
	_zero()
	cmd.zoom_by(1.4)
	await frames(3)
	for k in ["paint", "map", "selected", "labels"]:
		check(counts[k] >= 1, "%s redrawn while zooming" % k)

	# A new day re-bakes the map and redraws everything that shows the state.
	await frames(30)
	_zero()
	Empire.day_t = 0.9999
	Empire.set_speed(Empire.SPEEDS.size() - 1)
	await frames(3)
	Empire.set_speed(0)
	await frames(2)
	for k in ["map", "labels", "overlay"]:
		check(counts[k] >= 1, "%s redrawn at dawn" % k)
