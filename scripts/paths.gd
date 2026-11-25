class_name Paths
extends RefCounted
## Walking round the building kit's walls (scripts/structures.gd): a tile grid of the map with walls solid.
## Only maps with structures switch it on; everywhere else allies and enemies keep walking straight at things
## and stepping round props the old way. An actor whose straight line is blocked by a wall asks toward() for
## the next step along a path; paths are cached per actor and refreshed a few times a second.

const REFRESH := 0.35  # seconds an actor keeps its path before asking again
const SIDE := 5.0  # px either side of a line that must be clear too (bodies have width)

static var active := false
static var grid: AStarGrid2D = null
static var size := Vector2i.ZERO
static var _solid := {}  # Vector2i -> true
static var _cache := {}  # actor instance id -> {"t": msec, "goal": Vector2i, "path": Array[Vector2i]}


static func reset() -> void:
	active = false
	grid = null
	_solid = {}
	_cache = {}


static func setup(rows: PackedStringArray, p_size: Vector2i) -> void:
	reset()
	size = p_size
	grid = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.cell_size = Vector2(16, 16)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for y in size.y:
		for x in mini(size.x, rows[y].length()):
			if Structures.SOLID.contains(rows[y][x]):
				_solid[Vector2i(x, y)] = true
				grid.set_point_solid(Vector2i(x, y), true)
	active = not _solid.is_empty()


static func tile(p: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(p.x / 16.0), 0, maxi(size.x - 1, 0)), clampi(floori(p.y / 16.0), 0, maxi(size.y - 1, 0)))


static func solid(t: Vector2i) -> bool:
	return _solid.has(t)


## No wall on the straight line from a to b (nor a body's width either side of it).
static func clear(a: Vector2, b: Vector2) -> bool:
	if not active:
		return true
	var d := b - a
	var side := d.orthogonal().normalized() * SIDE if d.length() > 0.5 else Vector2.ZERO
	return _line(a, b) and _line(a + side, b + side) and _line(a - side, b - side)


static func _line(a: Vector2, b: Vector2) -> bool:
	# Off-map points (a parked enemy far outside the world) only matter up to the map's edge.
	var world := Rect2(Vector2(-16, -16), Vector2(size * 16) + Vector2(32, 32))
	a = a.clamp(world.position, world.end)
	b = b.clamp(world.position, world.end)
	var n := int(ceil(a.distance_to(b) / 6.0))
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / maxf(n, 1))
		if _solid.has(Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))):
			return false
	return true


## Which way an actor should walk to get to goal: straight there when nothing is in the way, else toward the
## next tile on a path round the walls. Vector2.ZERO when there is no way through.
static func toward(actor: Node2D, goal: Vector2) -> Vector2:
	var from := actor.global_position
	if clear(from, goal):
		return (goal - from).normalized()
	var id := actor.get_instance_id()
	var gt := _free_near(tile(goal))
	var now := Time.get_ticks_msec()
	var c: Dictionary = _cache.get(id, {})
	if c.is_empty() or c["goal"] != gt or now - int(c["t"]) > REFRESH * 1000.0 or (c["path"] as Array).is_empty():
		var st := _free_near(tile(from))
		var path: Array = Array(grid.get_id_path(st, gt)) if grid else []
		c = {"t": now, "goal": gt, "path": path}
		_cache[id] = c
	var path: Array = c["path"]
	# Drop the tiles already reached, and skip ahead to the furthest one in plain sight.
	while not path.is_empty() and tile(from) == path[0]:
		path.pop_front()
	if path.is_empty():
		return (goal - from).normalized()
	var aim: Vector2 = _centre(path[0])
	for i in range(mini(path.size(), 6) - 1, 0, -1):
		if clear(from, _centre(path[i])):
			aim = _centre(path[i])
			break
	return (aim - from).normalized()


static func _centre(t: Vector2i) -> Vector2:
	return Vector2(t * 16) + Vector2(8, 8)


## The nearest open tile (an actor nudged into a wall's edge still gets a path).
static func _free_near(t: Vector2i) -> Vector2i:
	if not _solid.has(t):
		return t
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := t + Vector2i(dx, dy)
				if not _solid.has(c) and grid.region.has_point(c):
					return c
	return t
