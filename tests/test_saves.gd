extends "res://tests/test_case.gd"
## Save versioning and migration (issue #110, docs/SAVES.md).

const FIXTURES := "res://tests/fixtures/saves/"

var Saves: Node
var Empire: Node


func before_each() -> void:
	Saves = autoload("Saves")
	Empire = autoload("Empire")
	runner.clear_scratch()
	Saves.notices = []
	Empire.reset()


func _fixtures() -> Array:
	var out := []
	for f in DirAccess.get_files_at(FIXTURES):
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


func _fixture_text(name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURES + name)


func _put(slot: String, text: String) -> void:
	var f := FileAccess.open(Saves.dir.path_join("save_%s.json" % slot), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _scratch_files() -> Array:
	return Array(DirAccess.get_files_at(Saves.dir))


# ------------------------------------------------------------------ the steps themselves

func test_migration_steps_are_well_formed() -> void:
	var ids: Array = SaveMigrations.ids()
	check(not ids.is_empty(), "no migration steps found in " + SaveMigrations.DIR)
	var sorted := ids.duplicate()
	sorted.sort()
	check_eq(ids, sorted, "steps run in file-name order")
	var rx := RegEx.create_from_string("^\\d{8}_[a-z0-9_]+$")
	for id in ids:
		check(rx.search(id) != null, "step file name '%s' should be <yyyymmdd>_<what>.gd" % id)
		var s: Script = load(SaveMigrations.DIR + id + ".gd")
		var has := false
		for m in s.get_script_method_list():
			has = has or m["name"] == "migrate"
		check(has, "step %s has no static func migrate(save)" % id)


func test_every_step_has_a_fixture() -> void:
	var names := _fixtures()
	for id in SaveMigrations.ids():
		var found := names.any(func(n): return n.begins_with(id + "__"))
		check(found, "step %s needs a save from just before it in %s<id>__<what>.json" % [id, FIXTURES])


# ------------------------------------------------------------------ old saves load

func test_every_fixture_upgrades_and_loads() -> void:
	for name in _fixtures():
		var r: Dictionary = Saves.parse(_fixture_text(name))
		if not check_eq(r["status"], Saves.GOOD, name + " status"):
			continue
		var d: Dictionary = r["data"]
		check_eq(d["version"], Saves.VERSION, name + " format after upgrade")
		check_eq(d["migrations"], SaveMigrations.ids(), name + " has every step after upgrade")
		check(typeof(d.get("empire")) == TYPE_DICTIONARY, name + " has a campaign")
		check(str(d.get("scene", "")).begins_with("res://scenes/"), name + " names a scene")
		Empire.from_dict(d["empire"])
		_check_campaign(name)
		# Saved again, it reads back as current with nothing left to upgrade.
		check(Saves.save("1", d), name + " saves again")
		var again: Dictionary = Saves.inspect("1")
		check_eq(again["status"], Saves.GOOD, name + " re-read")
		check_eq(again.get("migrated", ["?"]), [], name + " needs no upgrade once saved")


## What every loaded campaign must have, whatever it came from: state for all current content.
func _check_campaign(name: String) -> void:
	for id in Empire.recruits:
		check(Empire.recruit_data.has(id), "%s: recruit %s is not in recruits.json" % [name, id])
		check(Empire.ROLE_NAMES.has(Empire.recruits[id]["role"]), "%s: %s has unknown role %s" % [name, id, Empire.recruits[id]["role"]])
	for id in Empire.building_data:
		check(Empire.buildings.has(id), "%s: no level for building %s" % [name, id])
	for fid in Empire.faction_data:
		check(Empire.standing.has(fid), "%s: no standing with %s" % [name, fid])
	for fid in Empire.standing:
		check(Empire.faction_data.has(fid), "%s: standing with unknown faction %s" % [name, fid])
	for rid in Empire.research_done:
		check(Empire.research_data.has(rid), "%s: unknown research %s" % [name, rid])
	var provinces: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/provinces.json"))
	check_eq(Empire.territory().provinces.size(), provinces["provinces"].size(), name + " province count")
	for k in Empire.START:
		check(Empire.res.has(k), "%s: no %s" % [name, k])
	for id in Progress.field_ids():
		check(not Progress.hero(id).is_empty(), "%s: no progress for field hero %s" % [name, id])


func test_first_build_save_is_converted() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261120_save_format_v2__first_build.json"))
	var d: Dictionary = r["data"]
	check_eq(d["scene"], "res://scenes/main.tscn", "scene")
	check_eq(d["mission"].get("id", ""), "meadow_patrol", "mission filled in")
	check_eq(d["banter"][0][0], "bran", "banter speaker is a recruit id")
	check(d["empire"]["dialogue"].get("event:first_kill", false), "said_first_kill became a seen event")
	check(not d["empire"]["dialogue"].has("event:low_power"), "said_low_power false stays unseen")
	check(not d.has("said_first_kill"), "old flag removed")
	check_eq(d["game_version"], "pre-release", "marked as a pre-release save")
	check_eq(float(d["empire"]["playtime"]), 412.5, "playtime kept")


## Issue #113: a squad out on Bran's old personal job comes home with its rations, and the mission waits.
func test_personal_job_in_progress_becomes_a_mission() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261121_personal_missions__table_day31_bran_job_out.json"))
	if not check_eq(r["status"], Saves.GOOD, "save with a personal job out reads"):
		return
	var e: Dictionary = r["data"]["empire"]
	check_eq(e["expeditions"].size(), 0, "the personal job is called off")
	check_eq(int(e["res"]["supplies"]), 40, "the squad's 4 Supplies come back")
	check(not e["job_ready"].has("personal_quill"), "old personal cooldowns forgotten")
	check(e["job_ready"].has("rescue_gristle"), "other cooldowns kept")
	check_eq(str(e["reports"][0].get("job", "")), "personal_bran", "a report says where the story went")
	check(str(e["reports"][0]["lines"]).contains("Gallows"), "report names the mission's province")
	Empire.from_dict(e)
	check_eq(Empire.role_of("bran"), "idle", "Bran is home")
	check_eq(Empire.role_of("gristle"), "idle", "Gristle is home")
	check_eq(Empire.bond_rank("bran"), 4, "bond rank kept")
	check_eq(PersonalMissions.state("bran"), "offered", "Bran's mission is on the Command Table")
	check_eq(PersonalMissions.state("quill"), "offered", "so is Quill's")


## Issue #53: a save from the nine-province map opens on the 24-province map, Act 1 as it was.
func test_pre_region_save_keeps_act1_and_fogs_the_rest() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261120_territory_regions__act1_table_day14.json"))
	if not check_eq(r["status"], Saves.GOOD, "pre-region save reads"):
		return
	var d: Dictionary = r["data"]
	check_eq(d["empire"].get("regions", []), ["marches"], "only the Brack Marches are open")
	Empire.from_dict(d["empire"])
	var t: Territory = Empire.territory()
	check_eq(t.provinces.size(), 24, "the whole map")
	check_eq(t.find("oldmill")["owner"], "you", "Old Mill still yours")
	check_eq(int(t.find("meadow")["fray"]), 46, "Meadow Fray kept")
	check_eq(int(t.find("saltreed")["scar"]), 2, "surge scar kept")
	check_eq(Empire.governor_of("oldmill"), "quill", "governor kept")
	check_eq(Empire.surge.get("id", ""), "saltreed", "surge kept")
	check(not Empire.province_open(t.find("abbey")), "the Abbey is under the fog")
	check_eq(int(t.find("halfwave")["fray"]), 40, "new provinces start as written")
	check_eq(t.find("spire")["owner"], "concord", "the capital is the Concord's")


func test_cut_content_is_dropped_not_fatal() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261120_save_format_v2__hub_day9.json"))
	Empire.from_dict(r["data"]["empire"])
	check(not Empire.recruits.has("cut_recruit"), "a recruit cut from the game is dropped")
	check(not "cut_research_node" in Empire.research_done, "a cut research node is dropped")
	check(not Empire.standing.has("cut_faction"), "a cut faction is dropped")
	check_eq(Empire.recruits["bran"]["role"], "idle", "a job that no longer exists falls back to idle")
	check_eq(Empire.day, 9, "day kept")
	check_eq(int(Empire.res["gilt"]), 200, "gilt kept")
	check_eq(Empire.expeditions.size(), 1, "running expedition kept")
	check_eq(Empire.recruits["quill"]["role"], "governor", "governor kept")
	check(Empire.research_active != "", "research in progress kept")
	check_eq(Empire.bond_rank("bran"), 2, "bond rank kept")


# ------------------------------------------------------------------ the slot rules

func test_current_save_round_trip() -> void:
	Empire.day = 5
	Empire.res["gilt"] = 333
	check(Saves.save("2", {"scene": Saves.HUB_SCENE, "area_name": "Hollowmark", "x": 10.0, "y": 20.0}), "save")
	var r: Dictionary = Saves.inspect("2")
	check_eq(r["status"], Saves.GOOD, "status")
	check_eq(r["migrated"], [], "nothing to upgrade")
	check_eq(r["data"]["game_version"], Saves.game_version(), "game version recorded")
	check_eq(Saves.latest_slot(), "2", "latest slot")
	var before: Dictionary = Empire.to_dict()
	Empire.reset()
	Empire.from_dict(r["data"]["empire"])
	check_eq(JSON.stringify(Empire.to_dict()), JSON.stringify(JSON.parse_string(JSON.stringify(before))), "campaign survives the round trip")


func test_newer_format_is_kept_and_not_loaded() -> void:
	var text := JSON.stringify({"version": Saves.VERSION + 1, "game_version": "9.9.9", "saved_at": 5, "empire": {}})
	_put("1", text)
	var r: Dictionary = Saves.inspect("1")
	check_eq(r["status"], Saves.NEWER, "status")
	check(Saves.describe("1").contains("newer version"), "menu says it is from a newer version")
	check_eq(Saves.latest_slot(), "", "Continue skips it")
	check_eq(FileAccess.get_file_as_string(Saves.dir.path_join("save_1.json")), text, "file left alone")


func test_unknown_step_means_newer() -> void:
	_put("3", JSON.stringify({"version": Saves.VERSION, "migrations": SaveMigrations.ids() + ["29991231_from_the_future"], "empire": {}}))
	check_eq(Saves.inspect("3")["status"], Saves.NEWER, "status")


func test_overwriting_a_newer_save_keeps_a_copy() -> void:
	var text := JSON.stringify({"version": Saves.VERSION + 1, "empire": {}})
	_put("1", text)
	check(Saves.save("1", {"scene": Saves.HUB_SCENE}), "save over it")
	var kept := _scratch_files().filter(func(f): return f.begins_with("save_1.newer-"))
	if check_eq(kept.size(), 1, "backup of the newer save"):
		check_eq(FileAccess.get_file_as_string(Saves.dir.path_join(kept[0])), text, "backup holds the original")


func test_upgraded_save_keeps_its_old_copy_when_overwritten() -> void:
	var text := _fixture_text("20261120_save_format_v2__hub_day9.json")
	_put("2", text)
	check(Saves.save("2", {"scene": Saves.HUB_SCENE}), "save over it")
	var kept := _scratch_files().filter(func(f): return f.begins_with("save_2.v"))
	if check_eq(kept.size(), 1, "pre-upgrade copy"):
		check_eq(FileAccess.get_file_as_string(Saves.dir.path_join(kept[0])), text, "copy holds the original")
	Saves.save("2", {"scene": Saves.HUB_SCENE})
	check_eq(_scratch_files().filter(func(f): return f.begins_with("save_2.v")).size(), 1, "no copy for an up-to-date save")


func test_unreadable_saves_are_set_aside_and_reported() -> void:
	allow_log("Save [0-9a-z]+ set aside")
	var cases := {"1": "{\"version\": 1, \"empire\": {", "2": "", "3": "[1, 2, 3]", "auto": "{\"empire\": {}}"}
	for slot in cases:
		_put(slot, cases[slot])
	Saves.check_all()
	for slot in cases:
		check(not FileAccess.file_exists(Saves.dir.path_join("save_%s.json" % slot)), "slot %s file moved aside" % slot)
		var kept := _scratch_files().filter(func(f): return f.begins_with("save_%s.broken-" % slot))
		if check_eq(kept.size(), 1, "slot %s backup" % slot):
			check_eq(FileAccess.get_file_as_string(Saves.dir.path_join(kept[0])), cases[slot], "slot %s backup is byte for byte" % slot)
		check_eq(Saves.inspect(slot)["status"], Saves.EMPTY, "slot %s is free" % slot)
	var notes: Array = Saves.take_notices()
	check_eq(notes.size(), cases.size(), "one notice per set-aside save")
	check(notes.size() > 0 and str(notes[0]).contains("set aside"), "notice explains what happened")
	check_eq(Saves.take_notices(), [], "notices are handed over once")


# ------------------------------------------------------------------ old saves in the real scenes

func test_old_mission_save_resumes_the_mission() -> void:
	_put("1", _fixture_text("20261120_save_format_v2__mid_mission.json"))
	check(Saves.load_and_play("1"), "load")
	var main := await wait_scene("res://scenes/main.tscn")
	if main == null:
		return
	check_eq(main.mission.get("id", ""), "gutterwoods_patrol", "same mission")
	check_eq(main.kills, 5, "kills kept")
	check_eq(Empire.day, 9, "campaign day")


func test_first_build_save_resumes_in_the_meadow() -> void:
	_put("2", _fixture_text("20261120_save_format_v2__first_build.json"))
	check(Saves.load_and_play("2"), "load")
	var main := await wait_scene("res://scenes/main.tscn")
	if main == null:
		return
	check_eq(main.mission.get("id", ""), "meadow_patrol", "meadow patrol")
	check_eq(main.kills, 7, "kills kept")
	check(main.heroes.size() > 0, "party on the field")


func test_old_town_save_resumes_in_hollowmark() -> void:
	_put("3", _fixture_text("20261120_save_format_v2__hub_day9.json"))
	check(Saves.load_and_play("3"), "load")
	var hub := await wait_scene("res://scenes/hub.tscn")
	if hub == null:
		return
	check(hub.leader.global_position.distance_to(Vector2(600, 420)) < 1.0, "Ash where the save left them")


## Issue #112: an old satchel full of found extras keeps the starting pack and stores the rest.
func test_unlimited_satchel_moves_extras_to_the_stores() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261121_stores_and_satchel__table_day31_full_satchel.json"))
	if not check_eq(r["status"], Saves.GOOD, "save with a full old satchel reads"):
		return
	var e: Dictionary = r["data"]["empire"]
	check_eq(int(e["satchel"]["tonic"]), 3, "three Tonics stay packed")
	check_eq(int(e["satchel"]["salts"]), 1, "one Salts stays packed")
	var a: Dictionary = e["progress"]["armory"]
	check_eq(int(a["stores"]["tonic"]), 4, "four extra Tonics go to the stores")
	check_eq(int(a["stores"]["salts"]), 1, "the extra Salts too")
	check_eq(int(a["stores"]["draught"]), 2, "and two Draughts")
	Empire.from_dict(e)
	check_eq(Armory.stored("tonic"), 4, "stores survive loading")
	check(Armory.satchel_total() <= Armory.satchel_slots(), "the satchel fits its capacity")
	check_eq(Armory.pack_of("tonic"), 3, "the pack is the starting stock")


## Issue #112: a save made mid-mission keeps its satchel until the mission ends.
func test_mid_mission_satchel_is_left_alone() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261120_save_format_v2__mid_mission.json"))
	if not check_eq(r["status"], Saves.GOOD, "old mission save reads"):
		return
	var e: Dictionary = r["data"]["empire"]
	check(e["progress"]["armory"]["stores"].is_empty(), "nothing moved to the stores mid-mission")


## Issue #158: the naming pass rewrites old display names in a save's history; ids stay as they were.
func test_old_names_in_history_are_renamed() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261124_names__table_day42_old_names.json"))
	if not check_eq(r["status"], Saves.GOOD, "save written before the naming pass reads"):
		return
	var text := JSON.stringify(r["data"])
	check(not text.contains("Hesper Quoin"), "old name gone from the history")
	check(text.contains("Hetty Coyne did not come back"), "new name in the same line")
	check(text.contains("\"hesper\""), "the recruit id is untouched")
	Empire.from_dict(r["data"]["empire"])
	check_eq(Empire.short_name("hesper"), "Hetty", "the recruit shows the new name")
	check_eq(Empire.short_name("quill"), "Quill", "Edwin \"Quill\" Pask goes by Quill")


## Issue #28: Chapter 2's factions get their land in old saves, and a campaign past the End of Act 1 sees the
## Abbey region open.
func test_chapter2_lands_and_region() -> void:
	var r: Dictionary = Saves.parse(_fixture_text("20261125_chapter2__table_day42_after_act1.json"))
	if not check_eq(r["status"], Saves.GOOD, "save from before Chapter 2 reads"):
		return
	var e: Dictionary = r["data"]["empire"]
	check("abbey" in e["regions"], "the Abbey region opens for a campaign past act1_end")
	Empire.from_dict(e)
	check_eq(Empire.territory().find("abbey")["owner"], "abbey", "Saint Ledger's belongs to the Abbey")
	check_eq(Empire.territory().find("ossuary")["owner"], "erasers", "the Bonefield belongs to the Erasers")
	check_eq(Empire.tier_of("abbey"), "wary", "the Abbey starts Wary")
	check_eq(Empire.tier_of("erasers"), "hostile", "the Erasers start Hostile")
	var want := "ch2_bells" if Story.held() >= 6 else ""
	check_eq(Story.next_beat().get("talk", ""), want, "Chapter 2's first beat waits for six provinces (%d held)" % Story.held())
