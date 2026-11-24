class_name Betrayal
extends RefCounted
## The climax betrayal (issue #186, docs/DESIGN.md section 10 "The betrayal"). Data: data/betrayal.json.
##
## At the end of Chapter 5 the Vacancy offers one companion their erased home back in exchange for Ash.
## Who takes the deal comes from a leverage score: neglect raises it (home erased or once lost, personal
## mission undone, a low bond, a rivalry left to fester, a romance Ash ended), closeness lowers it (bond
## rank 5 or a current romance). The top scorer betrays Ash if they reach the threshold. If nobody does,
## Bran "sells Ash out" as he has promised since the Prologue: a con on the Vacancy, not a real betrayal.
##
## Until the Chapter 5 scene calls lock(), the pick is live and follows the campaign: pick() says who it
## would be today, top() who leads the candidates (Chapter 4 foreshadowing aims at them). lock() fixes it
## for good. Chapter 6 then calls resolve() with Ash's gesture: take them back ("redeemed") or let them
## go ("let_go").
##
## Saved state: Empire.relations["betrayal"] (see fresh()), plus each person's fate "betrayal" field
## (Relationships.fate): "" (nothing happened), "betrayed", "redeemed", "let_go", or "faked" (Bran's con).
## Epilogues read the fate with the "betrayal" condition. Every function here is static.
##
## What the chapters hook in (each is one line of data, so a chapter never touches this script):
##   Ch3 (#29)  Hortense's spy reveal is the decoy: she is never a candidate (tests check it).
##   Ch4 (#30)  a story mission's "on_success": {"betrayal": "foreshadow"} starts the foreshadowing
##              (begin_foreshadowing): the top candidate's banter gets black bars, their heart in town turns
##              grey and talking to them plays their seed talks, Verity's letter about them plays in town
##              (story beat "pick": "letter"), and one Verity plan leans on their home for a few days.
##   Ch5 (#31)  "on_success": {"betrayal": "lock"} fixes the betrayer (lock) and takes them off the roster
##              (their role becomes "away"). Back in Hollowmark the betrayal scene plays (story beat
##              "pick": "scene"): one per candidate, a romance variant for a betraying partner, Bran's con,
##              and the night nobody is left to take the offer.
##   Ch6 (#32)  the betrayer's fight is a story mission on their home ("needs": {"betrayer": id}), offered
##              even when the home is erased: their own kit (scripts/turncoat.gd) in their home written as
##              words (@written maps). Its outro asks Ash's gesture (a dialogue choice with "betrayal":
##              "redeemed" / "let_go", see resolve). Bran's con is paid off by his own mission instead
##              ("on_success": {"betrayal": "con_home"}). Chapter 6 adds its own "after" to these missions.
## Talks, seed lines, letters and the gesture choices are in data/betrayal.json "talks" (merged into the
## dialogue data like data/story.json's).

const FATES := ["betrayed", "redeemed", "let_go", "faked"]
const GESTURES := ["redeemed", "let_go"]
## The locked "betrayer" when nobody was left to take the deal (Bran lost and no candidate on the roster).
const NOBODY := "-"
## The role a betrayer holds while they are gone (Empire.recruits[id]["role"]): off every post and out of town.
const AWAY_ROLE := "away"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/betrayal.json", FileAccess.READ)
		_data = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file()) if f else {}
	return _data


## A new campaign's state. fell: province id -> how many times the Blank erased it. betrayer: the locked
## pick ("" until lock(), NOBODY when nobody was left). day: the day it was locked. foreshadow: the day
## Chapter 4 started the foreshadowing (0 = not yet). aimed: the province Verity's plan leaned on ("" =
## none). con_home: Bran is back from his con.
static func fresh() -> Dictionary:
	return {"fell": {}, "betrayer": "", "day": 0, "foreshadow": 0, "aimed": "", "con_home": false}


## Cleans a saved state up: wrong types are replaced, counts are made whole numbers.
static func from_save(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY:
		return out
	if typeof(d.get("fell")) == TYPE_DICTIONARY:
		for pid in d["fell"]:
			var n := int(d["fell"][pid])
			if n > 0:
				out["fell"][str(pid)] = n
	out["betrayer"] = str(d.get("betrayer", ""))
	out["day"] = int(d.get("day", 0))
	out["foreshadow"] = int(d.get("foreshadow", 0))
	out["aimed"] = str(d.get("aimed", ""))
	out["con_home"] = bool(d.get("con_home", false))
	return out


static func _st() -> Dictionary:
	var rel := Relationships._st()
	if typeof(rel.get("betrayal")) != TYPE_DICTIONARY or not rel["betrayal"].has("fell"):
		rel["betrayal"] = from_save(rel.get("betrayal"))
	return rel["betrayal"]


# ---------------------------------------------------------------- the Blank's history

## The Blank erased a province (Empire._erase calls this).
static func note_fell(province_id: String) -> void:
	var fell: Dictionary = _st()["fell"]
	fell[province_id] = int(fell.get(province_id, 0)) + 1


## How many times a province has been erased.
static func fell_count(province_id: String) -> int:
	return int(_st()["fell"].get(province_id, 0))


# ---------------------------------------------------------------- candidates and scores

## Candidate ids in data order (the tie-break order).
static func candidates() -> Array:
	return data().get("candidates", []).map(func(c): return str(c.get("id", "")))


static func is_candidate(id: String) -> bool:
	return id in candidates()


static func fallback() -> String:
	return str(data().get("fallback", "bran"))


static func threshold() -> int:
	return int(data().get("threshold", 40))


static func weight(key: String) -> int:
	return int(data().get("weights", {}).get(key, 0))


## The candidate's home province id ("" for anyone else).
static func home_of(id: String) -> String:
	for c in data().get("candidates", []):
		if str(c.get("id", "")) == id:
			return str(c.get("home", ""))
	return ""


static func home_erased(id: String) -> bool:
	return Empire.territory().find(home_of(id)).get("owner", "") == "erased"


## Can they be offered the deal at all? On the roster, not lost in the white, and a current partner only
## while their home is erased.
static func eligible(id: String) -> bool:
	if not is_candidate(id) or not Empire.recruits.has(id) or Relationships.was_lost(id):
		return false
	if Relationships.romance_of(id) == "partner" and not home_erased(id):
		return false
	return true


## Why they score what they score: [[weight key, points]], only the parts that apply.
static func parts(id: String) -> Array:
	var out := []
	var home := home_of(id)
	if home_erased(id):
		out.append(["home_erased", weight("home_erased")])
	elif home != "" and fell_count(home) > 0:
		out.append(["home_reclaimed", weight("home_reclaimed")])
	if Empire.personal_job(id) != "" and not Empire.personal_done(id):
		out.append(["personal_locked", weight("personal_locked")] if Empire.personal_lost(id) != "" else ["personal_open", weight("personal_open")])
	var rank := Empire.bond_rank(id)
	if rank <= 1:
		out.append(["bond_low", weight("bond_low")])
	elif rank == 2:
		out.append(["bond_mid", weight("bond_mid")])
	for pr in Relationships.pairs_of(id):
		if pr[0]["kind"] == "rivals" and Empire.recruits.has(pr[1]) and not Relationships.was_lost(pr[1]):
			out.append(["rival", weight("rival")])
			break
	var rom := Relationships.romance_of(id)
	if rom == "ex":
		out.append(["ex", weight("ex")])
	if rank >= 5 or rom == "partner":
		out.append(["close", weight("close")])
	return out


static func score(id: String) -> int:
	var t := 0
	for p in parts(id):
		t += int(p[1])
	return t


## Every eligible candidate, highest score first ({"id", "score", "parts"}); ties keep data order.
static func ranking() -> Array:
	var out := []
	var order := candidates()
	for id in order:
		if eligible(id):
			out.append({"id": id, "score": score(id), "parts": parts(id)})
	out.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return order.find(a["id"]) < order.find(b["id"]))
	return out


## The leading candidate right now, below the threshold or not ("" when nobody is eligible). Chapter 4's
## foreshadowing (redacted banter, the grey heart, Verity's letters, the aimed plan) points at them.
static func top() -> String:
	var r := ranking()
	return str(r[0]["id"]) if not r.is_empty() else ""


## Who would betray Ash if Chapter 5 ended today: always exactly one id. The locked pick once there is
## one. Otherwise the top candidate if they reach the threshold, else Bran's con. If Bran is gone (lost in
## the white or never there), the top candidate takes the deal whatever their score; with nobody at all
## left, it is still Bran's (the Chapter 5 scene has to cover that case: see issue #186).
static func pick() -> String:
	var locked := betrayer()
	if locked != "":
		return locked
	var r := ranking()
	if not r.is_empty() and int(r[0]["score"]) >= threshold():
		return str(r[0]["id"])
	var fb := fallback()
	if Empire.recruits.has(fb) and not Relationships.was_lost(fb):
		return fb
	return str(r[0]["id"]) if not r.is_empty() else fb


## Is the pick Bran's con rather than a real betrayal?
static func is_con(id := "") -> bool:
	return (id if id != "" else pick()) == fallback()


# ---------------------------------------------------------------- the betrayal itself

## The locked betrayer, or "" before the Chapter 5 scene.
static func betrayer() -> String:
	return str(_st()["betrayer"])


static func locked() -> bool:
	return betrayer() != ""


## The Chapter 5 scene: fixes the pick for good and records the fate ("betrayed", or "faked" for Bran).
## Calling it again changes nothing. Returns the betrayer.
##
## The betrayer walks out with the Vacancy: they leave the party and whatever post they held (role
## AWAY_ROLE) until Chapter 6 settles it. With nobody left at all (Bran lost, no candidate on the roster) the
## lock is NOBODY: no fate is written and the "alone" scene plays.
static func lock() -> String:
	var st := _st()
	if str(st["betrayer"]) != "":
		return str(st["betrayer"])
	var id := pick()
	if not Empire.recruits.has(id) or Relationships.was_lost(id):
		st["betrayer"] = NOBODY
		st["day"] = Empire.day
		return NOBODY
	st["betrayer"] = id
	st["day"] = Empire.day
	Relationships.fate(id)["betrayal"] = "faked" if is_con(id) else "betrayed"
	_send_away(id)
	return id


static func _send_away(id: String) -> void:
	if not Empire.recruits.has(id):
		return
	var r: Dictionary = Empire.recruits[id]
	if str(r.get("role", "")) == "expedition":
		return  # out with a squad: they leave from wherever the squad comes home (Empire keeps the role until then)
	r["role"] = AWAY_ROLE
	r["target"] = ""


## Back from the white (taken back, or Bran home from his con): idle in Hollowmark, ready for a post.
static func _bring_home(id: String) -> void:
	if Empire.recruits.has(id) and str(Empire.recruits[id].get("role", "")) == AWAY_ROLE:
		Empire.recruits[id]["role"] = "idle"
		Empire.recruits[id]["target"] = ""


## Chapter 6: Ash's gesture after the betrayer's fight, "redeemed" (taken back) or "let_go". Only for a
## real betrayal that has not been settled yet. Returns true when it was recorded.
static func resolve(gesture: String) -> bool:
	var id := betrayer()
	if id == "" or id == NOBODY or is_con(id) or not gesture in GESTURES or outcome(id) != "betrayed":
		return false
	Relationships.fate(id)["betrayal"] = gesture
	if gesture == "redeemed":
		_bring_home(id)
	return true


## Bran's con is paid off: he walks back out of the white with the receipt (his Chapter 6 mission).
static func con_home() -> bool:
	var id := betrayer()
	if id == "" or not is_con(id) or bool(_st()["con_home"]):
		return false
	_st()["con_home"] = true
	_bring_home(id)
	return true


## Someone's betrayal fate: "", "betrayed", "redeemed", "let_go" or "faked".
static func outcome(id: String) -> String:
	return str(Relationships.fate(id).get("betrayal", ""))


## Away from Ash's side: betrayed and not yet taken back or let go, or Bran gone with the Vacancy on his con
## until his mission brings him home. Chapter 6 starts one hero short.
static func away(id: String) -> bool:
	if id == "" or id != betrayer():
		return false
	if is_con(id):
		return outcome(id) == "faked" and not bool(_st()["con_home"])
	return outcome(id) == "betrayed"


## Gone for good: Ash let them go into the white.
static func gone(id: String) -> bool:
	return id != "" and id == betrayer() and outcome(id) == "let_go"


## The roster line for someone who isn't coming back to their post ("" for anyone else).
static func away_label(id: String) -> String:
	if gone(id):
		return Loc.t("gone into the white")
	if away(id):
		return Loc.t("gone with the Vacancy")
	return ""


# ---------------------------------------------------------------- Chapter 4: the foreshadowing

## Chapter 4 starts the foreshadowing (a story mission's on_success "betrayal": "foreshadow"). Once only.
## Verity's plan leans on the top candidate's home, if they have a home on the map to lean on, so the player
## gets a fair chance to defend it and bring the score down. Returns true the first time.
static func begin_foreshadowing() -> bool:
	var st := _st()
	if int(st["foreshadow"]) > 0 or locked():
		return false
	st["foreshadow"] = maxi(Empire.day, 1)
	var id := top()
	var plan: Dictionary = data().get("plan", {})
	var pid := home_of(id)
	var p := Empire.territory().find(pid)
	if id != "" and not p.is_empty() and str(p.get("owner", "")) != "erased" and not plan.is_empty():
		st["aimed"] = pid
		BlankPlans.add(pid, str(plan.get("label", "")), int(plan.get("per_day", 2)), int(plan.get("days", 6)),
			str(plan.get("counter", "governor")), "betrayal")
		var note := str(plan.get("notice", "%s"))
		Empire.notice.emit(note % [p.get("name", pid), Empire.short_name(id)] if note.count("%s") >= 2 else note % p.get("name", pid), true)
	return true


## Is the foreshadowing on (from Chapter 4 until the Chapter 5 scene)?
static func foreshadowing() -> bool:
	return int(_st()["foreshadow"]) > 0 and not locked()


## Days since the foreshadowing started (0 before).
static func foreshadow_days() -> int:
	var f := int(_st()["foreshadow"])
	return maxi(Empire.day - f, 0) if f > 0 else 0


## Marked by the foreshadowing: the top candidate while it runs. Their banter gets black bars and their heart
## turns grey. It follows the campaign: fix their home and it can move to someone else, or go away.
static func marked(id: String) -> bool:
	return id != "" and foreshadowing() and id == top()


## The marked person's next seed talk ("" when none is due): a few days apart, in data order.
static func seed_talk(id: String) -> String:
	if not marked(id) and not (id == fallback() and foreshadowing() and is_con()):
		return ""
	var gap := int(data().get("seed_gap", 3))
	var n := 0
	for t in data().get("seeds", {}).get(id, []):
		if foreshadow_days() < n * gap:
			return ""
		if not Dialogue.is_seen("talk:" + str(t)):
			return str(t)
		n += 1
	return ""


## Black bars over a line from a marked speaker: [[word]] around one or two longer words, the same words
## every time for the same line. Lines that already carry bars are left alone.
static func redact(text: String) -> String:
	if text.contains("[["):
		return text
	var words := text.split(" ", false)
	var picks := []
	for i in words.size():
		var core := (words[i] as String).rstrip(".,!?;:'\"").lstrip("'\"")
		if core.length() >= 4 and not core.contains("{"):
			picks.append(i)
	if picks.is_empty():
		return text
	var h := absi(hash(text))
	var chosen := [picks[h % picks.size()]]
	if picks.size() >= 5:
		var second: int = picks[(h / 7) % picks.size()]
		if second != chosen[0]:
			chosen.append(second)
	for i in chosen:
		var w: String = words[i]
		var core := w.rstrip(".,!?;:'\"").lstrip("'\"")
		var at := w.find(core)
		words[i] = w.substr(0, at) + "[[" + core + "]]" + w.substr(at + core.length())
	return " ".join(words)


# ---------------------------------------------------------------- story beats (data/story.json "pick")

## The talk a story beat with "pick" plays right now ("" for none). letter: Verity's letter about the marked
## candidate, once per campaign. scene: the Chapter 5 betrayal scene, once the betrayer is locked.
static func beat_talk(kind: String) -> String:
	var talks: Dictionary = data().get("talks", {})
	match kind:
		"letter":
			for k in talks:
				if str(k).begins_with("betrayal_letter_") and Dialogue.is_seen("talk:" + str(k)):
					return ""
			var id := top()
			return "betrayal_letter_" + id if foreshadowing() and talks.has("betrayal_letter_" + id) else ""
		"scene":
			return scene_talk()
	return ""


## The Chapter 5 betrayal scene for the locked betrayer ("" before the lock): betrayal_<id>, or
## betrayal_<id>_partner for a betraying romance partner, betrayal_bran for the con, betrayal_alone when
## nobody was left.
static func scene_talk() -> String:
	var id := betrayer()
	if id == "":
		return ""
	if id == NOBODY:
		return "betrayal_alone"
	var talks: Dictionary = data().get("talks", {})
	if Relationships.romance_of(id) == "partner" and talks.has("betrayal_%s_partner" % id):
		return "betrayal_%s_partner" % id
	return "betrayal_" + id


## A dialogue choice's "betrayal" effect (dialogue_box.gd calls it when Ash picks): the Chapter 6 gesture.
static func choose(effect: String) -> void:
	if effect in GESTURES:
		resolve(effect)


## Story conditions (Story.blocker reads these keys). Returns "" when they hold.
##   betrayal: "foreshadow" | "locked" | "away" | "settled"   the stage the betrayal is at
##   betrayer: id       the locked betrayer is this person     betrayal_top: id   the marked candidate
static func blocker(c: Dictionary) -> String:
	var not_yet := Loc.t("the story is not there yet")
	if c.has("betrayal"):
		var id := betrayer()
		match str(c["betrayal"]):
			"foreshadow":
				if not foreshadowing():
					return not_yet
			"locked":
				if not locked():
					return not_yet
			"away":
				if not away(id):
					return not_yet
			"settled":
				if not locked() or away(id):
					return not_yet
			_:
				return not_yet
	if c.has("betrayer") and (betrayer() != str(c["betrayer"]) or not away(betrayer())):
		return not_yet
	if c.has("betrayal_top") and not marked(str(c["betrayal_top"])):
		return not_yet
	return ""
