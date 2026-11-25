class_name Stance
extends RefCounted
## Ash's gestures and the lean they add up to (data/gestures.json).
##
## Ash never speaks. At a choice point Ash does something instead ("Hand Morrow the empty strongbox", "Shrug"),
## and the people around read it in their own voices. Each option can carry effects, applied once, the first time
## Ash makes that choice:
##   stance: "mercy" | "hard" | "spite"   and weight: n (default 1), adding to Ash's lean
##   flag: "name" (or a list)             remembered for later scenes (a Story condition: "flag" / "not_flag")
##   bond: {recruit id: n}                standing: {faction id: n} (with "notice", the diplomacy log line)
##   gain: {resource: n}                  Gilt, Supplies, Ink, Renown, Insight (negative pays)
##
## Where the choices come from:
##   - a talk's own "choice" (story.json, betrayal.json...). gestures.json "overlays" adds effects to those by
##     option index, so a story writer can keep the words and this file keeps the consequences.
##   - gestures.json "choices": a choice for a talk that has none, kept here so the story files stay untouched.
##     "at" is the index of the line the choice follows (no "at": after the last line).
## gestures.json "inserts" splices extra lines into a talk when their "when" holds ("after": the index of the line
## they follow; none: the end). That is how Verity's Act 1 letter answers Ash's lean.
## "anchor" (never translated) is a piece of the English text of that line: tests/test_gestures.gd checks it is
## still there, so an edit to a story talk cannot quietly move a choice or an insert onto the wrong line.
##
## Nothing here is saved separately: the choices Ash made live in Dialogue.seen ("choice:<talk>:<i>"), and the lean
## and flags are worked out from them, so old saves need no migration.
##
## The lean shows in Bran's name for Ash ({nick} in any line), in what the townsfolk say as Ash walks past
## (scripts/town_chatter.gd), in Verity's letter and in the epilogues.

const PATH := "res://data/gestures.json"
const STANCES := ["mercy", "hard", "spite"]

static var _data := {}
static var _choice_talks := []  # every talk id with a choice for Ash (built once)


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = Loc.load_json(PATH)
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data


# ---------------------------------------------------------------- the choices

## A talk's choice for Ash with the effects from gestures.json laid over it ([] when it has none).
static func options(talk_id: String) -> Array:
	var t = Dialogue.raw_talk(talk_id)
	var own: Array = t.get("choice", []) if typeof(t) == TYPE_DICTIONARY else []
	if own.is_empty():
		return data().get("choices", {}).get(talk_id, {}).get("choice", [])
	var over: Array = data().get("overlays", {}).get(talk_id, [])
	if over.is_empty():
		return own
	var out := []
	for i in own.size():
		var o: Dictionary = (own[i] as Dictionary).duplicate()
		if i < over.size():
			o.merge(over[i])  # the talk's own words win; the overlay only adds keys it does not have
		out.append(o)
	return out


## The index of the line a talk's choice follows (-1 = after the last line).
static func choice_index(talk_id: String) -> int:
	var t = Dialogue.raw_talk(talk_id)
	if typeof(t) == TYPE_DICTIONARY and t.has("choice"):
		return int(t.get("choice_at", -1))
	return int(data().get("choices", {}).get(talk_id, {}).get("at", -1))


## Every talk with a choice for Ash, from every file.
static func choice_talks() -> Array:
	if _choice_talks.is_empty():
		for id in Dialogue.data().get("talks", {}):
			var t = Dialogue.raw_talk(id)
			if typeof(t) == TYPE_DICTIONARY and t.has("choice"):
				_choice_talks.append(id)
		for id in data().get("choices", {}):
			if not id in _choice_talks:
				_choice_talks.append(id)
	return _choice_talks


## The option Ash picked in a talk ({} if none yet).
static func picked(talk_id: String) -> Dictionary:
	var i := Dialogue.choice_made(talk_id)
	var opts := options(talk_id)
	return opts[i] if i >= 0 and i < opts.size() else {}


## Ash picked an option: its effects land (the first time only; a replayed scene changes nothing).
static func apply(opt: Dictionary, first_time: bool) -> void:
	if not first_time:
		return
	for id in opt.get("bond", {}):
		if Empire.recruits.has(id):
			Empire.bond_gain(str(id), int(opt["bond"][id]), Loc.t("how Ash answered"))
	for fid in opt.get("standing", {}):
		Empire.change_standing(str(fid), int(opt["standing"][fid]), str(opt.get("notice", Loc.t("how Ash answered"))))
	var gains: Dictionary = opt.get("gain", {})
	var parts := []
	for k in gains:
		Empire.gain(str(k), int(gains[k]))
		parts.append("%+d %s" % [int(gains[k]), Loc.t(str(Empire.RES_NAMES.get(k, str(k).capitalize())))])
	if not parts.is_empty():
		Empire.notice.emit(", ".join(parts), false)


# ---------------------------------------------------------------- the lean

## Points toward each stance from every choice Ash has made: {"mercy": n, "hard": n, "spite": n}.
static func points() -> Dictionary:
	var out := {"mercy": 0, "hard": 0, "spite": 0}
	for id in choice_talks():
		var o := picked(id)
		var s := str(o.get("stance", ""))
		if out.has(s):
			out[s] += int(o.get("weight", 1))
	return out


## Ash's lean: "mercy", "hard", "spite", or "" while no stance clearly leads (not enough choices yet, or a mix).
## A stance leads with at least "threshold" points and "lead" more than the next one.
static func lean() -> String:
	var p := points()
	var best := ""
	var top := 0
	var second := 0
	for s in STANCES:
		if p[s] > top:
			second = top
			top = p[s]
			best = s
		elif p[s] > second:
			second = p[s]
	if top < int(data().get("threshold", 3)) or top - second < int(data().get("lead", 2)):
		return ""
	return best


## Whether a choice Ash made set this flag.
static func flag(name: String) -> bool:
	for id in choice_talks():
		var f = picked(id).get("flag", null)
		if f == null:
			continue
		if (typeof(f) == TYPE_ARRAY and name in f) or str(f) == name:
			return true
	return false


## Bran's name for Ash: "smudge" until a lean shows, then the lean's own.
static func nick() -> String:
	var l := lean()
	if l == "":
		return str(data().get("nick", "smudge"))
	return str(data().get("stances", {}).get(l, {}).get("nick", data().get("nick", "smudge")))


## Fills {nick} / {Nick} in a line with Bran's name for Ash.
static func fill(s: String) -> String:
	if not "{nick}" in s and not "{Nick}" in s:
		return s
	var n := nick()
	return s.replace("{nick}", n).replace("{Nick}", n.capitalize())


## Why a Story condition about gestures does not hold ("" when it does). Keys: flag / not_flag (a name or a list),
## lean ("mercy", "hard", "spite", "none" for no clear lean, "any" for some lean).
static func blocker(c: Dictionary) -> String:
	for f in _list(c.get("flag", [])):
		if not flag(str(f)):
			return Loc.t("the story is not there yet")
	for f in _list(c.get("not_flag", [])):
		if flag(str(f)):
			return Loc.t("the story went another way")
	if c.has("lean"):
		var want := str(c["lean"])
		var l := lean()
		if (want == "none" and l != "") or (want == "any" and l == "") or (not want in ["none", "any"] and l != want):
			return Loc.t("the story went another way")
	return ""


static func _list(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else ([] if str(v) == "" else [v])


# ---------------------------------------------------------------- lines spliced into talks

## A talk's lines with the inserts that hold spliced in, and where its choice comes:
## {"lines": [raw lines], "at": index of the line the choice follows, -1 for the last}.
static func splice(talk_id: String, raw: Array) -> Dictionary:
	var choice_line := choice_index(talk_id)
	if choice_line >= raw.size():
		choice_line = -1
	var ins: Array = data().get("inserts", {}).get(talk_id, [])
	var after := {}  # original index -> [lines]
	for e in ins:
		if not Story.meets(e.get("when", {})):
			continue
		var k := int(e.get("after", -1))
		if k < 0 or k >= raw.size():
			k = raw.size() - 1
		if not after.has(k):
			after[k] = []
		after[k].append_array(e.get("lines", []))
	if after.is_empty():
		return {"lines": raw, "at": choice_line}
	var out := []
	var at := -1
	for k in raw.size():
		out.append(raw[k])
		out.append_array(after.get(k, []))
		if k == choice_line:
			at = out.size() - 1  # the choice comes after the lines spliced in behind its line
	return {"lines": out, "at": at}


## The index of the first line whose text holds the piece (-1 if none).
static func find_line(raw: Array, piece: String) -> int:
	for k in raw.size():
		var l = raw[k]
		var text := str(l.get("text", "")) if typeof(l) == TYPE_DICTIONARY else (str(l[1]) if (l as Array).size() > 1 else "")
		if piece in text:
			return k
	return -1


# ---------------------------------------------------------------- town chatter

## Overheard lines that fit the campaign right now: [{"id", "text"}], the ones not heard yet first.
static func chatter() -> Array:
	var fresh := []
	var heard := []
	for c in data().get("chatter", []):
		if not Story.meets(c.get("when", {})):
			continue
		var e := {"id": str(c.get("id", "")), "text": str(c.get("text", ""))}
		if Dialogue.is_seen("chatter:" + e["id"]):
			if c.get("repeat", false):
				heard.append(e)
		else:
			fresh.append(e)
	return fresh if not fresh.is_empty() else heard


## Bran's lines for a lean he has not named yet ([] when he already has, or there is no lean).
static func nick_banter() -> Array:
	var l := lean()
	if l == "" or Dialogue.is_seen("event:nick_" + l):
		return []
	return data().get("stances", {}).get(l, {}).get("banter", [])
