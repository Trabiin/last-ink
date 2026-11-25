extends "res://tests/test_case.gd"
## Ash's gestures (data/gestures.json, scripts/stance.gd): choices that carry effects, add up to a lean, and come
## back later (Bran's name for Ash, town chatter, Verity's letter, Morrow's letters, the epilogues).

const HUB := "res://scenes/hub.tscn"
const BOX := preload("res://scripts/dialogue_box.gd")

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


func _raw_lines(talk: String) -> Array:
	var t = Dialogue.raw_talk(talk)
	return t.get("lines", []) if typeof(t) == TYPE_DICTIONARY else t


func _text(l) -> String:
	return str(l.get("text", "")) if typeof(l) == TYPE_DICTIONARY else str(l[1])


## Pick option i in a talk the way the dialogue box does.
func _choose(talk: String, i: int) -> void:
	var opts := Dialogue.talk_choice(talk)
	Dialogue.make_choice(talk, i, opts[i])


func _join(id: String) -> void:
	Empire.recruits[id] = {"role": "idle", "target": "", "injured": 0}


# ---------------------------------------------------------------- data

## Every gesture, overlay and insert points at a real talk and line, and every option is well formed.
func test_data_is_well_formed() -> void:
	var d := Stance.data()
	var factions := []
	for f in Empire.faction_data:
		factions.append(f)
	var talks: Dictionary = Dialogue.data()["talks"]
	var mine := 0
	for id in d["choices"]:
		check(talks.has(id), "gesture for an unknown talk: %s" % id)
		var t = Dialogue.raw_talk(id)
		check(not (typeof(t) == TYPE_DICTIONARY and t.has("choice")), "%s has a choice of its own; put the effects in overlays" % id)
		var g: Dictionary = d["choices"][id]
		var raw := _raw_lines(id)
		var at := int(g.get("at", -1))
		var line := raw.size() - 1 if at < 0 else at
		check(line < raw.size(), "%s: choice after line %d of %d" % [id, at, raw.size()])
		if g.has("anchor") and line < raw.size():
			check(_text(raw[line]).contains(str(g["anchor"])), "%s: the choice should follow '%s', but line %d reads '%s'" % [id, g["anchor"], line, _text(raw[line]).left(50)])
		check(g.get("choice", []).size() >= 2 and g.get("choice", []).size() <= 3, "%s: two or three gestures" % id)
		mine += 1
	for id in d["overlays"]:
		var own = Dialogue.raw_talk(id)
		check(typeof(own) == TYPE_DICTIONARY and own.get("choice", []).size() == (d["overlays"][id] as Array).size(),
			"overlay for %s: one entry per option of its own choice" % id)
	for id in d["inserts"]:
		check(talks.has(id), "insert into an unknown talk: %s" % id)
		var raw := _raw_lines(id)
		for e in d["inserts"][id]:
			var k := int(e.get("after", raw.size() - 1))
			check(k < raw.size(), "%s: insert after line %d of %d" % [id, k, raw.size()])
			if e.has("anchor") and k < raw.size():
				check(_text(raw[k]).contains(str(e["anchor"])), "%s: insert should follow '%s', line %d reads '%s'" % [id, e["anchor"], k, _text(raw[k]).left(50)])
	var stances := 0
	for id in Stance.choice_talks():
		for o in Dialogue.talk_choice(id):
			var w := "%s '%s'" % [id, o.get("text", "")]
			check(str(o.get("text", "")) != "", "%s: no gesture text" % id)
			if o.has("stance"):
				check(str(o["stance"]) in Stance.STANCES, "%s: unknown stance %s" % [w, o["stance"]])
				stances += 1
			for r in o.get("bond", {}):
				check(Empire.has_bond(str(r)) or Empire.recruit_data.has(str(r)), "%s: bond with unknown %s" % [w, r])
			for f in o.get("standing", {}):
				check(str(f) in factions, "%s: unknown faction %s" % [w, f])
				check(o.has("notice"), "%s: a standing change needs a notice" % w)
			for k in o.get("gain", {}):
				check(Empire.RES_NAMES.has(k), "%s: unknown resource %s" % [w, k])
			for l in Dialogue.lines(o.get("reply", [])):
				check(Dialogue.portrait(l[0], l[2]) != null or l[0] == "" or Dialogue.is_letter(l[0]), "%s: %s has no portrait" % [w, l[0]])
	check(mine >= 8, "at least eight gesture choice points of Ash's own (%d)" % mine)
	check(stances >= 24, "every gesture leans somewhere (%d)" % stances)
	for b in d["beats"]:
		check(talks.has(str(b["talk"])), "beat for an unknown talk: %s" % b["talk"])
	for s in Stance.STANCES:
		check(str(d["stances"][s].get("nick", "")) != "", "%s: Bran has a name for it" % s)
		check(not d["stances"][s].get("banter", []).is_empty(), "%s: Bran says the name once" % s)
	var ids := {}
	for c in d["chatter"]:
		check(not ids.has(c["id"]), "chatter id twice: %s" % c["id"])
		ids[c["id"]] = true


## Every gesture fits on its line above the text box, at the largest text size and with the readable font.
func test_gestures_fit_the_box() -> void:
	var font: Font = ThemeDB.fallback_font
	var was := Access.text_size
	for size in [0, Access.TEXT_SIZES.size() - 1]:
		Access.text_size = size
		var width := 640.0 - 24.0 - 40.0 - 44.0
		for id in Stance.choice_talks():
			for o in Dialogue.talk_choice(id):
				var w := font.get_string_size(BOX.gesture_label(o), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(11)).x
				check(w <= width, "%s '%s' is %d px wide at text size %d (room for %d)" % [id, o["text"], w, size, width])
	Access.text_size = was


# ---------------------------------------------------------------- the lean, flags and effects

func test_lean_needs_a_clear_lead() -> void:
	check_eq(Stance.lean(), "", "no lean before any choice")
	check_eq(Stance.nick(), "smudge", "Bran's default")
	_choose("ch1_arrest", 0)  # mercy
	_choose("ch1_breakout_intro", 2)  # mercy
	check_eq(Stance.points()["mercy"], 2, "two mercy points")
	check_eq(Stance.lean(), "", "two points is not a lean yet")
	_choose("ch1_takeover", 0)  # mercy
	check_eq(Stance.lean(), "mercy", "three clear points is")
	check_eq(Stance.nick(), "saint", "and Bran's name follows it")
	check_eq(Dialogue.line(["bran", "Oi, {nick}. {Nick}!"])[1], "Oi, saint. Saint!", "{nick} in any line")
	_choose("act1_writ", 2)  # spite
	_choose("ninefingers_first", 1)  # spite
	check_eq(Stance.lean(), "", "a mix is no lean: a lead of one is not enough")
	check_eq(Stance.nick(), "smudge", "back to smudge")
	check(Stance.flag("agnes_freed") and Stance.flag("coat_given") and Stance.flag("writ_nailed"), "flags from the choices made")
	check(not Stance.flag("morrow_spared"), "and not from the ones not made")
	check(Story.meets({"flag": "coat_given", "not_flag": "morrow_spared", "lean": "none"}), "flags and lean as Story conditions")
	check(not Story.meets({"lean": "any"}), "lean any needs a lean")


func test_effects_land_once() -> void:
	_join("ninefingers")
	_join("gristle")
	var gilt := int(Empire.res["gilt"])
	var b: int = Empire.bond_points("gristle")
	_choose("act1_concord_after", 1)  # step aside for Gristle
	check_eq(Empire.bond_points("gristle"), b + 3, "Gristle's bond")
	check_eq(Stance.points()["spite"], 2, "a big choice weighs two")
	_choose("act1_concord_after", 2)  # changed mind on a replay: the record moves, the effects do not land again
	check_eq(int(Empire.res["gilt"]), gilt, "a replayed choice pays nothing")
	check(Stance.flag("morrow_stripped") and not Stance.flag("morrow_dosed"), "the latest pick is the one remembered")
	Empire.reset()
	var concord: int = Empire.standing_of("concord")
	var renown := int(Empire.res["renown"])
	_choose("ch1_takeover", 1)  # the register down the well
	check_eq(int(Empire.res["renown"]), renown + 2, "renown gained")
	check_eq(Empire.standing_of("concord"), concord - 3, "the Concord minds")
	check(Empire.diplo_log.any(func(e): return str(e.get("text", "")).contains("register")), "and the diplomacy log says why")


## A save keeps the choices, and with them the lean and flags (nothing else to save).
func test_lean_survives_a_save() -> void:
	_choose("ch1_arrest", 2)
	_choose("ch1_breakout_intro", 1)
	_choose("ch1_takeover", 1)
	check_eq(Stance.lean(), "spite", "spite before saving")
	var d: Dictionary = JSON.parse_string(JSON.stringify(Empire.to_dict()))
	Empire.reset()
	check_eq(Stance.lean(), "", "a new game has none")
	Empire.from_dict(d)
	check_eq(Stance.lean(), "spite", "loaded back")
	check(Stance.flag("register_drowned"), "flags too")


# ---------------------------------------------------------------- talks

## A mid-talk gesture stops on its line, the reply plays, then the rest of the talk.
func test_gesture_mid_talk_in_the_box() -> void:
	var box = BOX.new()
	tree.root.add_child(box)
	await frames(2)
	check(box.play("ch1_arrest"), "the arrest plays")
	var raw := _raw_lines("ch1_arrest")
	var total := raw.size()
	for i in 10:
		box._shown = 99999.0
		box._advance()
		if box._choosing:
			break
	check(box._choosing, "Ash is asked")
	check_eq(box._at, 4, "on the clerk's 'Name, please'")
	box._pick(1)  # shrug
	check_eq(Dialogue.choice_made("ch1_arrest"), 1, "remembered")
	check_eq(box._current()[0], "clerk", "the clerk reads the shrug")
	check_eq(box._lines.size(), total + 1, "the reply is spliced in and the rest of the talk is still there")
	check(_text(box._lines[box._lines.size() - 1]) == _text(raw[total - 1]), "the talk still ends where it did")
	box._skip()
	check(not box.visible, "skip after the choice ends the talk")
	# Skip before the choice jumps to it, never past it.
	box.play("ch1_breakout_intro")
	box._skip()
	check(box._choosing and box.visible, "skip stops at the gesture")
	check_eq(box._at, 2, "on Bran's terms")
	box.queue_free()


func test_morrow_scene_and_letter_follow_the_lean() -> void:
	var raw := _raw_lines("act1_concord_after")
	var ls := Dialogue.talk("act1_concord_after")
	check_eq(ls.size(), raw.size() + 2, "Morrow, still in the mud, is spliced on the end")
	check_eq(Dialogue.choice_at("act1_concord_after"), -1, "and the choice comes last")
	var base := _raw_lines("act1_end").size()
	check_eq(Dialogue.talk("act1_end").size(), base + 1, "Verity has a line for an Ash nobody can read")
	check(Dialogue.talk("act1_end")[3][1].contains("Nobody can tell me"), "the undecided letter")
	check_eq(Dialogue.choice_at("act1_end"), 7, "Ash's answer moves down past her extra line")
	for t in ["ch1_arrest", "ch1_breakout_intro", "ch1_takeover"]:
		_choose(t, Dialogue.talk_choice(t).map(func(o): return o.get("stance", "")).find("hard"))
	check_eq(Stance.lean(), "hard", "hard-nosed")
	check(Dialogue.talk("act1_end")[3][1].contains("keep accounts"), "the hard-nosed letter")


func test_morrow_comes_back_in_chapter_two() -> void:
	Story.begin()
	Empire.missions_cleared.append_array(["meadow_prologue", "ch1_breakout", "act1_concord", "auditor_duel"])
	_join("gristle")
	_join("ninefingers")
	for t in ["ch1_arrest", "ch1_takeover", "act1_rumours", "act1_writ", "act1_concord_after", "act1_end", "ch2_bells"]:
		Dialogue.mark_seen("talk:" + t)
	check(Story.next_beat().get("talk", "") != "morrow_letter_1", "no letter without sparing him")
	_choose("act1_concord_after", 0)
	check_eq(Story.next_beat().get("talk", ""), "morrow_letter_1", "spared, he writes once Chapter 2 starts")
	var ins := int(Empire.res["insight"])
	_choose("morrow_letter_1", 0)
	Dialogue.mark_seen("talk:morrow_letter_1")
	check_eq(int(Empire.res["insight"]), ins + 15, "his schedule is worth Insight")
	check(Story.next_beat().get("talk", "") != "morrow_letter_2", "the second letter waits for the Causeway")
	Dialogue.mark_seen("talk:ch2_end")
	Dialogue.mark_seen("talk:ch3_invitation")
	var b := Story.next_beat()
	check_eq(b.get("talk", ""), "morrow_letter_2", "the warning about Gaudin follows the invitation south")
	check(Story.meets(Story.beat_for("morrow_letter_2")["when"]), "its conditions hold")
	check(Dialogue.talk("morrow_letter_2")[1][1].contains("flour"), "he thanks Ash for the flour")
	check(Epilogues.cards().any(func(c): return c["name"] == "Tithe-Captain Morrow" and str(c["text"]).contains("Nothing found")), "his epilogue card")
	# The other two roads get their own Chapter 2 echo.
	for pick in [[1, "morrow_pension"], [2, "morrow_ledger"]]:
		_choose("act1_concord_after", pick[0])
		check(Story.meets(Story.beat_for(pick[1])["when"]), "%s plays on its road" % pick[1])
		check(not Story.meets(Story.beat_for("morrow_letter_1")["when"]), "and the letter does not")


func test_epilogue_town_card_follows_the_lean() -> void:
	var cards := Epilogues.cards()
	check(not cards.is_empty() and cards[cards.size() - 1]["name"] == "Hollowmark", "Hollowmark gets the last card")
	check(str(cards[cards.size() - 1]["text"]).contains("argues"), "an undecided Ash: the town still argues")
	check(not cards.any(func(c): return c["name"] == "Tithe-Captain Morrow"), "no Morrow card without meeting him")
	for t in ["ch1_arrest", "ch1_breakout_intro", "act1_writ"]:
		_choose(t, Dialogue.talk_choice(t).map(func(o): return o.get("stance", "")).find("spite"))
	cards = Epilogues.cards()
	check(str(cards[cards.size() - 1]["text"]).contains("never filed"), "a spiteful Ash: the town never filed")
	_join("tobble")
	Empire.bonds["tobble"] = {"points": Empire.bond_threshold(2), "rank": 2, "talk_day": 0, "personal_done": false}
	check(Epilogues.text_for("tobble").contains("bear"), "Tobble's stories grow: %s" % Epilogues.text_for("tobble").left(40))


# ---------------------------------------------------------------- town

## In the real town: Bran names Ash once the lean settles, and townsfolk talk about what Ash did.
func test_town_names_and_chatter() -> void:
	Story.begin()
	Empire.missions_cleared.append_array(["meadow_prologue", "ch1_breakout"])
	for t in ["meadow_intro", "ch1_arrest", "ch1_breakout_intro", "ch1_takeover", "act1_rumours"]:
		Dialogue.mark_seen("talk:" + t)
	Empire.day = 3
	for t in ["ch1_arrest", "ch1_breakout_intro", "ch1_takeover"]:
		_choose(t, Dialogue.talk_choice(t).map(func(o): return o.get("stance", "")).find("mercy"))
	var hub = await goto(HUB, 20)
	if not check(hub != null and hub.npcs.has("bran"), "Bran stands in town"):
		return
	var chatter: TownChatter = null
	for c in hub.get_children():
		if c is TownChatter:
			chatter = c
	if not check(chatter != null, "the town has its chatter"):
		return
	if hub.dialogue_box.visible:
		hub.dialogue_box._close()
	await frames(3)
	check(Dialogue.is_seen("event:nick_mercy"), "Bran tries out his new name for Ash")
	check(hub.banter.to_save().any(func(l): return str(l[1]).begins_with("Saint.")), "and says it: %s" % str(hub.banter.to_save()))
	hub.banter.queue = []
	hub.banter._cur = []
	var folk: Node2D = null
	for c in hub.entities.get_children():
		if c is Townsfolk:
			folk = c
	if not check(folk != null, "townsfolk on the plaza"):
		return
	folk.set_process(false)
	hub.leader.global_position = folk.global_position + Vector2(10, 0)
	chatter._wait = 0.0
	await frames(3)
	var said: Array = hub.banter.to_save()
	check(said.size() == 1 and said[0][0] == "", "a townsperson is overheard: %s" % str(said))
	var heard := Dialogue.seen.keys().filter(func(k): return str(k).begins_with("chatter:"))
	check_eq(heard.size(), 1, "and marked heard")
	var fits := ["chatter:agnes", "chatter:coat", "chatter:mercy_1", "chatter:mercy_2", "chatter:mercy_3"]
	check(heard.size() == 1 and str(heard[0]) in fits, "about what Ash did, or what Ash is like: %s" % str(heard))
