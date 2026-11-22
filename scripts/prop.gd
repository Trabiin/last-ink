extends StaticBody2D
## Scenery: an art pass sprite from assets/props/<kind>.png when there is one, else the CC0 overworld sheet. Origin = the bottom-centre of the prop's footprint.
##
## Each kind is one line here, so swapping a sprite never touches the maps or the code that places them.

## kind -> [tile x, tile y, width, height (tiles), optional source rect in pixels (when the art is not on the
## 16px grid)]: the CC0 fallback art and the tile footprint a big prop is anchored by on the map. Collision comes
## from data/footprints.json (scripts/footprints.gd), traced from the art pass sprite.
const KINDS := {
	"bush": [5, 16, 2, 2],
	"shrub": [2, 14, 1, 1],
	"rock_big": [4, 1, 2, 2],
	"rock": [7, 5, 1, 1],
	"stump": [31, 3, 2, 2],
	"skull": [28, 2, 1, 1],
	"bones": [29, 2, 1, 1],
	"sign": [34, 2, 1, 1],
	"pond": [2, 9, 2, 2],
	# Hollowmark
	"house": [6, 0, 5, 5],
	"townhall": [6, 0, 5, 5],
	"tavern": [6, 0, 5, 5],
	"barn": [11, 0, 5, 5],
	"stores": [11, 0, 5, 5],
	"stall": [18, 22, 4, 5],
	"fountain": [22, 9, 3, 3],
	"crates": [30, 0, 2, 2],
	"barrels": [33, 0, 2, 1],
	"produce": [24, 20, 5, 2],
	"bench": [28, 4, 3, 1],
	"banner": [5, 27, 1, 2],
	"grave": [0, 0, 1, 2, Rect2(566, 82, 22, 26)],
	# Art pass only (no CC0 fallback worth keeping: they fall back to crates)
	"well": [30, 0, 3, 3],
	"cart": [30, 0, 3, 2],
	"lamppost": [30, 0, 1, 2],
	"noticeboard": [30, 0, 3, 2],
}
## Flat things lie on the ground: always drawn under characters.
const FLAT := ["pond", "bones", "skull", "garden", "lilypad", "planks", "inkspring", "dock"]

var kind := "bush"
var text := ""  # sign text, or a building's name plate
var _plate_y := 0.0
var seed_v := 0
var collision_poly := PackedVector2Array()  # the footprint this prop stands on (empty: walk-through)


## The collision polygon for a kind: its traced footprint, nothing for walk-through growth, and for art that has
## no entry yet (tests/test_footprints.gd fails on that) a box from the sprite's size so it is never walk-through.
static func footprint_poly(k: String, sprite_size: Vector2, has_art: bool) -> PackedVector2Array:
	if Footprints.has("props", k):
		return Footprints.poly("props", k)
	if not has_art and KINDS.has(k):
		return Footprints.box(Vector2(KINDS[k][2] * 16.0 * 0.8, maxf(KINDS[k][3] * 16.0 * 0.35, 4.0)))
	return Footprints.box(Vector2(sprite_size.x * 0.8, clampf(sprite_size.y * 0.32, 4.0, 60.0)))


static func footprint(k: String) -> Vector2i:
	if not KINDS.has(k):
		return Vector2i(1, 1)  # free-standing art (e.g. the town mockup): the map char is its bottom-centre tile
	return Vector2i(KINDS[k][2], KINDS[k][3])


func _ready() -> void:
	collision_layer = 1
	if kind in FLAT:
		z_index = -1
	var k: Array = KINDS.get(kind, [30, 0, 1, 1])
	var spr := Sprite2D.new()
	spr.texture = Art.region(k[4]) if k.size() > 4 else Art.tile_region(k[0], k[1], k[2], k[3])
	var art_path := "res://assets/props/%s.png" % kind  # art pass sprite, trimmed to its pixels
	var has_art := ResourceLoader.exists(art_path)
	if has_art:
		spr.texture = load(variant_path(art_path, seed_v))
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
	var pts := footprint_poly(footprint_key(kind, seed_v) if has_art else kind, spr.texture.get_size(), has_art)
	collision_poly = pts
	if Footprints.attach(self, pts) != null and has_art and not kind in FLAT:
		Art.add_footprint_occluder(self, pts)
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
static func variant_path(path: String, pick: int) -> String:
	var opts := [path]
	var i := 1
	while ResourceLoader.exists(path.replace(".png", "_v%d.png" % i)):
		opts.append(path.replace(".png", "_v%d.png" % i))
		i += 1
	return opts[posmod(pick * 7 + pick / 5, opts.size())]


## The footprint entry a placement uses: its variant's own when that variant is shaped differently (a different
## tree, another house), else the kind's (data/footprints.json, tools/footprints.py).
static func footprint_key(k: String, pick: int) -> String:
	var path := "res://assets/props/%s.png" % k
	if not ResourceLoader.exists(path):
		return k
	var v := variant_path(path, pick).get_file().get_basename()
	return v if Footprints.has("props", v) else k


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
