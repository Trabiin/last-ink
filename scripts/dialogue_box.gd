extends Control
## The dialogue box (issue #11): visual-novel style. The world dims, the speakers stand on the left
## and right (whoever is talking is lit, the other waits in shadow), and the text types out in a
## box along the bottom with the speaker's name on a tag.
##
## Enter / J / click / tap: next line (finishes the current line first if it is still typing).
## Tab / Q / gamepad Y: text speed (Slow, Normal, Fast, Instant; remembered on this device).
## Esc: skip the rest of the conversation.
## Backspace / gamepad Back / mouse wheel up: the dialogue log (issue #34). Auto-advance is an
## accessibility option (Access.auto_advance).
##
## play("talk_id") plays a conversation from data/dialogue.json; play_lines([...]) plays any lines.
## A talk with "choice" ends on a choice for Ash (issue #186): [{"text", "reply": [lines], "betrayal": effect}].
## Up/Down (or a tap) picks; the reply plays on; Skip jumps to the choice but never past it. The pick is
## remembered (Dialogue.choice_made) and its "betrayal" effect goes to Betrayal.choose.
## Portraits come from Dialogue.portrait (assets/portraits/); a letter read aloud stands as a sheet of paper.

signal finished(id: String)

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.66, 0.64, 0.66)
const INK := UiSkin.PAGE_INK
const INK_SOFT := UiSkin.PAGE_INK_SOFT

var id := ""
var title := ""
var closed_frame := -1
var opened_frame := -1
var _lines: Array = []  # [speaker, text, expression]
var _at := 0
var _shown := 0.0
var _slots := ["", ""]  # who stands on the left and on the right
var _exprs := ["", ""]
var _speed_rect := Rect2()
var _skip_rect := Rect2()
var _log_rect := Rect2()
var _auto_t := 0.0  # seconds the finished line has waited (auto-advance)
var _choices: Array = []  # the talk's choice for Ash, while it has not been made
var _choosing := false
var _choice := 0
var _choice_rects: Array = []
var font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # full screen from the first frame
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


## Play a conversation from data/dialogue.json. Marks it seen. Returns false if it does not exist.
func play(talk_id: String) -> bool:
	var ls := Dialogue.talk(talk_id)
	if ls.is_empty():
		return false
	Dialogue.mark_seen("talk:" + talk_id)
	play_lines(ls, Dialogue.talk_title(talk_id), talk_id)
	_choices = Dialogue.talk_choice(talk_id)
	return true


## Play any lines ([speaker, text(, expression)] each).
func play_lines(ls: Array, heading := "", talk_id := "") -> void:
	_lines = Dialogue.lines(ls)
	if _lines.is_empty():
		return
	id = talk_id
	title = heading
	_choices = []
	_choosing = false
	_choice = 0
	_at = 0
	_shown = 0.0
	_slots = ["", ""]
	_exprs = ["", ""]
	_place_speaker()
	position = Vector2.ZERO
	# Only when it changed: setting the size of a full-rect box in the frame it was created (a
	# mission's opening talk) trips Godot's "size overridden after _ready()" warning.
	if size != get_viewport_rect().size:
		size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()


func _current() -> Array:
	return _lines[_at] if _at < _lines.size() else ["", "", ""]


## Put the current speaker on stage: keep their side if they are already there, else take the
## first empty side, else replace whoever is not the previous speaker.
func _place_speaker() -> void:
	var who: String = _current()[0]
	if who == "":
		return
	var side := _slots.find(who)
	if side < 0:
		side = _slots.find("")
		if side < 0:
			var prev: String = _lines[_at - 1][0] if _at > 0 else ""
			side = 1 if _slots[0] == prev else 0
		_slots[side] = who
	_exprs[side] = _current()[2]


func _typing() -> bool:
	return _shown < float(Dialogue.plain(String(_current()[1])).length())


func _advance() -> void:
	if _choosing:
		_pick(_choice)
		return
	if _typing():
		_shown = 99999.0
		return
	if _at + 1 >= _lines.size() and not _choices.is_empty():
		_choosing = true  # the last line stays up behind the choice
		_choice = 0
		return
	_at += 1
	_shown = 0.0
	_auto_t = 0.0
	if _at >= _lines.size():
		_close()
	else:
		_place_speaker()


## Ash makes the choice: its effect lands, then its reply plays as the rest of the talk.
func _pick(i: int) -> void:
	if i < 0 or i >= _choices.size():
		return
	var opt: Dictionary = _choices[i]
	_choices = []
	_choosing = false
	Dialogue.make_choice(id, i, opt)
	DialogueLog.add("", "[%s]" % str(opt.get("text", "")), "talk")
	var reply := Dialogue.lines(opt.get("reply", []))
	if reply.is_empty():
		_close()
		return
	_lines = _lines.slice(0, _at + 1) + reply
	_at += 1
	_shown = 0.0
	_auto_t = 0.0
	_place_speaker()


## Skip: the rest of the talk, or up to the choice when there is one still to make.
func _skip() -> void:
	if _choosing:
		return
	if not _choices.is_empty():
		_at = _lines.size() - 1
		_shown = 99999.0
		_place_speaker()
		_choosing = true
		_choice = 0
		return
	_close()


func _close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	finished.emit(id)


func _process(delta: float) -> void:
	if not visible:
		return
	size = get_viewport_rect().size
	DialogueLog.track(self, _current(), "talk")
	queue_redraw()
	if DialogueLog.is_open():
		return  # the log is up over us: wait, don't type on
	var cps := Dialogue.chars_per_sec()
	_shown = 99999.0 if cps <= 0.0 else _shown + delta * cps
	if Engine.get_process_frames() == opened_frame:
		return
	if _choosing:
		if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
			_choice = posmod(_choice - 1, _choices.size())
		elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
			_choice = posmod(_choice + 1, _choices.size())
		elif Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
			_pick(_choice)
		return
	if not _typing() and Access.auto_delay(_current()[1]) > 0.0:
		_auto_t += delta
		if _auto_t >= Access.auto_delay(_current()[1]):
			_advance()
			return
	if DialogueLog.asked():
		DialogueLog.popup(get_parent())
	elif Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
		_advance()
	elif Input.is_action_just_pressed("swap"):
		Dialogue.cycle_speed()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		_skip()


func _gui_input(event: InputEvent) -> void:
	if DialogueLog.is_open():
		return
	if DialogueLog.asked(event) and event is InputEventMouseButton:  # wheel up
		accept_event()
		DialogueLog.popup(get_parent())
		return
	var pos := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	if pos == Vector2.INF or Engine.get_process_frames() == opened_frame:
		return
	accept_event()
	if _choosing:
		for i in _choice_rects.size():
			if (_choice_rects[i] as Rect2).has_point(pos):
				if _choice == i:
					_pick(i)
				else:
					_choice = i  # first tap picks it out, second tap chooses (like bond scenes)
				return
		return
	if _speed_rect.has_point(pos):
		Dialogue.cycle_speed()
	elif _skip_rect.has_point(pos):
		_skip()
	elif _log_rect.has_point(pos):
		DialogueLog.popup(get_parent())
	else:
		_advance()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.025, 0.05, 0.6))
	var cur := _current()
	var speaker: String = cur[0]
	var box_h := Access.px(82.0)
	var box := Rect2(12, vs.y - box_h - Access.px(9.0) - 3.0, vs.x - 24, box_h)  # room for the tags underneath
	# The cast, standing behind the text box.
	var ph := vs.y - 24.0
	var pw := ph * 2.0 / 3.0
	var rects := [Rect2(20, vs.y - ph, pw, ph), Rect2(vs.x - 20 - pw, vs.y - ph, pw, ph)]
	for side in 2:
		var who: String = _slots[side]
		if who == "":
			continue
		var talking := who == speaker
		var r: Rect2 = rects[side]
		if not talking:
			r = r.grow_individual(-8, -12, -8, 0)
		if Dialogue.portrait(who, _exprs[side]) == null and not Dialogue.is_letter(who):  # safety-net busts get a soft card
			var card := Rect2(r.position + Vector2(0, r.size.y * 0.12), Vector2(r.size.x, r.size.y * 0.88))
			draw_rect(card, Color(Dialogue.accent(who).darkened(0.75), 0.85 if talking else 0.5))
		Dialogue.draw_portrait(self, r, who, _exprs[side], 0.0 if talking else 0.55, side == 0)

	if title != "":
		draw_string(UiSkin.TITLE_FONT, Vector2(14, 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(16), SOFT)
	UiSkin.page(self, box)
	var text: String = cur[1]
	var ty := box.position.y + Access.px(22.0)
	var tx := box.position.x + 30  # right of the ledger's red margin line
	if speaker != "":
		# The speaker's name, written in the heading face with a brushed underline in their colour.
		var nm := Dialogue.display_name(speaker)
		var acc := Dialogue.accent(speaker)
		var nw := UiSkin.TITLE_FONT.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(14)).x
		var np := Vector2(tx, box.position.y + Access.px(18.0))
		if _slots[1] == speaker and _slots[0] != speaker:  # name on the speaker's side
			np.x = box.end.x - 20 - nw
		UiSkin.brush(self, np + Vector2(-3, 3), nw + 8, acc.darkened(0.15))
		draw_string(UiSkin.TITLE_FONT, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(14), INK)
		ty += Access.px(12.0)
	Dialogue.draw_text(self, font, Vector2(tx, ty), text, box.size.x - 52, Access.fs(11), INK if speaker != "" else INK_SOFT,
		mini(int(_shown), 1 << 30))  # black bars for redacted words (issue #186)
	if _choosing:
		_draw_choices(box)
	elif not _typing():
		# A quill nib bobbing in the corner: there's more.
		var tip := box.end - Vector2(22, 14 - sin(Time.get_ticks_msec() / 220.0) * 1.5)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-3, -7), tip + Vector2(0, -10), tip + Vector2(3, -7)]), INK)
		draw_line(tip + Vector2(0, -2), tip + Vector2(0, -6), Color("d6cdba"), 1.0)
	# Speed, skip and the log, small, under the box (they are also on Tab, Esc and Backspace).
	var tag_h := Access.px(9.0)
	var tag_y := box.end.y + 1
	var tag_col := Color(0.62, 0.6, 0.64)
	var sp := tr("Text: %s") % Dialogue.speed_name()
	_speed_rect = _tag(Vector2(box.position.x, tag_y), sp, tag_h, tag_col)
	_skip_rect = _tag(Vector2(_speed_rect.end.x + 4, tag_y), tr("Skip"), tag_h, tag_col)
	_log_rect = _tag(Vector2(_skip_rect.end.x + 4, tag_y), tr("Log"), tag_h, tag_col)
	if Access.auto_advance > 0:
		_tag(Vector2(_log_rect.end.x + 4, tag_y), tr("Auto"), tag_h, GOLD.darkened(0.2))
	var hint := Prompts.help([["ui_accept", "next"], ["swap", tr("text speed")], ["ui_cancel", "skip"], [DialogueLog.ACTION, tr("log")]], tr("Tap: next"))
	draw_string(font, Vector2(vs.x - font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x - 14, vs.y - 2), hint,
		HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(0.5, 0.48, 0.52))



## Ash's choice: a small stack of options just above the text box, the picked one in gold with a nib.
func _draw_choices(box: Rect2) -> void:
	_choice_rects = []
	var row_h := Access.px(16.0)
	var w := 0.0
	for o in _choices:
		w = maxf(w, font.get_string_size(str(o.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(11)).x)
	w = minf(w + 34.0, box.size.x - 40.0)
	var h := row_h * _choices.size() + 8.0
	var r := Rect2(box.end.x - w - 16.0, box.position.y - h - 4.0, w, h)
	UiSkin.page(self, r)
	for i in _choices.size():
		var rr := Rect2(r.position.x + 4, r.position.y + 4 + i * row_h, r.size.x - 8, row_h)
		_choice_rects.append(rr)
		var on := i == _choice
		if on:
			draw_rect(rr, Color(GOLD, 0.28))
			var tip := rr.position + Vector2(9, row_h * 0.5)
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-4, -3), tip + Vector2(2, 0), tip + Vector2(-4, 3)]), INK)
		draw_string(font, rr.position + Vector2(16, row_h * 0.5 + Access.fs(11) * 0.32), str(_choices[i].get("text", "")),
			HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 18, Access.fs(11), INK if on else INK_SOFT)


## A small tag under the box (Text speed, Skip, Log). Returns its tap rect.
func _tag(at: Vector2, s: String, h: float, col: Color) -> Rect2:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x + 10.0
	var r := Rect2(at, Vector2(w, h))
	draw_string(font, at + Vector2(4, h - 2.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), col)
	return r
