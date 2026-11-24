extends SceneTree
## Writes the files Steamworks needs from the game's data (issue #150, docs/STEAM.md):
##   steam/rich_presence_english.vdf   Rich Presence text (data/steam.json "presence"), uploaded in
##                                     Steamworks under Community > Rich Presence
##   steam/achievements.md             every achievement as Steamworks asks for it (API name, name,
##                                     description, hidden), for entering them under Stats & Achievements
## tests/test_steam.gd fails when the committed copies are out of date. Run:
##   godot --headless --path . -s tools/steam_files.gd

const VDF := "res://steam/rich_presence_english.vdf"
const TABLE := "res://steam/achievements.md"

var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:  # the autoloads exist from the first frame on
		var link = root.get_node("SteamLink")
		var ach = root.get_node("Achievements")
		_write(VDF, link.presence_vdf())
		_write(TABLE, table(ach.list, ach.groups))
		print("steam_files: wrote %s and %s" % [VDF, TABLE])
		quit(0)
	return false


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


static func table(list: Array, groups: Array) -> String:
	var out := [
		"# Last Ink achievements for Steamworks",
		"",
		"Generated from data/achievements.json by tools/steam_files.gd. Do not edit by hand.",
		"Enter each row in Steamworks (Stats & Achievements > Achievements): API name, display name,",
		"description, and Hidden for rows marked yes. Icons: steam/icons/<API name>.jpg and",
		"<API name>_locked.jpg, 256 x 256 (see docs/STEAM.md). \"Later\" rows wait for a chapter",
		"that is not in the game yet; they can be entered now, because nothing unlocks them early.",
		"",
		"| API name | Name | Description | Hidden | Later | Group |",
		"|---|---|---|---|---|---|",
	]
	var names := {}
	for g in groups:
		names[str(g["id"])] = str(g["name"])
	for a in list:
		out.append("| %s | %s | %s | %s | %s | %s |" % [a["id"], str(a["name"]).replace("|", "/"),
			str(a["desc"]).replace("|", "/"), "yes" if a.get("hidden", false) else "", "yes" if a.get("later", false) else "",
			names.get(str(a.get("group", "")), "")])
	out.append("")
	out.append("%d achievements." % list.size())
	return "\n".join(out) + "\n"
