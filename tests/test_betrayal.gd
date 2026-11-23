extends "res://tests/test_case.gd"
## The climax betrayal (issue #186): data/betrayal.json, scripts/betrayal.gd, the betrayal fates and their
## epilogue variants, and the save step 20261125_betrayal.

const FIXTURE := "res://tests/fixtures/saves/20261125_betrayal__table_day51_tithe_erased_oldmill_reclaimed.json"
const WEIGHT_KEYS := ["home_erased", "home_reclaimed", "personal_locked", "personal_open", "bond_low", "bond_mid", "rival", "ex", "close"]

var Empire: Node
var Saves: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	Empire.reset()


func _join(id: String, rank := 3) -> void:
	Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}
	Empire.bonds[id] = {"points": Empire.bond_threshold(rank), "rank": rank, "talk_day": 0, "personal_done": false}


## Nobody on the roster but Ash (and Bran when `bran`), every home held, nothing remembered.
func _blank_slate(bran := true) -> void:
	for id in Empire.recruits.keys():
		if id != "ash" and not (bran and id == "bran"):
			Empire.recruits.erase(id)
	for p in Empire.territory().provinces:
		if p["owner"] == "erased":
			p["owner"] = "free"
	Empire.relations = Relationships.fresh()


func _set_home(id: String, state: String) -> void:
	var pid := Betrayal.home_of(id)
	var p: Dictionary = Empire.territory().find(pid)
	p["owner"] = "erased" if state == "erased" else "free"
	if state != "held":
		Empire.relations["betrayal"]["fell"][pid] = 1
	else:
		Empire.relations["betrayal"]["fell"].erase(pid)


func _truce_all() -> void:
	for p in Relationships.pairs(false):
		if p["kind"] == "rivals" or p["kind"] == "truce":
			Empire.relations["pairs"][p["key"]] = {"days": 99, "truce": true}


func _lose(id: String) -> void:
	Empire.recruits.erase(id)
	Relationships.note_lost(id, "the paper edge")


# ---------------------------------------------------------------- data

func test_data() -> void:
	var d := Betrayal.data()
	check(Betrayal.threshold() > 0, "betrayal.json: a threshold")
	for k in d.get("weights", {}):
		check(k in WEIGHT_KEYS, "betrayal.json: unknown weight %s" % k)
	for k in WEIGHT_KEYS:
		check(d.get("weights", {}).has(k), "betrayal.json: weight %s missing" % k)
	check(Betrayal.weight("close") < 0, "closeness lowers the score")
	check(Empire.recruit_data.has(Betrayal.fallback()), "the fallback is a recruit")
	check(not Betrayal.is_candidate(Betrayal.fallback()), "the fallback is not also a candidate")
	var cands := Betrayal.candidates()
	check(cands.size() >= 3, "at least the first three candidates")
	for id in ["ottoline", "ninefingers", "odile"]:
		check(id in cands, "first build ships %s" % id)
	for c in d.get("candidates", []):
		var id := str(c.get("id", ""))
		check(Empire.recruit_data.has(id), "betrayal.json: %s is not a recruit" % id)
		check(Empire.bond_cast().has(id), "betrayal.json: %s has no bond" % id)
		check(cands.count(id) == 1, "betrayal.json: %s listed twice" % id)
		check(str(c.get("_offer", "")) != "", "betrayal.json: %s has no offer" % id)
		check(str(c.get("home", "")) == str(PersonalMissions.def_for(id).get("province", "")),
			"betrayal.json: %s's home is not their personal mission's province" % id)
		check(not Empire.territory().find(str(c.get("home", ""))).is_empty(), "betrayal.json: %s's home is not a province" % id)


func test_epilogue_variants_for_every_outcome() -> void:
	for id in Betrayal.candidates():
		var have := Epilogues.variants(id).map(func(v): return str(v.get("when", {}).get("betrayal", "")))
		for g in Betrayal.GESTURES:
			check(g in have, "epilogues.json %s: no '%s' variant" % [id, g])
	var bran := Epilogues.variants(Betrayal.fallback()).map(func(v): return str(v.get("when", {}).get("betrayal", "")))
	check("faked" in bran, "epilogues.json bran: no 'faked' variant")


# ---------------------------------------------------------------- scores

func test_erased_home_tips_a_good_friend() -> void:
	_blank_slate()
	_join("ninefingers", 3)
	Empire.bonds["ninefingers"]["personal_done"] = true
	_truce_all()
	check_eq(Betrayal.pick(), "bran", "home held, personal done, rank 3: nobody takes the deal")
	_set_home("ninefingers", "erased")
	check_eq(Betrayal.score("ninefingers"), Betrayal.weight("home_erased"), "only the erased home counts")
	check_eq(Betrayal.pick(), "ninefingers", "home erased: Daro takes the deal")


func test_neglect_adds_up() -> void:
	_blank_slate()
	_join("odile", 1)
	_set_home("odile", "reclaimed")
	_truce_all()
	var keys := Betrayal.parts("odile").map(func(p): return p[0])
	check_eq(keys, ["home_reclaimed", "personal_open", "bond_low"], "fell once, mission open, low bond")
	check(Betrayal.score("odile") >= Betrayal.threshold(), "neglect alone can clear the threshold")
	check_eq(Betrayal.pick(), "odile", "neglected Odile betrays Ash")
	Empire.bonds["odile"]["rank"] = 3
	Empire.bonds["odile"]["personal_done"] = true
	check_eq(Betrayal.pick(), "bran", "bond grown and mission done: Bran's con instead")


func test_locked_personal_mission_counts_more() -> void:
	_blank_slate()
	_join("ottoline", 3)
	check("personal_open" in Betrayal.parts("ottoline").map(func(p): return p[0]), "home held: the mission is just open")
	_set_home("ottoline", "erased")
	var keys := Betrayal.parts("ottoline").map(func(p): return p[0])
	check("personal_locked" in keys and not "personal_open" in keys, "the lost home locks the mission")


func test_rivalry_until_truce() -> void:
	_blank_slate(false)
	_join("ottoline", 3)
	check(not "rival" in Betrayal.parts("ottoline").map(func(p): return p[0]), "no rival on the roster, no rivalry")
	# Bran and Ottoline are rivals in data/relationships.json; Bran is on the roster.
	_join("bran", 3)
	check(Relationships.pair_state("bran", "ottoline") == "rivals", "fixture: Bran and Ottoline start as rivals")
	check("rival" in Betrayal.parts("ottoline").map(func(p): return p[0]), "Bran on the roster: rivalry counts")
	_truce_all()
	check(not "rival" in Betrayal.parts("ottoline").map(func(p): return p[0]), "a truce settles it")


func test_romance_partner_only_with_home_erased() -> void:
	_blank_slate()
	_join("odile", 5)
	Empire.relations["romance"]["odile"] = "partner"
	Empire.relations["partner"] = "odile"
	_join("jessamy", 0)  # an unresolved rival
	_set_home("odile", "reclaimed")
	check(not Betrayal.eligible("odile"), "a partner whose home stands is never offered the deal")
	check_eq(Betrayal.pick(), "bran", "so it's Bran's con")
	_set_home("odile", "erased")
	check(Betrayal.eligible("odile"), "home erased: the partner can be tempted")
	var close := Betrayal.parts("odile").filter(func(p): return p[0] == "close")
	check_eq(close.size(), 1, "rank 5 and romance are one minus, not two")
	check_eq(Betrayal.pick(), "odile", "rare, and meant to hurt")


func test_ex_holds_a_grudge() -> void:
	_blank_slate()
	_join("ottoline", 3)
	Empire.relations["romance"]["ottoline"] = "ex"
	check("ex" in Betrayal.parts("ottoline").map(func(p): return p[0]), "an ended romance adds to the score")


func test_ties_go_in_data_order() -> void:
	_blank_slate()
	_truce_all()
	var cands := Betrayal.candidates()
	for id in cands:
		_join(id, 3)
		_set_home(id, "erased")
	check_eq(Betrayal.pick(), cands[0], "equal scores: the first listed candidate")
	var r := Betrayal.ranking()
	check_eq(r.map(func(e): return e["id"]), cands, "ranking keeps data order on ties")
	Empire.bonds[cands[1]]["rank"] = 1
	check_eq(Betrayal.pick(), cands[1], "a higher score wins over data order")


func test_lost_and_absent_are_never_picked() -> void:
	_blank_slate()
	_join("ninefingers", 0)
	_set_home("ninefingers", "erased")
	check_eq(Betrayal.pick(), "ninefingers", "on the roster: picked")
	_lose("ninefingers")
	check(not Betrayal.eligible("ninefingers"), "lost in the white: not a candidate")
	check_eq(Betrayal.pick(), "bran", "lost: falls back to Bran")


func test_without_bran_the_top_candidate_takes_the_deal() -> void:
	_blank_slate(false)
	_join("odile", 4)
	_truce_all()
	Empire.bonds["odile"]["personal_done"] = true
	check(Betrayal.score("odile") < Betrayal.threshold(), "fixture: Odile is below the threshold")
	check_eq(Betrayal.pick(), "odile", "Bran gone: the top candidate takes the deal anyway")
	Empire.recruits.erase("odile")
	check_eq(Betrayal.pick(), "bran", "nobody left at all: it is still Bran's (Chapter 5 covers it)")


## The rule from DESIGN.md section 10: every save state picks exactly one betrayer, or Bran.
## Walks a few thousand campaigns built from every lever the score reads, plus the edges, and checks the
## pick is one known id, stable, obeys the rules, and that lock() writes exactly one betrayal fate.
func test_every_state_picks_exactly_one() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 186
	var cands := Betrayal.candidates()
	var fb := Betrayal.fallback()
	var states := 0
	var picked := {}
	for i in 3000:
		Empire.reset()
		_blank_slate(rng.randf() < 0.85)
		var partner := ""
		for id in cands:
			match rng.randi_range(0, 5):
				0:
					continue  # never joined
				1:
					_join(id, rng.randi_range(0, 5))
					_lose(id)
					continue
			_join(id, rng.randi_range(0, 5))
			_set_home(id, ["held", "reclaimed", "erased"][rng.randi_range(0, 2)])
			Empire.bonds[id]["personal_done"] = rng.randf() < 0.4
			var rom: String = ["", "", "ex", "friends", "partner"][rng.randi_range(0, 4)]
			if rom == "partner":
				if partner != "":
					rom = "ex"
				else:
					partner = id
					Empire.relations["partner"] = id
			if rom != "":
				Empire.relations["romance"][id] = rom
		for other in ["jessamy", "dunmore", "quill"]:
			if rng.randf() < 0.5:
				_join(other, 2)
		if rng.randf() < 0.3:
			_truce_all()
		states += 1
		var who := Betrayal.pick()
		picked[who] = int(picked.get(who, 0)) + 1
		var where := "state %d" % i
		if not check(who == fb or who in cands, "%s: picked %s, not a candidate or Bran" % [where, who]):
			continue
		check_eq(Betrayal.pick(), who, "%s: the pick is stable" % where)
		var r := Betrayal.ranking()
		var ids := r.map(func(e): return e["id"])
		for id in ids:
			check(ids.count(id) == 1, "%s: %s ranked twice" % [where, id])
		if who != fb:
			check(Betrayal.eligible(who), "%s: picked someone who can't be offered the deal" % where)
			check(who == ids[0], "%s: picked someone who isn't the top scorer" % where)
			var bran_here: bool = Empire.recruits.has(fb)
			check(not bran_here or Betrayal.score(who) >= Betrayal.threshold(), "%s: below the threshold with Bran around" % where)
			check(not (Relationships.romance_of(who) == "partner" and not Betrayal.home_erased(who)), "%s: a partner with a home betrayed Ash" % where)
		else:
			check(r.is_empty() or int(r[0]["score"]) < Betrayal.threshold(), "%s: Bran's con while %s clears the threshold" % [where, r[0]["id"] if not r.is_empty() else ""])
		# Locking writes exactly one betrayal fate, and it is the pick.
		Betrayal.lock()
		var marked := []
		for id in Empire.relations["fates"]:
			if Betrayal.outcome(str(id)) != "":
				marked.append(str(id))
		check_eq(marked, [who], "%s: exactly one betrayal fate after lock()" % where)
	check(states == 3000, "walked every state")
	for id in cands + [fb]:
		check(int(picked.get(id, 0)) > 0, "%s is picked in some campaign (%s)" % [id, str(picked)])


# ---------------------------------------------------------------- the betrayal itself

func test_lock_and_gestures() -> void:
	_blank_slate()
	_join("ottoline", 1)
	_set_home("ottoline", "erased")
	Empire.day = 77
	check_eq(Betrayal.lock(), "ottoline", "lock picks Ottoline")
	check_eq(Betrayal.outcome("ottoline"), "betrayed", "her fate says so")
	check(Betrayal.away("ottoline"), "Chapter 6 starts one hero short")
	check_eq(int(Empire.relations["betrayal"]["day"]), 77, "the day is kept")
	# Fixing everything afterwards changes nothing: the deal is done.
	_set_home("ottoline", "held")
	Empire.bonds["ottoline"]["rank"] = 5
	check_eq(Betrayal.pick(), "ottoline", "a locked pick no longer follows the campaign")
	check_eq(Betrayal.lock(), "ottoline", "locking again changes nothing")
	check(not Betrayal.resolve("forgive"), "unknown gesture refused")
	check(Betrayal.resolve("let_go"), "let her go")
	check_eq(Betrayal.outcome("ottoline"), "let_go", "fate recorded")
	check(not Betrayal.away("ottoline"), "settled")
	check(not Betrayal.resolve("redeemed"), "a settled betrayal can't be settled twice")
	check(Epilogues.text_for("ottoline").contains("seven"), "her epilogue is the let-go one")


func test_redeemed_epilogue_wins_over_romance() -> void:
	_blank_slate()
	_join("ninefingers", 5)
	Empire.relations["romance"]["ninefingers"] = "partner"
	Empire.relations["partner"] = "ninefingers"
	_set_home("ninefingers", "erased")
	_join("odile", 2)  # unresolved rival
	check_eq(Betrayal.lock(), "ninefingers", "the partner betrays Ash")
	check(Betrayal.resolve("redeemed"), "taken back")
	check(Epilogues.text_for("ninefingers").contains("court-martial"), "the redeemed epilogue, not the wedding")


func test_bran_con() -> void:
	_blank_slate()
	check_eq(Betrayal.lock(), "bran", "nobody else: Bran")
	check(Betrayal.is_con(), "it's a con")
	check_eq(Betrayal.outcome("bran"), "faked", "Bran's fate: faked")
	check(not Betrayal.away("bran"), "Bran never really leaves")
	check(not Betrayal.resolve("redeemed"), "nothing to forgive")
	check(Epilogues.text_for("bran").contains("receipt"), "Bran's con epilogue")
	for id in Betrayal.candidates():
		check_eq(Betrayal.outcome(id), "", "%s untouched" % id)


# ---------------------------------------------------------------- the Blank remembers

func test_erasing_a_province_is_remembered() -> void:
	var p: Dictionary = Empire.territory().find("gallows")
	check_eq(Betrayal.fell_count("gallows"), 0, "a new campaign remembers nothing")
	allow_log("erased|fled")
	Empire._erase(p)
	check_eq(Betrayal.fell_count("gallows"), 1, "Gallows Ferry fell once")
	p["owner"] = "free"  # reclaimed
	check(not Betrayal.home_erased("ottoline"), "back on the map")
	_join("ottoline", 3)
	check("home_reclaimed" in Betrayal.parts("ottoline").map(func(x): return x[0]), "fell and was reclaimed")


func test_state_survives_a_save() -> void:
	_blank_slate()
	_join("odile", 1)
	_set_home("odile", "reclaimed")
	Betrayal.lock()
	var d: Dictionary = JSON.parse_string(JSON.stringify(Empire.to_dict()))
	Empire.from_dict(d)
	check_eq(Betrayal.betrayer(), "odile", "the locked betrayer survives a save")
	check_eq(Betrayal.outcome("odile"), "betrayed", "and so does the fate")
	check_eq(Betrayal.fell_count("oldmill"), 1, "and the Old Mill's fall")


func test_old_save_learns_which_homes_fell() -> void:
	var r: Dictionary = Saves.parse(FileAccess.get_file_as_string(FIXTURE))
	if not check_eq(r["status"], Saves.GOOD, "save from before the betrayal reads"):
		return
	check("20261125_betrayal" in r["migrated"], "the betrayal step ran")
	var fell: Dictionary = r["data"]["empire"]["relations"]["betrayal"]["fell"]
	check(fell.has("oldmill"), "a cleared Reclaim mission proves the Old Mill fell")
	check(fell.has("tithe"), "erased now: the Tithe Road fell")
	check(fell.has("whitewater"), "Whitewater was white from the start")
	check(not fell.has("gallows"), "Gallows Ferry never fell")
	Empire.from_dict(r["data"]["empire"])
	check_eq(Betrayal.betrayer(), "", "nobody has betrayed anyone yet")
	check("home_reclaimed" in Betrayal.parts("odile").map(func(x): return x[0]), "Odile's home counts as once lost")
	check_eq(Betrayal.pick(), "ninefingers", "Daro, with the Tithe Road erased, leads by a mile")
	var again: Dictionary = Saves.parse(JSON.stringify(r["data"]))
	check_eq(again["migrated"], [], "the step runs once")
