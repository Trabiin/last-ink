class_name Footprints
## Collision footprints for props and buildings (data/footprints.json, traced from the art by tools/footprints.py).
##
## A footprint is the ground a thing stands on, as a convex polygon in pixels around its origin (the bottom-centre
## its sprite stands on). It covers the angled walls an art pass building shows and reaches back as far as the roof
## hides Ash, so a building is solid from every side and you can't walk "into" it from behind: from the north you
## stop at its back wall, hidden behind the roof, and the Y-sorted layer draws you behind it.
##
## props are keyed by prop kind (scripts/prop.gd), buildings by "<look>_<level>" (scripts/building_site.gd).
## tests/test_footprints.gd checks that everything placed on a map has one and that it blocks from N, S, E and W.

const PATH := "res://data/footprints.json"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


## The raw entry, or {} when there is none.
static func entry(section: String, key: String) -> Dictionary:
	var e = data().get(section, {}).get(key, {})
	return e if e is Dictionary else {}


static func has(section: String, key: String) -> bool:
	return data().get(section, {}).has(key)


## True when the entry says to walk through it (grass, reeds, planks, flat bones).
static func walk(section: String, key: String) -> bool:
	return bool(entry(section, key).get("walk", false))


## The footprint polygon around the origin; empty for walk-through things and unknown keys.
static func poly(section: String, key: String) -> PackedVector2Array:
	var e := entry(section, key)
	var out := PackedVector2Array()
	if e.get("walk", false):
		return out
	for p in e.get("poly", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A plain box footprint (width x depth, its bottom edge on the origin): the fallback for art with no entry yet.
static func box(size: Vector2) -> PackedVector2Array:
	var hw := size.x / 2.0
	return PackedVector2Array([Vector2(-hw, -size.y), Vector2(hw, -size.y), Vector2(hw, 0), Vector2(-hw, 0)])


## Adds the polygon to a physics body as one convex shape. Returns the CollisionShape2D (null for an empty polygon).
static func attach(body: CollisionObject2D, pts: PackedVector2Array) -> CollisionShape2D:
	if pts.size() < 3:
		return null
	var shape := ConvexPolygonShape2D.new()
	shape.points = pts
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)
	return col


## The polygon's bounding box, relative to the origin.
static func bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## Is `point` (world) on the footprint placed at `origin`, grown by `margin` pixels (an actor's radius)?
static func covers(pts: PackedVector2Array, origin: Vector2, point: Vector2, margin := 0.0) -> bool:
	if pts.size() < 3:
		return false
	var local := point - origin
	if Geometry2D.is_point_in_polygon(local, pts):
		return true
	if margin <= 0.0:
		return false
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		if Geometry2D.get_closest_point_to_segment(local, a, b).distance_to(local) < margin:
			return true
	return false


## Moves any character standing on a footprint that just appeared (a building finished or grew a level) out to
## the nearest open side, so nobody is left stuck inside the walls.
static func eject(owner: Node2D, pts: PackedVector2Array) -> void:
	if pts.size() < 3 or owner.get_parent() == null:
		return
	var r := bounds(pts)
	for n in owner.get_parent().get_children():
		if not (n is CharacterBody2D):
			continue
		var body := n as CharacterBody2D
		var rad := float(body.get("radius")) if body.get("radius") != null else 6.0
		if not covers(pts, owner.global_position, body.global_position, rad):
			continue
		var local := body.global_position - owner.global_position
		var exits := [  # [distance, new local position]: front first on a tie, so people step out the door side
			[r.end.y - local.y, Vector2(local.x, r.end.y + rad + 1.0)],
			[local.y - r.position.y, Vector2(local.x, r.position.y - rad - 1.0)],
			[local.x - r.position.x, Vector2(r.position.x - rad - 1.0, local.y)],
			[r.end.x - local.x, Vector2(r.end.x + rad + 1.0, local.y)],
		]
		exits.sort_custom(func(a, b): return a[0] < b[0])
		body.global_position = owner.global_position + exits[0][1]
