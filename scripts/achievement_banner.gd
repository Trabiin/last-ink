class_name AchievementBanner
extends Control
## The small "Achievement unlocked" card in the top-right corner (issue #150), for builds without Steam
## (Steam shows its own). Slides in, stays a few seconds, fades out and frees its layer. Never takes input.

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const PANEL := Color(0.06, 0.05, 0.08, 0.9)
const EDGE := Color(1.0, 0.82, 0.4, 0.55)
const STAY := 4.0
const SLIDE := 0.25
const TOP := 30.0  # under the header line of full-screen menus and the mission HUD's top row

var heading := ""
var title := ""
var _t := 0.0
var _font: Font


func setup(p_heading: String, p_title: String) -> void:
	heading = p_heading
	title = p_title


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func _process(delta: float) -> void:
	size = get_viewport_rect().size  # its parent is a CanvasLayer, so anchors alone don't size it
	_t += delta
	if _t > STAY + SLIDE * 2:
		get_parent().queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var hs := Access.fs(8)
	var ts := Access.fs(11)
	var w := maxf(_font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x,
		_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(11)).x) + 20.0
	w = minf(w, size.x - 16.0)
	var h := float(hs + ts) + 14.0
	var slide_in := clampf(_t / SLIDE, 0.0, 1.0)
	var fade := 1.0 - clampf((_t - STAY - SLIDE) / SLIDE, 0.0, 1.0)
	var x := size.x - (w + 8.0) * ease(slide_in, 0.4)
	var r := Rect2(Vector2(roundf(x), TOP), Vector2(w, h))
	modulate.a = fade
	draw_rect(r, PANEL)
	draw_rect(r, EDGE, false, 1.0)
	UiSkin.tab(self, r, "brass")
	var tx := r.position.x + 10.0
	draw_string(_font, Vector2(tx, r.position.y + 4.0 + hs), heading, HORIZONTAL_ALIGNMENT_LEFT, w - 14.0, Access.fs(8), GOLD)
	draw_string(_font, Vector2(tx, r.position.y + 8.0 + hs + ts), title, HORIZONTAL_ALIGNMENT_LEFT, w - 14.0, Access.fs(11), TEXT)
