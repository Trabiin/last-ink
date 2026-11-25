class_name EnemyKinds
extends RefCounted
## The Act 1 enemy roster (issue #16): which enemy types live where, and how to spawn them.
## Data: data/enemies.json. Each kind is an Enemy subclass so heroes, allies and abilities treat
## them all alike (group "enemies", radius, dead, take_hit, taunt, goal).
##   nibbler  - scripts/enemy.gd: chase, wind up, lunge
##   spitter  - scripts/spitter.gd: keeps its distance, swells, spits a slow glob
##   moth     - scripts/moth.gd: Gutterwoods letter-moths, in packs; circle, flash, dive
##   enforcer - scripts/enforcer.gd: Concord heavy; front shield, slow ground-slam with a red ring
##   copyist  - scripts/copyist.gd: Chapter 2 scribe-monk; keeps its distance, copies strips of floor out
##   penitent - scripts/penitent.gd: Chapter 2 Blank monk; lunges, and grabs and holds a hero (issue #206)
##   reader   - scripts/reader.gd: Eraser; lunges, and reads a name aloud that spurs other Erasers on (#206)
##   whitewasher - scripts/whitewasher.gd: Eraser; spits like a Spitter, and paints stripes that slow and Erase (#206)
##   reveller - scripts/reveller.gd: Chapter 3 masquerade guest; circles, rises on its toes, spins down a line (#29)
##   duellist - scripts/duellist.gd: Chapter 3 bridge duellist; front guard parries, salute then double lunge (#29)
##   inkeel   - scripts/inkeel.gd: Chapter 3 lake eel; swims under the ground, surfaces through a ring biting (#29)
##   lamplighter - scripts/lamplighter.gd: Chapter 3; hangs back like a Spitter and lobs lanterns that burst in fire (#29)
##   breaker  - scripts/breaker.gd: Chapter 4 stopped wave; rears up over a lane and crashes down it, then lies flat (#30)
##   netcaster - scripts/netcaster.gd: Chapter 4 drowned netter; hangs back, whirls and throws a net that slows (#30)
##   gannet   - scripts/gannet.gd: Chapter 4 half-gannet; circles out of reach, marks a spot, dives, sticks in the sand (#30)
##   saltwight - scripts/saltwight.gd: Chapter 4; lunges, and crumbles into a heap that stands up again unless broken (#30)
## A kind can reuse another's behaviour with its own art: "script" names the behaviour (a key of
## SCRIPTS), "sprite" the sprite set (data/sprites.json). The marsh reedling spits like a Spitter;
## the mill scarecrow and the Guild sellsword chase and lunge like a Nibbler.

const SCRIPTS := {
	"nibbler": preload("res://scripts/enemy.gd"),
	"spitter": preload("res://scripts/spitter.gd"),
	"moth": preload("res://scripts/moth.gd"),
	"enforcer": preload("res://scripts/enforcer.gd"),
	"copyist": preload("res://scripts/copyist.gd"),
	"penitent": preload("res://scripts/penitent.gd"),
	"reader": preload("res://scripts/reader.gd"),
	"whitewasher": preload("res://scripts/whitewasher.gd"),
	"reveller": preload("res://scripts/reveller.gd"),
	"duellist": preload("res://scripts/duellist.gd"),
	"inkeel": preload("res://scripts/inkeel.gd"),
	"lamplighter": preload("res://scripts/lamplighter.gd"),
	"breaker": preload("res://scripts/breaker.gd"),
	"netcaster": preload("res://scripts/netcaster.gd"),
	"gannet": preload("res://scripts/gannet.gd"),
	"saltwight": preload("res://scripts/saltwight.gd"),
}

static var _data := {}
static var _told := {}  # kind -> true once its tip was shown this session


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/enemies.json", FileAccess.READ)
		if f:
			_data = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file())
	return _data


static func kind(id: String) -> Dictionary:
	return data().get("kinds", {}).get(id, {})


## Spawn weights for a mission: its own "enemies", else its province's roster, else the default.
## blank_only keeps the kinds marked "blank" (what pours out of a surge or a Blot).
static func roster(mission: Dictionary, blank_only := false) -> Dictionary:
	var r: Dictionary = data().get("rosters", {})
	var out: Dictionary = mission["enemies"] if mission.has("enemies") else \
		r.get(str(mission.get("province", "")), r.get("default", {"nibbler": 1}))
	if blank_only:
		out = out.duplicate()
		for k in out.keys():
			if not kind(k).get("blank", false):
				out.erase(k)
		if out.is_empty():
			out = {"nibbler": 1}
	return out


static func pick(mission: Dictionary, blank_only := false) -> String:
	var r := roster(mission, blank_only)
	var total := 0.0
	for k in r:
		total += float(r[k])
	var roll := randf() * total
	for k in r:
		roll -= float(r[k])
		if roll <= 0.0 and SCRIPTS.has(kind(k).get("script", k)):
			return k
	return "nibbler"


## "Nibblers, Spitters": for the briefing.
static func names(mission: Dictionary) -> String:
	var out := []
	for k in roster(mission):
		out.append(kind(k).get("plural", k))
	return ", ".join(out)


## Spawns one roll of the mission's roster at pos (a pack for moths) and returns what came out.
static func spawn(parent: Node, pos: Vector2, mission: Dictionary, id := "", blank_only := false) -> Array:
	if id == "":
		id = pick(mission, blank_only)
	var info := kind(id)
	var out := []
	var n := randi_range(maxi(1, int(info.get("pack", 1)) - 1), maxi(1, int(info.get("pack", 1))))  # packs vary by one
	for i in n:
		var e: Enemy = SCRIPTS[info.get("script", id)].new()
		if info.has("sprite"):
			e.set_meta("art", info["sprite"])
		e.position = pos + (Vector2.RIGHT.rotated(TAU * i / n) * 10.0 if n > 1 else Vector2.ZERO)
		parent.add_child(e)  # _ready runs here; the data overrides the script's defaults after it
		e.max_hp = int(info.get("hp", e.max_hp))
		e.hp = e.max_hp
		e.move_speed = float(info.get("speed", e.move_speed))
		e.xp = int(info.get("xp", e.xp))
		if e.get("damage") != null:
			e.set("damage", int(info.get("damage", e.get("damage"))))
		e.set_meta("kind", id)
		out.append(e)
	return out


## The first time a kind notices the party, the HUD says how to deal with it.
static func notice(e: Enemy) -> void:
	var id: String = e.get_meta("kind", "nibbler")
	Journal.saw(id)  # met: its codex entry opens (issue #114)
	if _told.has(id):
		return
	_told[id] = true
	var tip: String = kind(id).get("tip", "")
	var scene := e.get_tree().current_scene
	if tip != "" and scene != null and scene.get("hud") != null:
		scene.hud.say(tip, 4.5)
