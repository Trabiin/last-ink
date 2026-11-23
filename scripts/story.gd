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
##   standing: {faction id: tier}   at least that standing tier with each faction (issue #28)
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
	for id in c.get("joined", []):
		if not Empire.recruits.has(id):
			return Loc.t("%s has to join first") % Empire.recruit(id).get("name", id)
	if int(Empire.res.get("renown", 0)) < int(c.get("renown", 0)):
		return Loc.t("needs %d Renown") % int(c["renown"])
	if held() < int(c.get("held", 0)):
		return Loc.t("hold %d provinces") % int(c["held"])
	for pid in c.get("owns", []):
		if Empire.territory().find(pid).get("owner", "") != "you":
			return Loc.t("take %s first") % Empire.territory().find(pid).get("name", pid)
	for pid in c.get("governs", []):
		var gp := Empire.territory().find(pid)
		if gp.get("owner", "") != "you":
			return Loc.t("take %s first") % gp.get("name", pid)
		if Empire.governor_of(pid) == "":
			return Loc.t("put a governor in %s") % gp.get("name", pid)
	var want: Dictionary = c.get("standing", {})
	for fid in want:
		if not Empire.at_least(fid, str(want[fid])):
			return Loc.t("needs %s standing with the %s") % [Empire.tier_name(str(want[fid])), Empire.faction(fid).get("short", fid)]
	if Empire.day < int(c.get("day", 0)):
		return Loc.t("not before day %d") % int(c["day"])
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
static func next_beat() -> Dictionary:
	for b in data().get("beats", []):
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
