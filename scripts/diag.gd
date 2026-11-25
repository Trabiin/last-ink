extends Node
## Autoload "Diag": the game's own black box (issue #146).
##
## - Every session writes user://logs/session.log: a header with the game version, OS, CPU, GPU and
##   renderer, then a line each time the scene, mission or save slot changes. The last five sessions
##   are kept (session.1.log is the one before this, and so on).
## - Errors and warnings: on desktop Godot itself writes them to user://logs/godot.log (and keeps the
##   last few sessions as godot<date>.log); our breadcrumbs are printed there too, so every error sits
##   between the lines that say where the player was. The web build has no engine log file, so the
##   browser console's errors and warnings are copied into session.log instead.
## - Next launch: if the last session crashed (desktop: it never reached a clean exit) or logged
##   errors, `previous` says so and the title screen offers to send a report (FeedbackView).
## - Web: the browser gives no clean-exit signal we can wait for, so WEB_HOOK keeps a flag in
##   localStorage that only the page's own pagehide event clears. A page that froze, crashed or lost its
##   graphics never runs pagehide, so the next launch knows the last session ended badly. A lost WebGL
##   context is logged as an error too.
## - Frame times: one "perf" line a minute (average fps, the worst frame) and a "hitch" line for any frame
##   that stalls for half a second or more, so a report says how the game ran before it went wrong.
## - F12 (action "screenshot") saves a screenshot to user://screenshots/ (the web build downloads it).
##
## Nothing here is ever sent anywhere. Reports leave the device only from FeedbackView, when the player
## presses Send (docs/PRIVACY.md).

const LOG_DIR := "user://logs/"
const SHOT_DIR := "user://screenshots/"
const KEEP := 5  # session logs kept: session.log + session.1.log .. session.4.log
const MAX_LOG := 1024 * 1024  # a session log stops growing here (an error loop must not fill the disk)
## Error lines, as the engine writes them on desktop and as we copy them from the browser console.
const ERROR_RE := "^\\s*(SCRIPT ERROR|ERROR|USER ERROR|USER SCRIPT ERROR):"
const WARNING_RE := "^\\s*(WARNING|USER WARNING):"
## Engine noise that is not the game's doing (the same list tools/run_tests.sh ignores).
const NOISE := ["leaked", "still in use at exit", "All audio drivers failed"]
## Printed by _exit_tree on a clean exit: what the engine logs after it is shutdown, not play.
const EXIT_LINE := "[last-ink] exit"
## Copies browser console errors and warnings into a list the game drains (web build only).
const WEB_HOOK := """
(function () {
	if (window.__lastInkLog) return;
	window.__lastInkLog = [];
	var keep = function (level, args) {
		try {
			var text = Array.prototype.map.call(args, function (a) {
				return (a && a.stack) ? String(a.stack) : String(a);
			}).join(' ');
			if (window.__lastInkLog.length < 500) window.__lastInkLog.push([level, text.slice(0, 2000)]);
		} catch (e) {}
	};
	['error', 'warn'].forEach(function (level) {
		var orig = console[level];
		console[level] = function () { keep(level, arguments); return orig.apply(console, arguments); };
	});
	window.addEventListener('error', function (e) { keep('error', [e.message + ' (' + e.filename + ':' + e.lineno + ')']); });
	window.addEventListener('unhandledrejection', function (e) { keep('error', ['Unhandled promise rejection: ' + e.reason]); });
	// The GPU dropped the canvas (driver reset, GPU process crash, too little video memory): the picture
	// tears or goes black and Godot does not get it back. Not bubbling, so listened for while capturing.
	document.addEventListener('webglcontextlost', function () { keep('error', ['WebGL context lost: the browser took the graphics away']); }, true);
	document.addEventListener('webglcontextrestored', function () { keep('warn', ['WebGL context restored']); }, true);
	// Clean-close flag: "open" while the page runs, "closed" once the page is closed or reloaded normally.
	// A page that hung or crashed never gets to pagehide, so the next launch still finds "open".
	try {
		window.__lastInkPrevSession = localStorage.getItem('lastInk.session') || '';
		localStorage.setItem('lastInk.session', 'open');
		window.addEventListener('pagehide', function () {
			try { localStorage.setItem('lastInk.session', 'closed'); } catch (e) {}
		});
	} catch (e) { window.__lastInkPrevSession = ''; }
})();
"""

## Frame-time logging: a "perf" line this often (seconds), a "hitch" line for a frame this slow (ms),
## at most one hitch line per HITCH_GAP seconds.
const PERF_EVERY := 60.0
const HITCH_MS := 500.0
const HITCH_GAP := 10.0

## Where the logs live. Test runs (`godot -s ...`) use their own folder and never show the notice.
var dir := LOG_DIR
## What the last session left behind: {"crashed": bool, "errors": int, "warnings": int,
## "samples": [first error lines], "logs": [paths]}. Empty when there was no earlier session.
var previous := {}
## This session so far (the web build counts console lines; desktop errors are only in godot.log).
var errors := 0
var warnings := 0
var started := 0.0  # unix time
var scripted := false  # running under a -s script (the tests): no notice, no real logs

var _scene := ""
var _mission := ""
var _slot := ""
var _poll := 0.0
var _full := false
var _toast: Label
var _toast_t := 0.0
var _frame_us := 0  # when the last frame started (Time.get_ticks_usec)
var _perf_frames: Array = []  # frame times in ms since the last perf line
var _perf_t := 0.0
var _hitch_t := -HITCH_GAP


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	scripted = _is_scripted()
	if scripted:
		dir = "user://test_logs/"
	started = Time.get_unix_time_from_system()
	_add_screenshot_action()
	add_child(preload("res://scripts/perf_overlay.gd").new())  # F3: fps and memory on real hardware (issue #35)
	if OS.has_feature("web"):
		JavaScriptBridge.eval(WEB_HOOK, true)  # first: start_session reads the clean-close flag it keeps
	start_session()


## Clean exit (window closed, Quit): the session did not crash.
func _exit_tree() -> void:
	breadcrumb("exit")
	DirAccess.remove_absolute(dir.path_join("session.lock"))


## The same as Saves.game_version(), without needing that autoload (Diag starts first).
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func _is_scripted() -> bool:
	var args := OS.get_cmdline_args()
	return args.has("-s") or args.has("--script")


## Rotates the session logs, reads what the last session left behind and starts this one.
func start_session() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var crashed := web_froze() if OS.has_feature("web") else FileAccess.file_exists(dir.path_join("session.lock"))
	_rotate()
	previous = read_previous(crashed)
	_write_file(dir.path_join("session.lock"), Time.get_datetime_string_from_system(true) + "Z\n")
	_full = false
	_append(["Last Ink session log", ""] + header_lines() + [""])  # no-tr: developer log
	_print("session " + game_version() + " " + OS.get_name())


## Web: the last session's page never closed normally (it froze, crashed or lost its graphics and was
## reloaded or killed). WEB_HOOK read the flag before setting it for this session.
func web_froze() -> bool:
	if scripted or not OS.has_feature("web"):
		return false
	return str(JavaScriptBridge.eval("window.__lastInkPrevSession || ''", true)) == "open"


## Session logs move up one (session.log -> session.1.log ...); the oldest is dropped.
func _rotate() -> void:
	var oldest := dir.path_join("session.%d.log" % (KEEP - 1))
	if FileAccess.file_exists(oldest):
		DirAccess.remove_absolute(oldest)
	for i in range(KEEP - 2, 0, -1):
		var p := dir.path_join("session.%d.log" % i)
		if FileAccess.file_exists(p):
			DirAccess.rename_absolute(p, dir.path_join("session.%d.log" % (i + 1)))
	var cur := dir.path_join("session.log")
	if FileAccess.file_exists(cur):
		DirAccess.rename_absolute(cur, dir.path_join("session.1.log"))


## What the session before this one left: our own log and (desktop) the engine's log from then.
func read_previous(crashed: bool) -> Dictionary:
	var logs := []
	var p := dir.path_join("session.1.log")
	if FileAccess.file_exists(p):
		logs.append(p)
	var engine_log := previous_engine_log() if not scripted else ""
	if engine_log != "":
		logs.append(engine_log)
	if logs.is_empty() and not crashed:
		return {}
	var out := {"crashed": crashed, "errors": 0, "warnings": 0, "samples": [], "logs": logs}
	for path in logs:
		var counts := count_problems(FileAccess.get_file_as_string(path))
		out["errors"] += counts["errors"]
		out["warnings"] += counts["warnings"]
		for s in counts["samples"]:
			if out["samples"].size() < 5:
				out["samples"].append(s)
	return out


## Godot keeps the last sessions' logs as godot<date>.log next to this session's godot.log (desktop
## only; the folder is project setting debug/file_logging/log_path). The newest of those is the
## session before this one.
func previous_engine_log() -> String:
	var log_path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	var folder := log_path.get_base_dir()
	var stem := log_path.get_file().get_basename()
	if not DirAccess.dir_exists_absolute(folder):
		return ""
	var best := ""
	for f in DirAccess.get_files_at(folder):
		if f.begins_with(stem) and f.ends_with(".log") and f != log_path.get_file() and f > best:
			best = f
	return folder.path_join(best) if best != "" else ""


## Counts error and warning lines in a log, skipping engine noise and anything after a clean exit.
## Samples are the first few errors.
static func count_problems(text: String) -> Dictionary:
	var err := RegEx.create_from_string(ERROR_RE)
	var warn := RegEx.create_from_string(WARNING_RE)
	var cont := RegEx.create_from_string("^\\s*(ERROR|WARNING):\\s+(at:|GDScript backtrace)")
	var out := {"errors": 0, "warnings": 0, "samples": []}
	for line in text.split("\n"):
		if line.begins_with(EXIT_LINE):
			break
		if NOISE.any(func(n): return n in line):
			continue
		if cont.search(line):  # "ERROR:    at: ..." written by older builds from the browser console: part of the error above
			continue
		if err.search(line):
			out["errors"] += 1
			if out["samples"].size() < 5:
				out["samples"].append(line.strip_edges().left(200))
		elif warn.search(line):
			out["warnings"] += 1
	return out


## Whether the title screen should offer to send a report about the last session.
func should_offer_report() -> bool:
	if scripted or previous.is_empty() or muted():
		return false
	return previous.get("crashed", false) or int(previous.get("errors", 0)) > 0


## "Don't ask again" holds until the next game version, so a fixed build asks afresh.
func muted() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(dir.path_join("diag.cfg")) != OK:
		return false
	return str(cfg.get_value("notice", "muted_version", "")) == game_version()


func mute() -> void:
	var cfg := ConfigFile.new()
	cfg.load(dir.path_join("diag.cfg"))
	cfg.set_value("notice", "muted_version", game_version())
	cfg.save(dir.path_join("diag.cfg"))


# ---------------------------------------------------------------- context

## Who and where, for the log header and for reports. No names, accounts or addresses: only the
## game build, the machine's OS, CPU and graphics card, language and screen.
func system_info() -> Dictionary:
	var info := {
		"game_version": game_version(),
		"build": ("debug" if OS.is_debug_build() else "release") + (" +test_shortcuts" if OS.has_feature("test_shortcuts") else ""),  # no-tr: build tag
		"godot": Engine.get_version_info().get("string", ""),
		"os": OS.get_name(),
		"os_version": OS.get_version(),
		"locale": OS.get_locale(),
		"cpu": OS.get_processor_name(),
		"cpu_cores": OS.get_processor_count(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(),
		"graphics_api": RenderingServer.get_video_adapter_api_version(),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"screen": str(DisplayServer.screen_get_size()) if DisplayServer.get_name() != "headless" else "headless",
		"window": str(DisplayServer.window_get_size()) if DisplayServer.get_name() != "headless" else "headless",
	}
	if OS.has_feature("web"):
		info["browser"] = str(JavaScriptBridge.eval("navigator.userAgent", true))
		# Typing events the browser sent to the text fields (Controls.WEB_TYPING_HOOK), e.g.
		# "compositionstart 2, input:insertCompositionText 9, ...": shows how a phone keyboard types.
		var typing = JavaScriptBridge.eval("(function(){var t=window.__lastInkTyping;if(!t)return '';var o=[];for(var k in t.seen)o.push(k+' '+t.seen[k]);if(t.synced)o.push('synced '+t.synced);return o.join(', ');})()", true)
		if typing is String and typing != "":
			info["web_typing"] = typing
		# Browsers report the GPU as "WebKit WebGL"; Chrome tells the real one through this extension.
		var gpu = JavaScriptBridge.eval("(function(){try{var gl=document.createElement('canvas').getContext('webgl2');var e=gl&&gl.getExtension('WEBGL_debug_renderer_info');return e?gl.getParameter(e.UNMASKED_RENDERER_WEBGL):'';}catch(x){return '';}})()", true)
		if gpu is String and gpu != "":
			info["gpu_web"] = gpu
		info["pixel_ratio"] = str(JavaScriptBridge.eval("window.devicePixelRatio", true))
	return info


## Where the player is right now.
func game_context() -> Dictionary:
	var empire := get_node_or_null("/root/Empire")
	var scene := get_tree().current_scene
	return {
		"scene": scene.scene_file_path if scene else "",
		"mission": str(empire.active_mission.get("id", "")) if empire else "",
		"save_slot": Saves.current_slot if is_instance_valid(Saves) else "",
		"day": empire.day if empire else 0,
		"playtime_min": snappedf(empire.playtime / 60.0, 0.1) if empire else 0.0,
		"session_min": snappedf((Time.get_unix_time_from_system() - started) / 60.0, 0.1),
		"difficulty": Settings.DIFFICULTIES[Settings.difficulty] if Settings.difficulty < Settings.DIFFICULTIES.size() else "",
		"battle_speed": Settings.battle_speed_name(),
		"visual_fx": fx_summary(),
		"display": display_summary(),
	}


## The Visual effects sliders, e.g. "shadows 100, clouds 0, ...": what the GPU was asked to draw.
static func fx_summary() -> String:
	var parts := []
	for f in Settings.FX:
		parts.append("%s %d" % [f[0], int(Settings.fx.get(f[0], f[2]))])
	return ", ".join(parts)


## Vsync and the frame cap, e.g. "vsync on, cap 60" (the browser ignores both and runs at its own pace).
static func display_summary() -> String:
	var cap: int = DisplaySettings.FPS_CAPS[DisplaySettings.fps_i] if DisplaySettings.fps_i < DisplaySettings.FPS_CAPS.size() else 0
	return "vsync %s, cap %s" % ["on" if DisplaySettings.vsync else "off", str(cap) if cap > 0 else "none"]  # no-tr: developer log


func header_lines() -> Array:
	var lines := []
	var info := system_info()
	for k in info:
		lines.append("%s: %s" % [k, info[k]])
	lines.append("started: %sZ" % Time.get_datetime_string_from_unix_time(int(started), true))  # no-tr: developer log
	return lines


# ---------------------------------------------------------------- breadcrumbs

func _process(delta: float) -> void:
	_track_frame()
	_poll += delta
	if _poll >= 0.5:
		_poll = 0.0
		_check_context()
		if OS.has_feature("web"):
			_drain_web_console()
	if _toast and _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.get_parent().queue_free()
			_toast = null


func _check_context() -> void:
	var c := game_context()
	if c["scene"] != _scene:
		_scene = c["scene"]
		breadcrumb("scene " + (_scene if _scene != "" else "(none)"))
	if c["mission"] != _mission:
		_mission = c["mission"]
		breadcrumb("mission " + (_mission if _mission != "" else "(ended)"))
	if c["save_slot"] != _slot:
		_slot = c["save_slot"]
		breadcrumb("save slot " + _slot)


## Frame times: real time between frames (delta is clamped and scaled by battle speed).
func _track_frame() -> void:
	var now := Time.get_ticks_usec()
	if _frame_us == 0:
		_frame_us = now
		return
	var ms := (now - _frame_us) / 1000.0
	_frame_us = now
	if ms >= 10000.0:  # a hidden tab or minimised window draws nothing: not a frame, but say so
		if not scripted:
			breadcrumb("no frames for %d s (window hidden, or a long stall)" % int(ms / 1000.0))  # no-tr: developer log
		return
	_perf_frames.append(ms)
	_perf_t += ms / 1000.0
	var secs := Time.get_unix_time_from_system() - started
	if ms >= HITCH_MS and secs - _hitch_t >= HITCH_GAP and not scripted:
		_hitch_t = secs
		breadcrumb("hitch: one frame took %d ms" % int(ms))  # no-tr: developer log
	if _perf_t >= PERF_EVERY:
		if not scripted:
			breadcrumb(perf_line(_perf_frames))
		_perf_frames.clear()
		_perf_t = 0.0


## "perf 58 fps, worst frame 41 ms, 3 frames over 50 ms" from frame times in ms.
static func perf_line(times: Array) -> String:
	if times.is_empty():
		return "perf (no frames)"  # no-tr: developer log
	var total := 0.0
	var worst := 0.0
	var slow := 0
	for t in times:
		total += float(t)
		worst = maxf(worst, float(t))
		if float(t) > 50.0:
			slow += 1
	var fps := times.size() / maxf(total / 1000.0, 0.001)
	return "perf %d fps, worst frame %d ms, %d frames over 50 ms" % [roundi(fps), int(worst), slow]  # no-tr: developer log


## One line in the session log (and in godot.log on desktop), stamped with the time and the day.
func breadcrumb(what: String) -> void:
	var t := Time.get_time_string_from_system()
	var empire := get_node_or_null("/root/Empire")
	var line := "[%s +%ds day %d] %s" % [t, int(Time.get_unix_time_from_system() - started), empire.day if empire else 0, what]  # no-tr: developer log
	_append([line])
	_print(what)


func _print(what: String) -> void:
	if not scripted:
		print("[last-ink] " + what)


func _drain_web_console() -> void:
	var raw = JavaScriptBridge.eval("JSON.stringify(window.__lastInkLog ? window.__lastInkLog.splice(0) : [])", true)
	if typeof(raw) != TYPE_STRING or raw == "[]":
		return
	var rows = JSON.parse_string(raw)
	if typeof(rows) != TYPE_ARRAY:
		return
	var got := console_lines(rows)
	errors += int(got["errors"])
	warnings += int(got["warnings"])
	_append(got["lines"])


## Browser console rows ([level, text]) as log lines. Godot prints one engine error as several console
## lines (the message, then "at: ..." and backtrace lines); only the message counts as an error, the rest
## is kept indented under it.
static func console_lines(rows: Array) -> Dictionary:
	var out := {"lines": [], "errors": 0, "warnings": 0}
	var err_re := RegEx.create_from_string(ERROR_RE)
	var warn_re := RegEx.create_from_string(WARNING_RE)
	var more_re := RegEx.create_from_string("^(at:|GDScript backtrace|\\[\\d+\\])")
	for r in rows:
		if typeof(r) != TYPE_ARRAY or r.size() < 2:
			continue
		var text := str(r[1]).strip_edges()
		if text == "":
			continue
		if more_re.search(text):
			out["lines"].append("   " + text)
			continue
		var is_err: bool = r[0] == "error"
		var tagged := (err_re if is_err else warn_re).search(text) != null
		out["errors" if is_err else "warnings"] += 1
		out["lines"].append(text if tagged else ("ERROR: " if is_err else "WARNING: ") + text)  # no-tr: developer log
	return out


## Appends to session.log. Opened and closed each time: the web build saves user:// to the browser
## only when a file is closed.
func _append(lines: Array) -> void:
	if _full or lines.is_empty():
		return
	var path := dir.path_join("session.log")
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	if f.get_length() > MAX_LOG:
		f.store_line("(log full: nothing more is written this session)")  # no-tr: developer log
		_full = true
	else:
		for l in lines:
			f.store_line(str(l))
	f.close()


func _write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


## Every log worth sending: this session's and the last one's, ours and the engine's.
func log_files() -> Array:
	var out := []
	for name in ["session.log", "session.1.log"]:
		var p := dir.path_join(name)
		if FileAccess.file_exists(p):
			out.append(p)
	var log_path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	if not scripted and FileAccess.file_exists(log_path):
		out.append(log_path)
	var prev := previous_engine_log()
	if not scripted and prev != "":
		out.append(prev)
	return out


## Opens the log folder in the file manager. The web build has no folder to show, so it downloads
## the logs as one zip instead.
func open_log_folder() -> void:
	if OS.has_feature("web"):
		var zip := Feedback.zip_files(log_files())
		if not zip.is_empty():
			JavaScriptBridge.download_buffer(zip, "last-ink-logs.zip", "application/zip")
		return
	OS.shell_open(ProjectSettings.globalize_path(dir))


# ---------------------------------------------------------------- screenshots

func _add_screenshot_action() -> void:
	if InputMap.has_action("screenshot"):
		return
	InputMap.add_action("screenshot")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F12
	InputMap.action_add_event("screenshot", ev)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot") and not event.is_echo():
		take_screenshot()


## Saves what is on screen (after this frame is drawn). Returns the file path (or the download name
## on the web build).
func take_screenshot() -> String:
	if DisplayServer.get_name() == "headless":  # nothing is drawn, and frame_post_draw never comes
		return ""
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():  # no screen to grab (headless)
		toast(tr("Could not take a screenshot."))
		return ""
	var name := "last-ink_%s.png" % Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), name, "image/png")
		toast(tr("Screenshot downloaded: %s") % name)
		return name
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	var path := SHOT_DIR.path_join(name)
	if img.save_png(path) != OK:
		toast(tr("Could not save the screenshot."))
		return ""
	breadcrumb("screenshot " + name)
	toast(tr("Screenshot saved: %s") % ProjectSettings.globalize_path(path))
	return path


## A short note at the bottom of the screen, over everything.
func toast(text: String, secs := 3.0) -> void:
	if _toast:
		_toast.get_parent().queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_toast = Label.new()
	_toast.text = text
	_toast.add_theme_font_size_override("font_size", Access.fs(10))
	_toast.add_theme_color_override("font_color", Color("ece6da"))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("shadow_offset_x", 1)
	_toast.add_theme_constant_override("shadow_offset_y", 1)
	_toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -22
	_toast.offset_bottom = -8
	_toast.offset_left = 8
	_toast.offset_right = -8
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_toast)
	_toast_t = secs
