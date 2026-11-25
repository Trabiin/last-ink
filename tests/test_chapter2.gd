extends "res://tests/test_case.gd"
## Chapter 2: The Copying Monks (issue #28). The End of Act 1 opens the Abbey region, the chapter's beats play in
## order in the real town, each story mission launches on its own map and runs its steps, the boss fight
## plays its copies and phase change, and the empire side (new factions, Eraser trouble, story effects,
## research, recruits) does what the chapter promises.

const MAIN := "res://scenes/main.tscn"
const HUB := "res://scenes/hub.tscn"
const CH2 := ["ch2_candleford", "ch2_hall", "ch2_crypt", "ch2_abbot"]

var Empire: Node
var Saves: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	runner.clear_scratch()
	Saves.pending = {}
	Empire.reset()
	for t in Help.topics():
		Help.mark(t["id"])


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0


## A story campaign that has just beaten the Auditor.
func _act1_done() -> void:
	Empire.reset()
	Story.begin()
	for pid in ["meadow", "oldmill", "lampwick", "saltreed", "gutterwoods"]:  # six provinces held: Chapter 2's start
		Empire.territory().find(pid)["owner"] = "you"
	for id in ["gristle", "ninefingers"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for m in ["meadow_prologue", "ch1_breakout", "act1_concord", "auditor_duel"]:
		Empire.missions_cleared.append(m)
	for t in ["meadow_intro", "ch1_arrest", "ch1_takeover", "act1_rumours", "act1_writ", "act1_concord_after"]:
		Dialogue.mark_seen("talk:" + t)


func _clear(ids: Array) -> void:
	for id in ids:
		if not id in Empire.missions_cleared:
			Empire.missions_cleared.append(id)


func _seen(ids: Array) -> void:
	for t in ids:
		Dialogue.mark_seen("talk:" + t)


func _inner(main: Node) -> MissionObjectives:
	return main.objective.inner if main.objective._inner_ready else null


# ---------------------------------------------------------------- data

func test_chapter_data_hangs_together() -> void:
	for id in CH2:
		var m := Missions.find(id)
		if not check(not m.is_empty(), "%s exists" % id):
			continue
		check(m.get("story", false), "%s is a story mission" % id)
		check(FileAccess.file_exists(str(m["map"])), "%s map %s exists" % [id, m["map"]])
		check_eq(Empire.territory().find(m["province"]).get("region", ""), "abbey", "%s is in the Abbey region" % id)
	for kind in ["penitent", "copyist", "reader", "whitewasher"]:
		check(EnemyKinds.data()["kinds"].has(kind), "enemy kind %s" % kind)
	check(BossFight.BOSSES.has("abbot"), "the Abbot is a boss")
	check_eq(Empire.faction("abbey").get("province", ""), "abbey", "the Abbey's home")
	check_eq(Empire.faction("erasers").get("province", ""), "ossuary", "the Erasers' home")
	var chapters: Array = Journal.data().get("chapters", []).map(func(c): return c["id"])
	check("ch2" in chapters, "the journal has a Chapter 2")
	for g in Story.data()["goals"]:
		if g.get("chapter", "") == "ch2":
			check(g.has("show"), "Chapter 2 goal '%s' stays hidden until its beat" % g["text"])


# ---------------------------------------------------------------- story flow in town

func test_act1_end_opens_the_abbey_and_chapter2_follows() -> void:
	_act1_done()
	check(not "abbey" in Empire.regions_open, "the Abbey is under the fog before the end of Act 1")
	var hub := await goto(HUB, 20)
	if hub == null:
		return
	if not check(hub.dialogue_box.visible and hub.story_beat.get("talk", "") == "act1_end", "the End of Act 1 plays"):
		return
	hub.dialogue_box._close()
	await frames(3)
	check("abbey" in Empire.regions_open, "act1_end lifts the fog over the Abbey")
	check(hub.chapter_card.visible, "the Act 1 card shows")
	hub.chapter_card.hide()
	hub.chapter_card.closed.emit()
	await frames(4)
	check_eq(hub.story_beat.get("talk", ""), "ch2_bells", "Chapter 2's first beat plays next")
	hub.dialogue_box._close()
	await frames(3)
	var offered := Missions.list_for_province("candlemere")
	check(not offered.is_empty() and offered[0]["id"] == "ch2_candleford", "Candleford offers The Wax Barges")


func test_beats_play_in_order() -> void:
	_act1_done()
	Empire.open_region("abbey", true)
	_seen(["act1_end", "ch2_bells"])
	check_eq(Story.next_beat().get("talk", ""), "", "nothing until the barges are saved")
	_clear(["ch2_candleford"])
	Empire.territory().find("candlemere")["owner"] = "you"  # what winning the barges does (on_success grant)
	check_eq(Story.next_beat().get("talk", ""), "ch2_candleford_after", "the Prioress's letter")
	_seen(["ch2_candleford_after"])
	check_eq(Story.next_beat().get("talk", ""), "", "the invitation waits for a governor")
	var hall := Missions.list_for_province("abbey").filter(func(m): return m["id"] == "ch2_hall")
	Empire.res["renown"] = 25
	if check(hall.size() == 1, "the Copying Hall is on the map"):
		check(str(hall[0].get("blocker", "")).contains("26 Renown"), "locked until 26 Renown (issue #138: %s)" % hall[0].get("blocker", ""))
	Empire.res["renown"] = 26
	hall = Missions.list_for_province("abbey").filter(func(m): return m["id"] == "ch2_hall")
	if check(hall.size() == 1, "the Copying Hall is still on the map"):
		check(str(hall[0].get("blocker", "")).contains("governor"), "but locked until Candleford has a governor (%s)" % hall[0].get("blocker", ""))
	Empire.assign("gristle", "governor", "candlemere")
	check_eq(Empire.governor_of("candlemere"), "gristle", "Gristle governs Candleford")
	check_eq(Story.next_beat().get("talk", ""), "ch2_hall_ready", "the invitation")
	hall = Missions.list_for_province("abbey").filter(func(m): return m["id"] == "ch2_hall")
	check(hall.size() == 1 and str(hall[0].get("blocker", "")) == "", "the Copying Hall can be launched")
	_seen(["ch2_hall_ready"])
	_clear(["ch2_hall"])
	check_eq(Story.next_beat().get("talk", ""), "ch2_hall_after", "after the hall: the Crypts")
	_seen(["ch2_hall_after"])
	check_eq(Story.next_beat().get("talk", ""), "", "Hild's scene needs Hild")
	Empire.recruits["abeyance"] = {"role": "idle", "target": "", "injured": 0}
	check_eq(Story.next_beat().get("talk", ""), "ch2_hild", "Hild remembers the Abbey")
	_seen(["ch2_hild"])
	var crypt := Missions.list_for_province("ossuary").filter(func(m): return m["id"] == "ch2_crypt")
	if check(crypt.size() == 1, "the Crypts are on the map"):
		check(str(crypt[0].get("blocker", "")).contains("31 Renown"), "locked until 31 Renown (%s)" % crypt[0].get("blocker", ""))
	_clear(["ch2_crypt"])
	check_eq(Story.next_beat().get("talk", ""), "ch2_verity_after", "after the crypts")
	_seen(["ch2_verity_after"])
	Empire.res["renown"] = 36
	var abbot := Missions.list_for_province("abbey").filter(func(m): return m["id"] == "ch2_abbot")
	if check(abbot.size() == 1, "the Abbot is on the map"):
		check(str(abbot[0].get("blocker", "")).to_lower().contains("forge"), "locked until the Forge reaches level 2 (%s)" % abbot[0].get("blocker", ""))
	Empire.buildings["forge"] = 2
	abbot = Missions.list_for_province("abbey").filter(func(m): return m["id"] == "ch2_abbot")
	if check(abbot.size() == 1, "the Abbot is still on the map"):
		check(str(abbot[0].get("blocker", "")).contains("Neutral"), "locked until the Abbey is Neutral (%s)" % abbot[0].get("blocker", ""))
	Empire.change_standing("abbey", 20, "test", true)
	abbot = Missions.list_for_province("abbey").filter(func(m): return m["id"] == "ch2_abbot")
	check(abbot.size() == 1 and str(abbot[0].get("blocker", "")) == "", "Neutral opens the hall")
	_clear(["ch2_abbot"])
	check_eq(Story.next_beat().get("talk", ""), "ch2_end", "the end of Chapter 2")
	_seen(["ch2_end"])
	var showing := Story.goals().map(func(g): return g["text"])
	check("Hold Scarth Pass" in showing, "Chapter 2's open goals show after its end")


# ---------------------------------------------------------------- story effects

func test_story_effects_apply_once() -> void:
	_act1_done()
	Empire.open_region("abbey", true)
	var m := Missions.find("ch2_candleford")
	var lines := Missions.story_effects(m, true)
	check(not lines.is_empty(), "the briefing/results can list what the win does")
	check_eq(Empire.territory().find("candlemere")["owner"], "free", "a dry run changes nothing")
	Missions.story_effects(m)
	check_eq(Empire.territory().find("candlemere")["owner"], "you", "winning the barges hands you Candleford")
	Missions.story_effects(Missions.find("ch2_crypt"))
	check(Empire.recruits.has("osyth"), "Sister Osyth joins after the crypts")
	var before: int = Empire.standing_of("abbey")
	Missions.story_effects(Missions.find("ch2_hall"))
	check_eq(Empire.standing_of("abbey"), before + 10, "the Copying Hall earns the Abbey's thanks")


# ---------------------------------------------------------------- missions in the real scene

func _launch(id: String) -> Node:
	var m := Missions.find(id)
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	check_eq(main.mission.get("id", ""), id, "%s running" % id)
	await frames(5)
	return main


## Walks a script mission's steps the quick way: closes talks, moves the leader onto goals, clears waves and
## finishes holds and works, checking each step starts cleanly.
func _walk_steps(main: Node, inner: MissionScript, id: String) -> void:
	var guard := 0
	while inner.step < inner.steps.size() and guard < 60 and not main.objective.failed():
		guard += 1
		var st: Dictionary = inner.st
		match str(st.get("do", "")):
			"talk":
				if main.dialogue_box.visible:
					main.dialogue_box._close()
			"goto":
				main.leader.global_position = inner.spot(st.get("at", "start"))
			"clear":
				for e in inner.wave.duplicate():
					if is_instance_valid(e) and not e.dead:
						e.take_hit(99999, e.global_position + Vector2(8, 0))
			"hold":
				inner.step_t = float(st.get("seconds", 30.0))
			"use":
				for c in inner.works:
					c.progress = 1.0
					c.done = true
			"exit":
				main.leader.global_position = inner.exit_pos
		await frames(4)
	check(not main.objective.failed(), "%s did not fail on the way (%s)" % [id, main.objective.inner.fail_why if inner else ""])
	check(inner.step >= inner.steps.size(), "%s ran every step (stuck at %d: %s)" % [id, inner.step, inner.st])


func test_story_missions_run_their_steps() -> void:
	_act1_done()
	Empire.open_region("abbey", true)
	_seen(["act1_end", "ch2_bells", "ch2_candleford_after", "ch2_hall_ready", "ch2_hall_after"])
	for id in ["ch2_candleford", "ch2_hall", "ch2_crypt"]:
		var main := await _launch(id)
		if main == null:
			continue
		var inner := _inner(main) as MissionScript
		if not check(inner != null, "%s runs as a script" % id):
			continue
		await _walk_steps(main, inner, id)
		main._show_results("success")
		await frames(3)
		main._on_results_confirmed()
		await wait_scene(HUB)
		check(Missions.cleared(id), "%s cleared" % id)
	check_eq(Empire.territory().find("candlemere")["owner"], "you", "Candleford is yours")
	check(Empire.recruits.has("osyth"), "Osyth came home")


func test_abbot_fight() -> void:
	_act1_done()
	Empire.open_region("abbey", true)
	_clear(["ch2_candleford", "ch2_hall", "ch2_crypt"])
	Empire.change_standing("abbey", 20, "test", true)
	Progress.award(PartyPicker.mission_party(), Progress.xp_to_reach(9))
	var main := await _launch("ch2_abbot")
	if main == null:
		return
	if main.dialogue_box.visible:
		main.dialogue_box._close()
	await frames(60)
	var abbot: Abbot = null
	var copies := 0
	for e in main.entities.get_children():
		if e is Abbot:
			if e.is_copy:
				copies += 1
			else:
				abbot = e
	if not check(abbot != null, "the Abbot is in the garth"):
		return
	main.leader.global_position = abbot.global_position + Vector2(0, 90)  # walk up to him: he wakes
	await frames(6)
	check(main.dialogue_box.visible, "he speaks when he wakes (abbot_intro)")
	main.dialogue_box._close()
	await frames(120)
	copies = 0
	for e in main.entities.get_children():
		if e is Abbot and e.is_copy and not e.dead:
			copies += 1
	check(copies >= 1, "he has copies (%d)" % copies)
	abbot.hp = int(abbot.max_hp * 0.45)
	abbot.take_hit(1, abbot.global_position + Vector2(10, 0))
	await frames(6)
	check_eq(abbot.phase, 2, "below half he becomes The Second Copy")
	check(main.dialogue_box.visible, "the phase change has its scene (abbot_phase2)")
	main.dialogue_box._close()
	await frames(150)
	for i in 40:  # untouchable through the phase change and re-copies (hurried along here), then the last hit
		if abbot.dead:
			break
		if abbot.act == Abbot.Act.TRANSITION or abbot.act == Abbot.Act.RECOPY:
			check(not abbot.take_hit(10, abbot.global_position + Vector2(10, 0)), "untouchable while re-copying")
			abbot.act_t = 0.0
		else:
			abbot.take_hit(99999, abbot.global_position + Vector2(10, 0))
		await frames(10)
	check(abbot.dead, "the real Abbot goes down")
	for i in 60:  # the outro waits a couple of seconds of game time
		if main.dialogue_box.visible:
			break
		await frames(10)
	check(main.dialogue_box.visible, "his last words (abbot_outro)")
	main.dialogue_box._close()
	for i in 100:
		if main.objective.done() or main.results_view.visible:
			break
		await frames(10)
	check(main.objective.done() or main.results_view.visible, "beating the real Abbot wins the fight")
	if not main.results_view.visible:
		main._show_results("success")
		await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)
	check(Missions.cleared("ch2_abbot"), "the Abbot is cleared")
	check(Empire.at_least("abbey", "friendly"), "the Abbey is grateful (Friendly)")
