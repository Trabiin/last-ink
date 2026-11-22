extends "res://tests/test_case.gd"
## Crash reports and feedback (issue #146): session logs rotate and carry the context, the next launch
## notices a crash or errors (and ignores shutdown noise), the title offers a report once and can be
## told to stop until the next version, reports hold only what the player chose, zip up, and reach a
## (local, fake) endpoint, the form opens from the title and every pause menu and never sends on its
## own, and none of this depends on the test shortcuts a release build leaves out.

const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"
const TITLE := "res://scenes/title.tscn"
const LOGS := "user://test_run/logs/"

var Empire: Node
var Saves: Node
var Diag: Node
var _dir_was := ""
var _prev_was := {}


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	Diag = autoload("Diag")
	runner.clear_scratch()
	Saves.pending = {}
	Saves.current_slot = ""
	Empire.reset()
	_dir_was = Diag.dir
	_prev_was = Diag.previous
	Diag.dir = LOGS
	_wipe(LOGS)
	Diag.previous = {}
	Feedback.override = {}
	for t in Help.topics():
		Help.mark(t["id"])
	Access.load_settings()
	Access.first_boot_done = true  # these tests drive the title as a returning player (the first-start page is test_access)


func after_each() -> void:
	Diag.dir = _dir_was
	Diag.previous = _prev_was
	Diag.scripted = true
	Feedback.override = {}
	tree.paused = false


func _wipe(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _view() -> FeedbackView:
	var found := tree.root.find_children("*", "FeedbackView", true, false)
	return found[0] if not found.is_empty() else null


func _wait_view(limit := 30) -> FeedbackView:
	for i in limit:
		await tree.process_frame
		var v := _view()
		if v and v.visible:
			return v
	return null


func test_logs_count_errors_but_not_shutdown_noise() -> void:
	var text := "\n".join([
		"Godot Engine v4.3",
		"[last-ink] scene res://scenes/hub.tscn",
		"SCRIPT ERROR: Invalid access to property 'hp' on a base object of type 'Nil'.",
		"   at: Hero._physics_process (res://scripts/hero.gd:120)",
		"USER WARNING: Could not write save",
		"ERROR: Condition \"!is_inside_tree()\" is true.",
		"WARNING: ObjectDB instances leaked at exit (run with --verbose for details).",
		"[last-ink] exit",
		"ERROR: 12 RID allocations of type 'Texture' were leaked at exit.",
		"ERROR: Something during shutdown",
	])
	var c: Dictionary = Diag.count_problems(text)
	check_eq(c["errors"], 2, "two errors before the clean exit")
	check_eq(c["warnings"], 1, "one warning (the leak is noise)")
	check(str(c["samples"][0]).begins_with("SCRIPT ERROR"), "the first error is kept as a sample")
	check_eq(Diag.count_problems("all fine\n")["errors"], 0, "a clean log has no errors")


## The web build reads errors from the browser console, where Godot prints one engine error as two or
## more lines (the message, then "at: ..."). One error must count once, now and in logs written before.
func test_one_browser_error_counts_once() -> void:
	var got: Dictionary = Diag.console_lines([
		["error", "USER ERROR: Something broke"],
		["error", "   at: push_error (core/variant/variant_utility.cpp:1092)"],
		["error", "Uncaught TypeError: x is undefined"],
		["warn", "WARNING: Careful"],
		["warn", "   at: push_warning (core/variant/variant_utility.cpp:1112)"],
	])
	check_eq(got["errors"], 2, "two errors, not four")
	check_eq(got["warnings"], 1, "one warning")
	check_eq(got["lines"][1], "   at: push_error (core/variant/variant_utility.cpp:1092)", "the location stays, under its error")
	check_eq(got["lines"][2], "ERROR: Uncaught TypeError: x is undefined", "untagged browser errors are tagged")
	var old_log := "USER ERROR: Something broke\nERROR:    at: push_error (core/variant/variant_utility.cpp:1092)\n"
	check_eq(Diag.count_problems(old_log)["errors"], 1, "logs written by the old counter count the error once too")


func test_sessions_rotate_and_a_crash_is_noticed() -> void:
	# A clean first session.
	Diag.start_session()
	check(FileAccess.file_exists(LOGS + "session.log"), "session.log written")
	var log := FileAccess.get_file_as_string(LOGS + "session.log")
	for key in ["game_version: " + Saves.game_version(), "os: ", "gpu: ", "cpu: ", "renderer: "]:
		check(log.contains(key), "header has " + key)
	Diag.breadcrumb("mission meadow_patrol")
	check(FileAccess.get_file_as_string(LOGS + "session.log").contains("] mission meadow_patrol"), "breadcrumbs are appended")
	check(FileAccess.file_exists(LOGS + "session.lock"), "the session is marked as running")
	# It never exited cleanly: the next start calls it a crash and keeps its log.
	Diag.start_session()
	check(Diag.previous.get("crashed", false), "a session that never reached a clean exit counts as a crash")
	check(FileAccess.get_file_as_string(LOGS + "session.1.log").contains("mission meadow_patrol"), "last session's log kept as session.1.log")
	# A clean exit (what _exit_tree does) is not a crash; errors in the old log are counted.
	_write(LOGS + "session.log", "[10:00 +1s day 2] scene x\nERROR: a browser error\nWARNING: a browser warning\n")
	DirAccess.remove_absolute(LOGS + "session.lock")
	Diag.start_session()
	check(not Diag.previous.get("crashed", true), "a clean exit is not a crash")
	check_eq(Diag.previous.get("errors", 0), 1, "the error in the last session's log is counted")
	check_eq(Diag.previous.get("warnings", 0), 1, "and the warning")
	# Only KEEP session logs stay.
	for i in 8:
		Diag.start_session()
	var logs := Array(DirAccess.get_files_at(LOGS)).filter(func(f): return f.begins_with("session") and f.ends_with(".log"))
	check_eq(logs.size(), Diag.KEEP, "only the last %d session logs are kept" % Diag.KEEP)


func test_offer_needs_trouble_and_can_be_muted_until_the_next_version() -> void:
	Diag.scripted = false
	Diag.previous = {}
	check(not Diag.should_offer_report(), "no earlier session: nothing to offer")
	Diag.previous = {"crashed": false, "errors": 0, "warnings": 3, "samples": [], "logs": []}
	check(not Diag.should_offer_report(), "warnings alone are not worth a prompt")
	Diag.previous["errors"] = 2
	check(Diag.should_offer_report(), "errors last time: offer a report")
	Diag.previous = {"crashed": true, "errors": 0, "warnings": 0, "samples": [], "logs": []}
	check(Diag.should_offer_report(), "a crash last time: offer a report")
	Diag.mute()
	check(not Diag.should_offer_report(), "muted for this version")
	var cfg := ConfigFile.new()
	cfg.load(LOGS + "diag.cfg")
	cfg.set_value("notice", "muted_version", "0.0.1")
	cfg.save(LOGS + "diag.cfg")
	check(Diag.should_offer_report(), "a new version asks again")
	Diag.scripted = true
	check(not Diag.should_offer_report(), "never during test runs")


func test_title_offers_a_report_once_after_a_crash() -> void:
	Diag.scripted = false
	Diag.previous = {"crashed": true, "errors": 1, "warnings": 0, "samples": ["SCRIPT ERROR: boom"], "logs": []}
	var title := await goto(TITLE)
	var offers := title.get_children().filter(func(c): return c is InkMenu and c.visible and c.title == "Sorry about that")
	if not check_eq(offers.size(), 1, "the title offers a report"):
		return
	var offer: InkMenu = offers[0]
	check(not title.menu.visible, "the main menu waits")
	check(Diag.previous.is_empty(), "asked once per launch")
	check(offer.items.map(func(i): return i["id"]) == ["send", "logs", "later", "mute"], "send, logs, not now, don't ask again")
	check(offer.subtitle.contains("boom"), "the offer quotes the first error, so a player can tell us what broke")
	offer.chosen.emit("send")
	var v := await _wait_view()
	if not check(v != null, "Send report opens the form"):
		return
	check(v._about_previous(), "the form is about last time")
	check(v.text_box.placeholder_text != "", "with a hint of what to write")
	check(v.shot == null, "no screenshot of the title screen")
	var r := v.current_report()
	check_eq(r["previous_session"].get("crashed", false), true, "the report says the last session crashed")
	v._on_cancel()
	await frames(3)
	check(title.menu.visible, "back to the title menu")
	# Next time the title is shown in the same launch, no offer.
	title = await goto(TITLE)
	check(title.get_children().filter(func(c): return c is InkMenu and c.visible and c.title == "Sorry about that").is_empty(), "not asked twice")


func test_reports_hold_only_what_the_player_chose() -> void:
	Saves.save("2", {"scene": HUB})
	check_eq(Saves.current_slot, "2", "saving remembers the slot")
	Diag.start_session()
	Diag.breadcrumb("scene res://scenes/hub.tscn")
	var img := Image.create(1600, 900, false, Image.FORMAT_RGBA8)
	img.fill(Color.DARK_SLATE_BLUE)
	var bare := Feedback.build({"kind": "bug", "text": "  The lamp-lighter walks through walls.  "})
	check_eq(bare["text"], "The lamp-lighter walks through walls.", "text trimmed")
	check(bare["attachments"].is_empty(), "nothing attached unless ticked")
	check(bare["id"].begins_with("LI-") and bare["id"].length() == 11, "a report number to quote")
	for key in ["game_version", "os", "gpu", "locale"]:
		check(bare["system"].has(key), "system info has " + key)
	for key in ["scene", "mission", "save_slot", "day"]:
		check(bare["context"].has(key), "context has " + key)
	check_eq(bare["context"]["save_slot"], "2", "context names the save slot")
	check(not JSON.stringify(bare).contains(OS.get_environment("USER")) or OS.get_environment("USER") == "", "no user name")
	var full := Feedback.build({"kind": "rant", "text": "x".repeat(Feedback.MAX_TEXT + 50), "contact": "me@example.com",
		"logs": true, "save": true, "screenshot": img})
	check_eq(full["kind"], "bug", "unknown kinds become bug")
	check_eq(full["text"].length(), Feedback.MAX_TEXT, "text capped")
	var att: Dictionary = full["attachments"]
	check(att.has("session.log") and str(att["session.log"]["data"]).contains("scene res://scenes/hub.tscn"), "the session log is attached")
	check(att.has("save_2.json") and str(att["save_2.json"]["data"]).contains("\"scene\""), "the save in use is attached")
	check(att.has("screenshot.png"), "the screenshot is attached")
	var png := Image.new()
	png.load_png_from_buffer(Marshalls.base64_to_raw(att["screenshot.png"]["base64"]))
	check(png.get_width() <= 1280, "big screenshots are halved (%d wide)" % png.get_width())
	check(not JSON.stringify(full).contains("game_key"), "the report itself has no key")
	check(Feedback.to_json(full).contains("\"game_key\""), "the body sent has the key")
	# The zip: summary, metadata and each file.
	var path := Feedback.save_zip(full)
	check(FileAccess.file_exists(path), "Save to file writes a zip")
	var zip := ZIPReader.new()
	if check_eq(zip.open(path), OK, "the zip opens"):
		var names := Array(zip.get_files())
		for n in ["report.txt", "report.json", "session.log", "save_2.json", "screenshot.png"]:
			check(n in names, "zip has " + n)
		check(zip.read_file("report.txt").get_string_from_utf8().contains("Contact: me@example.com"), "summary has the contact")
		check(not zip.read_file("report.json").get_string_from_utf8().contains("\"attachments\""), "metadata without the files")
		zip.close()
	DirAccess.remove_absolute(path)


## A tiny HTTP server for one request: answers `reply` with `code` and returns what it got.
func _serve(server: TCPServer, code: int, reply: String) -> Dictionary:
	var peer: StreamPeerTCP
	for i in 600:
		await tree.process_frame
		if server.is_connection_available():
			peer = server.take_connection()
			break
	if peer == null:
		return {}
	var got := PackedByteArray()
	var want := -1
	for i in 600:
		await tree.process_frame
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			got.append_array(peer.get_data(n)[1])
		var text := got.get_string_from_utf8()
		var head_end := text.find("\r\n\r\n")
		if head_end >= 0 and want < 0:
			var m := RegEx.create_from_string("(?i)content-length:\\s*(\\d+)").search(text)
			want = head_end + 4 + (int(m.get_string(1)) if m else 0)
		if want >= 0 and got.size() >= want:
			break
	var head := got.get_string_from_utf8()
	var body := head.substr(head.find("\r\n\r\n") + 4)
	var status := "200 OK" if code == 200 else "%d Error" % code
	peer.put_data(("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status, reply.to_utf8_buffer().size(), reply]).to_utf8_buffer())
	for i in 10:
		await tree.process_frame
	peer.disconnect_from_host()
	return {"head": head.left(head.find("\r\n\r\n")), "body": body}


func test_send_posts_the_report_and_says_how_it_went() -> void:
	var server := TCPServer.new()
	var port := 0
	for p in range(28461, 28481):
		if server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if not check(port > 0, "a local port for the fake endpoint"):
		return
	Feedback.override = {"endpoint": "http://127.0.0.1:%d/report" % port, "timeout": 10}
	Diag.start_session()
	check(Feedback.can_send(), "an endpoint makes the form able to send")
	var report := Feedback.build({"kind": "idea", "text": "A photo mode!", "logs": true})
	var done := {}
	var send_it := func():
		done["res"] = await Feedback.send(tree.root, report)
	send_it.call()
	var got := await _serve(server, 200, JSON.stringify({"ok": true, "id": report["id"]}))
	for i in 120:
		if done.has("res"):
			break
		await tree.process_frame
	check(str(got.get("head", "")).begins_with("POST /report"), "POSTs to the endpoint")
	var body = JSON.parse_string(str(got.get("body", "")))
	if check(typeof(body) == TYPE_DICTIONARY, "a JSON body"):
		check_eq(body["text"], "A photo mode!", "the text arrives")
		check_eq(body["game_key"], Feedback.config()["game_key"], "with the game key")
		check(body["attachments"].has("session.log"), "and the log")
	check(done.get("res", {}).get("ok", false), "success is reported: %s" % str(done.get("res")))
	# A refusal is reported as a failure, with the reason.
	done.clear()
	send_it.call()
	await _serve(server, 429, JSON.stringify({"ok": false, "error": "slow down"}))
	for i in 120:
		if done.has("res"):
			break
		await tree.process_frame
	check(not done.get("res", {"ok": true})["ok"] and str(done["res"]["error"]).contains("slow down"), "a refusal says why: %s" % str(done.get("res")))
	server.stop()
	Feedback.override = {"endpoint": ""}
	check(not Feedback.can_send(), "no endpoint: the form only saves to a file")
	check_eq((await Feedback.send(tree.root, report))["ok"], false, "and send does nothing")


## The whole way a player goes: the town pause menu, the form, typing, Send, and the thank-you, against a
## local fake inbox.
func test_send_from_the_form_in_town() -> void:
	var server := TCPServer.new()
	var port := 0
	for p in range(28481, 28501):
		if server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	if not check(port > 0, "a local port for the fake endpoint"):
		return
	Feedback.override = {"endpoint": "http://127.0.0.1:%d/report" % port, "timeout": 10}
	Diag.start_session()
	Empire.reset()
	var hub := await goto(HUB, 20)
	hub.open_menu()
	await frames(2)
	hub._on_menu("report")
	var v := await _wait_view()
	if not check(v != null, "the form opens in town"):
		server.stop()
		return
	check(v.send_button.visible and not v.send_button.disabled, "Send is offered when the inbox is set up")
	v._on_send()
	await frames(2)
	check(v.status.text != "" and not v.sending, "Send with nothing typed asks for a line first")
	v.text_box.text = "The lamp-lighter walks through the Guildhall wall."
	v._set_kind("bug")
	v._on_send()
	check(v.sending, "sending")
	var got := await _serve(server, 200, JSON.stringify({"ok": true, "id": v.report_id}))
	for i in 120:
		if v.sent or not v.sending:
			break
		await tree.process_frame
	var body = JSON.parse_string(str(got.get("body", "")))
	if check(typeof(body) == TYPE_DICTIONARY, "the form posted a report"):
		check_eq(body["text"], "The lamp-lighter walks through the Guildhall wall.", "with what was typed")
		check_eq(body["context"]["scene"], HUB, "and where the player was")
		check(body["attachments"].has("session.log"), "and the log")
	check(v.sent, "the form says it was sent")
	check(v.status.text.contains(v.report_id), "and gives the report number")
	check_eq(v.send_button.text, tr("Close"), "Send turns into Close")
	v._on_send()  # Close
	await frames(3)
	check(hub.menu.visible, "back to the town menu")
	hub._close_menu()
	server.stop()


func test_form_from_the_title_and_every_pause_menu() -> void:
	# Title.
	var title := await goto(TITLE)
	check(title.menu.items.any(func(i): return i["id"] == "report"), "Report a bug on the title menu")
	title._on_choice("report")
	var v := await _wait_view()
	if check(v != null, "the form opens from the title"):
		check(not v.send_button.visible or Feedback.can_send(), "no Send button without an endpoint")
		v.text_box.text = "typed something"
		v._on_cancel()
		await frames(2)
		check(v.visible, "Back with text typed asks first")
		v._on_cancel()
		await frames(3)
	check(title.menu.visible, "the title menu comes back")
	# Town.
	Empire.reset()
	var hub := await goto(HUB, 20)
	hub.open_menu()
	await frames(2)
	check(hub.menu.items.any(func(i): return i["id"] == "report"), "Report a bug in the town menu")
	hub._on_menu("report")
	v = await _wait_view()
	if check(v != null, "the form opens in town"):
		check(tree.paused, "the game stays paused under it")
		v._on_cancel()
		await frames(3)
	check(hub.menu.visible, "back to the town menu")
	hub._close_menu()
	# Command Table.
	var cmd := await goto(COMMAND, 20)
	cmd._open_menu()
	await frames(2)
	check(cmd.menu.items.any(func(i): return i["id"] == "report"), "Report a bug in the Command menu")
	cmd._on_menu("report")
	v = await _wait_view()
	if check(v != null, "the form opens at the table"):
		v._on_cancel()
		await frames(3)
	check(cmd.menu.visible, "back to the Command menu")
	cmd._close_menu()
	# Mission.
	Empire.reset()
	Missions.launch(Missions.find("meadow_patrol"))
	var main := await wait_scene(MAIN)
	if main == null:
		return
	await frames(10)
	main.set_paused(true)
	await frames(2)
	check(main.pause_menu.items.any(func(i): return i["id"] == "report"), "Report a bug in the mission pause menu")
	main._on_pause_choice("report")
	v = await _wait_view()
	if check(v != null, "the form opens mid-mission"):
		v._set_kind("feedback")
		v.text_box.text = "The moths are great."
		var r := v.current_report()
		check_eq(r["kind"], "feedback", "the picked kind")
		check_eq(r["context"]["mission"], "meadow_patrol", "the report knows the mission")
		v._on_save_file()
		check(v.saved_path != "" and FileAccess.file_exists(v.saved_path), "Save to file writes the zip")
		DirAccess.remove_absolute(v.saved_path)
		v._on_cancel()  # saved: no second ask
		await frames(3)
		check(not is_instance_valid(v) or not v.visible, "closes after saving without asking again")
	check(main.pause_menu.visible, "back to the pause menu")
	main.set_paused(false)


func test_screenshot_key_and_release_builds() -> void:
	check(InputMap.has_action("screenshot"), "a screenshot action")
	var keys := InputMap.action_get_events("screenshot").filter(func(e): return e is InputEventKey and e.physical_keycode == KEY_F12)
	check(not keys.is_empty(), "on F12")
	var path: String = await Diag.take_screenshot()
	check(path == "" or FileAccess.file_exists(path), "a screenshot is saved where there is a screen (headless: none, no error)")
	# Logging, the offer and the form never look at the test_shortcuts feature a release build drops.
	for f in ["res://scripts/diag.gd", "res://scripts/feedback.gd", "res://scripts/feedback_view.gd"]:
		check(not FileAccess.get_file_as_string(f).contains("test_shortcuts_on"), f.get_file() + " works the same in release builds")
	var title_src := FileAccess.get_file_as_string("res://scripts/title.gd")
	check(title_src.find("\"error_test\"") > title_src.find("if test_shortcuts_on():"), "the test error shortcut is only in the test shortcuts menu")
