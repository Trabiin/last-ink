class_name Story
extends RefCounted
## The main story (issue #18): Prologue, Chapter 1 and the Act 1 story beats around the command phase.
##
## The words and the order live in data/story.json (see its _comment). Its talks and speakers are
## merged into Dialogue.data(), so the dialogue box plays them like any other conversation.
##
## Flow:
##   New Game -> Prologue mission (Frayed Meadow) -> Hollowmark: Ash is arrested (ch1_arrest) ->
##   Chapter 1 mission (breakout from the tax office) -> Hollowmark: the takeover (ch1_takeover),
##   and only now do the Command Table and the clock switch on -> Act 1 beats in town as the empire
##   grows (rumours, the Concord's writ, the Auditor's warning) -> The Auditor (#17) -> Verity's
##   letter and the End of Act 1 card.
##
## Everything is static. The story's own state is just which talks were seen (Dialogue.seen, saved
## with the campaign) and which missions were cleared (Empire.missions_cleared), plus one marker,
## "story:on", set when a New Game starts the story. Saves from before the story existed (and the
## title screen's Hollowmark preview) do not have it, so they skip Chapter 1 and keep their table.

const PATH := "res://data/story.json"
const ON := "story:on"
const BREAKOUT := "ch1_breakout"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = Loc.load_json(PATH)
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed
			# The gestures' later payoffs (data/gestures.json "beats", Morrow's letters...) play after the story's own.
			_data["beats"] = _data.get("beats", []) + Stance.data().get("beats", [])
	return _data


## Called by New Game, right after Empire.reset(): this campaign plays the story from the start.
static func begin() -> void:
	Dialogue.mark_seen(ON)


static func active() -> bool:
	return Dialogue.is_seen(ON)


## The Command Table and the clock only switch on once Ash has taken Hollowmark (end of Chapter 1).
static func command_on() -> bool:
	return not active() or Missions.cleared(BREAKOUT)


## Whether every condition holds. Conditions (all optional):
##   active: true       the campaign started with the story on (New Game)
##   cleared: [ids]     missions cleared         not_cleared: [ids]   missions not cleared yet
##   seen: [talk ids]   conversations played     joined: [ids]        recruits on the roster
##   renown: n          at least n Renown        held: n              at least n provinces held
##   owns: [ids]        provinces you hold       day: n               on day n or later
##   governs: [ids]     provinces you hold with a governor posted (issue #28)
##   built: {building id: level}   Hollowmark buildings at that level or higher (issue #190)
##   not_joined: [ids]              recruits not on the roster yet
##   chose: [talk id, i] / not_chose: [talk id, i]   Ash picked (or didn't pick) option i of that talk's choice
##   saved: {group: n} / lost: {group: n}   at least n people of that group got out / were lost (Incidents)
##   incident: {id: state}          an incident's state (Incidents.blocker: open, done, ignored, closed, none)
##   standing: {faction id: tier}   at least that standing tier with each faction (issue #28)
##   not_seen: [talk ids]           conversations not played yet
##   betrayal / betrayer / betrayal_top   the climax betrayal's stage (issue #186, Betrayal.blocker)
##   flag / not_flag: name or [names]   a gesture Ash made set (or did not set) it (data/gestures.json, Stance.blocker)
##   lean: "mercy" | "hard" | "spite" | "none" | "any"   Ash's lean from the gestures so far
static func meets(c: Dictionary) -> bool:
	return blocker(c) == ""


## What is still missing ("" when every condition holds), for the briefing.
static func blocker(c: Dictionary) -> String:
	if c.get("active", false) and not active():
		return Loc.t("only in a story campaign")
	for id in c.get("cleared", []):
		if not Missions.cleared(id):
			var m := Missions.find(id)
			return Loc.t("clear %s first") % m.get("name", id)
	for id in c.get("not_cleared", []):
		if Missions.cleared(id):
			return Loc.t("already done")
	for id in c.get("seen", []):
		if not Dialogue.is_seen("talk:" + id):
			return Loc.t("the story is not there yet")
	for id in c.get("not_seen", []):
		if Dialogue.is_seen("talk:" + id):
			return Loc.t("already done")
	for id in c.get("joined", []):
		if not Empire.recruits.has(id):
			return Loc.t("%s has to join first") % Empire.recruit(id).get("name", id)
	for id in c.get("not_joined", []):
		if Empire.recruits.has(id):
			return Loc.t("already done")
	if int(Empire.res.get("renown", 0)) < int(c.get("renown", 0)):
		return Loc.t("needs %d Renown") % int(c["renown"])
	if held() < int(c.get("held", 0)):
		return Loc.n("hold %d province", "hold %d provinces", int(c["held"])) % int(c["held"])
	for pid in c.get("owns", []):
		if Empire.territory().find(pid).get("owner", "") != "you":
			return Loc.t("take %s first") % Empire.territory().find(pid).get("name", pid)
	for pid in c.get("governs", []):
		var gp := Empire.territory().find(pid)
		if gp.get("owner", "") != "you":
			return Loc.t("take %s first") % gp.get("name", pid)
		if Empire.governor_of(pid) == "":
			return Loc.t("put a governor in %s") % gp.get("name", pid)
	var built: Dictionary = c.get("built", {})
	for bid in built:
		if Empire.level_of(bid) < int(built[bid]):
			var bname: String = Empire.building(bid).get("name", bid)
			if int(built[bid]) <= 1:
				return Loc.t("build the %s") % bname
			return Loc.t("raise the %s to level %d") % [bname, int(built[bid])]
	var want: Dictionary = c.get("standing", {})
	for fid in want:
		if not Empire.at_least(fid, str(want[fid])):
			return Loc.t("needs %s standing with the %s") % [Empire.tier_name(str(want[fid])), Empire.faction(fid).get("short", fid)]
	# A choice Ash made in a talk (Dialogue.choice_made): [talk id, option index].
	var ch: Array = c.get("chose", [])
	if ch.size() == 2 and Dialogue.choice_made(str(ch[0])) != int(ch[1]):
		return Loc.t("the story is not there yet")
	var nch: Array = c.get("not_chose", [])
	if nch.size() == 2 and Dialogue.choice_made(str(nch[0])) == int(nch[1]):
		return Loc.t("the story is not there yet")
	# People got out, or lost, on missions (scripts/incidents.gd): {"group": at least n}.
	var sv: Dictionary = c.get("saved", {})
	for g in sv:
		if int(Incidents.people(str(g))["saved"]) < int(sv[g]):
			return Loc.t("the story is not there yet")
	var ls: Dictionary = c.get("lost", {})
	for g in ls:
		if int(Incidents.people(str(g))["lost"]) < int(ls[g]):
			return Loc.t("the story is not there yet")
	if c.has("incident"):
		var why := Incidents.blocker(c["incident"])
		if why != "":
			return why
	if Empire.day < int(c.get("day", 0)):
		return Loc.t("not before day %d") % int(c["day"])
	if c.has("flag") or c.has("not_flag") or c.has("lean"):  # Ash's gestures (data/gestures.json, Stance.blocker)
		var why := Stance.blocker(c)
		if why != "":
			return why
	if c.has("betrayal") or c.has("betrayer") or c.has("betrayal_top"):
		return Betrayal.blocker(c)
	return ""


static func held() -> int:
	var n := 0
	for p in Empire.territory().provinces:
		if p.get("owner", "") == "you":
			n += 1
	return n


# ---------------------------------------------------------------- beats in Hollowmark

## The beat to play in town right now ({} for none): the first one whose conditions hold and whose
## talk has not been seen (beats with repeat: true play every time their conditions hold).
## A beat with "pick" instead of "talk" asks the betrayal which talk it is (Betrayal.beat_talk, issue #186).
static func next_beat() -> Dictionary:
	for b0 in data().get("beats", []) + Incidents.beats():  # requests' asks and aftermaths after the story's own
		var b: Dictionary = b0
		if b.has("pick"):
			b = b.duplicate()
			b["talk"] = Betrayal.beat_talk(str(b["pick"]))
		var talk: String = b.get("talk", "")
		if talk == "" or not meets(b.get("when", {})):
			continue
		if b.get("repeat", false) or not Dialogue.is_seen("talk:" + talk):
			return b
	return {}


static func beat_for(talk: String) -> Dictionary:
	for b in data().get("beats", []):
		if b.get("talk", "") == talk:
			return b
	return {}


# ---------------------------------------------------------------- the Act 1 checklist

## [{"text", "hint", "done"}] for the goals that are showing.
static func goals() -> Array:
	var out := []
	for g in data().get("goals", []):
		if g.has("show") and not meets(g["show"]):
			continue
		out.append({"text": g.get("text", ""), "hint": g.get("hint", ""), "done": meets(g.get("done", {}))})
	return out


## The first goal not done yet ({} when everything showing is done).
static func current_goal() -> Dictionary:
	for g in goals():
		if not g["done"]:
			return g
	return {}
