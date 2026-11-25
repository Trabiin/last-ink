class_name FxLayer
extends CanvasLayer
## Pixel-art effects (docs/ART_STYLE.md "Effects"). Skill, tech and weapon effects are drawn in code, and
## drawn straight onto the 4x scaled screen they came out as smooth bright vector shapes next to pixel art
## sprites. Here they are drawn instead into their own small picture, one pixel per world pixel, which
## shaders/pixel_fx.gdshader turns into pixel art (palette colours, flat see-through steps) before it is
## shown. Nothing about how an effect is drawn has to know: a node joins with FxLayer.adopt(self).
##
## Two pictures: the air (BIT: blasts, swings, guards, sparks), shown over the whole world on this
## follow-the-camera layer; and the ground (GROUND_BIT: shadows under the heroes, where a charging tech will
## land), shown inside the world just above the ground and under every actor.
##
## How: effect nodes are put on their own visibility layer. The main viewport stops drawing those layers
## while an FxLayer is alive; a SubViewport per layer shares the world's canvas and draws only its layer,
## following the camera on whole world pixels, and a Sprite2D shows it at world scale.
## Without an FxLayer in the scene (tools, tests, scenes without one) effects simply draw as before.

const BIT := 1 << 9  # visibility layer 10, "fx"
const GROUND_BIT := 1 << 10  # visibility layer 11, "fx ground"
const MARGIN := 8  # world pixels drawn past each edge of the view, so a fast camera never shows a seam
## tools/style_palette.hex, copied here because tools/ is not exported (tests/test_pixel_ui.gd keeps them equal).
const STYLE := [
	"12141f", "1f2233", "2e3247", "3d4152", "575b6b", "7a7d88", "a3a3a6", "2a2019", "3a2a1c", "5a3e28",
	"7d5836", "a07a4e", "c9a97a", "8f8270", "b5a68a", "d6cdba", "1c2619", "2a3a22", "3d5130", "566b3a",
	"7d8c4c", "a3a865", "2b3448", "3f4c66", "5b6b85", "5c2a26", "85402f", "a85d3e", "6b4532", "a06a4c",
	"d19c7c", "3a5f9e", "7fa8ec", "c2622d", "e8c65a", "f2c25c", "6fd13a", "a3243b",
]
## The FX palette: STYLE (the 38 colours every sprite uses) plus the accent tints effects
## and UI need for light (docs/ART_STYLE.md "Effects"). Paper white stays out: only the Blank is paper.
const EXTRA := ["e6dfcd", "3b2a4a", "6a4a7e", "8f6fae", "b49bcc", "7a3a52", "b05a78", "d98aa0", "b8cff2",
	"f7e3a6", "b5e88a", "c4504a", "d98a5a", "5b84c4", "c9a24a"]

static var active: FxLayer = null

var view: SubViewport  # the air
var sprite: Sprite2D
var ground_view: SubViewport
var ground_sprite: Sprite2D
var _mats: Array = []
var _main: Viewport
var _old_mask := 0xFFFFFFFF
var _tint: CanvasModulate


## Puts an effect node on an FX layer: itself only on that layer, and the layer added to every CanvasItem
## above it so the FX view reaches it (a Viewport draws an item only when it and all its parents share a
## layer with it). Call once the node is in the tree. Parents that draw something themselves must keep
## that drawing in a child (Hero does), or the FX view would draw it a second time.
static func adopt(ci: CanvasItem, ground := false) -> void:
	var bit := GROUND_BIT if ground else BIT
	ci.visibility_layer = bit
	var p := ci.get_parent()
	while p != null:
		if p is CanvasItem:
			(p as CanvasItem).visibility_layer |= bit
		p = p.get_parent()


static func palette_colors() -> PackedColorArray:
	var out := PackedColorArray()
	for h in STYLE + EXTRA:
		out.append(Color(h))
	return out


func _init() -> void:
	layer = 1  # above the world, below the HUD layers added after it
	follow_viewport_enabled = true  # this layer moves with the camera, so the sprite sits in world pixels
	name = "FxLayer"  # no-tr: node name


func _ready() -> void:
	_main = get_viewport()
	var pal := palette_colors()
	var img := Image.create(pal.size(), 1, false, Image.FORMAT_RGBA8)
	for i in pal.size():
		img.set_pixel(i, 0, pal[i])
	var pal_tex := ImageTexture.create_from_image(img)
	view = _make_view(BIT)
	sprite = _make_sprite(view, pal_tex, 0.45)
	add_child(sprite)
	# The ground picture lives in the world, right before the actors, so it lands on the ground and under
	# everyone. The world's night tint reaches it twice (drawing, then showing), so the shader takes all of
	# it out once (tint_kept 0).
	ground_view = _make_view(GROUND_BIT)
	ground_sprite = _make_sprite(ground_view, pal_tex, 0.0)
	ground_sprite.name = "FxGround"  # no-tr: node name
	var scene := get_parent()
	var ents: Node = scene.get("entities") if scene != null and "entities" in scene else null
	if ents != null and ents.get_parent() == scene:
		scene.add_child.call_deferred(ground_sprite)
		scene.move_child.call_deferred(ground_sprite, ents.get_index())
	else:
		add_child(ground_sprite)  # no actors node: over the world with the air
	_old_mask = _main.canvas_cull_mask
	_main.canvas_cull_mask = _old_mask & ~(BIT | GROUND_BIT)
	active = self
	process_priority = 1000  # after the camera has moved this frame
	_follow()


func _make_view(bit: int) -> SubViewport:
	var v := SubViewport.new()
	v.transparent_bg = true
	v.world_2d = _main.world_2d
	v.canvas_cull_mask = bit
	v.snap_2d_transforms_to_pixel = true
	v.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	v.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	v.size = Vector2i(16, 16)
	add_child(v)
	return v


func _make_sprite(v: SubViewport, pal_tex: Texture2D, tint_kept: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.texture = v.get_texture()
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/pixel_fx.gdshader")
	mat.set_shader_parameter("palette", pal_tex)
	mat.set_shader_parameter("palette_size", pal_tex.get_width())
	mat.set_shader_parameter("tint_kept", tint_kept)
	sp.material = mat
	_mats.append(mat)
	return sp


func _exit_tree() -> void:
	if _main != null:
		_main.canvas_cull_mask = _old_mask
	if active == self:
		active = null
	if ground_sprite != null and is_instance_valid(ground_sprite) and ground_sprite.get_parent() != self:
		ground_sprite.queue_free()


func _process(_delta: float) -> void:
	_follow()


## Keeps both FX views over what the camera sees, snapped to whole world pixels, and passes on the night tint.
func _follow() -> void:
	var ct := _main.canvas_transform
	var zoom := maxf(ct.x.length(), 0.01)
	var vs := _main.get_visible_rect().size
	var top_left := -ct.origin / zoom
	var origin := (top_left - Vector2(MARGIN, MARGIN)).floor()
	var want := Vector2i((vs / zoom).ceil()) + Vector2i(MARGIN * 2 + 1, MARGIN * 2 + 1)
	for v in [view, ground_view]:
		if v.size != want:
			v.size = want
		v.canvas_transform = Transform2D(0.0, -origin)
	sprite.position = origin
	ground_sprite.position = origin
	if _tint == null or not is_instance_valid(_tint):
		_tint = _find_tint()
	var t := _tint.color if _tint != null and _tint.visible else Color.WHITE
	for m in _mats:
		m.set_shader_parameter("world_tint", Vector3(t.r, t.g, t.b))


func _find_tint() -> CanvasModulate:
	var scene := get_parent()
	if scene == null:
		return null
	for c in scene.get_children():
		if c is CanvasModulate:
			return c
	return null
