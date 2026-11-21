extends "res://tests/test_case.gd"
## Screenshots of every main screen at a chosen text size (issue #34), to check that nothing clips or
## overflows at Large and Largest. Does nothing in the normal test run. Under a display (not --headless):
##   ACCESS_SHOTS=/tmp/a11y TEXT_SIZE=2 xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- access_shots
## TEXT_SIZE is 0 (Normal), 1 (Large) or 2 (Largest). The danger markers, the first-start page, the
## Accessibility page, a conversation, the dialogue log and a bond scene are included.

const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"
const TITLE := "res://scenes/title.tscn"

var shots := ""


func before_each() -> void:
	shots = OS.get_environment("ACCESS_SHOTS")
	if shots != "" and DisplayServer.get_name() == "headless":
		shots = ""
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)


func after_each() -> void:
	if shots != "":
		Access.text_size = 0
		Access.danger_patterns = true


func _shot(name: String) -> void:
	await frames(4)
	var img := tree.root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [shots, name])


func test_screens() -> void:
	if shots == "":
		return
	Access.load_settings()
	Access.text_size = clampi(int(OS.get_environment("TEXT_SIZE")), 0, Access.TEXT_SIZES.size() - 1)
	var Empire := autoload("Empire")
	autoload("Saves").pending = {}
	Empire.reset()
	for id in ["gristle", "ninefingers", "abeyance"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	for k in Dialogue.data().get("talks", {}):
		Dialogue.mark_seen("talk:" + str(k))
	Settings.tips = false
	var title := await goto(TITLE, 20)
	await _shot("00_title")
	var first := OptionsView.popup(title, "first")
	await _shot("01_first_start")
	first.queue_free()
	var hub := await goto(HUB, 20)
	await _shot("02_hub")
	hub.open_menu()
	await _shot("03_hub_menu")
	var cmd := await goto(COMMAND, 20)
	await _shot("04_command")
	var views := {"roster": cmd.roster_view, "buildings": cmd.buildings_view, "expeditions": cmd.expedition_view,
		"research": cmd.research_view, "diplomacy": cmd.diplomacy_view, "bonds": cmd.bonds_view,
		"newcomers": cmd.newcomers_view}
	var i := 10
	for name in views:
		views[name].open()
		await _shot("%02d_%s" % [i, name])
		views[name].close()
		i += 1
	cmd.gear_view.open("town")
	await _shot("20_gear")
	cmd.gear_view.close()
	cmd.governor_view.open("hollowmark")
	await _shot("21_governor")
	cmd.governor_view.close()
	if cmd.armory_view:
		cmd.armory_view.open()
		await _shot("22_armory")
		cmd.armory_view.close()
	if cmd.journal_view:
		cmd.journal_view.open()
		await _shot("23_journal")
		cmd.journal_view.close()
	cmd._open_brief(Missions.find("meadow_patrol"))
	await _shot("24_briefing")
	cmd._on_brief("go")
	await _shot("25_party_picker")
	cmd.party_picker.close()
	var opts := OptionsView.popup(cmd)
	await _shot("26_options")
	opts.page = "access"
	opts._rebuild()
	await _shot("27_options_access")
	opts.queue_free()
	var help := HelpView.popup(cmd)
	await _shot("28_help")
	help.queue_free()
	cmd.bonds_view.open()
	cmd.bonds_view.scene_view.play("bran", 1, true)
	await frames(40)
	cmd.bonds_view.scene_view._shown = 99999.0
	await _shot("29_bond_scene")
	cmd.bonds_view.scene_view._close()
	cmd.bonds_view.close()
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	await frames(30)
	await _shot("30_mission")
	main.open_quick_menu()
	await _shot("31_quick_menu")
	main.quick_menu.close()
	await frames(5)
	main.play_talk("meadow_intro")
	await frames(20)
	main.dialogue_box._shown = 99999.0
	await _shot("32_dialogue")
	main.dialogue_box._advance()
	main.dialogue_box._advance()
	await frames(10)
	var log := DialogueLog.popup(main)
	await _shot("33_dialogue_log")
	log.close()
	main.dialogue_box._close()
	await frames(5)
	# Danger markers: an Enforcer winding up its slam, a Spitter aiming, a Nibbler's tell.
	var hero: Node2D = main.leader
	var kinds := ["enforcer", "spitter", "nibbler"]
	var spawned := []
	for k in kinds.size():
		for e in EnemyKinds.spawn(main.entities, hero.global_position + Vector2(50 + 45 * k, 12), {}, kinds[k]):
			e.set_physics_process(false)
			e.set_process(false)
			e.set("state", e.State.WINDUP)
			e.set("state_t", 0.45)
			e.set("anim_t", 0.2)
			if kinds[k] == "spitter":
				e.set("aim", Vector2.LEFT * 30.0)
			spawned.append(e)
	main.get_tree().paused = true
	_redraw(spawned)
	await frames(3)
	await _shot("34_danger_patterned")
	Access.danger_patterns = false
	_redraw(spawned)
	await _shot("35_danger_colour")
	main.get_tree().paused = false
	main._show_results("success")
	await _shot("36_results")
	check(true, "shots taken")


func _redraw(list: Array) -> void:
	for e in list:
		if is_instance_valid(e):
			e.queue_redraw()
			if e.get("overlay"):
				e.overlay.queue_redraw()
