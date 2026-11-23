class_name InkGlob
extends Node2D
## A Spitter's glob of Blank: slow enough to sidestep, it flies straight and pops on the
## first hero (or the wardstone it was aimed at) it touches, or when it runs out of range.

var dir := Vector2.RIGHT
var speed := 105.0
var damage := 7
var range_left := 190.0
var goal: Node2D = null  # a Defense wardstone the spitter was aiming at
var kind := "spitter"  # the enemy kind that spat it: its "inflict" rides on the glob (issue #112)
var t := 0.0


func _ready() -> void:
	z_index = 2


func _physics_process(delta: float) -> void:
	t += delta
	var step := speed * delta * Assists.pace()  # enemy speed assist (issue #192)
	position += dir * step
	range_left -= step
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero and not hero.dead and hero.global_position.distance_to(global_position + Vector2(0, 6)) < hero.radius + 4.0:
			if hero.take_hit(Empire.damage_to_party(damage), global_position - dir * 8.0, 150.0):
				Status.struck_kind(kind, hero)
			_pop()
			return
	if goal != null and is_instance_valid(goal) and goal.global_position.distance_to(global_position + Vector2(0, 6)) < 10.0:
		goal.nibble(damage)
		_pop()
		return
	if range_left <= 0.0:
		_pop()
	queue_redraw()


func _pop() -> void:
	Fx.burst(get_parent(), global_position, [Color.WHITE, Color("d9d9d9"), Color.BLACK], 8, 50.0)
	queue_free()


func _draw() -> void:
	# Shadow on the ground, the glob riding a little above it.
	draw_set_transform(Vector2(0, 6), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var wob := 1.0 + sin(t * 18.0) * 0.12
	draw_circle(Vector2.ZERO, 4.0 * wob, Color("f3f1ea"))
	draw_circle(Vector2(-0.5, 0.5), 2.0 * wob, Color("15101a"))
	draw_rect(Rect2(-dir * 6.0 + Vector2(-0.5, -0.5), Vector2(1, 1)), Color(1, 1, 1, 0.8))
