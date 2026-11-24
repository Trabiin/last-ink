extends "res://tests/test_case.gd"
## Playtest survey (issues #148, #168): the questions keep AI out of every page before the AI page,
## that page locks the earlier answers, answers become a "survey" report with survey.json attached,
## the form opens from the title and every pause menu only in playtest builds, the title welcomes
## testers once per round and asks for the survey after enough play, and a sent survey is remembered.

const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"
const TITLE := "res://scenes/title.tscn"
const STATE := "user://test_run/playtest.cfg"
const AI_WORDS := "(?i)\\bA\\.?I\\b|generat|artificial|machine learning|neural"

var Empire: Node
var Saves: Node
var Diag: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	Diag = autoload("Diag")
	runner.clear_scratch()
	Saves.pending = {}
	Saves.current_slot = ""
	Empire.reset()
	Diag.previous = {}
	Feedback.override = {"endpoint": ""}  # tests never reach the real inbox
	Survey.override = {}
	Survey.as_release = false
	Survey.state_path = STATE
	DirAccess.remove_absolute(STATE)
	for t in Help.topics():
		Help.mark(t["id"])
	Access.load_settings()
	Access.first_boot_done = true  # these tests drive the title as a returning player (the first-start page is test_access)


func after_each() -> void:
	Diag.scripted = true
	Feedback.override = {"endpoint": ""}  # tests never reach the real inbox
	Survey.override = {}
	Survey.as_release = false
	Survey.state_path = STATE
	tree.paused = false


func _view() -> SurveyView:
	var found := tree.root.find_children("*", "SurveyView", true, false)
	for v in found:
		if is_instance_valid(v) and v.visible:
			return v
	return null


func _wait_view(limit := 30) -> SurveyView:
	for i in limit:
		await tree.process_frame
		var v := _view()
		if v:
			return v
	return null


func _close(v: SurveyView) -> void:
	if v == null:
		return
	v._discard_armed = true
	v._on_cancel()
	await frames(3)


func test_questions_are_well_formed_and_neutral_before_the_ai_page() -> void:
	var pages := Survey.pages()
	check(pages.size() >= 3, "the survey has pages")
	check(Survey.version() >= 1, "the survey has a version")
	var ids := {}
	var ai_at := -1
	var ai_re := RegEx.create_from_string(AI_WORDS)
	for i in pages.size():
		var p: Dictionary = pages[i]
		check(str(p.get("title", "")) != "", "page %d has a title" % i)
		if p.get("ai", false):
			check(ai_at == -1, "only one AI page")
			ai_at = i
		for q in p.get("questions", []):
			var qid := str(q.get("id", ""))
			check(qid != "" and not ids.has(qid), "question id %s is set and unique" % qid)
			ids[qid] = true
			check(str(q.get("type", "")) in Survey.TYPES, "%s: known type %s" % [qid, q.get("type")])
			check(str(q.get("prompt", "")) != "", "%s has a prompt" % qid)
			match str(q["type"]):
				"scale":
					check(q.get("labels", []).size() == 5, "%s: a five-point scale" % qid)
				"choice", "multi":
					check(q.get("options", []).size() >= 2, "%s: options to pick" % qid)
			if ai_at == -1:
				# Before the AI page nothing may say AI, so any mention there is the tester's own.
				var words := [str(p.get("title", "")), str(p.get("intro", "")), str(q["prompt"])]
				words.append_array(q.get("options", []))
				words.append_array(q.get("labels", []))
				for w in words:
					check(ai_re.search(str(w)) == null, "page %s mentions AI before the AI page: \"%s\"" % [p["id"], w])
	check(ai_at > 0, "the AI page exists and isn't first")
	check(ai_at >= pages.size() - 2, "the AI page is the last page of questions (only the thank-you page after it)")
	for need in ["stop_reason", "enjoy", "odd_art", "alive_most", "alive_least", "flat_lines", "buy", "price", "ai_feel", "ai_buy"]:
		check(ids.has(need), "the survey asks %s" % need)
	var ai_buy := Survey.find_question("ai_buy")
	check(str(ai_buy.get("labels", [""])[0]).contains("because of this"), "ai_buy 1 means: wouldn't buy because of AI (tools/playtest_report.py counts it)")
	# playtest.json: a release build has no round; a playtest build names one like r1.
	var s := Survey.settings()
	check(str(s["round"]) == "" or RegEx.create_from_string("^r\\d+$").search(str(s["round"])) != null, "round is empty or r<n>: %s" % s["round"])
	check(str(s["welcome"]).contains("screenshot"), "the welcome note asks not to share screenshots")
	check(Survey.ai_short() != "", "a short AI statement to show")
	check(Survey.ai_url().begins_with("https://"), "a link to the full AI statement")
	for k in ["unprompted_ai_max", "ai_wont_buy_baseline", "ai_wont_buy_alarm"]:
		check(float(s.get("targets", {}).get(k, 0)) > 0, "target %s set" % k)


func test_release_builds_have_no_survey() -> void:
	Survey.as_release = true
	check(not Survey.enabled(), "no round and no test feature: off")
	check(Survey.menu_items().is_empty(), "no menu entry")
	check(not Survey.should_offer(), "never offered")
	Survey.override = {"round": "r1"}
	check_eq(Survey.round_id(), "r1", "a playtest build names its round")
	check_eq(Survey.menu_items().size(), 1, "and has the menu entry")
	Survey.as_release = false
	Survey.override = {}
	check_eq(Survey.round_id(), "dev", "editor and test builds count as round dev")


func test_answers_become_a_survey_report() -> void:
	Empire.recruits["bran"] = Empire.recruits.get("bran", {})
	var answers := {
		"enjoy": 4,
		"difficulty": 9,  # out of range: dropped
		"stop_reason": "I got bored",
		"price": "a million",  # not an option: dropped
		"loved": "  The moth packs.  ",
		"alive_most": {"id": "bran", "name": "Bran", "other": ""},
		"alive_least": {"id": Survey.OTHER, "name": "", "other": "the toll clerk"},
		"odd_art": "",  # blank: dropped
		"nonsense": "x",  # unknown question: dropped
		"ai_buy": 3,
		"contact": "tester@example.com",
	}
	var r := Survey.build_report(answers, {"ai_page_seen": true, "minutes": 4.5, "characters": ["Bran"]})
	check_eq(r["kind"], "survey", "kind survey")
	check_eq(r["contact"], "tester@example.com", "the contact line goes to the report's contact field")
	check(r["attachments"].has("survey.json"), "answers attached")
	check(not r["attachments"].has("save_1.json") and not r["attachments"].has("session.log"), "no logs or save in a survey")
	var payload = JSON.parse_string(r["attachments"]["survey.json"]["data"])
	var a: Dictionary = payload["answers"]
	check_eq(payload["round"], "dev", "the round")
	check_eq(int(payload["survey_version"]), Survey.version(), "the survey version")
	check(payload["ai_page_seen"], "whether the AI page was reached")
	check_eq(int(a.get("enjoy", 0)), 4, "a scale answer")
	check_eq(a.get("stop_reason"), "I got bored", "a choice answer")
	check_eq(a.get("loved"), "The moth packs.", "typed text trimmed")
	check(not a.has("difficulty") and not a.has("price") and not a.has("odd_art") and not a.has("nonsense") and not a.has("contact"),
		"bad, blank and unknown answers dropped, contact not duplicated: %s" % str(a.keys()))
	check_eq(a["alive_least"]["other"], "the toll clerk", "someone else, named")
	var text: String = r["text"]
	check(text.contains("How much did you enjoy it overall?\n  4/5 A lot"), "the readable copy has the question and answer")
	check(text.contains("Someone else: the toll clerk"), "someone else in the readable copy")
	check(not text.contains("tester@example.com"), "contact not in the text")
	check(JSON.parse_string(Feedback.to_json(r))["kind"] == "survey", "sent as kind survey")
	# A huge answer is cut to fit.
	var long := Survey.build_report({"loved": "x".repeat(5000), "confused": "y".repeat(5000), "annoyed": "z".repeat(5000)})
	check(long["text"].length() <= Feedback.MAX_TEXT, "the report text fits the inbox limit")


func test_offers_after_enough_play_and_remembers() -> void:
	Survey.override = {"offer_after_min": 30}
	Empire.playtime = 10 * 60.0
	check(not Survey.should_offer(), "not after 10 minutes")
	Empire.playtime = 31 * 60.0
	check(Survey.should_offer(), "after 30 minutes")
	Survey.mark_offered()
	check(not Survey.should_offer(), "not again straight away")
	Empire.playtime = (31 + Survey.REOFFER_MIN + 1) * 60.0
	check(Survey.should_offer(), "again after more play")
	Survey.mute_offers()
	check(not Survey.should_offer(), "Don't ask again holds")
	DirAccess.remove_absolute(STATE)
	check(not Survey.submitted(), "fresh state: not sent")
	Survey.mark_submitted("LI-00000001")
	check(Survey.submitted() and not Survey.should_offer(), "a sent survey is never offered again")
	check(Survey.menu_items()[0]["detail"].contains("thank you"), "the menu entry says it was sent")
	Survey.override = {"round": "r2"}
	check(not Survey.submitted(), "a new round asks afresh")


func test_form_walks_the_pages_and_locks_before_the_ai_page() -> void:
	Empire.recruits["bran"] = Empire.recruits.get("bran", {})
	var title := await goto(TITLE)
	check(title.menu.items.any(func(i): return i["id"] == "survey"), "Playtest survey on the title menu")
	title._on_choice("survey")
	var v := await _wait_view()
	if not check(v != null, "the survey opens from the title"):
		return
	check(not title.menu.visible, "the title menu hides under it")
	check(v.back_button.disabled, "no Back on the first page")
	check(v.cast.any(func(c): return c["id"] == "bran"), "the character questions offer the roster")
	v._set_answer("stop_reason", "I ran out of time")
	v._on_next()
	await frames(1)
	check_eq(v.page, 1, "Next goes to page 2")
	v._set_answer("enjoy", 5)
	v._on_back()
	check_eq(v.page, 0, "Back goes back")
	check_eq(v.answers.get("stop_reason"), "I ran out of time", "answers survive paging")
	var ai := v.ai_page_index()
	while v.page < ai - 1:
		v._on_next()
	check(not v.ai_page_seen, "the AI page not seen yet")
	v._on_next()
	check_eq(v.page, ai, "on the AI page")
	check(v.ai_page_seen, "AI page seen")
	check(v.back_button.disabled, "no way back to the neutral pages from the AI page")
	v._on_back()
	check_eq(v.page, ai, "Back does nothing there")
	var shown := []
	for l in v.body.find_children("*", "Label", true, false):
		shown.append(l.text)
	check(" ".join(shown).contains(Survey.ai_short().left(30)), "the AI page quotes the statement")
	v._set_answer("ai_buy", 3)
	v._on_next()
	check_eq(v.page, ai + 1, "on to the thank-you page")
	v._on_back()
	check_eq(v.page, ai, "can step back to the AI page itself")
	v._on_next()
	# This build has no inbox: the last button saves to a file and counts as done.
	check(not Feedback.can_send(), "no endpoint in tests")
	check_eq(v.next_button.text, "Save to file", "the last button saves to a file")
	v._on_next()
	await frames(2)
	check(v.sent, "done after saving")
	check(v.saved_path != "" and FileAccess.file_exists(v.saved_path), "the zip is written")
	var zip := ZIPReader.new()
	if check(zip.open(v.saved_path) == OK, "the zip opens"):
		var payload = JSON.parse_string(zip.read_file("survey.json").get_string_from_utf8())
		check_eq(payload["answers"].get("stop_reason"), "I ran out of time", "the zip holds the answers")
		check(not payload["answers"].has("alive_most__pick"), "the form's own picks aren't answers")
		zip.close()
	DirAccess.remove_absolute(v.saved_path)
	check(Survey.submitted(), "remembered as sent")
	v._on_next()  # Close
	await frames(3)
	check(title.menu.visible, "back to the title menu")
	var item = title.menu.items.filter(func(i): return i["id"] == "survey")
	check(not item.is_empty() and str(item[0]["detail"]).contains("thank you"), "the entry now says thank you")


func test_character_pick_and_discard_guard() -> void:
	Empire.recruits["bran"] = Empire.recruits.get("bran", {})
	var title := await goto(TITLE)
	title._on_choice("survey")
	var v := await _wait_view()
	if not check(v != null, "opens"):
		return
	v.show_page(2)  # look, characters and writing
	var rows := v.body.find_children("*", "HFlowContainer", true, false)
	var picked := false
	for row in rows:
		for b in row.get_children():
			if b is Button and b.text == Empire.short_name("bran") and not picked:
				b.button_pressed = true
				picked = true
	check(picked, "Bran is a button")
	check_eq(v.answers.get("alive_most", {}).get("id", ""), "bran", "picking a character answers the question")
	for row in rows:
		for b in row.get_children():
			if b is Button and b.text == Empire.short_name("bran") and b.button_pressed:
				b.button_pressed = false
				break
	check(not v.answers.has("alive_most"), "pressing it again clears the answer")
	v._set_answer("flat_lines", "something")
	v._on_cancel()
	await frames(2)
	check(v.visible, "closing with answers asks first")
	v._on_cancel()
	await frames(3)
	check(not is_instance_valid(v) or not v.visible, "second press closes")
	check(not Survey.submitted(), "closing doesn't count as sent")


func test_pause_menus_offer_the_survey() -> void:
	var hub := await goto(HUB, 20)
	hub.open_menu()
	await frames(2)
	check(hub.menu.items.any(func(i): return i["id"] == "survey"), "survey in the town menu")
	hub._on_menu("survey")
	var v := await _wait_view()
	check(v != null, "opens in town")
	await _close(v)
	check(hub.menu.visible, "back to the town menu")
	hub._close_menu()
	var cmd := await goto(COMMAND, 20)
	cmd._open_menu()
	await frames(2)
	check(cmd.menu.items.any(func(i): return i["id"] == "survey"), "survey in the Command menu")
	cmd._on_menu("survey")
	v = await _wait_view()
	check(v != null, "opens at the table")
	await _close(v)
	cmd._close_menu()
	Empire.reset()
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	if main == null:
		return
	await frames(10)
	main.set_paused(true)
	await frames(2)
	check(main.pause_menu.items.any(func(i): return i["id"] == "survey"), "survey in the mission pause menu")
	main._on_pause_choice("survey")
	v = await _wait_view()
	if check(v != null, "opens mid-mission"):
		check(tree.paused, "the game stays paused")
		check_eq(v.current_report()["context"]["mission"], "meadow_patrol", "the answers know the mission")
	await _close(v)
	check(main.pause_menu.visible, "back to the pause menu")
	main.set_paused(false)
	# Release build: no entry anywhere.
	Survey.as_release = true
	main.set_paused(true)
	await frames(2)
	check(not main.pause_menu.items.any(func(i): return i["id"] == "survey"), "no survey in a release build")
	main.set_paused(false)


func test_title_welcomes_once_then_offers_after_play() -> void:
	Diag.scripted = false  # the title only shows notices outside scripted runs
	var title := await goto(TITLE)
	var notes := title.get_children().filter(func(c): return c is InkMenu and c != title.menu and c.visible)
	if check(notes.size() == 1, "a welcome note on the first visit"):
		check_eq(notes[0].title, Survey.settings()["welcome_title"], "it's the welcome")
		check(notes[0].subtitle.contains(Survey.ai_short()), "with the AI statement")
		check(not title.menu.visible, "over the menu")
		notes[0].chosen.emit("ok")
		await frames(2)
		check(title.menu.visible, "OK brings the menu back")
	check(Survey.welcomed(), "welcomed is remembered")
	title = await goto(TITLE)
	notes = title.get_children().filter(func(c): return c is InkMenu and c != title.menu and c.visible)
	check(notes.is_empty(), "no note on the next visit before enough play")
	Empire.playtime = 40 * 60.0
	title = await goto(TITLE)
	notes = title.get_children().filter(func(c): return c is InkMenu and c != title.menu and c.visible)
	if check(notes.size() == 1, "after enough play the title asks for the survey"):
		notes[0].chosen.emit("survey")
		var v := await _wait_view()
		check(v != null, "Take the survey opens it")
		await _close(v)
	title = await goto(TITLE)
	notes = title.get_children().filter(func(c): return c is InkMenu and c != title.menu and c.visible)
	check(notes.is_empty(), "not asked again straight away")
