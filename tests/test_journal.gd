extends "res://tests/test_case.gd"
## The journal (issue #114): data/journal.json is complete and well formed, the quest log follows the
## campaign, enemies and history are recorded and saved, the save step fills in old saves, and the
## screen works in town, at the Command Table (with "show on map") and from the mission pause menu.

const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"
const FIXTURE := "res://tests/fixtures/saves/20261121_journal__act1_done_day29.json"
const STORY_KEYS := ["active", "cleared", "not_cleared", "seen", "joined", "renown", "held", "owns", "day"]
const ENTRY_KEYS := ["id", "cat", "title", "text", "more", "unlock", "region", "faction", "enemy", "ink", "habits", "weakness", "defeat"]

var Empire: Node
var J := {}


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	Empire.reset()
	J = JSON.parse_string(FileAccess.get_file_as_string("res://data/journal.json"))


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0


## A campaign at the Command Table after Act 1, with the people it would have by then.
func _act1() -> void:
	Empire.reset()
	Story.begin()
	for t in ["ch1_arrest", "ch1_takeover", "act1_rumours", "act1_writ", "act1_concord_after"]:
		Dialogue.mark_seen("talk:" + t)
	for m in ["meadow_prologue", "ch1_breakout", "act1_concord"]:
		Empire.missions_cleared.append(m)
	for id in ["gristle", "ninefingers", "quill", "tobble"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Empire.day = 12
	for t in Help.topics():  # a day-12 player has heard the explainers and tips (issue #115)
		Help.mark(t["id"])


# ------------------------------------------------------------------ data

func _check_cond(where: String, c) -> void:
	if not check(typeof(c) == TYPE_DICTIONARY, where + ": conditions must be an object"):
		return
	for k in c:
		check(k in STORY_KEYS or k in Journal.OWN_KEYS, "%s: unknown condition %s" % [where, k])


func test_journal_data_is_complete_and_well_formed() -> void:
	var regions := {}
	for r in JSON.parse_string(FileAccess.get_file_as_string("res://data/provinces.json"))["regions"]:
		regions[r["id"]] = true
	var provinces := {}
	for p in JSON.parse_string(FileAccess.get_file_as_string("res://data/provinces.json"))["provinces"]:
		provinces[p["id"]] = true
	var inks: Dictionary = Abilities.data().get("inks", {})
	var kinds: Dictionary = EnemyKinds.data().get("kinds", {})
	var seen := {}
	var linked := {"region": {}, "faction": {}, "enemy": {}, "ink": {}}
	for e in J["codex"]:
		var w := "journal.json codex %s" % e.get("id", "?")
		check(str(e.get("id", "")) != "", w + ": id")
		check(not seen.has(e["id"]), w + ": id used twice")
		seen[e["id"]] = true
		check(str(e.get("cat", "")) in Journal.CATS, w + ": cat")
		check(str(e.get("title", "")) != "" and str(e.get("text", "")).length() > 40, w + ": title and text")
		for k in e:
			check(k in ENTRY_KEYS, "%s: unknown key %s" % [w, k])
		for k in ["unlock", "defeat"]:
			if e.has(k):
				_check_cond(w + " " + k, e[k])
		for m in e.get("more", []):
			_check_cond(w + " more", m.get("when", {}))
			check(str(m.get("text", "")) != "", w + ": more without text")
		if e.has("region"):
			check(regions.has(e["region"]), w + ": no region " + str(e["region"]))
			linked["region"][e["region"]] = true
		if e.has("faction"):
			check(not Empire.faction(e["faction"]).is_empty(), w + ": no faction " + str(e["faction"]))
			linked["faction"][e["faction"]] = true
		if e.has("enemy"):
			check(kinds.has(e["enemy"]) or BossFight.BOSSES.has(e["enemy"]), w + ": no enemy kind " + str(e["enemy"]))
			check(str(e.get("habits", "")) != "" and str(e.get("weakness", "")) != "", w + ": habits and weakness")
			linked["enemy"][e["enemy"]] = true
		if e.has("ink"):
			check(inks.has(e["ink"]) or e["ink"] == "white", w + ": no Ink colour " + str(e["ink"]))
			linked["ink"][e["ink"]] = true
	# Content added elsewhere must arrive with its journal entry, so each chapter fills the codex.
	for r in regions:
		check(linked["region"].has(r), "journal.json: region %s has no codex entry" % r)
	for f in Empire.faction_ids():
		check(linked["faction"].has(f), "journal.json: faction %s has no codex entry" % f)
	for k in kinds:
		check(linked["enemy"].has(k), "journal.json: enemy kind %s has no codex entry" % k)
	for c in inks:
		check(linked["ink"].has(c), "journal.json: Ink colour %s has no codex entry" % c)
	for pid in J.get("provinces", {}):
		check(provinces.has(pid), "journal.json provinces: no province " + str(pid))
		for para in J["provinces"][pid]:
			_check_cond("journal.json provinces " + str(pid), para.get("when", {}))
	var chs := {}
	for c in J["chapters"]:
		check(not chs.has(c["id"]), "journal.json: chapter id %s used twice" % c["id"])
		chs[c["id"]] = true
		check(str(c.get("title", "")) != "", "journal.json chapter %s: title" % c["id"])
		_check_cond("journal.json chapter %s starts" % c["id"], c.get("starts", {}))
		_check_cond("journal.json chapter %s done" % c["id"], c.get("done", {}))
		check(not c.get("recap", []).is_empty(), "journal.json chapter %s: recap" % c["id"])
		for para in c.get("recap", []):
			_check_cond("journal.json chapter %s recap" % c["id"], para.get("when", {}))
	for g in Story.data().get("goals", []):
		check(chs.has(str(g.get("chapter", ""))), "story.json goal '%s': chapter %s is not in journal.json" % [g.get("text", ""), g.get("chapter", "")])
	var figs := {}
	for f in J["figures"]:
		check(not figs.has(f["id"]), "journal.json: figure %s twice" % f["id"])
		figs[f["id"]] = true
		check(str(f.get("name", "")) != "" and str(f.get("text", "")) != "", "journal.json figure %s: name and text" % f["id"])
		check(ResourceLoader.exists("res://assets/portraits/%s.png" % f.get("portrait", "")), "journal.json figure %s: portrait missing" % f["id"])
		_check_cond("journal.json figure %s" % f["id"], f.get("unlock", {}))
	check(InputMap.has_action("journal"), "the journal has an input action")
	var bound := false
	for a in Settings.REMAPPABLE:
		bound = bound or a[0] == "journal"
	check(bound, "the journal key can be rebound in Options")


# ------------------------------------------------------------------ the quest log

func test_quest_log_follows_the_story() -> void:
	Empire.reset()
	Story.begin()
	var q := Journal.story_quests()
	check(q.is_empty(), "nothing on the story list before the prologue is cleared (got %d)" % q.size())
	check_eq(Journal.current_chapter().get("id", ""), "prologue", "a new game starts in the prologue")
	Empire.missions_cleared.append("meadow_prologue")
	q = Journal.story_quests()
	check_eq(Journal.current_chapter().get("id", ""), "ch1", "then Chapter 1")
	check(q.size() == 2 and q[0]["title"] == "Escape the tax office", "Chapter 1 goals listed")
	check(q[0]["next"] != "" and q[0]["state"] == "open", "with a next step")
	_act1()
	q = Journal.story_quests()
	check_eq(Journal.current_chapter().get("id", ""), "act1", "Act 1 after the breakout")
	var titles := q.map(func(x): return x["title"])
	check("The Auditor: stop him on the Tithe Road" in titles, "the Auditor goal shows once the column is broken")
	check(not "Escape the tax office" in titles, "Chapter 1 goals are history now")
	var auditor: Dictionary = q.filter(func(x): return x["title"].begins_with("The Auditor"))[0]
	check_eq(auditor["target"].get("mission", ""), "auditor_duel", "show on map goes to the Auditor's mission")
	check_eq(auditor["where"], "Tithe Road", "and names where it is")
	var done: Array = q.filter(func(x): return x["state"] == "done")
	check(done.size() >= 3, "goals already met are ticked (%d)" % done.size())
	# Saves from before the story: no story goals, but a row that says why.
	Empire.reset()
	Empire.missions_cleared.append("meadow_prologue")
	q = Journal.story_quests()
	check(q.size() == 1 and q[0]["id"] == "story_none", "a story-less campaign says why there is no story")


func test_quest_log_personal_factions_and_open_missions() -> void:
	_act1()
	# Personal: locked under rank 4, open at rank 4 with a Guildhall, done after.
	var pers := Journal.personal_quests()
	check(not pers.is_empty(), "personal stories listed for the core cast")
	var g: Dictionary = pers.filter(func(x): return x["id"] == "personal_gristle")[0]
	check_eq(g["state"], "locked", "Gristle's is locked at rank 0")
	check_eq(g["target"].get("view", ""), "bonds", "and points at the Bonds screen")
	Empire.bonds["gristle"] = {"points": 400, "rank": 4, "talk_day": 0, "personal_done": false}
	Empire.buildings["guildhall"] = 1
	g = Journal.personal_quests().filter(func(x): return x["id"] == "personal_gristle")[0]
	check(g["state"] in ["open", "blocked"], "open (or waiting) at rank 4: %s" % g["state"])
	check(g["next"] != "", "with a next step: " + g["next"])
	Empire.bonds["gristle"]["personal_done"] = true
	g = Journal.personal_quests().filter(func(x): return x["id"] == "personal_gristle")[0]
	check_eq(g["state"], "done", "done once it is done")
	# Factions: what each wants next.
	var fq := Journal.faction_quests()
	check_eq(fq.size(), Empire.faction_ids().filter(func(f): return Journal.faction_known(f)).size(), "one row per known faction")
	check(not fq.any(func(x): return x["id"] == "faction_abbey"), "the Abbey is not listed while its region is under the fog")
	for f in fq:
		check(f["next"] != "" and f["target"].get("view", "") == "diplomacy", "%s: next step and Diplomacy" % f["title"])
	Empire.standing["concord"] = -60
	var cq: Dictionary = Journal.faction_quests().filter(func(x): return x["id"] == "faction_concord")[0]
	check(cq["next"].contains("Concord trouble"), "a hostile Concord warns about trouble")
	# Open missions: a surge makes a timed Defense mission, with its province. Timed rows come first, soonest
	# first (raids and salvage runs have countdowns too, #113).
	Empire.surge = {"id": "meadow", "day": Empire.day + 2}
	var open := Journal.open_quests()
	var defense: Array = open.filter(func(x): return x["id"] == "mission_defense_meadow")
	if check(defense.size() == 1, "the gathering surge is listed"):
		check_eq(int(defense[0]["days"]), Empire.surge_days_left(), "with its countdown")
		check_eq(defense[0]["target"].get("province", ""), "meadow", "and its province")
	var days: Array = open.map(func(x): return int(x["days"]))
	var timed: Array = days.filter(func(d): return d >= 0)
	var sorted_timed := timed.duplicate()
	sorted_timed.sort()
	check(timed == sorted_timed and days.slice(0, timed.size()) == timed, "timed rows first, soonest first")
	check(open.any(func(x): return x["id"] == "mission_reclaim_whitewater"), "erased Whitewater offers a Reclaim")
	check(open.any(func(x): return x.get("type", "") == "patrol"), "patrols listed too")
	check(open.all(func(x): return x["id"] != "mission_auditor_duel"), "story missions stay under Main story")
	# Verity's plans show as timed threats.
	BlankPlans.add("oldmill", "Chalk lines on the road", 3, 4, "governor")
	open = Journal.open_quests()
	check(open.any(func(x): return x.get("type", "") == "plan" and x["where"] == "Old Mill Crossing"), "Verity's plan listed")
	for row in Journal.quests():
		check(row["title"] != "", "every quest has a title")


# ------------------------------------------------------------------ recording and saving

func test_enemies_history_and_reads_are_saved() -> void:
	_act1()
	check(not Journal.seen_enemy("moth"), "moths not met yet")
	var moths := Journal.codex_in("enemies").filter(func(e): return e["id"] == "enemy_moth")
	check(moths.size() == 1 and not moths[0]["unlocked"] and moths[0]["title"] == "???", "an unmet enemy is a ??? row")
	Journal.saw("moth")
	var e: Dictionary = Journal.codex_in("enemies").filter(func(x): return x["id"] == "enemy_moth")[0]
	check(e["unlocked"] and e["new"], "met: unlocked and new")
	check(e["paras"].any(func(p): return p.begins_with("Weakness: beat one")), "weakness hidden until one is beaten")
	Journal.defeated("moth")
	Journal.defeated("moth")
	e = Journal.codex_in("enemies").filter(func(x): return x["id"] == "enemy_moth")[0]
	check(e["paras"].any(func(p): return p.begins_with("Weakness: Paper-thin")), "beaten: the weakness shows")
	check_eq(Journal.kills("moth"), 2, "kills counted")
	Journal.mark_read("enemy_moth")
	Journal.record_mission({"name": "Patrol: Gutterwoods", "outcome": "success", "pay": {"gilt": 12}, "province_id": "gutterwoods",
		"objective": "Thin out the moths", "lines": ["The trail is clear."]})
	# A real expedition coming home writes its report into history.
	Empire.buildings["guildhall"] = 1
	var sent := false
	for jid in Empire.job_ids():
		var j: Dictionary = Empire.job(jid)
		if not sent and j.get("kind", "") != "Rescue" and j.get("personal", "") == "" and Empire.job_blocker(jid) == "":
			sent = Empire.send_expedition(jid, ["quill", "tobble"])
	check(sent, "an expedition went out")
	for i in 4000:
		Empire.tick(0.5)
		if not Journal.log_entries("expedition").is_empty():
			break
	check_eq(Journal.log_entries("expedition").size(), 1, "its report is in the history")
	check_eq(Journal.log_entries("mission").size(), 1, "the mission is in the history")
	check_eq(Journal.log_entries()[0]["kind"], "expedition", "newest first")
	var d: Dictionary = JSON.parse_string(JSON.stringify(Empire.to_dict()))
	Empire.reset()
	check_eq(Journal.kills("moth"), 0, "reset clears the journal")
	Empire.from_dict(d)
	check_eq(Journal.kills("moth"), 2, "kills survive saving")
	check(Journal.is_read("enemy_moth"), "read markers survive saving")
	check_eq(Journal.log_entries().size(), 2, "history survives saving")
	check_eq(Journal.log_entries("mission")[0]["province"], "gutterwoods", "with where it happened")
	# Junk in the save never breaks loading.
	d["journal"] = {"enemies": {"moth": "lots"}, "log": [42, {"no": "title"}], "read": []}
	Empire.from_dict(d)
	check_eq(Journal.kills("moth"), 0, "a broken enemies entry is dropped")
	check(Journal.log_entries().is_empty(), "broken history entries are dropped")


func test_old_saves_get_a_journal() -> void:
	var Saves := autoload("Saves")
	var r: Dictionary = Saves.parse(FileAccess.get_file_as_string(FIXTURE))
	if not check_eq(r["status"], Saves.GOOD, "fixture loads"):
		return
	check("20261121_journal" in r["data"]["migrations"], "the journal step ran")
	var j: Dictionary = r["data"]["empire"]["journal"]
	for k in ["nibbler", "spitter", "enforcer", "auditor"]:
		check(j["enemies"].has(k), "met and beaten before the journal: " + k)
	check(not j["enemies"].has("reedling"), "never went to Saltreed: no reedlings")
	var kinds: Array = j["log"].map(func(e): return e["kind"])
	check_eq(kinds.count("expedition"), 1, "the save's expedition report became history")
	check_eq(kinds.count("mission"), 5, "every mission cleared before the journal is listed")
	check_eq(j["log"][0]["kind"], "expedition", "the dated report comes first")
	check(j["read"].is_empty(), "nothing read yet")
	Empire.from_dict(r["data"]["empire"])
	var aud: Dictionary = Journal.codex_in("enemies").filter(func(x): return x["id"] == "enemy_auditor")[0]
	check(aud["unlocked"] and aud["paras"].any(func(p): return p.begins_with("Weakness: Step sideways")), "the Auditor's page is open, weakness and all")
	check_eq(Journal.current_chapter().get("id", ""), "ch2", "past the End of Act 1, the history is on Chapter 2 (issue #28)")
	var act1: Array = Journal.data()["chapters"].filter(func(c): return c["id"] == "act1")
	check(act1.size() == 1 and Journal.chapter_done(act1[0]), "and knows Act 1 is finished")


# ------------------------------------------------------------------ the screen

func _press(action: String) -> void:
	Input.action_press(action)
	await frames(1)
	Input.action_release(action)
	await frames(1)


func _walk_tabs(v: Control) -> void:
	for t in v.TABS:
		v.open(t)
		await frames(2)
		check(v.visible and v._tab_id() == t, "%s tab opens" % t)
		check(not v._rows.is_empty(), "%s tab has rows" % t)
		for i in mini(v._rows.size(), 40):  # every kind of row draws its page without errors
			if not v._rows[i].has("head"):
				v.sel[v.tab] = i
				v.focus = 1
				v.queue_redraw()
				await frames(1)
		v.focus = 0
	v.close()
	await frames(2)


func test_journal_in_town_and_show_on_map() -> void:
	_act1()
	Empire.surge = {"id": "meadow", "day": Empire.day + 2}
	Journal.saw("nibbler")
	Journal.defeated("nibbler")
	var hub := await goto(HUB, 15)
	if not check(hub != null and hub.journal_view != null, "hub has a journal"):
		return
	await _press("journal")
	check(hub.journal_view.visible, "I opens the journal in town")
	check(not hub.leader.controlled, "Ash stands still while it is open")
	await _press("journal")
	check(not hub.journal_view.visible, "I closes it again")
	await _walk_tabs(hub.journal_view)
	hub.open_menu()
	await frames(2)
	hub._on_menu("journal")
	await frames(2)
	check(hub.journal_view.visible and hub.journal_view._tab_id() == "quests", "the town menu's Journal opens the quests")
	# Show on map from town: the Defense mission's province, on the Command Table.
	var v: Control = hub.journal_view
	for i in v._rows.size():
		if v._rows[i].get("id", "") == "mission_defense_meadow":
			v.sel[v.tab] = i
	v._activate()
	var cmd := await wait_scene(COMMAND)
	if not check(cmd != null, "show on map goes to the Command Table"):
		return
	await frames(3)
	check_eq(Empire.territory().provinces[cmd.selected]["id"], "meadow", "with the Meadow selected")


func test_journal_at_the_command_table_and_in_a_mission() -> void:
	_act1()
	var cmd := await goto(COMMAND, 15)
	if not check(cmd != null and cmd.journal_view != null, "command table has a journal"):
		return
	await _press("journal")
	check(cmd.journal_view.visible, "I opens the journal at the table")
	var speed: int = Empire.speed
	await _press("tab_next")
	check_eq(Empire.speed, speed, "tab keys don't touch the clock while it is open")
	check_eq(cmd.journal_view._tab_id(), "people", "RB moves to the next tab")
	cmd.journal_view.close()
	await frames(2)
	await _walk_tabs(cmd.journal_view)
	cmd.journal_view.open("quests")
	cmd.journal_view.go.emit({"province": "oldmill"})
	await frames(3)
	check_eq(Empire.territory().provinces[cmd.selected]["id"], "oldmill", "show on map selects the province")
	cmd._on_menu("journal")
	await frames(2)
	check(cmd.journal_view.visible, "the Command menu has a Journal")
	cmd.journal_view.close()
	await frames(2)
	# Mid-mission: from the pause menu, readable, but the map waits.
	Dialogue.mark_seen("talk:meadow_intro")
	Empire.active_mission = Missions.find("meadow_patrol").duplicate(true)
	var main := await goto(MAIN, 20)
	if not check(main != null and main.leader != null, "mission running"):
		return
	main.set_paused(true)
	await frames(2)
	check(main._pause_items().any(func(i): return i["id"] == "journal"), "the pause menu has a Journal")
	main._on_pause_choice("journal")
	await frames(2)
	var jv: Control = main.journal_view
	check(jv.visible and not main.pause_menu.visible, "the journal opens over the paused mission")
	check(not jv.can_go, "no show on map mid-mission")
	jv._go({"province": "meadow"})
	await frames(1)
	check(jv.visible and tree.current_scene == main, "asking for the map just explains it has to wait")
	jv.close()
	await frames(3)
	check(main.pause_menu.visible, "closing it goes back to the pause menu")
	# Enemies met in the field reach the journal.
	var e: Node = null
	for n in tree.get_nodes_in_group("enemies"):
		e = n
		break
	if e != null:
		var k := Journal.kind_of(e)
		var before := Journal.kills(k)
		main._on_enemy_died(e)
		check_eq(Journal.kills(k), before + 1, "a kill in the field is counted for " + k)
	main.set_paused(false)
