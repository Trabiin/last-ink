class_name TownChatter
extends Node
## What Hollowmark says about Ash (data/gestures.json "chatter", Stance). Walk past a townsperson now and then and
## you overhear them: about the coat Ash gave away, the writ nailed up backwards, the captain sent home barefoot,
## and, once a lean shows, about what kind of person is running the town. Lines play through the walking banter at
## the top of the screen and never stop the game. Each plays once per campaign; lines marked "repeat" come back
## when nothing new is left.
##
## Bran also names Ash here: the first time Ash's lean settles (or changes), and he is standing in town, he tries out
## his new name for Ash once (Stance.nick_banter). After that it turns up wherever he says {nick}.

const NEAR := 46.0  # how close Ash walks to a townsperson to overhear them
const GAP := Vector2(22.0, 40.0)  # seconds between overheard lines (random in this range)

var hub: Node  # scripts/hub.gd
var _wait := 12.0


func _init(host: Node = null) -> void:
	hub = host


func _process(delta: float) -> void:
	if hub == null or not is_instance_valid(hub.leader) or not hub.leader.controlled or hub.banter.busy():
		return
	if hub.leaving or hub.dialogue_box.visible:
		return
	if _nick():
		return
	_wait -= delta
	if _wait > 0.0:
		return
	var folk := _folk_near()
	if folk == null:
		return
	var lines := Stance.chatter()
	if lines.is_empty():
		_wait = GAP.y
		return
	var e: Dictionary = lines[randi() % mini(lines.size(), 3)]  # one of the first few, so the order is not fixed
	Dialogue.mark_seen("chatter:" + str(e["id"]))
	hub.banter.say("", str(e["text"]))
	_wait = randf_range(GAP.x, GAP.y)


## Bran's new name for Ash, when he is in town to say it. True if he said it.
func _nick() -> bool:
	if not hub.npcs.has("bran"):
		return false
	var ls := Stance.nick_banter()
	if ls.is_empty():
		return false
	Dialogue.mark_seen("event:nick_" + Stance.lean())
	hub.banter.add(ls)
	return true


func _folk_near() -> Node2D:
	for c in hub.entities.get_children():
		if c is Townsfolk and (c as Node2D).global_position.distance_to(hub.leader.global_position) < NEAR:
			return c
	return null
