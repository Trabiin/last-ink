extends StaticBody2D
## Scenery: an art pass sprite from assets/props/<kind>.png when there is one, else the CC0 overworld sheet. Origin = the bottom-centre of the prop's footprint.
##
## Each kind is one line here, so swapping a sprite never touches the maps or the code that places them.

## kind -> [tile x, tile y, width, height (tiles), collision radius, optional collision box,
## optional source rect in pixels (when the art is not on the 16px grid)]
const KINDS := {
	"bush": [5, 16, 2, 2, 11.0],
	"shrub": [2, 14, 1, 1, 6.0],
	"rock_big": [4, 1, 2, 2, 11.0],
	"rock": [7, 5, 1, 1, 6.0],
	"stump": [31, 3, 2, 2, 11.0],
	"skull": [28, 2, 1, 1, 0.0],
	"bones": [29, 2, 1, 1, 0.0],
	"sign": [34, 2, 1, 1, 5.0],
	"pond": [2, 9, 2, 2, 13.0],
	# Hollowmark
	"house": [6, 0, 5, 5, 0.0, Vector2(72, 40)],
	"townhall": [6, 0, 5, 5, 0.0, Vector2(72, 40)],
	"tavern": [6, 0, 5, 5, 0.0, Vector2(72, 40)],
	"barn": [11, 0, 5, 5, 0.0, Vector2(72, 40)],
	"stores": [11, 0, 5, 5, 0.0, Vector2(72, 40)],
	"stall": [18, 22, 4, 5, 0.0, Vector2(58, 14)],
	"fountain": [22, 9, 3, 3, 0.0, Vector2(42, 26)],
	"crates": [30, 0, 2, 2, 0.0, Vector2(28, 14)],
	"barrels": [33, 0, 2, 1, 0.0, Vector2(26, 8)],
	"produce": [24, 20, 5, 2, 0.0, Vector2(36, 10)],
	"bench": [28, 4, 3, 1, 0.0, Vector2(40, 6)],
	"banner": [5, 27, 1, 2, 3.0],
	"grave": [0, 0, 1, 2, 0.0, Vector2(16, 6), Rect2(566, 82, 22, 26)],
	# Art pass only (no CC0 fallback worth keeping: they fall back to crates)
	"well": [30, 0, 3, 3, 0.0, Vector2(34, 18)],
	"cart": [30, 0, 3, 2, 0.0, Vector2(36, 14)],
	"lamppost": [30, 0, 1, 2, 3.0],
	"noticeboard": [30, 0, 3, 2, 0.0, Vector2(36, 6)],
}
## Small growth you walk through (no collision).
const NOBLOCK := ["fern", "drygrass", "reeds", "lilypad", "planks", "dock", "roots", "fungus", "inkspring"]
## Flat things lie on the ground: always drawn under characters.
const FLAT := ["pond", "bones", "skull", "garden", "lilypad", "planks", "inkspring", "dock"]

var kind := "bush"
var text := ""  # sign text, or a building's name plate
var _plate_y := 0.0
var seed_v := 0


static func footprint(k: String) -> Vector2i:
	if not KINDS.has(k):
		return Vector2i(1, 1)  # free-standing art (e.g. the town mockup): the map char is its bottom-centre tile
	return Vector2i(KINDS[k][2], KINDS[k][3])


func _ready() -> void:
	collision_layer = 1
	if kind in FLAT:
		z_index = -1
	var k: Array = KINDS.get(kind, [30, 0, 1, 1, 0.0])
	var spr := Sprite2D.new()
	spr.texture = Art.region(k[6]) if k.size() > 6 else Art.tile_region(k[0], k[1], k[2], k[3])
	var art_path := "res://assets/props/%s.png" % kind  # art pass sprite, trimmed to its pixels
	var has_art := ResourceLoader.exists(art_path)
	if has_art:
		spr.texture = load(_variant(art_path))
	spr.centered = true
	# Bottom of the sprite sits a few pixels below the origin, so Y-sorting feels right.
	spr.offset = Vector2(0, -spr.texture.get_height() / 2.0 + 3.0)
	spr.flip_h = seed_v % 2 == 1 and kind in ["bush", "shrub", "rock", "rock_big", "grave", "bones", "skull", "stump"]
	spr.material = Art.art_world_material() if has_art else Art.world_material()
	if has_art and not kind in FLAT:
		var sh := Node2D.new()  # cast shadow, under the sprite
		var sw := float(spr.texture.get_width())
		var st := float(spr.texture.get_height())
		sh.draw.connect(func(): Art.draw_cast_shadow(sh, Vector2(0, 2), sw, st))
		add_child(sh)
	add_child(spr)
	if has_art and not kind in FLAT and spr.texture.get_height() > 12:
		Art.add_cast_shadow(self, spr.texture, 3.0)
	if not KINDS.has(kind) and has_art and not kind in NOBLOCK:  # free-standing art: a footprint box from the sprite's size
		k = k + [Vector2(spr.texture.get_width() * 0.8, minf(spr.texture.get_height() * 0.3, 28.0))]
	if k.size() > 5:
		var box: Vector2 = k[5]
		var rect := RectangleShape2D.new()
		rect.size = box
		var colb := CollisionShape2D.new()
		colb.shape = rect
		colb.position = Vector2(0, -box.y / 2.0)
		add_child(colb)
		if has_art and not kind in FLAT:
			Art.add_occluder(self, Vector2(box.x * 0.9, maxf(box.y * 0.6, 4.0)))
	elif k[4] > 0.0:
		var shape := CircleShape2D.new()
		shape.radius = k[4]
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = Vector2(0, -2)
		add_child(col)
	if kind == "lamppost" and has_art:
		_add_lamp_light(spr.texture.get_height())
	if text != "" and kind != "sign":
		if not KINDS.has(kind) and spr != null and spr.texture != null:
			_plate_y = -spr.texture.get_height() * 0.28  # free-standing art: over its door, low on the wall
		var plate := Node2D.new()
		add_child(plate)
		plate.draw.connect(_draw_plate.bind(plate))


## Recoloured copies (<kind>_v1.png, _v2..., made by tools/depth_pass.py) so a repeated prop doesn't read as a
## copy: each placement picks one from its map position.
func _variant(path: String) -> String:
	var opts := [path]
	var i := 1
	while ResourceLoader.exists(path.replace(".png", "_v%d.png" % i)):
		opts.append(path.replace(".png", "_v%d.png" % i))
		i += 1
	return opts[posmod(seed_v * 7 + seed_v / 5, opts.size())]


## Street lamps glow after dark (the light follows the clock, like Ambience's lantern).
var _lights: Array = []


func _add_lamp_light(h: int) -> void:
	_lights = Art.add_lamp(self, Vector2(0, -h + 8.0), Color(1.0, 0.8, 0.5), 176)
	set_process(true)


func _process(_delta: float) -> void:
	if not _lights.is_empty():
		Art.set_lamp(_lights, 0.7 * Ambience.darkness(Empire.day_t))


## A code-drawn name board over a building's door.
func _draw_plate(c: Node2D) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6)).x + 8.0
	var y := -float(KINDS[kind][3]) * 16.0 * 0.42 if KINDS.has(kind) else _plate_y
	var r := Rect2(-w / 2.0, y - 7.0, w, 9.0)
	c.draw_rect(r, Color("3a2a1c"))
	c.draw_rect(r, Color("c9a46a"), false, 1.0)
	c.draw_string(font, Vector2(r.position.x + 4.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6), Color("f3e3c3"))
