extends Control
## Newcomers screen. Opened with N, from the menus, in town or on the Command Table.
##
## Left: everyone who could still join. People waiting at Hollowmark's south gate come first;
## below them, rumours of people out there and what it takes to bring them in.
## Right: who they are, their stats and traits, their hook and how close you are to it.
## Enter on a visitor takes them on (for their hire price). Esc / N closes.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const RUMOUR := Color("c9b6e8")
const STAT_KEYS := ["might", "craft", "lore", "charm", "grit"]
const TIER_NAMES := {"field": "Field hero", "core": "Core staff", "recruit": "Recruit"}
const TIER_COLORS := {"field": Color("e8a05a"), "core": Color("8fa7e8"), "recruit": Color("a9a39a")}
const LIST_W := 220.0

var sel := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _row_rects: Array = []
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open(who := "") -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	var ids := Empire.lead_ids()
	sel = clampi(sel, 0, maxi(ids.size() - 1, 0))
	if who != "" and who in ids:
		sel = ids.find(who)
	elif not ids.is_empty() and Empire.is_visitor(ids[0]):
		sel = 0


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("newcomers"):
		close()
		return
	var ids := Empire.lead_ids()
	if ids.is_empty():
		if Input.is_action_just_pressed("ui_accept"):
			close()
		return
	sel = clampi(sel, 0, ids.size() - 1)
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		sel = posmod(sel - 1, ids.size())
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		sel = posmod(sel + 1, ids.size())
	if Input.is_action_just_pressed("ui_accept"):
		_pick(ids[sel])


func _pick(id: String) -> void:
	var r := Empire.recruit(id)
	if not Empire.is_visitor(id):
		_say(Empire.hook_text(id))
		return
	var why := Empire.hire_blocker(id)
	if why != "":
		_say(tr("Can't take on %s: %s.") % [r["name"], why])
		return
	if Empire.hire(id):
		_say("%s: %s" % [Empire.short_name(id), r.get("welcome", tr("Glad to be here."))])
		sel = 0


func _say(s: String) -> void:
	flash = s
	flash_t = 4.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position):
				sel = i
	elif Prompts.tapped(event):
		if _close_rect().has_point(event.position):
			close()
			return
		var ids := Empire.lead_ids()
		for i in _row_rects.size():
			if (_row_rects[i] as Rect2).has_point(event.position) and i < ids.size():
				if sel == i:
					_pick(ids[i])  # tap to select, tap again to act (touch friendly)
				sel = i
				return
		if _hire_rect().has_point(event.position) and sel < ids.size():
			_pick(ids[sel])


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


func _hire_rect() -> Rect2:
	return Rect2(Vector2(LIST_W + 24, size.y - 42), Vector2(150, 18))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	# Text cut by its width ends in "..." rather than mid-letter (long names at large text sizes).
	draw_string(font, pos, Access.fit(font, s, Access.fs(fsize), width) if width > 0.0 else s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	_row_rects.clear()
	_text(Vector2(8, 20), tr("Newcomers"), 15, Color("f3efe4"))
	var ids := Empire.lead_ids()
	var waiting := ids.filter(func(id): return Empire.is_visitor(id)).size()
	var hl := UiSkin.header_line(font, tr("Newcomers"), 15, (tr("%d waiting at the gate.") % waiting) if waiting > 0 else "", 9, vs.x, 98.0)
	_text(Vector2(hl[0], 20), hl[1], 9, GOLD)
	_text(Vector2(8, 34), tr("Roster %d of %d. People turn up at the south gate when you meet their hook; talk to them there or take them on here.")
		% [Empire.roster_ids().size(), Empire.recruit_data.size()], 8, SOFT, vs.x - 70)
	if ids.is_empty():
		_text(Vector2(8, 60), tr("Everyone in the Inklands worth having is already on your roster. For now."), 10, TEXT)
		return
	var row_h := minf(30.0, (vs.y - 64.0) / float(ids.size()))
	var y := 44.0
	for i in ids.size():
		var id: String = ids[i]
		var r := Empire.recruit(id)
		var rr := Rect2(8, y, LIST_W, row_h - 3)
		_row_rects.append(rr)
		var on := i == sel
		var here := Empire.is_visitor(id)
		UiSkin.row(self, rr, on)
		UiSkin.tab(self, rr, "brass" if here else TIER_COLORS.get(r["tier"], SOFT))
		_text(rr.position + Vector2(10, 12), r["name"], 9, GOLD if on else TEXT, 120)
		var tag := tr("at the gate") if here else ("rescue" if Empire.join_hook(id).get("type", "") == "rescue" else "rumour")
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
		_text(rr.position + Vector2(LIST_W - 6 - tw, 12), tag, 8, GOLD if here else RUMOUR)
		if row_h >= 26.0:
			_text(rr.position + Vector2(10, 23), r.get("title", ""), 8, SOFT, LIST_W - 16)
		y += row_h
	_draw_details(vs, ids[sel])
	_text(Vector2(8, vs.y - 8), Prompts.help([["updown", "choose"], ["ui_accept", tr("take on / show hook")], [["ui_cancel", "newcomers"], "close"]], tr("Tap a name, tap again to take them on")), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var fw := minf(font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x, vs.x - 40)
		draw_rect(Rect2(vs.x - fw - 18, vs.y - 21, fw + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - fw - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a), fw)


func _draw_details(vs: Vector2, id: String) -> void:
	var r := Empire.recruit(id)
	var here := Empire.is_visitor(id)
	var x := LIST_W + 24
	var w := vs.x - x - 10
	var top := 44.0
	var hr := _hire_rect()
	# Written up on a ledger page (LedgerPage), on its lines; the hire button sits under it.
	var bottom := (hr.position.y - 4.0) if here else vs.y - 18.0
	var pg := LedgerPage.begin(self, Rect2(x - 8, top, w + 16, bottom - top), font)
	pg.heading(r["name"], 13)
	pg.line(r.get("title", ""), 8, LedgerPage.INK_SOFT, Loc.t(TIER_NAMES.get(r["tier"], "")), LedgerPage.ink(TIER_COLORS.get(r["tier"], SOFT)))
	pg.para(r.get("blurb", ""), 8, LedgerPage.INK)
	# Stats on one line of little bars, traits under them.
	var sr := pg.space(2)
	if sr.size.x > 0.0:
		var cw := sr.size.x / 5.0
		for i in STAT_KEYS.size():
			var k: String = STAT_KEYS[i]
			var v := int(r["stats"][k])
			var sx := sr.position.x + i * cw
			draw_string(font, Vector2(sx, sr.position.y + pg.lh - 2.0), Access.fit(font, "%s %d" % [Loc.t(Empire.STAT_NAMES[k]), v], Access.fs(8), cw - 4.0), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8), LedgerPage.INK)
			UiSkin.bar(self, Rect2(sx, sr.end.y - 5.0, cw - 8.0, 3), v / 10.0, "bone", {"notch": 5})
	for t in r.get("traits", []):
		var td: Dictionary = Empire.trait_data.get(t, {})
		pg.para("%s: %s" % [td.get("name", t), td.get("desc", "")], 8, LedgerPage.GREEN)
	pg.skip()
	# The hook
	if here:
		pg.para("\"%s\"" % r.get("pitch", tr("I'm looking for work.")), 8, LedgerPage.GOLD)
	else:
		pg.para(r.get("rumour", ""), 8, LedgerPage.PLUM)
		pg.para(tr("How: %s") % Empire.hook_text(id), 8, LedgerPage.INK)
	var prog: Array = Empire.hook_progress(id)
	if prog[0] != "":
		pg.para(tr("Now: %s") % prog[0], 8, LedgerPage.GREEN if prog[1] else LedgerPage.INK_SOFT)
	if Empire.join_hook(id).get("type", "") != "rescue":
		var cost := Empire.hire_cost(id)
		var price := "free" if cost.is_empty() else Empire.cost_text(cost)
		pg.skip()
		pg.para(tr("Takes: %s.  Upkeep %d Supplies a day.") % [price, Empire.UPKEEP_SUPPLIES], 8, LedgerPage.INK_SOFT)
	if here:
		var why := Empire.hire_blocker(id)
		UiSkin.panel(self, hr, "button", Color.WHITE if why == "" else Color(0.6, 0.6, 0.62))
		var label := tr("Take them on (%s)") % Prompts.confirm() if why == "" else tr("Can't: %s") % why
		_text(hr.position + Vector2(8, 12), label, 9, GOLD if why == "" else BAD, hr.size.x - 12)
