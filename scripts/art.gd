class_name Art
## Shared art helpers: CC0 sheet regions, materials, and paper-doll palettes.

const OVERWORLD := preload("res://assets/tiles/overworld.png")
const BODY := preload("res://assets/characters/body.png")
const SLIME := preload("res://assets/characters/slime.png")
const OUTFITS := {
	"archer": preload("res://assets/characters/outfit_archer.png"),
	"warrior": preload("res://assets/characters/outfit_warrior.png"),
	"soldier": preload("res://assets/characters/outfit_soldier.png"),
	"mage": preload("res://assets/characters/outfit_mage.png"),
}
const PALETTE_SWAP := preload("res://shaders/palette_swap.gdshader")
const WORLD_TINT := preload("res://shaders/world_tint.gdshader")

## Source color groups in each Puny Characters layer, light to dark.
## A hero picks one target color per group; the shading is carried over.
const GROUPS := {
	"body": {"skin": ["f7d099", "f6a954", "d97f40", "aa5a33", "84482a"]},
	"archer": {
		"cloth": ["8b9e0f", "627105", "455000", "303600"],
		"leather": ["866114", "433416"],
		"boots": ["5d4717", "3f3013"],
		"trim": ["d4cfc4", "c8c1b3", "bfb7a6", "a8a59d", "6e6c68", "686662"],
	},
	"warrior": {
		"metal": ["bebbb5", "a29e96", "7d7b76", "4d4c4b", "363636", "1e1e1e"],
		"accent": ["00b49d", "007966", "004b3f", "002e27"],
		"boots": ["5d4717", "3f3013"],
	},
	"soldier": {
		"metal": ["bebbb5", "a29e96", "7d7b76", "4d4c4b", "363636", "1e1e1e"],
		"cloth": ["007d89", "005355", "00332f"],
		"boots": ["5d4717", "3f3013"],
	},
	"mage": {
		"cloth": ["00b49d", "007966", "004f43", "002e27"],
		"leather": ["866114", "433416"],
		"boots": ["5d4717", "3f3013"],
		"trim": ["bfb7a6", "c8c1b3", "6e6c68"],
	},
	"slime": {
		"body": ["c0e869", "a9e74e", "6bd926", "40ad29", "087129", "005928"],
		"core": ["002f15"],
		"shine": ["e0e8b1", "ededed"],
	},
}

static var _world_material: ShaderMaterial
static var _art_world_material: ShaderMaterial


static func world_material() -> ShaderMaterial:
	if _world_material == null:
		_world_material = ShaderMaterial.new()
		_world_material.shader = WORLD_TINT
	return _world_material


## The same Blank fade for art pass tiles and props, with no mood grade: they are locked to the style palette
## (docs/ART_STYLE.md), so their colours are shown as drawn and only the day/night light changes them.
static func art_world_material() -> ShaderMaterial:
	if _art_world_material == null:
		_art_world_material = ShaderMaterial.new()
		_art_world_material.shader = WORLD_TINT
		_art_world_material.set_shader_parameter("desat", 0.0)
		_art_world_material.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.0))
		_art_world_material.set_shader_parameter("gain", 1.0)
		_art_world_material.set_shader_parameter("blank_x", world_material().get_shader_parameter("blank_x"))
	return _art_world_material


## Where the Blank starts eating colour, for both world materials.
static func set_blank_x(x: float) -> void:
	world_material().set_shader_parameter("blank_x", x)
	art_world_material().set_shader_parameter("blank_x", x)


static func tile_region(cx: int, cy: int, w := 1, h := 1) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = OVERWORLD
	t.region = Rect2(cx * 16, cy * 16, w * 16, h * 16)
	return t


## Any pixel rect of the overworld sheet, for art that is not on the 16px grid.
static func region(r: Rect2) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = OVERWORLD
	t.region = r
	return t


static func _lum(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## Builds a palette-swap material for one layer. `targets` maps group -> Color.
## Each source shade keeps its brightness relative to the group's average shade.
static func recolor_material(layer: String, targets: Dictionary) -> ShaderMaterial:
	var src := PackedColorArray()
	var dst := PackedColorArray()
	var groups: Dictionary = GROUPS[layer]
	for g in groups:
		if not targets.has(g):
			continue
		var target: Color = targets[g]
		var shades: Array = groups[g]
		var ref := 0.0
		for hex in shades:
			ref += _lum(Color(hex))
		ref /= shades.size()
		for hex in shades:
			var s := Color(hex)
			# Keep each shade's brightness relative to the group average, slightly flattened
			# so light targets do not blow out to white.
			var k := 1.0 + (_lum(s) / maxf(ref, 0.01) - 1.0) * 0.8
			src.append(s)
			dst.append(Color(clampf(target.r * k, 0, 1), clampf(target.g * k, 0, 1), clampf(target.b * k, 0, 1)))
	while src.size() < 24:
		src.append(Color(0, 0, 0, 0))
		dst.append(Color(0, 0, 0, 0))
	var m := ShaderMaterial.new()
	m.shader = PALETTE_SWAP
	m.set_shader_parameter("count", _count(groups, targets))
	m.set_shader_parameter("src", src)
	m.set_shader_parameter("dst", dst)
	return m


static func _count(groups: Dictionary, targets: Dictionary) -> int:
	var n := 0
	for g in groups:
		if targets.has(g):
			n += (groups[g] as Array).size()
	return mini(n, 24)


## A small heart drawn in code (bonds). s = half its width in pixels.
static func draw_heart(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var r := s * 0.52
	ci.draw_circle(c + Vector2(-s * 0.48, -s * 0.35), r, col)
	ci.draw_circle(c + Vector2(s * 0.48, -s * 0.35), r, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.98, -s * 0.18), c + Vector2(s * 0.98, -s * 0.18),
		c + Vector2(0, s * 0.95)]), col)


## Cast shadow under an art pass building or prop (docs/ART_STYLE.md: light from the top left), drawn on `c`
## with the object's bottom-centre at `base`: a soft contact ellipse, and for tall things a band thrown to the
## bottom right.
static func draw_cast_shadow(c: CanvasItem, base: Vector2, w: float, tall: float) -> void:
	var col := Color(0.03, 0.04, 0.09, 0.32)
	c.draw_set_transform(base + Vector2(w * 0.06, 0.5), 0.0, Vector2(1.0, 0.3))
	c.draw_circle(Vector2.ZERO, w * 0.52, col)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)



## How far a cast shadow leans: per pixel of height, this much to the right and this much of the height kept.
const SHADOW_LEAN := 0.42
const SHADOW_SQUASH := 0.5
const SHADOW_COLOR := Color(0.04, 0.05, 0.12, 0.5)
const SHADOW_SORT := 6.0  # the shadow sorts this far in front of its caster, so it falls over neighbours beside it
static var _shadow_cache := {}


## The object's own silhouette thrown to the right along the ground (light from the top left), minus the
## object itself. White on transparent, tinted by the sprite that shows it.
static func shadow_texture(tex: Texture2D) -> ImageTexture:
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _shadow_cache.has(key):
		return _shadow_cache[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var extra := int(ceil(h * SHADOW_LEAN))
	var out := Image.create(w + extra, h + 2, false, Image.FORMAT_RGBA8)
	var base := float(h - 1)
	for oy in h + 2:
		var hgt := (base + 1.0 - float(oy)) / SHADOW_SQUASH  # height on the object this ground row comes from
		if hgt < 0.0:
			hgt = 0.0
		var sy := int(round(base - hgt))
		if sy < 0 or sy >= h:
			continue
		for ox in w + extra:
			var sx := int(round(float(ox) - hgt * SHADOW_LEAN))
			if sx < 0 or sx >= w or img.get_pixel(sx, sy).a < 0.5:
				continue
			if ox < w and oy < h and img.get_pixel(ox, oy).a >= 0.5:
				continue  # the object hides its own shadow
			out.set_pixel(ox, oy, Color.WHITE)
	var it := ImageTexture.create_from_image(out)
	_shadow_cache[key] = it
	return it


## Adds the cast shadow of a sprite (centred, its bottom `bottom` px below the owner's origin) next to `owner`,
## as a sibling in the same Y-sorted parent: it sorts a little in front of the owner, so it darkens what stands
## beside it (a neighbour's wall, a barrel by a stall). It follows the owner's lifetime.
static func add_cast_shadow(owner: Node2D, tex: Texture2D, bottom: float) -> Sprite2D:
	var sh := Sprite2D.new()
	sh.texture = shadow_texture(tex)
	sh.centered = false
	sh.position = owner.position + Vector2(0, SHADOW_SORT)
	sh.offset = Vector2(-tex.get_width() / 2.0, bottom - tex.get_height() - SHADOW_SORT)
	sh.modulate = Color(SHADOW_COLOR, SHADOW_COLOR.a * Settings.fxf("shadows"))
	sh.visible = Settings.fx_value("shadows") > 0
	sh.add_to_group("cast_shadow")
	owner.get_parent().add_child.call_deferred(sh)
	owner.tree_exiting.connect(sh.queue_free)
	return sh



## Light masks: lamps light the ground through a shadowed light (so props throw shadows on it) and light
## the actors and props through a second, unshadowed one (so nothing stands in its own shadow).
const LIGHT_GROUND := 2
const LIGHT_ITEMS := 1
static var _radial_cache := {}


static func _radial(size: int) -> GradientTexture2D:
	if _radial_cache.has(size):
		return _radial_cache[size]
	var g := GradientTexture2D.new()
	g.width = size
	g.height = size
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	g.gradient = grad
	_radial_cache[size] = g
	return g


## A lamp: [ground light with shadows, items light]. Drive it with set_lamp() every frame.
static func add_lamp(parent: Node, pos: Vector2, color: Color, size: int) -> Array:
	var out := []
	for ground in [true, false]:
		var l := PointLight2D.new()
		l.texture = _radial(size)
		l.color = color
		l.position = pos
		l.range_item_cull_mask = LIGHT_GROUND if ground else LIGHT_ITEMS
		l.shadow_enabled = ground
		l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
		l.shadow_filter_smooth = 1.5
		parent.add_child(l)
		out.append(l)
	return out


## Sets a lamp's strength (0..1 before the player's Lamp brightness) and its shadows (Lamp shadows).
static func set_lamp(lights: Array, energy: float) -> void:
	var e := energy * Settings.fxf("lamp_glow") / 0.6
	var sh := Settings.fxf("lamp_shadows")
	for l in lights:
		l.energy = e
		l.enabled = e > 0.05
		if l.range_item_cull_mask == LIGHT_GROUND:
			l.shadow_enabled = sh > 0.0
			l.shadow_color = Color(0, 0, 0, sh)


## A footprint that blocks lamp light: a box at the owner's base, `size` = (width, depth).
## A light occluder for a collision footprint (scripts/footprints.gd): a low box along its front, as wide as the
## walls, so lamp light stops at the building without darkening its own lit front face.
static func add_footprint_occluder(owner: Node2D, pts: PackedVector2Array) -> LightOccluder2D:
	var r := Footprints.bounds(pts)
	return add_occluder(owner, Vector2(r.size.x * 0.9, clampf(r.size.y * 0.35, 4.0, 20.0)))


static func add_occluder(owner: Node2D, size: Vector2) -> LightOccluder2D:
	var o := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	var hw := size.x / 2.0
	poly.polygon = PackedVector2Array([Vector2(-hw, -size.y), Vector2(hw, -size.y), Vector2(hw, 0), Vector2(-hw, 0)])
	o.occluder = poly
	owner.add_child(o)
	return o
