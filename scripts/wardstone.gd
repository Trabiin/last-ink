class_name Wardstone
extends StaticBody2D
## A Defense mission's wardstone: the thing the surge wants to eat. Nibblers that reach it
## call nibble(); the Defense objective fails if it breaks or the Blank swallows it.

var max_hp := 100
var hp := 100
var t := 0.0
var flash_t := 0.0


func _ready() -> void:
	collision_layer = 1
	var shape := CircleShape2D.new()
	shape.radius = 7.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func nibble(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	flash_t = 0.15
	Fx.damage_number(get_parent(), global_position + Vector2(0, -26), str(amount), Color("8ad1ff"))


func _process(delta: float) -> void:
	t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 10.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var glow := 0.5 + 0.5 * sin(t * 2.5)
	var ratio := float(hp) / max_hp
	draw_circle(Vector2(0, -12), 18.0 + glow * 3.0, Color(0.55, 0.82, 1.0, 0.08 + 0.1 * ratio))
	var stone := Color("6d6878") if flash_t <= 0.0 else Access.flash(Color("6d6878"))
	draw_colored_polygon(PackedVector2Array([Vector2(-7, 0), Vector2(-6, -18), Vector2(0, -24), Vector2(6, -18), Vector2(7, 0)]), stone)
	draw_polyline(PackedVector2Array([Vector2(-7, 0), Vector2(-6, -18), Vector2(0, -24), Vector2(6, -18), Vector2(7, 0)]), Color("2b2733"), 1.0)
	# The rune dims as the stone takes damage.
	var rune := Color(0.55, 0.85, 1.0, 0.35 + 0.65 * ratio * (0.7 + 0.3 * glow))
	draw_line(Vector2(0, -19), Vector2(0, -5), rune, 1.5)
	draw_line(Vector2(-3, -15), Vector2(3, -9), rune, 1.0)
	draw_line(Vector2(3, -15), Vector2(-3, -9), rune, 1.0)
	UiSkin.field_bar(self, -33, 24, ratio, "ink", Access.danger_patterns and ratio <= 0.25)
