extends "res://tests/test_case.gd"
## Screenshots of the climax betrayal (issue #186): the grey heart in town, a redacted line, the Vacancy on stage,
## each betrayer's fight in their home written as words, and Ash's gesture. Does nothing in the normal test run.
## Under a display (not --headless):
##   BETRAYAL_SHOTS=/tmp/betrayal xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- betrayal_shots

const HUB := "res://scenes/hub.tscn"
const MAIN := "res://scenes/main.tscn"

var shots := ""
var Empire: Node


func before_each() -> void:
	shots = OS.get_environment("BETRAYAL_SHOTS")
	if shots != "" and DisplayServer.get_name() == "headless":
		shots = ""
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	Empire = autoload("Empire")
	autoload("Saves").pending = {}
	Empire.reset()
	for t in Help.topics():
		Help.mark(t["id"])


func after_each() -> void:
	tree.paused = false


func _shot(name: String) -> void:
	await frames(4)
	var img := tree.root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [shots, name])


func _campaign(id: String) -> void:
	Story.begin()
	for m in ["meadow_prologue", "ch1_breakout"]:
		Empire.missions_cleared.append(m)
	for t in ["meadow_intro", "ch1_arrest", "ch1_takeover", "act1_rumours", "act1_writ"]:
		Dialogue.mark_seen("talk:" + t)
	for other in Betrayal.candidates():
		Empire.recruits.erase(other)
	Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Empire.bonds[id] = {"points": 0, "rank": 1, "talk_day": 0, "personal_done": false}
	var p: Dictionary = Empire.territory().find(Betrayal.home_of(id))
	p["owner"] = "erased"


func test_town() -> void:
	if shots == "":
		return
	_campaign("ottoline")
	Betrayal.begin_foreshadowing()
	var hub := await goto(HUB)
	await frames(10)
	if hub.dialogue_box.visible:
		await _shot("01_verity_letter")
		hub.dialogue_box._close()
		await frames(6)
	if hub.npcs.has("ottoline"):
		hub.leader.global_position = (hub.npcs["ottoline"] as Node2D).global_position + Vector2(-30, 20)
	await _shot("02_grey_heart")
	hub.dialogue_box.play_lines([["ottoline", Betrayal.redact("Thirty year our Tobble's kept a list of who drinks here. I keep the list of who doesn't.")]])
	hub.dialogue_box._shown = 9999.0
	await _shot("03_redacted_line")
	hub.dialogue_box._close()
	Betrayal.lock()
	hub.dialogue_box.play("betrayal_ottoline")
	hub.dialogue_box._at = 2
	hub.dialogue_box._place_speaker()
	hub.dialogue_box._shown = 9999.0
	await _shot("04_vacancy_on_stage")
	hub.dialogue_box._close()


func test_fights() -> void:
	if shots == "":
		return
	var moves := {"ottoline": "chucking_out", "ninefingers": "skewer", "odile": "final_demand"}
	for id in moves:
		Empire.reset()
		autoload("Saves").pending = {}
		_campaign(id)
		Betrayal.lock()
		Progress.award(PartyPicker.mission_party(), Progress.xp_to_reach(12))
		Missions.launch(Missions.find("betrayal_fight_" + id))
		var main := await wait_scene(MAIN)
		await frames(20)
		var boss: Turncoat = null
		for e in main.entities.get_children():
			if e is Turncoat:
				boss = e
		main.leader.global_position = boss.global_position + Vector2(0, 90)
		await frames(6)
		if main.dialogue_box.visible:
			main.dialogue_box._shown = 9999.0
			await _shot("10_%s_intro" % id)
			main.dialogue_box._close()
		await frames(30)
		if moves[id] == "skewer":
			boss.phase = 2  # Twin Prongs
		boss.target = main.leader
		boss._wind(moves[id])
		boss.act_t = boss.act_total * 0.35
		await frames(2)
		await _shot("11_%s_tell" % id)
		boss.take_hit(99999, boss.global_position + Vector2(10, 0))
		for i in 60:
			if main.dialogue_box.visible:
				break
			await frames(10)
		var box = main.dialogue_box
		box._skip()
		await _shot("12_%s_gesture" % id)
		box._pick(0)
		box._shown = 9999.0
		await _shot("13_%s_taken_back" % id)
		box._close()
		tree.paused = false
