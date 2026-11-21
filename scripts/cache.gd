class_name Cache
extends Node2D
## Something worth carrying home (issue #113): a faction strongbox on a Raid, a half-eaten pile of goods
## at the Blank's edge on a Salvage, or the thing a personal mission asks you to stand at and work on
## (a desk, a door, a poster). A hero standing next to it fills its progress ring; full means done.
## The objective decides what that pays and what happens next; this node only draws and counts.

signal opened

const RANGE := 20.0

var style := "crate"  # crate (raid), pile (salvage), work (a personal mission's "use" spot)
var label := ""  # shown over a "work" spot
var open_time := 1.6
var progress := 0.0
var done := false
var gone := false  # salvage: the white got it first
var worker: Node2D = null  # who is working it (a hero, or an escort for "by escort" steps)
var t := 0.0
var _tex: Texture2D


func _ready() -> void:
	z_index = 0
	if style == "crate" and ResourceLoader.exists("res://assets/props/crates.png"):
		_tex = load("res://assets/props/crates.png")


## One frame of work. who = the nodes that can work it (heroes, or the escort). Returns true once it opens.
func work(delta: float, who: Array) -> bool:
	if done or gone:
		return false
	worker = null
	for h in who:
		var n := h as Node2D
		if n != null and is_instance_valid(n) and not n.get("dead") and n.global_position.distance_to(global_position) < RANGE:
			worker = n
			break
	if worker != null:
		progress = minf(progress + delta / maxf(open_time, 0.05), 1.0)
	else:
		progress = maxf(progress - delta * 0.25, 0.0)  # walking off loses a little, not all of it
	if progress >= 1.0:
		done = true
		opened.emit()
		Audio.sfx("coin")
		Fx.burst(get_parent(), global_position + Vector2(0, -8), [Color("ffd166"), Color("f3efe4")], 12, 70.0)
		return true
	return false


func swallow() -> void:
	if done or gone:
		return
	gone = true
	Fx.burst(get_parent(), global_position + Vector2(0, -6), [Color.WHITE, Color("d9d9d9")], 16, 60.0)


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	if gone:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 11.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match style:
		"crate":
			if _tex:
				var c := Color(0.55, 0.5, 0.45) if done else Color.WHITE
				draw_texture(_tex, Vector2(-_tex.get_width() / 2.0, -_tex.get_height() + 3.0), c)
			else:
				draw_rect(Rect2(-8, -14, 16, 14), Color("6b4a2e") if not done else Color("3a2a1c"))
			if not done:  # the owner's wax seal on the lid
				draw_rect(Rect2(-2.5, -11.5, 5, 5), Color("3a1414"))
				draw_rect(Rect2(-1.5, -10.5, 3, 3), Color("b8443a"))
		"pile":
			var col := Color("8a6a4a") if not done else Color("4a3a2a")
			draw_colored_polygon(PackedVector2Array([Vector2(-12, 0), Vector2(-8, -9), Vector2(-1, -12), Vector2(7, -8), Vector2(12, 0)]), col)
			draw_rect(Rect2(-6, -16, 9, 7), Color("a08060") if not done else Color("504030"))
			draw_line(Vector2(4, -14), Vector2(10, -20), Color("c9b089"), 1.5)
			if not done:  # the white has already started on it
				var rng := RandomNumberGenerator.new()
				rng.seed = int(position.x * 13 + position.y)
				for i in 7:
					draw_rect(Rect2(Vector2(rng.randf_range(2, 12), rng.randf_range(-12, -1)), Vector2(2, 2)), Color(1, 1, 1, 0.85))
		"work":
			if not done:
				var pulse := 0.5 + 0.5 * sin(t * 4.0)
				draw_arc(Vector2(0, -2), 9.0 + pulse * 2.0, 0, TAU, 24, Color(1.0, 0.82, 0.4, 0.5 + 0.3 * pulse), 1.5)
	if not done and progress > 0.0:
		draw_arc(Vector2(0, -26), 6.0, -PI / 2.0, -PI / 2.0 + TAU * progress, 24, Color("ffd166"), 2.5)
		draw_arc(Vector2(0, -26), 6.0, 0, TAU, 24, Color(0, 0, 0, 0.35), 1.0)
	if style == "work" and label != "" and not done:
		var f := ThemeDB.fallback_font
		var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
		draw_string_outline(f, Vector2(-w / 2.0, -36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), 3, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(-w / 2.0, -36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color("ffe7a3"))
