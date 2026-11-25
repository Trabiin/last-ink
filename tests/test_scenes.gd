extends "res://tests/test_case.gd"
## Scene smoke tests (issue #110): the real scenes boot, the screens open, every mission type
## launches and settles, and saving and loading put the player back where they were.
## These catch crashes and script errors (tools/run_tests.sh fails on any in the log); the
## numbers are checked by the unit-style tests.

const TITLE := "res://scenes/title.tscn"
const MAIN := "res://scenes/main.tscn"
const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"

var Empire: Node
var Saves: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	runner.clear_scratch()
	Saves.pending = {}
	Empire.reset()


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0


## A campaign past Chapter 1, so the Command Table and the clock are on.
func _campaign() -> void:
	Empire.reset()
	for id in ["gristle", "ninefingers", "abeyance"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Dialogue.mark_seen("talk:meadow_intro")


func test_title_boots() -> void:
	var t := await goto(TITLE)
	check(t != null and t.scene_file_path == TITLE, "title scene running")
	check(t.menu.visible, "title menu shown")
	check(t.menu.items.any(func(i): return i["id"] == "new"), "New Game offered")


func test_title_reports_set_aside_saves() -> void:
	allow_log("Save [0-9a-z]+ set aside")
	var f := FileAccess.open(Saves.dir.path_join("save_1.json"), FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	Saves.check_all()
	var t := await goto(TITLE)
	check(not t.menu.visible, "the notice comes before the menu")
	var notice: Node = t.get_children().filter(func(c): return c is InkMenu and c.visible).back()
	check(notice != null and str(notice.subtitle).contains("Slot 1"), "notice names the slot")
	notice.chosen.emit("ok")
	await frames(2)
	check(t.menu.visible, "menu back after OK")


func test_new_game_starts_the_prologue() -> void:
	var t := await goto(TITLE)
	t._on_choice("new")
	var main := await wait_scene(MAIN)
	if main == null:
		return
	check_eq(main.mission.get("id", ""), "meadow_prologue", "story starts with the prologue")
	check(main.heroes.size() > 0 and main.leader != null, "party on the field")
	check(Story.active(), "story switched on")


func test_hub_loads_and_every_screen_opens() -> void:
	_campaign()
	var hub := await goto(HUB, 15)
	check(hub != null and hub.scene_file_path == HUB, "hub running")
	check(hub.leader != null, "Ash in town")
	hub.open_menu()
	await frames(3)
	var cmd := await goto(COMMAND, 15)
	if not check(cmd != null and cmd.scene_file_path == COMMAND, "command table running"):
		return
	var views := {"roster": cmd.roster_view, "buildings": cmd.buildings_view, "expeditions": cmd.expedition_view,
		"research": cmd.research_view, "diplomacy": cmd.diplomacy_view, "bonds": cmd.bonds_view,
		"newcomers": cmd.newcomers_view}
	for name in views:
		var v: Control = views[name]
		v.open()
		await frames(3)
		check(v.visible, name + " screen opens")
		v.close()
		await frames(2)
		check(not v.visible, name + " screen closes")
	cmd.gear_view.open("town")
	await frames(3)
	check(cmd.gear_view.visible, "gear screen opens")
	cmd.gear_view.close()
	cmd.governor_view.open("hollowmark")
	await frames(3)
	check(cmd.governor_view.visible, "governor screen opens")
	cmd.governor_view.close()
	var m: Dictionary = Missions.find("meadow_patrol")
	cmd._open_brief(m)
	await frames(3)
	check(cmd.brief_menu.visible, "briefing opens")
	cmd._on_brief("go")
	await frames(3)
	check(cmd.party_picker.visible, "party picker opens from the briefing")
	cmd.party_picker.close()
	cmd._open_menu()
	await frames(3)
	check(cmd.menu.visible, "pause menu opens")
	cmd._close_menu()
	Empire.set_speed(Empire.SPEEDS.size() - 1)
	await frames(30)  # let the clock run at 4x for a moment
	check(Empire.day_t > 0.0, "clock running")


## Launches a mission the way the briefing does, wins it and walks home.
func _play(m: Dictionary, outcome := "success") -> Node:
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	check_eq(main.mission.get("id", ""), m["id"], "mission %s running" % m["id"])
	await frames(20)
	main._show_results(outcome)
	await frames(3)
	check(main.results_view.visible, "%s results screen" % m["id"])
	main._on_results_confirmed()
	return await wait_scene(HUB)


func test_patrol_mission() -> void:
	_campaign()
	var hub := await _play(Missions.find("gutterwoods_patrol"))
	check(hub != null, "home after the patrol")
	check(Missions.cleared("gutterwoods_patrol"), "patrol cleared")
	check(Saves.inspect("auto")["status"] == Saves.GOOD, "autosaved on the way home")


func test_retreat_keeps_the_mission_open() -> void:
	_campaign()
	await _play(Missions.find("saltreed_patrol"), "retreat")
	check(not Missions.cleared("saltreed_patrol"), "retreat does not clear it")


func test_boss_mission() -> void:
	_campaign()
	Progress.award(PartyPicker.mission_party(), Progress.xp_to_reach(6))  # the Auditor is tuned for level 6 (issue #35)
	await _play(Missions.find("auditor_duel"))
	check(Missions.cleared("auditor_duel"), "Auditor beaten")


func test_defense_mission() -> void:
	_campaign()
	var p: Dictionary = Empire.territory().find("meadow")
	Empire.surge = {"id": "meadow", "day": Empire.day + 2}
	var m := MissionTypes.defense(p)
	await _play(m)
	check(Empire.surge.is_empty() or Empire.surge.get("id", "") != "meadow", "surge broken")


## Ojon: the party used to arrive at a half-eaten wardstone. The surge now waits for them to reach it.
func test_defense_waits_for_the_party() -> void:
	_campaign()
	var p: Dictionary = Empire.territory().find("meadow")
	Empire.surge = {"id": "meadow", "day": Empire.day + 2}
	var m := MissionTypes.defense(p)
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return
	await frames(10)
	var o: MissionObjectives = main.objective.inner
	if not check(o != null and o.kind == "defense", "defense objective running"):
		return
	check(o.grace > 0.0, "the surge waits at the start (%.1f s)" % o.grace)
	var clock := o.time_left
	o.update(5.0)
	check_eq(o.time_left, clock, "the hold clock does not run while the party walks over")
	check(main.get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get("goal") == o.ward).is_empty(), "no Nibbler goes for the stone yet")
	check_eq(o.ward.hp, o.ward.max_hp, "the stone is whole when the party arrives")
	main.leader.global_position = o.ward.position + Vector2(-40, 0)
	o.update(0.1)
	check_eq(o.grace, 0.0, "reaching the stone starts the surge")
	o.update(3.0)
	check(o.time_left < clock, "the hold clock runs once the surge comes")
	main._show_results("retreat")
	await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)


func test_reclaim_mission() -> void:
	_campaign()
	Empire.res["ink"] = 20
	var p: Dictionary = Empire.territory().find("whitewater")
	check_eq(p.get("owner", ""), "erased", "Whitewater starts erased")
	var m := MissionTypes.reclaim(p)
	check_eq(str(m.get("blocker", "")), "", "reclaim can launch")
	await _play(m)
	check(Empire.territory().find("whitewater")["owner"] != "erased", "land rewritten")


func test_rescue_mission() -> void:
	Empire.reset()
	Dialogue.mark_seen("talk:meadow_intro")
	var jid := ""
	for id in Empire.job_ids():
		if Empire.job(id).get("recruit", "") == "gristle":
			jid = id
	if not check(jid != "", "rescue job for Gristle"):
		return
	await _play(MissionTypes.rescue(jid))
	check(Empire.recruits.has("gristle"), "Gristle joined")


func test_quick_menu_opens_and_slows_time() -> void:
	_campaign()
	Empire.active_mission = Missions.find("meadow_patrol").duplicate(true)
	var main := await goto(MAIN, 20)
	main.open_quick_menu()
	await frames(3)
	check(main.quick_open, "quick menu open")
	check(Engine.time_scale < 1.0, "time slows while it is open")
	main.quick_menu.close()
	await frames(3)
	check(not main.quick_open, "quick menu closed")
	check_eq(Engine.time_scale, 1.0, "time back to normal")


func test_mission_save_and_load() -> void:
	_campaign()
	Empire.active_mission = Missions.find("oldmill_patrol").duplicate(true)
	var main := await goto(MAIN, 20)
	main.kills = 4
	main.leader.global_position = Vector2(300, 260)
	Empire.res["gilt"] = 777
	check(Saves.save("1", main.snapshot()), "save mid-mission")
	Empire.res["gilt"] = 1
	check(Saves.load_and_play("1"), "load")
	var again := await wait_scene(MAIN)
	if again == null:
		return
	check(again != main, "a fresh scene")
	check_eq(again.mission.get("id", ""), "oldmill_patrol", "same mission")
	check_eq(again.kills, 4, "kills")
	check(again.leader.global_position.distance_to(Vector2(300, 260)) < 2.0, "leader position")
	check_eq(int(Empire.res["gilt"]), 777, "campaign restored")


func test_town_and_command_save_and_load() -> void:
	_campaign()
	var hub := await goto(HUB, 15)
	hub.leader.global_position = Vector2(520, 380)
	Empire.day = 6
	check(Saves.save("2", hub.snapshot()), "save in town")
	var cmd := await goto(COMMAND, 10)
	Empire.day = 8
	check(Saves.save("3", cmd.snapshot()), "save at the table")
	Empire.day = 1
	check(Saves.load_and_play("2"), "load town save")
	var hub2 := await wait_scene(HUB)
	if hub2 != null:
		check(hub2.leader.global_position.distance_to(Vector2(520, 380)) < 2.0, "Ash where they stood")
		check_eq(Empire.day, 6, "town save day")
	check(Saves.load_and_play("3"), "load table save")
	if await wait_scene(COMMAND) != null:
		check_eq(Empire.day, 8, "table save day")
	check_eq(Saves.latest_slot(), "3", "Continue picks the newest")


# ------------------------------------------------------------------ mission variety (issue #113)

## The mission's objective once it has set itself up (it does on the first frame the world exists).
func _inner(main: Node) -> MissionObjectives:
	return main.objective.inner if main.objective._inner_ready else null


func test_raid_mission() -> void:
	_campaign()
	Empire.day = 1
	var p: Dictionary = Empire.territory().find("gallows")
	check_eq(p.get("owner", ""), "guild", "Gallows Ferry is Guild land")
	var m := MissionTypes.raid(p)
	check_eq(str(m.get("blocker", "")), "", "raid can launch")
	check(m["objective"]["caches"].size() >= 3, "caches laid out")
	var standing_was: int = Empire.standing_of("guild")
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return
	await frames(10)
	var inner := _inner(main)
	if not check(inner != null and inner.caches.size() == m["objective"]["caches"].size(), "caches on the map"):
		return
	check(main.respawn_t > 1e8, "no Blank stream on a raid")
	var gilt_before := int(main.found.get("gilt", 0))
	for i in inner.need:
		inner.caches[i].done = true
		inner._open_cache(inner.caches[i])
	check(int(main.found.get("gilt", 0)) > gilt_before, "a cache pays into what the party carries")
	check(inner.alarm > 0.0, "prying caches open raises the alarm")
	check(inner.exit_visible(), "exit shown once enough is taken")
	var saved: Dictionary = main.snapshot()
	check_eq(int(saved["objective"]["inner"]["taken"]), inner.need, "mid-mission save keeps the caches taken")
	main._show_results("success")
	await frames(3)
	check(main.results_view.visible, "raid results")
	main._on_results_confirmed()
	await wait_scene(HUB)
	check(Empire.standing_of("guild") < standing_was, "the Guild noticed")
	check(MissionTypes.raid_open(Empire.territory().find("gallows")) < 0, "no second raid straight away")


func test_raid_is_refused_on_friends() -> void:
	_campaign()
	Empire.standing["guild"] = 40
	var m := MissionTypes.raid(Empire.territory().find("gallows"))
	check(str(m.get("blocker", "")) != "", "no raiding a Friendly faction")


func test_salvage_mission() -> void:
	_campaign()
	var p: Dictionary = Empire.territory().find("meadow")
	p["fray"] = 50
	var m := MissionTypes.salvage(p)
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return
	await frames(10)
	var inner := _inner(main)
	if not check(inner != null and inner.caches.size() >= 3, "piles on the map"):
		return
	var start_x: float = main.blank.base_x
	check(inner.grace > 0.0, "the white waits long enough to reach the first pile")
	check(main.objective.text().contains("moves in"), "the objective counts the wait down")
	await frames(30)
	check_eq(main.blank.base_x, start_x, "the white holds still during the grace")
	inner.grace = 0.0
	await frames(30)
	check(main.blank.base_x < start_x, "then the white creeps toward the piles")
	main._show_results("success")
	await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)
	check(Empire.mission_ready.has("salvage:meadow"), "the meadow rests after a salvage")


func test_type_missions_vary_their_layout() -> void:
	_campaign()
	var p: Dictionary = Empire.territory().find("meadow")
	Empire.surge = {"id": "meadow", "day": Empire.day + 2}
	var seen := {}
	for d in 12:
		Empire.day = 1 + d
		var m := MissionTypes.defense(p)
		seen[m["map"] + str(m["objective"]["ward"]) + str(m["layout"].get("blank", 0))] = true
		check(int(m["layout"].get("blank", 99)) >= int(m["objective"]["ward"][0]) + MissionTypes.BLANK_GAP, "the white starts clear of the wardstone")
	check(seen.size() >= 4, "twelve days give several different layouts (%d)" % seen.size())
	Empire.day = 3
	check_eq(MissionTypes.defense(p)["map"], MissionTypes.defense(p)["map"], "same day, same layout")


func _bond_to(id: String, rank: int) -> void:
	Empire.recruits[id] = Empire.recruits.get(id, {"role": "idle", "target": "", "injured": 0})
	Empire.bonds[id] = {"points": Empire.bond_threshold(rank), "rank": rank, "talk_day": 0, "personal_done": false}


func test_personal_mission_field_hero() -> void:
	_campaign()
	_bond_to("bran", 3)
	check_eq(Missions.personal_state("bran"), "locked", "locked below rank 4")
	_bond_to("bran", 4)
	check_eq(Missions.personal_state("bran"), "offered", "offered at rank 4")
	var offered := Missions.list_for_province("gallows").filter(func(m): return m.get("type", "") == "personal")
	if not check(offered.size() == 1, "Gallows Ferry offers Bran's mission"):
		return
	Empire.assign("bran", "idle")
	var m: Dictionary = offered[0]
	check_eq(str(m.get("force", "")), "bran", "Bran is forced into the party")
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return
	check(main.heroes.any(func(h): return h.hero_id == "bran"), "Bran came along without being picked")
	await frames(5)
	var inner := _inner(main) as MissionScript
	if not check(inner != null, "the script runs"):
		return
	check(main.dialogue_box.visible, "the opening talk plays")
	main.dialogue_box._close()
	await frames(3)
	check_eq(str(inner.st.get("do", "")), "goto", "then the first goal")
	main.leader.global_position = inner.spot("landing")
	await frames(3)
	check_eq(str(inner.st.get("do", "")), "clear", "reaching the landing moves on")
	check(inner.elite != null, "Big Corrie turns up")
	main._show_results("success")
	await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)
	check(Empire.personal_done("bran"), "personal mission done")
	check_eq(Empire.bond_next_scene("bran"), 5, "the rank 5 scene is waiting")
	check_eq(Missions.personal_state("bran"), "done", "and it leaves the table")


func test_personal_mission_escort() -> void:
	_campaign()
	_bond_to("quill", 4)
	var m := Missions.personal_for("quill")
	check_eq(str(m.get("escort", "")), "quill", "Quill comes as an escort")
	check(not m.has("force"), "staff are not forced into the fighting party")
	check_eq(Missions.find("personal_quill").get("who", ""), "quill", "Missions.find resolves personal ids")
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return
	await frames(5)
	var inner := _inner(main) as MissionScript
	if not check(inner != null and inner.escort != null, "Quill is on the field"):
		return
	check_eq(inner.escort.hero_id, "quill", "the escort is Quill")
	main.dialogue_box._close()
	await frames(2)
	check(not main.heroes.has(inner.escort), "the escort is not a playable hero")
	inner.escort.take_hit(999, inner.escort.global_position + Vector2(10, 0))
	await frames(2)
	check(inner.escort.dead, "Quill can go down")
	inner.down_t = MissionScript.DOWN_LIMIT + 1.0
	await frames(3)
	check(main.objective.failed(), "staying down fails the mission")
