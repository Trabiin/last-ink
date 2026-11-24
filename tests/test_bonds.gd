extends "res://tests/test_case.gd"
## Bonds (issues #50 and #120; this file is issue #122, replacing tools/bond_check.gd). For every bond in
## data/bonds.json: the data is complete, every line fits the scene's text box, ranks 1 to 5 (and the
## romance moment, for those who have one) play through the real scene view and move the bond on, the
## personal mission comes up at rank 4 and an erased home province locks it until it is reclaimed, and
## every perk unlocks at its rank and does what it says.
##
## Screenshots (optional): run with BOND_SHOTS=<folder> under a display (xvfb-run, not --headless):
##   BOND_SHOTS=/tmp/bonds xvfb-run -a godot --audio-driver Dummy --path . -s tests/run.gd -- bonds

const EXPRESSIONS := ["happy", "angry", "sad", "surprised", "smug"]
## The scene view's text box (scripts/scene_view.gd _draw) at the 640x360 layout size.
const VIEW_W := 640.0
const BOX_H := 86.0
const TEXT_W := VIEW_W - 24.0 - 52.0  # box width less its margins
const CHOICE_W := VIEW_W - 24.0 - 60.0 - 16.0
const MAX_CHOICES := 3  # 20 px a row below the "Ash..." line
const LABEL_MAX := 60

var Empire: Node
var D := {}
var view: Control
var shots := ""


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	Empire.reset()
	D = JSON.parse_string(FileAccess.get_file_as_string("res://data/bonds.json"))
	shots = OS.get_environment("BOND_SHOTS")
	if shots != "" and DisplayServer.get_name() == "headless":
		print("BOND_SHOTS ignored: screenshots need a display (run under xvfb-run without --headless)")
		shots = ""
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)


func after_each() -> void:
	if view != null and is_instance_valid(view):
		view.queue_free()
	tree.paused = false


func _cast() -> Array:
	return (D["cast"] as Dictionary).keys()


## Everyone with a bond, in Ash's company, with a Guildhall so personal missions can come up.
func _join_all() -> void:
	Empire.buildings["guildhall"] = 1
	for id in _cast():
		Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}


func _shot(name: String) -> void:
	if shots == "":
		return
	await frames(2)
	var img := tree.root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [shots, name])


# ------------------------------------------------------------------ data

func test_every_bond_is_complete() -> void:
	var font: Font = ThemeDB.fallback_font
	for id in _cast():
		var info: Dictionary = Empire.bond_info(id)
		if not check(not info.is_empty(), "%s has a bond" % id):
			continue
		check(load("res://scripts/scene_view.gd").portrait(id) != null, "%s has a portrait" % id)
		for k in ["3", "5"]:
			var pk: Dictionary = info.get("perks", {}).get(k, {})
			check(str(pk.get("name", "")) != "" and str(pk.get("desc", "")) != "" and not (pk.get("effect", {}) as Dictionary).is_empty(),
				"%s has a full rank %s perk" % [id, k])
		check(Empire.personal_job(id) != "", "%s has a personal mission" % id)
		check(PersonalMissions.def_for(id).get("province", "") != "", "%s's personal mission has a home province" % id)
		var ranks := []
		for sc in info.get("scenes", []):
			ranks.append(int(sc["rank"]))
			var where := "%s rank %d" % [id, sc["rank"]]
			check(str(sc.get("title", "")) != "", where + ": a title")
			var choices: Array = sc.get("choice", [])
			check(choices.size() >= 2 and choices.size() <= MAX_CHOICES, "%s: 2 to %d choices (has %d)" % [where, MAX_CHOICES, choices.size()])
			var all: Array = sc["lines"] + sc.get("end", [])
			for ch in choices:
				var label := str(ch.get("label", ""))
				check(label != "" and label.length() <= LABEL_MAX, "%s: choice label 1 to %d characters: %s" % [where, LABEL_MAX, label])
				check(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x <= CHOICE_W, "%s: choice too wide for its row: %s" % [where, label])
				all += ch.get("reply", [])
			for l in all:
				_check_line(where, id, l, font)
		check_eq(ranks, [1, 2, 3, 4, 5], "%s has one scene per rank" % id)


## A scene line: a known speaker, a known expression, and text that fits the box (scene_view.gd draws
## it from 22 px below the box top, 12 px lower under a name, and the box is BOX_H tall).
func _check_line(where: String, id: String, l: Array, font: Font) -> void:
	var sp := str(l[0])
	check(sp == "" or sp == id or Empire.recruits.has(sp) or not Empire.recruit(sp).is_empty() or not Dialogue.speaker_info(sp).is_empty(),
		"%s: unknown speaker %s" % [where, sp])
	if l.size() > 2:
		check(str(l[2]) in EXPRESSIONS, "%s: unknown expression %s" % [where, l[2]])
	var text := str(l[1])
	check(text.strip_edges() != "", "%s: an empty line" % where)
	var lines := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, TEXT_W, 11).y / font.get_height(11)
	var top := 22.0 + (12.0 if sp != "" else 0.0)
	var last_baseline := top + (roundi(lines) - 1) * font.get_height(11)
	check(last_baseline <= BOX_H - 6.0, "%s: line too long for the box (%d lines): %s" % [where, roundi(lines), text.left(50)])


# ------------------------------------------------------------------ the scenes

## Every rank scene of every bond, through the real scene view: lines, the choice, the reply, the outro.
func test_every_scene_plays_through_the_view() -> void:
	_join_all()
	allow_log("non-equal opposite anchors")  # scene_view sizes itself on play, as in town
	allow_log("If you want to set size")
	view = load("res://scripts/scene_view.gd").new()
	tree.root.add_child(view)
	view.visible = false
	await frames(1)
	for id in _cast():
		var queue := []
		for r in range(1, 6):
			queue.append(r)
			if r == 3 and Relationships.can_romance(id):  # the romance question comes before rank 4 (#116)
				queue.append(Relationships.MOMENT)
		for r in queue:
			await _play(id, r)
	view.queue_free()


func _play(id: String, r: int) -> void:
	var b: Dictionary = Empire.bonds.get(id, {"points": 0, "rank": maxi(r - 1, 0), "talk_day": 0, "personal_done": false})
	Empire.bonds[id] = b
	if r == Relationships.MOMENT:
		b["points"] = maxi(int(b["points"]), int(Relationships.data()["romance"]["moment_points"]))
	else:
		b["points"] = Empire.bond_threshold(r)
	if r == 5:
		var st := PersonalMissions.state(id)
		check(st == "offered" or st == "blocked", "%s's personal mission is on the Command Table at rank 4 (%s)" % [id, st])
		b["personal_done"] = true  # rank 5 waits on it
	check_eq(Empire.bond_next_scene(id), r, "%s: the next scene" % id)
	view.play(id, r)
	if not check(view.visible, "%s rank %d opens" % [id, r]):
		return
	await frames(2)
	view._at = mini(2, view._lines.size() - 1)
	view._shown = 99999.0
	await _shot("%s_r%d_line" % [id, r])
	view._at = view._lines.size() - 1
	view._shown = 99999.0
	view._advance()
	if not check_eq(view._stage, "choice", "%s rank %d reaches its choice" % [id, r]):
		view._close()
		return
	await _shot("%s_r%d_choice" % [id, r])
	view._pick(0)
	var guard := 0
	while view._stage == "reply" and guard < 50:
		view._shown = 99999.0
		view._advance()
		guard += 1
	check_eq(view._stage, "done", "%s rank %d reaches its outro" % [id, r])
	await _shot("%s_r%d_done" % [id, r])
	if r == Relationships.MOMENT:
		check_eq(Relationships.romance_of(id), "partner", "%s: saying yes starts a romance" % id)
	else:
		check_eq(Empire.bond_rank(id), r, "%s reaches rank %d" % [id, r])
		check(view._outro.contains("Bond rank %d" % r), "%s rank %d: the outro names the rank" % [id, r])
		if r == 4:
			check(view._outro.contains("Personal mission"), "%s rank 4: the outro points at the personal mission" % id)
	view._close()
	check(not view.visible, "%s rank %d closes" % [id, r])
	await frames(1)


# ------------------------------------------------------------------ personal missions

## Rank 4 puts the personal mission on the Command Table; losing the home province to the Blank locks
## it (Ojon's rule) until it is reclaimed; done stays done.
func test_personal_missions_follow_rank_and_home() -> void:
	_join_all()
	for id in _cast():
		var home := str(PersonalMissions.def_for(id).get("province", ""))
		var prov: Dictionary = Empire.territory().find(home)
		if not check(not prov.is_empty(), "%s's home province %s exists" % [id, home]):
			continue
		Empire.bonds[id] = {"points": Empire.bond_threshold(3), "rank": 3, "talk_day": 0, "personal_done": false}
		check_eq(PersonalMissions.state(id), "locked", "%s: locked below rank 4" % id)
		Empire.bonds[id]["rank"] = 4
		Empire.bonds[id]["points"] = Empire.bond_threshold(4)
		var st := PersonalMissions.state(id)
		check(st == "offered" or st == "blocked", "%s: on the Command Table at rank 4 (%s)" % [id, st])
		var owner_was: String = prov["owner"]
		prov["owner"] = "erased"
		check_eq(PersonalMissions.state(id), "lost", "%s: an erased %s locks it" % [id, home])
		check(Empire.personal_lost(id) != "", "%s: and says which province took it" % id)
		check(Empire.bond_next_scene(id) != 5 or not Empire.personal_done(id), "%s: rank 5 stays shut" % id)
		prov["owner"] = owner_was
		check(PersonalMissions.state(id) in ["offered", "blocked"], "%s: back when %s is reclaimed" % [id, home])
		check_eq(Empire.personal_lost(id), "", "%s: nothing lost any more" % id)
		Empire.bonds[id]["personal_done"] = true
		prov["owner"] = "erased"
		check_eq(PersonalMissions.state(id), "done", "%s: once done, losing the province takes nothing away" % id)
		prov["owner"] = owner_was


# ------------------------------------------------------------------ perks

## Every perk shows up at its rank and not before.
func test_every_perk_unlocks_at_its_rank() -> void:
	_join_all()
	for id in _cast():
		for r in [2, 3, 5]:
			Empire.bonds[id] = {"points": Empire.bond_threshold(r), "rank": r, "talk_day": 0, "personal_done": r == 5}
			var have: Array = Empire.bond_perks().filter(func(p): return p["id"] == id).map(func(p): return int(p["rank"]))
			var want: Array = [3, 5].filter(func(k): return k <= r)
			have.sort()
			check_eq(have, want, "%s at rank %d: perks" % [id, r])
		Empire.bonds.erase(id)


## The eight perks added with the four new field heroes (#120) doing what they say.
func test_new_hero_perks_take_effect() -> void:
	_join_all()
	for id in ["ottoline", "jessamy", "odile", "velvette"]:
		Empire.bonds[id] = {"points": Empire.bond_threshold(5), "rank": 5, "talk_day": 0, "personal_done": true}
	var e: Node = Empire
	# Ottoline: House Rules (10% less damage to the party) and Nobody Gets Through (less Hollowmark Fray).
	check_eq(e.damage_to_party(20), 18, "House Rules: 20 damage to the party becomes 18")
	var home: Dictionary = e.territory().find("hollowmark")
	check(e.fray_sources(home).any(func(s): return str(s[0]).begins_with("Nobody Gets Through")), "Nobody Gets Through is in Hollowmark's Fray list")
	# Jessamy: Night Freight (Supplies a day) and Back Roads (expeditions 20% quicker).
	check(e.ledger().any(func(l): return str(l["label"]).begins_with("Night Freight") and int(l["supplies"]) == 2), "Night Freight pays 2 Supplies a day")
	var two := ""
	for jid in e.job_data:
		if int(e.job(jid).get("days", 0)) == 2:
			two = jid
			break
	if check(two != "", "a two-day expedition to time"):
		check(is_equal_approx(e.job_days(two), 1.6), "Back Roads: a 2-day expedition takes %s days" % e.job_days(two))
	# Odile: Fair Assessment (Gilt a day per province held) and Clean Books (20% off building Gilt).
	check(e.ledger().any(func(l): return str(l["label"]).begins_with("Fair Assessment") and int(l["gilt"]) >= 1), "Fair Assessment is in the ledger")
	var raw: Dictionary = e.building("barracks")["levels"][0]["cost"]
	var cut: Dictionary = e.next_level("barracks")["cost"]
	if raw.has("gilt"):
		check_eq(int(cut["gilt"]), int(floor(int(raw["gilt"]) * 0.8)), "Clean Books: 20% off the Barracks")
	# Fauvette: Pillow Talk (+1 on every standing gain) and Encore (15% faster gauge on missions).
	var before: int = e.standing_of("guild")
	e.change_standing("guild", 3, "", true)
	check_eq(e.standing_of("guild") - before, 4, "Pillow Talk: +3 standing becomes +4")
	var b: Dictionary = e.mission_boosts()
	check(is_equal_approx(float(b["power_rate"]), 1.15), "Encore: gauge rate %s, want 1.15" % b["power_rate"])
	check(b.get("lines", []).any(func(l): return str(l).contains("Encore")), "Encore shows in the mission briefing lines")
	# Without the bonds, none of it.
	for id in ["ottoline", "jessamy", "odile", "velvette"]:
		e.bonds.erase(id)
	check_eq(e.damage_to_party(20), 20, "no House Rules without Ottoline's bond")
	check(is_equal_approx(float(e.mission_boosts()["power_rate"]), 1.0), "no Encore without Fauvette's bond")
