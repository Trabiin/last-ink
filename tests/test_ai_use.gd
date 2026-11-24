extends "res://tests/test_case.gd"
## AI use statement (issue #164). docs/AI_USE.md is the one public statement; data/ai_use.json holds its
## short version for the in-game credits. These checks keep the two in step and make sure every folder
## under assets/ is in the provenance log, so nothing ships without saying where it came from.
## The docs checks are skipped in exported builds, which don't carry docs/.

const DOC := "res://docs/AI_USE.md"
const DATA := "res://data/ai_use.json"


func _data() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return d if d is Dictionary else {}


## The text of the "### Short version" quote in the doc, joined into one line.
func _doc_short(doc: String) -> String:
	var at := doc.find("### Short version")
	if at < 0:
		return ""
	var parts := []
	var started := false
	for line in doc.substr(at).split("\n"):
		if line.begins_with("> "):
			started = true
			parts.append(line.substr(2).strip_edges())
		elif started:
			break
	return " ".join(parts)


func test_short_statement_is_in_the_credits() -> void:
	var d := _data()
	for key in ["heading", "short", "more"]:
		check(str(d.get(key, "")).length() > 0, "data/ai_use.json: missing %s" % key)
	var lines: Array = load("res://scripts/title.gd").ai_use_lines()
	var text := " ".join(lines)
	check(text.contains(str(d.get("short", "?"))), "credits don't show the short AI statement")
	check(text.contains(str(d.get("more", "?"))), "credits don't link the full statement")
	# One paragraph per line: the credits box wraps by pixels (InkMenu.wrap_px, tested in
	# test_menu_layout), so a longer language reflows instead of being cut at a fixed width (issue #183).
	check(lines.has(str(d.get("short", "?"))), "the short statement is one paragraph, not pre-wrapped")


func test_short_statement_matches_the_doc() -> void:
	if not FileAccess.file_exists(DOC):
		return
	var doc := FileAccess.get_file_as_string(DOC)
	check_eq(_doc_short(doc), str(_data().get("short", "")), "docs/AI_USE.md short version vs data/ai_use.json")


func test_every_asset_folder_is_in_the_provenance_log() -> void:
	if not FileAccess.file_exists(DOC):
		return
	var doc := FileAccess.get_file_as_string(DOC)
	var log_at := doc.find("## 5. Provenance log")
	check(log_at >= 0, "docs/AI_USE.md has no provenance log")
	var table := doc.substr(log_at)
	for dir in DirAccess.get_directories_at("res://assets"):
		check(table.contains("`assets/%s/`" % dir), "provenance log is missing assets/%s/" % dir)
	for sub in ["sprites", "props"]:
		for dir in DirAccess.get_directories_at("res://assets/" + sub):
			if dir.begins_with("_"):
				check(table.contains("`assets/%s/%s/`" % [sub, dir]), "provenance log is missing assets/%s/%s/" % [sub, dir])
