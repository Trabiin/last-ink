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
	if kind == "ledger":
		grain(ci, r.grow(-7.0), tint.a)


## Where text and rows go inside a panel: past the frame and its inner shadow, with a pixel of air.
static func inner(r: Rect2, kind := "ledger") -> Rect2:
	return r.grow(-8.0 if kind == "ledger" else -2.0)


## Hand-made surfaces are never one flat colour: a sparse speckle of lighter and darker pixels (with the odd
## short fibre) over a panel or row, like the dithered shading on the sprites. One fixed pattern, so it never
## crawls; anchored to the screen, so rows side by side share it.
static var _grain: ImageTexture = null


static func grain(ci: CanvasItem, r: Rect2, alpha := 1.0) -> void:
	r = _snap(r)
	if r.size.x < 2.0 or r.size.y < 2.0 or alpha <= 0.02:
		return
	if _grain == null:
		_grain = _make_grain()
	var src := Rect2(Vector2(fposmod(r.position.x, 256.0), fposmod(r.position.y, 128.0)), r.size)
	src.size = src.size.min(Vector2(_grain.get_size()) - src.position)
	ci.draw_texture_rect_region(_grain, Rect2(r.position, src.size), src, Color(1, 1, 1, alpha))


static func _make_grain() -> ImageTexture:
	var w := 1024
	var h := 640
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var lite := Color(0.36, 0.38, 0.5, 0.22)
	var dark := Color(0.03, 0.03, 0.06, 0.32)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	for y in h:
		for x in w:
			var v := rng.randf()
			if v < 0.035:
				img.set_pixel(x, y, dark)
				if v < 0.006 and x + 1 < w:  # a short fibre
					img.set_pixel(x + 1, y, dark)
			elif v > 0.972:
				img.set_pixel(x, y, lite)
	return ImageTexture.create_from_image(img)


## Full-screen views (Roster, Buildings, Research...): the game dimmed behind, one big ledger frame round the
## whole screen and a brass rule under the header row, instead of a flat dark box.
static func screen(ci: CanvasItem, vs: Vector2, header_h := 25.0) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.035, 0.06, 0.9))
	# Pushed past the screen edge so the brass corners only peek in and never sit under the header text.
	panel(ci, Rect2(Vector2(-7, -7), vs + Vector2(14, 14)), "ledger")
	var y := floorf(header_h)
	ci.draw_rect(Rect2(10, y, vs.x - 20, 1), Color("a07a4e"))
	ci.draw_rect(Rect2(10, y + 1, vs.x - 20, 1), Color(0.07, 0.06, 0.1, 0.8))


## A full-screen view's header line beside its title: where it starts (after the title, never on it,
## at any text size or font) and the text trimmed with "..." so it stops short of the Close button.
## Returns [x, text]. `size` is the line's unscaled font size; the title is `title` at `title_size`.
static func header_line(font: Font, title: String, title_size: int, text: String, size: int, view_w: float,
		min_x := 0.0, title_font: Font = null, x0 := 8.0) -> Array:
	var tf := title_font if title_font else font
	var x := maxf(min_x, x0 + tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(title_size)).x + 10.0)
	return [x, Access.fit(font, text, Access.fs(size), view_w - 64.0 - x)]


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


# ---------------------------------------------------------------- pixel bars, rows and tabs
## Bars, list rows and slot tabs drawn as pixel art (issue: flat single-colour bars clashed with the art):
## whole pixels only, an ink outline, a recessed trough, and every fill shaded from a 3-4 step ramp
## (shadow, base, light, highlight) out of the style palette, with notches that count the value.
## docs/ART_STYLE.md "UI bars and rows" lists the ramps.

const BAR_INK := Color("12141f")  # outline
const BAR_TROUGH := Color("1f2233")  # empty part
const BAR_TROUGH_LIT := Color("2e3247")  # the trough's lower lip
const BRASS := [Color("5a3e28"), Color("a07a4e"), Color("c9a97a"), Color("e8c65a")]
## Fill ramps: [shadow, base, light, highlight]. Muted on purpose; the light/highlight rows carry the shine.
const RAMP := {
	"hp": [Color("3d5130"), Color("566b3a"), Color("7d8c4c"), Color("a3a865")],  # moss: healthy
	"hp_mid": [Color("5a3e28"), Color("a07a4e"), Color("c9a97a"), Color("e8c65a")],  # brass: hurt
	"hp_low": [Color("5c2a26"), Color("a3243b"), Color("c4504a"), Color("d98a6e")],  # crimson: in danger
	"enemy": [Color("5c2a26"), Color("a3243b"), Color("c4504a"), Color("d98a6e")],
	"ink": [Color("2b3448"), Color("3a5f9e"), Color("5b84c4"), Color("7fa8ec")],
	"power": [Color("3a2a1c"), Color("7d5836"), Color("a07a4e"), Color("c9a97a")],
	"power_full": [Color("7d5836"), Color("c9a24a"), Color("e8c65a"), Color("f7e3a6")],
	"xp": [Color("3b2a4a"), Color("6a4a7e"), Color("8f6fae"), Color("b49bcc")],  # plum
	"brass": [Color("5a3e28"), Color("a07a4e"), Color("c9a97a"), Color("e8c65a")],
	"bone": [Color("8f8270"), Color("b5a68a"), Color("d6cdba"), Color("e6dfcd")],
	"rust": [Color("5c2a26"), Color("85402f"), Color("c2622d"), Color("d98a5a")],
	"slate": [Color("2b3448"), Color("3f4c66"), Color("5b6b85"), Color("7f8ca3")],
	"moss": [Color("2a3a22"), Color("3d5130"), Color("566b3a"), Color("7d8c4c")],
	"poison": [Color("2a3a22"), Color("4d8a2c"), Color("6fd13a"), Color("a8e07a")],
	"stone": [Color("2e3247"), Color("575b6b"), Color("7a7d88"), Color("a3a3a6")],
}


## The ramp for any colour: a named one, or four steps built from the colour itself, pulled toward the
## palette's muted night slate so a bright data colour (a tech's "ffd166") still sits in the art.
static func ramp(c: Variant) -> Array:
	if c is String and RAMP.has(c):
		return RAMP[c]
	if c is Array:
		return c
	var col: Color = c if c is Color else Color(str(c))
	var base := col.lerp(Color("2e3247"), 0.28)
	base.s = minf(base.s, 0.62)
	return [base.darkened(0.45), base, base.lightened(0.22), base.lightened(0.42)]


## The HP ramp for a fill fraction: moss, brass under half, crimson under a quarter.
static func hp_ramp(f: float) -> Array:
	return RAMP["hp"] if f > 0.5 else (RAMP["hp_mid"] if f > 0.25 else RAMP["hp_low"])


static func _snap(r: Rect2) -> Rect2:
	var p := r.position.round()
	return Rect2(p, (r.position + r.size).round() - p)


## A framed pixel bar filling rect r (the inside: the ink frame sits one pixel outside it).
##   f       fill 0..1
##   ramp    a RAMP name, a colour (a ramp is built from it) or a [shadow, base, light, highlight] array
##   opts    notch: a notch every this many pixels (0 = none); notches: fractions to notch at instead
##           (techs reached on the charge gauge); hatch: diagonal stripes over the fill (low HP, with
##           Access.danger_patterns, so it never rests on colour alone); dim: drawn faded (an unused colour);
##           ghost: a second fraction drawn behind the fill in pale bone (HP just lost, a preview);
##           frame: false to leave out the ink frame (a bar sitting inside its own panel edge).
static func bar(ci: CanvasItem, r: Rect2, f: float, rmp: Variant = "brass", opts := {}) -> void:
	r = _snap(r)
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	var rp := ramp(rmp)
	var a := 0.45 if opts.get("dim", false) else 1.0
	if opts.get("frame", true):
		ci.draw_rect(r.grow(1.0), Color(BAR_INK, a))
	ci.draw_rect(r, Color(BAR_TROUGH, a))
	if r.size.y >= 3.0:
		ci.draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Color(BAR_TROUGH_LIT, a))
	var ghost := clampf(float(opts.get("ghost", 0.0)), 0.0, 1.0)
	if ghost > f:
		var gw := roundf(r.size.x * ghost)
		ci.draw_rect(Rect2(r.position, Vector2(gw, r.size.y)), Color(Color("8f8270"), a))
	f = clampf(f, 0.0, 1.0)
	var w := roundf(r.size.x * f)
	if f > 0.0 and w < 1.0:
		w = 1.0
	if w >= 1.0:
		var fr := Rect2(r.position, Vector2(w, r.size.y))
		ci.draw_rect(fr, Color(rp[1], a))
		var h := r.size.y
		if h >= 2.0:
			ci.draw_rect(Rect2(fr.position, Vector2(w, 1.0)), Color(rp[2], a))  # lit top row
		if h >= 3.0:
			ci.draw_rect(Rect2(fr.position.x, fr.end.y - 1.0, w, 1.0), Color(rp[0], a))  # shaded bottom row
		if h >= 5.0:  # a short gleam on the second row near the start, like light on glass
			ci.draw_rect(Rect2(fr.position.x + 1.0, fr.position.y + 1.0, minf(w - 2.0, clampf(roundf(r.size.x * 0.12), 2.0, 10.0)), 1.0), Color(rp[3], a))
		if opts.get("hatch", false) and h >= 2.0:
			for x in range(0, int(w), 3):  # 1 px stripes leaning right, in the ramp's shadow
				for y in int(h):
					var px := x + y
					if px < int(w):
						ci.draw_rect(Rect2(fr.position.x + px, fr.position.y + y, 1.0, 1.0), Color(rp[0], a))
		if w < r.size.x and w >= 2.0:  # the leading edge, one step lighter
			ci.draw_rect(Rect2(fr.end.x - 1.0, fr.position.y, 1.0, h - (1.0 if h >= 3.0 else 0.0)), Color(rp[2], a))
	var marks: Array = []
	var notch := float(opts.get("notch", 0.0))
	if notch >= 3.0:
		var x2 := notch
		while x2 < r.size.x - 1.0:
			marks.append(roundf(x2))
			x2 += notch
	for nf in opts.get("notches", []):
		var nx := roundf(r.size.x * float(nf))
		if nx > 0.0 and nx < r.size.x:
			marks.append(nx)
	for m in marks:
		var lit: bool = m < w
		ci.draw_rect(Rect2(r.position.x + m, r.position.y, 1.0, r.size.y), Color(rp[0] if lit else BAR_INK, a * (1.0 if lit else 0.8)))


## A notch spacing in pixels so a bar of width w shows one notch per `per` of a value whose top is `of`
## (10 HP a notch); 0 when the notches would crowd closer than 4 px.
static func notch_every(w: float, of: float, per := 10.0) -> float:
	if of <= per:
		return 0.0
	var px := w * per / of
	return px if px >= 4.0 else 0.0


## The small bar over a fighter's head in the field (world pixels at the camera's zoom): one ink-framed
## row of fill shaded light over base, centred on x = 0 at the given top. Hidden at full health by callers.
static func field_bar(ci: CanvasItem, top: float, w: float, f: float, rmp: Variant = "enemy", hatch := false) -> void:
	var rp := ramp(rmp)
	var r := _snap(Rect2(-roundf(w / 2.0), top, roundf(w), 2.0))
	ci.draw_rect(r.grow(1.0), BAR_INK)
	ci.draw_rect(r, BAR_TROUGH)
	f = clampf(f, 0.0, 1.0)
	var fw := maxf(1.0 if f > 0.0 else 0.0, roundf(r.size.x * f))
	if fw >= 1.0:
		ci.draw_rect(Rect2(r.position, Vector2(fw, 1.0)), rp[2])
		ci.draw_rect(Rect2(r.position + Vector2(0, 1), Vector2(fw, 1.0)), rp[1])
		if hatch:
			for x in range(1, int(fw), 3):
				ci.draw_rect(Rect2(r.position.x + x, r.position.y, 1.0, 2.0), rp[0])


## A list row (a hero, a building, a research): a recessed ink panel with a lit lower lip and a dark top
## edge, in place of a flat rectangle; the chosen row gets a warm fill and a brass frame with corner studs.
## focused = false: the chosen row of a list that is not the one being steered (a muted frame).
static func row(ci: CanvasItem, r: Rect2, on := false, focused := true) -> void:
	r = _snap(r)
	if r.size.x < 3.0 or r.size.y < 3.0:
		return
	ci.draw_rect(r, Color("2a2019") if on else Color("191a26"))
	grain(ci, r.grow(-1.0))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.0)), BAR_INK)  # dark top edge: the row sits recessed
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Color("3a2a1c") if on else Color("262838"))  # lit lower lip
	if on:
		frame(ci, r, BRASS if focused else [Color("2a2019"), Color("5a3e28"), Color("7d5836"), Color("8f8270")])


## A brass pixel frame round r: a 1 px rule, darker on the lower and right sides (light from the top
## left), with a lighter stud at each corner.
static func frame(ci: CanvasItem, r: Rect2, col: Array = BRASS) -> void:
	r = _snap(r)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.0)), col[2])
	ci.draw_rect(Rect2(r.position, Vector2(1.0, r.size.y)), col[2])
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), col[1])
	ci.draw_rect(Rect2(r.end.x - 1.0, r.position.y, 1.0, r.size.y), col[1])
	for c in [r.position, Vector2(r.end.x - 2.0, r.position.y), Vector2(r.position.x, r.end.y - 2.0), r.end - Vector2(2, 2)]:
		ci.draw_rect(Rect2(c, Vector2(2, 2)), col[3])
		ci.draw_rect(Rect2(c + Vector2(1, 1), Vector2(1, 1)), col[0])


## A bookmark ribbon down the left edge of a row (a gear slot's kind, a tech's colour, a bond's mood):
## 4 px wide, shaded from its ramp, with a notched tail at the bottom, instead of a flat colour strip.
static func tab(ci: CanvasItem, r: Rect2, rmp: Variant, dim := false) -> void:
	r = _snap(r)
	var rp := ramp(rmp)
	var a := 0.4 if dim else 1.0
	var x := r.position.x + 1.0
	var top := r.position.y + 1.0
	var h := r.size.y - 3.0
	if h < 4.0:
		return
	ci.draw_rect(Rect2(x - 1.0, top, 6.0, h + 1.0), Color(BAR_INK, a))  # outline
	ci.draw_rect(Rect2(x, top, 4.0, h - 2.0), Color(rp[1], a))
	ci.draw_rect(Rect2(x, top, 1.0, h - 2.0), Color(rp[2], a))  # lit left edge
	ci.draw_rect(Rect2(x + 3.0, top, 1.0, h - 2.0), Color(rp[0], a))  # shaded right edge
	ci.draw_rect(Rect2(x, top, 4.0, 1.0), Color(rp[3], a))  # a stitch of light where it folds over the top
	# The swallow tail: two points with a notch between them.
	ci.draw_rect(Rect2(x, top + h - 2.0, 1.0, 2.0), Color(rp[1], a))
	ci.draw_rect(Rect2(x + 3.0, top + h - 2.0, 1.0, 2.0), Color(rp[0], a))
	ci.draw_rect(Rect2(x + 1.0, top + h - 2.0, 2.0, 1.0), Color(rp[0], a))


## A small square swatch (an Ink colour's chip): framed and shaded like a gem.
static func swatch(ci: CanvasItem, r: Rect2, rmp: Variant, dim := false) -> void:
	r = _snap(r)
	var rp := ramp(rmp)
	var a := 0.4 if dim else 1.0
	ci.draw_rect(r.grow(1.0), Color(BAR_INK, a))
	ci.draw_rect(r, Color(rp[1], a))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1.0)), Color(rp[2], a))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Color(rp[0], a))
	ci.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(1, 1)), Color(rp[3], a))


## A scroll bar: an ink-framed trough with a brass thumb (shaded, lit on its left) at `at` pixels down,
## `len` long.
static func scrollbar(ci: CanvasItem, track: Rect2, at: float, len: float) -> void:
	track = _snap(track)
	ci.draw_rect(track.grow(1.0), BAR_INK)
	ci.draw_rect(track, BAR_TROUGH)
	var th := _snap(Rect2(track.position.x, track.position.y + at, track.size.x, len)).intersection(track)
	if th.size.y < 1.0:
		return
	ci.draw_rect(th, BRASS[1])
	ci.draw_rect(Rect2(th.position, Vector2(1.0, th.size.y)), BRASS[2])
	ci.draw_rect(Rect2(th.position, Vector2(th.size.x, 1.0)), BRASS[3])
	ci.draw_rect(Rect2(th.position.x, th.end.y - 1.0, th.size.x, 1.0), BRASS[0])
