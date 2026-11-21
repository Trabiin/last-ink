class_name EpilogueView
extends Control
## The epilogue cards at the ending (issue #116; the ending itself is #32): one card per person, their
## portrait on the left in their accent colour and what became of them on a torn ledger page.
## Enter / J / click / tap: next card (finishing the text first). Esc: straight to the last card.
##
##   var v := EpilogueView.new(); add_child(v); v.finished.connect(...); v.play(Epilogues.cards())

signal finished

const CHARS_PER_SEC := 90.0
const SceneViewScript := preload("res://scripts/scene_view.gd")

var cards: Array = []
var at := 0
var _shown := 0.0
var _opened_frame := -1
var _card_ms := 0
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font
	visible = false


func play(list: Array) -> void:
	cards = list
	at = 0
	_shown = 0.0
	_card_ms = Time.get_ticks_msec()
	_opened_frame = Engine.get_process_frames()
	_fit()
	visible = not cards.is_empty()
	if cards.is_empty():
		finished.emit()


## Covers the whole screen (sized by hand: the ending may put it under a CanvasLayer, which has no rect).
func _fit() -> void:
	position = Vector2.ZERO
	if size != get_viewport_rect().size:
		size = get_viewport_rect().size


func _typing() -> bool:
	return at < cards.size() and _shown < float(str(cards[at]["text"]).length())


func advance() -> void:
	if _typing():
		_shown = 99999.0
		return
	at += 1
	_shown = 0.0
	_card_ms = Time.get_ticks_msec()
	if at >= cards.size():
		visible = false
		finished.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_shown += delta * CHARS_PER_SEC
	_fit()
	queue_redraw()
	if Engine.get_process_frames() == _opened_frame:
		return
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
		advance()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		at = cards.size() - 1
		_shown = 99999.0


func _gui_input(event: InputEvent) -> void:
	if Engine.get_process_frames() == _opened_frame:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed):
		advance()


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.025, 0.05))
	if at >= cards.size():
		return
	var c: Dictionary = cards[at]
	var accent := Color(str(c.get("color", "c9c3b6")))
	var fade := clampf((Time.get_ticks_msec() - _card_ms) / 400.0, 0.0, 1.0)
	# Portrait on the left, lit in their colour (greyed out for the people the white took).
	var tex: Texture2D = SceneViewScript.portrait(str(c["id"]))
	var floor_y := vs.y - 18.0
	for i in 32:
		draw_circle(Vector2(150, floor_y - 170), 170.0 * (1.0 - i / 32.0), Color(accent, 0.012 * fade))
	if tex != null:
		var sz := Dialogue.portrait_size(tex, minf(vs.y - 40.0, 320.0))
		tex = Dialogue.fitted(tex, sz.y)
		var tint := Color(0.55, 0.55, 0.6, fade) if c.get("lost", false) else Color(1, 1, 1, fade)
		draw_set_transform(Vector2(150 + sz.x / 2, floor_y - sz.y), 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, Rect2(Vector2.ZERO, sz), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		Dialogue.draw_portrait(self, Rect2(40, 40, 200, vs.y - 80), str(c["id"]), "", 0.0, true)
	# The page: name, then what became of them.
	var box := Rect2(vs.x * 0.44, 46, vs.x * 0.56 - 18, vs.y - 92)
	UiSkin.page(self, box)
	var ink := UiSkin.PAGE_INK
	var nm := str(c["name"])
	var np := box.position + Vector2(26, 34)
	var nw := UiSkin.TITLE_FONT.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(18)).x
	UiSkin.brush(self, np + Vector2(-4, 4), nw + 10, accent.darkened(0.1))
	draw_string(UiSkin.TITLE_FONT, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(18), ink)
	var text := str(c["text"]).substr(0, int(_shown))
	draw_multiline_string(font, box.position + Vector2(26, 58), text, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, Access.fs(10), -1, ink)
	# Header and footer
	var head := tr("Afterwards")
	draw_string(UiSkin.TITLE_FONT, Vector2(vs.x * 0.44, 30), head, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(16), Color("e8d9a8"))
	var count := "%d / %d" % [at + 1, cards.size()]
	draw_string(font, Vector2(vs.x - font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x - 16, 30), count, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), Color(0.6, 0.58, 0.6))
	var hint := Prompts.help([["ui_accept", "next"], ["ui_cancel", tr("last card")]], tr("Tap: next"))
	draw_string(font, Vector2(vs.x - font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x - 14, vs.y - 6), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(0.5, 0.48, 0.52))
