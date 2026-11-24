class_name StatusMarks
extends Node2D
## Little status icons over an enemy: circling stars while stunned (Last Orders, Chucking Out,
## Through the Door), a gold tally seal while Audited (Odile), hearts while Beguiled (Hortense) and a
## signed contract under Small Print (Nan). Drawn above the enemy's own overlay.

var enemy: Enemy


func _ready() -> void:
	z_index = 3


func _process(_delta: float) -> void:
	queue_redraw()


## Burn and poison on the enemy run here (issue #112), so every enemy script gets them without its
## own _physics_process calling in.
func _physics_process(delta: float) -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.dying_t < 0.0:
		Status.tick(enemy, delta)


func _draw() -> void:
	if enemy == null or enemy.dead or enemy.dying_t >= 0.0:
		return
	var top := -24.0 if enemy.boss else -20.0
	if enemy.stun_left() > 0.0 and not enemy.charmed():  # beguiled shows hearts instead
		var t := Time.get_ticks_msec() / 1000.0
		for k in 3:
			var a := t * 6.0 + k * TAU / 3.0
			var p := Vector2(cos(a) * 6.0, top + sin(a) * 2.0)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("ffe58a"))
			draw_rect(Rect2(p - Vector2(0.5, 0.5), Vector2(1, 1)), Color.WHITE)
	if enemy.marked():
		# A ledger tick in a gold ring: "this one owes".
		var c := Vector2(7, top + 4)
		draw_circle(c, 3.2, Color(0.08, 0.06, 0.1, 0.8))
		draw_arc(c, 3.2, 0, TAU, 12, Color("e8c45a"), 1.0)
		draw_line(c + Vector2(-1.5, 0), c + Vector2(-0.3, 1.3), Color("e8c45a"), 1.0)
		draw_line(c + Vector2(-0.3, 1.3), c + Vector2(1.8, -1.6), Color("e8c45a"), 1.0)
	if enemy.charmed():
		# Beguiled (Hortense): two small hearts bobbing over its head, in her blue.
		var t2 := Time.get_ticks_msec() / 1000.0
		for k in 2:
			var hp2 := Vector2(-4.0 + 8.0 * k, top - 1.0 + sin(t2 * 4.0 + k * 1.7) * 1.2)
			_heart(hp2, Color("8fb0ff"))
	if enemy.weakened():
		# Small Print (Nan): a tiny signed contract with a black seal, on the left.
		var c2 := Vector2(-8, top + 4)
		draw_rect(Rect2(c2 - Vector2(2.5, 3.0), Vector2(5, 6)), Color("e8e2d0"))
		draw_rect(Rect2(c2 - Vector2(2.5, 3.0), Vector2(5, 6)), Color(0.08, 0.06, 0.1, 0.9), false, 1.0)
		draw_line(c2 + Vector2(-1.5, -1.2), c2 + Vector2(1.5, -1.2), Color(0.2, 0.18, 0.25), 1.0)
		draw_circle(c2 + Vector2(1.0, 1.6), 1.2, Color("2a2030"))
	Status.draw_marks(self, enemy, top - 6.0)  # burning, poisoned (issue #112)


func _heart(c: Vector2, col: Color) -> void:
	draw_circle(c + Vector2(-0.9, -0.6), 1.1, col)
	draw_circle(c + Vector2(0.9, -0.6), 1.1, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-2.0, -0.3), c + Vector2(2.0, -0.3), c + Vector2(0, 2.0)]), col)
