extends "res://tests/test_case.gd"
## The script export (issue #142, tools/script_export.gd): the proofreading files hold every string
## the game can show, and each chapter's text lands in that chapter's file.

const Export := preload("res://tools/script_export.gd")
const Scan := preload("res://tools/loc_scan.gd")

var _md := {}
var _ex: RefCounted


func _export() -> RefCounted:
	if _ex == null:
		_ex = Export.new()
		_md = _ex.build()
	return _ex


## Every data string the loader translates is in the export (same walk as Loc.each_text).
func test_every_data_string_is_exported() -> void:
	var ex := _export()
	var missing := 0
	for f in DirAccess.get_files_at("res://data/"):
		if not f.ends_with(".json") or f in Export.DEV_ONLY:
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + f))
		for s in Scan.new().data_texts(f, parsed):
			if not ex.all_texts.has(s):
				missing += 1
				if missing <= 10:
					check(false, "data/%s: not in the script export: \"%s\"" % [f, str(s).left(70)])
	check(missing == 0, "%d data string(s) missing from the export" % missing)


## Every player-text literal in scripts/ is in ui.md.
func test_every_script_string_is_exported() -> void:
	var ex := _export()
	var missing := 0
	for f in DirAccess.get_files_at("res://scripts/"):
		if not f.ends_with(".gd"):
			continue
		for t in Scan.new().script_texts("res://scripts/" + f):
			if not ex.all_texts.has(t["text"]):
				missing += 1
				if missing <= 10:
					check(false, "scripts/%s:%d not in the export: \"%s\"" % [f, t["line"], str(t["text"]).left(70)])
	check(missing == 0, "%d script string(s) missing from the export" % missing)


## Story text sorts into the right chapter file.
func test_chapters_sort() -> void:
	_export()
	check("### talks / ch1_arrest" in _md["act1"], "Chapter 1's arrest is in act1.md")
	check("### talks / auditor_intro" in _md["act1"], "the Auditor duel is in act1.md")
	check("### talks / gristle_first" in _md["act1"], "an Act 1 recruit's first talk is in act1.md")
	check(not "ch2_bells" in _md["act1"], "Chapter 2 talk not in act1.md")
	check("### talks / ch2_bells" in _md["ch2"], "Chapter 2's bells are in ch2.md")
	check("### talks / abbot_intro" in _md["ch2"], "the Abbot boss talk is in ch2.md")
	check("### talks / betrayal_seed_bran_1" in _md["later"], "betrayal seeds are in later.md")
	check(not "betrayal_" in _md["act1"], "no betrayal text in act1.md")
	check("**Bran:**" in _md["act1"], "speakers show by name")
	check("## scripts/" in _md["ui"] or "scripts/" in _md["ui"], "ui.md lists script text by file")
