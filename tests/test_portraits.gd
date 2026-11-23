extends "res://tests/test_case.gd"
## Portrait art checks (issue #169). Every portrait in assets/portraits/ is hi-res pixel art made by
## tools/cut_portraits.py: 224x336, hard alpha, no stray specks, and no leftover background along the
## silhouette (the grey or the pale glow the generator paints round hair, which shows as white specks on
## a dark scene).
##
## The leftover check counts light, colourless pixels in the outer 3-pixel ring of the figure. A few
## characters are pale at the edge by design (a white hood, silver hair). Each was checked by eye and has
## its own ceiling in PALE_OK; anyone else must stay under PALE_MAX. A new pale character goes in the list
## only after looking at it on a dark background.

const DIR := "res://assets/portraits/"
const SIZE := Vector2i(224, 336)
const RING := 3
const PALE_MAX := 10  # per mille of the ring
## Reviewed 2026-11-21: Hild's white hood, the Auditor's quill-feather blade, Ilse's silver hair and
## armour, the Merrow kids' pale hair and collars, Verity's bone robe and erased sleeve.
## Reviewed 2026-11-23 (portraits redrawn to match the sprites): Quill's steel-grey hair, white quill and papers;
## Verity's cream robe and erased hem.
## Reviewed 2026-11-23 (painted redraws): Hesper's pale rolled map, open at the end (Nell is her Chapter 2 stand-in).
const PALE_OK := {"abeyance": 160, "auditor": 35, "hesper": 30, "ilse": 200, "merrow": 50, "nell": 30, "quill": 135, "verity": 175}
const SPECK := 20  # opaque islands (8-connected) smaller than this float free of the figure


func _portrait_files() -> Array:
	var out := []
	for f in DirAccess.get_files_at(DIR):
		f = f.trim_suffix(".import")  # exported builds list only the import files (desktop smoke test, #145)
		if f.ends_with(".png") and not out.has(f):
			out.append(f)
	return out


func test_portraits_are_pixel_art_at_dialogue_size() -> void:
	var files := _portrait_files()
	check(files.size() > 0, "no portraits found")
	for f in files:
		var img: Image = (load(DIR + f) as Texture2D).get_image()
		if not check_eq(img.get_size(), SIZE, "%s: size" % f):
			continue
		var soft := 0
		for y in SIZE.y:
			for x in SIZE.x:
				var a := img.get_pixel(x, y).a8
				if a != 0 and a != 255:
					soft += 1
		check(soft == 0, "%s: %d half-transparent pixels (pixel portraits use hard alpha)" % [f, soft])


func test_portraits_have_no_leftover_background() -> void:
	for f in _portrait_files():
		var img: Image = (load(DIR + f) as Texture2D).get_image()
		if img.get_size() != SIZE:
			continue  # reported by the size test
		var w := SIZE.x
		var h := SIZE.y
		var solid := PackedByteArray()
		solid.resize(w * h)
		for y in h:
			for x in w:
				solid[y * w + x] = 1 if img.get_pixel(x, y).a8 > 127 else 0
		# Distance (in steps) from the outside: transparent pixels and the left/right/top frame. The
		# bottom edge is where the frame cuts the figure, so it doesn't count as outside.
		var dist := PackedInt32Array()
		dist.resize(w * h)
		dist.fill(1 << 20)
		var q: Array[int] = []
		for i in w * h:
			var x := i % w
			var y := i / w
			if solid[i] == 0:
				dist[i] = 0
				q.append(i)
			elif x == 0 or x == w - 1 or y == 0:
				dist[i] = 1
				q.append(i)
		var head := 0
		while head < q.size():
			var i: int = q[head]
			head += 1
			if dist[i] >= RING:
				continue
			var x := i % w
			var y := i / w
			for n in [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]:
				if n[0] < 0 or n[0] >= w or n[1] < 0 or n[1] >= h:
					continue
				var j: int = n[1] * w + n[0]
				if solid[j] == 1 and dist[j] > dist[i] + 1:
					dist[j] = dist[i] + 1
					q.append(j)
		var ring := 0
		var pale := 0
		for i in w * h:
			if solid[i] == 1 and dist[i] <= RING:
				ring += 1
				var c := img.get_pixel(i % w, i / w)
				var lo := mini(c.r8, mini(c.g8, c.b8))
				var hi := maxi(c.r8, maxi(c.g8, c.b8))
				if lo >= 140 and hi - lo <= 24:
					pale += 1
		var id: String = f.get_basename().split("_")[0]
		var limit: int = PALE_OK.get(id, PALE_MAX)
		var permille := 1000 * pale / maxi(ring, 1)
		check(permille <= limit, "%s: %d pale pixels on the silhouette edge (%d per mille, limit %d): leftover background? Re-cut with tools/cut_portraits.py and look at it on a dark background" % [f, pale, permille, limit])
		_check_specks(f, solid, w, h)


## Small opaque islands away from the figure are flecks of background or noise.
func _check_specks(f: String, solid: PackedByteArray, w: int, h: int) -> void:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var sizes: Array[int] = []
	for s in w * h:
		if solid[s] == 0 or seen[s] == 1:
			continue
		var n := 0
		var st: Array[int] = [s]
		seen[s] = 1
		while not st.is_empty():
			var i: int = st.pop_back()
			n += 1
			var x := i % w
			var y := i / w
			for d in [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1], [x - 1, y - 1], [x + 1, y - 1], [x - 1, y + 1], [x + 1, y + 1]]:
				if d[0] < 0 or d[0] >= w or d[1] < 0 or d[1] >= h:
					continue
				var j: int = d[1] * w + d[0]
				if solid[j] == 1 and seen[j] == 0:
					seen[j] = 1
					st.append(j)
		sizes.append(n)
	var small := sizes.filter(func(n): return n < SPECK)
	check(small.is_empty(), "%s: %d stray specks (opaque islands under %d px)" % [f, small.size(), SPECK])
