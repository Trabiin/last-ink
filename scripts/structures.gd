class_name Structures
extends RefCounted
## The building kit (docs/MAP_KIT.md): walls, floors, doors and roofs drawn tile by tile from a map's text, so
## premade maps can have buildings you walk into. A roof covers each enclosed floor and fades away while the
## hero you control stands under it.
##
## Map characters (written as the place looks on screen, top-down 3/4):
##   #  top of a wall (seen from above)        =  wall face        !  wall face with a window
##   _  floor under a roof (an enclosed room)   +  doorway: walkable, drawn as a threshold
## A wall face is the front of a wall: write one or two rows of "=" under a row of "#" for a wall that faces
## south, the way the tiles will be drawn. Rows of "_" fully closed in by walls and doors get a roof.
## @kit <name> picks the art set for every structure on the map (assets/tiles/kit/<name>/, default timber);
## @kitat x,y <name> gives the building that touches tile x,y its own set (a stone office in a timber village).
## Art: tools/make_map_kit.py draws the stand-ins (tracked in data/placeholders.json); final art drops in by name.

const SOLID := "#=!"
const ALL := "#=!_+"
const KIT_DIR := "res://assets/tiles/kit/%s/%s.png"
const DEFAULT_KIT := "timber"
const ROOF_Z := 4  # over the actors (z 0-3), under the drifting motes (5)
const FADE_SPEED := 5.0  # roof alpha per second
const ROOF_INSIDE_ALPHA := 0.0
const INK := Color("12141f")

static var _tex := {}  # "kit/name" -> Texture2D


static func has_any(rows: PackedStringArray) -> bool:
	for r in rows:
		for c in SOLID:
			if r.contains(c):
				return true
	return false


static func tex(kit: String, name: String) -> Texture2D:
	var key := kit + "/" + name
	if not _tex.has(key):
		var p := KIT_DIR % [kit, name]
		if not ResourceLoader.exists(p):
			p = KIT_DIR % [DEFAULT_KIT, name]
		_tex[key] = load(p) if ResourceLoader.exists(p) else null
	return _tex[key]


## Builds every structure on the map: floors under `area`, wall runs Y-sorted into `entities`, roofs over both,
## the collision for the walls, and the path grid (Paths) that lets allies and enemies walk round them.
static func build(area: Node2D, entities: Node2D, rows: PackedStringArray, kit: String, kit_at: Array) -> Dictionary:
	var size := Vector2i(rows[0].length() if not rows.is_empty() else 0, rows.size())
	var cell := func(x: int, y: int) -> String:
		if y < 0 or y >= rows.size() or x < 0 or x >= rows[y].length():
			return "."
		return rows[y][x]
	var kits := _kit_map(rows, size, kit, kit_at, cell)
	# Floors and doorways: one node under the actors.
	var floor_node := Node2D.new()
	floor_node.material = Art.art_world_material()
	floor_node.set_meta("kit", kit)
	area.add_child(floor_node)
	var furnished := {}  # furniture cells inside rooms get the room's floor under them
	for room in rooms(size, cell):
		for c in room:
			if cell.call(c.x, c.y) != "_":
				furnished[c] = str(kits.get(_first_floor(room, cell), kit))
	floor_node.draw.connect(_draw_floor.bind(floor_node, rows, size, kits, cell, furnished))
	# Walls: one Y-sorted node per vertical run of wall cells, sorted at the run's foot, so a hero behind a
	# wall is drawn behind it and one in front is drawn over it.
	for x in size.x:
		var y := 0
		while y < size.y:
			if not SOLID.contains(cell.call(x, y)):
				y += 1
				continue
			var y0 := y
			while y < size.y and SOLID.contains(cell.call(x, y)):
				y += 1
			var run := WallRun.new()
			run.cells = []
			for yy in range(y0, y):
				run.cells.append(cell.call(x, yy))
			run.kit = str(kits.get(Vector2i(x, y0), kit))
			run.left = []
			run.right = []
			for yy in range(y0, y):
				run.left.append(SOLID.contains(cell.call(x - 1, yy)))
				run.right.append(SOLID.contains(cell.call(x + 1, yy)))
			run.above_open = not SOLID.contains(cell.call(x, y0 - 1))
			run.position = Vector2(x * 16, y * 16)
			run.material = Art.art_world_material()
			entities.add_child(run)
	_build_collision(area, rows, size, cell)
	var roofs := _build_roofs(area, rows, size, kits, kit, cell)
	Paths.setup(rows, size)
	return {"roofs": roofs}


## Which kit each structure cell uses: the map's @kit, or a @kitat override spread over the building it touches.
static func _kit_map(rows: PackedStringArray, size: Vector2i, kit: String, kit_at: Array, cell: Callable) -> Dictionary:
	var out := {}
	for k in kit_at:
		var start: Vector2i = k[0]
		if not ALL.contains(cell.call(start.x, start.y)):
			continue
		var todo := [start]
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			if out.has(c) or not ALL.contains(cell.call(c.x, c.y)):
				continue
			out[c] = k[1]
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				todo.append(c + d)
	return out


static func _draw_floor(n: Node2D, rows: PackedStringArray, size: Vector2i, kits: Dictionary, cell: Callable, furnished: Dictionary) -> void:
	for y in size.y:
		for x in size.x:
			var c: String = cell.call(x, y)
			if c != "_" and c != "+" and not furnished.has(Vector2i(x, y)):
				continue
			var k := str(kits.get(Vector2i(x, y), furnished.get(Vector2i(x, y), _default_kit(n))))
			var t: Texture2D
			if c == "+":
				t = tex(k, "door")
			else:
				t = tex(k, "floor_v1" if (x * 7 + y * 13) % 5 == 0 else "floor")
			if t:
				n.draw_texture(t, Vector2(x * 16, y * 16))
			# A soft shadow along the foot of the wall above, so floors sit under the walls.
			if SOLID.contains(cell.call(x, y - 1)):
				n.draw_rect(Rect2(x * 16, y * 16, 16, 3), Color(INK, 0.35))
				n.draw_rect(Rect2(x * 16, y * 16 + 3, 16, 2), Color(INK, 0.15))
	# Ground shadow under wall faces that stand on open ground (outside walls).
	for y in size.y:
		for x in size.x:
			if "=!".contains(cell.call(x, y)) and not ALL.contains(cell.call(x, y + 1)):
				n.draw_rect(Rect2(x * 16, y * 16 + 16, 16, 3), Color(INK, 0.3))


static func _default_kit(n: Node) -> String:
	return str(n.get_meta("kit")) if n.has_meta("kit") else DEFAULT_KIT


## One static body: a box per horizontal run of wall cells in each row.
static func _build_collision(area: Node2D, rows: PackedStringArray, size: Vector2i, cell: Callable) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	area.add_child(body)
	for y in size.y:
		var x := 0
		while x < size.x:
			if not SOLID.contains(cell.call(x, y)):
				x += 1
				continue
			var x0 := x
			while x < size.x and SOLID.contains(cell.call(x, y)):
				x += 1
			var shape := RectangleShape2D.new()
			shape.size = Vector2((x - x0) * 16, 16)
			var col := CollisionShape2D.new()
			col.shape = shape
			col.position = Vector2(x0 * 16 + (x - x0) * 8, y * 16 + 8)
			body.add_child(col)


## A roof over each room: a set of floor cells closed in by walls (doorways let you in but don't break it).
## A prop or marker standing on a room's floor (a bench, a strongbox, the party's start "@"): any letter or
## digit, or "@".
static func _is_furniture(ch: String) -> bool:
	return ch == "@" or (ch.length() == 1 and (ch.to_upper() != ch.to_lower() or ch.is_valid_int()))


## Every enclosed room: {cell: true} for its floor, the furniture on it included. Floor that runs off into
## open ground is a courtyard, not a room, and is left out.
static func rooms(size: Vector2i, cell: Callable) -> Array:
	var seen := {}
	var out := []
	for y in size.y:
		for x in size.x:
			if cell.call(x, y) != "_" or seen.has(Vector2i(x, y)):
				continue
			var room := {}
			var todo := [Vector2i(x, y)]
			var open := false
			while not todo.is_empty():
				var c: Vector2i = todo.pop_back()
				if room.has(c):
					continue
				var ch: String = cell.call(c.x, c.y)
				if ch != "_" and not _is_furniture(ch):
					if not ALL.contains(ch):
						open = true
					continue
				room[c] = true
				seen[c] = true
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					todo.append(c + d)
			if not open:
				out.append(room)
	return out


static func _build_roofs(area: Node2D, rows: PackedStringArray, size: Vector2i, kits: Dictionary, kit: String, cell: Callable) -> Array:
	var out := []
	for room in rooms(size, cell):
		var r := Rect2i(room.keys()[0], Vector2i.ONE)
		for c in room:
			r = r.expand(c).expand(c + Vector2i.ONE)
		# The walls round the room: one cell each side, and up the north wall (cap and inside face).
		var top := r.position.y - 1
		while top > 0 and _row_solid(cell, r.position.x, r.end.x, top - 1):
			top -= 1
		var bottom := r.end.y  # the south wall's cap row(s), not its outside face
		while bottom + 1 < size.y and _row_caps(cell, r.position.x, r.end.x, bottom + 1):
			bottom += 1
		var roof := Roof.new()
		roof.cells = Rect2i(r.position.x - 1, top, r.size.x + 2, bottom - top + 1)
		roof.inside = room
		roof.kit = str(kits.get(_first_floor(room, cell), kit))
		roof.z_index = ROOF_Z
		roof.position = Vector2(roof.cells.position * 16)
		roof.material = Art.art_world_material()
		area.get_parent().add_child.call_deferred(roof)
		out.append(roof)
	return out


static func _first_floor(room: Dictionary, cell: Callable) -> Vector2i:
	for c in room:
		if cell.call(c.x, c.y) == "_":
			return c
	return room.keys()[0]


static func _row_solid(cell: Callable, x0: int, x1: int, y: int) -> bool:
	for x in range(x0, x1):
		if not SOLID.contains(cell.call(x, y)):
			return false
	return true


static func _row_caps(cell: Callable, x0: int, x1: int, y: int) -> bool:
	for x in range(x0, x1):
		if not "#+".contains(cell.call(x, y)):
			return false
	return true


## A column of wall cells: the cap on top, faces below, an ink edge where it meets open ground.
class WallRun extends Node2D:
	var cells: Array = []
	var kit := DEFAULT_KIT
	var left: Array = []
	var right: Array = []
	var above_open := true

	func _draw() -> void:
		var n := cells.size()
		var y0 := -n * 16.0
		for i in n:
			var c: String = cells[i]
			var name := "cap"
			if c == "!":
				name = "window"
			elif c == "=":
				var up_face: bool = i > 0 and "=!".contains(str(cells[i - 1]))
				var down_face: bool = i + 1 < n and "=!".contains(str(cells[i + 1]))
				if i == n - 1:
					name = "face_base"
				elif not up_face:
					name = "face_top"
				elif down_face:
					name = "face"
				else:
					name = "face_base"
			var t := Structures.tex(kit, name)
			var at := Vector2(0, y0 + i * 16)
			if t:
				draw_texture(t, at)
			# Ink outline on the open sides of the wall's top, and down the sides of a face.
			if not left[i]:
				draw_rect(Rect2(at, Vector2(1, 16)), INK)
			if not right[i]:
				draw_rect(Rect2(at + Vector2(15, 0), Vector2(1, 16)), INK)
		if above_open:
			draw_rect(Rect2(Vector2(0, y0), Vector2(16, 1)), INK)


## The roof over one room. Drawn as a gable: lighter slope above the ridge, darker below, eaves at the bottom.
## Fades out while the hero you control stands in the room, and back in when they leave.
class Roof extends Node2D:
	var cells := Rect2i()
	var inside := {}  # Vector2i -> true: the room's floor
	var kit := DEFAULT_KIT
	var alpha := 1.0

	func _ready() -> void:
		set_process(true)

	func covers(tile: Vector2i) -> bool:
		return inside.has(tile)

	func _process(delta: float) -> void:
		var want := 1.0
		for h in get_tree().get_nodes_in_group("heroes"):
			if h.get("controlled") == true and not h.get("dead"):
				var t := Vector2i(floori(h.global_position.x / 16.0), floori(h.global_position.y / 16.0))
				if inside.has(t) or inside.has(t + Vector2i.UP):
					want = Structures.ROOF_INSIDE_ALPHA
		if not is_equal_approx(alpha, want):
			alpha = move_toward(alpha, want, Structures.FADE_SPEED * delta)
			modulate.a = alpha
		visible = alpha > 0.01

	func _draw() -> void:
		var w := cells.size.x
		var h := cells.size.y
		var ridge := maxi(h / 2 - 1, 0)
		var roof_t := Structures.tex(kit, "roof")
		var ridge_t := Structures.tex(kit, "roof_ridge")
		var eave_t := Structures.tex(kit, "roof_eave")
		for y in h:
			for x in w:
				var t := roof_t
				if y == ridge:
					t = ridge_t
				elif y == h - 1:
					t = eave_t
				if t:
					draw_texture(t, Vector2(x, y) * 16, Color(1.12, 1.12, 1.12) if y < ridge else Color.WHITE)
		# Eaves overhang the wall face a little; ink outline all round.
		var r := Rect2(Vector2.ZERO, Vector2(w, h) * 16)
		draw_rect(Rect2(0, r.size.y, r.size.x, 3), Color(INK, 0.45))
		draw_rect(r, INK, false, 1.0)
