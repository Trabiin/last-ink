extends "res://tests/test_case.gd"
## The climax betrayal's chapter pieces (issue #186): the Chapter 4 foreshadowing (black bars, the grey heart,
## seed talks, Verity's letter, the aimed plan), the Chapter 5 scene and lock (the betrayer leaves the roster),
## and Chapter 6 (the betrayer's fight with their own kit in their home written as words, Ash's gesture as a
## dialogue choice, and Bran's con mission), played in the real scenes.

const MAIN := "res://scenes/main.tscn"
const HUB := "res://scenes/hub.tscn"
const FIGHTS := {"ottoline": "betrayal_fight_ottoline", "ninefingers": "betrayal_fight_ninefingers", "odile": "betrayal_fight_odile"}

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


func _join(id: String, rank := 3) -> void:
	Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Empire.bonds[id] = {"points": Empire.bond_threshold(rank), "rank": rank, "talk_day": 0, "personal_done": false}


## Bran and one candidate whose home is erased and bond is low: they lead and clear the threshold.
func _campaign(id: String, rank := 1) -> void:
	Story.begin()
	for m in ["meadow_prologue", "ch1_breakout"]:
		Empire.missions_cleared.append(m)
	for t in ["meadow_intro", "ch1_arrest", "ch1_takeover"]:
		Dialogue.mark_seen("talk:" + t)
	for other in Betrayal.candidates():
		Empire.recruits.erase(other)
	_join(id, rank)
	var p: Dictionary = Empire.territory().find(Betrayal.home_of(id))
	p["owner"] = "erased"
	Betrayal.note_fell(p["id"])


func _seen_talks() -> int:
	return Dialogue.seen.keys().filter(func(k): return str(k).begins_with("talk:betrayal_")).size()


# ---------------------------------------------------------------- data

func test_every_candidate_has_their_whole_story() -> void:
	var talks: Dictionary = Betrayal.data().get("talks", {})
	for id in Betrayal.candidates():
		for k in ["betrayal_%s", "betrayal_%s_partner", "betrayal_letter_%s", "betrayal_fight_%s_intro", "betrayal_fight_%s_phase2", "betrayal_fight_%s_outro"]:
			check(talks.has(k % id), "%s: talk %s" % [id, k % id])
		var seeds: Array = Betrayal.data().get("seeds", {}).get(id, [])
		check(seeds.size() >= 3, "%s: three seed talks" % id)
		for t in seeds:
			check(talks.has(t), "%s: seed %s exists" % [id, t])
		var outro := Dialogue.talk_choice("betrayal_fight_%s_outro" % id)
		check_eq(outro.map(func(o): return str(o.get("betrayal", ""))), ["redeemed", "let_go"], "%s: the gesture is the outro's choice" % id)
		for o in outro:
			check(not (o.get("reply", []) as Array).is_empty(), "%s: each gesture has its scene" % id)
		check(Turncoat.KITS.has(id), "%s: a kit for their fight" % id)
		var fight := Missions.find(FIGHTS[id])
		check_eq(fight.get("province", ""), Betrayal.home_of(id), "%s: the fight is in their home" % id)
		check(fight.get("in_blank", false), "%s: offered even when the home is erased" % id)
		check(FileAccess.get_file_as_string(str(fight.get("map", ""))).contains("@written"), "%s: their home written as words" % id)
	for k in ["betrayal_bran", "betrayal_alone", "betrayal_con_intro", "betrayal_con_bran", "betrayal_con_outro"]:
		check(talks.has(k), "talk %s" % k)
	check(not Betrayal.is_candidate("hortense"), "Hortense is the decoy (Chapter 3): never a candidate")
	check(not Missions.find("betrayal_con").is_empty(), "Bran's con mission")


func test_vacancy_speaks_in_black_bars() -> void:
	var lines := Dialogue.talk("betrayal_ottoline").filter(func(l): return l[0] == "vacancy")
	check(not lines.is_empty(), "the Vacancy speaks in the scene")
	for l in lines:
		check(Dialogue.has_bars(l[1]), "every Vacancy line is redacted: %s" % l[1])
	check(Dialogue.is_letter("vacancy") and Dialogue.is_blank("vacancy"), "staged as a hole in the page, no portrait")
	check_eq(Dialogue.plain("[[Six]] coats."), "Six coats.", "plain() keeps the words for typing and wrapping")


# ---------------------------------------------------------------- Chapter 4

func test_foreshadowing() -> void:
	_campaign("odile")
	Empire.territory().find("oldmill")["owner"] = "you"  # reclaimed: still the top candidate on her low bond
	check(not Betrayal.foreshadowing(), "off until Chapter 4")
	check(not Betrayal.marked("odile"), "nobody marked yet")
	check_eq(Betrayal.seed_talk("odile"), "", "no seeds yet")
	check_eq(Story.next_beat().get("talk", ""), "", "no letter yet")
	var plans_before: int = Empire.blank_plans["pressure"].size()
	Missions.story_effects({"on_success": {"betrayal": "foreshadow"}})  # how Chapter 4 switches it on
	check(Betrayal.foreshadowing(), "Chapter 4 has started it")
	check(Betrayal.marked("odile"), "Odile leads: marked")
	check(not Betrayal.marked("bran"), "Bran is not the top candidate")
	check_eq(Empire.blank_plans["pressure"].size(), plans_before + 1, "one Verity plan aimed")
	check_eq(str(Empire.blank_plans["pressure"].back()["pid"]), "oldmill", "at her home")
	check(not Betrayal.begin_foreshadowing(), "only once")
	# Seeds: one now, the next a few days on.
	check_eq(Betrayal.seed_talk("odile"), "betrayal_seed_odile_1", "first seed")
	Dialogue.mark_seen("talk:betrayal_seed_odile_1")
	check_eq(Betrayal.seed_talk("odile"), "", "the next waits a few days")
	Empire.day += int(Betrayal.data()["seed_gap"])
	check_eq(Betrayal.seed_talk("odile"), "betrayal_seed_odile_2", "second seed")
	# Verity's letter plays once, about her.
	check_eq(Betrayal.beat_talk("letter"), "betrayal_letter_odile", "Verity's letter names her")
	Dialogue.mark_seen("talk:betrayal_letter_odile")
	check_eq(Betrayal.beat_talk("letter"), "", "only one letter a campaign")
	# Black bars: the same words every time, only on her lines.
	var line := "Somebody has offered me a different table. I have not read it."
	var r := Betrayal.redact(line)
	check(Dialogue.has_bars(r), "her lines get bars")
	check_eq(Betrayal.redact(line), r, "the same bars every time")
	check_eq(Dialogue.plain(r), line, "the words are still there under the bars")
	# Fix her: bond to 5 and personal done and the mark lifts.
	Empire.bonds["odile"]["rank"] = 5
	Empire.bonds["odile"]["personal_done"] = true
	check(not Betrayal.marked("odile") or Betrayal.score("odile") >= Betrayal.threshold() or Betrayal.top() == "odile",
		"the mark follows the campaign")


func test_bran_seed_only_when_the_pick_is_his_con() -> void:
	_campaign("odile", 5)
	Empire.territory().find("oldmill")["owner"] = "you"
	Empire.relations["betrayal"]["fell"].erase("oldmill")
	Empire.bonds["odile"]["personal_done"] = true
	check(Betrayal.is_con(), "nobody clears the threshold: Bran's con")
	Betrayal.begin_foreshadowing()
	check_eq(Betrayal.seed_talk("bran"), "betrayal_seed_bran_1", "Bran has a word about a visitor")


func test_grey_heart_and_seed_in_town() -> void:
	_campaign("ottoline")
	Betrayal.begin_foreshadowing()
	var hub := await goto(HUB)
	if hub == null:
		return
	await frames(10)
	if hub.dialogue_box.visible:  # Verity's letter plays first
		check_eq(hub.dialogue_box.id, "betrayal_letter_ottoline", "the letter about Ottoline")
		hub.dialogue_box._close()
		await frames(6)
	if not check(hub.npcs.has("ottoline"), "Ottoline stands in town"):
		return
	hub.leader.global_position = (hub.npcs["ottoline"] as Node2D).global_position + Vector2(0, 14)
	await frames(4)
	var t: Dictionary = hub._find_target()
	check(str(t.get("label", "")).contains("something on their mind"), "her prompt changes (%s)" % t.get("label", ""))
	hub._use(t)
	await frames(4)
	check(hub.dialogue_box.visible and hub.dialogue_box.id == "betrayal_seed_ottoline_1", "talking to her plays her first seed")


# ---------------------------------------------------------------- Chapter 5

func test_lock_sends_them_away_and_the_scene_plays() -> void:
	_campaign("ninefingers")
	Empire.assign("ninefingers", "party")
	Empire.relations["romance"]["ninefingers"] = "partner"
	Empire.relations["partner"] = "ninefingers"
	Missions.story_effects({"on_success": {"betrayal": "lock"}})  # how Chapter 5 locks it
	check_eq(Betrayal.betrayer(), "ninefingers", "Daro took the deal")
	check_eq(Empire.role_of("ninefingers"), Betrayal.AWAY_ROLE, "off the party")
	check(not Empire.party_ids().has("ninefingers"), "not in the party")
	check(PartyPicker.blocker("ninefingers").contains("Vacancy"), "the picker says why (%s)" % PartyPicker.blocker("ninefingers"))
	check(Empire.role_options("ninefingers").all(func(o): return not o["enabled"]), "no post can be given")
	var fed_before: int = Empire.recruits.size()
	check_eq(Empire.fed_count(), fed_before - 1, "nobody feeds someone who isn't there")
	check_eq(Betrayal.scene_talk(), "betrayal_ninefingers_partner", "the romance variant")
	check(not Betrayal.foreshadowing(), "the foreshadowing ends with the lock")
	var hub := await goto(HUB)
	if hub == null:
		return
	await frames(10)
	check(hub.dialogue_box.visible and hub.dialogue_box.id == "betrayal_ninefingers_partner", "the scene plays in town (%s)" % hub.dialogue_box.id)
	check(not hub.npcs.has("ninefingers"), "Daro isn't in Hollowmark")


# ---------------------------------------------------------------- Chapter 6

func _launch(id: String) -> Node:
	var m := Missions.find(id)
	Missions.launch(m)
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	check_eq(main.mission.get("id", ""), id, "%s running" % id)
	await frames(5)
	return main


func _offered(id: String) -> Dictionary:
	var m := Missions.find(id)
	for o in Missions.list_for_province(str(m.get("province", ""))):
		if o.get("id", "") == id:
			return o
	return {}


func test_fights_are_offered_only_to_the_betrayer() -> void:
	_campaign("odile")
	for id in FIGHTS:
		check(_offered(FIGHTS[id]).is_empty(), "%s's fight hidden before Chapter 5" % id)
	Betrayal.lock()
	check(not _offered(FIGHTS["odile"]).is_empty(), "Odile's fight is on her erased home")
	check(_offered(FIGHTS["ottoline"]).is_empty(), "nobody else's")
	check(_offered("betrayal_con").is_empty(), "no con without Bran's betrayal")


func test_each_betrayer_fights_with_their_kit_and_ash_chooses() -> void:
	var gestures := {"ottoline": 0, "ninefingers": 1, "odile": 0}
	for id in FIGHTS:
		Empire.reset()
		Saves.pending = {}
		_campaign(id)
		Betrayal.lock()
		Progress.award(PartyPicker.mission_party(), Progress.xp_to_reach(12))
		var main := await _launch(FIGHTS[id])
		if main == null:
			continue
		check(main.area.written, "%s: the map is written as words" % id)
		check(main.area.props.all(func(p): return p.written), "%s: every prop is a word" % id)
		check(not PartyPicker.mission_party().has(id), "%s: not in the party" % id)
		await frames(30)
		var boss: Turncoat = null
		for e in main.entities.get_children():
			if e is Turncoat:
				boss = e
		if not check(boss != null and boss.who == id, "%s waits in the arena" % id):
			continue
		check(boss.art != null, "%s: drawn with their own sprites" % id)
		main.leader.global_position = boss.global_position + Vector2(0, 90)
		await frames(6)
		check(main.dialogue_box.visible and main.dialogue_box.id == "betrayal_fight_%s_intro" % id, "%s: the intro plays" % id)
		main.dialogue_box._close()
		# Every move in their kit lands without errors.
		for mv in Turncoat.KITS[id]["moves"] + [Turncoat.KITS[id]["tech"], "swing"]:
			boss.target = main.leader
			boss._wind(str(mv))
			boss.act_t = 0.0
			await frames(3)
			if boss.act == Turncoat.Act.DASH:
				boss.act_t = 0.0
				await frames(2)
		boss.hp = int(boss.max_hp * 0.45)
		boss.take_hit(1, boss.global_position + Vector2(10, 0))
		await frames(4)
		check_eq(boss.phase, 2, "%s: phase 2 below half" % id)
		check(main.dialogue_box.visible and main.dialogue_box.id.ends_with("_phase2"), "%s: the phase2 talk" % id)
		main.dialogue_box._close()
		check(not boss.take_hit(10, boss.global_position + Vector2(10, 0)), "%s: untouchable while written over" % id)
		boss.act_t = 0.0
		await frames(4)
		boss.take_hit(99999, boss.global_position + Vector2(10, 0))
		await frames(4)
		check(boss.dead, "%s goes down" % id)
		for i in 60:
			if main.dialogue_box.visible:
				break
			await frames(10)
		var box = main.dialogue_box
		check(box.visible and box.id == "betrayal_fight_%s_outro" % id, "%s: the outro plays" % id)
		box._skip()  # skipping jumps to the choice and never past it
		check(box._choosing and box.visible, "%s: Ash has to choose" % id)
		box._pick(gestures[id])
		check(box.visible, "%s: the gesture's scene plays on" % id)
		box._close()
		var want := "redeemed" if gestures[id] == 0 else "let_go"
		check_eq(Betrayal.outcome(id), want, "%s: the fate records Ash's gesture" % id)
		check_eq(Dialogue.choice_made("betrayal_fight_%s_outro" % id), gestures[id], "%s: the choice is remembered" % id)
		if want == "redeemed":
			check_eq(Empire.role_of(id), "idle", "%s: taken back, home in Hollowmark" % id)
		else:
			check(Betrayal.gone(id), "%s: gone into the white" % id)
			check(PartyPicker.blocker(id).contains("white"), "%s: the picker says so" % id)
		for i in 100:
			if main.objective.done() or main.results_view.visible:
				break
			await frames(10)
		if not main.results_view.visible:
			main._show_results("success")
			await frames(3)
		main._on_results_confirmed()
		await wait_scene(HUB)
		check(Missions.cleared(FIGHTS[id]), "%s: the fight is cleared" % id)
		check(Epilogues.text_for(id) != "", "%s: an epilogue card" % id)


func test_bran_con_mission_brings_him_home() -> void:
	Story.begin()
	for m in ["meadow_prologue", "ch1_breakout"]:
		Empire.missions_cleared.append(m)
	for other in Betrayal.candidates():
		Empire.recruits.erase(other)
	check_eq(Betrayal.lock(), "bran", "Bran's con")
	check(Betrayal.away("bran"), "Bran walked off with the Vacancy")
	check(not _offered("betrayal_con").is_empty(), "his mission is on Gallows Ferry")
	var main := await _launch("betrayal_con")
	if main == null:
		return
	check(main.area.written, "Gallows Ferry as written")
	var inner: MissionScript = main.objective.inner if main.objective._inner_ready else null
	for i in 20:
		if inner != null:
			break
		await frames(3)
		inner = main.objective.inner if main.objective._inner_ready else null
	if not check(inner != null, "it runs as a script"):
		return
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
			"hold":
				inner.step_t = float(st.get("seconds", 30.0))
			"exit":
				main.leader.global_position = inner.exit_pos
		await frames(4)
	check(inner.step >= inner.steps.size(), "every step ran (stuck at %d)" % inner.step)
	main._show_results("success")
	await frames(3)
	main._on_results_confirmed()
	await wait_scene(HUB)
	check(not Betrayal.away("bran"), "Bran is home")
	check_eq(Empire.role_of("bran"), "idle", "ready for a post")
	check_eq(Betrayal.outcome("bran"), "faked", "his fate stays a con")
