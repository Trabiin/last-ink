class_name FloorMark
extends Node2D
## A mark painted on the ground for an enemy that is somewhere else in the Y-sort (a Reader's reading ring):
## lives on the Area, under every entity, like StruckLine, and draws whatever its owner's painter draws.
## painter: Callable(ci: CanvasItem) drawing in this node's local space; the owner moves and frees it.

var painter: Callable


static func put(owner_node: Node2D, paint: Callable) -> FloorMark:
	var m := FloorMark.new()
	m.painter = paint
	var scene := owner_node.get_tree().current_scene
	var floor_node: Node = scene.get("area") if scene != null and scene.get("area") != null else owner_node.get_parent()
	floor_node.add_child(m)
	m.global_position = owner_node.global_position
	return m


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
