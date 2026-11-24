class_name Lamplighter
extends Spitter
## Lamplighter (issue #29, Chapter 3): a Causeway lamplighter who works for whoever pays for the oil.
## Pattern: hangs back like a Spitter (Spitter's keep-away and strafing), but instead of spitting it lobs an
## oil lantern in a high arc at where the hero stands (scripts/thrown_lantern.gd): a round danger zone fills in
## on the ground while it flies, and it bursts in a ring of fire that can set you burning. A hit during the
## wind-up spoils the throw. Up close it swings its pole slowly and backs off: close in between throws.

const LanternScript := preload("res://scripts/thrown_lantern.gd")
const FLIGHT := 0.95
const LEAD := 0.25  # aims a little ahead of a moving hero


func _ready() -> void:
	art_id = "lamplighter"
	super._ready()


func _spit() -> void:
	var at := global_position + (aim if aim.length() > 0.1 else facing * 60.0)
	if target != null and not target.dead:
		at = target.global_position + target.velocity * LEAD
	elif goal != null and is_instance_valid(goal):
		at = goal.global_position
	var l: ThrownLantern = LanternScript.new()
	l.from = global_position + Vector2(0, -10)
	l.flight = FLIGHT
	l.kind = Journal.kind_of(self)
	l.damage = roundi(damage * hit_mult())
	var scene := get_tree().current_scene
	var floor_node: Node = scene.get("area") if scene != null and scene.get("area") != null else get_parent()
	floor_node.add_child(l)
	l.global_position = at
	if target == null and goal != null and is_instance_valid(goal):
		l.goal = goal  # a Defense wardstone has nowhere to step to
	Audio.sfx("swing", 0.8, -8.0, tr("A lamplighter lobs a lantern"))
