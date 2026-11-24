class_name Fx
extends Node2D
## Code-drawn effects: floating damage numbers and pixel bursts. Bursts, sweeps and rings draw on the pixel
## FX layer (scripts/fx_layer.gd), which turns them into pixel art, and they animate on held frames like the
## sprites (STEP) instead of gliding every screen frame. Damage numbers stay crisp text on the world.

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
var shown := 0.0  # the life the last drawn frame showed (moves in STEPs)
var _acc := 0.0
const STEP := 1.0 / 15.0  # effect frames: 15 a second, close to the sprites' own animation speed


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


func _enter_tree() -> void:
	if kind != Kind.NUMBER:
		FxLayer.adopt(self, kind == Kind.RING)  # a ring lies flat on the ground, under the actors


func _process(delta: float) -> void:
	life += delta
	if life >= max_life:
		queue_free()
		return
	if kind == Kind.NUMBER:
		position.y -= 20.0 * delta
		queue_redraw()
		return
	_acc += delta
	if _acc < STEP and shown > 0.0:
		return
	while _acc >= STEP:
		_acc -= STEP
		for p in particles:
			p[0] += p[1] * STEP
			p[1] *= 0.9 ** (STEP * 60.0)  # the same drag as before, per held frame
	shown = life
	queue_redraw()


func _draw() -> void:
	if kind == Kind.NUMBER:
		var a0 := 1.0 - life / max_life
		var font := ThemeDB.fallback_font
		var size := 8
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, Vector2(-w / 2.0, 0) + o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), Color(0, 0, 0, a0))
		draw_string(font, Vector2(-w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), Color(color, a0))
		return
	var t := shown / max_life
	var a := 1.0 - t
	if kind == Kind.SWEEP:
		_draw_sweep(t, a)
	elif kind == Kind.RING:
		_draw_ring(t, a)
	else:
		_draw_burst(t, a)


## A weapon arc: a crescent smear sweeping across the wedge (lit outer rim, darker inner edge, a few speed
## lines behind it) instead of a flat pie slice. Thin lunges (a few degrees) are a streak to the tip.
func _draw_sweep(t: float, a: float) -> void:
	var rr := radius * (0.7 + 0.3 * minf(t * 2.0, 1.0))
	var light := color.lightened(0.4)
	var shade := color.darkened(0.35)
	if half_arc < 0.3:  # a lunge
		var d := Vector2.from_angle(angle)
		var side := d.orthogonal()
		var w := clampf(tan(half_arc) * radius, 1.5, 4.0)
		draw_colored_polygon(PackedVector2Array([side * w, d * rr, -side * w]), Color(color, 0.8 * a))
		draw_line(d * 3.0, d * rr, Color(light, a), 1.0)
		draw_rect(Rect2((d * rr).round() - Vector2(1, 1), Vector2(2, 2)), Color(light, a))
		return
	var full := half_arc >= PI - 0.01
	var a0 := angle - (PI if full else half_arc)
	var span := TAU if full else half_arc * 2.0
	# The smear runs from the start of the arc to its head, which travels across it in the first half.
	var head := a0 + span * minf(t * 2.2, 1.0)
	var tail := maxf(a0, head - span * 0.75)
	if head - tail > 0.05:
		var n := clampi(int((head - tail) / 0.14), 3, 24)
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		var thick := clampf(rr * 0.35, 3.0, 9.0)
		for i in n + 1:
			var u := float(i) / n
			var d2 := Vector2.from_angle(lerpf(tail, head, u))
			outer.append(d2 * rr)
			inner.append(d2 * (rr - maxf(thick * pow(u, 0.7), 0.8)))
		inner.reverse()
		var poly := PackedVector2Array()
		poly.append_array(outer)
		poly.append_array(inner)
		draw_colored_polygon(poly, Color(color, 0.85 * a))
		draw_polyline(inner.slice(0, maxi(int(n * 0.6), 2)), Color(shade, a), 1.0)  # the inner edge, near the head
		draw_polyline(outer.slice(mini(int(n * 0.3), n - 1)), Color(light, a), 1.0)  # lit outer rim
	# A faint wash over the whole area that was hit, so its reach still reads.
	if not full:
		var pts := PackedVector2Array([Vector2.ZERO])
		var m := clampi(int(rad_to_deg(span) / 15.0), 1, 12)
		for i in m + 1:
			pts.append(Vector2.from_angle(a0 + span * i / m) * rr)
		draw_colored_polygon(pts, Color(color, 0.18 * a))
	else:
		_ellipse(Vector2.ZERO, rr, 1.0, Color(color, 0.18 * a))
	# Speed lines: three short strokes trailing behind the head.
	for k in 3:
		var ang := head - 0.25 - k * 0.22
		if ang < a0:
			break
		var d3 := Vector2.from_angle(ang)
		draw_line(d3 * (rr * 0.45), d3 * (rr * (0.75 - 0.08 * k)), Color(light, a * (0.7 - 0.2 * k)), 1.0)


## A ring rolling out along the ground: a two-tone band (lit top half, shaded bottom half, as the light
## comes from the top left) with a dithered wash inside that thins as it spreads.
func _draw_ring(t: float, a: float) -> void:
	var r := radius * (0.3 + 0.7 * t)
	var light := color.lightened(0.35)
	_ellipse(Vector2.ZERO, r, 0.55, Color(color, 0.22 * a * (1.0 - t)))
	TechFx.inked_ring(self, Vector2.ZERO, r, 0.55, Color(color, a), 2.0)
	if r > 10.0:  # a thinner echo inside, catching the light at the back
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_arc(Vector2.ZERO, r - 4.0, PI * 1.1, PI * 1.9, 12, Color(light, a * 0.6), 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Sparks: the fast ones are short streaks along their flight, the slow ones 1-2 px chips that flick
## between a bright and a base pixel as they tumble.
func _draw_burst(_t: float, a: float) -> void:
	var i := 0
	for p in particles:
		var s: float = p[2]
		var c: Color = p[3]
		var pos: Vector2 = (p[0] as Vector2).round()
		var v: Vector2 = p[1]
		if v.length() > 40.0:
			draw_line(pos, (pos - v * 0.035).round(), Color(c, a), 1.0)
			draw_rect(Rect2(pos, Vector2(1, 1)), Color(c.lightened(0.3), a))
		else:
			var px := 2.0 if s > 2.0 else 1.0
			var lit := (i + int(shown / STEP)) % 3 == 0
			draw_rect(Rect2(pos, Vector2(px, px)), Color(c.lightened(0.3) if lit else c, a))
		i += 1


func _ellipse(c: Vector2, r: float, flat: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, flat))
	draw_circle(Vector2.ZERO, r, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
