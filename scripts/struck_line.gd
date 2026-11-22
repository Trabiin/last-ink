class_name StruckLine
extends Node2D
## The Auditor's ink line (issue #17): he strikes a whole row (or column) of the arena out of
## the record. First a dotted line and a red wash show where it will land (warn seconds), then
## the pen sweeps across and the floor there is erased: a ragged strip of blank paper with a
## black strikethrough. Standing on it hurts. After `last` seconds the floor writes itself back.
##
## Lives on the Area (under the Y-sorted entities), so it reads as part of the ground.
## rect is in world coordinates.

const PAPER := Color("ebe7dc")
const INK := Color("15101a")
const SWEEP := 0.22  # seconds for the pen to cross the arena
const TICK := 0.45

var rect := Rect2()
var warn := 1.1
var last := 4.0
var damage := 5
var t := 0.0
var tick := 0.0
var seed_v := 0


func _ready() -> void:
	seed_v = randi()


func horizontal() -> bool:
	return rect.size.x >= rect.size.y


func active() -> bool:
	return t >= warn + SWEEP and t < warn + last


func _process(delta: float) -> void:
	t += delta
	if t >= warn + last + 0.4:
		queue_free()
		return
	if t >= warn and t - delta < warn:
		Fx.burst(get_parent(), rect.get_center(), [INK, PAPER], 10, 70.0)
	if t > warn * 0.3 and t < warn + last:
		_step_allies_out()
	if active():
		tick -= delta
		if tick <= 0.0:
			tick = TICK
			_hurt()
	queue_redraw()


## Allies the player is not steering see the line too: they sidestep off it (the nearer side).
func _step_allies_out() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead or hero.controlled or not rect.grow(hero.radius + 2.0).has_point(hero.global_position):
			continue
		var c := rect.get_center()
		var p := hero.global_position
		var out := Vector2(0, signf(p.y - c.y + 0.01)) if horizontal() else Vector2(signf(p.x - c.x + 0.01), 0)
		hero.knockback = out * 110.0


func _hurt() -> void:
	for h in get_tree().get_nodes_in_group("heroes"):
		var hero := h as Hero
		if hero == null or hero.dead:
			continue
		var p := hero.global_position
		if rect.grow(hero.radius - 2.0).has_point(p):
			# Pushed out sideways, off the struck line, from its centre.
			var c := rect.get_center()
			var from := Vector2(p.x, c.y) if horizontal() else Vector2(c.x, p.y)
			hero.take_hit(Empire.damage_to_party(damage), from, 140.0)


func _draw() -> void:
	var long := rect.size.x if horizontal() else rect.size.y
	var thick := rect.size.y if horizontal() else rect.size.x
	var along := Vector2.RIGHT if horizontal() else Vector2.DOWN
	var across := Vector2.DOWN if horizontal() else Vector2.RIGHT
	var start := rect.position + across * thick / 2.0  # one end of the centre line
	if t < warn:
		var k := t / warn
		var blink := 1.0 if k < 0.7 or Access.reduce_flashing else (0.5 + 0.5 * sin(t * 40.0))
		Telegraph.rect(self, rect, 1.0, k * blink)
		var d := 0.0
		while d < long:
			draw_line(start + along * d, start + along * minf(d + 4.0, long), Color(INK, 0.55 + 0.4 * k), 1.0)
			d += 9.0
		return
	var fade := clampf((warn + last + 0.4 - t) / 0.6, 0.0, 1.0)
	var reach := long * clampf((t - warn) / SWEEP, 0.0, 1.0)  # how far the pen has got
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var step := 4.0
	var d2 := 0.0
	while d2 < reach:
		# Ragged edges: each little slice of erased floor is a slightly different width.
		var a := rng.randf_range(0.0, 3.0)
		var b := rng.randf_range(0.0, 3.0)
		var r := Rect2(rect.position + along * d2 + across * a, along * step + across * (thick - a - b))
		draw_rect(r.abs(), Color(PAPER, 0.95 * fade))
		if rng.randf() < 0.18:  # flecks of the old ground left behind
			var fp := rect.position + along * (d2 + rng.randf_range(0, step)) + across * rng.randf_range(3, thick - 3)
			draw_rect(Rect2(fp, Vector2(1, 1)), Color(0.3, 0.45, 0.25, 0.6 * fade))
		d2 += step
	# The strikethrough itself: a thick wobbly stroke where the pen went.
	var pts := PackedVector2Array()
	var d3 := 0.0
	while d3 <= reach:
		pts.append(start + along * d3 + across * sin(d3 * 0.07 + float(seed_v % 7)) * 1.5)
		d3 += 6.0
	if pts.size() >= 2:
		draw_polyline(pts, Color(INK, fade), 3.0)
	if reach < long:  # the nib, racing ahead
		var tip := start + along * reach
		draw_circle(tip, 3.0, INK)
		draw_circle(tip, 6.0, Color(INK, 0.25))
