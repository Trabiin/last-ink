extends "res://tests/test_case.gd"
## Act 1 meaning pass (Ojon 2026-11-25): the four set pieces on their premade maps (the tax office breakout,
## Gristle's tree, Daro's farm, Millbrook), each choice branch run in the real mission scene, the people they
## save or lose counted into Incidents, the bonus pay and cost, and the incidents (requests with an asker, a
## deadline and a rival) opening, lapsing and coming home. Also the building kit: roofs fade when the hero is
## inside, and allies path around walls.

const MAIN := "res://scenes/main.tscn"
const HUB := "res://scenes/hub.tscn"
const SET_PIECES := ["ch1_breakout", "act1_gristle", "act1_daro", "act1_concord"]

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


## A story campaign just after the takeover of Hollowmark (the rumours beat seen).
func _after_takeover() -> void:
	Empire.reset()
	Story.begin()
	for m in ["meadow_prologue", "ch1_breakout"]:
		Empire.missions_cleared.append(m)
	for t in ["meadow_intro", "ch1_arrest", "ch1_takeover", "act1_rumours"]:
		Dialogue.mark_seen("talk:" + t)


func _inner(main: Node) -> MissionObjectives:
	return main.objective.inner if main.objective._inner_ready else null


func _launch_dict(m: Dictionary) -> Node:
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	check_eq(main.mission.get("id", ""), m.get("id", ""), "%s running" % m.get("id", ""))
	await frames(5)
	# A mission with an intro talk starts its script once the talk is closed.
	var guard := 0
	while not main.objective._inner_ready and guard < 20:
		guard += 1
		if main.dialogue_box.visible:
			main.dialogue_box._close()
		await frames(3)
	return main


## Walks a script mission the quick way. picks = {talk id: option}: when that talk's choice comes up, Ash
## picks it through the dialogue box. Lead steps: everyone is walked to safety, except `lose` of them, who go
## down and stay down.
func _walk(main: Node, inner: MissionScript, id: String, picks: Dictionary, lose := 0) -> void:
	var guard := 0
	var lost_left := lose
	while inner.step < inner.steps.size() and guard < 90 and not main.objective.failed():
		guard += 1
		var st: Dictionary = inner.st
		match str(st.get("do", "")):
			"talk":
				if main.dialogue_box.visible:
					var box = main.dialogue_box
					var tid := str(box.id)
					if picks.has(tid) and not box._choices.is_empty():
						box._pick(int(picks[tid]))
					if box.visible:
						box._close()
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
			"lead":
				var to: Vector2 = inner.spot(st.get("to", "start"))
				for f in inner.folk.duplicate():
					if not is_instance_valid(f) or f.safe:
						continue
					if lost_left > 0 and not f.dead:
						lost_left -= 1
						f.freed = true
						f.hp = 0
						f.dead = true
						f.down_t = MissionScript.Folk.DOWN_LIMIT + 1.0
					elif not f.dead:
						f.freed = true
						f.global_position = to
			"exit":
				main.leader.global_position = inner.exit_pos
		await frames(4)
	check(not main.objective.failed(), "%s did not fail on the way (%s)" % [id, inner.fail_why])
	check(inner.step >= inner.steps.size(), "%s ran every step (stuck at %d: %s)" % [id, inner.step, inner.st])


func _finish(main: Node) -> void:
	main._show_results("success")
	await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)


func _run(id: String, picks: Dictionary, lose := 0) -> MissionScript:
	var main := await _launch_dict(Missions.find(id))
	if main == null:
		return null
	var inner := _inner(main) as MissionScript
	if not check(inner != null, "%s runs as a script" % id):
		return null
	await _walk(main, inner, id, picks, lose)
	await _finish(main)
	return inner


# ---------------------------------------------------------------- data

func test_set_piece_data_hangs_together() -> void:
	for id in SET_PIECES:
		var m := Missions.find(id)
		if not check(not m.is_empty(), "%s exists" % id):
			continue
		check(str(m.get("stakes", "")) != "", "%s says what is at stake" % id)
		var spots: Dictionary = Area.header(str(m["map"]))["spots"]
		for st in m["objective"]["steps"]:
			for k in ["at", "to"]:
				var v = st.get(k)
				if typeof(v) == TYPE_STRING:
					check(spots.has(v), "%s: spot %s is on %s" % [id, v, m["map"]])
			if st.has("talk"):
				check(Dialogue.data()["talks"].has(str(st["talk"])), "%s: talk %s exists" % [id, st["talk"]])
			var w: Dictionary = st.get("when", {})
			for k in ["chose", "not_chose"]:
				if w.has(k):
					var tid := str(w[k][0])
					check(int(w[k][1]) < Dialogue.talk_choice(tid).size(), "%s: %s has option %s" % [id, tid, w[k][1]])


func test_incident_data_hangs_together() -> void:
	var talks: Dictionary = Dialogue.data()["talks"]
	var ids := []
	for i in Incidents.all():
		var id := str(i["id"])
		ids.append(id)
		check(not Empire.territory().find(str(i["province"])).is_empty(), "%s: province %s exists" % [id, i["province"]])
		for k in ["ask", "done_talk", "ignored_talk"]:
			check(talks.has(str(i.get(k, ""))), "%s: %s talk exists" % [id, k])
		for k in ["asker_name", "stakes", "if_ignored", "notice"]:
			check(str(i.get(k, "")) != "", "%s has %s" % [id, k])
		var m: Dictionary = i["mission"]
		var spots: Dictionary = Area.header(str(m["map"]))["spots"]
		for st in m["objective"]["steps"]:
			if st.has("talk"):
				check(talks.has(str(st["talk"])), "%s: talk %s exists" % [id, st["talk"]])
			for k in ["at", "to"]:
				var v = st.get(k)
				if typeof(v) == TYPE_STRING:
					check(spots.has(v), "%s: spot %s is on %s" % [id, v, m["map"]])
			if st.get("do", "") == "lead":
				check(m.get("people", {}).has(str(st["group"])), "%s: its people %s are described" % [id, st["group"]])
		if m.has("force"):
			check(not Empire.recruit(str(m["force"])).is_empty(), "%s: forced hero %s exists" % [id, m["force"]])
	for i in Incidents.all():
		var r := str(i.get("rival", ""))
		if r != "":
			check(r in ids and str(Incidents.find(r).get("rival", "")) == str(i["id"]), "%s and %s are each other's rival" % [i["id"], r])
			check_eq(Incidents.find(r).get("when", {}), i.get("when", {}), "%s opens on the same day as its rival" % i["id"])


# ---------------------------------------------------------------- incidents

func test_incidents_open_lapse_and_rival() -> void:
	_after_takeover()
	Empire.day = 2
	Incidents.check()
	check_eq(Incidents.state("wickham_lamps"), "", "nothing opens before its day")
	Empire.day = 5
	Incidents.check()
	check_eq(Incidents.state("wickham_lamps"), "open", "Wickham's lamps open")
	check_eq(Incidents.state("reedmere_school"), "open", "Reedmere opens")
	check_eq(Incidents.state("fever_cart"), "open", "its rival opens with it")
	check_eq(Incidents.state("charcoal_burners"), "", "the Gristle/Daro pair waits for both to join")
	var m := Incidents.mission("reedmere_school")
	check_eq(m.get("type", ""), "request", "a request on the map")
	check_eq(m.get("rival_name", ""), str(Incidents.find("fever_cart")["name"]), "it names the rival it would leave")
	check_eq(int(m.get("days_left", -1)), 2, "two days to answer")
	check(Missions.list_for_province("saltreed").any(func(x): return x["id"] == "incident_reedmere_school"), "on the province's mission list")
	var lines := Missions.stake_lines(m)
	check(lines.size() >= 3, "the brief opens with who asks, what is at stake and what lapsing costs")
	# Wickham: nobody goes.
	var fray := int(Empire.territory().find("lampwick")["fray"])
	Empire.day = 9
	Incidents.check()
	check_eq(Incidents.state("wickham_lamps"), "ignored", "Wickham lapses after its deadline")
	check_eq(int(Empire.territory().find("lampwick")["fray"]), mini(99, fray + 15), "the hills fray")
	check_eq(Incidents.people("wickham")["lost"], 3, "the lamplighters are lost")
	check_eq(Incidents.state("fever_cart"), "ignored", "the fever cart lapsed too")
	check(Story.meets({"incident": {"wickham_lamps": "closed"}}), "story condition: closed")
	check(Story.meets({"lost": {"wickham": 1}}), "story condition: lost")
	check(not Story.meets({"saved": {"wickham": 1}}), "story condition: saved")
	var beat_talks := Incidents.beats().map(func(b): return b["talk"])
	check("wickham_dark" in beat_talks, "the consequence plays in town")


func test_answering_one_lapses_its_rival() -> void:
	_after_takeover()
	Empire.day = 5
	Incidents.check()
	var supplies := int(Empire.res.get("supplies", 0))
	var main := await _launch_dict(Incidents.mission("reedmere_school"))
	if main == null:
		return
	var inner := _inner(main) as MissionScript
	if not check(inner != null, "the request runs as a script"):
		return
	await _walk(main, inner, "reedmere_school", {}, 1)
	await _finish(main)
	check_eq(Incidents.state("reedmere_school"), "done", "Reedmere answered")
	check_eq(Incidents.state("fever_cart"), "ignored", "the fever cart went unanswered")
	check_eq(Incidents.people("reedmere"), {"saved": 4, "lost": 1}, "four children out, one lost")
	check(int(Empire.res.get("supplies", 0)) < supplies + 6 + 1, "the fever cost supplies")
	var hurt: Array = Empire.recruits.keys().filter(func(r): return int(Empire.recruits[r].get("injured", 0)) > 0)
	check(hurt.size() >= 1, "the fever put people in bed")
	check("reedmere_thanks" in Incidents.beats().map(func(b): return b["talk"]), "the thanks plays in town")


func test_gristle_daro_pair_and_save() -> void:
	_after_takeover()
	for id in ["gristle", "ninefingers"]:
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Empire.day = 9
	Incidents.check()
	check_eq(Incidents.state("charcoal_burners"), "open", "Gristle asks")
	check_eq(Incidents.state("tollgate_families"), "open", "Daro asks the same day")
	check_eq(Incidents.mission("charcoal_burners").get("force", ""), "gristle", "Gristle goes herself")
	var d: Dictionary = Empire.to_dict()
	Empire.reset()
	Empire.from_dict(JSON.parse_string(JSON.stringify(d)))
	check_eq(Incidents.state("tollgate_families"), "open", "open requests survive a save")
	Empire.bond_gain("ninefingers", 30, "test", true)
	var bond: int = Empire.bond_points("ninefingers")
	Incidents.lapse("tollgate_families")
	check_eq(Incidents.people("tollgate")["lost"], 5, "the families are struck out")
	check(Empire.bond_points("ninefingers") < bond, "Daro remembers")


# ---------------------------------------------------------------- set pieces

func test_breakout_leading_the_pruetts() -> void:
	Empire.reset()
	Story.begin()
	Empire.missions_cleared.append("meadow_prologue")
	for t in ["meadow_intro", "ch1_arrest"]:
		Dialogue.mark_seen("talk:" + t)
	var gilt := int(Empire.res.get("gilt", 0))
	var inner := await _run("ch1_breakout", {"ch1_ledger_room": 0}, 1)
	if inner == null:
		return
	check(Missions.cleared("ch1_breakout"), "breakout cleared")
	check_eq(Dialogue.choice_made("ch1_ledger_room"), 0, "Ash took the key")
	check_eq(Incidents.people("pruetts"), {"saved": 3, "lost": 1}, "three Pruetts out, one lost")
	check(int(Empire.res.get("gilt", 0)) < gilt + 90, "no strongbox money")
	check(Story.meets({"saved": {"pruetts": 3}}), "the Pruetts beat can ask who got out")


func test_breakout_taking_the_strongbox() -> void:
	Empire.reset()
	Story.begin()
	Empire.missions_cleared.append("meadow_prologue")
	for t in ["meadow_intro", "ch1_arrest"]:
		Dialogue.mark_seen("talk:" + t)
	var gilt := int(Empire.res.get("gilt", 0))
	var inner := await _run("ch1_breakout", {"ch1_ledger_room": 1})
	if inner == null:
		return
	check_eq(Dialogue.choice_made("ch1_ledger_room"), 1, "Ash took the strongbox")
	check(int(Empire.res.get("gilt", 0)) >= gilt + 90 + 30, "the strongbox paid")
	check_eq(Incidents.people("pruetts"), {"saved": 0, "lost": 4}, "the Pruetts were left")
	check(Story.meets({"lost": {"pruetts": 4}}), "and the story knows")


func test_gristle_both_ways() -> void:
	for pick in [0, 1]:
		_after_takeover()
		Empire.res["gilt"] = 200
		var coven: int = Empire.standing_of("coven")
		var inner := await _run("act1_gristle", {"act1_gristle_tree": pick})
		if inner == null:
			return
		check(Empire.recruits.has("gristle"), "Gristle joins (option %d)" % pick)
		check_eq(Dialogue.choice_made("act1_gristle_tree"), pick, "the choice is remembered")
		var g := int(Empire.res.get("gilt", 0))
		if pick == 0:
			check(g < 200 + 20 + 1, "paying the knives cost gilt (%d)" % g)
		else:
			check(g >= 200 + 70, "the bounty purse paid (%d)" % g)
			check(Empire.standing_of("coven") <= coven - 14, "the Coven noticed")
		check(not Missions.list_for_province("gutterwoods").any(func(x): return x.get("id", "") == "act1_gristle"), "she is not asked for twice")


func test_daro_both_ways() -> void:
	for pick in [0, 1]:
		_after_takeover()
		var inner := await _run("act1_daro", {"act1_daro_farm": pick})
		if inner == null:
			return
		check(Empire.recruits.has("ninefingers"), "Daro joins (option %d)" % pick)
		if pick == 0:
			check_eq(Incidents.people("hobbs")["saved"], 5, "the Hobbs walk out")
		else:
			check_eq(Incidents.people("hobbs")["lost"], 5, "the Hobbs were taken")
			check(Story.meets({"chose": ["act1_daro_farm", 1]}), "Millbrook will remember the order")


func test_concord_with_hobb_and_millbrook() -> void:
	for pick in [0, 1]:
		_after_takeover()
		for id in ["gristle", "ninefingers"]:
			Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
		Dialogue.make_choice("act1_daro_farm", 1, {})
		Dialogue.mark_seen("talk:act1_writ")
		for pid in ["meadow", "oldmill", "lampwick", "saltreed"]:
			Empire.territory().find(pid)["owner"] = "you"
		Empire.res["renown"] = 20
		var inner := await _run("act1_concord", {"act1_concord_hamlet": pick})
		if inner == null:
			return
		check(Missions.cleared("act1_concord"), "Concord cleared (option %d)" % pick)
		check(Dialogue.seen.has("talk:act1_concord_hobb"), "Hobb turns up when the wagon order was chosen")
		if pick == 0:
			check_eq(Incidents.people("millbrook")["saved"], 6, "Millbrook gets into the mill")
		else:
			check_eq(Incidents.people("millbrook")["lost"], 6, "Millbrook is marched")


# ---------------------------------------------------------------- kit

func test_kit_roofs_fade_and_allies_path() -> void:
	_after_takeover()
	var main := await _launch_dict(Missions.find("act1_daro"))
	if main == null:
		return
	var roofs: Array = main.area.roofs
	if not check(roofs.size() >= 1, "the farm has roofs"):
		return
	check(Paths.active, "the path grid is up on a kit map")
	var inner := _inner(main) as MissionScript
	var inside: Vector2 = inner.spot("inside")
	var t := Vector2i(floori(inside.x / 16.0), floori(inside.y / 16.0))
	var hits := roofs.filter(func(r): return r.covers(t))
	if not check(hits.size() == 1, "the farmhouse spot is under one roof"):
		return
	var roof = hits[0]
	for n in 5:
		if main.dialogue_box.visible:
			main.dialogue_box._close()
		await frames(3)
	main.leader.global_position = Vector2(40, 40)
	await frames(30)
	check(roof.modulate.a > 0.9, "the roof is solid from outside")
	main.leader.global_position = inside
	await frames(40)
	check(roof.modulate.a < 0.5, "the roof fades with the hero inside (%.2f)" % roof.modulate.a)
	var a := Vector2(inside.x, inside.y)
	var outside := inner.spot("farm")
	if not Paths.clear(a, outside):
		var d: Vector2 = Paths.toward(main.leader, outside)
		check(d.length() > 0.0, "a path leads out of the house")
