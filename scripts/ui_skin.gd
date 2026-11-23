class_name UiSkin
extends RefCounted
## The art pass UI look (docs/ART_STYLE.md "UI"): framed panels instead of plain rectangles, drawn as
## 9-slices from small palette-locked textures in assets/ui (PixelLab, picked in Phase 6), and the title
## font for headings. Body text uses the project font (Jersey 10, set as the theme's custom font).
##   ledger - dark ink-blue panel with a brass-cornered frame: HUD plates, menus, the dialogue box
##   paper  - torn parchment: signs, notes, tooltips
##   button - leather button with a brass rim: ability slots, choices

const TEX := {
	"ledger": preload("res://assets/ui/panel_ledger.png"),
	"paper": preload("res://assets/ui/panel_paper.png"),
	"button": preload("res://assets/ui/button.png"),
}
const MARGIN := {"ledger": 14, "paper": 9, "button": 6}
## Clean frames stretch; the torn paper edge repeats so it stays ragged.
const TILED := ["paper"]
## A FontVariation over Jacquard 12; the readable font option (Access) swaps its base for Atkinson Hyperlegible Bold.
const TITLE_FONT := preload("res://assets/fonts/heading.tres")
const PAPER_INK := Color("2a2019")  # text colour on paper
const PAGE_INK := Color("2a2019")  # dialogue text on the torn ledger page (UiSkin.page)
const PAGE_INK_SOFT := Color("5a4a3c")  # narration on the page
const PAGE_PAPER := Color("d9cfba")
const PAGE_RULE := Color(0.42, 0.5, 0.62, 0.22)
const PAGE_MARGIN := Color(0.62, 0.22, 0.18, 0.45)

static var _boxes := {}


static func box(kind: String) -> StyleBoxTexture:
	if not _boxes.has(kind):
		var sb := StyleBoxTexture.new()
		sb.texture = TEX[kind]
		var m: int = MARGIN[kind]
		sb.texture_margin_left = m
		sb.texture_margin_right = m
		sb.texture_margin_top = m
		sb.texture_margin_bottom = m
		if kind in TILED:
			sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
			sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		_boxes[kind] = sb
	return _boxes[kind]


## Draws a framed panel. The frame needs a little room, so tiny rects grow to the frame's minimum.
static func panel(ci: CanvasItem, r: Rect2, kind := "ledger", tint := Color.WHITE) -> void:
	var m: float = MARGIN[kind] * 2.0
	r.size = Vector2(maxf(r.size.x, m), maxf(r.size.y, m))
	var sb := box(kind)
	sb.modulate_color = tint
	ci.draw_style_box(sb, r.grow(2.0))


## Full-screen views (Roster, Buildings, Research...): the game dimmed behind, one big ledger frame round the
## whole screen and a brass rule under the header row, instead of a flat dark box.
static func screen(ci: CanvasItem, vs: Vector2, header_h := 25.0) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.035, 0.06, 0.9))
	# Pushed past the screen edge so the brass corners only peek in and never sit under the header text.
	panel(ci, Rect2(Vector2(-7, -7), vs + Vector2(14, 14)), "ledger")
	var y := floorf(header_h)
	ci.draw_rect(Rect2(10, y, vs.x - 20, 1), Color("a07a4e"))
	ci.draw_rect(Rect2(10, y + 1, vs.x - 20, 1), Color(0.07, 0.06, 0.1, 0.8))


## A gold highlight around a panel (the controlled hero, the chosen row).
static func highlight(ci: CanvasItem, r: Rect2, col := Color("e8c65a")) -> void:
	ci.draw_rect(r.grow(1.0), col, false, 1.0)


## Icons (assets/icons/<id>.png, 32px, picked in Phase 6). Ids follow the data: item, gear, ability, research,
## building and faction ids as they are; tech_<hero>, role_<role>, trait_<trait>, status_<kind>; gilt, supplies,
## ink, renown, insight. A missing icon is null, and callers just leave the space out.
static var _icons := {}


static func icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var p := "res://assets/icons/%s.png" % id
		_icons[id] = load(p) if ResourceLoader.exists(p) else null
	return _icons[id]


## Draws the icon into r (square). Returns whether there was one, so text can make room only when needed.
static func draw_icon(ci: CanvasItem, id: String, r: Rect2, tint := Color.WHITE) -> bool:
	var t := icon(id)
	if t == null:
		return false
	ci.draw_texture_rect(t, r, false, tint)
	return true



## The text sits on a torn-out ledger page: deckled edges, faint ruling, a red margin line, ink spatter, and the
## right edge fraying into blank paper where the Blank has been at it.
static func page(ci: CanvasItem, box: Rect2) -> void:
	if box.size.x < 8.0 or box.size.y < 8.0:  # a control not laid out yet: nothing to draw
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var x := box.position.x
	while x <= box.end.x:
		top.append(Vector2(x, box.position.y + rng.randf_range(-1.5, 1.5) + sin(x * 0.05) * 1.2))
		bottom.append(Vector2(x, box.end.y + rng.randf_range(-2.5, 1.0)))
		x += 4.0
	var poly := PackedVector2Array()
	poly.append_array(top)
	var b := bottom.duplicate()
	b.reverse()
	poly.append_array(b)
	# Shadow, then the page.
	var sh := PackedVector2Array()
	for p in poly:
		sh.append(p + Vector2(3, 4))
	ci.draw_colored_polygon(sh, Color(0, 0, 0, 0.45))
	ci.draw_colored_polygon(poly, PAGE_PAPER)
	# Paper grain: soft darker blotches.
	for i in 70:
		var gp := Vector2(rng.randf_range(box.position.x + 4, box.end.x - 4), rng.randf_range(box.position.y + 4, box.end.y - 4))
		ci.draw_rect(Rect2(gp.floor(), Vector2(rng.randi_range(2, 6), 1)), Color(0.45, 0.36, 0.25, rng.randf_range(0.05, 0.12)))
	# Ledger ruling and the red margin.
	var ry := box.position.y + 14.0
	while ry < box.end.y - 6.0:
		ci.draw_line(Vector2(box.position.x + 6, ry), Vector2(box.end.x - 6, ry), PAGE_RULE, 1.0)
		ry += 13.0
	ci.draw_line(Vector2(box.position.x + 22, box.position.y + 2), Vector2(box.position.x + 22, box.end.y - 2), PAGE_MARGIN, 1.0)
	# Torn edges inked darker.
	ci.draw_polyline(top, Color(0.35, 0.27, 0.19, 0.7), 1.0)
	ci.draw_polyline(bottom, Color(0.35, 0.27, 0.19, 0.7), 1.0)
	# Ink spatter in two corners.
	for c in [box.position + Vector2(10, box.size.y - 12), Vector2(box.end.x - 60, box.position.y + 8)]:
		for i in 6:
			var o := Vector2(rng.randf_range(-8, 8), rng.randf_range(-5, 5))
			ci.draw_circle(c + o, rng.randf_range(0.6, 2.2), Color(PAGE_INK, 0.55))
	# The right end frays into blank paper.
	for i in 24:
		var k := float(i) / 24.0
		ci.draw_rect(Rect2(box.end.x - 24 + i, box.position.y + 2, 1, box.size.y - 4), Color(0.95, 0.945, 0.92, k * k * 0.85))
	for i in 30:
		var fy := rng.randf_range(box.position.y + 2, box.end.y - 2)
		var fx := box.end.x - rng.randf() * rng.randf() * 34.0
		ci.draw_rect(Rect2(Vector2(fx, fy).floor(), Vector2(rng.randi_range(1, 3), 1)), Color(0.95, 0.945, 0.92, 0.8))


## A dry-brush ink stroke under a name.
static func brush(ci: CanvasItem, at: Vector2, w: float, col: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(w)
	for i in 3:
		var y := at.y + i
		ci.draw_line(Vector2(at.x + rng.randf_range(0, 3), y), Vector2(at.x + w - rng.randf_range(0, 6), y + rng.randf_range(-0.5, 0.5)), Color(col, 0.75 - i * 0.2), 1.0)


## Where a sign's lines go (the paper plate shown when standing at a signpost): a paper panel centred
## on the screen at height y, sized to the text, which wraps so it fits at every text size and screen.
## ~~text~~ is painted out (a struck-through old word, like a town's old population).
## Returns {"panel": Rect2, "lines": [[text, Vector2 baseline start, width], ...]}.
static func sign_layout(font: Font, vs: Vector2, y: float, text: String) -> Dictionary:
	var max_w := minf(vs.x - 48.0, Access.px(320.0))
	var lines := []
	for raw in text.split("\n"):
		for line in InkMenu.wrap_px(font, raw, Access.fs(10), max_w):
			lines.append(line)
	var w := 120.0
	for line in lines:
		w = maxf(w, font.get_string_size(line.replace("~~", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10)).x)
	var lh := Access.px(16.0)
	var panel := Rect2(vs.x / 2.0 - (w + 32.0) / 2.0, y - Access.fs(10) - Access.px(8.0), w + 32.0, lh * lines.size() + Access.px(12.0))
	var out := []
	var yy := y
	for line in lines:
		var lw := font.get_string_size(line.replace("~~", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10)).x
		out.append([line, Vector2(roundf((vs.x - lw) / 2.0), roundf(yy)), lw])
		yy += lh
	return {"panel": panel, "lines": out}


## Draws a sign: dark ink straight on the paper, with no outline (an outline round dark letters on
## light paper smears them into a blob). ~~struck~~ parts get a painted line through them.
static func sign(ci: CanvasItem, vs: Vector2, y: float, text: String) -> void:
	var font := ThemeDB.fallback_font
	var lay := sign_layout(font, vs, y, text)
	panel(ci, lay["panel"], "paper")
	for l in lay["lines"]:
		var at: Vector2 = l[1]
		var parts: PackedStringArray = str(l[0]).split("~~")
		for i in parts.size():
			var pw := font.get_string_size(parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10)).x
			if i % 2 == 1:  # painted out: faded ink with a thin red line through it, still readable
				ci.draw_string(font, at, parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10), Color(PAPER_INK, 0.7))
				var mid := roundf(at.y - Access.fs(10) * 0.3)
				ci.draw_rect(Rect2(at.x - 1.0, mid, pw + 2.0, maxf(1.0, roundf(Access.fs(10) * 0.1))), Color("8a2a20"))
			else:
				ci.draw_string(font, at, parts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10), PAPER_INK)
			at.x += pw
