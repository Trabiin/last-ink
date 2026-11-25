extends "res://tests/test_case.gd"
## The Command Table clock without a pause button, and the mission results that lead with what changed
## (Ojon, 2026-11-25: "take away the pause button and just keep the 1x, 2x and 3x", "the payoff is a little weird").
##
## Clock: 1x, 2x and 4x always; the stop and 0.5x only with their assists; the keys and buttons skip what is not
## allowed; a save paused under the old clock loads at 1x; screens and briefings hold the clock at 1x; the Esc
## menu stops time but covers the map, unless pausing is allowed.
## Results: Payoff.entries makes "what changed" from a result (or takes the mission's own result["changed"]), adds
## one line from someone who went (never Ash), and the results page shows the changes before the accounts.

const COMMAND := "res://scenes/command.tscn"

var Empire: Node


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	autoload("Saves").pending = {}
	Empire.reset()
	Assists.reset()
	for t in Help.topics():
		Help.mark(str(t.get("id", "")))  # no first-time card pausing the table


func after_each() -> void:
	tree.paused = false
	Assists.reset()
	Empire.set_speed(Empire.SPEED_1X)


# ---------------------------------------------------------------- the clock

func test_speeds_without_assists() -> void:
	check_eq(Empire.speed, Empire.SPEED_1X, "a new game starts at 1x")
	check_eq(Empire.speed_choices(), [Empire.SPEED_1X, 3, 4], "only 1x, 2x and 4x to pick")
	check_eq(Empire.speed_choices().map(func(i): return Empire.speed_label(i)), ["1x", "2x", "4x"], "their labels")
	Empire.pick_speed(Empire.SPEED_STOP)
	check_eq(Empire.speed, Empire.SPEED_1X, "the stop can't be picked")
	Empire.pick_speed(Empire.SPEED_HALF)
	check_eq(Empire.speed, Empire.SPEED_1X, "nor 0.5x")
	Empire.step_speed(-1)
	check_eq(Empire.speed, Empire.SPEED_1X, "slower stays at 1x")
	Empire.step_speed(1)
	Empire.step_speed(1)
	Empire.step_speed(1)
	check_eq(Empire.speed, 4, "faster stops at 4x")
	for i in Empire.SPEED_KEYS.size():
		check(InputMap.has_action("clock_speed_%d" % i), "clock key %d exists" % i)
	Empire.pick_speed(Empire.SPEED_KEYS[3])
	check_eq(Empire.speed, 4, "the fourth clock key (stop) does nothing without the assist")
	var d0: float = Empire.day_t
	Empire.set_speed(Empire.SPEED_1X)
	Empire.tick(Empire.DAY_SECONDS * 0.1)
	check(absf(Empire.day_t - d0 - 0.1) < 0.001, "1x runs a tenth of a day in a tenth of DAY_SECONDS")


func test_assists_add_stop_and_half() -> void:
	Assists.allow_pause = true
	Assists.half_clock = true
	Assists.save()
	check(Assists.any_on(), "the Options row says some assists are on")
	check_eq(Empire.speed_choices(), [0, 1, 2, 3, 4], "stop, 0.5x, 1x, 2x, 4x")
	check_eq(Empire.speed_label(Empire.SPEED_HALF), "0.5x", "0.5x label")
	Empire.step_speed(-1)
	check_eq(Empire.speed, Empire.SPEED_HALF, "slower reaches 0.5x")
	var d0: float = Empire.day_t
	Empire.tick(Empire.DAY_SECONDS * 0.1)
	check(absf(Empire.day_t - d0 - 0.05) < 0.001, "0.5x runs at half pace")
	Empire.step_speed(-1)
	check_eq(Empire.speed, Empire.SPEED_STOP, "and then the stop")
	d0 = Empire.day_t
	Empire.tick(60.0)
	check_eq(Empire.day_t, d0, "stopped time does not move")
	# Switching the assist off again drops the clock back to 1x.
	Assists.allow_pause = false
	Assists.save()
	Empire.fit_speed()
	check_eq(Empire.speed, Empire.SPEED_1X, "a stop that is no longer allowed becomes 1x")
	# Half only: slower goes from 1x to 0.5x, the stop is skipped.
	Empire.step_speed(-1)
	Empire.step_speed(-1)
	check_eq(Empire.speed, Empire.SPEED_HALF, "with only the slower clock, 0.5x is the bottom")


func test_saves_old_and_new() -> void:
	var d: Dictionary = Empire.to_dict()
	check(d.has("clock_x") and not d.has("speed"), "the save keeps the speed itself, not an index")
	Empire.set_speed(4)
	d = Empire.to_dict()
	Empire.from_dict(d)
	check_eq(Empire.speed, 4, "4x round trips")
	# Saves from before: "speed" indexed [stop, 1x, 2x, 4x].
	d.erase("clock_x")
	d["speed"] = 3
	Empire.from_dict(d)
	check_eq(Empire.speed, 4, "an old save at 4x loads at 4x")
	d["speed"] = 1
	Empire.from_dict(d)
	check_eq(Empire.speed, Empire.SPEED_1X, "an old save at 1x loads at 1x")
	d["speed"] = 0
	Empire.from_dict(d)
	check_eq(Empire.speed, Empire.SPEED_1X, "an old save left paused loads at 1x")
	d.erase("speed")
	d["clock_x"] = 0.0
	Assists.allow_pause = true
	Assists.save()
	Empire.from_dict(d)
	check_eq(Empire.speed, Empire.SPEED_STOP, "a stopped save stays stopped while pausing is allowed")


func test_hold_at_1x() -> void:
	Empire.set_speed(4)
	Empire.hold_1x = true
	check_eq(Empire.speed_x(), 1.0, "held: 4x runs at 1x")
	Empire.hold_1x = false
	check_eq(Empire.speed_x(), 4.0, "let go: 4x again")
	Assists.half_clock = true
	Assists.save()
	Empire.set_speed(Empire.SPEED_HALF)
	Empire.hold_1x = true
	check_eq(Empire.speed_x(), 0.5, "held never speeds a slower clock up")
	Empire.hold_1x = false


func test_command_table_clock() -> void:
	var cmd := await goto(COMMAND, 20)
	if not check(cmd != null and cmd.scene_file_path == COMMAND, "command table running"):
		return
	Empire.set_speed(4)
	await frames(3)
	# A screen holds the clock at 1x.
	cmd.roster_view.open()
	await frames(2)
	check(cmd.panel_open(), "the roster counts as a screen")
	var d0: float = Empire.day_t + Empire.day
	await frames(10)
	var moved: float = Empire.day_t + Empire.day - d0
	check(moved > 0.0, "time still runs under a screen")
	check(moved <= 10.0 * Empire.MAX_TICK / Empire.DAY_SECONDS + 0.0001, "but no faster than 1x (%.5f days)" % moved)
	cmd.roster_view.close()
	await frames(3)
	# A briefing no longer stops time.
	var m := {}
	for o in Missions.list_for_province("meadow"):
		m = o
		break
	if check(not m.is_empty(), "a mission to brief"):
		cmd._open_brief(m)
		await frames(2)
		check(not tree.paused, "a briefing does not pause the game")
		var before: int = cmd.selected
		Input.action_press("ui_right")
		await frames(2)
		Input.action_release("ui_right")
		check_eq(cmd.selected, before, "keys under a briefing do not move the map's selection")
		cmd._on_brief("back")
		await frames(2)
	# The Esc menu stops time and covers the map.
	cmd._open_menu()
	await frames(2)
	check(tree.paused, "the menu stops time")
	check(cmd.menu_cover.visible, "and covers the map")
	cmd._close_menu()
	await frames(2)
	check(not cmd.menu_cover.visible, "the cloth comes off with the menu")
	# The speed buttons: three of them, no stop.
	check_eq(Empire.speed_choices().size(), 3, "three speed buttons")
	# With the assist, the stop is back and the menu leaves the map in view.
	Assists.allow_pause = true
	Assists.save()
	cmd._open_menu()
	await frames(2)
	check(not cmd.menu_cover.visible, "pausing allowed: the menu leaves the map in view")
	cmd._close_menu()
	await frames(2)
	Empire.pick_speed(Empire.SPEED_STOP)
	await frames(3)
	check(cmd.paused_canvas.visible, "TIME PAUSED shows when the assist's stop is picked")


# ---------------------------------------------------------------- results

func _settled(id: String, outcome := "success") -> Dictionary:
	var m := Missions.find(id)
	Empire.active_mission = m
	return Missions.settle(m, outcome, {"gilt": 3}, {"kills": 9, "time": 75.0, "objective": "Disperse Nibblers"})


func test_payoff_from_a_result() -> void:
	Empire.recruits["bran"] = {"role": "party", "target": "", "injured": 0}
	var r := _settled("meadow_patrol")
	var e := Payoff.entries(r, ["ash", "bran"])
	check(not e.is_empty() and e[0]["kind"] == "place", "a patrol that pushes Fray back leads with the place (%s)" % str(e))
	check(e[0].get("province_id", "") == "meadow", "the meadow")
	check(e.back()["kind"] == "line" and e.back()["who"] == "bran", "Bran says the line, not Ash (%s)" % str(e.back()))
	check(str(e.back()["text"]) != "", "the line has words")
	check(Payoff.entries(r, ["ash"]).all(func(x): return x["kind"] != "line"), "Ash alone says nothing")
	var lost := Payoff.entries(_settled("meadow_patrol", "wiped"), ["ash"])
	check(lost[0]["kind"] == "lost", "driven out leads with what was lost")
	# The same mission on the same day picks the same line.
	check_eq(Payoff.entries(r, ["ash", "bran", "gristle"]).back(), Payoff.entries(r, ["ash", "bran", "gristle"]).back(), "the line is stable")


func test_payoff_from_the_mission() -> void:
	var r := _settled("meadow_patrol")
	r["changed"] = [
		{"kind": "people", "count": 11, "from": "Millbrook", "text": "Eleven people from Millbrook walk into Hollowmark."},
		{"kind": "line", "who": "odile", "text": "Entered, all eleven."},
		{"kind": "nonsense", "text": "dropped"},
	]
	var e := Payoff.entries(r, ["ash", "bran"])
	check_eq(e.size(), 2, "the mission's own changes, the unknown kind dropped")
	check_eq(e[0]["kind"], "people", "the people first")
	check_eq(e[1]["who"], "odile", "and the mission's own line, not a fallback")


func test_payoff_lines_data() -> void:
	var heroes: Dictionary = Payoff.data().get("heroes", {})
	check(not heroes.is_empty(), "data/payoffs.json loads")
	check(not heroes.has("ash"), "Ash never gets a line")
	for id in heroes:
		check(not Empire.recruit(str(id)).is_empty(), "%s is a recruit" % id)
		for k in ["people", "place", "person", "lost", "plain"]:
			check((heroes[id] as Dictionary).has(k), "%s has a %s line" % [id, k])


func test_results_page_order() -> void:
	var main := await goto("res://scenes/title.tscn", 5)  # any scene to hang the view on
	var view = preload("res://scripts/results_view.gd").new()
	main.add_child(view)
	Empire.recruits["bran"] = {"role": "party", "target": "", "injured": 0}
	var r := _settled("meadow_patrol")
	r["changed"] = [{"kind": "people", "count": 5, "from": "Millbrook", "text": "Five people from Millbrook walk into Hollowmark."}]
	var reduce: bool = Access.reduce_motion
	Access.reduce_motion = false
	view.open(r, ["ash", "bran"])
	await frames(2)
	var texts: Array = view.drawn_text.map(func(x): return str(x[2]))
	check(not texts.has(tr("The accounts")), "the accounts wait for the changes")
	check(not view.all_shown(), "the beats are still coming")
	# A press shows everything at once; the next goes home.
	var got := [false]
	view.confirmed.connect(func(): got[0] = true)
	await frames(20)
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	view._input(ev)
	await frames(2)
	texts = view.drawn_text.map(func(x): return str(x[2]))
	check(view.all_shown(), "the first press shows it all")
	check(texts.has(tr("The accounts")), "accounts on the page")
	check(texts.has("Five people from Millbrook walk into Hollowmark."), "the change on the page")
	check(texts.find("Five people from Millbrook walk into Hollowmark.") < texts.find(tr("The accounts")), "the change is written before the accounts")
	check(not got[0], "the first press does not leave")
	view._input(ev)
	check(got[0], "the second press returns home")
	for t in view.drawn_text:
		var rect: Rect2 = t[0]
		var box: Rect2 = t[1]
		check(box.grow(1.0).encloses(rect) or rect.size.x <= 0.0, "'%s' stays on its page" % str(t[2]))
	Access.reduce_motion = reduce
	view.queue_free()
