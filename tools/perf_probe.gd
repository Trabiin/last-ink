extends SceneTree
## Performance probe (issue #35): loads the busiest Act 1 scenes with every visual effect at full,
## lets each settle, then measures frame times, the game's own CPU time per frame, draw calls,
## nodes and memory. Writes a Markdown table.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 --audio-driver Dummy \
##       -s tools/perf_probe.gd -- [seconds] [out.md] [scenes] [fx]
## fx: every Options > Visual effects slider at this value (default 100, the worst case; 0 = the low-end fallback).
##
## scenes (comma list, default all): town_noon, town_night, command, fight, fight_night, defense, boss, tollgate.
## Under xvfb the GPU is software (llvmpipe), so frame times there are a worst case: the column to
## trust across machines is "Game CPU ms" (scripts and physics, which a laptop runs at about the same
## speed). For real fps on a laptop, press F3 in the game (scripts/perf_overlay.gd).
## Nothing is saved; settings are changed in memory only.

const SCENES := ["town_noon", "town_night", "command", "fight", "fight_night", "defense", "boss", "tollgate"]
const WARMUP := 90  # frames before measuring (scene build, first shader compiles)
const CROWD := 30  # enemies kept alive in the big-fight scenes

var _frame := 0
var _seconds := 10.0
var _out := "user://perf.md"
var _queue: Array = []
var _fx := 100
var _cur := ""
var _phase := ""
var _t0 := 0
var _load_ms := 0.0
var _since := 0
var _samples: Array = []
var _cpu: Array = []
var _rows: Array = []
var _peak_static := 0.0
var _draws := 0
var _nodes := 0
var _objects := 0
var _prims := 0
var _vmem := 0.0
var _tex_mem := 0.0
var _last_us := 0
var Empire  # the autoload, found after the first frame
var _open_us := 0  # when this frame's work started (first physics step or process)
var _work: Array = []  # ms of real work per frame: physics + process + draw, without the idle wait


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_seconds = float(a[0])
	if a.size() > 1:
		_out = a[1]
	_queue = Array(a[2].split(",", false)) if a.size() > 2 and a[2] != "all" else SCENES.duplicate()
	if a.size() > 3:
		_fx = int(a[3])


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		physics_frame.connect(_open)
		process_frame.connect(_open)
		var tail := _Tail.new()  # processes last each frame, then closes the frame after the queued redraws
		tail.probe = self
		tail.process_priority = 1 << 30
		tail.process_mode = Node.PROCESS_MODE_ALWAYS
		root.add_child.call_deferred(tail)
		Empire = root.get_node("Empire")
		var saves = root.get_node_or_null("Saves")
		if saves != null:
			saves.dir = "user://perf_scratch/"
		var st = load("res://scripts/settings.gd")
		st.load_settings()
		for f in st.FX:
			st.fx[f[0]] = _fx  # 100 = every effect at full, the worst case the sliders allow
		_next()
		return false
	if _phase == "load":
		if current_scene != null and current_scene.scene_file_path != "":
			_load_ms = (Time.get_ticks_usec() - _t0) / 1000.0
			_phase = "warm"
			_since = 0
	elif _phase == "warm":
		_since += 1
		if _since == 20:
			_stage()
		if _since >= WARMUP:
			_phase = "measure"
			_samples = []
			_cpu = []
			_work = []
			_peak_static = 0.0
			_draws = 0
			_last_us = Time.get_ticks_usec()
			_t0 = Time.get_ticks_msec()
	elif _phase == "measure":
		var now := Time.get_ticks_usec()
		_samples.append((now - _last_us) / 1000.0)
		_last_us = now
		_cpu.append((Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		_peak_static = maxf(_peak_static, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
		_draws = maxi(_draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_prims = maxi(_prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		_vmem = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
		_tex_mem = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
		_keep_busy()
		if Time.get_ticks_msec() - _t0 >= int(_seconds * 1000.0):
			_finish()
	return false


class _Tail extends Node:
	var probe
	func _process(_d: float) -> void:
		probe._close.call_deferred()


func _open() -> void:
	if _open_us == 0:
		_open_us = Time.get_ticks_usec()


func _close() -> void:
	if _open_us != 0 and _phase == "measure":
		_work.append((Time.get_ticks_usec() - _open_us) / 1000.0)
	_open_us = 0


func _next() -> void:
	if _queue.is_empty():
		_write()
		quit(0)
		return
	_cur = _queue.pop_front()
	_phase = "load"
	_t0 = Time.get_ticks_usec()
	_prims = 0
	Empire.reset()
	var dlg = load("res://scripts/dialogue.gd")
	for k in dlg.data().get("talks", {}):
		dlg.mark_seen("talk:" + str(k))  # no conversation in the way
	var help = load("res://scripts/help.gd")
	for t in help.topics():
		help.mark(str(t.get("id", "")))  # no first-time explainers either
	Empire.set_speed(0)
	match _cur:
		"town_noon", "town_night":
			_town(0.5 if _cur == "town_noon" else 0.9)
		"command":
			_town(0.6)
			change_scene_to_file("res://scenes/command.tscn")
		"fight", "fight_night":
			Empire.day_t = 0.5 if _cur == "fight" else 0.9
			_mission("meadow_patrol")
		"defense":
			Empire.day_t = 0.8
			var p: Dictionary = Empire.territory().find("meadow")
			p["owner"] = "you"
			Empire.surge = {"id": "meadow", "day": Empire.day + 1}
			_mission_dict(load("res://scripts/mission_types.gd").defense(p))
		"boss":
			load("res://scripts/progress.gd").award(load("res://scripts/party_picker.gd").mission_party(), 3000)
			_mission("auditor_duel")
		"tollgate":
			Empire.day_t = 0.75
			_mission("tithe_patrol")
		_:
			push_warning("perf_probe: unknown scene " + _cur)
			_next()


func _town(day_t: float) -> void:
	Empire.day_t = day_t
	for id in Empire.building_ids():
		if id != "wardlamp":
			Empire.buildings[id] = Empire.max_level(id)  # a full late-Act-1 town: every building up
	Empire.lamps["hollowmark"] = 2
	for id in Empire.recruit_data:  # everyone on the roster, so the streets are as full as they get
		if not Empire.recruits.has(id):
			Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	change_scene_to_file("res://scenes/hub.tscn")


func _mission(id: String) -> void:
	_mission_dict(load("res://scripts/missions.gd").find(id))


func _mission_dict(m: Dictionary) -> void:
	var party := ["ash", "bran", "gristle"]
	for id in Empire.recruits:
		if Empire.recruits[id]["role"] == "party":
			Empire.recruits[id]["role"] = "idle"
	for id in party:
		Empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
	Empire.active_mission = m.duplicate(true)
	change_scene_to_file(m.get("scene", "res://scenes/main.tscn"))


## Big fights: a crowd of mixed enemies around the party (kept topped up while measuring).
func _stage() -> void:
	if _cur in ["fight", "fight_night", "tollgate"]:
		_top_up()


func _keep_busy() -> void:
	if _cur in ["fight", "fight_night", "tollgate"] and _frame % 30 == 0:
		_top_up()
	var cur := current_scene
	if cur != null and "heroes" in cur:
		for h in cur.heroes:  # nobody dies mid-measure: a wiped party ends the scene
			if "hp" in h and "max_hp" in h:
				h.hp = h.max_hp


func _top_up() -> void:
	var cur := current_scene
	if cur == null or not ("heroes" in cur) or cur.heroes.is_empty() or not ("entities" in cur):
		return
	var alive := cur.get_tree().get_nodes_in_group("enemies").size()
	var kinds := load("res://scripts/enemy_kinds.gd")
	var base: Vector2 = cur.heroes[0].global_position
	var picks := ["nibbler", "nibbler", "spitter", "moth", "enforcer", "sellsword", "scarecrow"]
	for i in maxi(0, CROWD - alive):
		var ang := TAU * float(i) / float(CROWD)
		kinds.spawn(cur.entities, base + Vector2(cos(ang), sin(ang)) * (90.0 + 30.0 * (i % 3)), cur.mission, picks[i % picks.size()])


func _finish() -> void:
	var s := _samples.duplicate()
	s.sort()
	var n := s.size()
	var avg := 0.0
	for v in s:
		avg += v
	avg /= maxf(1.0, n)
	var cpu_avg := 0.0
	for v in _work:
		cpu_avg += v
	cpu_avg /= maxf(1.0, _work.size())
	var c := _work.duplicate()
	c.sort()
	var enemies := current_scene.get_tree().get_nodes_in_group("enemies").size() if current_scene != null else 0
	_rows.append([_cur, _load_ms, 1000.0 / avg if avg > 0 else 0.0, avg, s[int(n * 0.95)] if n > 0 else 0.0, s[n - 1] if n > 0 else 0.0,
		cpu_avg, c[int(c.size() * 0.95)] if not c.is_empty() else 0.0, _draws, _prims, _nodes, _objects, enemies, _peak_static, _vmem, _tex_mem])
	print("perf_probe: %s done (%d frames)" % [_cur, n])
	_next()


func _write() -> void:
	var lines := ["| Scene | Load ms | FPS (xvfb) | Frame ms avg | p95 | worst | Work ms avg | Work p95 | Draw calls | Primitives | Nodes | Objects | Enemies | RAM MB | VRAM MB | Textures MB |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	for r in _rows:
		lines.append("| %s | %d | %.0f | %.1f | %.1f | %.1f | %.2f | %.2f | %d | %d | %d | %d | %d | %.0f | %.0f | %.0f |" % r)
	var text := "\n".join(lines) + "\n\nGPU: %s (%s)\nWindow: %s, visual effects at %d\n" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(), str(root.size), _fx]
	var f := FileAccess.open(_out, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(text)
