class_name ThrownLantern
extends Node2D
## A Lamplighter's lantern (issue #29, Chapter 3): lobbed in a high arc at where a hero stood. While it is in
## the air (flight seconds, longer under the enemy speed assist) the landing spot shows as a round danger zone
## that fills in; when it lands it bursts in a ring of fire: damage to every hero inside, and the thrower's
## "inflict" (burn, data/enemies.json) on top. Step out of the circle before it fills.
##
## Lives on the Area (under the Y-sorted entities) at the landing spot; the lantern itself is drawn riding its arc.

const BURST_R := 24.0
const FIRE := Color("f2a03a")
const GLASS := Color("ffe7a3")
const INK := Color("15101a")

var from := Vector2.ZERO  # where it was thrown from (world space)
var flight := 0.9
var damage := 7
var kind := "lamplighter"
var goal: Node2D = null  # a Defense wardstone it was thrown at
var t := 0.0
var burst_t := -1.0


func _process(delta: float) -> void:
	if burst_t >= 0.0:
		burst_t += delta
		if burst_t > 0.35:
			queue_free()
		queue_redraw()
		return
	t += delta * Assists.pace()
	if t >= flight:
		_burst()
	queue_redraw()


func _burst() -> void:
	burst_t = 0.0
	Fx.burst(get_parent(), global_position, [FIRE, GLASS, INK], 14, 70.0)
	Audio.sfx("burst", 1.2, -4.0, tr("A lantern bursts into flame"))
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead or h.global_position.distance_to(global_position) > BURST_R + h.radius:
			continue
		if h.take_hit(Empire.damage_to_party(damage), global_position, 150.0):
			Status.struck_kind(kind, h)
	if goal != null and is_instance_valid(goal) and goal.global_position.distance_to(global_position) <= BURST_R + 8.0:
		goal.nibble(damage)


func _draw() -> void:
	if burst_t >= 0.0:  # the ring of fire going out
		var k := burst_t / 0.35
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, BURST_R * (0.6 + 0.5 * k), 0, TAU, 28, Color(FIRE, 1.0 - k), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var k := clampf(t / flight, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))  # the danger zone, squashed onto the ground
	Telegraph.circle(self, Vector2.ZERO, BURST_R, k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The lantern on its arc from the thrower to here, with its shadow growing under the landing spot.
	var start := from - global_position
	var p := start.lerp(Vector2.ZERO, k) + Vector2(0, -sin(k * PI) * 40.0 - 6.0 * (1.0 - k))
	draw_circle(Vector2.ZERO, 2.0 + 2.0 * k, Color(0, 0, 0, 0.25))
	draw_rect(Rect2(p + Vector2(-2.5, -3.5), Vector2(5, 7)), INK)
	draw_rect(Rect2(p + Vector2(-1.5, -2.5), Vector2(3, 5)), GLASS)
	draw_circle(p, 1.2, FIRE)
