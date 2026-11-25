extends "res://tests/test_case.gd"
## Onboarding and help (issue #115): data/help.json is complete and well formed, button tokens follow
## the device and remaps, the story opens the empire a piece at a time, explainers play the first
## time each screen opens (and only then), locked screens stay shut with a reason, first-time tips
## come due when things happen, and the Help screen opens from every pause menu and replays topics.

const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"
const HELP_KEYS := ["any", "flag", "surge", "injured", "trouble", "hungry", "visitor", "bond_ready", "fray_high", "seen_help"]
const STORY_KEYS := ["active", "cleared", "not_cleared", "seen", "joined", "renown", "held", "owns", "day"]

var Empire: Node
var Saves: Node
var _tips_were := true
var _device_was := Prompts.KEYS


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	runner.clear_scratch()
	Saves.pending = {}
	Empire.reset()
	_tips_were = Settings.tips_enabled()
	Settings.tips = true
	_device_was = Prompts.device
	Prompts.device = Prompts.KEYS


func after_each() -> void:
	Settings.tips = _tips_were
	Prompts.device = _device_was
	tree.paused = false
	Engine.time_scale = 1.0


## A story campaign on the morning after the takeover: the Command Table has just switched on.
func _day_one() -> void:
	Empire.reset()
	Story.begin()
	for t in ["ch1_arrest", "ch1_takeover"]:
		Dialogue.mark_seen("talk:" + t)
	for m in ["meadow_prologue", "ch1_breakout"]:
		Empire.missions_cleared.append(m)
	Empire.day = 1


## Waits until the scene's help card is up (or `limit` frames pass).
func _wait_card(limit := 60) -> bool:
	for i in limit:
		await tree.process_frame
		if Help.busy():
			return true
	return false


## Skips the talk on the card and waits for the game to get its input back.
func _skip_card() -> void:
	if Help.busy():
		Help.card._close()
	await frames(4)


# ------------------------------------------------------------------ data

func _check_cond(where: String, c) -> void:
	if not check(typeof(c) == TYPE_DICTIONARY, where + ": conditions must be an object"):
		return
	for k in c:
		check(k in STORY_KEYS or k in Journal.OWN_KEYS or k in HELP_KEYS, "%s: unknown condition %s" % [where, k])
	for sub in c.get("any", []):
		_check_cond(where + " (any)", sub)


func _check_tokens(where: String, text: String) -> void:
	var at := text.find("{")
	while at >= 0:
		var close := text.find("}", at)
		var tok := text.substr(at + 1, close - at - 1)
		if tok.begins_with("tag:") or tok.begins_with("key:"):
			check(InputMap.has_action(tok.substr(4)), "%s: no action %s" % [where, tok])
		at = text.find("{", at + 1)


func test_help_data_is_complete_and_well_formed() -> void:
	var ids := {}
	var screens_explained := {}
	for t in Help.topics():
		var id: String = t.get("id", "")
		check(id != "" and not ids.has(id), "topic ids are unique and set: '%s'" % id)
		ids[id] = true
		check(t.get("kind", "") in Help.KINDS, "%s: known kind" % id)
		check(t.get("group", "") in Help.GROUPS, "%s: known group" % id)
		check(str(t.get("title", "")) != "" and str(t.get("summary", "")) != "", "%s: title and summary" % id)
		check(not t.get("lines", []).is_empty(), "%s: has words" % id)
		var voices: Array = t.get("voice", [])
		check(not voices.is_empty(), "%s: has a voice" % id)
		for v in voices:
			check(not Empire.recruit(v).is_empty() or not Dialogue.speaker_info(v).is_empty(), "%s: voice %s exists" % [id, v])
			check(Dialogue.portrait(v) != null, "%s: voice %s has a portrait" % [id, v])
		for v in t.get("alt", {}):
			check(v in voices, "%s: alt lines for %s, who is not a voice" % [id, v])
		for say in ["lines", "locked"]:
			for l in t.get(say, []):
				_check_tokens(id, l if l is String else str(l[1]))
		for v in t.get("alt", {}):
			for l in t["alt"][v]:
				_check_tokens(id, l if l is String else str(l[1]))
		match t.get("kind", ""):
			"screen":
				check(Help.SCREENS.has(t.get("screen", "")), "%s: known screen %s" % [id, t.get("screen", "")])
				screens_explained[t.get("screen", "")] = true
			"unlock":
				check(not t.get("screens", []).is_empty() and t["screens"].all(func(s): return Help.SCREENS.has(s)), "%s: unlocks known screens" % id)
				check(not t.get("locked", []).is_empty(), "%s: says why when asked too early" % id)
				_check_cond(id, t.get("when", {}))
				check(Help._day_of(t.get("when", {})) > 0, "%s: opens by a day at the latest, so nobody is stuck" % id)
			"tip":
				_check_cond(id, t.get("when", {}))
	for s in Help.SCREENS:
		check(screens_explained.has(s), "screen %s has an explainer" % s)
	for need in ["tip_surge", "tip_erased", "tip_injured", "tip_trouble"]:
		check(ids.has(need), "the issue's first-time tip %s exists" % need)
	# Each voice, with or without the people who might not have joined yet, says something whole.
	Empire.reset()
	for t in Help.topics():
		for l in Help.lines(t):
			check(not "{" in l[1] and l[1].strip_edges() != "", "%s: filled line reads cleanly: %s" % [t["id"], l[1]])


func test_prompt_tokens_follow_the_device_and_remaps() -> void:
	Prompts.device = Prompts.KEYS
	check_eq(Prompts.fill("Research{tag:research}"), "Research (T)", "keyboard tag")
	check_eq(Prompts.fill("press {key:journal}"), "press I", "keyboard key")
	check_eq(Prompts.fill("{dev:keys {key:ledger}|pad|touch}"), "keys L", "device choice with a nested token")
	check_eq(Prompts.fill("no tokens here"), "no tokens here", "plain text untouched")
	check_eq(Prompts.fill("a {brace} stays"), "a {brace} stays", "unknown braces untouched")
	Prompts.device = Prompts.PAD
	Prompts.pad_style = "xbox"
	check_eq(Prompts.fill("Roster{tag:roster}"), "Roster (Y)", "pad tag")
	check_eq(Prompts.fill("Research{tag:research}"), "Research (via Menu)", "unbound on a pad: through the menu")
	check_eq(Prompts.fill("{dev:keys|pad|touch}"), "pad", "pad choice")
	Prompts.pad_style = "playstation"
	check_eq(Prompts.fill("{confirm}"), "Cross", "PlayStation names")
	Prompts.pad_style = "xbox"
	Prompts.device = Prompts.TOUCH
	check_eq(Prompts.fill("Research{tag:research}."), "Research.", "no keys on touch")
	check_eq(Prompts.fill("{dev:keys|pad|touch}"), "touch", "touch choice")
	check_eq(Prompts.fill("{dev:keys|pad}"), "keys", "touch falls back to the first choice")
	# Remaps show up.
	Prompts.device = Prompts.KEYS
	var before: Array = InputMap.action_get_events("research")
	InputMap.action_erase_events("research")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_U
	InputMap.action_add_event("research", ev)
	check_eq(Prompts.fill("{tag:research}"), " (U)", "a rebound key shows")
	InputMap.action_erase_events("research")
	for e in before:
		InputMap.action_add_event("research", e)
	# Data that used to hardcode keys now fills them in.
	Prompts.device = Prompts.TOUCH
	for g in Story.goals():
		check(not "(E)" in g["hint"] and not "{" in Prompts.fill(g["hint"]), "story hints carry no fixed keys: " + g["hint"])


# ------------------------------------------------------------------ pacing

func test_the_story_opens_the_empire_a_piece_at_a_time() -> void:
	Empire.reset()  # a campaign from before the story: everything open
	for s in ["expeditions", "research", "diplomacy", "bonds"]:
		check(Help.is_open(s), "%s open without the story" % s)
	_day_one()
	for s in ["expeditions", "research", "diplomacy", "bonds"]:
		check(not Help.is_open(s), "%s shut on the first day" % s)
	for s in ["roster", "buildings", "governor", "journal", "gear", "newcomers", "armory", "party"]:
		check(Help.is_open(s), "%s open from the first day" % s)
	check_eq(Help.locked_note("research"), "day 3", "the button says when")
	check(Empire.role_options("quill").all(func(o): return o["role"] != "envoy"), "no envoys before Diplomacy opens")
	check_eq(Help.due().get("id", ""), "", "nothing due before the Command Table explainer has played")
	Help.mark("command")
	check_eq(Help.due().get("id", ""), "day_one", "then Quill's first-day plan")
	Help.mark("day_one")
	Empire.day = 2
	check(Help.is_open("bonds") and not Help.is_open("expeditions"), "day 2: bonds")
	check_eq(Help.due().get("id", ""), "unlock_bonds", "and Tobble says so")
	Help.mark("unlock_bonds")
	Dialogue.mark_seen("talk:act1_rumours")  # Tobble's rumours open the Guildhall board early
	check(Help.is_open("expeditions") and not Help.is_open("research"), "the rumours open expeditions")
	Empire.day = 3
	check(Help.is_open("research") and not Help.is_open("diplomacy"), "day 3: research")
	Empire.day = 4
	check(Help.is_open("diplomacy"), "day 4: diplomacy")
	check(Empire.role_options("quill").any(func(o): return o["role"] == "envoy"), "envoys once it is open")
	# Unlocks are the story: they play even with tips off. Tips do not.
	Settings.tips = false
	check(Help.due().get("kind", "") == "unlock", "unlocks still due with tips off")
	for t in Help.of_kind("unlock"):
		Help.mark(t["id"])
	Empire.surge = {"id": "hollowmark", "day": 9}
	check(Help.due().is_empty(), "tips stay quiet when switched off")


func test_old_campaigns_are_not_told_their_whole_first_week() -> void:
	_day_one()
	Empire.day = 14
	Help.settle_old_campaign()
	for t in Help.of_kind("unlock"):
		check(Help.seen(t["id"]), "%s counts as told on a day-14 save" % t["id"])


func test_first_time_tips_come_due() -> void:
	_day_one()
	Empire.day = 9
	for t in Help.topics():
		if t["kind"] != "tip":
			Help.mark(t["id"])
	Help.mark("day_one")
	check(Help.due().is_empty(), "a quiet day: nothing due")
	Empire.surge = {"id": "hollowmark", "day": 11}
	check_eq(Help.due().get("id", ""), "tip_surge", "a surge against your land")
	Help.mark("tip_surge")
	check(Help.due().is_empty(), "erased land from before (Whitewater) is not news")
	Help.flag("erased")  # what HelpWatch does when Empire says a province was erased
	check_eq(Help.due().get("id", ""), "tip_erased", "the first erasure")
	Help.mark("tip_erased")
	Empire.recruits["pell"]["injured"] = 3
	check_eq(Help.due().get("id", ""), "tip_injured", "the first injury")
	Help.mark("tip_injured")
	Empire.diplo_log.push_front({"day": 9, "faction": "concord", "text": "A fine.", "change": 0, "trouble": true})
	check_eq(Help.due().get("id", ""), "tip_trouble", "the first Concord trouble")
	Help.mark("tip_trouble")
	Empire.hungry = true
	check_eq(Help.due().get("id", ""), "tip_hungry", "the first hunger")


# ------------------------------------------------------------------ in the real scenes

func test_command_table_explains_itself_and_its_screens_once() -> void:
	_day_one()
	var cmd := await goto(COMMAND, 5)
	if not check(cmd != null and cmd.scene_file_path == COMMAND, "command table running"):
		return
	check(await _wait_card(), "the Command Table explainer plays on the first visit")
	check_eq(Help.card.heading, "The Command Table", "Quill's explainer")
	check_eq(Help.card._current()[0], "quill", "voiced by Quill")
	check(tree.paused, "the clock stops while the card is up")
	await _skip_card()
	check(not tree.paused, "and runs again after")
	check(Help.seen("command"), "marked as heard")
	check(await _wait_card(), "Quill's first-day plan follows")
	await _skip_card()
	# A locked screen stays shut, and someone says why.
	cmd.research_view.open()
	await frames(3)
	check(not cmd.research_view.visible, "research stays shut on day 1")
	check(Help.busy() and Help.card.heading.contains("day 3"), "and the card says when it opens: " + str(Help.card.heading))
	check_eq(Help.card._current()[0], "pell", "Pell explains why")
	await _skip_card()
	# An open screen gets its explainer over it, once.
	cmd.roster_view.open()
	check(await _wait_card(10), "the roster explainer plays the first time")
	check(cmd.roster_view.visible, "over the open roster")
	check_eq(cmd.roster_view.process_mode, Node.PROCESS_MODE_DISABLED, "the roster is held still under the card")
	check_eq(Help.card._current()[0], "bran", "voiced by Bran")
	await _skip_card()
	check(cmd.roster_view.process_mode != Node.PROCESS_MODE_DISABLED, "and gets its input back after")
	cmd.roster_view.close()
	await frames(3)
	cmd.roster_view.open()
	await frames(5)
	check(not Help.busy(), "no explainer the second time")
	cmd.roster_view.close()
	# The voice fits who is there: research falls to Quill until Hild joins.
	var res := Help.topic("research")
	check_eq(Help.voice(res), "quill", "Quill reads the files before Hild joins")
	Empire.recruits["abeyance"] = {"role": "idle", "target": "", "injured": 0}
	check_eq(Help.voice(res), "abeyance", "Hild once she has")
	# Pause menu: locked screens are greyed with their day, and Help is there.
	cmd._open_menu()
	await frames(2)
	var items: Array = cmd.menu.items
	var research: Dictionary = items.filter(func(i): return i["id"] == "research")[0]
	check(not research.get("enabled", true) and str(research.get("note", "")).contains("day 3"), "Research greyed in the menu with its day")
	check(items.any(func(i): return i["id"] == "help"), "Help in the Command menu")
	cmd._on_menu("help")
	await frames(3)
	var hv := _help_view()
	check(hv != null and hv.visible, "Help opens from the Command menu")
	if hv:
		hv.close()
		await frames(3)
	check(cmd.menu.visible, "and goes back to the menu")
	cmd._close_menu()


func test_town_explains_screens_and_plays_unlocks_after_story_beats() -> void:
	_day_one()
	Empire.day = 2
	Help.mark("command")
	Help.mark("day_one")
	var hub := await goto(HUB, 5)
	if not check(hub != null and hub.scene_file_path == HUB, "hub running"):
		return
	# Day 2 in town: Tobble's rumours (a story beat) play first; the unlock waits its turn.
	for i in 30:
		await tree.process_frame
		if hub.dialogue_box.visible:
			break
	check(hub.dialogue_box.visible, "the day-2 story beat plays")
	check(not Help.busy(), "no card over a story beat")
	hub.dialogue_box._close()
	await frames(3)
	if hub.chapter_card.visible:  # the rumours beat names the new story missions on a card
		hub.chapter_card._close()
	var got := {}
	for n in 4:  # unlocks due now: bonds and expeditions (the rumours were heard)
		if not await _wait_card(200):
			break
		got[Help.card.heading] = true
		await _skip_card()
	check(got.has("Bonds open") and got.has("Expeditions open"), "both unlocks played after the beat: %s" % str(got.keys()))
	hub.expedition_view.open()
	check(await _wait_card(10), "the expeditions explainer plays in town too")
	await _skip_card()
	hub.expedition_view.close()
	hub.open_menu()
	await frames(2)
	check(hub.menu.items.any(func(i): return i["id"] == "help"), "Help in the town menu")
	hub._on_menu("help")
	await frames(3)
	var hv := _help_view()
	if not check(hv != null and hv.visible, "Help opens from the town menu"):
		return
	# Replay a topic from the Help screen.
	hv.open("buildings")
	await frames(2)
	check_eq(hv._row().get("id", ""), "buildings", "the buildings topic picked")
	hv._activate()
	check(await _wait_card(5), "it replays on the card over the Help screen")
	check_eq(Help.card.heading, "Buildings", "the buildings explainer")
	await _skip_card()
	check(hv.visible, "Help is still open after the replay")
	# The tips switch flips both ways.
	hv.sel = 1
	var was := Settings.tips_enabled()
	hv._activate()
	check(Settings.tips_enabled() != was, "the switch flips tips")
	hv._activate()
	check_eq(Settings.tips_enabled(), was, "and back")
	hv.sel = 2
	await frames(2)
	check(hv._blocks().any(func(b): return b[0] == "key" and b[1] == "Journal" and b[2] == "I"), "the controls page lists the keyboard keys")
	Prompts.device = Prompts.PAD
	check(hv._blocks().any(func(b): return b[0] == "key" and b[1] == "Roster" and b[2] == "Y"), "and the pad's buttons on a pad")
	Prompts.device = Prompts.KEYS
	hv.close()
	await frames(3)
	check(hub.menu.visible, "back to the town menu")
	hub._close_menu()


func test_help_from_the_mission_pause_menu_and_in_the_codex() -> void:
	Empire.reset()
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	if main == null:
		return
	await frames(10)
	main.set_paused(true)
	await frames(2)
	check(main.pause_menu.items.any(func(i): return i["id"] == "help"), "Help in the mission pause menu")
	main._on_pause_choice("help")
	await frames(3)
	var hv := _help_view()
	if check(hv != null and hv.visible, "Help opens mid-mission"):
		hv.open("field_techs")
		hv._activate()
		check(await _wait_card(5), "field notes replay mid-mission")
		await _skip_card()
		check(tree.paused, "the mission stays paused under Help")
		hv.close()
		await frames(3)
		check(main.pause_menu.visible, "back to the pause menu")
	main.set_paused(false)
	# The codex holds every topic.
	var cx := Journal.codex_in("help")
	check_eq(cx.size(), Help.topics().size(), "every help topic is in the codex")
	check(cx.all(func(e): return not e["paras"].is_empty()), "with its words")
	check("help" in Journal.CATS, "under its own codex heading")


func _help_view() -> HelpView:
	var found: HelpView = null
	for n in tree.root.find_children("*", "HelpView", true, false):
		if (n as Control).visible:
			found = n
	return found


## The playtest goal in the issue, automated: a new player at the Command Table runs the clock from the
## morning after the takeover to day 5, hearing each card as it comes, and ends with every system open
## and explained, nothing stuck behind a lock, and Hollowmark still standing.
func test_a_new_player_reaches_day_five_with_everything_open() -> void:
	_day_one()
	var cmd := await goto(COMMAND, 5)
	if not check(cmd != null and cmd.scene_file_path == COMMAND, "command table running"):
		return
	var heard := []
	for i in 4000:
		await tree.process_frame
		if Help.busy():
			heard.append(Help.card.heading)
			Help.card._close()
			await frames(3)
			continue
		if Empire.day >= 5:
			break
		if not Help.seen("command") or not Help.due().is_empty():
			check(await _wait_card(600), "a due card shows up (%s)" % str(Help.due().get("id", "command")))
			continue  # a player hears it before the next day comes round
		Empire.set_speed(3)
		Empire.tick(8.0)  # about a day every 8 frames at 4x
	check(Empire.day >= 5, "reached day 5 (day %d)" % Empire.day)
	for h in ["The Command Table", "Who to post first", "Bonds open", "Expeditions open", "Research opens", "Diplomacy opens"]:
		check(h in heard, "heard: %s (got %s)" % [h, str(heard)])
	check(heard.find("The Command Table") == 0, "the table explains itself first")
	for s in Help.SCREENS:
		check(Help.is_open(s), "%s open by day 5" % s)
	check(Empire.territory().find("hollowmark").get("owner", "") == "you", "Hollowmark still stands")
	# Each newly opened screen explains itself the first time.
	for v in [cmd.expedition_view, cmd.research_view, cmd.diplomacy_view]:
		v.open()
		check(await _wait_card(10), "%s explains itself once open" % v.name)
		await _skip_card()
		check(v.visible, "and stays open")
		v.close()
		await frames(2)
