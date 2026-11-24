extends "res://tests/test_case.gd"
## Steam (issue #150, docs/STEAM.md): the achievement list, how each kind unlocks, the per-player file,
## Rich Presence, the overlay pause, and the Steamworks files kept in sync. Steam itself is a fake
## singleton here (FakeSteam), the same way the game would see GodotSteam.

const TITLE := "res://scenes/title.tscn"
const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const SteamFiles := preload("res://tools/steam_files.gd")
const CHECKS := ["bond_rank", "all_bonds_bound", "romance", "truce", "personal_done", "all_personal_done", "roster",
	"everyone_recruited", "held", "all_provinces", "top_building", "all_buildings", "all_research", "allied",
	"max_level", "hungry", "betrayal_settled"]
const EVENTS := ["reclaimed", "surge_broken", "boss_flawless", "boss_hard", "wiped"]
const COUNTERS := ["kills", "retreats", "expeditions_won"]


## Answers what GodotSteam answers, and remembers what it was told.
class FakeSteam:
	extends RefCounted
	signal overlay_toggled(active: bool, user_initiated: bool, app_id: int)
	var achieved := {}
	var stored := 0
	var presence := {}
	var callbacks := 0
	var progress: Array = []

	func run_callbacks() -> void:
		callbacks += 1

	func setAchievement(n: String) -> bool:
		achieved[n] = true
		return true

	func getAchievement(n: String) -> Dictionary:
		return {"ret": true, "achieved": achieved.has(n)}

	func storeStats() -> bool:
		stored += 1
		return true

	func indicateAchievementProgress(n: String, cur: int, mx: int) -> bool:
		progress.append([n, cur, mx])
		return true

	func setRichPresence(k: String, v: String) -> bool:
		presence[k] = v
		return true

	func clearRichPresence() -> void:
		presence = {}


var ach: Node
var link: Node
var _difficulty := 1


func before_each() -> void:
	ach = autoload("Achievements")
	link = autoload("SteamLink")
	_difficulty = Settings.difficulty
	autoload("Saves").pending = {}
	autoload("Empire").reset()
	ach.clear_all()


func after_each() -> void:
	link.use_api(null)
	link.stop()
	Settings.difficulty = _difficulty
	tree.paused = false
	ach.clear_all()


func _story_on() -> void:
	Story.begin()


# ---------------------------------------------------------------- the list

func test_list_is_well_formed() -> void:
	var ids := {}
	check(ach.list.size() >= 30 and ach.list.size() <= 45, "30 to 45 achievements, as issue #150 plans (%d)" % ach.list.size())
	var groups: Array = ach.groups.map(func(g): return str(g["id"]))
	var top: int = ach.top_bond_rank()
	for a in ach.list:
		var id := str(a.get("id", ""))
		check(RegEx.create_from_string("^ACH_[A-Z0-9_]+$").search(id) != null, "%s: Steam API names are ACH_ and capitals" % id)
		check(not ids.has(id), "%s is listed twice" % id)
		ids[id] = true
		check(str(a.get("name", "")) != "" and str(a.get("desc", "")) != "", "%s has a name and a description" % id)
		check(str(a.get("name", "")).length() <= 40, "%s: name fits Steam's pop-up" % id)
		check(str(a.get("group", "")) in groups, "%s: group is one of the groups" % id)
		var ways := ["when", "check", "event", "counter"].filter(func(k): return a.has(k))
		if a.get("later", false):
			check(ways.is_empty(), "%s waits for later content, so it has no trigger yet" % id)
			continue
		check(ways.size() == 1, "%s unlocks exactly one way (has %s)" % [id, ways])
		if a.has("check"):
			check(str(a["check"]) in CHECKS, "%s: known check %s" % [id, a["check"]])
			if str(a["check"]) == "bond_rank":
				check(int(a["min"]) <= top, "%s: bond rank %d exists" % [id, int(a["min"])])
		if a.has("event"):
			check(str(a["event"]) in EVENTS, "%s: an event the game reports" % id)
		if a.has("counter"):
			check(str(a["counter"]) in COUNTERS and int(a.get("min", 0)) > 1, "%s: a counter the game keeps, with a goal" % id)
		var w: Dictionary = a.get("when", {})
		for m in w.get("cleared", []):
			check(not Missions.find(str(m)).is_empty(), "%s: mission %s exists" % [id, m])
		for r in w.get("joined", []):
			check(not autoload("Empire").recruit(str(r)).is_empty(), "%s: recruit %s exists" % [id, r])


func test_every_named_check_answers() -> void:
	_story_on()
	for c in CHECKS:
		ach._check(c, 1)  # no "no check called" warning, no script error
	check(true, "checks ran")


func test_betrayal_check_matches_missions() -> void:
	var found := Missions.all().filter(func(m): return str(m["id"]).begins_with("betrayal_"))
	check(not found.is_empty(), "the betrayal missions ACH_BETRAYAL watches exist")


# ---------------------------------------------------------------- unlocking

func test_story_condition_unlocks_once_and_is_kept() -> void:
	_story_on()
	var empire := autoload("Empire")
	check(not "ACH_PROLOGUE" in ach.check_all(), "nothing before the prologue is cleared")
	empire.missions_cleared.append("meadow_prologue")
	check_eq(ach.check_all(), ["ACH_PROLOGUE"], "clearing the prologue unlocks it")
	check(ach.check_all().is_empty(), "and only once")
	ach.load_file()
	check(ach.is_unlocked("ACH_PROLOGUE"), "kept in the achievements file")
	check_eq(ach.path, ach.TEST_FILE, "tests write to the scratch file")


func test_only_a_story_campaign_counts() -> void:
	var empire := autoload("Empire")
	empire.missions_cleared.append("meadow_prologue")
	check(not ach.playing(), "a test-shortcut town (story off) is not play that counts")
	check(ach.event("wiped").is_empty(), "events don't count without the story")
	ach.count("retreats", 9)
	check_eq(int(ach.counters.get("retreats", 0)), 0, "nor do counters")


func test_later_achievements_never_unlock() -> void:
	_story_on()
	check(not ach.unlock("ACH_ENDING"), "the ending isn't in the game yet")
	check(not ach.is_unlocked("ACH_ENDING"), "still locked")


func test_mission_results() -> void:
	_story_on()
	var boss := {"id": "auditor_duel", "objective": {"kind": "boss"}}
	ach.mission_done({"outcome": "success", "mission_dict": boss, "kills": 3, "downs": 1})
	check(not ach.is_unlocked("ACH_FLAWLESS_BOSS"), "someone went down: not flawless")
	ach.mission_done({"outcome": "success", "mission_dict": boss, "kills": 3, "downs": 0, "skipped": true})
	check(not ach.is_unlocked("ACH_FLAWLESS_BOSS"), "a skipped fight doesn't count")
	ach.mission_done({"outcome": "success", "mission_dict": boss, "kills": 3, "downs": 0})
	check(ach.is_unlocked("ACH_FLAWLESS_BOSS"), "a boss with nobody down")
	check(not ach.is_unlocked("ACH_HARD_BOSS"), "not on Hard")
	Settings.difficulty = 2
	ach._mission_low = 2
	ach.mission_done({"outcome": "success", "mission_dict": boss, "kills": 1})
	check(ach.is_unlocked("ACH_HARD_BOSS"), "a boss on Hard")
	ach.mission_done({"outcome": "success", "mission_dict": {"id": "x", "type": "reclaim"}})
	check(ach.is_unlocked("ACH_RECLAIM"), "a Reclaim mission won")
	ach.mission_done({"outcome": "success", "mission_dict": {"id": "x", "type": "defense"}})
	check(ach.is_unlocked("ACH_SURGE_HELD"), "a Defense mission won")
	ach.mission_done({"outcome": "wiped", "mission_dict": {"id": "x"}})
	check(ach.is_unlocked("ACH_WIPED"), "the party wiped")
	for i in 4:
		ach.mission_done({"outcome": "retreat", "mission_dict": {"id": "x"}})
	check(not ach.is_unlocked("ACH_RETREATS"), "4 retreats isn't 5")
	ach.mission_done({"outcome": "retreat", "mission_dict": {"id": "x"}})
	check(ach.is_unlocked("ACH_RETREATS"), "5 retreats")
	check_eq(int(ach.counters["kills"]), 10, "kills add up across missions")


func test_hard_needs_the_whole_mission_on_hard() -> void:
	_story_on()
	Settings.difficulty = 2
	ach._mission_low = 1  # turned down to Normal for a bit
	ach.mission_done({"outcome": "success", "mission_dict": {"id": "b", "objective": {"kind": "boss"}}, "downs": 1})
	check(not ach.is_unlocked("ACH_HARD_BOSS"), "lowered mid-fight: no Hard achievement")


func test_lowest_difficulty_is_kept_per_save() -> void:
	var empire := autoload("Empire")
	Settings.difficulty = 2
	empire.reset()
	check_eq(int(empire.feats["lowest_difficulty"]), 2, "a new game on Hard")
	Settings.difficulty = 1
	ach.note_difficulty()
	Settings.difficulty = 2
	ach.note_difficulty()
	check_eq(int(empire.feats["lowest_difficulty"]), 1, "turning it down once is remembered")
	var d: Dictionary = empire.to_dict()
	empire.reset()
	empire.from_dict(d)
	check_eq(int(empire.feats["lowest_difficulty"]), 1, "saved and loaded with the game")
	d.erase("feats")
	empire.from_dict(d)
	check(int(empire.feats["lowest_difficulty"]) <= 1, "an older save can't claim it was all on Hard")


func test_expeditions_count() -> void:
	_story_on()
	var empire := autoload("Empire")
	for i in 24:
		empire.expedition_returned.emit({"outcome": "success" if i % 2 == 0 else "great"})
	empire.expedition_returned.emit({"outcome": "fail"})
	check(not ach.is_unlocked("ACH_EXPEDITIONS"), "24 good ones and a failure")
	empire.expedition_returned.emit({"outcome": "success"})
	check(ach.is_unlocked("ACH_EXPEDITIONS"), "25 successful expeditions")


func test_checks_against_the_empire() -> void:
	_story_on()
	var empire := autoload("Empire")
	empire.hungry = true
	for p in empire.territory().provinces.slice(0, 10):
		p["owner"] = "you"
	ach.check_all()
	check(ach.is_unlocked("ACH_HUNGRY"), "Supplies ran out")
	check(ach.is_unlocked("ACH_FIRST_CLAIM") and ach.is_unlocked("ACH_HOLD_10"), "10 provinces held")
	check(not ach.is_unlocked("ACH_EVERY_PAGE"), "not every province")


# ---------------------------------------------------------------- Steam

func test_without_steam_everything_is_quiet() -> void:
	check(not link.active, "no GodotSteam in the test run, so Steam is off")
	check(link.status != "", "and says why: %s" % link.status)
	check(link.api() == null, "no singleton")
	check(not link.unlock("ACH_PROLOGUE"), "unlock is a no-op")
	link.set_presence("menu", {})  # no error
	_story_on()
	check(ach.unlock("ACH_PROLOGUE"), "achievements still unlock in the game's own list")


func test_unlocks_reach_steam_and_sync_both_ways() -> void:
	_story_on()
	ach.unlock("ACH_PROLOGUE")  # earned before Steam started
	var fake := FakeSteam.new()
	fake.achieved["ACH_BREAKOUT"] = true  # earned on another machine
	link.use_api(fake)
	check(link.active, "the fake counts as Steam")
	check(fake.achieved.has("ACH_PROLOGUE"), "ours went up to Steam on start")
	check(ach.is_unlocked("ACH_BREAKOUT"), "Steam's came down to us")
	ach.unlock("ACH_TITHE_COLUMN")
	check(fake.achieved.has("ACH_TITHE_COLUMN") and fake.stored > 0, "a new unlock is set and stored at once")
	ach.count("kills", 300)
	check(not fake.progress.is_empty() and fake.progress[-1][0] == "ACH_ERASED_1000", "Steam's progress pop-up for counters")
	await frames(2)
	check(fake.callbacks > 0, "callbacks run every frame")


func test_rich_presence() -> void:
	var fake := FakeSteam.new()
	await goto(TITLE)
	link.use_api(fake)
	link.update_presence()
	check_eq(fake.presence.get("steam_display", ""), "#Status_menu", "the title screen is 'in the menus'")
	autoload("Empire").reset()
	_story_on()
	autoload("Empire").missions_cleared.append_array(["meadow_prologue", "ch1_breakout"])
	await goto(COMMAND)
	link.update_presence()
	check_eq(fake.presence.get("steam_display", ""), "#Status_command", "at the Command Table")
	check_eq(fake.presence.get("chapter", ""), "act1", "in Act 1")
	check_eq(fake.presence.get("status", ""), "Act 1: at the Command Table", "and the plain line says so")
	var a: Array = ["mission", {"chapter": "ch2", "place": "Candleford"}]
	link.set_presence(a[0], a[1])
	check_eq(link.presence_text(a[0], a[1]), "Chapter 2: Candleford", "a mission names the place")


func test_overlay_pauses_and_unpauses() -> void:
	var fake := FakeSteam.new()
	await goto(HUB)
	link.use_api(fake)
	tree.paused = false
	fake.overlay_toggled.emit(true, true, 0)
	check(tree.paused, "the overlay pauses the game")
	fake.overlay_toggled.emit(false, true, 0)
	check(not tree.paused, "closing it unpauses")


func test_presence_has_every_chapter() -> void:
	var known: Dictionary = link.presence_chapters()
	for c in Journal.chapters():
		check(known.has(str(c["id"])), "Rich Presence knows chapter %s" % c["id"])


func test_steamworks_files_are_up_to_date() -> void:
	check_eq(FileAccess.get_file_as_string(SteamFiles.VDF), link.presence_vdf(),
		"steam/rich_presence_english.vdf matches data/steam.json (run tools/steam_files.gd)")
	check_eq(FileAccess.get_file_as_string(SteamFiles.TABLE), SteamFiles.table(ach.list, ach.groups),
		"steam/achievements.md matches data/achievements.json (run tools/steam_files.gd)")


func test_title_page() -> void:
	_story_on()
	ach.unlock("ACH_PROLOGUE")
	ach.count("kills", 12)
	var t := await goto(TITLE)
	var item = t.menu.items.filter(func(i): return i["id"] == "achievements")
	check(not item.is_empty(), "the title menu lists Achievements")
	t._on_choice("achievements")
	await frames(3)
	var views := t.find_children("*", "AchievementsView", true, false)
	check_eq(views.size(), 1, "it opens the Achievements screen")
	if views.is_empty():
		return
	var v: AchievementsView = views[0]
	check_eq(v._rows.size(), ach.list.size(), "All lists every achievement")
	v._set_tab(1)
	check(v._rows.all(func(a): return a["group"] == "story"), "a group tab lists that group")
	v._set_tab(0)
	for i in v._rows.size():  # walk to the bottom: every row draws, scrolling follows
		v.sel = i
		await frames(1)
	check(not v._row_rects.is_empty() and int(v._row_rects[-1][1]) == v._rows.size() - 1, "the last row scrolls into view")
	check_eq(ach.progress_of(ach.info("ACH_ERASED_1000")), [12, 1000], "counters show how far they've got")
	v.close()
	await frames(2)
	check(t.menu.visible, "closing goes back to the title menu")


## The Steam build's smoke test (.github/workflows/steam.yml) sets LASTINK_EXPECT_GODOTSTEAM=1: there the
## real extension must have loaded, and with no app id yet Steam must stay off without a fuss.
func test_steam_build_has_godotsteam() -> void:
	if OS.get_environment("LASTINK_EXPECT_GODOTSTEAM") != "1":
		check(not Engine.has_singleton("Steam") or link.status != "", "not a Steam build run")
		return
	check(Engine.has_singleton("Steam"), "GodotSteam loaded in the Steam build")
	check(not link.start(), "Steam doesn't start without an app id")
	check(link.status.begins_with("no Steam app id") or link.status.begins_with("Steam didn't start"),
		"no app id and no client: Steam stays off (%s)" % link.status)


func test_deck_answer_matches_the_display_settings() -> void:
	DisplaySettings._deck_override = 1
	check(link.on_deck(), "without Steam, SteamLink asks DisplaySettings.on_deck() (issue #149)")
	DisplaySettings._deck_override = 0
	check(not link.on_deck(), "and agrees when it says no")
	DisplaySettings._deck_override = -1
