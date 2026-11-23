extends "res://tests/test_case.gd"
## Romance, friends and rivals, fates and epilogues (issue #116): data/relationships.json,
## data/epilogues.json, scripts/relationships.gd, scripts/epilogues.gd, scripts/epilogue_view.gd.

const FIXTURE := "res://tests/fixtures/saves/20261122_relationships__table_day38_romance_ready.json"
const EXPRESSIONS := ["happy", "angry", "sad", "surprised", "smug"]
const PERK_KEYS := ["gilt", "supplies", "insight", "gilt_per_held", "heal", "research_pace", "squad_odds", "all_odds",
	"surge_warning", "job_speed", "build_discount", "standing_bonus", "fray_home", "mission_hp", "mission_damage",
	"mission_revive", "mission_guard", "mission_power_rate"]
const PARTY_KEYS := ["damage", "hp", "guard", "power_rate", "revive"]
const WHEN_KEYS := ["romance", "rank_min", "rank_max", "personal", "home", "missions_min", "injuries_min", "choice", "lost", "pair", "betrayal"]

var Empire: Node
var Saves: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	Empire.reset()


func _join(id: String, rank := 0, points := -1) -> void:
	Empire.recruits[id] = Empire.recruits.get(id, {"role": "idle", "target": "", "injured": 0})
	Empire.bonds[id] = {"points": Empire.bond_threshold(rank) if points < 0 else points, "rank": rank, "talk_day": 0, "personal_done": false}


func _choice_index(sc: Dictionary, romance: bool) -> int:
	var opts: Array = sc.get("choice", [])
	for i in opts.size():
		if bool(opts[i].get("romance", false)) == romance:
			return i
	return -1


## Lines must fit the scene box: four lines of 11 px text at 592 px.
func _check_lines(where: String, ls: Array, owner: String) -> void:
	var f = ThemeDB.fallback_font
	for l in ls:
		if not check(typeof(l) == TYPE_ARRAY and l.size() >= 2, "%s: a line is not [speaker, text]" % where):
			continue
		var sp = str(l[0])
		check(sp == "" or sp == owner or Empire.recruit_data.has(sp), "%s: unknown speaker %s" % [where, sp])
		if l.size() > 2:
			check(str(l[2]) in EXPRESSIONS, "%s: unknown expression %s" % [where, l[2]])
		var h = f.get_multiline_string_size(str(l[1]), HORIZONTAL_ALIGNMENT_LEFT, 592, 11).y
		check(h <= 4 * f.get_height(11) + 1, "%s: line too long for the box: %s" % [where, str(l[1]).left(50)])


# ---------------------------------------------------------------- data

func test_romance_data() -> void:
	var cast = Relationships.romance_cast()
	check(cast.size() >= 4, "a real choice of romances")
	for id in cast:
		var w = "relationships.json romance " + id
		var c: Dictionary = cast[id]
		check(Empire.bond_cast().has(id), "%s: not in the bond cast" % w)
		var pk: Dictionary = c.get("perk", {})
		check(pk.has("name") and pk.has("desc") and not pk.get("effect", {}).is_empty(), "%s: perk incomplete" % w)
		for k in pk.get("effect", {}):
			check(k in PERK_KEYS, "%s: unknown perk effect %s" % [w, k])
		var m: Dictionary = c.get("moment", {})
		check(str(m.get("title", "")) != "", "%s: moment has no title" % w)
		_check_lines(w + " moment", m.get("lines", []), id)
		var opts: Array = m.get("choice", [])
		check(opts.filter(func(o): return o.get("romance", false) == true).size() == 1, "%s: exactly one romantic choice" % w)
		check(opts.filter(func(o): return o.has("romance") and o["romance"] == false).size() >= 1, "%s: a way to say no" % w)
		for o in opts:
			check(str(o["label"]).length() <= 60, "%s: choice too long: %s" % [w, o["label"]])
			_check_lines(w + " moment reply", o.get("reply", []), id)
		var r5: Dictionary = c.get("rank5", {})
		check(int(r5.get("rank", 0)) == 5 and r5.get("choice", []).size() >= 2, "%s: romantic rank 5 scene with two choices" % w)
		_check_lines(w + " rank 5", r5.get("lines", []), id)
		for o in r5.get("choice", []):
			check(str(o["label"]).length() <= 60, "%s: rank 5 choice too long: %s" % [w, o["label"]])
			_check_lines(w + " rank 5 reply", o.get("reply", []), id)
		_check_lines(w + " ended", c.get("ended", []), id)
		check(not c.get("ended", []).is_empty(), "%s: no lines for when it ends" % w)
		check(c.get("talk", []).size() >= 3, "%s: at least three partner chats" % w)


func test_pair_data() -> void:
	var seen = {}
	for p in Relationships.data()["pairs"]:
		var ids: Array = p["ids"]
		var w = "relationships.json pair %s" % "+".join(ids)
		check(ids.size() == 2 and ids[0] != ids[1], "%s: needs two different people" % w)
		for id in ids:
			check(Empire.recruit_data.has(id) and id != "ash", "%s: %s is not a recruit" % [w, id])
		var k = "|".join([ids[0], ids[1]] if ids[0] < ids[1] else [ids[1], ids[0]])
		check(not seen.has(k), "%s: listed twice" % w)
		seen[k] = true
		check(p.get("kind", "") in ["friends", "rivals"], "%s: kind must be friends or rivals" % w)
		check(str(p.get("name", "")) != "" and str(p.get("text", "")) != "", "%s: name and text" % w)
		for sec in [p] + ([p["truce"]] if p.has("truce") else []):
			for ek in sec.get("effects", {}):
				check(ek in ["expedition", "building", "party", "bond"], "%s: unknown effect %s" % [w, ek])
			for pk in sec.get("effects", {}).get("party", {}):
				check(pk in PARTY_KEYS, "%s: unknown party effect %s" % [w, pk])
			check(not sec.get("banter", []).is_empty(), "%s: needs banter" % w)
			for ex in sec.get("banter", []):
				check(ex.size() >= 2, "%s: banter is an exchange of two or more lines" % w)
				for l in ex:
					check(str(l[0]) in ids, "%s: banter speaker %s is not in the pair" % [w, l[0]])
		if p.has("truce"):
			check(p["kind"] == "rivals" and int(p["truce"].get("days", 0)) > 0, "%s: only rivals make peace, after some days" % w)
	var kinds = Relationships.data()["pairs"].map(func(p): return p["kind"])
	check(kinds.count("friends") >= 5 and kinds.count("rivals") >= 5, "plenty of friends and rivals")


func test_epilogue_data() -> void:
	var cast: Dictionary = Epilogues.data()["cast"]
	check(cast.has("default"), "a default epilogue for recruits added later")
	for id in Empire.recruit_data:
		if id != "ash":
			check(cast.has(id), "epilogues.json: %s has no epilogue" % id)
	for id in cast:
		var vs: Array = cast[id]
		check(not vs.is_empty() and not vs[-1].has("when"), "epilogues.json %s: the last variant must have no 'when'" % id)
		check(id == "default" or Empire.recruit_data.has(id), "epilogues.json: %s is not a recruit" % id)
		for v in vs:
			check(str(v.get("text", "")).length() > 40, "epilogues.json %s: text too short" % id)
			for k in v.get("when", {}):
				check(k in WHEN_KEYS, "epilogues.json %s: unknown condition %s" % [id, k])
			var pr: Dictionary = v.get("when", {}).get("pair", {})
			if not pr.is_empty():
				check(not Relationships.pair_between(id, str(pr.get("with", ""))).is_empty(), "epilogues.json %s: no pair with %s" % [id, pr.get("with")])
			if v.get("when", {}).has("romance") and str(v["when"]["romance"]) in ["partner", "ex"]:
				check(Relationships.can_romance(id), "epilogues.json %s: romance variant for someone who can't be romanced" % id)


# ---------------------------------------------------------------- romance

func test_romance_moment_comes_before_rank_4() -> void:
	_join("velvette", 3)
	check_eq(Empire.bond_next_scene("velvette"), 0, "right after rank 3: nothing yet")
	Empire.bond_gain("velvette", 99)
	check_eq(Empire.bond_next_scene("velvette"), Relationships.MOMENT, "the question comes before rank 4")
	var sc = Empire.bond_scene("velvette", Relationships.MOMENT)
	check_eq(str(sc.get("title", "")), "Second Billing", "the moment scene")
	var perk = Empire.finish_bond_scene("velvette", Relationships.MOMENT, _choice_index(sc, true))
	check_eq(Relationships.partner(), "velvette", "saying yes starts a romance")
	check_eq(str(perk.get("name", "")), "Leading Lady", "and returns the romance perk")
	check_eq(Empire.bond_rank("velvette"), 3, "the moment doesn't change the rank")
	check_eq(Empire.bond_next_scene("velvette"), 4, "then rank 4 is next")
	check(Empire.bond_perks().any(func(p): return p.get("romance", false) and p["name"] == "Leading Lady"), "the perk counts while it lasts")
	check(float(Empire.mission_boosts()["revive"]) > 1.2, "faster revives on missions")
	check(Relationships.status_text("velvette").begins_with("Romance: with Ash"), "the Bonds screen says so")


func test_saying_no_is_final() -> void:
	_join("odile", 3, 40)
	var sc = Empire.bond_scene("odile", Relationships.MOMENT)
	Empire.finish_bond_scene("odile", Relationships.MOMENT, _choice_index(sc, false))
	check_eq(Relationships.romance_of("odile"), "friends", "friends")
	check_eq(Relationships.partner(), "", "no partner")
	check(not Relationships.moment_ready("odile"), "never asked again")
	check_eq(Empire.bond_next_scene("odile"), 0, "the next rank waits for points as usual")
	Empire.bond_gain("odile", 99)
	check_eq(Empire.bond_next_scene("odile"), 4, "rank 4 scene follows")
	check_eq(str(Empire.bond_scene("odile", 5).get("title", "")), "Reconciled", "the plain rank 5 scene")
	check(not str(Empire.bond_scene("odile", 5)["lines"]).contains("jointly held"), "not the romantic one")


func test_one_romance_at_a_time() -> void:
	_join("velvette", 4, 50)
	_join("jessamy", 3, 40)
	var sv = Empire.bond_scene("velvette", Relationships.MOMENT)
	Empire.finish_bond_scene("velvette", Relationships.MOMENT, _choice_index(sv, true))
	var sj = Empire.bond_scene("jessamy", Relationships.MOMENT)
	var yes = _choice_index(sj, true)
	check(str(sj["choice"][yes]["label"]).contains("ends it with Fauvette"), "the choice says what it costs")
	var before = Empire.bond_points("velvette")
	Empire.finish_bond_scene("jessamy", Relationships.MOMENT, yes)
	check_eq(Relationships.partner(), "jessamy", "Jessamy now")
	check_eq(Relationships.romance_of("velvette"), "ex", "Fauvette is an ex")
	check_eq(Empire.bond_points("velvette"), maxi(before - 6, Empire.bond_threshold(4)), "it costs Fauvette's bond, never below her rank")
	check(not Empire.bond_perks().any(func(p): return p["name"] == "Leading Lady"), "her romance perk is gone")
	check(Empire.bond_perks().any(func(p): return p["name"] == "Two for the Road"), "Jessamy's counts")
	check(not Relationships.take_ended_lines("velvette").is_empty(), "Fauvette has words for Ash")
	check(Relationships.take_ended_lines("velvette").is_empty(), "once")
	check(not Relationships.moment_ready("velvette"), "no second chance")
	check(Relationships.talk_line("jessamy", 0) != "", "partner chats")
	check_eq(Relationships.talk_line("velvette", 0), "", "no partner chats for an ex")


func test_romantic_rank_5_and_its_replay() -> void:
	_join("jessamy", 4, 46)
	Relationships.decide("jessamy", {"romance": true})
	Empire.bonds["jessamy"]["personal_done"] = true
	Empire.bond_gain("jessamy", 99)
	check_eq(Empire.bond_next_scene("jessamy"), 5, "rank 5 waits")
	check(str(Empire.bond_scene("jessamy", 5)["lines"]).contains("next of kin"), "the romantic version plays")
	Empire.finish_bond_scene("jessamy", 5, 0)
	check_eq(str(Relationships.fate("jessamy")["choices"].get("5v", "")), "romance", "which version was seen is kept")
	Relationships.end_romance("jessamy")
	check(str(Empire.bond_scene("jessamy", 5)["lines"]).contains("next of kin"), "replays show what was seen, even after it ended")
	var seen = Empire.bond_seen_scenes("jessamy").map(func(s): return int(s["rank"]))
	check(Relationships.MOMENT in seen, "the moment can be replayed")
	check_eq(seen.find(Relationships.MOMENT), 3, "between rank 3 and rank 4")


func test_scene_view_plays_the_moment() -> void:
	_join("ottoline", 3, 40)
	allow_log("non-equal opposite anchors")  # scene_view sizes itself on play, as in town
	allow_log("If you want to set size")
	var view = load("res://scripts/scene_view.gd").new()
	tree.root.add_child(view)
	await frames(1)
	view.play("ottoline", Relationships.MOMENT)
	check(view.visible, "the scene opens")
	view._at = view._lines.size() - 1
	view._shown = 99999.0
	view._advance()
	check_eq(view._stage, "choice", "reaches the choice")
	view._pick(_choice_index(view._scene(), true))
	while view._stage == "reply":
		view._shown = 99999.0
		view._advance()
	check(str(view._outro).contains("a romance"), "the closing card says so: %s" % view._outro)
	check(str(view._outro).contains("Bouncer's Favourite"), "and names the perk")
	view.queue_free()


# ---------------------------------------------------------------- friends and rivals

func test_rivals_at_work_and_on_the_road() -> void:
	Empire.buildings["command_table"] = 2
	for id in ["quill", "tobble"]:
		_join(id, 1)
	check_eq(Relationships.pair_state("quill", "tobble"), "rivals", "Quill and Tobble are rivals")
	check_eq(Relationships.building_mod(["quill", "tobble"]), -1, "they get in each other's way")
	var both: int = Empire.building_effect("command_table", 2, ["quill", "tobble"]).get("upkeep_cut", 0)
	var raw = int(Empire.recruit("quill")["stats"]["craft"]) / 3 + int(Empire.recruit("tobble")["stats"]["craft"]) / 3
	check_eq(both, maxi(raw - 1, 0) if raw > 0 else 0, "the Command Table's output drops by one")
	var preview = Relationships.notes_text(["quill", "tobble"], "building")
	check(preview.contains("Rivals") and preview.contains("building output -1"), "shown up front: %s" % preview)
	Empire.buildings["guildhall"] = 1
	var jid: String = Empire.job_ids()[0]
	var odds = Empire.expedition_odds(jid, ["quill", "tobble"])
	check(odds["why"].any(func(w): return str(w[0]).begins_with("The bar tab") and not w[1]), "the odds list says why")


func test_rivals_in_the_party_and_their_truce() -> void:
	for id in Empire.recruits:
		Empire.recruits[id]["role"] = "idle"
	for id in ["bran", "gristle"]:
		_join(id, 2)
		Empire.recruits[id]["role"] = "party"
	Empire.recruits["ash"]["role"] = "party"
	var b = Empire.mission_boosts()
	check(b["lines"].any(func(l): return str(l).contains("The bandage bill")), "mission boosts list the pair")
	check_eq(Empire.damage_to_party(20), 22, "rivals showing off take 10% more damage")
	var pts = Empire.bond_points("bran")
	Relationships.daily()
	check_eq(Empire.bond_points("bran"), maxi(pts - 1, Empire.bond_threshold(2)), "posting rivals together costs a little bond")
	for i in 11:
		Relationships.daily()
	check_eq(Relationships.pair_state("bran", "gristle"), "truce", "twelve days together and they make peace")
	check_eq(Empire.damage_to_party(20), 20, "no more risk-taking")
	check(Journal.log_entries("bond").any(func(e): return str(e["title"]).contains("Account in good standing")), "the journal records it")
	check(not Relationships.banter_for(["bran", "gristle", "ash"]).is_empty(), "they banter at the start of a mission")


func test_friends_help() -> void:
	for id in Empire.recruits:
		Empire.recruits[id]["role"] = "idle"
	Empire.recruits["ash"]["role"] = "party"
	for id in ["ottoline", "velvette"]:
		_join(id, 2)
		Empire.recruits[id]["role"] = "party"
	check_eq(Relationships.pair_state("ottoline", "velvette"), "friends", "Old Encore hands")
	check_eq(Empire.damage_to_party(20), 19, "friends watch each other: 5% less damage")
	var pts = Empire.bond_points("velvette")
	Relationships.daily()
	check_eq(Empire.bond_points("velvette"), pts + 1, "and enjoy it")


# ---------------------------------------------------------------- fates and epilogues

func test_fates_and_epilogues() -> void:
	for id in ["velvette", "jessamy", "bran", "gristle", "pell"]:
		_join(id, 0)
	Empire.recruit_data  # loaded
	Empire.bonds.erase("pell")
	check(Epilogues.text_for("velvette").begins_with("Fauvette took the first good offer"), "a distant Fauvette gets the fallback")
	Empire.bonds["velvette"]["rank"] = 5
	Relationships.note_choice("velvette", 4, 1)
	check(Epilogues.text_for("velvette").contains("Augustin Sallow lived"), "sparing Sallow at rank 4 shows: %s" % Epilogues.text_for("velvette").left(40))
	Relationships.decide("velvette", {"romance": true})
	check(Epilogues.text_for("velvette").contains("Chapter nine"), "a romance wins over everything")
	Relationships.decide("jessamy", {"romance": true})
	check(Epilogues.text_for("velvette").contains("looked up at the wings"), "an ex has their own ending")
	Relationships.note_mission(["bran"], "success")
	check_eq(int(Relationships.fate("bran")["missions"]), 1, "missions counted")
	Relationships.note_injury("bran")
	check_eq(int(Relationships.fate("bran")["injuries"]), 1, "injuries counted")
	Relationships.note_lost("pell", "Skim the paper edge")
	Empire.recruits.erase("pell")
	check(Relationships.was_lost("pell"), "Pell was lost")
	check(Epilogues.text_for("pell").begins_with("Pell Mossop went into the white"), "a lost recruit gets the lost card")
	var cards = Epilogues.cards()
	var ids = cards.map(func(c): return c["id"])
	check(not "ash" in ids, "Ash gets no card")
	check("pell" in ids and cards[ids.find("pell")]["lost"], "the lost are remembered")
	check(cards.all(func(c): return str(c["text"]) != ""), "everyone has a line")
	# Someone added later with no list of their own still gets one.
	check(Epilogues.variants("nobody_yet") == Epilogues.data()["cast"]["default"], "new recruits use the default")


func test_every_epilogue_has_a_line_in_any_state() -> void:
	for id in Empire.recruit_data:
		if id != "ash":
			_join(id, 0)
	for rank in [0, 3, 5]:
		for id in Empire.bond_ids():
			Empire.bonds[id]["rank"] = rank
		for c in Epilogues.cards():
			check(str(c["text"]).length() > 40, "%s at rank %d has an epilogue" % [c["id"], rank])
	check(not Epilogues.text_for("odile").contains("{"), "no unfilled placeholders")


func test_epilogue_view_pages_through() -> void:
	for id in ["bran", "velvette"]:
		_join(id, 5)
	var v = EpilogueView.new()
	tree.root.add_child(v)
	await frames(1)
	var done = [false]
	v.finished.connect(func(): done[0] = true)
	var cards = Epilogues.cards()
	v.play(cards)
	check(v.visible, "the cards show")
	await frames(2)
	for i in cards.size() * 2:
		v.advance()
	check(done[0], "every card, then finished")
	check(not v.visible, "and it closes")
	v.queue_free()


func test_old_save_gets_its_fates() -> void:
	var r: Dictionary = Saves.parse(FileAccess.get_file_as_string(FIXTURE))
	if not check_eq(r["status"], Saves.GOOD, "the day 38 save reads"):
		return
	var rel: Dictionary = r["data"]["empire"]["relations"]
	check_eq(int(rel["fates"].get("hesper", {}).get("lost_day", 0)), 30, "Hetty, lost on day 30")
	check_eq(str(rel["fates"]["hesper"]["lost_where"]), "Skim the paper edge at Whitewater", "and where")
	check_eq(int(rel["fates"].get("dunmore", {}).get("injuries", 0)), 1, "Dunmore came back hurt")
	check_eq(int(rel["fates"].get("jessamy", {}).get("injuries", 0)), 1, "Jessamy is hurt right now")
	check_eq(int(rel["fates"].get("velvette", {}).get("personal_tries", 0)), 1, "Fauvette's mission was done")
	check_eq(str(rel["partner"]), "", "nobody's partner yet")
	Empire.from_dict(r["data"]["empire"])
	check_eq(Empire.bond_next_scene("velvette"), Relationships.MOMENT, "Fauvette, already bound, gets asked")
	check_eq(Empire.bond_next_scene("jessamy"), 0, "Jessamy isn't far enough along yet")
	check_eq(Empire.bond_next_scene("odile"), Relationships.MOMENT, "Odile at rank 4 gets asked before anything else")
	check_eq(Relationships.pair_state("quill", "tobble"), "rivals", "rivals start from zero")
	var ids = Epilogues.cards().map(func(c): return c["id"])
	check("hesper" in ids, "Hetty gets an epilogue")
	check(Epilogues.text_for("hesper").contains("walking off the page"), "the lost one")
