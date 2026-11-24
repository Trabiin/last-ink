extends SceneTree
## Automated tests (issue #110). Runs every tests/test_*.gd and quits with exit code 1 on any failure.
##
##   godot --headless --audio-driver Dummy --path . -s tests/run.gd              every test file
##   godot --headless --audio-driver Dummy --path . -s tests/run.gd -- saves     files whose name contains "saves"
##
## tools/run_tests.sh wraps this and also fails on any script error or warning in the log; CI runs
## that script (.github/workflows/tests.yml). See docs/TESTING.md.
##
## Test files extend tests/test_case.gd and hold `func test_<name>()` methods, which may await.
## Class scripts need the autoloads, which exist only after the first frame, so the test files are
## loaded from _process, not here.

const DIR := "res://tests/"
const SCRATCH := "user://test_run/"

var _frame := 0
var _filter := ""
var _failed := 0
var _passed := 0
var _failures: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_filter = args[0]


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_run()
	return false


func _run() -> void:
	var saves = root.get_node_or_null("Saves")
	if saves == null:  # an autoload failed to compile: the errors are above
		print("Autoloads did not start; see the script errors above.")
		quit(1)
		return
	saves.dir = SCRATCH  # never touch the player's real saves
	# Never send to the real report inbox (data/feedback.json endpoint): tests that send use a local fake.
	var feedback: GDScript = load("res://scripts/feedback.gd")
	clear_scratch()
	saves.notices = []
	var files := []
	for f in DirAccess.get_files_at(DIR):
		f = f.trim_suffix(".remap")  # an exported build lists scripts as test_x.gd.remap (desktop smoke test, #145)
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd" and (_filter == "" or _filter in f):
			files.append(f)
	files.sort()
	print("Running %d test file(s)%s" % [files.size(), (" matching '%s'" % _filter) if _filter != "" else ""])
	for f in files:
		var script: GDScript = load(DIR + f)
		if script == null or not script.can_instantiate():
			_fail(f, "(load)", "script failed to load")
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			t.tree = self
			t.runner = self
			feedback.override = {"endpoint": ""}
			await t.before_each()
			await t.call(name)
			await t.after_each()
			if t.failures.is_empty():
				_passed += 1
				print("  ok    %s :: %s" % [f.get_basename(), name])
			else:
				for msg in t.failures:
					_fail(f, name, msg)
	clear_scratch()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAILED " + line)
	# Leave the last scene before quitting so nothing it holds is reported as leaked.
	if current_scene:
		current_scene.free()
	await process_frame
	quit(1 if _failed > 0 else 0)


func _fail(file: String, test: String, msg: String) -> void:
	_failed += 1
	var line := "%s :: %s: %s" % [file.get_basename(), test, msg]
	_failures.append(line)
	print("  FAIL  " + line)


## Empties the scratch save folder.
func clear_scratch() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH):
		DirAccess.make_dir_recursive_absolute(SCRATCH)
		return
	for f in DirAccess.get_files_at(SCRATCH):
		DirAccess.remove_absolute(SCRATCH.path_join(f))
