extends Control
## Buildings screen: every Hollowmark building and the Wardlamps, what each does now, what
## the next level costs and does, and who works there. Every choice previews its effect first.
##
## Three steps, all plain lists: buildings on the left, then that building's actions (build or
## upgrade, staff slots), then for a staff slot, who to post there. Keyboard, gamepad, mouse and
## touch. The clock keeps running underneath (pause it with 1).
##
## After the buildings: the tavern feast (after Act 1) and one Wardlamp row per province you hold. The list
## scrolls (wheel, drag, or just moving the selection) once it is longer than the screen. Levels 4 and 5 and
## level 3 beacons show their daily upkeep and what happens when it goes unpaid (issue #189).

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff8a7a")
const LIST_X := 8.0
const LIST_W := 214.0
const ROW_H := 24.0
const DETAIL_X := 236.0
const RES_COLORS := {"gilt": Color("e8c66a"), "supplies": Color("b7c98a"), "ink": Color("8fa7e8"), "insight": Color("d7b8f0")}

var sel := 0  # selected row (building or lamp)
var act := 0  # selected action
var pick := 0  # selected person in the picker
var focus := 0  # 0 = list, 1 = actions, 2 = picker
var picker_slot := -1  # which staff slot the picker fills
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var _row_rects: Array = []
var _act_rects: Array = []
var _pick_rects: Array = []
var scroll := 0.0  # how far the left list is scrolled down, in pixels
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


## Opens the screen, optionally on one building (walking up to it in town does that).
func open(building_id := "") -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	focus = 0
	act = 0
	var rows := _rows()
	sel = clampi(sel, 0, rows.size() - 1)
	if building_id != "":
		for i in rows.size():
			if rows[i]["id"] == building_id:
				sel = i
				focus = 1
	_follow_sel()


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


## The left list: buildings, the tavern feast, then one Wardlamp row per province you hold.
func _rows() -> Array:
	var out := []
	for id in Empire.building_ids():
		out.append({"kind": "building", "id": id})
	out.append({"kind": "feast", "id": "feast"})
	for p in Empire.territory().provinces:
		if p["owner"] == "you":
			out.append({"kind": "lamp", "id": p["id"]})
	return out


func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for k in ["gilt", "supplies", "ink"]:
		if int(cost.get(k, 0)) > 0:
			parts.append("%d %s" % [int(cost[k]), Loc.t(Empire.RES_NAMES[k])])
	return ", ".join(parts) if not parts.is_empty() else "free"


## The actions for the selected row: [{"kind", "label", "enabled", "note", "preview", "slot"}].
func _actions() -> Array:
	var rows := _rows()
	if rows.is_empty():
		return []
	var row: Dictionary = rows[sel]
	var out := []
	if row["kind"] == "feast":
		var why := Sinks.feast_blocker()
		var heads := Empire.recruits.size()
		out.append({"kind": "feast", "label": tr("Hold a feast  (%s)") % _cost_text(Sinks.feast_cost()), "enabled": why == "", "note": why,
			"preview": Loc.n("%d person at the table: %d Supplies and %d Gilt a head. The next feast can be %s after this one.", "%d people at the tables: %d Supplies and %d Gilt a head. The next feast can be %s after this one.", heads) % [heads, Sinks.FEAST_PER_HEAD["supplies"], Sinks.FEAST_PER_HEAD["gilt"], Loc.days(Sinks.FEAST_GAP)]})
		return out
	if row["kind"] == "lamp":
		var pid: String = row["id"]
		var nl := Empire.lamp_next(pid)
		var lv := int(Empire.lamps.get(pid, 0))
		if not nl.is_empty():
			var blocker := Empire.lamp_blocker(pid)
			var p := Empire.territory().find(pid)
			var verb := tr("Light a Wardlamp") if lv == 0 else tr("Brighten the Wardlamp to level %d") % nl["level"]
			var preview := tr("%s: Fray %d a day from the lamp instead of %d. The province would change by %+d a day.") % [p["name"], nl["fray"], Empire.lamp_fray(lv), Empire.fray_rate(p) - Empire.lamp_fray(lv) + int(nl["fray"])]
			if not (nl.get("upkeep", {}) as Dictionary).is_empty():
				preview += " " + tr("A beacon burns %s a day; without it, it burns as level %d.") % [_cost_text(nl["upkeep"]), nl["level"] - 1]
			out.append({"kind": "lamp", "label": Loc.n("%s  (%s, %d day)", "%s  (%s, %d days)", nl["days"]) % [verb, _cost_text(nl["cost"]), nl["days"]],
				"enabled": blocker == "", "note": blocker, "preview": preview})
		return out
	var id: String = row["id"]
	var b := Empire.building(id)
	var nl := Empire.next_level(id)
	var lv := Empire.level_of(id)
	var building_now: bool = Empire.construction.get("id", "") == id
	if not nl.is_empty() and not building_now:
		var blocker := Empire.build_blocker(id)
		var verb := tr("Build") if lv == 0 else tr("Upgrade to level %d") % nl["level"]
		var next_fx: Dictionary = Empire.building_effect(id, nl["level"], Empire.staff_of(id))
		var preview := Loc.n("Level %d: %s. %d staff slot.", "Level %d: %s. %d staff slots.", nl["slots"]) % [nl["level"], next_fx["text"], nl["slots"]]
		if not (nl.get("upkeep", {}) as Dictionary).is_empty():  # levels 4 and 5 (issue #189)
			preview += " " + tr("Upkeep %s a day; while a dawn can't pay it, the building works as level 3.") % _cost_text(nl["upkeep"])
		out.append({"kind": "build", "label": Loc.n("%s  (%s, %d day)", "%s  (%s, %d days)", nl["days"]) % [verb, _cost_text(nl["cost"]), nl["days"]],
			"enabled": blocker == "", "note": blocker, "preview": preview})
	if id == "scriptorium" and Sinks.feast_open():  # Ink lessons for benched heroes (issue #189)
		var pupils := Sinks.lesson_pupils().size()
		var why := Sinks.lessons_blocker()
		var on_label := Loc.n("Ink lessons: on, %d pupil", "Ink lessons: on, %d pupils", pupils) % pupils if why == "" else tr("Ink lessons: off")
		var note := "" if why == "" or why == tr("switched off") else why
		out.append({"kind": "lessons", "label": on_label + "  " + (tr("(switch off)") if Sinks.lessons_on() else tr("(switch on)")),
			"enabled": Sinks.lessons_open(), "note": note, "preview": Sinks.lessons_text()})
	if id == "market" and lv > 0:  # a full granary goes to the traders (issue #189)
		var sb := Sinks.sell_blocker()
		out.append({"kind": "sell", "label": tr("Sell %d Supplies for %d Gilt") % [Sinks.SELL_LOT, Sinks.sell_gilt()], "enabled": sb == "", "note": sb,
			"preview": tr("The traders take grain off your hands for a little coin; a charming trader gets more. Keep enough for upkeep and field rations.")})
	if building_now:  # spare Gilt buys extra hands (issue #189)
		var hb := Sinks.hurry_blocker()
		out.append({"kind": "hurry", "label": tr("Hurry the builders: a day sooner  (%s)") % _cost_text(Sinks.hurry_cost()), "enabled": hb == "", "note": hb,
			"preview": tr("Extra hands and overtime. The job finishes a day sooner; you can hurry it again while more than a few hours are left.")})
	var staff := Empire.staff_of(id)
	for i in Empire.slots_of(id):
		var who: String = staff[i] if i < staff.size() else ""
		var label := "%s %d:  %s" % [b["staff_title"], i + 1, Empire.recruit(who)["name"] if who != "" else Loc.t("empty")]
		if who != "":
			label += "  (%s %d)" % [String(b["stat"]).capitalize(), int(Empire.recruit(who)["stats"][b["stat"]])]
		var pairs := Relationships.notes_text(staff, "building")  # friends and rivals at work (issue #116)
		out.append({"kind": "slot", "slot": i, "who": who, "label": label, "enabled": true, "note": "",
			"preview": tr("Choose who works here. %s drives this building.%s") % [String(b["stat"]).capitalize(), ("\n" + pairs) if pairs != "" else ""]})
	return out


## The picker for a staff slot: leave empty, then everyone who could work here.
func _picks() -> Array:
	var rows := _rows()
	var id: String = rows[sel]["id"]
	var b := Empire.building(id)
	var staff := Empire.staff_of(id)
	var current: String = staff[picker_slot] if picker_slot >= 0 and picker_slot < staff.size() else ""
	var lv := Empire.level_of(id)
	var now_text: String = Empire.current_effect(id)["text"]
	var out := []
	var without := staff.filter(func(r): return r != current)
	out.append({"id": "", "label": tr("Leave empty") if current == "" else tr("Send %s back to idle") % Empire.recruit(current)["name"], "enabled": true, "note": "",
		"preview": tr("%s  (now: %s)") % [Empire.building_effect(id, lv, without)["text"], now_text]})
	for rid in Empire.roster_ids():
		if rid == current or rid in staff:
			continue
		var r := Empire.recruit(rid)
		var note := ""
		if r.get("locked_party", false):
			note = tr("Ash leads the party")
		elif int(Empire.recruits[rid]["injured"]) > 0:
			note = "injured"
		var with_me := without.duplicate()
		with_me.append(rid)
		var role := Empire.role_label(rid)
		var pairs := Relationships.notes_text(with_me, "building")  # friends and rivals at work (issue #116)
		out.append({"id": rid, "label": "%s  %s %d" % [r["name"], String(b["stat"]).capitalize(), int(r["stats"][b["stat"]])], "enabled": note == "", "note": note,
			"role": role, "preview": tr("%s  (now: %s)%s%s") % [Empire.building_effect(id, lv, with_me)["text"], now_text,
			"" if Empire.role_of(rid) == "idle" else tr(". Leaves their post: %s") % role, ("\n" + pairs) if pairs != "" else ""]})
	return out


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return  # the key that opened the screen must not also act inside it
	var up := Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up")
	var down := Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down")
	var accept := Input.is_action_just_pressed("ui_accept")
	var back := Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause")
	var right := Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right")
	var left := Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left")
	if Input.is_action_just_pressed("buildings"):
		close()
		return
	match focus:
		0:
			var n := _rows().size()
			if up:
				sel = posmod(sel - 1, n)
				_follow_sel()
			elif down:
				sel = posmod(sel + 1, n)
				_follow_sel()
			if (accept or right) and not _actions().is_empty():
				focus = 1
				act = 0
			elif back:
				close()
		1:
			var acts := _actions()
			if acts.is_empty():
				focus = 0
				return
			act = clampi(act, 0, acts.size() - 1)
			if up:
				act = posmod(act - 1, acts.size())
			elif down:
				act = posmod(act + 1, acts.size())
			if accept:
				_do(acts[act])
			elif back or left:
				focus = 0
		2:
			var picks := _picks()
			if up:
				pick = posmod(pick - 1, picks.size())
			elif down:
				pick = posmod(pick + 1, picks.size())
			if accept:
				_choose(picks[pick])
			elif back or left:
				focus = 1


func _do(a: Dictionary) -> void:
	var row: Dictionary = _rows()[sel]
	if not a["enabled"]:
		_flash(tr("Can't: %s.") % a["note"])
		return
	match a["kind"]:
		"build":
			if Empire.start_build(row["id"]):
				var b := Empire.building(row["id"])
				_flash(tr("Builders start on the %s. Done in %s.") % [b["name"], Empire.job_left_text(Empire.construction)])
		"lamp":
			if Empire.start_lamp(row["id"]):
				_flash(tr("A Wardlamp goes up in %s.") % Empire.territory().find(row["id"])["name"])
		"sell":
			if Sinks.sell_supplies():
				_flash(tr("Sold %d Supplies for %d Gilt.") % [Sinks.SELL_LOT, Sinks.sell_gilt()])
		"hurry":
			if Sinks.hurry():
				_flash(tr("Extra hands on the site. Done in %s.") % Empire.job_left_text(Empire.construction))
		"lessons":
			Sinks.set_lessons(not Sinks.lessons_on())
			_flash(tr("Ink lessons switched on.") if Sinks.lessons_on() else tr("Ink lessons switched off."))
		"feast":
			if Sinks.hold_feast():
				_flash(tr("The tavern throws open its doors. Everyone eats."))
		"slot":
			picker_slot = int(a["slot"])
			focus = 2
			pick = 0


func _choose(p: Dictionary) -> void:
	if not p["enabled"]:
		_flash(tr("Can't: %s.") % p["note"])
		return
	var id: String = _rows()[sel]["id"]
	var staff := Empire.staff_of(id)
	var current: String = staff[picker_slot] if picker_slot < staff.size() else ""
	if current != "":
		Empire.assign(current, "idle")
	if p["id"] != "":
		if Empire.assign(p["id"], "staff", id):
			_flash("%s: %s." % [Empire.recruit(p["id"])["name"], Empire.role_label(p["id"])])
	elif current != "":
		_flash(tr("%s is idle.") % Empire.recruit(current)["name"])
	focus = 1


func _flash(s: String) -> void:
	flash = s
	flash_t = 3.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if focus == 2:
			for i in _pick_rects.size():
				if (_pick_rects[i] as Rect2).has_point(event.position):
					pick = i
		else:
			for i in _row_rects.size():  # pointing at another building focuses it, like the arrow keys
				if (_row_rects[i] as Rect2).has_point(event.position) and sel != i:
					sel = i
					focus = 0
					act = 0
			for i in _act_rects.size():
				if (_act_rects[i] as Rect2).has_point(event.position):
					focus = 1
					act = i
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll += ROW_H * (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		_clamp_scroll()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_click(event.position)


## Touch does not emulate the mouse in this project, so taps arrive here.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventScreenDrag and event.position.x < LIST_X + LIST_W:
		scroll -= event.relative.y
		_clamp_scroll()
		get_viewport().set_input_as_handled()
		return
	if visible and event is InputEventScreenTouch and event.pressed:
		get_viewport().set_input_as_handled()
		_click(event.position)


func _click(pos: Vector2) -> void:
	if _close_rect().has_point(pos):
		close()
		return
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(pos):
			sel = i
			focus = 1 if not _actions().is_empty() else 0
			act = 0
			return
	if focus == 2:
		var picks := _picks()
		for i in _pick_rects.size():
			if (_pick_rects[i] as Rect2).has_point(pos):
				pick = i
				_choose(picks[i])
				return
		focus = 1  # tapping outside the picker closes it
		return
	var acts := _actions()
	for i in _act_rects.size():
		if (_act_rects[i] as Rect2).has_point(pos):
			act = i
			focus = 1
			_do(acts[i])
			return


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


const LIST_TOP := 30.0


func _list_bottom() -> float:
	return size.y - 22.0  # above the flash line


## Height of the whole left list, section heads included.
func _list_height() -> float:
	var h := 0.0
	var last := "building"
	for row in _rows():
		if row["kind"] != last:
			last = row["kind"]
			h += 17.0
		h += ROW_H
	return h


func _clamp_scroll() -> void:
	scroll = clampf(scroll, 0.0, maxf(_list_height() - (_list_bottom() - LIST_TOP), 0.0))


## Scrolls just enough to show the selected row.
func _follow_sel() -> void:
	var y := 0.0
	var last := "building"
	var rows := _rows()
	for i in rows.size():
		if rows[i]["kind"] != last:
			last = rows[i]["kind"]
			y += 17.0
		if i == sel:
			var view := _list_bottom() - LIST_TOP
			if y < scroll:
				scroll = y
			elif y + ROW_H > scroll + view:
				scroll = y + ROW_H - view
			break
		y += ROW_H
	_clamp_scroll()


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _row_status(row: Dictionary) -> Array:
	if row["kind"] == "feast":
		if not Sinks.feast_open():
			return [tr("After Act 1"), Color(0.55, 0.53, 0.56)]
		if Sinks.fed():
			return [tr("The party is still full"), GOOD]
		var left := Sinks.feast_ready_day() - Empire.day
		if left > 0:
			return [Loc.n("Next feast in %d day", "Next feast in %d days", left) % left, Color(0.62, 0.6, 0.62)]
		return [tr("Ready: %s") % _cost_text(Sinks.feast_cost()), GOLD]
	if row["kind"] == "lamp":
		var pid: String = row["id"]
		if Empire.lamp_jobs.has(pid):
			return [tr("Going up: %s left") % Empire.job_left_text(Empire.lamp_jobs[pid]), GOLD]
		var lv := int(Empire.lamps.get(pid, 0))
		if lv > 0 and Sinks.lamp_working_level(pid) < lv:
			return [tr("Unfed beacon: burns as level %d") % Sinks.lamp_working_level(pid), BAD]
		return [tr("Unlit") if lv == 0 else tr("Lit, level %d  (Fray %d a day)") % [lv, Empire.lamp_fray(lv)], Color(0.62, 0.6, 0.62) if lv == 0 else GOOD]
	var id: String = row["id"]
	var lv := Empire.level_of(id)
	if Empire.construction.get("id", "") == id:
		return [tr("%s: %s left") % [tr("Building") if lv == 0 else tr("Upgrading"), Empire.job_left_text(Empire.construction)], GOLD]
	if lv == 0:
		return [tr("Not built"), Color(0.55, 0.53, 0.56)]
	if Sinks.working_level(id) < lv:
		return [tr("Level %d, works as %d: upkeep unpaid") % [lv, Sinks.working_level(id)], BAD]
	return [tr("Level %d/%d   staff %d/%d") % [lv, Empire.max_level(id), Empire.staff_of(id).size(), Empire.slots_of(id)], Color(0.7, 0.68, 0.7)]


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	_text(Vector2(LIST_X, 20), tr("Buildings"), 15, Color("f3efe4"))
	# Resources, Insight included (it only lives here and in the ledger for now).
	var x := LIST_X + 90
	for k in ["gilt", "supplies", "ink", "insight"]:
		var s := "%s %d" % [Loc.t(Empire.RES_NAMES[k]), int(Empire.res.get(k, 0))]
		_text(Vector2(x, 19), s, 9, RES_COLORS[k])
		x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x + 12
	var crew := tr("Builders: idle")
	if not Empire.construction.is_empty():
		crew = tr("Builders: %s, %s left") % [Empire.building(Empire.construction["id"])["name"], Empire.job_left_text(Empire.construction)]
	_text(Vector2(x + 6, 19), crew, 9, GOLD if not Empire.construction.is_empty() else Color(0.6, 0.58, 0.6))
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))

	# Left list
	var rows := _rows()
	_row_rects.clear()
	_clamp_scroll()
	var y := LIST_TOP - scroll
	var bottom := _list_bottom()
	var last_kind := "building"
	for i in rows.size():
		var row: Dictionary = rows[i]
		if row["kind"] != last_kind:
			last_kind = row["kind"]
			y += 4
			if y >= LIST_TOP - 4 and y + 13 <= bottom:
				_text(Vector2(LIST_X, y + 9), tr("Wardlamps") if row["kind"] == "lamp" else tr("Hollowmark"), 9, Color(0.7, 0.68, 0.7))
			y += 13
		var r := Rect2(LIST_X, y, LIST_W, ROW_H - 3)
		if y < LIST_TOP - 1 or y + ROW_H - 3 > bottom:
			_row_rects.append(Rect2())  # scrolled out of view: keeps the index, never hit
			y += ROW_H
			continue
		_row_rects.append(r)
		var on := i == sel
		UiSkin.row(self, r, on, focus == 0)
		var name_s: String = Empire.building(row["id"])["name"] if row["kind"] == "building" else (tr("Tavern feast") if row["kind"] == "feast" else Empire.territory().find(row["id"])["name"])
		var tx := 8.0
		if row["kind"] in ["building", "feast"] and UiSkin.draw_icon(self, row["id"], Rect2(r.position + Vector2(5, 3), Vector2(18, 18))):
			tx = 27.0
		_text(r.position + Vector2(tx, 10), name_s, 9, GOLD if on else Color("ece6da"))
		var st := _row_status(row)
		_text(r.position + Vector2(tx, 19), st[0], 7, st[1])
		if row["kind"] == "building" and Empire.construction.get("id", "") == row["id"]:
			UiSkin.bar(self, Rect2(r.position.x + 130, r.position.y + 6, 76, 4), Empire.job_progress(Empire.construction), "brass", {"notches": [0.25, 0.5, 0.75]})
		y += ROW_H
	var total := _list_height()
	if total > bottom - LIST_TOP:  # scroll bar
		var view := bottom - LIST_TOP
		var tr_r := Rect2(LIST_X + LIST_W + 3, LIST_TOP, 3, view)
		var th := maxf(view * view / total, 12.0)
		UiSkin.scrollbar(self, tr_r, (view - th) * scroll / maxf(total - view, 1.0), th)
	if rows.is_empty():
		return

	# Detail: written up on a ledger page (LedgerPage) sized to its text, the actions under it.
	var row: Dictionary = rows[sel]
	var w := vs.x - DETAIL_X - 8
	var entries := []  # [text, size, colour, wrapped?], heading first
	var bar_job := {}
	var bar_label := ""
	var icon_id := ""
	if row["kind"] == "feast":
		entries.append([tr("Tavern feast"), 13, LedgerPage.INK, false])
		entries.append([tr("Long tables in the square, a pig on the spit and everyone who works for you at one sitting. It costs a little for every mouth, and the tavern needs a week to recover."), 8, LedgerPage.INK_SOFT, true])
		entries.append([Sinks.feast_text(), 8, LedgerPage.GREEN, true])
	elif row["kind"] == "lamp":
		var p := Empire.territory().find(row["id"])
		entries.append([tr("Wardlamp: %s") % p["name"], 13, LedgerPage.INK, false])
		entries.append([Empire.lamp_data["blurb"], 8, LedgerPage.INK_SOFT, true])
		var rate := Empire.fray_rate(p)
		entries.append([tr("Fray %d / 100, changing %+d a day") % [int(p["fray"]), rate], 8, LedgerPage.RED if rate > 0 else LedgerPage.GREEN, false])
		if Empire.lamp_jobs.has(row["id"]):
			bar_job = Empire.lamp_jobs[row["id"]]
			bar_label = tr("Going up")
	else:
		var id: String = row["id"]
		var b := Empire.building(id)
		var lv := Empire.level_of(id)
		icon_id = id
		entries.append([b["name"], 13, LedgerPage.INK, false])
		entries.append([tr("Not built") if lv == 0 else tr("Level %d of %d") % [lv, Empire.max_level(id)], 8, LedgerPage.INK_SOFT, false])
		entries.append([Prompts.fill(str(b["blurb"])), 8, LedgerPage.INK, true])
		if lv > 0:
			entries.append([tr("Now: %s") % Empire.current_effect(id)["text"], 8, LedgerPage.GREEN, true])
			var up := Sinks.building_upkeep(id)
			if not up.is_empty():  # levels 4 and 5 (issue #189)
				var unpaid := Sinks.working_level(id) < lv
				entries.append([(tr("Upkeep %s a day. Unpaid at the last dawn: working as level 3.") if unpaid else tr("Upkeep %s a day, paid at dawn.")) % _cost_text(up), 8, LedgerPage.RED if unpaid else LedgerPage.INK_SOFT, true])
		if Empire.construction.get("id", "") == id:
			bar_job = Empire.construction
			bar_label = tr("Building") if lv == 0 else tr("Upgrading to level %d") % (lv + 1)
	var pw := w + 8.0
	var need := 0
	for i in range(1, entries.size()):
		need += LedgerPage.lines_for(entries[i][0], font, entries[i][1], pw) if entries[i][3] else 1
	if not bar_job.is_empty():
		need += 2
	var ph := minf(LedgerPage.height_for(need, font), vs.y * 0.55)
	var pg := LedgerPage.begin(self, Rect2(DETAIL_X - 6, 36, pw, ph), font)
	pg.heading(entries[0][0], entries[0][1], entries[0][2], icon_id)
	for i in range(1, entries.size()):
		if entries[i][3]:
			pg.para(entries[i][0], entries[i][1], entries[i][2])
		else:
			pg.line(entries[i][0], entries[i][1], entries[i][2])
	if not bar_job.is_empty():
		pg.line(tr("%s: %s left") % [bar_label, Empire.job_left_text(bar_job)], 8, LedgerPage.GOLD)
		var jr := pg.space()
		if jr.size.x > 0.0:
			UiSkin.bar(self, Rect2(jr.position.x, jr.end.y - 5.0, jr.size.x, 4), Empire.job_progress(bar_job), "brass", {"notches": [0.25, 0.5, 0.75]})
	var dy := 36.0 + ph

	# Actions
	var acts := _actions()
	_act_rects.clear()
	var ay := dy + 6
	for i in acts.size():
		var a: Dictionary = acts[i]
		var r := Rect2(DETAIL_X, ay, w, 17)
		_act_rects.append(r)
		var hl := focus >= 1 and i == act
		UiSkin.row(self, r, hl, focus == 1)
		var col := Color("ece6da") if a["enabled"] else Color(0.42, 0.41, 0.44)
		_text(r.position + Vector2(8, 12), a["label"], 9, GOLD if hl and a["enabled"] and focus == 1 else col)
		if not a["enabled"] and a["note"] != "":
			var lw := font.get_string_size(a["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
			_text(r.position + Vector2(14 + lw, 12), "(" + a["note"] + ")", 7, Color(0.6, 0.45, 0.42))
		ay += 19
	if acts.is_empty():
		var why := tr("Fully upgraded.") if row["kind"] == "lamp" else tr("Nothing to do here right now.")
		_text(Vector2(DETAIL_X, ay + 10), why, 8, Color(0.5, 0.48, 0.52))
		ay += 16

	if focus == 2:
		_draw_picker(ay, w)
	elif focus == 1 and act < acts.size() and acts[act]["preview"] != "":
		_wrap(Vector2(DETAIL_X, ay + 12), acts[act]["preview"], w, 8, Color("cfe0b0"))

	var help := Prompts.help([["updown", "choose"], ["ui_accept", "open"], [["ui_cancel", "buildings"], "close"]], tr("Tap a building, then tap what to do"))
	if focus == 1:
		help = Prompts.help([["updown", "choose"], ["ui_accept", tr("do it")], ["ui_cancel", "back"]], tr("Tap what to do   Tap the building list to go back"))
	elif focus == 2:
		help = Prompts.help([["updown", tr("choose who")], ["ui_accept", tr("post them")], ["ui_cancel", "back"]], tr("Tap who to post"))
	_text(Vector2(DETAIL_X, vs.y - 8), help, 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a2 := clampf(flash_t / 0.4, 0.0, 1.0)
		_wrap(Vector2(LIST_X, vs.y - 18), flash, LIST_W, 8, Color(1, 0.9, 0.7, a2))


func _draw_picker(py: float, w: float) -> void:
	var picks := _picks()
	pick = clampi(pick, 0, picks.size() - 1)
	var title := tr("Who works here?")
	_text(Vector2(DETAIL_X, py + 10), title, 9, Color("f3efe4"))
	py += 14
	_pick_rects.clear()
	var rh := clampf((size.y - py - 40.0) / float(maxi(picks.size(), 1)), 11.0, 15.0)  # a big roster squeezes up
	var ty := minf(10.0, rh - 2.0)
	for i in picks.size():
		var p: Dictionary = picks[i]
		var r := Rect2(DETAIL_X + 8, py, w - 8, rh - 1)
		_pick_rects.append(r)
		var hl := i == pick
		draw_rect(r, Color(0.2, 0.16, 0.1) if hl else Color(0.08, 0.07, 0.1))
		if hl:
			draw_rect(r, GOLD, false, 1.0)
		var col := Color("ece6da") if p["enabled"] else Color(0.42, 0.41, 0.44)
		_text(r.position + Vector2(6, ty), p["label"], 8, GOLD if hl and p["enabled"] else col)
		var side: String = p.get("role", "") if p["enabled"] else "(" + p["note"] + ")"
		if side != "":
			_text(r.position + Vector2(150, ty), side, 7, Color(0.55, 0.53, 0.56))
		py += rh
	if pick < picks.size():
		_wrap(Vector2(DETAIL_X, py + 10), picks[pick]["preview"], w, 8, Color("cfe0b0"))
