extends Control
## Makes the Blank's creep visible on the Command Table (issue #33). Sits over the territory map
## (a child of command.gd, drawn after it) and never takes input.
##
## At dawn it fades the land the Blank just ate from its old colour to paper, floats each
## province's Fray change over it, and rings any province that was erased. All day it marks
## provinces Verity's plans are aimed at, and names the next province on course to fall.

const FADE := 1.8  # seconds the old colour takes to drain away
const FLOAT := 3.2  # seconds the Fray changes float
const CHALK := Color("e4dcf2")

var cmd: Control  # command.gd
var last_img: Image
var last_fray := {}  # province id -> Fray at the last bake
var last_owner := {}
var fade_tex: ImageTexture
var fade_t := 0.0
var marks: Array = []  # [province id, text, colour]
var marks_t := 0.0
var rings: Array = []  # province ids erased this dawn
var t := 0.0
# Redrawn only while something moves or after the map or the game state changed (issue #191).
var plans: Array = []  # [province, label] for each province Verity's plans are aimed at
var next := {}  # next_to_fall(), worked out when the state changes, not every frame
var _state := -1
var _view := -1
var _moving := false


func _ready() -> void:
	if cmd == null:
		cmd = get_parent()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_remember()
	# Connected after command.gd's own handler, so the map has already been re-baked.
	Empire.day_passed.connect(_on_day_passed)


func _remember() -> void:
	last_img = cmd.map_img.duplicate() if cmd.map_img != null else null
	for p in cmd.territory.provinces:
		last_fray[p["id"]] = int(p["fray"])
		last_owner[p["id"]] = p["owner"]


func _on_day_passed(_d: int) -> void:
	var img: Image = cmd.map_img
	if last_img != null and last_img.get_size() == img.get_size():
		# Land that turned white overnight keeps its old colour for a moment, then drains away.
		var diff := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		var any := false
		for y in img.get_height():
			for x in img.get_width():
				var was := last_img.get_pixel(x, y)
				var now := img.get_pixel(x, y)
				if now.get_luminance() > was.get_luminance() + 0.15:
					diff.set_pixel(x, y, was)
					any = true
		if any:
			fade_tex = ImageTexture.create_from_image(diff)
			fade_t = FADE
	marks = []
	rings = []
	for p in cmd.territory.provinces:
		var id: String = p["id"]
		if p["owner"] == "erased":
			if last_owner.get(id, "") != "erased":
				rings.append(id)
			continue
		var d := int(p["fray"]) - int(last_fray.get(id, p["fray"]))
		if d != 0:
			marks.append([id, "%+d" % d, Color("ff8a7a") if d > 0 else Color("9fd18b")])
	marks_t = FLOAT
	_remember()


func _process(delta: float) -> void:
	t += delta
	fade_t = maxf(fade_t - delta, 0.0)
	marks_t = maxf(marks_t - delta, 0.0)
	var state: int = cmd.get("state_serial") if cmd.get("state_serial") != null else -1
	var view: int = cmd.get("view_serial") if cmd.get("view_serial") != null else -1
	var changed := state != _state or state < 0
	if changed:
		_state = state
		_refresh()
	var moving := fade_t > 0.0 or marks_t > 0.0 or not plans.is_empty() or _next_pulses()
	if changed or moving or _moving or view != _view:
		_view = view
		queue_redraw()
	_moving = moving  # one more frame after the motion stops, to clear it


## What the plans and the next-to-fall line say: worked out again when the table's state changes.
func _refresh() -> void:
	plans = []
	for pid in BlankPlans.targets():
		var p: Dictionary = cmd.territory.find(pid)
		if p.is_empty():
			continue
		var total := 0
		for e in BlankPlans.on(p):
			total += int(e["per_day"])
		plans.append([p, tr("Verity %+d/day") % total if total != 0 else tr("Verity (held off)")])
	next = next_to_fall()


## The next-to-fall line pulses when it is your land and close.
func _next_pulses() -> bool:
	return not next.is_empty() and next["owner"] == "you" and int(next["days"]) <= 5


func _draw() -> void:
	var map_rect: Rect2 = cmd._map_rect()
	if fade_t > 0.0 and fade_tex != null:
		draw_texture_rect(fade_tex, cmd._world_rect(), false, Color(1, 1, 1, fade_t / FADE))
	# Verity's plans: a chalk ring round the target, and what it is costing.
	for plan in plans:
		var pos: Vector2 = cmd._province_screen_pos(plan[0]) + Vector2(0, -9)
		var n := 14
		for i in n:
			if i % 2 == 0:
				var a0 := TAU * i / n + t * 0.4
				draw_arc(pos, 9.0, a0, a0 + TAU / n, 4, Color(0.08, 0.06, 0.1, 0.7), 3.0)
				draw_arc(pos, 9.0, a0, a0 + TAU / n, 4, CHALK, 1.0)
		_text_c(pos + Vector2(0, -12), plan[1], 8, CHALK)
	# Dawn: rings where land was erased, and every province's Fray change floating up.
	if marks_t > 0.0:
		var k := 1.0 - marks_t / FLOAT
		for pid in rings:
			var p: Dictionary = cmd.territory.find(pid)
			var pos: Vector2 = cmd._province_screen_pos(p)
			for j in 2:
				var r := 6.0 + (k + j * 0.25) * 60.0
				draw_arc(pos, r, 0, TAU, 48, Color(0.98, 0.97, 0.94, clampf(1.0 - k - j * 0.2, 0.0, 1.0)), 3.0)
		var a := clampf(marks_t / 0.6, 0.0, 1.0)
		for m in marks:
			var p: Dictionary = cmd.territory.find(m[0])
			var pos: Vector2 = cmd._province_screen_pos(p) + Vector2(34, -2 - k * 14.0)
			_text_c(pos, tr("%s Fray") % m[1], 9, Color(m[2], a))
	# The Blank's watch: who goes next if nothing changes.
	if not next.is_empty():
		var yours: bool = next["owner"] == "you"
		var s := tr("Next to fall: %s in ~%d day%s") % [next["name"], next["days"], "" if next["days"] == 1 else "s"]
		var col := Color(1, 0.6, 0.52) if yours else Color(0.85, 0.83, 0.78)
		if yours and next["days"] <= 5:
			col.a = 0.7 + 0.3 * sin(t * 4.0)
		var w: float = cmd.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
		_text(Vector2(map_rect.end.x - w - 6, map_rect.end.y - 8), s, 8, col)


## The province the Blank will finish first at today's rates: {"name", "owner", "days"} or {}.
static func next_to_fall() -> Dictionary:
	var best := {}
	for p in Empire.territory().provinces:
		if p["owner"] == "erased" or not Empire.province_open(p):
			continue
		var rate := Empire.fray_rate(p)
		if rate <= 0:
			continue
		var days := ceili((100.0 - float(p["fray"])) / rate)
		if best.is_empty() or days < int(best["days"]):
			best = {"name": p["name"], "owner": p["owner"], "days": days}
	return best


func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string_outline(cmd.font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), 3, Color(0.05, 0.04, 0.06, col.a))
	draw_string(cmd.font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)


func _text_c(center: Vector2, s: String, fsize: int, col: Color) -> void:
	var w: float = cmd.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	_text(center - Vector2(w / 2.0, 0), s, fsize, col)
