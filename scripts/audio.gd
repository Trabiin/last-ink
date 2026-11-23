extends Node
## Music and sound effects (issue #20). Autoload "Audio".
##
## Music picks itself: every few frames it looks at the current scene (title, Hollowmark,
## Command Table, a mission) and the active mission, and cross-fades to the matching track.
## Nothing else has to start or stop music. Tracks live in assets/audio/music/<id>.ogg.
##
## Sound effects: Audio.sfx("<name>") plays assets/audio/sfx/<name>.wav on the "SFX" bus.
## Other code that may run before this autoload exists can call it safely with
##   var a := get_node_or_null("/root/Audio"); if a: a.sfx("alert")
##
## Buses: music plays on "Music", effects on "SFX" (both children of Master). The Options
## screen (#14) owns their volume sliders; this script only creates the buses if missing.
##
## Browsers block sound until the page gets a click, key or touch, so on the web build
## nothing plays until the first input. The Blank hums (a code-made drone) when the party
## leader walks near its edge or near a Blot.

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DB := -7.0
const SFX_DB := -5.0
const FADE := 1.2  # seconds for a music cross-fade (real time, ignores time_scale)
const VOICES := 10
const HUM_RANGE := 150.0  # px from the Blank's edge (or a Blot) where the hum starts

## Per-effect tweaks: volume offset (dB), random pitch spread, minimum gap between plays (s).
const SFX := {
	"ui_move": {"db": -6.0, "gap": 0.03},
	"ui_ok": {"db": -4.0},
	"ui_back": {"db": -6.0},
	"swing": {"db": -6.0, "spread": 0.08, "gap": 0.05},
	"heavy": {"db": -3.0, "spread": 0.05},
	"hit": {"db": -4.0, "spread": 0.12, "gap": 0.04},
	"hurt": {"db": -3.0, "spread": 0.06, "gap": 0.12},
	"death": {"db": -8.0, "spread": 0.15, "gap": 0.06},
	"hero_down": {"db": -2.0},
	"block": {"db": -6.0, "spread": 0.06, "gap": 0.08},
	"alert": {"db": -4.0, "gap": 0.3},
	"fanfare": {"db": -2.0},
	"levelup": {"db": -3.0, "gap": 0.25},
	"coin": {"db": -8.0, "spread": 0.1, "gap": 0.06},
	"talk": {"db": -10.0, "gap": 0.05},
	"error": {"db": -6.0, "gap": 0.2},
	"portal": {"db": -5.0},
	"burst": {"db": -6.0, "spread": 0.1, "gap": 0.05},
	"cast": {"db": -6.0, "spread": 0.05, "gap": 0.05},
	"pause_in": {"db": -6.0},
	"pause_out": {"db": -6.0},
}

var unlocked := false  # true once the browser allows sound (always true off the web)
var track := ""  # the track that is playing (or fading in)
var _music: Array[AudioStreamPlayer] = []
var _front := 0  # index into _music of the player fading in / playing
var _fade_t := 1.0
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _streams := {}
var _last_play := {}
var _hum: AudioStreamPlayer
var _hum_level := 0.0
var _check_t := 0.0
var _last_scene: Node = null
var _blots: Array = []
var _last_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_buses()
	unlocked = not OS.has_feature("web")
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"  # no-tr: audio bus
		p.volume_db = -80.0
		add_child(p)
		_music.append(p)
	for i in VOICES:
		var v := AudioStreamPlayer.new()
		v.bus = "SFX"  # no-tr: audio bus
		add_child(v)
		_voices.append(v)
	_hum = AudioStreamPlayer.new()
	_hum.bus = "SFX"  # no-tr: audio bus
	_hum.stream = _hum_stream()
	_hum.volume_db = -80.0
	add_child(_hum)
	_last_ms = Time.get_ticks_msec()


## Creates the "Music" and "SFX" buses under Master if they don't exist yet. Safe to call twice;
## the Options screen does the same check.
static func ensure_buses() -> void:
	for bus_name in ["Music", "SFX"]:  # no-tr: audio bus
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _input(event: InputEvent) -> void:
	if unlocked:
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch \
			or event is InputEventJoypadButton:
		if event.is_pressed():
			unlocked = true
			track = ""  # start whatever this scene wants right away


func _process(_delta: float) -> void:
	# Real-time delta: the quick menu slows Engine.time_scale, music fades shouldn't.
	var now := Time.get_ticks_msec()
	var dt := minf((now - _last_ms) / 1000.0, 0.1)
	_last_ms = now
	if not unlocked:
		return
	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = 0.25
		var want := pick_track()
		if want != track:
			play_music(want)
		_scan_blots()
	_update_fade(dt)
	_update_hum(dt)


# ---------------------------------------------------------------- music

## Which track fits what's on screen now ("" = silence).
func pick_track() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return track
	var path := scene.scene_file_path
	if path.ends_with("title.tscn"):
		return "title"
	if path.ends_with("hub.tscn"):
		return "town"
	if path.ends_with("command.tscn"):
		return "command"
	if path.ends_with("main.tscn"):
		return mission_track(_active_mission())
	return track


static func mission_track(m: Dictionary) -> String:
	var obj: Dictionary = m.get("objective", {})
	if str(obj.get("kind", "")) == "boss":
		return "abbot" if str(obj.get("boss", "")) == "abbot" else "boss"
	if str(m.get("map", "")).contains("tax_office"):
		return "breakout"
	if str(m.get("type", "")) in ["reclaim", "defense"]:
		return "blank"
	if str(m.get("province", "")) in ["gutterwoods", "saltreed", "gallows"]:
		return "woods"
	var tree := Engine.get_main_loop() as SceneTree
	var emp: Node = tree.root.get_node_or_null("Empire") if tree != null else null
	if emp != null and str(emp.territory().find(str(m.get("province", ""))).get("region", "")) == "abbey":
		return "abbey"  # Chapter 2's region track (issue #28)
	return "meadow"


func _active_mission() -> Dictionary:
	var e := get_node_or_null("/root/Empire")
	if e == null:
		return {}
	var m = e.get("active_mission")
	return m if m is Dictionary else {}


## Cross-fades to a track by id (file name in assets/audio/music without .ogg). "" fades out.
func play_music(id: String) -> void:
	var was := track
	track = id
	if id == "":
		_fade_t = 0.0
		_front = 1 - _front
		_music[_front].stop()
		return
	var stream := _music_stream(id)
	if stream == null:
		return
	_front = 1 - _front
	var p := _music[_front]
	p.stream = stream
	p.volume_db = -80.0
	p.play()
	_fade_t = 0.0 if was != "" else 0.5  # first track: a shorter fade-in
	if was != "" and id != "title":
		if _active_mission().size() > 0 and get_tree().current_scene and get_tree().current_scene.scene_file_path.ends_with("main.tscn"):
			sfx("portal")


func _music_stream(id: String) -> AudioStream:
	var key := "music:" + id
	if not _streams.has(key):
		var path := MUSIC_DIR + id + ".ogg"
		var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		_streams[key] = s
	return _streams[key]


func _update_fade(dt: float) -> void:
	if _fade_t >= 1.0:
		return
	_fade_t = minf(_fade_t + dt / FADE, 1.0)
	var front := _music[_front]
	var back := _music[1 - _front]
	if track != "":
		front.volume_db = lerpf(-40.0, MUSIC_DB, sqrt(_fade_t))
	back.volume_db = lerpf(back.volume_db, -80.0, _fade_t)
	if _fade_t >= 1.0:
		back.stop()
		back.volume_db = -80.0


# ---------------------------------------------------------------- effects

## Plays a one-shot effect. pitch: 1.0 = as recorded; each effect also gets a small random spread.
func sfx(id: String, pitch := 1.0, db := 0.0) -> void:
	if not unlocked:
		return
	var cfg: Dictionary = SFX.get(id, {})
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(id, -10.0)) < float(cfg.get("gap", 0.0)):
		return
	var stream := _sfx_stream(id)
	if stream == null:
		return
	_last_play[id] = now
	var v := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	var spread := float(cfg.get("spread", 0.0))
	v.stream = stream
	v.pitch_scale = maxf(0.1, pitch * (1.0 + randf_range(-spread, spread)))
	v.volume_db = SFX_DB + float(cfg.get("db", 0.0)) + db
	v.play()


func _sfx_stream(id: String) -> AudioStream:
	var key := "sfx:" + id
	if not _streams.has(key):
		var path := SFX_DIR + id + ".wav"
		_streams[key] = load(path) if ResourceLoader.exists(path) else null
	return _streams[key]


## Shorthand for actors taking a hit: heroes sound different from enemies.
func hit(is_hero: bool, fatal: bool) -> void:
	if fatal:
		sfx("hero_down" if is_hero else "death")
		if not is_hero:
			sfx("hit", 0.8)
	else:
		sfx("hurt" if is_hero else "hit")


# ---------------------------------------------------------------- the Blank's hum

func _scan_blots() -> void:
	_blots.clear()
	var scene := get_tree().current_scene
	if scene == null or not scene.scene_file_path.ends_with("main.tscn"):
		return
	for c in scene.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path.ends_with("/blot.gd"):  # by path: no class deps in an autoload
			_blots.append(c)


func _update_hum(dt: float) -> void:
	var target := 0.0
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path.ends_with("main.tscn") and not get_tree().paused:
		var leader = scene.get("leader")
		if leader is Node2D and is_instance_valid(leader):
			var pos: Vector2 = leader.global_position
			var near := INF
			var blank = scene.get("blank")
			if blank != null and is_instance_valid(blank) and blank.has_method("edge_x"):
				near = maxf(blank.edge_x(pos.y) - pos.x, 0.0)
			for b in _blots:
				if is_instance_valid(b):
					near = minf(near, (b as Node2D).global_position.distance_to(pos))
			target = clampf(1.0 - near / HUM_RANGE, 0.0, 1.0)
	_hum_level = move_toward(_hum_level, target, dt * 1.5)
	if _hum_level <= 0.01:
		if _hum.playing:
			_hum.stop()
		return
	if not _hum.playing:
		_hum.play()
	_hum.volume_db = linear_to_db(_hum_level) - 6.0
	_hum.pitch_scale = 1.0 + _hum_level * 0.08


## A 4-second seamless drone made in code: two low tones beating against each other,
## a faint high whine and soft static, so the Blank sounds like an empty, humming page.
static func _hum_stream() -> AudioStreamWAV:
	var rate := 22050
	var secs := 4.0
	var n := int(rate * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noise := 0.0
	for i in n:
		var t := float(i) / rate
		# Frequencies are whole cycles per 4 s so the loop point is seamless.
		var s := 0.42 * sin(TAU * 55.0 * t) + 0.32 * sin(TAU * 55.5 * t) + 0.16 * sin(TAU * 110.25 * t)
		s *= 0.75 + 0.25 * sin(TAU * 0.5 * t)
		s += 0.035 * sin(TAU * 1760.0 * t) * (0.5 + 0.5 * sin(TAU * 0.25 * t))
		noise = noise * 0.96 + rng.randf_range(-1.0, 1.0) * 0.04
		s += noise * 0.5
		data.encode_s16(i * 2, int(clampf(s * 0.55, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w
