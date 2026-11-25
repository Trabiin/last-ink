class_name ThrownKnife
extends Node2D
## Jessamy's Knife Fan (abilities.gd kind "bolt"): a small blade that flies straight and sticks in the
## first enemy it touches (or every enemy on its line with "pierce"), or drops when it runs out of range.

var dir := Vector2.RIGHT
var speed := 240.0
var damage := 8
var knock := 120.0
var range_left := 150.0
var pierce := false
var color := Color("d8d2c4")
## Who threw it and with what (skill tree perks and riders, issue #25). source: "ability" or "tech".
var hero: Hero = null
var ability := {}
var source := "ability"
var hit: Array = []
var t := 0.0


func _ready() -> void:
	z_index = 2
	FxLayer.adopt(self)  # a hero's thrown blade: drawn as pixel art with the other effects


func _physics_process(delta: float) -> void:
	t += delta
	var step := speed * delta
	position += dir * step
	range_left -= step
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or hit.has(enemy):
			continue
		if enemy.global_position.distance_to(global_position + Vector2(0, 6)) < enemy.radius + 4.0:
			hit.append(enemy)
			if hero != null and is_instance_valid(hero):
				TreePerks.strike(hero, enemy, damage, global_position - dir * 8.0, knock, ability, source)
			else:
				enemy.take_hit(damage, global_position - dir * 8.0, knock)
			Fx.burst(get_parent(), global_position, [color, Color.WHITE], 5, 40.0)
			if not pierce:
				queue_free()
				return
	if range_left <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 2.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, dir.angle(), Vector2.ONE)
	draw_line(Vector2(-7, 0), Vector2(-2, 0), Color(color, 0.35), 1.0)  # motion streak
	draw_rect(Rect2(-2, -0.5, 3, 1), Color("5a4636"))  # grip
	draw_colored_polygon(PackedVector2Array([Vector2(1, -1), Vector2(5, 0), Vector2(1, 1)]), color)
