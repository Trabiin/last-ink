extends "res://tests/test_case.gd"
## Tracked placeholder art (issue #28, Ojon 2026-11-23): data/placeholders.json lists every stand-in in the game.
## This prints the list on every run, so nobody forgets it, and checks that each entry is real: the stand-in is
## on disk at the exact path the final art will use (so the swap is dropping a file in), the game actually points
## at that id, and the brief for the art batch is written. With RELEASE_CHECK=1 in the environment it also fails
## while any entry is left, like tools/release_check.sh (issue #118).

const PATH := "res://data/placeholders.json"
const KINDS := ["sprite", "portrait", "prop", "tiles", "icon", "music", "cg"]


func _entries() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d.get("placeholders", []) if typeof(d) == TYPE_DICTIONARY else []


func test_list_is_printed() -> void:
	var list := _entries()
	var by_kind := {}
	for e in list:
		by_kind[e["kind"]] = int(by_kind.get(e["kind"], 0)) + 1
	print("PLACEHOLDERS: %d stand-ins still in the game (data/placeholders.json, release check #118): %s" % [list.size(), by_kind])
	for e in list:
		print("  %s -> %s" % [e["id"], e["path"]])
	if OS.get_environment("RELEASE_CHECK") == "1":
		check(list.is_empty(), "release check: %d placeholders left in data/placeholders.json" % list.size())


func test_entries_are_complete() -> void:
	var seen := {}
	for e in _entries():
		var id := str(e.get("id", ""))
		check(not seen.has(id), "placeholder %s is listed twice" % id)
		seen[id] = true
		var kind := str(e.get("kind", ""))
		check(kind in KINDS, "%s: unknown kind %s" % [id, kind])
		check(id.begins_with(kind + ":") and id.length() > kind.length() + 1, "%s: id must be <kind>:<art id>" % id)
		check(str(e.get("path", "")) != "", "%s has no path" % id)
		check(str(e.get("for", "")) != "", "%s does not say where the game uses it" % id)
		check(str(e.get("final", "")).length() > 20, "%s has no brief for the final art" % id)
		check(kind == "cg" or str(e.get("from", "")) != "", "%s does not say what it is made from" % id)


## The stand-in sits where the final file goes, under the id the game already asks for.
func test_stand_ins_are_in_place() -> void:
	var sprites = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprites.json"))
	for e in _entries():
		var id := str(e["id"])
		var name := id.split(":", true, 1)[1]
		var path := "res://" + str(e["path"])
		match str(e["kind"]):
			"sprite":
				check(DirAccess.dir_exists_absolute(path) and not DirAccess.get_files_at(path).is_empty(), "%s: no frames in %s" % [id, path])
				check(sprites["sprites"].has(name), "%s: no data/sprites.json entry" % id)
			"tiles":
				check(DirAccess.dir_exists_absolute(path) and not DirAccess.get_files_at(path).is_empty(), "%s: no tiles in %s" % [id, path])
			"portrait":
				check_eq(path, "res://assets/portraits/%s.png" % name, "%s: portrait path" % id)
				check(FileAccess.file_exists(path), "%s: %s missing" % [id, path])
			"icon":
				check_eq(path, "res://assets/icons/%s.png" % name, "%s: icon path" % id)
				check(FileAccess.file_exists(path), "%s: %s missing" % [id, path])
			"prop":
				check_eq(path, "res://assets/props/%s.png" % name, "%s: prop path" % id)
				check(FileAccess.file_exists(path), "%s: %s missing" % [id, path])
			"music":
				check_eq(path, "res://assets/audio/music/%s.ogg" % name, "%s: music path" % id)
				check(FileAccess.file_exists(path), "%s: %s missing" % [id, path])
			"cg":
				check(path.begins_with("res://assets/cg/"), "%s: CGs go in assets/cg/" % id)
