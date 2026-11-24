extends RefCounted
## The script export (issue #142): every player-facing string in data/ and scripts/, laid out as a
## readable script, one Markdown file per chapter, for proofreading and continuity checks.
## Run tools/export_script.sh (writes build/script/*.md); tests/test_script_export.gd checks that
## nothing the game shows is left out. Rules for what counts as text are the localisation ones
## (scripts/loc.gd, tools/loc_scan.gd), so the export and the translators' .pot see the same strings.
##
## Files:
##   act1.md     prologue, Chapter 1 and Act 1: story, missions, Marches recruits, bonds, codex...
##   ch2.md      Chapter 2 (the Abbey, the north)
##   later.md    text for chapters not written yet (other regions, the betrayal, epilogues)
##   anytime.md  text not tied to a chapter: items, skills, buildings, help, combat barks...
##   ui.md       text in scripts/ (menus, HUD, prompts, notices)
##
## A string's chapter is the latest chapter of any id on its way down the data (a talk, mission,
## province, region, recruit, faction) or in the conditions that unlock it. CHAPTER_ORDER lists them.

const Scan := preload("res://tools/loc_scan.gd")

const CHAPTER_ORDER := ["act1", "ch2", "later"]
const TITLES := {
	"act1": "Act 1: prologue, Chapter 1 (No Such Person) and the rest of Act 1 (The Unregistered Town)",
	"ch2": "Chapter 2: The Copying Monks",
	"later": "Later chapters: regions, the betrayal and epilogues not reached yet",
	"anytime": "Any chapter: items, skills, buildings, help, combat barks and other system text",
	"ui": "Interface text from scripts/",
}
## A region's "chapter" number (data/provinces.json) -> export chapter. A province takes its region's.
const CHAPTER_NUMBER := {1: "act1", 2: "ch2"}
## Story chapter keys (goals' "chapter", journal chapters) -> export chapter.
const STORY_CHAPTER := {"prologue": "act1", "ch1": "act1", "act1": "act1", "ch2": "ch2"}
## Talk id prefixes, for talks no table points at (boss talks are keyed by boss id).
const PREFIX_CHAPTER := {
	"ch1_": "act1", "act1_": "act1", "meadow_": "act1", "auditor_": "act1",
	"ch2_": "ch2", "abbot_": "ch2", "betrayal_": "later",
}
## Whole files that belong to one chapter.
const FILE_CHAPTER := {"epilogues.json": "later", "betrayal.json": "later"}
## Files the game never shows (see tests/test_loc.gd).
const DEV_ONLY := ["placeholders.json"]
## Read first, in this order; the rest follow alphabetically.
const FILE_ORDER := ["story.json", "missions.json", "dialogue.json", "personal.json", "recruits.json",
	"bonds.json", "relationships.json", "journal.json", "factions.json", "provinces.json", "expeditions.json"]
## Keys whose values are conditions: ids in them move the text to their chapter.
const COND_KEYS := ["when", "needs", "gate", "unlock", "show", "requires"]
## Fields of a dictionary that name what it belongs to.
const OWNER_KEYS := ["id", "province", "region", "who", "chapter", "talk", "intro", "faction", "node", "mission", "job", "enemy"]

var ids := {}  # id -> chapter
## chapter -> [{file, group, label, speaker, text}]
var records := {}
var all_texts := {}  # every exported string (for the coverage test)


func build() -> Dictionary:
	ids.clear()
	records.clear()
	all_texts.clear()
	for c in CHAPTER_ORDER + ["anytime", "ui"]:
		records[c] = []
	var empire = Engine.get_main_loop().root.get_node_or_null("Empire")
	if empire != null:  # speaker name tags fall back to the recruit's short name, as in the game
		empire._load_recruit_data()
	var data := {}
	for f in _data_files():
		data[f] = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))
	_learn_ids(data)
	for f in _ordered(data.keys()):
		_walk(data[f], f, "", [], "", FILE_CHAPTER.get(f, ""), "")
	_scripts()
	var out := {}
	for c in records:
		out[c] = _markdown(c)
	return out


## Writes every chapter file into dir. Returns {file name: number of strings}.
func write(dir: String) -> Dictionary:
	var md := build()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir)
	var counts := {}
	for c in md:
		var f := FileAccess.open(dir.path_join(c + ".md"), FileAccess.WRITE)
		f.store_string(md[c])
		counts[c + ".md"] = records[c].size()
	return counts


func _data_files() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://data/"):
		if f.ends_with(".json") and not f in DEV_ONLY:
			out.append(f)
	return out


func _ordered(files: Array) -> Array:
	var out := []
	for f in FILE_ORDER:
		if f in files:
			out.append(f)
	var rest := files.filter(func(f): return not f in FILE_ORDER)
	rest.sort()
	return out + rest


static func rank(c: String) -> int:
	return CHAPTER_ORDER.find(c)


static func _earliest(a: String, b: String) -> String:
	if a == "":
		return b
	return a if rank(a) <= rank(b) else b


static func later_of(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	return a if rank(a) >= rank(b) else b


# ---------------------------------------------------------------- which chapter an id belongs to

func _learn_ids(data: Dictionary) -> void:
	var regions := by_id(data["provinces.json"].get("regions", []))
	for r in regions:
		ids[r] = CHAPTER_NUMBER.get(int(regions[r].get("chapter", 0)), "later")
	var provs := by_id(data["provinces.json"]["provinces"])
	for p in provs:
		ids[p] = ids.get(provs[p].get("region", ""), "later")
	for k in STORY_CHAPTER:
		ids[k] = STORY_CHAPTER[k]
	# factions: the earliest chapter they hold land in
	for f in by_id(data["factions.json"]["factions"]):
		var best := ""
		for p in provs:
			if provs[p].get("owner", "") == f:
				var c: String = ids[p]
				best = c if best == "" or rank(c) < rank(best) else best
		ids[f] = best if best != "" else "act1"
	# missions: their province, unless the story or the betrayal places them
	var enemies := {}
	for m in data["missions.json"]["missions"]:
		var mid: String = m.get("id", "")
		var c: String = _prefix(mid)
		if c == "":
			c = ids.get(m.get("province", ""), "act1")
		ids[mid] = c
		if m.has("intro"):
			ids[m["intro"]] = c
		if typeof(m.get("enemies")) == TYPE_DICTIONARY:  # an enemy kind first meets you in its earliest mission
			for e in m["enemies"]:
				enemies[e] = _earliest(enemies.get(e, ""), c)
		if typeof(m.get("map")) == TYPE_STRING:  # area banter is keyed by map name
			ids[m["map"].get_file().get_basename()] = _earliest(ids.get(m["map"].get_file().get_basename(), ""), c)
	for e in enemies:
		if not ids.has(e):
			ids[e] = enemies[e]
	# story talks: the beat or prefix that plays them
	for t in data["story.json"]["talks"]:
		ids[t] = _prefix(t) if _prefix(t) != "" else ids.get(t, "act1")
	for b in data["story.json"]["beats"]:
		if b.has("talk") and _prefix(b["talk"]) == "":
			ids[b["talk"]] = _cond_chapter(b.get("when", {}))
	for t in data["betrayal.json"]["talks"]:
		ids[t] = "later"
	# expedition jobs: their province
	for j in data["expeditions.json"]["jobs"]:
		if typeof(j) == TYPE_DICTIONARY and j.has("id"):
			ids[j["id"]] = ids.get(j.get("province", ""), "act1")
	# recruits: when they can join
	var rec := by_id(data["recruits.json"]["recruits"])
	for pass_n in 2:  # bond joins name another recruit
		for r in rec:
			ids[r] = _join_chapter(rec[r].get("join"), data)
	for r in data["dialogue.json"]["first_talk"]:
		ids[data["dialogue.json"]["first_talk"][r]] = ids.get(r, "act1")
	for t in data["personal.json"]["talks"]:
		var who: String = t.trim_prefix("personal_").get_slice("_", 0)
		ids[t] = later_of(ids.get(who, "act1"), "")
	for m in data["personal.json"]["missions"]:
		ids[m["id"]] = later_of(ids.get(m.get("who", ""), "act1"), ids.get(m.get("province", ""), ""))


## {id: entry} from either a dictionary keyed by id or an array of entries with an "id".
static func by_id(v) -> Dictionary:
	if typeof(v) == TYPE_DICTIONARY:
		return v
	var out := {}
	for x in v:
		if typeof(x) == TYPE_DICTIONARY and x.has("id"):
			out[x["id"]] = x
	return out


func _prefix(id: String) -> String:
	for p in PREFIX_CHAPTER:
		if id.begins_with(p):
			return PREFIX_CHAPTER[p]
	return ""


func _join_chapter(join, data: Dictionary) -> String:
	if typeof(join) != TYPE_DICTIONARY:
		return "act1"
	match join.get("type", ""):
		"claim":
			return ids.get(join.get("province", ""), "act1")
		"standing":
			return ids.get(join.get("faction", ""), "act1")
		"story":
			return ids.get(join.get("mission", ""), "act1")
		"rescue":
			return ids.get(join.get("job", ""), "act1")
		"bond":
			return ids.get(join.get("who", ""), "act1")
	return "act1"


## The latest chapter named anywhere in a condition (seen/cleared/joined lists, governs, standing...).
func _cond_chapter(v) -> String:
	var c := ""
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				if ids.has(str(k)):
					c = later_of(c, ids[str(k)])
				c = later_of(c, _cond_chapter(v[k]))
		TYPE_ARRAY:
			for x in v:
				c = later_of(c, _cond_chapter(x))
		TYPE_STRING:
			if ids.has(v):
				c = ids[v]
	return c


func _own_chapter(d: Dictionary) -> String:
	var c := ""
	for k in OWNER_KEYS:
		var v = d.get(k)
		if typeof(v) == TYPE_STRING and ids.has(v):
			c = later_of(c, ids[v])
	if typeof(d.get("ids")) == TYPE_ARRAY:  # relationship pairs
		for x in d["ids"]:
			c = later_of(c, ids.get(str(x), ""))
	for k in COND_KEYS:
		if d.has(k):
			c = later_of(c, _cond_chapter(d[k]))
	return c


# ---------------------------------------------------------------- walking the data

## Mirrors Loc._visit (the loader), keeping the path, the speaker and the chapter.
## group: the heading a string sits under ("talks / ch1_arrest").
func _walk(v, file: String, mode: String, path: Array, group: String, chapter: String, label: String) -> void:
	match typeof(v):
		TYPE_DICTIONARY:
			var here := later_of(chapter, _own_chapter(v))
			if v.has("id") and typeof(v["id"]) == TYPE_STRING and group.count(" / ") < 1:
				group = (group + " / " if group != "" else "") + v["id"]
			for k in v.keys():
				var ks := str(k)
				var m := Loc.key_mode(ks, file) if mode != "voices" else "lines"
				var c := later_of(here, ids.get(ks, _prefix(ks)))
				var g := group
				if g.count(" / ") < 1 and typeof(v[k]) in [TYPE_DICTIONARY, TYPE_ARRAY] and m == "" and mode == "":
					g = (g + " / " if g != "" else "") + ks
				var spk := ks if mode == "voices" else ""
				_walk(v[k], file, m, path + [ks], g, c, spk if spk != "" else ks)
		TYPE_ARRAY:
			if mode == "lines" and Loc.is_line(v):
				_add(file, group, chapter, "line", v[0], v[1])
				return
			for x in v:
				_walk(x, file, mode, path, group, chapter, label)
		TYPE_STRING:
			if (mode == "text" or mode == "lines") and v.strip_edges() != "":
				var spk := label if mode == "lines" and label != "" and not label in Loc.LINE_KEYS else ""
				_add(file, group, chapter, label if spk == "" else "line", spk, v)


func _add(file: String, group: String, chapter: String, label: String, speaker: String, text: String) -> void:
	var c := chapter if chapter != "" else "anytime"
	records[c].append({"file": file, "group": group, "label": label, "speaker": speaker, "text": text})
	all_texts[text] = true


func _scripts() -> void:
	var scan := Scan.new()
	var call_re := RegEx.create_from_string(load("res://tools/extract_strings.gd").CALL_RE)
	var files := Array(DirAccess.get_files_at("res://scripts/"))
	files.sort()
	for f in files:
		if not f.ends_with(".gd"):
			continue
		var path: String = "res://scripts/" + f
		var seen := {}
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for n in lines.size():
			if lines[n].strip_edges().begins_with("#"):
				continue
			for m in call_re.search_all(lines[n]):
				var s: String = m.get_string(2)
				s = s.substr(1, s.length() - 2).c_unescape()
				_ui(f, n + 1, s, seen)
				if m.get_string(1) in ["tr_n", "Loc.n"] and m.get_string(3) != "":
					var p: String = m.get_string(3)
					_ui(f, n + 1, p.substr(1, p.length() - 2).c_unescape(), seen)
		for t in scan.script_texts(path):
			_ui(f, t["line"], t["text"], seen)


func _ui(file: String, line: int, text: String, seen: Dictionary) -> void:
	if text.strip_edges() == "" or seen.has(text):
		return
	seen[text] = true
	records["ui"].append({"file": "scripts/" + file, "group": "", "label": str(line), "speaker": "", "text": text})
	all_texts[text] = true


# ---------------------------------------------------------------- writing

func _markdown(c: String) -> String:
	var s := "# Last Ink script: %s\n\n" % TITLES[c]
	s += "Generated by tools/export_script.sh from data/ and scripts/ (issue #142). Do not edit: fix the text at the source shown in each heading.\n"
	s += "%d strings. Lines read as **Speaker:** text; *narration* is in italics; other fields show their key.\n" % records[c].size()
	var file := ""
	var group := "\t"
	for r in records[c]:
		if r["file"] != file:
			file = r["file"]
			group = "\t"
			s += "\n\n## %s\n" % file
		if r["group"] != group:
			group = r["group"]
			if group != "":
				s += "\n### %s\n\n" % group
			else:
				s += "\n"
		var t: String = r["text"].replace("\n", " / ")
		if c == "ui":
			s += "- `%s` %s\n" % [r["label"], t]
		elif r["label"] == "line":
			if r["speaker"] == "":
				s += "*%s*\n\n" % t
			else:
				s += "**%s:** %s\n\n" % [Dialogue.display_name(r["speaker"]), t]
		else:
			s += "- %s: %s\n" % [r["label"], t]
	return s
