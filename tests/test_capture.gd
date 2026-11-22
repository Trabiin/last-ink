extends "res://tests/test_case.gd"
## Trailer capture tooling (#152): every shot in tools/capture/shots/ is valid against the game's
## data, so a shot written for the trailer still records after heroes, missions or enemies change.
## The recording itself (tools/capture.sh) needs a display and ffmpeg and is not run here.

const SHOTS := "res://tools/capture/shots/"
const CAPTURE := "res://tools/capture.gd"


func test_every_shot_is_valid() -> void:
	if not DirAccess.dir_exists_absolute(SHOTS):
		return  # a test pack without tools/ (desktop smoke test)
	var capture = load(CAPTURE)
	check(capture != null, "tools/capture.gd compiles")
	var files := Array(DirAccess.get_files_at(SHOTS)).filter(func(f): return f.ends_with(".json"))
	check(files.size() >= 4, "sample shots are in tools/capture/shots/")
	var scenes := {}
	for f in files:
		var d: Dictionary = capture.load_shot(SHOTS + f)
		check(not d.is_empty(), "%s parses" % f)
		check(str(d.get("_about", "")) != "", "%s says what it is for (_about)" % f)
		var bad: Array = capture.problems(d)
		check(bad.is_empty(), "%s: %s" % [f, ", ".join(bad)])
		scenes[str(d.get("scene", "mission"))] = true
	for s in ["mission", "town", "command"]:
		check(scenes.has(s), "a sample shot in the %s scene" % s)


func test_problems_are_caught() -> void:
	if not DirAccess.dir_exists_absolute(SHOTS):
		return
	var capture = load(CAPTURE)
	var bad: Array = capture.problems({
		"scene": "mission", "mission": "no_such_mission", "party": ["ash", "nobody"],
		"camera": [{"t": 2}, {"t": 1, "ease": "bounce", "follow": "bran"}],
		"beats": [{"t": 1, "spawn": "dragon"}, {"t": 2, "tech": "bran"}, {"t": 3, "explode": true}],
	})
	for want in ["no_such_mission", "nobody", "time order", "bounce", "follows 'bran'", "dragon", "'tech' for 'bran'", "explode"]:
		check(bad.any(func(line): return want in line), "a broken shot is reported: %s" % want)
	check(capture.problems({"scene": "town", "beats": [{"t": 1, "spawn": "nibbler"}]}).size() == 1, "fights only in missions")
