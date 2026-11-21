class_name Telegraph
extends RefCounted
## Enemy tells drawn the same way everywhere (issue #34): where an attack will land and who is winding up.
## With Danger markers set to Patterned (Access.danger_patterns, the default) nothing relies on red alone:
## danger zones are hatched with ink stripes inside a dark, dashed outline, aim lines are chevrons that
## point the way, and a wind-up is a warning sign (a dark triangle with "!") rather than a red mark.
## With Colour only, they draw as they always did.
##
## Each takes the CanvasItem to draw on; zones draw in that item's local space, so callers can set a
## transform first (a squashed circle on the ground, a lane rotated to its aim).

const RED := Color(1, 0.3, 0.3)
const EDGE := Color(1, 0.35, 0.35)
const INK := Color(0.08, 0.05, 0.08)
const SIGN := Color("ffd166")  # the warning sign's face: yellow reads apart from red for most eyes


static func patterned() -> bool:
	return Access.danger_patterns


## A round danger zone of radius r, k = how far the wind-up has got (0..1).
static func circle(ci: CanvasItem, center: Vector2, r: float, k: float) -> void:
	ci.draw_circle(center, r * k, Color(RED, 0.18))
	if not patterned():
		ci.draw_arc(center, r, 0, TAU, 32, Color(EDGE, 0.5 + 0.4 * k), 1.0)
		return
	var gap := 4.0
	var c := -r * 1.42
	while c < r * 1.42:  # stripes at 45 degrees, clipped to the circle
		var d := c / sqrt(2.0)
		if absf(d) < r:
			var half := sqrt(r * r - d * d)
			var mid := center + Vector2(1, 1).normalized() * d
			var along := Vector2(1, -1).normalized()
			ci.draw_line(mid - along * half, mid + along * half, Color(INK, 0.28 + 0.25 * k), 1.0)
		c += gap
	ci.draw_arc(center, r, 0, TAU, 40, Color(INK, 0.75), 3.0)
	_dashed_arc(ci, center, r, Color(EDGE, 0.6 + 0.4 * k))


## A rectangular danger zone (a lane, a struck line). fill_k: how much of it has filled in (0..1).
static func rect(ci: CanvasItem, r: Rect2, fill_k: float, strength: float, fill: Rect2 = Rect2()) -> void:
	var f := fill if fill.size != Vector2.ZERO else Rect2(r.position, Vector2(r.size.x * fill_k, r.size.y))
	ci.draw_rect(f, Color(RED, 0.12 + 0.2 * strength))
	if not patterned():
		ci.draw_rect(r, Color(EDGE, 0.35 + 0.6 * strength), false, 1.0)
		return
	# Diagonal stripes across the whole zone, so its full extent shows before it fills.
	var gap := 5.0
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(x, r.end.y)
		var b := Vector2(x + r.size.y, r.position.y)
		var seg := _clip(a, b, r)
		if seg.size() == 2:
			ci.draw_line(seg[0], seg[1], Color(INK, 0.3 + 0.3 * strength), 1.0)
		x += gap
	ci.draw_rect(r.grow(0.5), Color(INK, 0.75), false, 2.5)
	ci.draw_rect(r, Color(EDGE, 0.5 + 0.5 * strength), false, 1.0)


## An aim line along the ground from `from` in direction n (normalized), k = wind-up progress.
static func aim(ci: CanvasItem, from: Vector2, n: Vector2, steps: int, step: float, k: float) -> void:
	for i in steps:
		var p := from + n * (step * i)
		if not patterned():
			ci.draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(EDGE, 0.25 + 0.4 * k))
			continue
		var side := n.orthogonal() * 2.5
		var tip := p + n * 2.5
		var back := p - n * 1.5
		var pts := PackedVector2Array([back + side, tip, back - side])
		ci.draw_polyline(pts, Color(INK, 0.7), 2.5)
		ci.draw_polyline(pts, Color(EDGE, 0.45 + 0.5 * k), 1.0)


## The wind-up mark over a head: a red "!", or with patterns a warning sign. size: the "!" font size.
static func alert(ci: CanvasItem, pos: Vector2, size := 10) -> void:
	var font := ThemeDB.fallback_font
	if not patterned():
		ci.draw_string(font, pos, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), Color("ff5d5d"))
		return
	var s := size * 0.75  # an icon in the world: the same size at every text size
	var c := pos + Vector2(1.5, -size * 0.35)
	var tri := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.95, s * 0.7), c + Vector2(-s * 0.95, s * 0.7)])
	ci.draw_colored_polygon(tri, INK)
	var inner := PackedVector2Array([c + Vector2(0, -s + 2.2), c + Vector2(s * 0.95 - 2.0, s * 0.7 - 1.0), c + Vector2(-s * 0.95 + 2.0, s * 0.7 - 1.0)])
	ci.draw_colored_polygon(inner, SIGN)
	ci.draw_rect(Rect2(c + Vector2(-0.5, -s * 0.45), Vector2(1.2, s * 0.6)), INK)
	ci.draw_rect(Rect2(c + Vector2(-0.5, s * 0.3), Vector2(1.2, 1.2)), INK)


static func _dashed_arc(ci: CanvasItem, center: Vector2, r: float, col: Color) -> void:
	var n := 16
	for i in n:
		if i % 2 == 0:
			var a0 := TAU * i / n
			ci.draw_arc(center, r, a0, a0 + TAU / n, 4, col, 1.5)


## The part of segment a-b inside rect r (Liang-Barsky), or [] if none.
static func _clip(a: Vector2, b: Vector2, r: Rect2) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - r.position.x, r.end.x - a.x, a.y - r.position.y, r.end.y - a.y]
	for i in 4:
		if absf(p[i]) < 0.0001:
			if q[i] < 0.0:
				return PackedVector2Array()
			continue
		var t: float = q[i] / p[i]
		if p[i] < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])
