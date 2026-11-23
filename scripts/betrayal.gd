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

const FATES := ["betrayed", "redeemed", "let_go", "faked"]
const GESTURES := ["redeemed", "let_go"]

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/betrayal.json", FileAccess.READ)
		_data = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file()) if f else {}
	return _data


## A new campaign's state. fell: province id -> how many times the Blank erased it. betrayer: the locked
## pick ("" until lock()). day: the day it was locked.
static func fresh() -> Dictionary:
	return {"fell": {}, "betrayer": "", "day": 0}


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
static func lock() -> String:
	var st := _st()
	if str(st["betrayer"]) != "":
		return str(st["betrayer"])
	var id := pick()
	st["betrayer"] = id
	st["day"] = Empire.day
	Relationships.fate(id)["betrayal"] = "faked" if is_con(id) else "betrayed"
	return id


## Chapter 6: Ash's gesture after the betrayer's fight, "redeemed" (taken back) or "let_go". Only for a
## real betrayal that has not been settled yet. Returns true when it was recorded.
static func resolve(gesture: String) -> bool:
	var id := betrayer()
	if id == "" or is_con(id) or not gesture in GESTURES or outcome(id) != "betrayed":
		return false
	Relationships.fate(id)["betrayal"] = gesture
	return true


## Someone's betrayal fate: "", "betrayed", "redeemed", "let_go" or "faked".
static func outcome(id: String) -> String:
	return str(Relationships.fate(id).get("betrayal", ""))


## Away from Ash's side: betrayed and not yet taken back or let go. Chapter 6 starts one hero short.
static func away(id: String) -> bool:
	return id != "" and id == betrayer() and outcome(id) == "betrayed"
