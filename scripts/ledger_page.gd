class_name LedgerPage
extends RefCounted
## A worn ledger page for the menus' reading panes (docs/ART_STYLE.md "Ledger pages"): the item, skill or
## person you are looking at is written up on a page torn out of a ledger, like the dialogue box, instead of
## on a dark panel. The paper is pixel art made once per size and kept: two or three paper tones in soft
## blotches, foxing, a tea ring, a crease, a folded corner, edges browned with age, ragged torn edges.
##
## Text is written on the page's own ruled lines and between its margins, never across them. Start a page
## with LedgerPage.begin(), then write it top down; each call takes the next ruled line(s):
##   var pg := LedgerPage.begin(self, rect, font)
##   pg.heading("Quill-knife")
##   pg.line("No bonus", 8, LedgerPage.GREEN)
##   pg.pair("Damage", "10")
##   pg.para(long_text)
## The ruling follows the text size option (Access), so lines stay lined up at every size. A page that runs
## out of lines ends its last line with "...".

const PAPER := Color("d6cdba")
const PAPER_LIGHT := Color("e6dfcd")
const PAPER_MID := Color("c9bea4")
const PAPER_DARK := Color("b5a68a")
const STAIN := Color("c9a97a")
const AGE := Color("a07a4e")
const EDGE := Color("5a3e28")
const RULE := Color("9fa9b4")
const MARGIN_RED := Color("b0604c")
const INK := Color("2a2019")
const INK_SOFT := Color("5a4a3c")
## Accent inks that read on the paper (the dark panels' gold, green and red are too light here).
const GOLD := Color("8a5a14")
const GREEN := Color("3d5130")
const RED := Color("85402f")
const BLUE := Color("2b3f6e")
const PLUM := Color("4a3060")

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

static var _cache := {}

var ci: CanvasItem
var font: Font
var box: Rect2
var lh := 11.0  # distance between the ruled lines
var x0 := 0.0  # where text starts: just past the red margin
var x1 := 0.0  # where text must end: the right margin
var first := 0.0  # y of the first ruled line
var line_i := 0  # the next line to write on
var lines := 0  # how many ruled lines the page has
var log = null  # an Array to note each text drawn in, as [rect, page box, text], for the layout tests


## Draws the page in box (its shadow too) and returns a writer for it. base_size is the body text size the
## ruling is spaced for. light wears the page less (no tea ring or ink blot, fewer patches): for the
## dialogue box, where the portraits are the thing to look at.
static func begin(on: CanvasItem, r: Rect2, f: Font, base_size := 8, light := false) -> LedgerPage:
	var pg := LedgerPage.new()
	pg.ci = on
	pg.font = f
	pg.box = Rect2(r.position.floor(), r.size.floor())
	var fh := f.get_height(Access.fs(base_size)) if f != null else 8.0
	pg.lh = maxf(Access.px(11.0), ceilf(fh) + 2.0)
	pg.first = pg.box.position.y + floorf(pg.lh * 1.7)  # a deeper head band, for the heading
	pg.x0 = pg.box.position.x + 24.0
	pg.x1 = pg.box.end.x - 10.0
	pg.lines = maxi(0, int(floorf((pg.box.end.y - 8.0 - pg.first) / pg.lh)) + 1)
	if pg.box.size.x >= 40.0 and pg.box.size.y >= 30.0:
		var tex := paper(Vector2i(pg.box.size), pg.lh, pg.first - pg.box.position.y, light)
		on.draw_texture(tex, pg.box.position + Vector2(3, 3), Color(0, 0, 0, 0.45))
		on.draw_texture(tex, pg.box.position)
	return pg


## How tall a page must be to hold n lines after its heading, for laying a page out to fit its text.
static func height_for(n: int, f: Font, base_size := 8) -> float:
	var fh := f.get_height(Access.fs(base_size)) if f != null else 8.0
	var step := maxf(Access.px(11.0), ceilf(fh) + 2.0)
	return floorf(step * 1.7) + n * step + 9.0


## How many ruled lines text takes on a page of width w (the margins come off it).
static func lines_for(s: String, f: Font, size: int, w: float) -> int:
	return InkMenu.wrap_px(f, s, Access.fs(size), w - 34.0).size()


## The ruled line's y for line k (text sits on it: its baseline one pixel above).
func rule_y(k: int) -> float:
	return first + k * lh


func full() -> bool:
	return line_i >= lines


func left() -> int:
	return maxi(0, lines - line_i)


## Leaves n lines empty.
func skip(n := 1) -> void:
	line_i += n


## The title on the first line(s), in the heading font. An icon id puts that icon in the head band's right
## corner, and the heading stops short of it.
func heading(s: String, size := 12, col := INK, icon_id := "") -> void:
	var w := x1 - x0
	if icon_id != "" and UiSkin.draw_icon(ci, icon_id, Rect2(Vector2(x1 - 30.0, box.position.y + 6.0), Vector2(30, 30))):
		w -= 34.0
	_write(UiSkin.TITLE_FONT, s, size, col, x0, w)
	line_i += 1


## One line of text on the next ruled line, cut with "..." at the margin. right puts a value at the right
## margin on the same line (a stat and its number).
func line(s: String, size := 8, col := INK, right := "", right_col := INK) -> void:
	if full():
		return
	var w := x1 - x0
	if right != "":
		var rw := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
		ci.draw_string(font, Vector2(x1 - rw, _base()), right, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), right_col)
		_note(font, right, size, x1 - rw)
		w -= rw + 6.0
	_write(font, s, size, col, x0, w)
	line_i += 1


## A label and its value on one line.
func pair(label: String, value: String, size := 8, col := INK_SOFT, value_col := INK) -> void:
	line(label, size, col, value, value_col)


## A label in a column of its own and a value that wraps beside it, each line of it on a ruled line
## (a report's "Found: ..." rows). Returns how many lines it took.
func field(label: String, value: String, label_w: float, size := 8, col := INK_SOFT, value_col := INK) -> int:
	if full():
		return 0
	_write(font, label, size, col, x0, label_w - 6.0)
	var n := 0
	for ln in InkMenu.wrap_px(font, value, Access.fs(size), x1 - x0 - label_w):
		if full():
			break
		_write(font, ln, size, value_col, x0 + label_w, x1 - x0 - label_w)
		line_i += 1
		n += 1
	if n == 0:  # an empty value: the label still takes its line
		line_i += 1
		n = 1
	return n


## A line that starts with a small icon (a trait, a role), the text after it.
func icon_line(icon_id: String, s: String, size := 8, col := INK) -> void:
	if full():
		return
	var off := 0.0
	var ih := minf(lh - 1.0, 10.0)
	if UiSkin.draw_icon(ci, icon_id, Rect2(Vector2(x0, rule_y(line_i) - ih), Vector2(ih, ih))):
		off = ih + 3.0
	_write(font, s, size, col, x0 + off, x1 - x0 - off)
	line_i += 1


## Reserves n ruled lines for drawing of your own (stat pips, a bar) and returns their box: from just under
## the line above down to the last one's rule, between the margins. Returns an empty rect when the page is full.
func space(n := 1) -> Rect2:
	if line_i + n > lines:
		line_i = lines
		return Rect2()
	var r := Rect2(x0, rule_y(line_i - 1) + 1.0, x1 - x0, n * lh - 1.0)
	line_i += n
	return r


## Pips on paper (a stat out of 10, ranks): filled ones shaded in the ramp, empty ones an inked outline,
## standing on the box's bottom edge.
func pips(r: Rect2, have: int, of: int, cell: float, ramp = "bone") -> void:
	for i in of:
		var c := Rect2(r.position.x + i * cell, r.end.y - 6.0, cell - 3.0, 5.0)
		if i < have:
			UiSkin.bar(ci, c, 1.0, ramp)
		else:
			ci.draw_rect(Rect2(c.position + Vector2(0.5, 0.5), c.size - Vector2(1, 1)), Color(INK_SOFT, 0.55), false, 1.0)


## Wrapped text, one ruled line per line of it. Returns how many lines it took.
func para(s: String, size := 8, col := INK) -> int:
	var n := 0
	for ln in InkMenu.wrap_px(font, s, Access.fs(size), x1 - x0):
		if full():
			break
		_write(font, ln, size, col, x0, x1 - x0)
		line_i += 1
		n += 1
	return n


func _base() -> float:
	return rule_y(line_i) - 1.0


func _write(f: Font, s: String, size: int, col: Color, x: float, w: float) -> void:
	if full():
		return
	var t := Access.fit(f, s, Access.fs(size), w)
	ci.draw_string(f, Vector2(x, _base()), t, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)
	_note(f, t, size, x)


func _note(f: Font, t: String, size: int, x: float) -> void:
	if log == null or t == "":
		return
	var top := _base() - f.get_ascent(Access.fs(size))
	log.append([Rect2(x, top, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x, f.get_height(Access.fs(size))), box, t])


## A colour from the dark panels turned into an ink that reads on the paper: greys become ink, colours
## keep their hue but go dark.
static func ink(c: Color) -> Color:
	if c.s < 0.25:
		return INK if c.v > 0.7 else INK_SOFT
	return Color.from_hsv(c.h, minf(c.s * 1.1, 0.8), 0.42)


## The paper itself, size px, ruled every lh from first_rule down. Made once per size and kept.
static func paper(size: Vector2i, lh: float, first_rule: float, light := false) -> ImageTexture:
	var key := "%dx%d:%d:%d:%s" % [size.x, size.y, int(lh), int(first_rule), light]
	if _cache.has(key):
		return _cache[key]
	if _cache.size() > 24:
		_cache.clear()
	var tex := ImageTexture.create_from_image(_make(size, lh, first_rule, light))
	_cache[key] = tex
	return tex


static func _make(size: Vector2i, lh: float, first_rule: float, light := false) -> Image:
	var w := size.x
	var h := size.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 1312 + w * 3 + h  # every page size its own wear, so screens don't share one stain
	noise.frequency = 0.018
	var fine := FastNoiseLite.new()
	fine.seed = 77
	fine.frequency = 0.22
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410 + w * 7 + h * 13
	# Torn edges: top and bottom ragged, the sides a little uneven.
	var top := PackedInt32Array()
	var bot := PackedInt32Array()
	for x in w:
		top.append(clampi(int(2.0 + 1.6 * noise.get_noise_1d(x * 3.0) + 1.2 * sin(x * 0.07)), 0, 5))
		bot.append(h - 1 - clampi(int(2.5 + 2.0 * noise.get_noise_1d(x * 3.0 + 500.0)), 0, 6))
	var lft := PackedInt32Array()
	var rgt := PackedInt32Array()
	for y in h:
		lft.append(clampi(int(1.0 + 1.0 * noise.get_noise_1d(y * 2.0 + 900.0)), 0, 3))
		rgt.append(w - 1 - clampi(int(1.0 + 1.2 * noise.get_noise_1d(y * 2.0 + 1300.0)), 0, 3))
	# A tea ring somewhere in the lower right, a crease across, the corner folded down.
	var ring_c := Vector2(w * rng.randf_range(0.62, 0.8), h * rng.randf_range(0.55, 0.78))
	var ring_r := clampf(minf(w, h) * 0.16, 10.0, 26.0)
	var crease_x0 := w * 0.58
	var crease_x1 := w * 0.5
	var fold := 9
	var patch := 0.45 if light else 0.3  # how far the noise must go before a patch shows
	if light:
		ring_r = -100.0  # no tea ring
	for y in h:
		for x in w:
			if y < top[x] or y > bot[x] or x < lft[y] or x > rgt[y]:
				continue
			var th: float = (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
			var n := noise.get_noise_2d(x, y)
			var c := PAPER
			# Big soft patches: lighter where the page caught the light, a mid tone where it has been
			# handled, each feathered in with a dither at its edge only.
			if n > patch:
				c = PAPER_LIGHT if n - patch > th * 0.12 else PAPER
			elif n < -patch:
				c = PAPER_MID if -patch - n > th * 0.12 else PAPER
				if n < -0.62 and fine.get_noise_2d(x, y) > 0.35:
					c = PAPER_DARK
			# Browned with age towards the edges.
			var e := mini(mini(y - top[x], bot[x] - y), mini(x - lft[y], rgt[y] - x))
			if e < 7 and float(e) / 7.0 < th:
				c = PAPER_DARK if e > 1 else AGE
			# The tea ring: a broken band, darker on its rim.
			var d := Vector2(x, y).distance_to(ring_c)
			var band := absf(d - ring_r)
			if band < 1.6 and fine.get_noise_2d(x * 0.6, y * 0.6) > -0.35:
				c = STAIN
			elif d < ring_r - 1.0 and th < 0.18:
				c = c.lerp(STAIN, 0.5)
			# The crease: a light ridge with a shadow beside it.
			var cx := lerpf(crease_x0, crease_x1, float(y) / h)
			if absf(x - cx) < 0.5:
				c = PAPER_LIGHT
			elif absf(x - cx - 1.0) < 0.5 and th < 0.7:
				c = PAPER_MID
			img.set_pixel(x, y, c)
	# Foxing: little rust spots.
	for i in int(w * h / (2800 if light else 1400)):
		var p := Vector2i(rng.randi_range(4, w - 5), rng.randi_range(4, h - 5))
		if img.get_pixelv(p).a > 0.0:
			img.set_pixelv(p, STAIN if rng.randf() < 0.7 else AGE)
			if rng.randf() < 0.35 and img.get_pixel(p.x + 1, p.y).a > 0.0:
				img.set_pixel(p.x + 1, p.y, STAIN)
	# The ruling, worn through in places, and the red margin (a double line).
	var y := first_rule
	while y < h - 6:
		var yi := int(y)
		for x in range(6, w - 6):
			if img.get_pixel(x, yi).a > 0.0 and fine.get_noise_2d(x * 0.5, yi * 3.0) > -0.55:
				img.set_pixel(x, yi, img.get_pixel(x, yi).lerp(RULE, 0.75))
		y += lh
	for yy in range(3, h - 3):
		for mx in [18, 20]:
			if img.get_pixel(mx, yy).a > 0.0 and (mx == 18 or (yy / 3) % 5 != 0):
				img.set_pixel(mx, yy, img.get_pixel(mx, yy).lerp(MARGIN_RED, 0.8 if mx == 18 else 0.45))
	# Ink: a blot and its spatter near the top right, a smudged thumbprint at the bottom left.
	for i in (0 if light else 1):
		_blot(img, rng, Vector2(w - 26, 12), 3.0, INK)
	for i in (0 if light else 7):
		var p2 := Vector2(w - 26, 12) + Vector2(rng.randf_range(-12, 12), rng.randf_range(-6, 8))
		_blot(img, rng, p2, rng.randf_range(0.5, 1.4), INK)
	for i in (0 if light else 18):
		var p3 := Vector2(rng.randf_range(10, 22), h - rng.randf_range(10, 20))
		if img.get_pixelv(Vector2i(p3)).a > 0.0 and rng.randf() < 0.6:
			img.set_pixelv(Vector2i(p3), img.get_pixelv(Vector2i(p3)).lerp(INK, 0.35))
	# The folded corner: the corner beyond the fold line (x - y = k) is gone, and lies folded back over the
	# page as its mirror image, the paper's darker underside, with the fold inked.
	var k := w - fold
	for yy in fold:
		for xx in range(k + yy + 1, w):
			img.set_pixel(xx, yy, Color(0, 0, 0, 0))
			var fx := yy + k
			var fy := xx - k
			if fx >= 0 and fy < h:
				img.set_pixel(fx, fy, PAPER_DARK if (fx + fy) % 4 != 0 else PAPER_MID)
	for i in fold:
		img.set_pixel(k + i, i, EDGE)  # the fold
		img.set_pixel(k, i, EDGE)  # the flap's edges
		img.set_pixel(k + i, fold - 1, EDGE)
	# The torn edge, inked darker.
	for x in w:
		if img.get_pixel(x, top[x]).a > 0.0:
			img.set_pixel(x, top[x], EDGE if x % 5 != 0 else AGE)
		if img.get_pixel(x, bot[x]).a > 0.0:
			img.set_pixel(x, bot[x], EDGE)
	for yy in h:
		if img.get_pixel(lft[yy], yy).a > 0.0:
			img.set_pixel(lft[yy], yy, AGE)
		if img.get_pixel(rgt[yy], yy).a > 0.0:
			img.set_pixel(rgt[yy], yy, EDGE)
	return img


static func _blot(img: Image, rng: RandomNumberGenerator, c: Vector2, r: float, col: Color) -> void:
	for y in range(int(c.y - r - 1), int(c.y + r + 2)):
		for x in range(int(c.x - r - 1), int(c.x + r + 2)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if Vector2(x, y).distance_to(c) <= r + rng.randf_range(-0.3, 0.3) and img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, col)
