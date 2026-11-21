extends Control
## Bond scenes, visual-novel style: a big character card on the left, a text box along the bottom,
## and (usually) one choice for Ash, who never speaks: the choices are what Ash does.
##
## Art: the character's portrait (assets/portraits/<id>.png, see docs/PORTRAITS.md) stands on the
## left, flipped to face Ash, who stands on the right. Whoever has the floor is lit, the other dims.
## A line may carry a third entry, an expression ("happy", "smug"...): <id>_<expr>.png is used when
## it exists. Characters with no portrait yet fall back to a bust drawn in code from their colours. Enter / J / click / tap moves on (finishing the line first if it
## is still typing); Up/Down pick a choice; Esc skips ahead to the choice (or closes a replay).
## The first time through, finishing the scene raises the bond rank (Empire.finish_bond_scene).

signal finished(id: String, rank: int)

const GOLD := Color("ffd166")
const TEXT := Color("ece6da")
const SOFT := Color(0.66, 0.64, 0.66)
const CHARS_PER_SEC := 70.0

var id := ""
var rank := 0
var replay := false
var closed_frame := -1
var opened_frame := -1
var _lines: Array = []  # [speaker, text] still to show; the current one is _lines[_at]
var _at := 0
var _shown := 0.0  # characters revealed of the current line
var _stage := "lines"  # lines -> choice -> reply -> done
var _choice := 0
var _picked := -1
var _choice_rects: Array = []
var _outro := ""  # the closing card: new rank and perk
var font: Font
var _opened_ms := 0
static var _portraits := {}  # path -> Texture2D or null, shared by every scene


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


## Play the scene for this person and rank. replay = already seen (no bond changes).
func play(who: String, r: int, is_replay := false) -> void:
	id = who
	rank = r
	replay = is_replay
	var sc := Empire.bond_scene(id, rank)
	if sc.is_empty():
		return
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	_opened_ms = Time.get_ticks_msec()
	_lines = sc["lines"].duplicate()
	_at = 0
	_shown = 0.0
	_stage = "lines"
	_choice = 0
	_picked = -1
	_outro = ""


func _scene() -> Dictionary:
	return Empire.bond_scene(id, rank)


func _close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	finished.emit(id, rank)


func _current() -> Array:
	return _lines[_at] if _at < _lines.size() else ["", ""]


func _typing() -> bool:
	return _stage in ["lines", "reply"] and _shown < float(String(_current()[1]).length())


func _advance() -> void:
	match _stage:
		"lines", "reply":
			if _typing():
				_shown = 99999.0
				return
			_at += 1
			_shown = 0.0
			if _at < _lines.size():
				return
			if _stage == "lines" and not _scene().get("choice", []).is_empty():
				_stage = "choice"
			else:
				_finish()
		"choice":
			_pick(_choice)
		"done":
			_close()


func _pick(i: int) -> void:
	var opts: Array = _scene().get("choice", [])
	if i < 0 or i >= opts.size():
		return
	_picked = i
	_lines = opts[i].get("reply", []).duplicate() + _scene().get("end", []).duplicate()
	_at = 0
	_shown = 0.0
	_stage = "reply"
	if _lines.is_empty():
		_finish()


func _finish() -> void:
	_stage = "done"
	if replay:
		_outro = tr("Memory: %s") % _scene().get("title", "")
		return
	var perk := Empire.finish_bond_scene(id, rank, _picked)
	if rank == Relationships.MOMENT:  # the romance question (issue #116)
		if Relationships.romance_of(id) == "partner":
			_outro = tr("%s and Ash: a romance.\nWhile it lasts: %s. %s") % [Empire.short_name(id), perk.get("name", ""), perk.get("desc", "")]
		else:
			_outro = tr("%s and Ash: friends, and that's settled.") % Empire.short_name(id)
		return
	_outro = tr("%s is now %s.  Bond rank %d.") % [Empire.short_name(id), Empire.bond_rank_name(Empire.bond_rank(id)), Empire.bond_rank(id)]
	if not perk.is_empty():
		_outro += tr("\nPerk unlocked: %s. %s") % [perk["name"], perk["desc"]]
	if rank == 4 and Empire.personal_job(id) != "":
		var pd := PersonalMissions.def_for(id)
		_outro += tr("\nPersonal mission on the Command Table: %s, at %s.") % [pd.get("name", "?"), Empire.territory().find(pd.get("province", "")).get("name", "?")]


func _process(delta: float) -> void:
	if not visible:
		return
	queue_redraw()
	if _stage in ["lines", "reply"]:
		DialogueLog.track(self, _current(), "scene")
	if DialogueLog.is_open():
		return  # the dialogue log is up over the scene (issue #34)
	if _stage in ["lines", "reply"]:
		_shown += delta * CHARS_PER_SEC
	if Engine.get_process_frames() == opened_frame:
		return
	if DialogueLog.asked():
		DialogueLog.popup(get_parent())
		return
	var opts: Array = _scene().get("choice", [])
	if _stage == "choice":
		if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
			_choice = posmod(_choice - 1, opts.size())
		elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
			_choice = posmod(_choice + 1, opts.size())
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("attack"):
		_advance()
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		if replay or _stage == "done":
			_close()
		elif _stage == "lines":  # skip ahead to the choice
			_at = _lines.size() - 1
			_shown = 99999.0
			_advance()
		elif _stage == "reply":
			_at = _lines.size() - 1
			_shown = 99999.0
			_advance()


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2.INF
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseMotion and _stage == "choice":
		for i in _choice_rects.size():
			if (_choice_rects[i] as Rect2).has_point(event.position):
				_choice = i
		return
	if pos == Vector2.INF or Engine.get_process_frames() == opened_frame:
		return
	if _stage == "choice":
		for i in _choice_rects.size():
			if (_choice_rects[i] as Rect2).has_point(pos):
				_pick(i)
				return
		return
	_advance()


# ---------------------------------------------------------------- drawing

## The portrait for this character (and expression, if drawn), or null when there is none yet.
static func portrait(who: String, expression := "") -> Texture2D:
	for key in ([who + "_" + expression] if expression != "" else []) + [who]:
		var path := "res://assets/portraits/%s.png" % key
		if not _portraits.has(path):
			_portraits[path] = load(path) if ResourceLoader.exists(path) else null
		if _portraits[path] != null:
			return _portraits[path]
	return null


## Draw a portrait standing with its feet at `bottom`, `h` tall. flip = face right.
## lit = has the floor; otherwise it is dimmed and pushed back a little.
func _draw_portrait(tex: Texture2D, center_x: float, bottom: float, h: float, flip: bool, lit: bool, slide: float) -> void:
	var sz := Dialogue.portrait_size(tex, h)  # pixel art: whole-number scale, so no shrink when dimmed
	tex = Dialogue.fitted(tex, sz.y)
	var pos := Vector2(center_x - sz.x / 2, bottom - sz.y)
	var a := clampf(slide, 0.0, 1.0)
	pos.x += (1.0 - a) * (-24.0 if flip else 24.0)
	var tint := Color(1, 1, 1, a) if lit else Color(0.42, 0.4, 0.48, a)
	if flip:
		draw_set_transform(Vector2(pos.x + sz.x, pos.y), 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, Rect2(Vector2.ZERO, sz), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(tex, Rect2(pos, sz), false, tint)


## A soft glow in the character's accent colour behind where they stand.
func _draw_glow(center: Vector2, radius: float, col: Color) -> void:
	for i in 32:
		var t := 1.0 - float(i) / 32.0
		draw_circle(center, radius * t, Color(col, 0.012))


func _draw() -> void:
	var vs := size
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.025, 0.05, 0.94))
	var sc := _scene()
	if sc.is_empty():
		return
	var accent := Color(Empire.bond_info(id).get("color", "c9c3b6"))
	# Who has the floor: the speaker of the current line, or Ash while choosing.
	var speaker_now := ""
	if _stage in ["lines", "reply"]:
		speaker_now = _current()[0]
	var expr: String = _current()[2] if _stage in ["lines", "reply"] and _current().size() > 2 else ""
	var ash_lit := _stage == "choice" or speaker_now == "ash"
	var them_lit := not ash_lit
	var slide := (Time.get_ticks_msec() - _opened_ms) / 250.0
	var floor_y := vs.y - 30
	var them := portrait(id, expr if speaker_now == id else "")
	var ash := portrait("ash")
	if ash != null:
		_draw_glow(Vector2(vs.x - 130, floor_y - 150), 150, Color("3a5a9a"))
		_draw_portrait(ash, vs.x - 130, floor_y, 300, false, ash_lit, slide)
	if them != null:
		_draw_glow(Vector2(150, floor_y - 160), 170, accent)
		_draw_portrait(them, 150, floor_y, 330, true, them_lit, slide)
	else:  # safety net only: tests/test_data.gd requires a portrait for everyone with a bond
		Dialogue.draw_portrait(self, Rect2(24, 30, 150, vs.y - 30 - 102), id, "", 0.0 if them_lit else 0.55, true)
	# Header: whose scene, which rank
	var head := "%s  ·  %s: %s%s" % [Empire.short_name(id), tr("Between ranks 3 and 4") if rank == Relationships.MOMENT else tr("Bond rank %d") % rank,
		sc.get("title", ""), tr("   (memory)") if replay else ""]
	var hw := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10)).x
	draw_rect(Rect2(vs.x - hw - 18, 5, hw + 12, 18), Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(vs.x - hw - 12, 18), head, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10), accent.lightened(0.2))

	var box := Rect2(12, vs.y - 96, vs.x - 24, 86)
	UiSkin.page(self, box)
	_choice_rects.clear()
	var ink := UiSkin.PAGE_INK
	match _stage:
		"lines", "reply":
			var cur := _current()
			var speaker: String = cur[0]
			var text: String = cur[1]
			var shown := text.substr(0, int(_shown))
			var tx := box.position.x + 30
			var ty := box.position.y + 22
			if speaker != "":
				var nm := Empire.short_name(speaker)
				var nw := UiSkin.TITLE_FONT.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(14)).x
				var np := Vector2(tx, box.position.y + 18)
				UiSkin.brush(self, np + Vector2(-3, 3), nw + 8, Dialogue.accent(speaker).darkened(0.15))
				draw_string(UiSkin.TITLE_FONT, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(14), ink)
				ty += 12
			draw_multiline_string(font, Vector2(tx, ty), shown, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, Access.fs(11), -1,
				ink if speaker != "" else UiSkin.PAGE_INK_SOFT)
			if not _typing():
				var tip := box.end - Vector2(22, 14 - sin(Time.get_ticks_msec() / 220.0) * 1.5)
				draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-3, -7), tip + Vector2(0, -10), tip + Vector2(3, -7)]), ink)
		"choice":
			draw_string(font, box.position + Vector2(30, 14), tr("Ash..."), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), UiSkin.PAGE_INK_SOFT)
			var opts: Array = sc.get("choice", [])
			var y := box.position.y + 20
			for i in opts.size():
				var rr := Rect2(box.position.x + 28, y, box.size.x - 60, 17)
				_choice_rects.append(rr)
				var on := i == _choice
				if on:  # an ink wash under the picked answer, with a nib pointing at it
					draw_rect(rr, Color(0.35, 0.27, 0.19, 0.18))
					draw_colored_polygon(PackedVector2Array([rr.position + Vector2(-8, 5), rr.position + Vector2(-3, 8.5), rr.position + Vector2(-8, 12)]), ink)
				draw_string(font, rr.position + Vector2(8, 12), opts[i]["label"], HORIZONTAL_ALIGNMENT_LEFT, rr.size.x - 16, Access.fs(10), ink if on else UiSkin.PAGE_INK_SOFT)
				y += 20
		"done":
			draw_multiline_string(font, box.position + Vector2(30, 22), _outro, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, Access.fs(10), -1, Color("3f6a32"))
	var hint := Prompts.help([["ui_accept", "next"], ["ui_cancel", "skip"]], tr("Tap: next")) if _stage != "choice" \
		else Prompts.help([["updown", "choose"], ["ui_accept", "pick"]], tr("Tap an answer"))
	if _stage == "done":
		hint = Prompts.help([["ui_accept", "close"]], tr("Tap to close"))
	draw_string(font, Vector2(vs.x - font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x - 14, vs.y - 3), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(0.5, 0.48, 0.52))
