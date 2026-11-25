class_name Dialogue
extends RefCounted
## Shared dialogue data and helpers (issue #11). Everything here is static, so any scene can use it
## without an autoload: Dialogue.talk("meadow_intro"), Dialogue.portrait("bran", "smug"), ...
##
## data/dialogue.json holds the words: conversations ("talks"), first chats in town ("first_talk"),
## event banter ("events") and walking banter zones per map ("banter"). See its _comment.
##
## A line is [speaker, text] or [speaker, text, expression]. Speaker is a recruit id, a key from
## "speakers" (characters who are not recruits) or "" for narration. Lines are normalised to
## [speaker, text, expression] by line().
##
## Portraits: assets/portraits/<id>_<expression>.png, then assets/portraits/<id>.png. Every speaker has
## one (tests/test_data.gd fails the build otherwise), except speakers whose "stage" is "letter": a
## letter read aloud stands on stage as a sealed sheet of paper (draw_letter). draw_bust is a last
## safety net for content added without a portrait and never shows in a passing build.
##
## Seen conversations and banter zones are saved with the campaign (Empire.to_dict "dialogue").
## Text speed is a per-device setting kept in user://settings.cfg.

const DATA_PATH := "res://data/dialogue.json"
const PORTRAIT_DIR := "res://assets/portraits/"
const SETTINGS_PATH := "user://settings.cfg"
## Typewriter speeds in characters per second. 0 = whole line at once.
const SPEEDS := [["Slow", 28.0], ["Normal", 60.0], ["Fast", 120.0], ["Instant", 0.0]]

static var seen := {}  # "talk:<id>" / "banter:<id>" / "event:<id>" -> true
static var _data := {}
static var _portraits := {}  # "<id>|<expr>" -> Texture2D or null
static var _speed := -1


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		# The main story's talks and speakers (data/story.json, issue #18), the personal missions'
		# (data/personal.json, issue #113) and the climax betrayal's (data/betrayal.json, issue #186) play
		# like any others.
		for k in ["speakers", "talks"]:
			if not _data.has(k):
				_data[k] = {}
			_data[k].merge(Story.data().get(k, {}))
			_data[k].merge(PersonalMissions.data().get(k, {}))
			_data[k].merge(Betrayal.data().get(k, {}))
			_data[k].merge(Incidents.data().get(k, {}))  # requests with a deadline (data/incidents.json)
	return _data


## [speaker, text, expression] from either list or {"who", "text", "expr"} form.
## Button tokens in the text ({tag:ledger}...) are filled for the device in use (Prompts.fill, issue #115).
static func line(l) -> Array:
	if typeof(l) == TYPE_DICTIONARY:
		return [String(l.get("who", "")), Prompts.fill(String(l.get("text", ""))), String(l.get("expr", ""))]
	var a: Array = l
	return [String(a[0]) if a.size() > 0 else "", Prompts.fill(String(a[1])) if a.size() > 1 else "", String(a[2]) if a.size() > 2 else ""]


static func lines(raw: Array) -> Array:
	return raw.map(func(l): return line(l))


## A whole conversation's lines, normalised. Empty when the id is unknown.
static func talk(id: String) -> Array:
	var t = data().get("talks", {}).get(id, {})
	if typeof(t) == TYPE_DICTIONARY:
		return lines(t.get("lines", []))
	return lines(t)


## A talk's choice for Ash ([] when it has none): [{"text", "reply": [lines], "betrayal": effect}] (issue #186).
static func talk_choice(id: String) -> Array:
	var t = data().get("talks", {}).get(id, {})
	return t.get("choice", []) if typeof(t) == TYPE_DICTIONARY else []


## Ash picked option i of a talk's choice: remembered with the campaign, and its effect applied.
static func make_choice(talk_id: String, i: int, opt: Dictionary) -> void:
	for k in seen.keys():
		if str(k).begins_with("choice:%s:" % talk_id):
			seen.erase(k)
	mark_seen("choice:%s:%d" % [talk_id, i])
	if opt.has("betrayal"):
		Betrayal.choose(str(opt["betrayal"]))


## Which option Ash picked in a talk's choice (-1 if none yet).
static func choice_made(talk_id: String) -> int:
	for k in seen:
		if str(k).begins_with("choice:%s:" % talk_id):
			return int(str(k).get_slice(":", 2))
	return -1


static func talk_title(id: String) -> String:
	var t = data().get("talks", {}).get(id, {})
	return String(t.get("title", "")) if typeof(t) == TYPE_DICTIONARY else ""


## The conversation someone starts the first time Ash talks to them in town ("" when none is left).
static func first_talk(who: String) -> String:
	var id := String(data().get("first_talk", {}).get(who, ""))
	if id == "" or is_seen("talk:" + id) or talk(id).is_empty():
		return ""
	return id


static func is_seen(key: String) -> bool:
	return seen.has(key)


static func mark_seen(key: String) -> void:
	seen[key] = true


# ---------------------------------------------------------------- who is speaking

static func speaker_info(who: String) -> Dictionary:
	return data().get("speakers", {}).get(who, {})


static func display_name(who: String) -> String:
	if who == "":
		return ""
	var info := speaker_info(who)
	if info.has("name"):
		return String(info["name"])
	if Empire.recruit_data.has(who):
		return Empire.short_name(who)
	return who.capitalize()


## The accent colour for name tags and card backgrounds.
static func accent(who: String) -> Color:
	var info := speaker_info(who)
	if info.has("color"):
		return Color(info["color"])
	var b: Dictionary = Empire.bond_info(who)
	if b.has("color"):
		return Color(b["color"])
	var cols := _colors(who)
	for k in ["accent", "cloth", "metal", "trim"]:
		if cols.has(k):
			return Color(cols[k])
	return Color("c9c3b6")


static func _colors(who: String) -> Dictionary:
	var info := speaker_info(who)
	if info.has("colors"):
		return info["colors"]
	return Empire.recruit(who).get("look", {}).get("colors", {}) if Empire.recruit_data.has(who) else {}


static func _col(cols: Dictionary, keys: Array, fallback: String) -> Color:
	for k in keys:
		if cols.has(k):
			return Color(cols[k])
	return Color(fallback)


## The portrait image for this speaker and expression, or null (letters, or a missing file).
static func portrait(who: String, expr := "") -> Texture2D:
	if who == "":
		return null
	var key := "%s|%s" % [who, expr]
	if _portraits.has(key):
		return _portraits[key]
	var tex: Texture2D = null
	var tries := []
	if expr != "":
		tries.append("%s%s_%s.png" % [PORTRAIT_DIR, who, expr])
	tries.append("%s%s.png" % [PORTRAIT_DIR, who])
	for p in tries:
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
			if tex:
				break
	_portraits[key] = tex
	return tex


## Draw this speaker into r: the portrait scaled to fit (feet on the bottom edge), a letter for letter
## speakers, or (safety net) a head-and-shoulders bust in their colours. dim darkens it (for whoever is not talking).
## Portraits face the viewer's left; flip = mirror them to face right (for the left side of the stage).
static func draw_portrait(ci: CanvasItem, r: Rect2, who: String, expr := "", dim := 0.0, flip := false) -> void:
	if is_blank(who):
		draw_blank(ci, r, dim)
		return
	if is_letter(who):
		draw_letter(ci, r, who, dim)
		return
	var tex := portrait(who, expr)
	var tint := Color(1, 1, 1).darkened(dim)
	if tex:
		var ts := tex.get_size()
		var sz := portrait_size(tex, minf(r.size.y, r.size.x * ts.y / ts.x))
		tex = fitted(tex, sz.y)
		var cx := r.get_center().x
		if flip:
			ci.draw_set_transform(Vector2(2.0 * cx, 0), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect(tex, Rect2(Vector2(cx - sz.x / 2.0, r.end.y - sz.y), sz), false, tint)
		if flip:
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_bust(ci, r, who, dim)


## Portraits are pixel art (224x336, issue #169), so they are drawn at a whole-number scale wherever
## they are shown big: asked for a height `h`, this gives the size to draw at. From three quarters of
## the art's own height up it snaps to 1x, 2x, ...; smaller (the journal thumbnail) it scales smoothly,
## drawn from fitted().
static func portrait_size(tex: Texture2D, h: float) -> Vector2:
	var ts := tex.get_size()
	if h >= ts.y * 0.75:
		return ts * maxf(1.0, roundf(h / ts.y))
	return Vector2(roundf(h * ts.x / ts.y), roundf(h))


static var _fitted := {}  # "<rid>|<h>" -> ImageTexture


## The portrait as drawn at height h: itself when that is a whole-number scale, otherwise a copy
## shrunk smoothly to exactly that size (nearest-neighbour shrinking would drop rows and columns).
static func fitted(tex: Texture2D, h: float) -> Texture2D:
	var ts := tex.get_size()
	if h >= ts.y * 0.75 or h < 1.0:
		return tex
	var key := "%d|%d" % [tex.get_rid().get_id(), int(h)]
	if not _fitted.has(key):
		var img := tex.get_image()
		if img == null:
			return tex
		img = img.duplicate()
		img.resize(int(roundf(h * ts.x / ts.y)), int(roundf(h)), Image.INTERPOLATE_LANCZOS)
		_fitted[key] = ImageTexture.create_from_image(img)
	return _fitted[key]


## Speakers that are a letter read aloud ("stage": "letter" in their speakers entry): no portrait. A "blank"
## speaker (the Vacancy, issue #186) has none either, and counts as staged too.
static func is_letter(who: String) -> bool:
	return str(speaker_info(who).get("stage", "")) in ["letter", "blank"]


static func is_blank(who: String) -> bool:
	return str(speaker_info(who).get("stage", "")) == "blank"


## The Vacancy on stage: a figure-shaped hole cut out of the scene, pure page-white, its edge an unsteady ink
## line, a few black bars drifting across it like words being struck out. Nothing to look at, on purpose.
static func draw_blank(ci: CanvasItem, r: Rect2, dim := 0.0) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var w := minf(r.size.x * 0.4, r.size.y * 0.24)
	var h := w * 2.4
	var base := Vector2(r.get_center().x, r.end.y - 92.0)
	var pts := PackedVector2Array()
	var steps := 36
	for i in steps + 1:
		var a := PI + PI * float(i) / steps  # a doorway arch over the top
		var wob := sin(t * (1.3 if not Access.reduce_flashing else 0.4) + i * 1.7) * 1.2
		pts.append(base + Vector2(cos(a) * (w / 2.0 + wob), -h + w / 2.0 + sin(a) * (w / 2.0 + wob)))
	pts.append(base + Vector2(w / 2.0, 0))
	pts.append(base + Vector2(-w / 2.0, 0))
	var white := Color("f6f4ee").darkened(dim * 0.4)
	ci.draw_colored_polygon(pts, white)
	ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.08, 0.06, 0.1, 0.8 * (1.0 - dim * 0.5)), 1.5)
	var rng := RandomNumberGenerator.new()
	for i in 5:
		rng.seed = i * 7919
		var y := base.y - h * rng.randf_range(0.15, 0.85)
		var bw := w * rng.randf_range(0.2, 0.55)
		var x := base.x - w * 0.4 + fmod(t * rng.randf_range(4.0, 9.0) + rng.randf() * w, w * 0.8 - bw * 0.5)
		ci.draw_rect(Rect2(x, y, bw, 4.0), Color(0.08, 0.06, 0.1, 0.85 * (1.0 - dim * 0.6)))


## A folded letter standing on the stage: a cream sheet with lines of handwriting in the sender's ink,
## a wax seal in the speaker's trim colour, lifted a little off the floor with a soft shadow.
static func draw_letter(ci: CanvasItem, r: Rect2, who: String, dim := 0.0) -> void:
	var cols := _colors(who)
	var paper := Color("efe6cf").darkened(dim)
	var shade := Color("d9ccab").darkened(dim)
	var edge := Color("a8956c").darkened(dim)
	var ink := Color("3e3150", 0.85).darkened(dim)
	var seal := _col(cols, ["trim"], "8f2a2a").darkened(dim)
	var w := minf(r.size.x * 0.62, r.size.y * 0.42)
	var h := w * 1.35
	var bob := sin(Time.get_ticks_msec() / 700.0) * 2.0
	# Standing just above the text box (which covers the bottom ~100 px of the stage).
	var c := Vector2(r.get_center().x, r.end.y - 104.0 - h / 2.0 + bob)
	ci.draw_set_transform(Vector2(c.x + 6, c.y + h / 2.0 + 8), 0.0, Vector2(1.0, 0.22))
	ci.draw_circle(Vector2.ZERO, w * 0.5, Color(0, 0, 0, 0.28))
	ci.draw_set_transform(c, deg_to_rad(-3.5), Vector2.ONE)
	var sheet := Rect2(Vector2(-w, -h) / 2.0, Vector2(w, h))
	ci.draw_rect(sheet.grow(1.0), edge)
	ci.draw_rect(sheet, paper)
	for k: int in [1, 2]:  # folded in three: a soft shaded band under each crease
		var fy: float = sheet.position.y + h * k / 3.0
		ci.draw_rect(Rect2(sheet.position.x, fy, w, h * 0.04), shade)
		ci.draw_line(Vector2(sheet.position.x, fy), Vector2(sheet.end.x, fy), edge, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(who)
	var y := sheet.position.y + h * 0.1
	var row := 0
	while y < sheet.end.y - h * 0.2:
		var x := sheet.position.x + w * (0.16 if row == 0 else 0.1)
		var end_x := sheet.end.x - w * rng.randf_range(0.08, 0.3)
		while x < end_x - w * 0.05:  # words: little looping strokes of handwriting
			var seg := minf(rng.randf_range(w * 0.05, w * 0.15), end_x - x)
			var pts := PackedVector2Array()
			var n := maxi(int(seg / 2.0), 2)
			for q in n + 1:
				var t := float(q) / n
				pts.append(Vector2(x + seg * t, y + sin(t * TAU * seg / 7.0 + row) * 1.2))
			ci.draw_polyline(pts, ink, 1.0)
			x += seg + w * 0.035
		y += h * 0.07
		row += 1
	# The signature, larger and slanted, then the wax seal at the foot of the sheet.
	var sig := PackedVector2Array()
	for q in 13:
		var t := q / 12.0
		sig.append(Vector2(sheet.end.x - w * 0.5 + w * 0.36 * t, sheet.end.y - h * 0.13 - sin(t * TAU * 1.5) * 2.5 - t * 3.0))
	ci.draw_polyline(sig, ink, 1.5)
	var sp := Vector2(-w * 0.2, sheet.end.y - h * 0.1)
	ci.draw_circle(sp, w * 0.1, seal.darkened(0.35))
	ci.draw_circle(sp, w * 0.085, seal)
	ci.draw_arc(sp, w * 0.05, 0.0, TAU, 16, seal.darkened(0.25), 1.0)
	ci.draw_circle(sp + Vector2(-w * 0.03, -w * 0.03), w * 0.022, seal.lightened(0.4))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Just the face, for small banter portraits: the top part of the portrait image, or a small bust.
static func draw_face(ci: CanvasItem, r: Rect2, who: String, expr := "") -> void:
	var tex := portrait(who, expr)
	ci.draw_rect(r, accent(who).darkened(0.7))
	if tex:
		var ts := tex.get_size()
		var side := ts.x * 0.62  # a square around the head, roughly the top third of a 2:3 portrait
		var src := Rect2((ts.x - side) / 2.0, ts.y * 0.04, side, side)
		ci.draw_texture_rect_region(tex, r, src)
	else:
		draw_bust(ci, Rect2(r.position + Vector2(-r.size.x * 0.25, 0), Vector2(r.size.x * 1.5, r.size.y * 1.7)), who, 0.0, r)
	ci.draw_rect(r, accent(who).lightened(0.1), false, 1.0)


## Safety-net bust drawn from the paper-doll colours, for a speaker whose portrait file is missing.
## clip: only draw inside this rect (used by draw_face, which zooms in on the head).
static func draw_bust(ci: CanvasItem, r: Rect2, who: String, dim := 0.0, clip := Rect2()) -> void:
	var cols := _colors(who)
	var skin := _col(cols, ["skin"], "d9a07a").darkened(dim)
	var cloth := _col(cols, ["cloth", "metal"], "5a4a6a").darkened(dim)
	var trim := _col(cols, ["trim", "accent", "metal"], "c9c3b6").darkened(dim)
	var hair := _col(cols, ["hair", "leather", "boots"], "3a2c22").darkened(dim)
	var c := Vector2(r.get_center().x, r.end.y)
	var w := r.size.x * 0.86
	var h := r.size.y
	var parts := []  # [kind, data, color]
	parts.append(["poly", PackedVector2Array([c + Vector2(-w / 2, 0), c + Vector2(-w / 2 + 8, -h * 0.3),
		c + Vector2(-w * 0.18, -h * 0.36), c + Vector2(w * 0.18, -h * 0.36),
		c + Vector2(w / 2 - 8, -h * 0.3), c + Vector2(w / 2, 0)]), cloth])
	parts.append(["poly", PackedVector2Array([c + Vector2(-w * 0.12, -h * 0.36), c + Vector2(w * 0.12, -h * 0.36),
		c + Vector2(0, -h * 0.22)]), skin.darkened(0.15)])
	var head := c + Vector2(0, -h * 0.56)
	var hr := r.size.x * 0.2
	parts.append(["rect", Rect2(head.x - hr * 0.35, head.y + hr * 0.6, hr * 0.7, h * 0.1), skin.darkened(0.1)])
	parts.append(["circle", [head + Vector2(0, -hr * 0.12), hr * 1.08], hair])
	parts.append(["circle", [head + Vector2(0, hr * 0.1), hr], skin])
	parts.append(["rect", Rect2(head.x - hr, head.y - hr * 0.9, hr * 2, hr * 0.55), hair])
	parts.append(["circle", [head + Vector2(-hr * 0.38, hr * 0.12), maxf(1.0, hr * 0.08)], Color(0.1, 0.08, 0.1)])
	parts.append(["circle", [head + Vector2(hr * 0.38, hr * 0.12), maxf(1.0, hr * 0.08)], Color(0.1, 0.08, 0.1)])
	for p in parts:
		match p[0]:
			"poly":
				var pts: PackedVector2Array = p[1]
				if clip.has_area():
					pts = _clip_poly(pts, clip)
				if pts.size() >= 3:
					ci.draw_colored_polygon(pts, p[2])
			"rect":
				var rr: Rect2 = p[1]
				if clip.has_area():
					rr = rr.intersection(clip)
				if rr.has_area():
					ci.draw_rect(rr, p[2])
			"circle":
				var cc: Vector2 = p[1][0]
				var rad: float = p[1][1]
				if clip.has_area():
					var poly := PackedVector2Array()
					for i in 20:
						poly.append(cc + Vector2.from_angle(TAU * i / 20.0) * rad)
					poly = _clip_poly(poly, clip)
					if poly.size() >= 3:
						ci.draw_colored_polygon(poly, p[2])
				else:
					ci.draw_circle(cc, rad, p[2])
	if not clip.has_area():
		ci.draw_line(c + Vector2(-w * 0.18, -h * 0.36), c + Vector2(0, -h * 0.2), trim, 2.0)
		ci.draw_line(c + Vector2(w * 0.18, -h * 0.36), c + Vector2(0, -h * 0.2), trim, 2.0)


static func _clip_poly(pts: PackedVector2Array, clip: Rect2) -> PackedVector2Array:
	var box := PackedVector2Array([clip.position, Vector2(clip.end.x, clip.position.y), clip.end, Vector2(clip.position.x, clip.end.y)])
	var res := Geometry2D.intersect_polygons(pts, box)
	return res[0] if not res.is_empty() else PackedVector2Array()


# ---------------------------------------------------------------- text speed (per device)

static func speed_index() -> int:
	if _speed < 0:
		_speed = 1
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK:
			_speed = clampi(int(cfg.get_value("dialogue", "text_speed", 1)), 0, SPEEDS.size() - 1)
	return _speed


static func speed_name() -> String:
	return Loc.t(SPEEDS[speed_index()][0])


## Characters per second for typewriter text (0 = show the whole line at once).
static func chars_per_sec() -> float:
	return SPEEDS[speed_index()][1]


static func cycle_speed() -> void:
	_speed = (speed_index() + 1) % SPEEDS.size()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("dialogue", "text_speed", _speed)
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------- banter

## Walking banter zones for a map id (the map file's name, e.g. "frayed_meadow").
static func banter_zones(map_id: String) -> Array:
	return data().get("banter", {}).get(map_id, [])


## Lines for a named event ("first_kill", "low_power", ...), or [] if it already played and is once-only.
static func event_lines(id: String) -> Array:
	var e = data().get("events", {}).get(id, {})
	if typeof(e) != TYPE_DICTIONARY or e.is_empty():
		return []
	if e.get("once", true) and is_seen("event:" + id):
		return []
	return lines(e.get("lines", []))


# ---------------------------------------------------------------- redacted words (issue #186)

## Text with black bars: "[[word]]" in a line is drawn as a bar of ink over the word (the Vacancy's speech, and
## the betrayal's top candidate from Chapter 4 on). plain() is the text as typed and measured: markers gone,
## the words kept, so the typewriter and wrapping are the same with or without bars. The dialogue log draws
## the bars too.
const BAR_OPEN := "[["
const BAR_CLOSE := "]]"


static func has_bars(text: String) -> bool:
	return text.contains(BAR_OPEN)


static func plain(text: String) -> String:
	return text.replace(BAR_OPEN, "").replace(BAR_CLOSE, "")


## How many lines draw_text wraps text into at this width and size.
static func line_count(font: Font, text: String, width: float, fsize: int) -> int:
	var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var n := 1
	var x := 0.0
	for w in plain(text).split(" ", false):
		var ww := font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if x > 0.0 and x + space + ww > width:
			n += 1
			x = ww
		else:
			x += (space if x > 0.0 else 0.0) + ww
	return n


## Splits text into [[segment, barred], ...] runs.
static func bar_runs(text: String) -> Array:
	var runs := []
	var i := 0
	while i < text.length():
		var a := text.find(BAR_OPEN, i)
		if a < 0:
			runs.append([text.substr(i), false])
			break
		var b := text.find(BAR_CLOSE, a)
		if b < 0:
			runs.append([text.substr(i), false])
			break
		if a > i:
			runs.append([text.substr(i, a - i), false])
		runs.append([text.substr(a + 2, b - a - 2), true])
		i = b + 2
	return runs


## Draws text like CanvasItem.draw_multiline_string (top-left of the first baseline at pos, wrapped at
## width), showing only the first `shown` characters of plain(text) (-1 = all), with barred words as ink
## bars. Lines without bars go straight to draw_multiline_string, so they look exactly as before.
## line_h > 0 spaces the lines that far apart (a ledger page's ruling) instead of the font's height.
static func draw_text(ci: CanvasItem, font: Font, pos: Vector2, text: String, width: float, fsize: int, col: Color,
		shown := -1, bar_col := Color("15101a"), line_h := -1.0) -> void:
	if not has_bars(text) and line_h <= 0.0:
		ci.draw_multiline_string(font, pos, text if shown < 0 else text.substr(0, shown), HORIZONTAL_ALIGNMENT_LEFT, width, fsize, -1, col)
		return
	# Words in order, each split into its plain and barred pieces.
	var words := []  # [[ [piece, barred], ... ], ...]
	var cur := []
	for run in bar_runs(text):
		var parts := str(run[0]).split(" ")
		for j in parts.size():
			if j > 0:
				words.append(cur)
				cur = []
			if parts[j] != "":
				cur.append([parts[j], run[1]])
	words.append(cur)
	if line_h <= 0.0:
		line_h = font.get_height(fsize)
	var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := 0.0
	var y := 0.0
	var left := shown if shown >= 0 else 1 << 30
	var first := true
	for w in words:
		var ww := 0.0
		for piece in w:
			ww += font.get_string_size(piece[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		if not first:
			left -= 1  # the space before this word
			if x + space + ww > width and x > 0.0:
				x = 0.0
				y += line_h
			elif x > 0.0:
				x += space
		first = false
		if left <= 0:
			return
		for piece in w:
			var s: String = piece[0]
			var n := mini(s.length(), left)
			var part := s.substr(0, n)
			var pw := font.get_string_size(part, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			if piece[1]:
				var asc := font.get_ascent(fsize)
				var r := Rect2(pos + Vector2(x - 0.5, y - asc * 0.82), Vector2(pw + 1.0, asc * 0.98))
				ci.draw_rect(r, bar_col)
				ci.draw_rect(Rect2(r.position + Vector2(1, r.size.y - 1.0), Vector2(maxf(r.size.x - 2.0, 0.0), 1.0)), Color(bar_col, 0.55))
			else:
				ci.draw_string(font, pos + Vector2(x, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
			x += pw
			left -= n
			if left <= 0:
				return
