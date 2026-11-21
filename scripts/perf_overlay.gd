extends CanvasLayer
## F3: a small performance readout in the top-right corner (issue #35), for checking real hardware.
## Frames per second, frame time (average and worst over the last second), draw calls, nodes,
## memory and video memory, the window size and the GPU. Off by default and not saved; Diag adds it.

const KEY := KEY_F3

var _label: Label
var _times: Array = []  # [msec timestamp, frame ms] over the last second
var _last_us := 0
var _refresh := 0.0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.position = Vector2(-4, 2)
	_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY:
		visible = not visible
		_times.clear()
		_last_us = 0
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		_times.append([Time.get_ticks_msec(), (now - _last_us) / 1000.0])
	_last_us = now
	var cutoff := Time.get_ticks_msec() - 1000
	while not _times.is_empty() and _times[0][0] < cutoff:
		_times.pop_front()
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.25
	_label.text = text()


## The readout as plain lines (also what the label shows).
func text() -> String:
	var avg := 0.0
	var worst := 0.0
	for t in _times:
		avg += t[1]
		worst = maxf(worst, t[1])
	avg /= maxf(1.0, _times.size())
	var lines := [
		"%d fps  %.1f ms (worst %.1f)" % [Engine.get_frames_per_second(), avg, worst],  # no-tr: developer readout (F3), numbers only
		"%d draw calls  %d nodes" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],  # no-tr: developer readout (F3), numbers only
		"RAM %d MB  VRAM %d MB" % [int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)],  # no-tr: developer readout (F3), numbers only
		"%dx%d  %s" % [get_viewport().get_window().size.x, get_viewport().get_window().size.y, RenderingServer.get_video_adapter_name()],
	]
	return "\n".join(lines)
