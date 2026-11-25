class_name InkSketch
extends RefCounted
## A portrait redrawn as a sepia ink-wash sketch, as a clerk would draw someone into the ledger (the
## journal's People pages). Made in code from the portrait, so it follows every portrait change: brown
## washes in three flat tones, dark ink lines where the picture has edges and round the silhouette, and the
## bottom brushed away in a ragged stroke, so the waist-up cut reads as a finished sketch. No dither.

const INK := Color("2a2019")
const SEPIA := Color("604028")
const SEPIA_LIGHT := Color("8c6846")
const WASH := [0.0, 0.35, 0.55, 0.8]  # how strong each wash tone is, lightest first
const STEPS := [0.38, 0.6, 0.8]  # darkness at which each tone starts
const EDGE := 0.045  # how strong an edge must be to get an ink line
const FADE_FROM := 0.55  # how far down the brushed-away bottom starts

static var _cache := {}


## The sketch of tex at width w (height kept in proportion). Made once per portrait and width.
static func of(tex: Texture2D, w: int) -> ImageTexture:
	if tex == null:
		return null
	var key := "%d|%d" % [tex.get_rid().get_id(), w]
	if _cache.has(key):
		return _cache[key]
	if _cache.size() > 64:
		_cache.clear()
	var src := tex.get_image()
	if src == null:
		return null
	var out := make(src, w)
	var t := ImageTexture.create_from_image(out)
	_cache[key] = t
	return t


static func make(src: Image, w: int) -> Image:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var h := maxi(1, int(round(float(img.get_height()) * w / img.get_width())))
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var lum := PackedFloat32Array()
	var al := PackedByteArray()
	lum.resize(w * h)
	al.resize(w * h)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			lum[y * w + x] = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
			al[y * w + x] = 1 if c.a > 0.5 else 0
	var b_fine := _blur(lum, w, h, 0.5)
	var b_tone := _blur(lum, w, h, 0.6)
	var b_wide := _blur(lum, w, h, 1.4)
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.12
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var down := float(y) / maxf(h - 1, 1)
		for x in w:
			var i := y * w + x
			if al[i] == 0:
				continue
			# The bottom brushed away: a ragged edge from noise, never a dither.
			var f := 1.0 - (down - FADE_FROM) / (1.0 - FADE_FROM)
			if f + noise.get_noise_2d(x, y) * 0.45 - 0.05 <= 0.0:
				continue
			var silhouette := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
					or al[i - 1] == 0 or al[i + 1] == 0 or al[i - w] == 0 or al[i + w] == 0
			if silhouette or b_wide[i] - b_fine[i] > EDGE:
				out.set_pixel(x, y, INK)
				continue
			var d := 1.0 - b_tone[i]
			var lvl := 0
			for s in STEPS:
				if d > s:
					lvl += 1
			if lvl > 0:
				out.set_pixel(x, y, Color(SEPIA if lvl >= 2 else SEPIA_LIGHT, WASH[lvl]))
	return out


## A separable gaussian blur of a w x h grey picture.
static func _blur(v: PackedFloat32Array, w: int, h: int, sigma: float) -> PackedFloat32Array:
	var r := maxi(1, int(ceil(sigma * 3.0)))
	var k := PackedFloat32Array()
	var sum := 0.0
	for j in range(-r, r + 1):
		var g := exp(-float(j * j) / (2.0 * sigma * sigma))
		k.append(g)
		sum += g
	for j in k.size():
		k[j] /= sum
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var a := 0.0
			for j in range(-r, r + 1):
				a += v[y * w + clampi(x + j, 0, w - 1)] * k[j + r]
			tmp[y * w + x] = a
	for y in h:
		for x in w:
			var a := 0.0
			for j in range(-r, r + 1):
				a += tmp[clampi(y + j, 0, h - 1) * w + x] * k[j + r]
			out[y * w + x] = a
	return out
