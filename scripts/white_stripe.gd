class_name WhiteStripe
extends Node2D
## A Whitewasher's stripe of wet lime (issue #206): a short band of whitewash slapped across the ground.
## First the warning (warn seconds: the hatched danger zone with a dotted centre line, where the brush will
## go), then the brush sweeps along it and the paint lies there for `last` seconds. Whoever walks through it
## wades (Hero.mire_t: feet at `slow` of their speed) and is Erased for a few seconds (a ward keeps it off).
## No damage: it is there to cut off the way in, so go round it, or through it and accept the cost.
##
## Lives on the Area (under the Y-sorted entities). The node sits at the stripe's centre, rotated along it,
## so `length` runs along local x and `width` across local y. The warning is longer under the enemy speed
## assist (it ticks at Assists.pace()); the paint, once down, dries on the clock.

const PAINT := Color("f1eee6")
const SHADE := Color("cfcabb")
const INK := Color("15101a")
const SWEEP := 0.3
const ERASE_AGAIN := 2.0  # standing in it Erases again this often

var length := 64.0
var width := 14.0
var warn := 0.9
var last := 6.0
var slow := 0.45
var erase_time := 3.0
var t := 0.0
var cancelled := false
var _inside := {}  # hero instance id -> seconds until it Erases them again
var seed_v := 0


func _ready() -> void:
	seed_v = randi()


func active() -> bool:
	return not cancelled and t >= warn + SWEEP * 0.5 and t < warn + SWEEP + last


## Its brush was knocked away before it touched the ground: the warning goes, nothing is painted.
func cancel() -> void:
	if t < warn and not cancelled:
		cancelled = true
		queue_free()


## Does a point (world space) stand in the stripe? pad grows it (a hero's radius).
func covers(p: Vector2, pad := 0.0) -> bool:
	var l := (p - global_position).rotated(-global_rotation)
	return absf(l.x) <= length / 2.0 + pad and absf(l.y) <= width / 2.0 + pad


func _process(delta: float) -> void:
	t += delta * (Assists.pace() if t < warn else 1.0)
	if t >= warn + SWEEP + last + 0.5:
		queue_free()
		return
	if t >= warn and t - delta < warn:
		Fx.burst(get_parent(), global_position, [PAINT, SHADE], 8, 50.0)
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h == null or h.dead:
			continue
		var id := h.get_instance_id()
		var inside := covers(h.global_position, h.radius - 2.0)
		if not h.controlled and inside and t > warn * 0.3:
			_step_out(h)  # allies the player isn't steering see it too
		if not active() or not inside:
			_inside.erase(id)
			continue
		h.mire_t = 0.12
		h.mire_mult = slow
		var again := float(_inside.get(id, 0.0)) - delta
		if not _inside.has(id) or again <= 0.0:
			again = ERASE_AGAIN
			Status.apply(h, "erase", erase_time)
		_inside[id] = again
	queue_redraw()


## Nudges an AI ally off the stripe, to the nearer side.
func _step_out(h: Hero) -> void:
	var l := (h.global_position - global_position).rotated(-global_rotation)
	var out := Vector2(0, signf(l.y + 0.01)).rotated(global_rotation)
	h.knockback = out * 90.0


func _draw() -> void:
	var r := Rect2(-length / 2.0, -width / 2.0, length, width)
	if t < warn:
		var k := t / warn
		Telegraph.rect(self, r, 1.0, k)
		var d := 0.0
		while d < length:  # the brush's path, dotted along the middle
			draw_line(Vector2(-length / 2.0 + d, 0), Vector2(-length / 2.0 + minf(d + 4.0, length), 0), Color(INK, 0.5 + 0.4 * k), 1.0)
			d += 9.0
		return
	var fade := clampf((warn + SWEEP + last + 0.5 - t) / 0.8, 0.0, 1.0)
	var reach := length * clampf((t - warn) / SWEEP, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var x := 0.0
	while x < reach:  # brush strokes: ragged slices, a shadow under the near edge so it reads as lying wet on the ground
		var a := rng.randf_range(0.0, 2.5)
		var b := rng.randf_range(0.0, 2.5)
		var sx := -length / 2.0 + x
		draw_rect(Rect2(sx, -width / 2.0 + a + 1.0, 4.0, width - a - b), Color(SHADE, 0.85 * fade))
		draw_rect(Rect2(sx, -width / 2.0 + a, 4.0, width - a - b - 1.0), Color(PAINT, 0.95 * fade))
		if rng.randf() < 0.3:  # bristle streaks
			var y := rng.randf_range(-width / 2.0 + 3.0, width / 2.0 - 3.0)
			draw_line(Vector2(sx, y), Vector2(sx + 4.0, y), Color(SHADE, 0.7 * fade), 1.0)
		if rng.randf() < 0.12:  # splashes past the edge
			draw_circle(Vector2(sx + 2.0, (width / 2.0 + 2.0) * (1.0 if rng.randf() < 0.5 else -1.0)), 1.2, Color(PAINT, 0.9 * fade))
		x += 4.0
	if reach < length:  # the brush, still going
		var tip := Vector2(-length / 2.0 + reach, 0)
		draw_rect(Rect2(tip - Vector2(2, width / 2.0 + 1.0), Vector2(4, width + 2.0)), Color("6a5038"))
		draw_rect(Rect2(tip - Vector2(1, width / 2.0), Vector2(2, width)), PAINT)
	elif Telegraph.patterned():
		# With Danger markers on Patterned, a dashed ink edge says "don't stand here" without relying on the white.
		var e := 0.0
		while e < length:
			for yy in [-width / 2.0 - 1.0, width / 2.0 + 1.0]:
				draw_line(Vector2(-length / 2.0 + e, yy), Vector2(-length / 2.0 + minf(e + 4.0, length), yy), Color(INK, 0.6 * fade), 1.0)
			e += 8.0
