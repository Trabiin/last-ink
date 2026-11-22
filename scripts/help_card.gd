class_name HelpCard
extends Control
## A short talk over whatever is on screen (issue #115): one of the cast stands at the left and
## explains the screen behind them a line at a time on a torn ledger page. The rest of the screen
## stays visible, dimmed, so what they talk about is right there.
##
## Confirm / Attack / click / tap: next line (finishes typing first). Back / pause / "Skip": skip the rest.
## While it is up the game is paused and the screen under it is held still, so no key meant for the
## card also acts on that screen; both come back a frame after it closes.
##
## One per scene: HelpCard.ensure(host) makes it (on its own layer, above every screen and menu) and
## Help.card points at it. Help.play(id) and Help.play_locked(screen) fill it.

signal closed

const GOLD := Color("ffd166")
const SOFT := Color(0.66, 0.64, 0.66)
const INK := UiSkin.PAGE_INK
const LAYER := 7

var heading := ""
var font: Font
var opened_frame := -1
var closed_frame := -1
var _lines: Array = []  # [speaker, text, expression]
var _at := 0
var _shown := 0.0
var _under: Node = null
var _under_mode := Node.PROCESS_MODE_INHERIT
var _was_paused := false
var _release_in := 0  # frames left before the game and the screen underneath get their input back
var _skip_rect := Rect2()


## The scene's card, made on first use under `host` (the hub, the Command Table or a mission).
static func ensure(host: Node) -> HelpCard:
	if is_instance_valid(Help.card) and Help.card.is_inside_tree() and host.is_ancestor_of(Help.card):
		return Help.card
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var c := HelpCard.new()
	c.visible = false
	layer.add_child(c)
	return c


func _enter_tree() -> void:
	Help.card = self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font


## Shows the lines. under: the screen it plays over (held still meanwhile). False if there is
## nothing to say or a talk is already up.
func show_talk(p_heading: String, ls: Array, under: Node = null) -> bool:
	if ls.is_empty() or visible:
		return false
	heading = p_heading
	_lines = ls
	_at = 0
	_shown = 0.0
	_release_in = 0
	_hold(under)
	visible = true
	opened_frame = Engine.get_process_frames()
	if size != get_viewport_rect().size:
		size = get_viewport_rect().size
	if has_node("/root/Audio"):
		get_node("/root/Audio").call("sfx", "alert")
	queue_redraw()
	return true


func _hold(under: Node) -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	_under = under if is_instance_valid(under) else null
	if _under:
		_under_mode = _under.process_mode
		_under.process_mode = Node.PROCESS_MODE_DISABLED


func _release() -> void:
	if _under and is_instance_valid(_under):
		_under.process_mode = _under_mode
	_under = null
	get_tree().paused = _was_paused


func _current() -> Array:
	return _lines[_at] if _at < _lines.size() else ["", "", ""]


func _typing() -> bool:
	return _shown < float(String(_current()[1]).length())


func _advance() -> void:
	if _typing():
		_shown = 99999.0
		return
	_at += 1
	_shown = 0.0
	if _at >= _lines.size():
		_close()


func _close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	_release_in = 2  # the key that closed the card is still "just pressed" this frame
	closed.emit()


func _process(delta: float) -> void:
	if _release_in > 0:
		_release_in -= 1
		if _release_in == 0 and not visible:
			_release()
	if not visible:
		return
	if size != get_viewport_rect().size:
		size = get_viewport_rect().size
	queue_redraw()
	DialogueLog.track(self, _current(), "help")
	if DialogueLog.is_open():
		return  # the dialogue log is up over the card (issue #34)
	var cps := Dialogue.chars_per_sec()
	_shown = 99999.0 if cps <= 0.0 else _shown + delta * cps
	if Engine.get_process_frames() == opened_frame:
		return
	if DialogueLog.asked():
		DialogueLog.popup(get_parent())
		return
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
		_advance()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		_close()


func _gui_input(event: InputEvent) -> void:
	if not Prompts.tapped(event) or Engine.get_process_frames() == opened_frame:
		return
	accept_event()
	if _skip_rect.has_point(event.position):
		_close()
	else:
		_advance()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.025, 0.05, 0.42))
	var cur := _current()
	var who: String = cur[0]
	var box := Rect2(118, vs.y - 100, vs.x - 130, 88)
	# The speaker stands at the left, feet below the screen edge, facing the page.
	var ph := 190.0
	var pr := Rect2(4, vs.y - ph + 18, ph * 2.0 / 3.0, ph)
	if who != "":
		var glow := Dialogue.accent(who)
		draw_circle(pr.get_center() + Vector2(0, -6), 54.0, Color(glow.darkened(0.6), 0.35))
		Dialogue.draw_portrait(self, pr, who, cur[2], 0.0, true)
	# Heading and where we are, over the page.
	var count := "%d / %d" % [mini(_at + 1, _lines.size()), _lines.size()]
	draw_string_outline(UiSkin.TITLE_FONT, Vector2(box.position.x + 4, box.position.y - 6), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(16), 4, Color(0, 0, 0, 0.8))
	draw_string(UiSkin.TITLE_FONT, Vector2(box.position.x + 4, box.position.y - 6), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(16), GOLD)
	var cw := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
	draw_string_outline(font, Vector2(box.end.x - cw - 4, box.position.y - 6), count, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), 3, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(box.end.x - cw - 4, box.position.y - 6), count, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), SOFT)
	UiSkin.page(self, box)
	var tx := box.position.x + 30
	var ty := box.position.y + 20
	if who != "":
		var nm := Dialogue.display_name(who)
		var nw := UiSkin.TITLE_FONT.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(14)).x
		UiSkin.brush(self, Vector2(tx - 3, box.position.y + 21), nw + 8, Dialogue.accent(who).darkened(0.15))
		draw_string(UiSkin.TITLE_FONT, Vector2(tx, box.position.y + 18), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(14), INK)
		ty += 12
	var text: String = cur[1]
	draw_multiline_string(font, Vector2(tx, ty), text.substr(0, int(_shown)), HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, Access.fs(11), -1, INK)
	if not _typing():
		var tip := box.end - Vector2(22, 14 - sin(Time.get_ticks_msec() / 220.0) * 1.5)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-3, -7), tip + Vector2(0, -10), tip + Vector2(3, -7)]), INK)
		draw_line(tip + Vector2(0, -2), tip + Vector2(0, -6), Color("d6cdba"), 1.0)
	# Skip, and what the buttons do on this device.
	var skip := tr("Skip")
	var sw := font.get_string_size(skip, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
	_skip_rect = Rect2(box.position.x, box.end.y + 1, sw + 12, 11)
	draw_string(font, _skip_rect.position + Vector2(4, 8), skip, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), Color(0.75, 0.72, 0.7))
	var hint := Prompts.help([["ui_accept", "next"], ["ui_cancel", "skip"]], tr("Tap: next"))
	hint += tr("   Replay any time: Help in the menu")
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
	draw_rect(Rect2(vs.x - hw - 18, vs.y - 10, hw + 18, 10), Color(0.05, 0.04, 0.07, 0.9))  # over the screen's own hint line
	draw_string(font, Vector2(vs.x - font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x - 12, vs.y - 2), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(0.6, 0.58, 0.62))
