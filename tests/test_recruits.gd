extends "res://tests/test_case.gd"
## The light recruit pool for Chapters 2 and 3 (issue #27): everyone has what a recruit needs (trait, hook,
## lines, epilogue, tracked stand-in art, a voice note), later chapters' people stay off the Newcomers screen
## until their region opens, chapter rescues wait for their story gate, the Vowed and Salon-bred traits do
## what their cards say, and Hollowmark never stands two people on the same spot.

const HUB := "res://scenes/hub.tscn"
const CH2 := ["osyth", "cuthbert", "nell", "alcuin", "mildred", "joan", "rafe", "sib"]
const CH3 := ["anselme", "margot", "gaspard", "ida", "clement", "josette", "firmin", "remy"]
const NEW := ["mildred", "joan", "rafe", "sib", "ida", "clement", "josette", "firmin", "remy"]

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


func _json(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _join(id: String) -> void:
	Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}


func test_every_new_recruit_is_complete() -> void:
	var epi: Dictionary = _json("res://data/epilogues.json").get("cast", {})
	var ph := {}
	for e in _json("res://data/placeholders.json").get("placeholders", []):
		ph[e["id"]] = e
	var voices := FileAccess.get_file_as_string("res://docs/VOICES.md")
	var glossary := FileAccess.get_file_as_string("res://docs/GLOSSARY.md")
	for id in NEW:
		var r: Dictionary = Empire.recruit(id)
		if not check(not r.is_empty(), "%s is in recruits.json" % id):
			continue
		check_eq(r.get("tier", ""), "recruit", "%s is a light recruit" % id)
		check(not r.get("start", false), "%s is found, not on the starting roster" % id)
		check(r.get("traits", []).size() >= 1, "%s has a trait" % id)
		check(r.get("lines", []).size() >= 3, "%s has three town lines" % id)
		check(r.get("quips", []).size() >= 2, "%s has two expedition quips" % id)
		for k in ["blurb", "rumour", "welcome", "post"]:
			check(str(r.get(k, "")) != "", "%s has a %s" % [id, k])
		check(not Empire.join_hook(id).is_empty(), "%s has a join hook" % id)
		check(epi.has(id) and epi[id].size() >= 2, "%s has an epilogue and a 'lost' variant" % id)
		check(ph.has("sprite:" + id) and ph.has("portrait:" + id), "%s's stand-in art is tracked in placeholders.json" % id)
		check(voices.contains("(`%s`" % id), "%s has a row in docs/VOICES.md" % id)
		check(glossary.contains("| %s |" % id), "%s is in docs/GLOSSARY.md" % id)


## docs/NAMING.md 1.3.3: a name's first letter differs from everyone else met in the same chapter.
func test_first_letters_differ_within_a_chapter() -> void:
	for group in [CH2, CH3]:
		var seen := {}
		for id in group:
			var r: Dictionary = Empire.recruit(id)
			var name: String = str(r.get("short", r.get("name", id))).replace("Sister ", "").replace("Brother ", "")
			var c := name.left(1)
			check(not seen.has(c), "%s and %s start with the same letter" % [id, seen.get(c, "")])
			seen[c] = id


func test_later_chapters_are_not_rumoured_early() -> void:
	Story.begin()
	var leads: Array = Empire.lead_ids()
	for id in CH2 + CH3:
		check(not id in leads, "%s is not on the Newcomers screen before their chapter" % id)
	Empire.open_region("abbey", true)
	leads = Empire.lead_ids()
	for id in CH2:
		check(id in leads, "%s is rumoured once the Abbey's fog lifts" % id)
	for id in CH3:
		check(not id in leads, "%s still waits for the Causeway" % id)
	Empire.open_region("causeway", true)
	leads = Empire.lead_ids()
	for id in CH3:
		check(id in leads, "%s is rumoured once the Causeway opens" % id)


func test_a_met_hook_waits_for_the_region() -> void:
	Story.begin()
	Empire.buildings["inkworks"] = 2
	check(not Empire.hook_met("rafe"), "Rafe does not turn up in Act 1 just because the Inkworks is big")
	Empire._check_leads()
	check(not Empire.visitors.has("rafe"), "nobody at the gate yet")
	Empire.open_region("abbey", true)
	check(Empire.hook_met("rafe"), "once the Abbey is on the map, the Inkworks brings him")
	Empire._check_leads()
	check(Empire.visitors.has("rafe"), "Rafe waits at the gate")


func test_chapter_rescues_wait_for_their_story_gate() -> void:
	Story.begin()
	Empire.open_region("abbey", true)
	Empire.open_region("causeway", true)
	Empire.buildings["guildhall"] = 1
	check(not "rescue_joan" in Empire.job_ids(), "the wax-barge rescue is not on the board before the Wax Barges")
	check(Empire.job_blocker("rescue_joan") != "", "and says why: %s" % Empire.job_blocker("rescue_joan"))
	check(not "rescue_josette" in Empire.job_ids(), "the copyist rescue waits for the masquerade")
	Empire.missions_cleared.append("ch2_candleford")
	check("rescue_joan" in Empire.job_ids(), "after the Wax Barges the rescue is on the board")
	check(not Empire.job_story_open("rescue_josette"), "the Causeway rescue still waits")
	Empire.missions_cleared.append("ch3_masquerade")
	check("rescue_josette" in Empire.job_ids(), "after the masquerade the copyist rescue is on the board")
	check_eq(Empire.job("rescue_josette").get("recruit", ""), "josette", "and it brings Josette")


func test_vowed_and_salon_bred() -> void:
	var cuth: Dictionary = Empire.envoy_effect("cuthbert", "abbey")
	var nell: Dictionary = Empire.envoy_effect("nell", "abbey")
	check(cuth["why"].any(func(w): return str(w[0]).begins_with("Vowed")), "Vowed shows as a reason with the Abbey")
	var e: Dictionary = Empire.envoy_effect("cuthbert", "erasers")
	check(e["why"].any(func(w): return str(w[0]).begins_with("Vowed")), "and with the Erasers")
	check(not Empire.envoy_effect("cuthbert", "guild")["why"].any(func(w): return str(w[0]).begins_with("Vowed")), "but not with the Guild")
	check(not nell["why"].any(func(w): return str(w[0]).begins_with("Vowed")), "Nell took no vows")
	var vel: Dictionary = Empire.envoy_effect("clement", "velvet")
	check(vel["why"].any(func(w): return str(w[0]).begins_with("Salon-bred") and w[1]), "Salon-bred helps with the Nobility")
	var gu: Dictionary = Empire.envoy_effect("clement", "guild")
	check(gu["why"].any(func(w): return str(w[0]).begins_with("Salon-bred") and not w[1]), "and grates on the Guild")
	_join("mildred")
	_join("clement")
	var esc: Dictionary = Empire.expedition_odds("escort_ferry", ["mildred"])
	check(esc["why"].any(func(w): return str(w[0]).contains("Vowed")), "a Vowed escort goes smoother")
	var sal: Dictionary = Empire.expedition_odds("salvage_mill", ["clement"])
	check(sal["why"].any(func(w): return str(w[0]).contains("Salon-bred") and not w[1]), "Salon-bred won't touch Salvage")


## Twelve people who all want the tavern: five stand there, the rest go where there is room, and no two
## stand on the same spot.
func test_town_posts_never_stack_people() -> void:
	Empire.recruits.clear()
	_join("ash")
	for id in ["tobble", "jessamy", "ottoline", "velvette", "saffron", "pell", "hesper", "dunmore", "biscuits", "merrow", "firmin", "joan"]:
		_join(id)
		Empire.recruit(id)["post"] = "tavern"
	var hub := await goto(HUB)
	if hub == null:
		return
	await frames(6)
	if hub.dialogue_box.visible:
		hub.dialogue_box._close()
		await frames(4)
	hub._place_people()
	var spots := {}
	var at_tavern := 0
	var tavern: Vector2 = hub.area.markers["tavern"][0]
	for id in hub.npcs:
		var p: Vector2 = (hub.npcs[id] as Node2D).global_position
		var key := "%d,%d" % [roundi(p.x), roundi(p.y)]
		check(not spots.has(key), "%s and %s share a spot" % [id, spots.get(key, "")])
		spots[key] = id
		if absf(p.y - tavern.y) < 1.0 and absf(p.x - tavern.x) <= 36.0:
			at_tavern += 1
	check_eq(at_tavern, hub.POST_ROOM, "five stand at the tavern")
	check_eq(hub.npcs.size(), 12, "everyone is somewhere in town")
	Empire.recruit_data.clear()  # drop the edited posts; the next lookup reloads recruits.json
