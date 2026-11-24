class_name Help
extends RefCounted
## Onboarding and in-game help (issue #115). The words live in data/help.json (see its _comment);
## this file decides what plays when. Everything is static, like Dialogue and Story.
##
##   Explainers  a short talk, voiced by whoever fits (Quill for the table, Hild for research,
##               Tobble for bonds...), the first time each Command screen opens. Skippable, and
##               replayable from the Help screen (scripts/help_view.gd) and the codex.
##   Unlocks     in a story campaign the empire switches on a piece at a time over the first Act 1
##               days (Bonds, Expeditions, Research, Diplomacy), each with a story reason. A screen
##               asked for early stays shut and someone says why.
##   Tips        the first surge, the first erased province, the first injury, the first Concord
##               trouble and so on, said once when they first happen.
##
## The talks play on a HelpCard (scripts/help_card.gd) over whatever is on screen; a HelpWatch
## (scripts/help_watch.gd) in town and at the Command Table notices screens opening and things
## happening. What has played is saved with the campaign as Dialogue seen markers ("help:<id>"),
## so no save step is needed. Explainers and tips can be switched off (Settings.tips); unlocks
## always play, since they are the story.

const PATH := "res://data/help.json"
const GROUPS := ["start", "screens", "unlocks", "events", "field"]
const GROUP_NAMES := {"start": "Getting started", "screens": "The Command Table", "unlocks": "New at the table",
	"events": "When things happen", "field": "In the field"}
const KINDS := ["screen", "unlock", "tip", "manual"]
## Screens an explainer or unlock can name, and the host property that holds each one.
const SCREENS := {"roster": "roster_view", "buildings": "buildings_view", "governor": "governor_view",
	"expeditions": "expedition_view", "research": "research_view", "diplomacy": "diplomacy_view",
	"bonds": "bonds_view", "newcomers": "newcomers_view", "gear": "gear_view", "armory": "armory_view",
	"journal": "journal_view", "party": "party_picker", "command": ""}
## Condition keys this file adds to Journal.meets.
const OWN_KEYS := ["any", "flag", "surge", "injured", "trouble", "hungry", "visitor", "bond_ready", "fray_high", "seen_help"]
## Past this day, unlocks already open when a campaign is loaded are marked as told, so an old save
## does not get the whole first week announced at once.
const ONBOARDING_DAYS := 6

static var _data := {}
static var card: Control  # the HelpCard in the running scene (set by the card itself)


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = Loc.load_json(PATH)
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data


static func topics() -> Array:
	return data().get("topics", [])


static func topic(id: String) -> Dictionary:
	for t in topics():
		if t.get("id", "") == id:
			return t
	return {}


static func of_kind(kind: String) -> Array:
	return topics().filter(func(t): return t.get("kind", "") == kind)


## The explainer for a screen ({} if it has none).
static func for_screen(screen: String) -> Dictionary:
	for t in of_kind("screen"):
		if t.get("screen", "") == screen:
			return t
	return {}


# ---------------------------------------------------------------- seen and switched on

static func seen(id: String) -> bool:
	return Dialogue.is_seen("help:" + id)


static func mark(id: String) -> void:
	Dialogue.mark_seen("help:" + id)


## A marker the game sets when something happens that is not kept anywhere else (an erasure).
static func flag(name: String) -> void:
	Dialogue.mark_seen("help:flag:" + name)


static func flagged(name: String) -> bool:
	return Dialogue.is_seen("help:flag:" + name)


## Explainers and tips play in story campaigns while the player has them switched on.
static func tips_on() -> bool:
	return Story.active() and Settings.tips_enabled()


## A card is up: hosts hold their input and their story beats.
static func busy() -> bool:
	return is_instance_valid(card) and card.is_inside_tree() and card.visible


# ---------------------------------------------------------------- paced unlocks

## The unlock topic that holds this screen back ({} when nothing does).
static func unlock_for(screen: String) -> Dictionary:
	for t in of_kind("unlock"):
		if screen in t.get("screens", []):
			return t
	return {}


## Whether a Command screen is open yet. Only story campaigns pace the empire; campaigns from
## before the story, and everything once its condition holds, are open.
static func is_open(screen: String) -> bool:
	if not Story.active():
		return true
	var u := unlock_for(screen)
	return u.is_empty() or meets(u.get("when", {}))


## "from day 3" style words for a locked screen's button, or "" when it is open.
static func locked_note(screen: String) -> String:
	if is_open(screen):
		return ""
	var u := unlock_for(screen)
	var d := _day_of(u.get("when", {}))
	return Loc.t("day %d") % d if d > 0 else Loc.t("not yet")


## The earliest day in a condition (looking inside "any"), or 0.
static func _day_of(c: Dictionary) -> int:
	var best := int(c.get("day", 0))
	for sub in c.get("any", []):
		var d := _day_of(sub)
		if d > 0 and (best == 0 or d < best):
			best = d
	return best


## On loading a campaign past its first week: unlocks that are already open count as told.
static func settle_old_campaign() -> void:
	if not Story.active() or Empire.day < ONBOARDING_DAYS:
		return
	for t in of_kind("unlock"):
		if meets(t.get("when", {})):
			mark(t["id"])


# ---------------------------------------------------------------- conditions

## Journal.meets (Story.meets plus the journal's keys) plus this file's keys (data/help.json _comment).
static func meets(c: Dictionary) -> bool:
	if c.is_empty():
		return true
	if c.has("any"):
		var ok := false
		for sub in c["any"]:
			if meets(sub):
				ok = true
				break
		if not ok:
			return false
	if c.has("flag") and not flagged(str(c["flag"])):
		return false
	if c.has("seen_help") and not seen(str(c["seen_help"])):
		return false
	if c.get("surge", false):
		var s: Dictionary = Empire.surge
		if s.is_empty() or Empire.territory().find(str(s.get("id", ""))).get("owner", "") != "you":
			return false
	if c.get("injured", false) and not Empire.recruits.values().any(func(r): return int(r.get("injured", 0)) > 0):
		return false
	if c.get("trouble", false) and not Empire.diplo_log.any(func(e): return e.get("trouble", false)):
		return false
	if c.get("hungry", false) and not Empire.hungry:
		return false
	if c.get("visitor", false) and Empire.visitors.is_empty():
		return false
	if c.get("bond_ready", false) and Empire.bond_ready_ids().is_empty():
		return false
	if c.has("fray_high"):
		var lim := int(c["fray_high"])
		if not Empire.territory().provinces.any(func(p): return p["owner"] == "you" and int(p["fray"]) >= lim):
			return false
	var rest := c.duplicate()
	for k in OWN_KEYS:
		rest.erase(k)
	return Journal.meets(rest)


## The next unlock or tip due right now ({} for none). Unlocks first: they are the story, and they
## play even with tips switched off. Only while the Command Table is running.
static func due() -> Dictionary:
	if not Story.active() or not Story.command_on():
		return {}
	for t in of_kind("unlock"):
		if not seen(t["id"]) and meets(t.get("when", {})):
			return t
	if not tips_on():
		return {}
	for t in of_kind("tip"):
		if not seen(t["id"]) and meets(t.get("when", {})):
			return t
	return {}


# ---------------------------------------------------------------- voices and words

## Who says it: the first voice on the roster (or a speaker who is not a recruit), else the last listed.
static func voice(t: Dictionary) -> String:
	var vs: Array = t.get("voice", [])
	for v in vs:
		if Empire.recruits.has(v) or (Empire.recruit(v).is_empty() and not Dialogue.speaker_info(v).is_empty()):
			return v
	return str(vs.back()) if not vs.is_empty() else ""


## The talk as dialogue lines [speaker, text, expression], with buttons filled in for the device in use.
## say: "lines" (the topic) or "locked" (an unlock's words for a screen asked for too early).
static func lines(t: Dictionary, say := "lines") -> Array:
	var who := voice(t)
	var raw: Array = t.get(say, [])
	if say == "lines" and who != "" and t.get("alt", {}).has(who) and who != str(t.get("voice", [""])[0]):
		raw = t["alt"][who]
	var out := []
	for l in raw:
		var line: Array = [who, l, ""] if l is String else Dialogue.line(l)
		out.append([line[0], Prompts.fill(str(line[1])), line[2] if line.size() > 2 else ""])
	return out


## Every topic as a codex entry (Journal.codex, category "help"): the words as paragraphs.
static func codex_entries() -> Array:
	var out := []
	for g in GROUPS:
		for t in topics():
			if t.get("group", "") != g:
				continue
			var paras := []
			for l in lines(t):
				paras.append(l[1])
			var who := voice(t)
			out.append({"id": "help_" + str(t["id"]), "cat": "help", "title": str(t.get("title", t["id"])), "unlocked": true,
				"new": false, "paras": paras, "facts": [[Loc.t("Told by"), Dialogue.display_name(who)], [Loc.t("Section"), Loc.t(GROUP_NAMES.get(g, g))]],
				"hint": "", "indent": 0})
	return out


# ---------------------------------------------------------------- playing

## Plays a topic on the scene's card. Marks it seen. Returns false when there is no card or no words.
## under: the screen it plays over, held still until the card closes.
static func play(id: String, under: Node = null) -> bool:
	var t := topic(id)
	if t.is_empty() or not is_instance_valid(card):
		return false
	mark(id)
	return card.show_talk(str(t.get("title", "")), lines(t), under)


## The words for a screen that is not open yet.
static func play_locked(screen: String, under: Node = null) -> bool:
	var u := unlock_for(screen)
	if u.is_empty() or not is_instance_valid(card):
		return false
	var note := locked_note(screen)
	return card.show_talk("%s: %s" % [str(u.get("title", "")).trim_suffix(" open").trim_suffix(" opens"), Loc.t("from %s") % note if note.begins_with("day") else Loc.t("not yet")],
		lines(u, "locked"), under)
