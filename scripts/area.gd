class_name Area
extends Node2D
## Loads a hand-written text map (maps/*.txt) into Godot TileMapLayers plus props.
##
## Layers, bottom to top: grass variants and flowers (TileMapLayers), then dirt paths drawn by
## the terrain_blend shader from a one-texel-per-tile mask, which gives smooth organic edges
## for any path shape without needing hand-made transition tiles.

const PropScript := preload("res://scripts/prop.gd")
const DIRT := preload("res://assets/tiles/dirt.png")
const TERRAIN_BLEND := preload("res://shaders/terrain_blend.gdshader")
const GROUND_BLEND := preload("res://shaders/ground_blend.gdshader")

const GRASS := [Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 9), Vector2i(1, 9), Vector2i(0, 10), Vector2i(1, 10), Vector2i(5, 9)]
const FLOWERS := [Vector2i(0, 8), Vector2i(1, 8), Vector2i(3, 11), Vector2i(2, 12), Vector2i(3, 12)]
const PROP_CHARS := {"T": "bush", "t": "shrub", "r": "rock", "R": "rock_big", "S": "stump", "o": "pond", "b": "bones", "k": "skull"}
const WORD_COUNT := 10
const WORD_LIFE := 7.0  # seconds a drifting word takes to reach the Blank
const WORDS := ["and then", "was", "the", "almost", "she said", "once", "here lived", "...", "until", "nobody"]

var area_name := ""
var size_tiles := Vector2i.ZERO
var blank_x := 1e9
var party_start := Vector2.ZERO
var spawns: Array[Vector2] = []
var props: Array = []
var markers := {}  # id -> Array of tile-centre positions (@mark lines: posts, the Command Table)
## @spot lines (issue #113): named objective spots in tiles, e.g. "@spot ward 50,31 46,22". Missions pick
## among them (see MissionTypes.vary), so the same map plays differently from one visit to the next.
var spots := {}  # id -> Array of Vector2i
var blank_edge := Callable()  # the Blank's live edge x for a y (main.gd sets Blank.edge_x); else blank_x
var _words: Node2D = null  # redrawn every frame: the words drift
var blank_tiles := -1  # set before build() to start the Blank's wall somewhere other than the map's @blank
var _rows: PackedStringArray = []
var _signs := {}
var _custom := {}  # char -> [kind, plate text] from @prop lines
var _marks := {}  # char -> marker id
var _dirt_chars := ":@"
var ground_set := ""  # @ground <name>: art pass corner tiles in res://assets/tiles/<name>/ (else the old CC0 look)
## @mood: the biome's own light and air, read by scripts/ambience.gd. grade multiplies the day/night light
## (a gentle tint: cool forest, cold marsh, warm hills); mist scales the ground mist; motes tints the drifting
## motes (pollen, spores, midges). Keeps every biome in the one palette but lets each read apart.
var mood := {"grade": Color.WHITE, "mist": 1.0, "motes": Color(1.0, 0.97, 0.85)}
## @written (issue #186): the place as the Blank keeps it, written out as words on a page. No ground tiles: ruled
## paper with paths pencilled in, every prop is its own name in ink (prop.gd), and plain page light (Ambience,
## mood "page"). The betrayer's home in Chapter 6, and the Margin when #32 builds it.
var written := false
const PAPER := Color("efeadf")
const RULE := Color(0.42, 0.5, 0.62, 0.16)
const MARGIN := Color(0.72, 0.25, 0.22, 0.32)


func world_size() -> Vector2:
	return Vector2(size_tiles * 16)


## Reads the map file and builds everything. Props are added to `entities` (the Y-sorted layer).
func build(path: String, entities: Node2D) -> void:
	_parse(path)
	_build_tiles()
	_build_objects(entities)
	var words := Node2D.new()
	add_child(words)
	if blank_x < 1e8:
		words.draw.connect(_draw_words.bind(words))
		_words = words


func _process(_delta: float) -> void:
	if _words:
		_words.queue_redraw()


func _parse(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "Missing map " + path)
	var in_rows := false
	while not f.eof_reached():
		var line := f.get_line()
		if in_rows:
			if line.strip_edges() != "":
				_rows.append(line)
		elif line == "---":
			in_rows = true
		elif line.begins_with("@"):
			var sp := line.find(" ")
			var key := line.substr(1, sp - 1) if sp > 0 else line.substr(1).strip_edges()  # "@written" has no value
			var val := line.substr(sp + 1) if sp > 0 else ""
			if key == "name":
				area_name = val
			elif key == "blank":
				blank_x = float(val) * 16.0
			elif key.begins_with("sign"):
				_signs[key.substr(4)] = val.replace("|", "\n")
			elif key.begins_with("prop"):
				# @propH house|TOWN HALL  ->  H places a house with that name board
				_custom[key.substr(4)] = [val.get_slice("|", 0), val.get_slice("|", 1) if val.contains("|") else ""]
			elif key.begins_with("mark"):
				_marks[key.substr(4)] = val
			elif key == "written":
				written = true
				mood["page"] = true  # Ambience: page light, no weather, ink flecks for motes
				mood["motes"] = Color(0.12, 0.1, 0.14)
			elif key == "ground":
				ground_set = val.strip_edges()
			elif key == "mood":
				# @mood grade=0.85,0.95,0.9 mist=1.6 motes=0.8,1,0.7
				for part in val.split(" ", false):
					var kv := part.split("=")
					if kv.size() != 2:
						continue
					var n := kv[1].split(",")
					if n.size() == 3:
						mood[kv[0]] = Color(float(n[0]), float(n[1]), float(n[2]))
					else:
						mood[kv[0]] = float(kv[1])
			elif key == "dirt":
				_dirt_chars += val  # these characters sit on the dirt layer too
			elif key == "spot":
				var parts := val.split(" ", false)
				if parts.size() >= 2:
					spots[parts[0]] = parse_tiles(parts.slice(1))
	size_tiles = Vector2i(_rows[0].length(), _rows.size())
	if blank_tiles > 0 and blank_x < 1e8:
		blank_x = float(blank_tiles) * 16.0


## "50,31" "46,22" -> [Vector2i(50, 31), Vector2i(46, 22)].
static func parse_tiles(words: Array) -> Array:
	var out := []
	for w in words:
		var xy := str(w).split(",")
		if xy.size() == 2:
			out.append(Vector2i(int(xy[0]), int(xy[1])))
	return out


static var _headers := {}  # path -> {"blank": tiles, "spots": {...}, "size": Vector2i}


## A map's header without building it: its Blank column, its @spot lines and its size in tiles.
## The Command Table uses this to lay out a mission before the map is ever loaded.
static func header(path: String) -> Dictionary:
	if _headers.has(path):
		return _headers[path]
	var out := {"blank": -1, "spots": {}, "size": Vector2i.ZERO, "name": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var rows := 0
	var width := 0
	var in_rows := false
	while not f.eof_reached():
		var line := f.get_line()
		if in_rows:
			if line.strip_edges() != "":
				rows += 1
				width = maxi(width, line.length())
			continue
		if line == "---":
			in_rows = true
		elif line.begins_with("@blank "):
			out["blank"] = int(line.substr(7))
		elif line.begins_with("@name "):
			out["name"] = line.substr(6)
		elif line.begins_with("@spot "):
			var parts := line.substr(6).split(" ", false)
			if parts.size() >= 2:
				out["spots"][parts[0]] = parse_tiles(parts.slice(1))
	out["size"] = Vector2i(width, rows)
	_headers[path] = out
	return out


func _cell(x: int, y: int) -> String:
	if y < 0 or y >= _rows.size() or x < 0 or x >= _rows[y].length():
		return "."
	return _rows[y][x]


func _is_dirt(x: int, y: int) -> int:
	var ch := _cell(x, y)
	return 1 if _dirt_chars.contains(ch) else 0


func _layer(tex: Texture2D, coords: Array) -> TileMapLayer:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(16, 16)
	for c in coords:
		if not src.has_tile(c):
			src.create_tile(c)
	ts.add_source(src, 0)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.material = Art.world_material()
	add_child(layer)
	return layer


func _build_tiles() -> void:
	if written:
		_build_paper()
		return
	if ground_set != "" and ResourceLoader.exists("res://assets/tiles/%s/GGGG.png" % ground_set):
		_build_corner_ground()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(area_name)
	var grass := _layer(Art.OVERWORLD, GRASS)
	var flowers := _layer(Art.OVERWORLD, FLOWERS)
	for y in size_tiles.y:
		for x in size_tiles.x:
			grass.set_cell(Vector2i(x, y), 0, GRASS[rng.randi() % GRASS.size()])
			if _cell(x, y) == "f":
				flowers.set_cell(Vector2i(x, y), 0, FLOWERS[rng.randi() % FLOWERS.size()])
	# Dirt paths: mask texture (white = path) blown up to map size, shaded into dirt.
	var mask := Image.create(size_tiles.x, size_tiles.y, false, Image.FORMAT_L8)
	for y in size_tiles.y:
		for x in size_tiles.x:
			mask.set_pixel(x, y, Color.WHITE if _is_dirt(x, y) else Color.BLACK)
	var dirt := Sprite2D.new()
	dirt.texture = ImageTexture.create_from_image(mask)
	dirt.centered = false
	dirt.scale = Vector2(16, 16)
	dirt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_BLEND
	mat.set_shader_parameter("dirt_tex", DIRT)
	mat.set_shader_parameter("tiles", Vector2(size_tiles))
	mat.set_shader_parameter("blank_x", blank_x)
	dirt.material = mat
	add_child(dirt)


## Art pass ground (docs/ART_ROADMAP.md 3.5): a PixelLab corner tileset, laid on a dual grid. Each map cell
## is one corner (G grass, D dirt); a tile sits between four cells, shifted half a tile, so paths keep
## exactly the shape drawn in the map text. Plain grass tiles are mirrored at random to break repeats.
func _build_corner_ground() -> void:
	var folder := "res://assets/tiles/%s/" % ground_set
	var keys: Array[String] = []
	for a in ["G", "D"]:
		for b in ["G", "D"]:
			for c in ["G", "D"]:
				for d in ["G", "D"]:
					keys.append(a + b + c + d)
	var atlas := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for i in keys.size():
		var img: Image = (load(folder + keys[i] + ".png") as Texture2D).get_image()
		img.convert(Image.FORMAT_RGBA8)
		atlas.blit_rect(img, Rect2i(0, 0, 16, 16), Vector2i(i % 4, i / 4) * 16)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas)
	src.texture_region_size = Vector2i(16, 16)
	for i in keys.size():
		src.create_tile(Vector2i(i % 4, i / 4))
	var plain := Vector2i(0, 0)  # GGGG
	for alt in 3:
		var a := src.create_alternative_tile(plain)
		var td := src.get_tile_data(plain, a)
		td.flip_h = alt != 1
		td.flip_v = alt != 0
	ts.add_source(src, 0)
	# Seamless grass (tools/make_ground.py grass): one 256 px texture over the whole map instead of the 16 px
	# grass tile, whose repeat showed as stripes. With it and a paving texture, the tiles aren't needed at all.
	var has_grass := ResourceLoader.exists(folder + "grass.png")
	if has_grass:
		var lawn := Sprite2D.new()
		lawn.texture = load(folder + "grass.png")
		lawn.centered = false
		lawn.region_enabled = true
		lawn.region_rect = Rect2(Vector2(-16, -16), world_size() + Vector2(32, 32))
		lawn.position = Vector2(-16, -16)
		lawn.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		lawn.material = Art.art_world_material()
		add_child(lawn)
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.material = Art.art_world_material()
	layer.position = Vector2(8, 8)  # dual grid: tile (x, y) covers the centres of cells x..x+1, y..y+1
	var use_tiles := not (has_grass and ResourceLoader.exists(folder + "cobbles.png"))
	if use_tiles:
		add_child(layer)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(area_name)
	for y in (range(-1, size_tiles.y) if use_tiles else []):
		for x in range(-1, size_tiles.x):
			var key := ""
			for c in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]:
				key += "D" if _is_dirt(clampi(c.x, 0, size_tiles.x - 1), clampi(c.y, 0, size_tiles.y - 1)) else "G"
			var blend := ResourceLoader.exists(folder + "cobbles.png")
			if blend:
				key = "GGGG"  # the textured layer below paints the paved part  # no-tr: tile key
			var i := keys.find(key)
			var alt := rng.randi() % 4 if i == 0 else 0
			layer.set_cell(Vector2i(x, y), 0, Vector2i(i % 4, i / 4), alt)
	if not use_tiles:
		layer.free()
	if ResourceLoader.exists(folder + "cobbles.png"):
		_build_paving(load(folder + "cobbles.png"))
	var flowers := Node2D.new()
	flowers.material = Art.art_world_material()
	add_child(flowers)
	flowers.draw.connect(_draw_flowers.bind(flowers))


## Paved ground (town cobbles): a seamless texture painted over the grass through the map mask, with ragged
## mossy edges (shaders/ground_blend.gdshader), so the plaza has no tile grid. Made by tools/make_cobbles.py.
func _build_paving(tex: Texture2D) -> void:
	# Red = paving, green = footpath (map char ","): trodden earth paths up to the doors.
	var mask := Image.create(size_tiles.x, size_tiles.y, false, Image.FORMAT_RGB8)
	for y in size_tiles.y:
		for x in size_tiles.x:
			mask.set_pixel(x, y, Color(_is_dirt(x, y), 1.0 if _cell(x, y) == "," else 0.0, 0.0))
	var pave := Sprite2D.new()
	pave.texture = ImageTexture.create_from_image(mask)
	pave.centered = false
	pave.scale = Vector2(16, 16)
	pave.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_BLEND
	mat.set_shader_parameter("ground_tex", tex)
	mat.set_shader_parameter("tex_size", float(tex.get_width()))
	mat.set_shader_parameter("tiles", Vector2(size_tiles))
	mat.set_shader_parameter("blank_x", blank_x)
	if ground_set != "town" and ground_set != "road":  # wild ground: big, round, wandering patches
		mat.set_shader_parameter("blur", 18.0)
		mat.set_shader_parameter("wobble", 0.5)
		mat.set_shader_parameter("wobble_scale", 30.0)
	pave.material = mat
	add_child(pave)


## Grass tufts on every grass cell (breaks up the repeat) and wildflowers on "f" cells.
func _draw_flowers(c: Node2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(area_name) + 7
	var tuft_dark := Color("26391f")
	var tuft_light := Color("6f8f4a")
	for y in size_tiles.y:
		for x in size_tiles.x:
			if _is_dirt(x, y) or rng.randf() < 0.45:
				continue
			var p := Vector2(x * 16 + rng.randi_range(2, 12), y * 16 + rng.randi_range(3, 13))
			c.draw_rect(Rect2(p, Vector2(1, 2)), tuft_dark)
			c.draw_rect(Rect2(p + Vector2(2, -1), Vector2(1, 3)), tuft_dark)
			c.draw_rect(Rect2(p + Vector2(1, -2), Vector2(1, 2)), tuft_light)
			c.draw_rect(Rect2(p + Vector2(3, -2), Vector2(1, 1)), tuft_light)
	var cols := [Color("d8cfa8"), Color("e0b84a"), Color("b48ac8"), Color("c86a5a")]
	for y in size_tiles.y:
		for x in size_tiles.x:
			if _cell(x, y) != "f":
				continue
			for i in 3:
				var p := Vector2(x * 16 + rng.randi_range(2, 13), y * 16 + rng.randi_range(2, 13))
				var col: Color = cols[rng.randi() % cols.size()]
				c.draw_rect(Rect2(p + Vector2(0, 1), Vector2(1, 2)), Color("2c3a22"))
				c.draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), col)
				c.draw_rect(Rect2(p + Vector2(0, -1), Vector2(1, 3)), col)
				c.draw_rect(Rect2(p, Vector2(1, 1)), col.lightened(0.35))


func _build_objects(entities: Node2D) -> void:
	for y in size_tiles.y:
		for x in size_tiles.x:
			var ch := _cell(x, y)
			var center := Vector2(x * 16 + 8, y * 16 + 8)
			if ch == "@":
				party_start = center
			elif ch == "e":
				spawns.append(center)
			elif _marks.has(ch):
				if not markers.has(_marks[ch]):
					markers[_marks[ch]] = []
				markers[_marks[ch]].append(center)
			elif PROP_CHARS.has(ch) or _signs.has(ch) or _custom.has(ch):
				var kind: String = PROP_CHARS.get(ch, "sign")
				var prop = PropScript.new()
				if _custom.has(ch):
					kind = _custom[ch][0]
					prop.text = _custom[ch][1]
				elif kind == "sign":
					prop.text = _signs[ch]
				prop.kind = kind
				prop.written = written
				prop.seed_v = x * 31 + y
				# Origin = bottom-centre of the footprint. Big props anchor at their top-left tile.
				var fp: Vector2i = PropScript.footprint(kind)
				prop.position = Vector2(x * 16 + fp.x * 8, y * 16 + fp.y * 16 - 3)
				entities.add_child(prop)
				props.append(prop)


## A written map's ground: one sheet of ruled paper the size of the map, a red margin down the left, and the
## ground marks of the map text (paths, ":" and the like) as faint pencil hatching where a path would be.
func _build_paper() -> void:
	var sheet := Node2D.new()
	sheet.z_index = -10
	add_child(sheet)
	sheet.draw.connect(func():
		var ws := world_size()
		sheet.draw_rect(Rect2(Vector2.ZERO, ws), PAPER)
		var y := 24.0
		while y < ws.y:
			sheet.draw_line(Vector2(0, y), Vector2(ws.x, y), RULE, 1.0)
			y += 16.0
		sheet.draw_line(Vector2(40, 0), Vector2(40, ws.y), MARGIN, 1.0)
		# Paths (":" cells) as a faint pencil edge along their outline, like a street sketched in before the words.
		var pencil := Color(0.3, 0.28, 0.32, 0.22)
		for ty in size_tiles.y:
			for tx in size_tiles.x:
				if _is_dirt(tx, ty) != 1:
					continue
				var o := Vector2(tx * 16, ty * 16)
				if _is_dirt(tx, ty - 1) == 0:
					sheet.draw_line(o, o + Vector2(16, 0), pencil, 1.0)
				if _is_dirt(tx, ty + 1) == 0:
					sheet.draw_line(o + Vector2(0, 16), o + Vector2(16, 16), pencil, 1.0)
				if _is_dirt(tx - 1, ty) == 0:
					sheet.draw_line(o, o + Vector2(0, 16), pencil, 1.0)
				if _is_dirt(tx + 1, ty) == 0:
					sheet.draw_line(o + Vector2(16, 0), o + Vector2(16, 16), pencil, 1.0))


func _draw_words(canvas: Node2D) -> void:
	# Near the Blank, scraps of the story it ate drift into it and fade: a few words at a time, always
	# moving and always right at its edge, so they read as the Blank at work and not as stray labels.
	var t := Time.get_ticks_msec() / 1000.0
	var h := world_size().y
	var font := ThemeDB.fallback_font
	for i in WORD_COUNT:
		var cycle := t / WORD_LIFE + float(i) / WORD_COUNT
		var n := floori(cycle)
		var k := cycle - n  # 0..1 through this word's life
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([i, n])
		var y := rng.randf_range(20.0, h - 20.0)
		var edge: float = blank_edge.call(y) if blank_edge.is_valid() else blank_x
		var word := Loc.t(WORDS[rng.randi() % WORDS.size()])
		var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
		var x := edge - w - 2.0 - rng.randf_range(6.0, 30.0) * (1.0 - k)  # ends touching the edge
		canvas.draw_string(font, Vector2(roundf(x), roundf(y)), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.06, 0.05, 0.09, sin(k * PI) * 0.7))