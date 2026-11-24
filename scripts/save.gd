extends Node
## Save slots (autoload "Saves"). One autosave slot plus three manual slots, stored as JSON
## in user://. On the web build user:// lives in the browser's IndexedDB, so saves survive
## closing the tab.
##
## The game scene hands over a snapshot Dictionary; this script only stores and finds them.
## To load, put the data in `pending` and change to the game scene, which applies it on start.
##
## Old saves keep working (issue #110, docs/SAVES.md): every save records the save format
## (`version`), the game version that wrote it and the migrations it already has. Reading an
## older save runs the missing steps from scripts/migrations/ in order (SaveMigrations). A save
## that cannot be read is never deleted: it is set aside as a backup file and the player is told.
## A save written by a newer build is left alone and shown as such.

## Save format. Version 1 had no migration list; 2 adds `game_version` and `migrations`.
## Bump it only when the outer layout changes in a way a migration step cannot express.
const VERSION := 2
const SLOTS := ["auto", "1", "2", "3"]
const GAME_SCENE := "res://scenes/main.tscn"
const COMMAND_SCENE := "res://scenes/command.tscn"
const HUB_SCENE := "res://scenes/hub.tscn"

## Slot states, from inspect().
const EMPTY := "empty"
const GOOD := "ok"
const NEWER := "newer"  # written by a newer build of the game: kept, but not loadable here
const BROKEN := "broken"  # unreadable: moved aside to a backup file

## Snapshot for the game scene to apply on its next _ready(), then clear.
var pending: Dictionary = {}
## Where the slot files live. Tests point this at a scratch folder so they never touch real saves.
var dir := "user://"
## Messages for the player about saves that were set aside (title screen shows them).
var notices: Array = []
## The slot this game was last loaded from or saved to ("" for a fresh game). Bug reports attach it (#146).
var current_slot := ""


func _ready() -> void:
	check_all()


func _path(slot: String) -> String:
	return dir.path_join("save_%s.json" % slot)


func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func slot_label(slot: String) -> String:
	return tr("Autosave") if slot == "auto" else tr("Slot %s") % slot


func save(slot: String, data: Dictionary) -> bool:
	_backup_before_overwrite(slot)
	data["version"] = VERSION
	data["game_version"] = game_version()
	data["migrations"] = SaveMigrations.ids()
	data["saved_at"] = snappedf(Time.get_unix_time_from_system(), 0.001)  # ms: two saves in one second still order
	data["playtime"] = Empire.playtime
	data["empire"] = Empire.to_dict()
	var ok := _write(_path(slot), JSON.stringify(data))
	if ok:
		current_slot = slot
	return ok


## Everything known about a slot: {"status": EMPTY|GOOD|NEWER|BROKEN, "data": migrated save (GOOD only),
## "error": why it is NEWER or BROKEN, "migrated": migration ids that ran on this read}.
## A BROKEN file is moved to a backup straight away and a notice is queued, so the slot reads EMPTY after.
func inspect(slot: String) -> Dictionary:
	var path := _path(slot)
	if not FileAccess.file_exists(path):
		return {"status": EMPTY}
	var text := FileAccess.get_file_as_string(path)
	var r := parse(text)
	if r["status"] == BROKEN:
		var kept := _set_aside(slot, text, "broken")
		var where := (tr(" A copy was kept as %s.") % kept.get_file()) if kept != "" else ""
		notices.append(tr("%s could not be read (%s), so it was set aside instead of loaded.%s The slot is free again.")
			% [slot_label(slot), r["error"], where])
		push_warning("Save %s set aside: %s" % [slot, r["error"]])
	return r


## Reads save text and brings it up to date. Pure: no files touched. See inspect() for the result.
func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if text.strip_edges() == "":
		return {"status": BROKEN, "error": tr("the file is empty")}
	if json.parse(text) != OK:
		return {"status": BROKEN, "error": tr("the file is damaged")}
	var d = json.data
	if typeof(d) != TYPE_DICTIONARY:
		return {"status": BROKEN, "error": tr("not a save file")}
	var v := int(d.get("version", 0))
	if v < 1:
		return {"status": BROKEN, "error": tr("no save format version")}
	if v > VERSION:
		return {"status": NEWER, "error": tr("made by a newer version of Last Ink (%s)") % d.get("game_version", "?")}
	var unknown := SaveMigrations.unknown(d)
	if not unknown.is_empty():
		return {"status": NEWER, "error": tr("made by a newer version of Last Ink (%s)") % d.get("game_version", "?")}
	var m := SaveMigrations.apply(d)
	if not m["ok"]:
		return {"status": BROKEN, "error": m["error"]}
	var out: Dictionary = m["data"]
	out["version"] = VERSION
	return {"status": GOOD, "data": out, "migrated": m["applied"]}


## Looks at every slot once at start-up, so broken files are set aside (and the player told)
## before any menu lists them.
func check_all() -> void:
	for s in SLOTS:
		inspect(s)


func read(slot: String) -> Dictionary:
	var r := inspect(slot)
	return r["data"] if r["status"] == GOOD else {}


func exists(slot: String) -> bool:
	return inspect(slot)["status"] == GOOD


## Hands over the queued notices and clears them.
func take_notices() -> Array:
	var out := notices
	notices = []
	return out


## The most recently written slot, or "" when there are no saves.
func latest_slot() -> String:
	var best := ""
	var best_t := -1.0
	for s in SLOTS:
		var d := read(s)
		if not d.is_empty() and float(d.get("saved_at", 0)) > best_t:
			best_t = float(d.get("saved_at", 0))
			best = s
	return best


## One-line description for menus, e.g. "Day 4   Frayed Meadow   12m played   (5 min ago)".
func describe(slot: String) -> String:
	var r := inspect(slot)
	if r["status"] == NEWER:
		return "(%s)" % r["error"]
	if r["status"] != GOOD:
		return tr("(empty)")
	var d: Dictionary = r["data"]
	var mins := int(float(d.get("playtime", 0.0)) / 60.0)
	var day := int(d.get("empire", {}).get("day", 1))
	return tr("Day %d   %s   %dm played   (%s)") % [day, d.get("area_name", "?"), mins, _ago(int(d.get("saved_at", 0)))]


func _ago(t: int) -> String:
	var s := int(Time.get_unix_time_from_system()) - t
	if s < 60:
		return tr("just now")
	if s < 3600:
		return tr("%d min ago") % (s / 60)
	if s < 86400:
		return tr("%d h ago") % (s / 3600)
	return Loc.n("%d day ago", "%d days ago", s / 86400) % (s / 86400)


## Loads a slot and starts the scene it was saved in (a mission or the Command Table).
## The empire state is restored right away; scene-specific data waits in `pending`.
## Returns false if the slot is empty, newer or unreadable.
func load_and_play(slot: String) -> bool:
	var d := read(slot)
	if d.is_empty():
		return false
	Empire.from_dict(d.get("empire", {}))
	pending = d
	current_slot = slot
	get_tree().paused = false
	get_tree().change_scene_to_file(d.get("scene", GAME_SCENE))
	return true


## Menu items for picking a slot. `for_saving` lists manual slots only, all selectable.
func slot_items(for_saving: bool) -> Array:
	var out := []
	for s in SLOTS:
		if for_saving and s == "auto":
			continue
		var has := exists(s)
		out.append({"id": s, "label": slot_label(s), "detail": describe(s), "enabled": for_saving or has})
	out.append({"id": "back", "label": tr("Back")})
	return out


## Before a save replaces a file from an older or newer build, keep the old file: a newer
## build's save must never be lost, and an upgraded save keeps its pre-upgrade copy once.
func _backup_before_overwrite(slot: String) -> void:
	var path := _path(slot)
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path)
	var r := parse(text)
	if r["status"] == NEWER:
		_set_aside(slot, text, "newer", false)
	elif r["status"] == GOOD and not (r["migrated"] as Array).is_empty():
		_set_aside(slot, text, "v" + str(r["data"].get("game_version", "1")).replace(" ", "_"), false)


## Copies save text to save_<slot>.<tag>-<time>.json; `remove` also deletes the original.
## Written with FileAccess (not a rename) because closing a file is what syncs IndexedDB on the web.
## Returns the backup's path, or "" if it could not be written (then the original stays put).
func _set_aside(slot: String, text: String, tag: String, remove := true) -> String:
	var kept := dir.path_join("save_%s.%s-%d.json" % [slot, tag, int(Time.get_unix_time_from_system())])
	if not _write(kept, text):
		return ""
	if remove:
		DirAccess.remove_absolute(_path(slot))
		_write(kept, text)  # a second close, so the web build also syncs the removal to IndexedDB
	return kept


func _write(path: String, text: String) -> bool:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(text)
	f.close()  # closing the file is what flushes it to IndexedDB on the web
	return true
