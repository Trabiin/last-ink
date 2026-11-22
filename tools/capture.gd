extends SceneTree
## Trailer and store capture (issue #152). Plays a scripted "shot" from tools/capture/shots/*.json:
## the scene and party, a camera path, a staged fight, and no HUD. Runs only from the command line
## (tools/* is left out of every export), so none of this reaches players.
##
## Usually run through tools/capture.sh, which records it with Godot's movie maker and trims it:
##   tools/capture.sh meadow_skirmish                 1080p60 PNG frames -> MP4
##   tools/capture.sh meadow_skirmish --4k            2160p60
## By hand (preview at 1280x720, no recording):
##   xvfb-run -a godot --path . -s tools/capture.gd -- shot=meadow_skirmish
##
## Extra key=value arguments override the shot file's top-level keys for one run:
##   seconds=4  day=0.9  seed=3  map=gutterwoods  party=ash,odile,velvette  ui=1 (keep the HUD)
##
## Time in a shot is in seconds from the first recorded frame, counted in fixed 1/60 s steps when
## recording with --fixed-fps 60, so the same shot gives the same cut every time (enemies are
## seeded too). The format is documented in tools/capture/README.md.

const SHOT_DIR := "res://tools/capture/shots/"
const TILE := 16.0

var frame := 0
var args := {}
var shot := {}
var scene_kind := "mission"
var started := false  # the scene is up and settled: the timeline is running
var start_frame := -1
var settle := 0  # frames left before the timeline starts
var t := 0.0  # seconds since the first recorded frame
var cam: Camera2D
var cam_keys: Array = []
var beats: Array = []
var next_beat := 0
var duration := 6.0
var hide_ui := true
var god := true
var marks := {}  # beat "mark": name -> Vector2, for later "at" specs
# Class scripts need the autoloads, which exist only after the first frame: loaded in _setup.
var _EnemyKinds
var _Techs
var _AllyTechs
var _Abilities
var _AllyAI


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var id := str(args.get("shot", ""))
	if id == "":
		push_error("capture: give shot=<name> (a file in tools/capture/shots/)")
		quit(1)
		return
	shot = load_shot(id)
	if shot.is_empty():
		quit(1)
		return
	for k in args:  # one-run overrides of the shot's top-level keys
		if k in ["shot", "out"]:
			continue
		match k:
			"party":
				shot["party"] = Array(str(args[k]).split(","))
			"ui":
				shot["hide_ui"] = str(args[k]) in ["0", "false"]
			_:
				shot[k] = float(args[k]) if str(args[k]).is_valid_float() else args[k]
	duration = float(shot.get("seconds", 6.0))
	hide_ui = bool(shot.get("hide_ui", true))
	god = bool(shot.get("god", true))
	scene_kind = str(shot.get("scene", "mission"))
	cam_keys = shot.get("camera", [])
	beats = shot.get("beats", []).duplicate()
	beats.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))


## Reads tools/capture/shots/<id>.json (or a path). Returns {} and reports why when it can't.
static func load_shot(id: String) -> Dictionary:
	var path := id if id.ends_with(".json") else SHOT_DIR + id + ".json"
	if not FileAccess.file_exists(path):
		push_error("capture: no shot file " + path)
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		push_error("capture: %s is not a JSON object" % path)
		return {}
	return d


const SCENES := ["mission", "town", "command", "title"]
const EASES := ["smooth", "linear", "in", "out", "cut"]
const BEAT_KEYS := ["t", "spawn", "count", "at", "hp", "tech", "order", "swing", "ability", "slot", "move", "walk",
	"for", "preset", "to", "shake", "slow", "mark", "call", "args", "say"]
const KEY_KEYS := ["t", "at", "follow", "off", "zoom", "ease", "focus"]


## What is wrong with a shot, in words (empty when it is fine). Needs the autoloads (game data).
## Checked before every capture and by tests/test_capture.gd for every file in tools/capture/shots/.
static func problems(d: Dictionary) -> Array:
	var out := []
	var scene := str(d.get("scene", "mission"))
	if not scene in SCENES:
		out.append("scene '%s' is not one of %s" % [scene, SCENES])
	if float(d.get("seconds", 6.0)) <= 0.0:
		out.append("seconds must be above 0")
	if scene == "mission":
		var m: Dictionary = load("res://scripts/missions.gd").find(str(d.get("mission", "meadow_patrol")))
		if m.is_empty():
			out.append("no mission '%s' in data/missions.json" % d.get("mission"))
	if d.has("map") and not FileAccess.file_exists("res://maps/%s.txt" % d["map"]):
		out.append("no map maps/%s.txt" % d["map"])
	var heroes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/heroes.json")).get("heroes", {})
	var party: Array = d.get("party", ["ash", "bran", "gristle"])
	if party.is_empty() or party.size() > 3:
		out.append("a party is 1 to 3 heroes")
	for id in party:
		if not heroes.has(id):
			out.append("'%s' is not a field hero (data/heroes.json)" % id)
	var presets = load("res://scripts/ally_ai.gd").PRESETS
	for id in d.get("presets", {}):
		if not id in party:
			out.append("preset for '%s', who is not in the party" % id)
		if not presets.has(str(d["presets"][id])):
			out.append("preset '%s' is not one of %s" % [d["presets"][id], presets.keys()])
	var kinds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")).get("kinds", {})
	var who := party.duplicate()
	who.append_array(["all", "leader"])
	var last := -1.0
	for k in d.get("camera", []):
		for key in k:
			if not key in KEY_KEYS:
				out.append("camera key has an unknown field '%s'" % key)
		if float(k.get("t", 0.0)) < last:
			out.append("camera keys must be in time order (t=%s)" % k.get("t"))
		last = float(k.get("t", 0.0))
		if k.has("ease") and not str(k["ease"]) in EASES:
			out.append("ease '%s' is not one of %s" % [k["ease"], EASES])
		if k.has("follow"):
			var f := str(k["follow"])
			if not (f in ["party", "enemies", "start", "blank", "leader"] or f.begins_with("mark:") or f in party):
				out.append("camera follows '%s', who is not in the party" % f)
	for b in d.get("beats", []):
		if not b.has("t"):
			out.append("a beat has no t")
		for key in b:
			if not key in BEAT_KEYS:
				out.append("beat t=%s has an unknown field '%s'" % [b.get("t"), key])
		if b.has("spawn") and not kinds.has(str(b["spawn"])):
			out.append("beat t=%s spawns '%s', not an enemy kind (data/enemies.json)" % [b.get("t"), b["spawn"]])
		for key in ["tech", "order", "swing", "ability", "move", "preset"]:
			if b.has(key) and not str(b[key]) in who:
				out.append("beat t=%s: '%s' for '%s', who is not in the party" % [b.get("t"), key, b[key]])
		if b.has("to") and not presets.has(str(b["to"])):
			out.append("beat t=%s: preset '%s' is not one of %s" % [b.get("t"), b["to"], presets.keys()])
		if (b.has("spawn") or b.has("tech") or b.has("walk")) and scene != "mission" and not (b.has("walk") and scene == "town"):
			out.append("beat t=%s only works in a mission" % b.get("t"))
	return out


func _process(delta: float) -> bool:
	frame += 1
	if frame == 2:
		_setup()
	elif frame > 2 and not started:
		_wait_for_scene()
	elif started:
		_tick(delta)
	if hide_ui and frame > 2:
		_hide_ui()
	return false


# ---------------------------------------------------------------- setup


func _setup() -> void:
	var bad := problems(shot)
	if not bad.is_empty():
		for line in bad:
			push_error("capture: " + line)
		quit(1)
		return
	_EnemyKinds = load("res://scripts/enemy_kinds.gd")
	_Techs = load("res://scripts/techs.gd")
	_AllyTechs = load("res://scripts/ally_techs.gd")
	_Abilities = load("res://scripts/abilities.gd")
	_AllyAI = load("res://scripts/ally_ai.gd")
	var empire = root.get_node("Empire")
	empire.reset()
	seed(int(shot.get("seed", 1)))
	var dlg = load("res://scripts/dialogue.gd")  # loaded late: class scripts need the autoloads
	for k in dlg.data().get("talks", {}):
		dlg.mark_seen("talk:" + str(k))  # no conversation in the way
	var help = load("res://scripts/help.gd")
	for tp in help.topics():  # no explainer cards holding the scene still
		help.mark(str(tp.get("id", "")))
	var st = load("res://scripts/settings.gd")
	for k in shot.get("fx", {}):  # Options > Visual effects sliders for this shot
		st.fx[k] = int(shot["fx"][k])
	if shot.has("day"):
		empire.day_t = float(shot["day"])  # 0.5 noon, 0.75 dusk, 0.9 night
	var party: Array = shot.get("party", ["ash", "bran", "gristle"])
	for id in empire.recruits:
		if empire.recruits[id]["role"] == "party":
			empire.recruits[id]["role"] = "idle"
	for id in party:
		empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
	for id in shot.get("presets", {}):  # ally AI preset per hero: aggressive, balanced, distance, support
		empire.ai_presets[id] = shot["presets"][id]
	if shot.has("levels"):  # every Hollowmark building at this level, and the Wardlamp lit
		for id in empire.building_ids():
			if id != "wardlamp":
				empire.buildings[id] = int(shot["levels"])
		empire.lamps["hollowmark"] = clampi(int(shot["levels"]) - 1, 1, 2)
	match scene_kind:
		"mission":
			var m: Dictionary = load("res://scripts/missions.gd").find(str(shot.get("mission", "meadow_patrol"))).duplicate(true)
			if shot.has("map"):
				m["map"] = "res://maps/%s.txt" % shot["map"]
			m.erase("intro")
			if bool(shot.get("clear", true)):
				m["respawn"] = false  # no stream of Nibblers: only what the beats spawn
			empire.active_mission = m
			change_scene_to_file("res://scenes/main.tscn")
		"town":
			if shot.has("map"):
				load("res://scripts/hub.gd").map_override = "res://maps/%s.txt" % shot["map"]
			change_scene_to_file("res://scenes/hub.tscn")
		"command":
			change_scene_to_file("res://scenes/command.tscn")
		"title":
			change_scene_to_file("res://scenes/title.tscn")
		_:
			push_error("capture: unknown scene '%s' (mission, town, command, title)" % scene_kind)
			quit(1)


## Waits a few frames after the scene is in so sprites, light and music have settled.
func _wait_for_scene() -> void:
	var cur := current_scene
	if cur == null or not cur.is_node_ready():
		return
	if settle == 0 and start_frame < 0:
		settle = int(shot.get("settle", 20))
		_stage(cur)
		start_frame = -2
		return
	settle -= 1
	if settle > 0:
		return
	started = true
	start_frame = frame
	print("CAPTURE_START frame=%d drawn=%d" % [frame, Engine.get_frames_drawn()])
	_tick(0.0)


## The scene is up: clear it, place the party, set up the camera.
func _stage(cur: Node) -> void:
	seed(int(shot.get("seed", 1)))  # the scene randomizes on _ready; fights replay the same from here
	if "heroes" in cur and bool(shot.get("clear", true)) and scene_kind == "mission":
		for e in cur.get_tree().get_nodes_in_group("enemies"):
			e.queue_free()
	if shot.has("party_at") and "heroes" in cur:
		var p := pos(shot["party_at"])
		var offs := [Vector2.ZERO, Vector2(-20, 14), Vector2(20, 14), Vector2(0, 26)]
		for i in cur.heroes.size():
			cur.heroes[i].global_position = p + offs[i % offs.size()]
	if "heroes" in cur:
		if bool(shot.get("all_ai", scene_kind == "mission")):  # nobody waits for a player
			for h in cur.heroes:
				h.controlled = false
	if "respawn_t" in cur and bool(shot.get("clear", true)):
		cur.respawn_t = 1e9
	if cur is Node2D and "camera" in cur:
		cam = Camera2D.new()
		cam.zoom = cur.camera.zoom
		for side in ["left", "top", "right", "bottom"]:
			cam.set("limit_" + side, cur.camera.get("limit_" + side))
		cam.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
		cur.add_child(cam)
		cam.global_position = cur.camera.global_position
		cam.make_current()


# ---------------------------------------------------------------- the timeline


func _tick(_delta: float) -> void:
	t = float(frame - start_frame) / 60.0  # recorded time: one frame is 1/60 s under --fixed-fps 60
	var cur := current_scene
	while next_beat < beats.size() and float(beats[next_beat].get("t", 0.0)) <= t + 0.0001:
		_beat(cur, beats[next_beat])
		next_beat += 1
	if god and cur != null and "heroes" in cur:
		for h in cur.heroes:
			if not h.dead:
				h.hp = maxi(h.hp, int(h.max_hp * 0.35))  # dents show, nobody goes down
	_camera(cur)
	if t >= duration:
		print("CAPTURE_END frame=%d drawn=%d" % [frame, Engine.get_frames_drawn()])
		quit()


## Hides every CanvasLayer the game made: HUD, touch buttons, banter, menus, cards. The world,
## its light and its effects are drawn outside them and stay.
func _hide_ui() -> void:
	var cur := current_scene
	if cur == null or scene_kind in ["command", "title"]:
		return
	for c in root.find_children("*", "CanvasLayer", true, false):
		if c.visible:
			c.visible = false
	if not bool(shot.get("numbers", true)):  # floating damage numbers and tech names
		for f in cur.find_children("*", "Fx", true, false):
			if f.kind == 0 and f.visible:
				f.visible = false
	if not bool(shot.get("bars", true)) and "heroes" in cur:
		for h in cur.heroes:
			if h.overlay:
				h.overlay.visible = false


## A point in the world from a shot spec, in tiles unless said otherwise:
##   [x, y]                         a tile
##   {"from": "start", "off": [x, y]}  from the party's starting tile ("start", "blank" edge,
##                                   "party" centre, "hero:<id>", "mark:<name>", "enemies" centre)
func pos(spec) -> Vector2:
	var cur := current_scene
	if spec is Array:
		return Vector2(float(spec[0]) + 0.5, float(spec[1]) + 0.5) * TILE
	if spec is String:
		spec = {"from": spec}
	var off := Vector2.ZERO
	if spec.has("off"):
		off = Vector2(float(spec["off"][0]), float(spec["off"][1])) * TILE
	var from := str(spec.get("from", "start"))
	var base := Vector2.ZERO
	if from == "start" and cur and "area" in cur:
		base = cur.area.party_start
	elif from == "blank" and cur and "blank" in cur and cur.blank:
		base = Vector2(cur.blank.base_x, cur.area.party_start.y)
	elif from == "party" and cur and "heroes" in cur:
		var n := 0
		for h in cur.heroes:
			if not h.dead:
				base += h.global_position
				n += 1
		base /= maxf(n, 1)
	elif from.begins_with("hero:"):
		var h = hero(from.substr(5))
		if h:
			base = h.global_position
	elif from.begins_with("mark:"):
		base = marks.get(from.substr(5), Vector2.ZERO)
	elif from == "enemies" and cur:
		var es := cur.find_children("*", "Enemy", true, false).filter(func(e): return not e.dead)
		for e in es:
			base += e.global_position
		base = base / es.size() if es.size() > 0 else pos("party")
	return base + off


func hero(id: String):
	var cur := current_scene
	if cur == null or not ("heroes" in cur):
		return null
	if id == "leader":
		return cur.heroes[0]
	for h in cur.heroes:
		if h.hero_id == id:
			return h
	return null


## One staged moment. Keys (all optional except t):
##   spawn: enemy kind, count, at, hp   enemies appear (packs come out as their kind says; hp scales)
##   tech: hero id ("all")              that hero fires its charged tech now
##   order: hero id ("all")             that ally charges its tech the AI way (gauge, telegraph)
##   ability: hero id, slot (1-4)       that hero uses an ability
##   swing: hero id ("all")             a basic attack
##   move: hero id, at                  teleports a hero (between cuts)
##   walk: [x, y], for (seconds)        the leader walks that way as if the stick were held
##   preset: hero id, to                switches the ally AI preset
##   shake: amount                      screen shake
##   slow: factor, for (seconds)        slow motion (Engine.time_scale); for=0 holds until changed
##   mark: name, at                     remembers a point for later {"from": "mark:<name>"}
##   call: "path.method", args          calls into the scene (e.g. "dialogue_box.play")
##   say: "text"                        prints to the log (for cue sheets)
func _beat(cur: Node, b: Dictionary) -> void:
	if b.has("say"):
		print("CAPTURE_BEAT t=%.2f %s" % [t, b["say"]])
	if b.has("mark"):
		marks[str(b["mark"])] = pos(b.get("at", "party"))
	if b.has("spawn") and cur and "entities" in cur:
		var at := pos(b.get("at", {"from": "party", "off": [5, 0]}))
		var n := int(b.get("count", 1))
		for i in n:
			var p := at + Vector2(0, (i - (n - 1) / 2.0) * 22.0) + Vector2((i % 2) * 14.0, 0)
			for e in _EnemyKinds.spawn(cur.entities, p, cur.mission, str(b["spawn"])):
				e.died.connect(cur._on_enemy_died)
				e.max_hp = int(e.max_hp * float(b.get("hp", 1.0)))  # hp: 2 keeps them up longer on screen
				e.hp = e.max_hp
	for key in ["tech", "order", "swing"]:
		if b.has(key):
			for h in _heroes_of(str(b[key])):
				if key != "order":
					_face_nearest(h)
				match key:
					"tech":
						_Techs.fire(h)
					"order":
						_AllyTechs.order(h)
					"swing":
						h.try_attack()
	if b.has("ability"):
		for h in _heroes_of(str(b["ability"])):
			_Abilities.use(h, int(b.get("slot", 1)) - 1)
	if b.has("move"):
		var h = hero(str(b["move"]))
		if h:
			h.global_position = pos(b.get("at", "start"))
	if b.has("walk"):
		_walk(Vector2(float(b["walk"][0]), float(b["walk"][1])))
		var go := float(b.get("for", 0.0))
		if go > 0.0:
			beats.insert(next_beat + 1, {"t": float(b["t"]) + go, "walk": [0, 0]})
			beats.sort_custom(func(x, y): return float(x.get("t", 0.0)) < float(y.get("t", 0.0)))
	if b.has("preset"):
		for h in _heroes_of(str(b["preset"])):
			h.ai_style = _AllyAI.preset_id(str(b.get("to", "balanced")))
	if b.has("shake") and cur and cur.has_method("shake"):
		cur.shake(float(b["shake"]))
	if b.has("slow"):
		Engine.time_scale = float(b["slow"])
		var hold := float(b.get("for", 0.0))
		if hold > 0.0:
			beats.insert(next_beat + 1, {"t": float(b["t"]) + hold, "slow": 1.0})
			beats.sort_custom(func(x, y): return float(x.get("t", 0.0)) < float(y.get("t", 0.0)))
	if b.has("call") and cur:
		var path := str(b["call"]).split(".")
		var obj: Object = cur
		for j in path.size() - 1:
			obj = obj.get(path[j])
		obj.callv(path[path.size() - 1], b.get("args", []))


## Walks the leader as if the stick were held (the others follow the way allies do). [0, 0] lets go,
## and the leader goes back to the AI when the shot has everyone on AI.
func _walk(dir: Vector2) -> void:
	var cur := current_scene
	var axes := {"move_right": dir.x, "move_left": -dir.x, "move_down": dir.y, "move_up": -dir.y}
	for action in axes:
		if axes[action] > 0.0:
			Input.action_press(action, minf(axes[action], 1.0))
		else:
			Input.action_release(action)
	if cur and "leader" in cur and cur.leader:
		cur.leader.controlled = dir != Vector2.ZERO or not bool(shot.get("all_ai", scene_kind == "mission"))


## Turns a hero toward the closest enemy, so a staged swing or tech lands on someone.
func _face_nearest(h) -> void:
	var best = null
	var best_d := 1e9
	for e in h.get_tree().get_nodes_in_group("enemies"):
		if not e.dead and e.global_position.distance_to(h.global_position) < best_d:
			best = e
			best_d = e.global_position.distance_to(h.global_position)
	if best != null:
		h.facing = (best.global_position - h.global_position).normalized()


func _heroes_of(id: String) -> Array:
	var cur := current_scene
	if cur == null or not ("heroes" in cur):
		return []
	if id == "all":
		return cur.heroes.filter(func(h): return not h.dead)
	var h = hero(id)
	return [h] if h != null else []


# ---------------------------------------------------------------- camera


## The camera path: keys {t, at | follow, zoom, ease}. Between two keys the camera eases from one
## to the next; "follow" targets ("party", "leader", a hero id, "enemies") move, so the path does
## too. Before the first key and after the last one it holds. No keys: it follows the party.
func _camera(cur: Node) -> void:
	if cam == null:
		_canvas_camera()
		return
	cam.make_current()
	if cam_keys.is_empty():
		cam.global_position = pos("party") + Vector2(0, -10)
		return
	var i := 0
	while i < cam_keys.size() - 1 and float(cam_keys[i + 1].get("t", 0.0)) <= t:
		i += 1
	var a: Dictionary = cam_keys[i]
	var b: Dictionary = cam_keys[mini(i + 1, cam_keys.size() - 1)]
	var ta := float(a.get("t", 0.0))
	var tb := float(b.get("t", 0.0))
	var w := 0.0 if tb <= ta or t <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	w = _ease(w, str(b.get("ease", shot.get("ease", "smooth"))))
	var pa := _key_pos(a)
	var pb := _key_pos(b)
	var za := float(a.get("zoom", cam.zoom.x))
	var zb := float(b.get("zoom", za))
	cam.global_position = pa.lerp(pb, w)
	cam.zoom = Vector2.ONE * lerpf(za, zb, w)
	if "shake_amount" in cur:
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * float(cur.shake_amount)


func _key_pos(k: Dictionary) -> Vector2:
	if k.has("follow"):
		var f := str(k["follow"])
		var spec := {"from": f if f in ["party", "enemies", "start", "blank"] or f.begins_with("mark:") else "hero:" + f}
		if k.has("off"):
			spec["off"] = k["off"]
		return pos(spec) + Vector2(0, -10)
	return pos(k.get("at", "party"))


## Command Table and title: no Camera2D, so a slow push-in scales the whole canvas instead.
## Keys use "zoom" and "focus" ([x, y] as fractions of the screen, 0.5,0.5 = centre).
func _canvas_camera() -> void:
	if cam_keys.is_empty():
		return
	var i := 0
	while i < cam_keys.size() - 1 and float(cam_keys[i + 1].get("t", 0.0)) <= t:
		i += 1
	var a: Dictionary = cam_keys[i]
	var b: Dictionary = cam_keys[mini(i + 1, cam_keys.size() - 1)]
	var ta := float(a.get("t", 0.0))
	var tb := float(b.get("t", 0.0))
	var w := 0.0 if tb <= ta or t <= ta else clampf((t - ta) / (tb - ta), 0.0, 1.0)
	w = _ease(w, str(b.get("ease", shot.get("ease", "smooth"))))
	var z := lerpf(float(a.get("zoom", 1.0)), float(b.get("zoom", a.get("zoom", 1.0))), w)
	var fa: Array = a.get("focus", [0.5, 0.5])
	var fb: Array = b.get("focus", fa)
	var size := root.get_visible_rect().size
	var focus := Vector2(lerpf(fa[0], fb[0], w), lerpf(fa[1], fb[1], w)) * size
	# Scale about the focus point, kept on screen.
	var origin := focus - focus * z
	origin = origin.clamp(size - size * z, Vector2.ZERO)
	root.canvas_transform = Transform2D(0.0, Vector2.ONE * z, 0.0, origin)


static func _ease(w: float, kind: String) -> float:
	match kind:
		"linear":
			return w
		"in":
			return w * w
		"out":
			return 1.0 - (1.0 - w) * (1.0 - w)
		"cut":
			return 1.0 if w > 0.0 else 0.0
		_:  # "smooth": ease in and out
			return w * w * (3.0 - 2.0 * w)
