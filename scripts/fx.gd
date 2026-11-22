class_name Fx
extends Node2D
## Code-drawn effects: floating damage numbers and pixel bursts.

enum Kind { NUMBER, BURST, SWEEP, RING }

var kind: int = Kind.NUMBER
var text := ""
var color := Color.WHITE
var life := 0.0
var max_life := 0.7
var particles: Array = []  # each: [pos: Vector2, vel: Vector2, size: float, color: Color]
var angle := 0.0  # SWEEP: facing; RING: unused
var half_arc := PI  # SWEEP: half-width of the wedge
var radius := 20.0  # SWEEP and RING: outer size


static func damage_number(parent: Node, pos: Vector2, value: String, col: Color) -> void:
	var f := Fx.new()
	f.kind = Kind.NUMBER
	f.text = value
	f.color = col
	f.position = pos + Vector2(randf_range(-4, 4), 0)
	f.z_index = 50
	parent.add_child(f)


static func burst(parent: Node, pos: Vector2, cols: Array, count := 14, speed := 90.0) -> void:
	var f := Fx.new()
	f.kind = Kind.BURST
	f.position = pos
	f.max_life = 0.55
	f.z_index = 40
	var calm := Access.reduce_flashing  # issue #34: no pure white sparks, fewer of them
	for i in (count if not calm else ceili(count * 0.6)):
		var dir := Vector2.RIGHT.rotated(randf() * TAU)
		var col: Color = cols[i % cols.size()]
		if calm and col.v > 0.9 and col.s < 0.15:
			col = Color(0.78, 0.76, 0.72)
		f.particles.append([Vector2.ZERO, dir * randf_range(speed * 0.3, speed), randf_range(1.0, 3.0), col])
	parent.add_child(f)


## A fading wedge of colour: a wide weapon arc (abilities like Cleave).
static func sweep(parent: Node, pos: Vector2, facing_angle: float, half: float, r: float, col: Color) -> void:
	var f := Fx.new()
	f.kind = Kind.SWEEP
	f.position = pos
	f.angle = facing_angle
	f.half_arc = half
	f.radius = r
	f.color = col
	f.max_life = 0.3
	f.z_index = 40
	parent.add_child(f)


## A ring that grows outwards: area abilities (heals, taunts).
static func ring(parent: Node, pos: Vector2, r: float, col: Color) -> void:
	var f := Fx.new()
	f.kind = Kind.RING
	f.position = pos
	f.radius = r
	f.color = col
	f.max_life = 0.45
	f.z_index = 40
	parent.add_child(f)


func _process(delta: float) -> void:
	life += delta
	if life >= max_life:
		queue_free()
		return
	if kind == Kind.NUMBER:
		position.y -= 20.0 * delta
	else:
		for p in particles:
			p[0] += p[1] * delta
			p[1] *= 0.9
	queue_redraw()


func _draw() -> void:
	var a := 1.0 - life / max_life
	if kind == Kind.NUMBER:
		var font := ThemeDB.fallback_font
		var size := 8
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, Vector2(-w / 2.0, 0) + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), Color(0, 0, 0, a))
		draw_string(font, Vector2(-w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), Color(color, a))
	elif kind == Kind.SWEEP:
		var t := life / max_life
		var rr := radius * (0.6 + 0.4 * t)
		if half_arc >= PI - 0.01:  # an all-round sweep: a disc (a closed fan repeats its first point and won't triangulate)
			draw_circle(Vector2.ZERO, rr, Color(color, 0.45 * a))
		else:
			var pts := PackedVector2Array([Vector2.ZERO])
			var n := clampi(int(rad_to_deg(2.0 * half_arc) / 15.0), 1, 12)  # thin lunges: few points
			for i in n + 1:
				pts.append(Vector2.RIGHT.rotated(angle - half_arc + 2.0 * half_arc * i / n) * rr)
			draw_colored_polygon(pts, Color(color, 0.45 * a))
		draw_arc(Vector2.ZERO, radius * (0.6 + 0.4 * t), angle - half_arc, angle + half_arc, 16, Color(color.lightened(0.4), a), 1.5)
	elif kind == Kind.RING:
		var t2 := life / max_life
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, radius * (0.3 + 0.7 * t2), 0, TAU, 32, Color(color, a), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		for p in particles:
			var s: float = p[2]
			draw_rect(Rect2(p[0] - Vector2(s, s) / 2.0, Vector2(s, s)), Color(p[3], a))
