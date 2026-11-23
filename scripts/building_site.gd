extends StaticBody2D
## One building plot in Hollowmark. Shows a staked-out empty plot, scaffolding while the
## builders work, and the finished building (with a name board and its level) once built.
## Origin = the bottom-centre of the 5x5-tile plot.
##
## Built looks are art pass sprites, res://assets/buildings/<look>_<level>.png (one per level; the
## art paths are checked by tests/test_data.gd, so every building and level has one). Each level's collision
## is its traced footprint in data/footprints.json ("<look>_<level>", scripts/footprints.gd): solid along
## the walls it shows and as deep as its roof, so it can't be walked through or into from any side.

const PLOT := Vector2(80, 80)


## The art pass sprite for this look at this level.
static func art_path(look_id: String, lv: int) -> String:
	return "res://assets/buildings/%s_%d.png" % [look_id, clampi(lv, 1, 3)]
const ROMAN := ["", "I", "II", "III", "IV"]

var id := ""
var look := ""
var _built_level := -1
var _box: CollisionShape2D
var _box_key := ""  # which footprint _box holds: "<look>_<level>", or "" for none
var _occluder: LightOccluder2D
var _sprites: Array = []
var highlight := false
## Chimney tops on the art pass sprites (offset from the plot's bottom-centre, per level), for the smoke.
## The lit forges (levels 2 and 3) smoke from the chimney cap; the sprites carry no painted smoke.
const SMOKE := {"forge_2": Vector2(27, -92), "forge_3": Vector2(28, -92)}
var _over: Node2D  # code-drawn labels above everything: name plate, build progress, smoke
var _scaffold: Node2D


func _ready() -> void:
	collision_layer = 1
	look = Empire.building(id).get("look", "")
	_scaffold = Node2D.new()  # timber over the rising building, Y-sorted with it (someone in front stays in front)
	add_child(_scaffold)
	_scaffold.draw.connect(_draw_scaffold_node)
	_over = Node2D.new()
	_over.z_index = 1
	add_child(_over)
	_over.draw.connect(_draw_over)
	refresh()


func plot_rect() -> Rect2:
	return Rect2(global_position - Vector2(PLOT.x / 2.0, PLOT.y - 4.0), Vector2(PLOT.x, PLOT.y - 4.0))


## Where staff stand: in front of the door, side by side.
func post_pos(n: int) -> Vector2:
	return global_position + Vector2([0, 18, -18][n % 3] - 14, 14)


## Rebuilds sprites and collision when the level changes. Cheap to call every frame.
func refresh() -> void:
	var lv := Empire.level_of(id)
	_refresh_footprint(lv)
	if lv == _built_level:
		return
	_built_level = lv
	for s in _sprites:
		s.queue_free()
	_sprites.clear()
	if lv <= 0 or look == "":
		return
	var path := art_path(look, lv)
	if ResourceLoader.exists(path):
		var spr := _sprite(load(path), Vector2.ZERO, Color.WHITE)
		spr.material = Art.art_world_material()
		_sprites.append(spr)
		var sh := Node2D.new()  # cast shadow, under the building
		var sw := float(spr.texture.get_width())
		var st := float(spr.texture.get_height())
		sh.draw.connect(func(): Art.draw_cast_shadow(sh, Vector2(0, 2), sw, st))
		add_child(sh)
		move_child(sh, 0)
		_sprites.append(sh)
		_sprites.append(Art.add_cast_shadow(self, spr.texture, 3.0))
	else:
		push_error("building art missing: %s" % path)


## Which footprint stands on the plot: the built level's, or level 1's while a new building is going up (the
## scaffold and the rising walls are in the way too). Nothing on an empty plot.
func footprint_key(lv: int) -> String:
	if look == "":
		return ""
	if lv > 0:
		return "%s_%d" % [look, clampi(lv, 1, 3)]
	if Empire.construction.get("id", "") == id:
		return "%s_1" % look
	return ""


func _refresh_footprint(lv: int) -> void:
	var key := footprint_key(lv)
	if key == _box_key:
		return
	_box_key = key
	if _box:
		_box.queue_free()
		_box = null
	if _occluder:
		_occluder.queue_free()
		_occluder = null
	if key == "":
		return
	var pts := Footprints.poly("buildings", key)
	if pts.is_empty():
		push_error("building footprint missing: %s (run tools/footprints.py)" % key)
		pts = Footprints.box(Vector2(72, 40))
	_box = Footprints.attach(self, pts)
	if lv > 0:
		_occluder = Art.add_footprint_occluder(self, pts)
	Footprints.eject(self, pts)  # anyone standing where the walls now are steps out


func _sprite(tex: Texture2D, off: Vector2, tint: Color) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.offset = off + Vector2(0, -tex.get_height() / 2.0 + 3.0)
	spr.material = Art.world_material()
	spr.modulate = tint
	add_child(spr)
	move_child(spr, 0)  # sprites under the code-drawn plate and scaffolding
	return spr


## Construction-site sprites: the rising building plus planks, crates and barrels from the town's own props.
var _site: Array = []
var _rise: Sprite2D
var _site_key := ""


func _update_site_sprites() -> void:
	var job: Dictionary = Empire.construction if Empire.construction.get("id", "") == id else {}
	var lv := Empire.level_of(id)
	var key := "" if job.is_empty() else "%d" % lv
	if key != _site_key:
		_site_key = key
		for n in _site:
			n.queue_free()
		_site.clear()
		_rise = null
		if key != "":
			var full := lv == 0
			var art := "res://assets/buildings/%s_1.png" % look
			var half := 34.0
			if full and ResourceLoader.exists(art):
				_rise = Sprite2D.new()
				_rise.texture = load(art)
				_rise.centered = false
				_rise.region_enabled = true
				_rise.material = Art.art_world_material()
				_rise.modulate = Color(0.8, 0.74, 0.68)
				add_child(_rise)
				_site.append(_rise)
				half = _rise.texture.get_width() / 2.0
			var x0 := -half - 10.0 if full else 18.0
			var x1 := half + 8.0 if full else 46.0
			for pr in [["crates_v1", Vector2(x0, 6)], ["crates", Vector2(x1, 6)], ["barrels", Vector2(x1 + 16, 10)]]:
				if not full and pr[0] == "barrels":
					continue
				var path := "res://assets/props/%s.png" % pr[0]
				if ResourceLoader.exists(path):
					var sp := Sprite2D.new()
					sp.texture = load(path)
					sp.offset = Vector2(0, -sp.texture.get_height() / 2.0)
					sp.position = pr[1]
					sp.material = Art.art_world_material()
					add_child(sp)
					_site.append(sp)
			move_child(_scaffold, -1)  # timber over the rising walls, labels over everything
			move_child(_over, -1)
	if _rise:
		var sz := _rise.texture.get_size()
		var h := floorf(sz.y * clampf(Empire.job_progress(Empire.construction), 0.08, 1.0))
		_rise.region_rect = Rect2(0, sz.y - h, sz.x, h)
		_rise.position = Vector2(-sz.x / 2.0, 3.0 - h).floor()


func _process(_delta: float) -> void:
	refresh()
	_update_site_sprites()
	queue_redraw()
	_scaffold.queue_redraw()
	_over.queue_redraw()


func _draw() -> void:
	if Empire.level_of(id) == 0:
		_draw_plot()


func _draw_over() -> void:
	var b := Empire.building(id)
	var lv := Empire.level_of(id)
	var job: Dictionary = Empire.construction if Empire.construction.get("id", "") == id else {}
	var font := ThemeDB.fallback_font
	if lv > 0 and SMOKE.has("%s_%d" % [look, lv]):
		_draw_smoke(SMOKE["%s_%d" % [look, lv]])
	# Name board: only while the player stands at the plot or it is being built (no always-on labels on the map,
	# docs/ART_STYLE.md); the interaction prompt names it too.
	var label: String = String(b.get("name", id)).to_upper()
	if lv > 0:
		label += " " + ROMAN[mini(lv, ROMAN.size() - 1)]
	elif not job.is_empty():
		label = tr("BUILDING: ") + label
	var y := -PLOT.y * 0.5 if lv > 0 else -10.0
	if highlight or not job.is_empty():
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6)).x + 8.0
		var r := Rect2(-w / 2.0, y - 7.0, w, 9.0)
		_over.draw_rect(r, Color("3a2a1c"))
		_over.draw_rect(r, Color("e8c65a") if highlight else Color("7d5836"), false, 1.0)
		_over.draw_string(font, Vector2(r.position.x + 4.0, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6), Color("f3e3c3"))
	if not job.is_empty():
		var by := y - 12.0
		_over.draw_rect(Rect2(-24, by, 48, 4), Color(0.1, 0.08, 0.12, 0.85))
		_over.draw_rect(Rect2(-24, by, 48 * Empire.job_progress(job), 4), Color("ffd166"))
		var t := Empire.job_left_text(job)
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6)).x
		_over.draw_string_outline(font, Vector2(-tw / 2.0, by - 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6), 2, Color(0, 0, 0, 0.8))
		_over.draw_string(font, Vector2(-tw / 2.0, by - 2), t, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6), Color("ffd166"))


## Stakes and rope around an empty plot: pegs with a lit side, rope sagging between them with its shadow on the
## ground, a few marker rags, trodden earth at the corners and a sign board by the front.
func _draw_plot() -> void:
	var r := Rect2(-PLOT.x / 2.0 + 6, -PLOT.y + 18, PLOT.x - 12, PLOT.y - 22)
	var rope := Color("8f8270")
	var rope_hi := Color("b5a68a")
	var shade := Color(0.07, 0.08, 0.12, 0.35)
	var pts: Array[Vector2] = []
	for i in 3:  # stakes every third of each side, corners included
		pts.append(r.position + Vector2(r.size.x * i / 3.0, 0))
	for i in 3:
		pts.append(Vector2(r.end.x, r.position.y) + Vector2(0, r.size.y * i / 3.0))
	for i in 3:
		pts.append(r.end - Vector2(r.size.x * i / 3.0, 0))
	for i in 3:
		pts.append(Vector2(r.position.x, r.end.y) - Vector2(0, r.size.y * i / 3.0))
	for p in pts:  # scuffed earth round each stake
		draw_rect(Rect2((p + Vector2(-3, -1)).floor(), Vector2(6, 3)), Color(0.23, 0.16, 0.11, 0.55))
	for i in pts.size():
		var a: Vector2 = pts[i] + Vector2(0, -6)
		var c: Vector2 = pts[(i + 1) % pts.size()] + Vector2(0, -6)
		var sag := 2.0 if absf(a.y - c.y) < 1.0 else 0.5
		var prev := a
		for k in range(1, 9):
			var t := k / 8.0
			var q := a.lerp(c, t) + Vector2(0, sag * 4.0 * t * (1.0 - t))
			draw_line((prev + Vector2(1, 7)).floor(), (q + Vector2(1, 7)).floor(), shade, 1.0)  # rope shadow
			draw_line(prev.floor(), q.floor(), rope, 1.0)
			prev = q
		if i % 3 == 1:  # a marker rag halfway along
			var m := a.lerp(c, 0.5) + Vector2(0, sag)
			draw_rect(Rect2(m.floor(), Vector2(2, 3)), Color("85402f"))
	for p in pts:
		var base: Vector2 = p.floor()
		draw_rect(Rect2(base + Vector2(-1, -8), Vector2(3, 9)), Color("12141f"))  # outline
		draw_rect(Rect2(base + Vector2(0, -7), Vector2(1, 7)), Color("7d5836"))  # lit side
		draw_rect(Rect2(base + Vector2(1, -7), Vector2(1, 7)), Color("5a3e28"))
		draw_rect(Rect2(base + Vector2(0, -7), Vector2(2, 1)), rope_hi)  # lashing
	var sign_tex: Texture2D = load("res://assets/props/sign.png") if ResourceLoader.exists("res://assets/props/sign.png") else null
	if sign_tex:
		draw_texture(sign_tex, Vector2(r.position.x + 6, r.end.y - sign_tex.get_height() + 2).floor())


func _draw_scaffold_node() -> void:
	if Empire.construction.get("id", "") == id:
		_draw_scaffold(Empire.level_of(id) == 0)


## Wooden scaffolding with planks; covers the whole plot for a new building, one side for an upgrade.
func _draw_scaffold(full: bool) -> void:
	var x0 := -30.0 if full else 18.0
	var x1 := 30.0 if full else 40.0
	var top := -56.0 if full else -40.0
	if full and _rise:
		# The building rises with progress (a sprite under the scaffold, see _update_site_sprites).
		var tsz: Vector2 = _rise.texture.get_size()
		var h := floorf(tsz.y * clampf(Empire.job_progress(Empire.construction), 0.08, 1.0))
		top = minf(-20.0, 3.0 - h - 6.0)
		x0 = -tsz.x / 2.0 + 4.0
		x1 = tsz.x / 2.0 - 4.0
	# Timber scaffolding: poles with ink outlines and a lit side, cross planks, one brace.
	var outline := Color("12141f")
	var lit := Color("8a6a44")
	var shade := Color("5a3e28")
	var n := 3 if full else 1
	for i in n + 1:
		var x := floorf(lerpf(x0, x1, float(i) / n))
		_scaffold.draw_rect(Rect2(x - 2, top, 4, -top), outline)
		_scaffold.draw_rect(Rect2(x - 1, top + 1, 1, -top - 2), lit)
		_scaffold.draw_rect(Rect2(x, top + 1, 1, -top - 2), shade)
	var y := top + 6.0
	while y < -4.0:
		_scaffold.draw_rect(Rect2(x0 - 3, y - 1, x1 - x0 + 6, 5), outline)
		_scaffold.draw_rect(Rect2(x0 - 2, y, x1 - x0 + 4, 2), lit)
		_scaffold.draw_rect(Rect2(x0 - 2, y + 2, x1 - x0 + 4, 1), shade)
		y += 14.0
	_scaffold.draw_line(Vector2(x0, -3), Vector2(x1, top + 5), outline, 2.0)
	_scaffold.draw_line(Vector2(x0, -3), Vector2(x1, top + 5), shade, 1.0)


func _draw_smoke(top: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in 4:
		var k := fmod(t * 0.35 + i * 0.25, 1.0)
		var p := top + Vector2(sin(k * 6.0 + i) * 4.0, -k * 26.0)
		_over.draw_circle(p, 3.0 + k * 4.0, Color(0.12, 0.12, 0.2, 0.55 * (1.0 - k)))
