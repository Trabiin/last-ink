extends RefCounted
## Save format 1 -> 2 (issue #110). Every save written before save migrations existed gets this.
##
## Format 1 covered the whole prototype, so it brings old layouts up to date:
## - The first builds saved missions without the campaign ("empire") or the scene: they get an
##   empty campaign (the game fills in a fresh one, keeping the playtime) and the mission scene.
## - Mission saves from before missions.json name no mission: they get the Frayed Meadow patrol,
##   the only fight those builds had.
## - Early banter named speakers by display name ("Bran"); dialogue now uses recruit ids ("bran").
## - The old one-off flags said_first_kill / said_low_power became seen dialogue events.
## - Saves now say which build wrote them; old ones are marked "pre-release".

const MISSION_SCENE := "res://scenes/main.tscn"
const FIRST_MISSION := "meadow_patrol"
const OLD_FLAGS := {"said_first_kill": "event:first_kill", "said_low_power": "event:low_power"}


static func migrate(save: Dictionary) -> Dictionary:
	if typeof(save.get("empire")) != TYPE_DICTIONARY:
		save["empire"] = {"playtime": float(save.get("playtime", 0.0))}
	var empire: Dictionary = save["empire"]
	if not save.has("scene"):
		save["scene"] = MISSION_SCENE
	if save["scene"] == MISSION_SCENE and typeof(save.get("mission")) != TYPE_DICTIONARY:
		var m: Dictionary = Missions.find(FIRST_MISSION)
		if not m.is_empty():
			save["mission"] = m.duplicate(true)
	var seen = empire.get("dialogue", {})
	if typeof(seen) != TYPE_DICTIONARY:
		seen = {}
	for flag in OLD_FLAGS:
		if bool(save.get(flag, false)):
			seen[OLD_FLAGS[flag]] = true
		save.erase(flag)
	if not seen.is_empty():
		empire["dialogue"] = seen
	if typeof(save.get("banter")) == TYPE_ARRAY:
		var ids := _ids_by_name()
		for l in save["banter"]:
			if typeof(l) == TYPE_ARRAY and l.size() > 0 and ids.has(str(l[0]).to_lower()):
				l[0] = ids[str(l[0]).to_lower()]
	if not save.has("game_version"):
		save["game_version"] = "pre-release"
	return save


## Lower-case id, full name or short name ("Bran" for Brannoc Tolley) -> recruit id.
static func _ids_by_name() -> Dictionary:
	var out := {}
	if Empire.recruit_data.is_empty():  # Saves checks the slots at start-up, before Empire is ready
		Empire._load_recruit_data()
	for id in Empire.recruit_data:
		out[str(id).to_lower()] = id
		out[str(Empire.recruit_data[id].get("name", id)).to_lower()] = id
		out[Empire.short_name(id).to_lower()] = id
	# Names from before the naming pass (#158, 20261124_names), as early saves wrote them.
	for old in LEGACY_NAMES:
		out[old] = LEGACY_NAMES[old]
	return out


const LEGACY_NAMES := {"quill marrow": "quill", "brannoc coil": "bran", "brannoc tolley": "bran", "sister abeyance": "abeyance",
	"abeyance": "abeyance", "hesper quoin": "hesper", "hesper": "hesper", "pell undermoss": "pell",
	"dunmore vell": "dunmore", "jessamy nightjar": "jessamy", "velvette": "velvette"}
