extends "res://tests/test_case.gd"
## Collision footprints (data/footprints.json, scripts/footprints.gd): every building and prop placed on any map has
## one traced from its current art, it is solid from the north, south, east and west, and no map gets cut off by
## the deeper footprints (every spawn, objective spot and recruit post can still be walked to).

const HUB := "res://scenes/hub.tscn"
const MAPS := "res://maps/"
const RADIUS := 5.0  # Hero radius (scripts/hero.gd)
const GRID := 4  # walkability check resolution, in pixels

var Empire: Node
var PropScript: GDScript


func before_each() -> void:
	Empire = autoload("Empire")
	Empire.reset()
	PropScript = load("res://scripts/prop.gd")


func after_each() -> void:
	tree.paused = false


func _maps() -> Array:
	var out := []
	for f in DirAccess.get_files_at(MAPS):
		if f.ends_with(".txt"):
			out.append(MAPS + f)
	out.sort()
	return out


## Every prop kind a map can place: its @prop lines, the built-in map characters and signs.
func _placed_kinds() -> Dictionary:
	var kinds := {}  # kind -> first map that places it
	var area_script: GDScript = load("res://scripts/area.gd")
	for k in area_script.PROP_CHARS.values():
		kinds[k] = "map characters (scripts/area.gd)"
	kinds["sign"] = "map signs"
	for path in _maps():
		var f := FileAccess.open(path, FileAccess.READ)
		while not f.eof_reached():
			var line := f.get_line()
			if line == "---":
				break
			if line.begins_with("@prop"):
				var kind := line.substr(line.find(" ") + 1).get_slice("|", 0).strip_edges()
				if not kinds.has(kind):
					kinds[kind] = path.get_file()
	return kinds


func _building_keys() -> Array:
	var out := []
	var f := FileAccess.open("res://data/buildings.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for b in d["buildings"]:
		var look := str(b.get("look", ""))
		if look == "table":
			continue
		for lv in range(1, b.get("levels", []).size() + 1):
			out.append("%s_%d" % [look, lv])
	return out


func test_everything_placed_has_a_footprint() -> void:
	var kinds := _placed_kinds()
	for kind in kinds:
		if kind == "word":  # @written maps: a word's box is sized from its text (Prop._ready_written)
			continue
		check(Footprints.has("props", kind), "prop '%s' (placed by %s) has no entry in data/footprints.json: add it and run tools/footprints.py" % [kind, kinds[kind]])
	for key in _building_keys():
		check(Footprints.poly("buildings", key).size() >= 3, "building %s has no footprint in data/footprints.json" % key)
	for key in ["command_table", "wardlamp_1", "wardlamp_2"]:
		check(Footprints.poly("props", key).size() >= 3, "%s has no footprint in data/footprints.json" % key)


## A footprint is traced from a sprite of a given size; new art of another size needs tools/footprints.py rerun.
## Every polygon is convex, stands on or above its origin (so anyone south of it is drawn in front) and has a
## real size.
func test_footprints_match_their_art() -> void:
	for section in ["props", "buildings"]:
		var entries: Dictionary = Footprints.data().get(section, {})
		for key in entries:
			var e: Dictionary = entries[key]
			if e.get("walk", false):
				continue
			var pts := Footprints.poly(section, key)
			if not check(pts.size() >= 3, "%s %s: no polygon" % [section, key]):
				continue
			check(_convex(pts), "%s %s: polygon is not convex" % [section, key])
			var r := Footprints.bounds(pts)
			check(r.end.y <= 0.01, "%s %s: footprint reaches below its origin (%.1f): Y-sorting would draw people in front of it inside it" % [section, key, r.end.y])
			check(r.size.x >= 4.0 and r.size.y >= 3.0, "%s %s: footprint too small (%s)" % [section, key, r.size])
			if e.get("manual", false):
				continue
			var path := "res://assets/%s/%s.png" % ["buildings" if section == "buildings" else "props", key]
			if not check(ResourceLoader.exists(path), "%s %s: no sprite %s to trace" % [section, key, path]):
				continue
			var tex: Texture2D = load(path)
			var src: Array = e.get("src", [])
			check(src.size() == 2 and int(src[0]) == tex.get_width() and int(src[1]) == tex.get_height(),
				"%s %s: art is %dx%d but its footprint was traced from %s: run python3 tools/footprints.py" % [section, key, tex.get_width(), tex.get_height(), src])
			var i := 1  # a recoloured variant shares its base's footprint; a differently shaped one needs its own
			while ResourceLoader.exists(path.replace(".png", "_v%d.png" % i)):
				var v: Texture2D = load(path.replace(".png", "_v%d.png" % i))
				check(v.get_size() == tex.get_size() or Footprints.has(section, "%s_v%d" % [key, i]),
					"%s %s_v%d: variant is shaped differently from its base but has no footprint of its own: run python3 tools/footprints.py" % [section, key, i])
				i += 1
			if tex.get_height() >= 64:  # a building: as wide as most of its art and deep, not a thin strip
				check(r.size.x >= tex.get_width() * 0.4, "%s %s: footprint only %.0f px wide for %d px of building" % [section, key, r.size.x, tex.get_width()])
				check(r.size.y >= 20.0, "%s %s: footprint only %.0f px deep: you could walk into the building from behind" % [section, key, r.size.y])


func _convex(pts: PackedVector2Array) -> bool:
	var turn := 0.0
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		var c: Vector2 = pts[(i + 2) % pts.size()]
		var z := (b - a).cross(c - b)
		if absf(z) < 0.0001:
			continue
		if turn == 0.0:
			turn = signf(z)
		elif signf(z) != turn:
			return false
	return true


## Walks a 5px-radius body at every footprint from the north, south, east and west, along three lanes each, and
## checks it is stopped outside the polygon every time (the town hall could be walked through from the north).
func test_every_footprint_is_solid_from_all_sides() -> void:
	var world := Node2D.new()
	tree.root.add_child(world)
	var walker := CharacterBody2D.new()
	walker.collision_mask = 1
	walker.collision_layer = 0
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	var wc := CollisionShape2D.new()
	wc.shape = circle
	walker.add_child(wc)
	world.add_child(walker)
	var origin := Vector2(2000, 2000)
	for section in ["props", "buildings"]:
		var entries: Dictionary = Footprints.data().get(section, {})
		for key in entries:
			var pts := Footprints.poly(section, key)
			if pts.size() < 3:
				continue
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.position = origin
			Footprints.attach(body, pts)
			world.add_child(body)
			await tree.physics_frame
			var r := Footprints.bounds(pts)
			for dir in [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2.LEFT]:
				var across: Vector2 = Vector2(-dir.y, dir.x)
				var span: float = r.size.x if dir.x == 0.0 else r.size.y
				for lane in [-0.3, 0.0, 0.3]:
					var mid: Vector2 = origin + r.get_center() + across * lane * span
					var start: Vector2 = mid - dir * (maxf(r.size.x, r.size.y) / 2.0 + 30.0)
					walker.global_position = start
					var hit := walker.move_and_collide(dir * (maxf(r.size.x, r.size.y) + 60.0))
					var stop := walker.global_position
					check(hit != null and not Geometry2D.is_point_in_polygon(stop - origin, pts),
						"%s %s: walked through it heading %s (lane %.1f), ended at %s from its origin" % [section, key, dir, lane, stop - origin])
			body.queue_free()
			await tree.physics_frame
	world.queue_free()


## In the real town: Ash can't walk through any building from any side, and from the north he stops behind the
## back wall, hidden behind the roof, not pressed against the front face.
func test_town_buildings_block_ash_from_every_side() -> void:
	for id in Empire.building_ids():
		if id != "wardlamp":
			Empire.buildings[id] = 3
	Empire.lamps["hollowmark"] = 2
	Dialogue.mark_seen("talk:meadow_intro")
	var hub = await goto(HUB, 20)
	if not check(hub != null and hub.leader != null, "town did not load"):
		return
	var ash: CharacterBody2D = hub.leader
	var things := []  # [name, origin, polygon]
	for p in hub.area.props:
		if p.collision_poly.size() >= 3 and Footprints.bounds(p.collision_poly).size.y >= 20.0:
			things.append([p.kind, p.global_position, p.collision_poly])
	for id in hub.sites:
		var key: String = hub.sites[id].footprint_key(3)
		things.append([key, hub.sites[id].global_position, Footprints.poly("buildings", key)])
	check(things.size() >= 10, "expected the town's buildings, found %d" % things.size())
	var saw_townhall := false
	for t in things:
		saw_townhall = saw_townhall or t[0] == "townhall"
		var r := Footprints.bounds(t[2])
		for dir in [Vector2.DOWN, Vector2.UP, Vector2.RIGHT, Vector2.LEFT]:
			var mid: Vector2 = t[1] + r.get_center()
			ash.global_position = mid - dir * (maxf(r.size.x, r.size.y) / 2.0 + RADIUS + 2.0)
			ash.move_and_collide(dir * (maxf(r.size.x, r.size.y) + 20.0))
			var local: Vector2 = ash.global_position - t[1]
			check(not Geometry2D.is_point_in_polygon(local, t[2]), "town %s: Ash walked into it heading %s (at %s)" % [t[0], dir, local])
			if dir == Vector2.DOWN:
				check(local.y <= r.position.y + 1.0, "town %s: from the north Ash got to %.0f px behind its front, past the back wall at %.0f" % [t[0], -local.y, -r.position.y])
	check(saw_townhall, "the town hall is missing from the town")


## No map is cut off by the footprints: from the party's start, every enemy spawn, objective spot and recruit post
## can be reached, and nothing starts inside a wall. Footprints are grown by an actor's radius.
func test_every_map_stays_walkable() -> void:
	var checked := {}
	for path in _maps():
		var area = load("res://scripts/area.gd").new()
		var holder := Node2D.new()
		area.build(path, holder)
		var size: Vector2 = area.world_size()
		var w := int(size.x / GRID)
		var h := int(size.y / GRID)
		var blocked := PackedByteArray()
		blocked.resize(w * h)
		var walls := []  # [origin, polygon]
		for p in area.props:
			walls.append([p.position, Footprints.poly("props", PropScript.footprint_key(p.kind, p.seed_v))])
		if path.ends_with("hollowmark.txt"):  # the town's building plots at their biggest, the table and the Wardlamp
			_add_town_walls(area, walls)
		for wl in walls:
			var pts: PackedVector2Array = wl[1]
			if pts.size() < 3:
				continue
			var r := Footprints.bounds(pts).grow(RADIUS + GRID)
			r.position += wl[0]
			for gy in range(maxi(int(r.position.y / GRID), 0), mini(int(r.end.y / GRID) + 1, h)):
				for gx in range(maxi(int(r.position.x / GRID), 0), mini(int(r.end.x / GRID) + 1, w)):
					var c := Vector2(gx * GRID + GRID / 2.0, gy * GRID + GRID / 2.0)
					if Footprints.covers(pts, wl[0], c, RADIUS):
						blocked[gy * w + gx] = 1
		var start := Vector2i(int(area.party_start.x / GRID), int(area.party_start.y / GRID))
		var name: String = path.get_file()
		if not check(blocked[start.y * w + start.x] == 0, "%s: the party starts inside a footprint at %s" % [name, area.party_start]):
			holder.free()
			area.free()
			continue
		var seen := PackedByteArray()
		seen.resize(w * h)
		var queue := [start]
		seen[start.y * w + start.x] = 1
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var i := n.y * w + n.x
				if seen[i] == 0 and blocked[i] == 0:
					seen[i] = 1
					queue.append(n)
		var goals := []  # [label, world position]
		for s in area.spawns:
			goals.append(["enemy spawn", s])
		for id in area.spots:
			for t in area.spots[id]:
				goals.append(["spot " + str(id), Vector2(t * 16) + Vector2(8, 8)])
		for id in area.markers:
			if str(id).begins_with("site_") or id in ["table", "lamp"]:
				continue  # building plots, the Command Table and the Wardlamp are the walls themselves
			for m in area.markers[id]:
				goals.append(["mark " + str(id), m])
		if path.ends_with("hollowmark.txt"):
			_add_town_goals(area, goals)
		for g in goals:
			var p: Vector2 = g[1]
			var gx := clampi(int(p.x / GRID), 0, w - 1)
			var gy := clampi(int(p.y / GRID), 0, h - 1)
			# A goal counts as reachable when an open cell within half a tile of it was reached.
			var ok := false
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var x := gx + ox
					var y := gy + oy
					if x >= 0 and y >= 0 and x < w and y < h and seen[y * w + x] == 1:
						ok = true
			check(ok, "%s: %s at %s can't be reached from the party's start (a footprint walls it off)" % [name, g[0], p])
		checked[name] = true
		holder.free()
		area.free()
	check(checked.size() == _maps().size(), "every map was checked")


func _site_origin(area, id: String) -> Vector2:
	var mark: String = Empire.building(id).get("site", "")
	var spots: Array = area.markers.get(mark, [])
	if mark == "" or spots.is_empty():
		return Vector2.INF
	return (spots[0] as Vector2) - Vector2(8, 8) + Vector2(40, 77)  # as scripts/hub.gd places a plot


func _add_town_walls(area, walls: Array) -> void:
	for id in Empire.building_ids():
		var o := _site_origin(area, id)
		var look := str(Empire.building(id).get("look", ""))
		if o == Vector2.INF or look == "":
			continue
		var biggest := PackedVector2Array()
		var area_best := -1.0
		for lv in range(1, 4):
			var pts := Footprints.poly("buildings", "%s_%d" % [look, lv])
			var r := Footprints.bounds(pts)
			if r.get_area() > area_best:
				area_best = r.get_area()
				biggest = pts
		walls.append([o, biggest])
	var table: Array = area.markers.get("table", [])
	if not table.is_empty():
		walls.append([(table[0] as Vector2) + Vector2(16, 20), Footprints.poly("props", "command_table")])
	var lamp: Array = area.markers.get("lamp", [])
	if not lamp.is_empty():
		walls.append([lamp[0], Footprints.poly("props", "wardlamp_2")])


func _add_town_goals(area, goals: Array) -> void:
	for id in Empire.building_ids():
		var o := _site_origin(area, id)
		if o == Vector2.INF:
			continue
		goals.append(["front door of " + id, o + Vector2(-14, 14)])  # where its staff stand (BuildingSite.post_pos)
	var table: Array = area.markers.get("table", [])
	if not table.is_empty():
		goals.append(["the Command Table's front", (table[0] as Vector2) + Vector2(16, 30)])
