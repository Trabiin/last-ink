class_name GearView
extends Control
## Party gear screen (issue #15): levels, XP and equipment for each field hero, their weapon and Ink
## skills (issue #24), plus the Hollowmark shop. Opened with K in town and on the Command Table, and
## from the pause menu on a mission (no shop out there; changes take effect on the spot).
##
## Equip tab: Left/Right picks the hero, Up/Down the slot, Enter opens the list of spare gear
## for that slot (Up/Down, Enter puts it on, Esc goes back). Skills tab: Left/Right the hero, Up/Down
## a tech, Enter makes it the one the hero always charges (again: back to choosing by hold length).
## Shop tab: Up/Down, Enter buys or sells. Q / E (LB / RB) switch tabs, shown beside the tab row (TabStrip).
## Mouse and touch: tap to select, tap again to act.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const XP_COL := Color("b9a0e8")
const PAPER := Color("f3efe4")
const SLOT_COLORS := {"weapon": Color("e89a8a"), "armor": Color("8fa7e8"), "trinket": Color("e8c66a")}

var party  # main.gd on a mission: live heroes get the new stats right away
var where := "town"  # "town" (shop open) or "mission"
var tab := "equip"
var hero_i := 0
var slot_i := 0
var picking := false
var pick_i := 0
var shop_i := 0
var tech_i := 0  # Skills tab: the highlighted tech
var _tech_rects: Array = []
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var font: Font
var _ids: Array = []
var _hero_rects: Array = []
var _slot_rects: Array = []
var _pick_rects: Array = []
var _shop_rects: Array = []
var _strip := TabStrip.new()  # the tab row with its switch keys either side
var _tree: SkillTreeView = null  # the skill tree screen (issue #25) while it is open over this one
var _tree_closed := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open(at := "town") -> void:
	where = at
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	_ids = Progress.field_ids()
	if party != null and where == "mission":
		_ids = party.heroes.map(func(h): return (h as Hero).hero_id)
	hero_i = clampi(hero_i, 0, maxi(_ids.size() - 1, 0))
	tab = "equip"
	picking = false


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _shop_open() -> bool:
	return where == "town"


func _hero_id() -> String:
	return _ids[hero_i] if hero_i < _ids.size() else ""


func _slot() -> String:
	return Progress.SLOTS[slot_i]


## What the pick list offers for the current slot: "" (take it off) and the spare gear that fits.
func _choices() -> Array:
	var out := [""]
	out.append_array(Progress.options(_hero_id(), _slot()))
	return out


## Shop rows: ["buy", item] for the stock, then ["sell", item] for spare gear in the bag.
func _shop_rows() -> Array:
	var rows := []
	for k in Progress.shop_stock():
		rows.append(["buy", k])
	var spare := Progress.bag().keys()
	spare.sort()
	for k in spare:
		if Progress.sell_price(k) > 0:
			rows.append(["sell", k])
	return rows


func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if _tree != null or Engine.get_process_frames() == _tree_closed:
		return  # the skill tree has the controls (and the Esc that closed it is not ours)
	if Engine.get_process_frames() == opened_frame or _ids.is_empty():
		return
	var up := Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up")
	var down := Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down")
	var left := Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left")
	var right := Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right")
	var back := Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause")
	var d := TabStrip.pressed()
	if d != 0:
		var tabs := _tabs()
		_set_tab(tabs[posmod(tabs.find(tab) + d, tabs.size())])
		return
	if tab == "skills":
		if left:
			hero_i = posmod(hero_i - 1, _ids.size())
		elif right:
			hero_i = posmod(hero_i + 1, _ids.size())
		var nt := maxi(Skills.all_techs(_hero_id()).size(), 1)
		if up:
			tech_i = posmod(tech_i - 1, nt)
		elif down:
			tech_i = posmod(tech_i + 1, nt)
		if Input.is_action_just_pressed("ui_accept"):
			_pick_tech(tech_i)
		elif back or Input.is_action_just_pressed("gear"):
			close()
		return
	if tab == "shop":
		var n := _shop_rows().size()
		if n > 0:
			if up:
				shop_i = posmod(shop_i - 1, n)
			elif down:
				shop_i = posmod(shop_i + 1, n)
			shop_i = clampi(shop_i, 0, n - 1)
		if Input.is_action_just_pressed("ui_accept"):
			_shop_pick(shop_i)
		elif back or Input.is_action_just_pressed("gear"):
			close()
		return
	if picking:
		var n2 := _choices().size()
		if up:
			pick_i = posmod(pick_i - 1, n2)
		elif down:
			pick_i = posmod(pick_i + 1, n2)
		if Input.is_action_just_pressed("ui_accept"):
			_equip(pick_i)
		elif back:
			picking = false
		return
	if left:
		hero_i = posmod(hero_i - 1, _ids.size())
	elif right:
		hero_i = posmod(hero_i + 1, _ids.size())
	if up:
		slot_i = posmod(slot_i - 1, Progress.SLOTS.size())
	elif down:
		slot_i = posmod(slot_i + 1, Progress.SLOTS.size())
	if Input.is_action_just_pressed("ui_accept"):
		_start_pick()
	elif back or Input.is_action_just_pressed("gear"):
		close()


func _set_tab(t: String) -> void:
	if t == "tree":
		_open_tree()
		return
	tab = t
	picking = false


func _tabs() -> Array:
	return ["equip", "skills", "tree", "shop"] if _shop_open() else ["equip", "skills", "tree"]


## The Tree tab opens the skill tree screen (issue #25) on the hero picked here; closing it comes back.
func _open_tree() -> void:
	if _tree != null or _ids.is_empty():
		return
	picking = false
	_tree = SkillTreeView.new()
	add_child(_tree)
	_tree.party = party
	_tree.open(where, _hero_id())
	# The tree keeps this screen's tab row on top, so it reads as one of the tabs and Q / E carry on past it.
	_strip_update()
	_tree.tabs = _strip
	_tree.tab_picked.connect(func(i: int):
		var t: String = _tabs()[i]
		_tree.close()
		if t != "tree":
			_set_tab(t))
	_tree.closed.connect(func():
		var back := _tree.hero_id()
		_tree.queue_free()
		_tree = null
		_tree_closed = Engine.get_process_frames()
		if back in _ids:
			hero_i = _ids.find(back))


## Skills tab: Enter on a known tech makes it the one this hero always charges; on the picked one,
## back to choosing by hold length (scripts/skills.gd).
func _pick_tech(i: int) -> void:
	var id := _hero_id()
	var all := Skills.all_techs(id)
	if i < 0 or i >= all.size():
		return
	var t: Dictionary = all[i]
	if int(t.get("level", 1)) > Skills.weapon_level(id):
		_say(tr("%s learns %s at %s level %d.") % [PartyPicker.short_of(id), t.get("name", "?"), Skills.weapon_name(id), int(t.get("level", 1))])
		return
	if Skills.pick(id) == t["id"]:
		Skills.set_pick(id, "")
		_say(tr("%s chooses by hold length again.") % PartyPicker.short_of(id))
	else:
		Skills.set_pick(id, str(t["id"]))
		_say(tr("%s will always charge %s.") % [PartyPicker.short_of(id), t.get("name", "?")])


func _say(s: String) -> void:
	flash = s
	flash_t = 2.8


func _start_pick() -> void:
	picking = true
	pick_i = 0
	var cur := str(Progress.gear(_hero_id()).get(_slot(), ""))
	var ch := _choices()
	# Start on the first spare piece, if there is one; else on "take it off".
	pick_i = 1 if ch.size() > 1 else 0
	if ch.size() <= 1 and cur == "":
		picking = false
		_say(tr("No spare %s for %s. The shop%s or missions have more.") % [Loc.t(Progress.SLOT_NAMES[_slot()]).to_lower(), PartyPicker.short_of(_hero_id()), Prompts.tag("swap")])


func _equip(i: int) -> void:
	var id := _hero_id()
	var ch := _choices()
	if i < 0 or i >= ch.size():
		return
	var item_id: String = ch[i]
	var cur := str(Progress.gear(id).get(_slot(), ""))
	if item_id == "" and cur == "":
		picking = false
		return
	var before := Progress.bonus(id)
	if not Progress.equip(id, _slot(), item_id):
		_say(tr("Can't: %s.") % Progress.wear_blocker(id, item_id))
		return
	_apply_live(id, before)
	picking = false
	if item_id == "":
		_say(tr("%s took off the %s.") % [PartyPicker.short_of(id), Progress.item(cur)["name"]])
	else:
		_say(tr("%s now uses the %s.") % [PartyPicker.short_of(id), Progress.item(item_id)["name"]])


## On a mission, the hero standing in the field changes too.
func _apply_live(id: String, before: Dictionary) -> void:
	if party == null:
		return
	for h in party.heroes:
		if (h as Hero).hero_id == id:
			Progress.apply_delta(h, before, Progress.bonus(id))


func _shop_pick(i: int) -> void:
	var rows := _shop_rows()
	if i < 0 or i >= rows.size():
		return
	var kind: String = rows[i][0]
	var k: String = rows[i][1]
	var it := Progress.item(k)
	if kind == "buy":
		var why := Progress.shop_blocker(k)
		if why != "":
			_say(tr("Can't: %s.") % why)
			return
		Progress.buy(k)
		_say(tr("Bought the %s for %d Gilt. It's in the bag: equip it on the Equip tab.") % [it["name"], int(it["price"])])
	else:
		var price := Progress.sell_price(k)
		Progress.sell(k)
		_say(tr("Sold the %s for %d Gilt.") % [it["name"], price])
		shop_i = clampi(shop_i, 0, maxi(_shop_rows().size() - 1, 0))


func _gui_input(event: InputEvent) -> void:
	if _tree != null:
		return
	if Prompts.tapped(event):
		var p: Vector2 = event.position
		if _close_rect().has_point(p):
			close()
			return
		var ti := _strip.hit(p)
		if ti >= 0:
			_set_tab(_tabs()[ti])
			return
		for i in _hero_rects.size():
			if tab == "skills" and (_hero_rects[i] as Rect2).has_point(p):
				hero_i = i
				return
		if tab == "skills":
			for i in _tech_rects.size():
				if (_tech_rects[i] as Rect2).has_point(p):
					if tech_i == i:
						_pick_tech(i)
					tech_i = i
					return
			return
		if tab == "shop":
			for i in _shop_rects.size():
				if (_shop_rects[i] as Rect2).has_point(p):
					if shop_i == i:
						_shop_pick(i)
					shop_i = i
					return
			return
		for i in _hero_rects.size():
			if (_hero_rects[i] as Rect2).has_point(p):
				hero_i = i
				picking = false
				return
		if picking:
			for i in _pick_rects.size():
				if (_pick_rects[i] as Rect2).has_point(p):
					if pick_i == i:
						_equip(i)
					pick_i = i
					return
		for i in _slot_rects.size():
			if (_slot_rects[i] as Rect2).has_point(p):
				if slot_i == i and not picking:
					_start_pick()
				else:
					slot_i = i
					picking = false
				return
		picking = false


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _text_r(right: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	_text(right - Vector2(w, 0), s, fsize, col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _bar(r: Rect2, f: float, col: Color) -> void:
	draw_rect(r, Color(0.14, 0.12, 0.16))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(f, 0.0, 1.0), r.size.y)), col)


func _box(r: Rect2, on: bool) -> void:
	draw_rect(r, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
	if on:
		draw_rect(r, GOLD, false, 1.0)


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	_text(Vector2(8, 20), tr("Party gear"), 15, PAPER)
	_strip_update()
	var tx := _strip.draw(self, font, Vector2(100, 7), 9)
	_text(Vector2(tx + 10, 19), tr("Gilt: %d") % int(Empire.res.get("gilt", 0)), 9, GOLD)
	_hero_rects.clear()
	_slot_rects.clear()
	_pick_rects.clear()
	_shop_rects.clear()
	_tech_rects.clear()
	if _ids.is_empty():
		_text(Vector2(8, 50), tr("No field heroes on the roster."), 10, BAD)
		return
	if tab == "skills":
		_draw_skills(vs)
		_text(Vector2(8, vs.y - 8), Prompts.help([["leftright", "hero"], ["updown", "tech"], ["ui_accept", tr("always charge it")], [["ui_cancel", "gear"], "close"]], tr("Tap a hero, tap a tech twice to always charge it")), 7, Color(0.5, 0.48, 0.52))
	elif tab == "equip":
		_draw_equip(vs)
		var help := Prompts.help([["leftright", "hero"], ["updown", "slot"], ["ui_accept", "change"], [["ui_cancel", "gear"], "close"]], tr("Tap a hero, tap a slot twice to change it"))
		if picking:
			help = Prompts.help([["updown", "choose"], ["ui_accept", tr("put it on")], ["ui_cancel", "back"]], tr("Tap gear twice to put it on"))
		_text(Vector2(8, vs.y - 8), help, 7, Color(0.5, 0.48, 0.52))
	else:
		_draw_shop(vs)
		_text(Vector2(8, vs.y - 8), Prompts.help([["updown", "choose"], ["ui_accept", tr("buy / sell")], [["ui_cancel", "gear"], "close"]], tr("Tap an item twice to buy or sell")), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var fw := font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		draw_rect(Rect2(vs.x - fw - 18, vs.y - 21, fw + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - fw - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a))


## The tab row's labels and the tab on show.
func _strip_update() -> void:
	var labels := []
	for t in _tabs():
		labels.append({"equip": tr("Equip"), "skills": tr("Skills"), "tree": _tree_label()}.get(t, Progress.data().get("shop_name", tr("Shop"))))
	_strip.labels = labels
	_strip.current = maxi(_tabs().find("tree" if _tree != null else tab), 0)  # the tree is open over this screen


## "Tree", or "Tree (2)" when that many heroes have a node they could learn right now.
func _tree_label() -> String:
	var n := SkillTree.unspent_ids().filter(func(id): return id in _ids).size()
	return tr("Tree (%d)") % n if n > 0 else tr("Tree")


func _draw_equip(vs: Vector2) -> void:
	_draw_chips(vs)
	_draw_equip_body(vs)


## Hero chips across the top (both the Equip and the Skills tab).
func _draw_chips(vs: Vector2) -> void:
	var x := 8.0
	var cw := minf(96.0, (vs.x - 16.0 - 4.0 * (_ids.size() - 1)) / _ids.size())
	for i in _ids.size():
		var id: String = _ids[i]
		var r := Rect2(x, 30, cw, 24)
		_hero_rects.append(r)
		_box(r, i == hero_i)
		_text(r.position + Vector2(5, 10), PartyPicker.short_of(id), 9, GOLD if i == hero_i else TEXT, cw - 30)
		_text_r(r.position + Vector2(cw - 4, 10), tr("Lv%d") % Progress.level(id), 8, SOFT)
		_bar(Rect2(r.position + Vector2(5, 15), Vector2(cw - 10, 3)), Progress.xp_fraction(id), XP_COL)
		if Empire.role_of(id) == "party":
			draw_circle(r.position + Vector2(cw - 5, 19), 1.5, GOOD)
		x += cw + 4


func _draw_equip_body(vs: Vector2) -> void:
	var id := _hero_id()
	var hd := PartyPicker.hero_data(id)
	var left := Rect2(8, 62, 300, vs.y - 62 - 18)
	UiSkin.panel(self, left, "ledger")
	var y := left.position.y + 16
	_text(Vector2(16, y), Empire.recruit(id).get("name", PartyPicker.short_of(id)), 12, PAPER, 200)
	_text_r(Vector2(left.end.x - 8, y), tr("Level %d") % Progress.level(id), 10, GOLD)
	y += 12
	var need := Progress.xp_to_next(Progress.level(id))
	var xp_line := tr("Max level") if need <= 0 else tr("XP %d / %d to level %d") % [int(Progress.hero(id)["xp"]), need, Progress.level(id) + 1]
	_text(Vector2(16, y), xp_line, 8, XP_COL)
	var where_line := tr("In the party") if Empire.role_of(id) == "party" else tr("On the bench")
	if Empire.role_of(id) != "party" and Empire.level_of("barracks") > 0:
		where_line += tr(": Barracks drill, +%d XP a day") % Progress.barracks_xp()
	_text_r(Vector2(left.end.x - 8, y), where_line, 8, SOFT)
	y += 4
	_bar(Rect2(16, y, left.size.x - 16, 3), Progress.xp_fraction(id), XP_COL)
	y += 14

	# Stats, with a preview of the highlighted pick
	var now := Progress.stats(id)
	var preview := {}
	if picking:
		var ch := _choices()
		if pick_i < ch.size():
			preview = Progress.stats(id, {_slot(): ch[pick_i]})
	var rows := ["hp", "damage", "power_rate", "speed", "reach", "guard", "ink"]
	if int(now.get("heal", 0)) > 0:
		rows.append("heal")
	var col_w := (left.size.x - 16) / 2.0
	for j in rows.size():
		var k: String = rows[j]
		var sx := 16.0 + (j % 2) * col_w
		var sy := y + (j / 2) * 12.0
		_text(Vector2(sx, sy), Loc.t(Progress.STAT_NAMES[k]), 8, SOFT)
		var val := _stat_shown(k, now[k])
		_text_r(Vector2(sx + col_w - 44, sy), val, 9, TEXT)
		if not preview.is_empty():
			var diff := float(preview[k]) - float(now[k])
			if absf(diff) > 0.001:
				var pv := _stat_shown(k, preview[k])
				_text(Vector2(sx + col_w - 40, sy), "> " + pv, 9, GOOD if diff > 0 else BAD)
	y += ceili(rows.size() / 2.0) * 12.0 + 2
	_text(Vector2(16, y), "%s. %s" % [hd.get("weapon", ""), hd.get("special", "")], 7, DIM, left.size.x - 16)
	y += 8

	# Slots
	var g := Progress.gear(id)
	for i in Progress.SLOTS.size():
		var s: String = Progress.SLOTS[i]
		var r := Rect2(16, y, left.size.x - 16, 26)
		_slot_rects.append(r)
		_box(r, i == slot_i)
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), SLOT_COLORS[s])
		var iid := str(g.get(s, ""))
		var ix := 8.0  # text starts after the item's icon, when it has one
		if iid != "" and UiSkin.draw_icon(self, iid, Rect2(r.position + Vector2(7, 3), Vector2(20, 20))):
			ix = 31.0
		_text(r.position + Vector2(ix, 10), Loc.t(Progress.SLOT_NAMES[s]).to_upper(), 7, SLOT_COLORS[s])
		if iid == "":
			_text(r.position + Vector2(8, 21), tr("(nothing)"), 9, DIM)
		else:
			_text(r.position + Vector2(ix, 21), Progress.item(iid)["name"], 9, GOLD if i == slot_i else TEXT, 128 - ix)
			_text(r.position + Vector2(130, 21), Progress.item_text(iid), 8, GOOD if Progress.item(iid).get("stats", {}).size() > 0 else DIM, r.size.x - 134)
		var spare := Progress.options(id, s).size()
		if spare > 0:
			_text_r(r.position + Vector2(r.size.x - 6, 10), tr("%d spare") % spare, 7, GOOD)
		y += 30

	# Right side: the pick list, or about the highlighted slot
	var rx := 320.0
	var rw := vs.x - rx - 8
	var right := Rect2(rx, 62, rw, vs.y - 62 - 18)
	UiSkin.panel(self, right, "ledger")
	var ry := right.position.y + 16
	if picking:
		_text(Vector2(rx + 8, ry), tr("%s for %s") % [Loc.t(Progress.SLOT_NAMES[_slot()]), PartyPicker.short_of(id)], 10, PAPER)
		ry += 8
		var ch := _choices()
		for i in ch.size():
			var r := Rect2(rx + 6, ry, rw - 12, 22)
			_pick_rects.append(r)
			_box(r, i == pick_i)
			var k: String = ch[i]
			if k == "":
				_text(r.position + Vector2(6, 14), tr("Take it off") if str(g.get(_slot(), "")) != "" else tr("(leave empty)"), 9, SOFT)
			else:
				var px := 26.0 if UiSkin.draw_icon(self, k, Rect2(r.position + Vector2(5, 3), Vector2(16, 16))) else 6.0
				_text(r.position + Vector2(px, 9), Progress.item(k)["name"], 9, GOLD if i == pick_i else TEXT)
				_text_r(r.position + Vector2(r.size.x - 6, 9), "x%d" % Progress.count(k), 8, SOFT)
				_text(r.position + Vector2(px, 19), Progress.item_text(k), 7, GOOD)
			ry += 24
		if pick_i < ch.size() and ch[pick_i] != "":
			_wrap(Vector2(rx + 8, ry + 10), Progress.item(ch[pick_i]).get("blurb", ""), rw - 16, 8, Color(0.78, 0.76, 0.74))
	else:
		var iid := str(g.get(_slot(), ""))
		_text(Vector2(rx + 8, ry), Loc.t(Progress.SLOT_NAMES[_slot()]), 10, SLOT_COLORS[_slot()])
		ry += 14
		if iid == "":
			_text(Vector2(rx + 8, ry), tr("Nothing worn."), 9, DIM)
		else:
			UiSkin.draw_icon(self, iid, Rect2(rx + rw - 42, ry - 26, 32, 32))
			_text(Vector2(rx + 8, ry), Progress.item(iid)["name"], 11, PAPER)
			ry += 12
			_text(Vector2(rx + 8, ry), Progress.item_text(iid), 8, GOOD, rw - 16)
			ry += 4
			ry += _wrap(Vector2(rx + 8, ry + 8), Progress.item(iid).get("blurb", ""), rw - 16, 8, Color(0.78, 0.76, 0.74))
		ry += 18
		var spare := Progress.options(id, _slot()).size()
		_text(Vector2(rx + 8, ry), (tr("%s to swap: %d spare that fit.") % [Prompts.confirm(), spare]) if spare > 0 else
			(Prompts.confirm() + tr(" to take it off.") if iid != "" else tr("No spare gear for this slot.")), 8, GOLD if spare > 0 else SOFT, rw - 16)
		ry += 18
		_text(Vector2(rx + 8, ry), tr("Levels"), 8, Color(0.75, 0.72, 0.7))
		ry += 2
		var gr := Progress.growth(id)
		var parts := []
		for k in Progress.STAT_ORDER:
			if gr.has(k) and float(gr[k]) > 0.0:
				var v := float(gr[k])
				parts.append(("+%d %s" % [int(v), Loc.t(Progress.STAT_NAMES[k])]) if v >= 1.0 else (tr("+1 %s every %d levels") % [Loc.t(Progress.STAT_NAMES[k]), int(round(1.0 / v))]))
		ry += _wrap(Vector2(rx + 8, ry + 9), tr("Each level: ") + ", ".join(parts) + tr(". XP comes from every enemy the party drops, shared by all three, plus a bonus for finishing the job. On missions the Barracks and research add their bonuses on top of these numbers."), rw - 16, 8, SOFT)


func _stat_shown(k: String, v) -> String:
	match k:
		"power_rate":
			return "%d%%" % int(round(float(v) * 100.0))
		"guard":
			return "%d%%" % int(round(float(v) * 100.0))
		_:
			return str(int(round(float(v))))


func _draw_shop(vs: Vector2) -> void:
	var d := Progress.data()
	_text(Vector2(8, 42), d.get("shop_blurb", ""), 8, SOFT, vs.x - 16)
	var rows := _shop_rows()
	var y := 52.0
	var lw := 330.0
	var last := ""
	var row_h := 14.0
	for i in rows.size():
		var kind: String = rows[i][0]
		var k: String = rows[i][1]
		var it := Progress.item(k)
		var head: String = Loc.t(Progress.SLOT_NAMES.get(it["slot"], "")) if kind == "buy" else tr("sell")
		if head != last:
			last = head
			y += 10
			_text(Vector2(10, y - 2), (tr("SELL SPARE GEAR (half price)") if kind == "sell" else head.to_upper() + "S"), 7,
				SOFT if kind == "sell" else SLOT_COLORS.get(it["slot"], TEXT))
		var r := Rect2(8, y, lw, row_h - 2)
		_shop_rects.append(r)
		var on := i == shop_i
		_box(r, on)
		var why := Progress.shop_blocker(k) if kind == "buy" else ""
		var locked := why.begins_with("needs")
		var col := DIM if locked else (GOLD if on else TEXT)
		var nx := 20.0 if UiSkin.draw_icon(self, k, Rect2(r.position + Vector2(5, 0), Vector2(12, 12)), Color(1, 1, 1, 0.45) if locked else Color.WHITE) else 6.0
		_text(r.position + Vector2(nx, 9), it["name"], 8, col, 116 - nx)
		var owner := str(it.get("hero", ""))
		_text(r.position + Vector2(118, 9), PartyPicker.short_of(owner) if owner != "" else Loc.t("anyone"), 7, DIM if locked else SOFT, 50)
		_text(r.position + Vector2(170, 9), Progress.item_text(k), 7, DIM if locked else GOOD, 110)
		if kind == "buy":
			var have := Progress.count(k) + Progress.worn_by(k).size()
			if have > 0:
				_text_r(r.position + Vector2(lw - 46, 9), tr("have %d") % have, 7, SOFT)
			_text_r(r.position + Vector2(lw - 6, 9), "%d G" % int(it["price"]), 8, DIM if locked else (GOLD if why == "" else BAD))
		else:
			_text_r(r.position + Vector2(lw - 46, 9), "x%d" % Progress.count(k), 7, SOFT)
			_text_r(r.position + Vector2(lw - 6, 9), "+%d G" % Progress.sell_price(k), 8, GOOD)
		y += row_h
	if rows.is_empty():
		return
	shop_i = clampi(shop_i, 0, rows.size() - 1)
	var kind2: String = rows[shop_i][0]
	var k2: String = rows[shop_i][1]
	var it2 := Progress.item(k2)
	var rx := lw + 18
	var rw := vs.x - rx - 8
	draw_rect(Rect2(rx, 52, rw, vs.y - 52 - 18), Color(0.08, 0.07, 0.1))
	var ry := 68.0
	UiSkin.draw_icon(self, k2, Rect2(rx + rw - 42, 58, 32, 32))
	_text(Vector2(rx + 8, ry), it2["name"], 11, PAPER, rw - 50)
	ry += 12
	var owner2 := str(it2.get("hero", ""))
	_text(Vector2(rx + 8, ry), "%s, %s" % [Loc.t(Progress.SLOT_NAMES[it2["slot"]]), (tr("for ") + PartyPicker.short_of(owner2)) if owner2 != "" else tr("anyone can wear it")], 8, SLOT_COLORS.get(it2["slot"], TEXT))
	ry += 12
	_text(Vector2(rx + 8, ry), Progress.item_text(k2), 8, GOOD, rw - 16)
	ry += 4
	ry += _wrap(Vector2(rx + 8, ry + 8), it2.get("blurb", ""), rw - 16, 8, Color(0.78, 0.76, 0.74)) + 6
	# Compared with what each hero who could wear it has on now
	var who := _ids.filter(func(id): return Progress.wear_blocker(id, k2) == "")
	if not who.is_empty():
		_text(Vector2(rx + 8, ry + 8), tr("Compared with what they wear now"), 8, Color(0.75, 0.72, 0.7))
		ry += 10
		for id in who:
			var now := Progress.stats(id)
			var then := Progress.stats(id, {it2["slot"]: k2})
			var parts := []
			for k in ["hp", "damage", "power_rate", "speed", "reach", "guard", "ink", "heal"]:
				var diff := float(then[k]) - float(now[k])
				if absf(diff) > 0.001:
					parts.append("%s%s %s" % ["+" if diff > 0 else "-", _stat_shown(k, absf(diff)).trim_prefix("+"), Loc.t(Progress.STAT_NAMES[k])])
			ry += 10
			var cur := str(Progress.gear(id).get(it2["slot"], ""))
			var line := "%s: %s" % [PartyPicker.short_of(id), ", ".join(parts) if not parts.is_empty() else tr("same as now")]
			_text(Vector2(rx + 8, ry + 2), line, 8, TEXT if cur != k2 else SOFT, rw - 16)
	ry += 20
	if kind2 == "buy":
		var why2 := Progress.shop_blocker(k2)
		_text(Vector2(rx + 8, ry), (tr("%s to buy for %d Gilt.") % [Prompts.confirm(), int(it2["price"])]) if why2 == "" else (tr("Can't buy: %s.") % why2), 8, GOLD if why2 == "" else BAD, rw - 16)
	else:
		_text(Vector2(rx + 8, ry), tr("%s to sell one for %d Gilt.") % [Prompts.confirm(), Progress.sell_price(k2)], 8, GOLD, rw - 16)


# ---------------------------------------------------------------- skills tab (issue #24)

func _draw_skills(vs: Vector2) -> void:
	_draw_chips(vs)
	var id := _hero_id()
	var techs := Skills.all_techs(id)
	tech_i = clampi(tech_i, 0, maxi(techs.size() - 1, 0))
	var wl := Skills.weapon_level(id)
	var left := Rect2(8, 62, 300, vs.y - 62 - 18)
	UiSkin.panel(self, left, "ledger")
	var y := left.position.y + 16
	_text(Vector2(16, y), tr("%s skill") % Skills.weapon_name(id), 12, PAPER, 200)
	_text_r(Vector2(left.end.x - 8, y), tr("Level %d / %d") % [wl, Skills.max_level()], 10, GOLD)
	y += 12
	var need := Skills.weapon_to_next(wl)
	_text(Vector2(16, y), tr("Mastered") if need <= 0 else tr("%d / %d to level %d") % [int(Skills.weapon(id).get("xp", 0)), need, wl + 1], 8, XP_COL)
	var drill := ""
	if Empire.role_of(id) != "party" and Empire.level_of("barracks") > 0:
		drill = (tr("Barracks drill +%d a day") % Skills.barracks_points()) if wl < Skills.barracks_cap() else tr("Drilled as far as the Barracks can")
	_text_r(Vector2(left.end.x - 8, y), drill, 8, SOFT)
	y += 4
	_bar(Rect2(16, y, left.size.x - 16, 3), Skills.weapon_fraction(id), XP_COL)
	y += 8
	var sk: Dictionary = Progress.data().get("skills", {})
	y += _wrap(Vector2(16, y + 8), tr("Landed full-power swings +%d, techs that land +%d. Each level teaches a tech; hold Attack longer on a full gauge to reach the later ones.") % [int(sk.get("swing", 2)), int(sk.get("tech", 4))], left.size.x - 20, 7, DIM) + 4
	var picked := Skills.pick(id)
	for i in techs.size():
		var t: Dictionary = techs[i]
		var lvl := int(t.get("level", i + 1))
		var known := lvl <= wl
		var r := Rect2(16, y, left.size.x - 16, 22)
		_tech_rects.append(r)
		_box(r, i == tech_i)
		var col := Color(str(t.get("color", "ffffff")))
		draw_rect(Rect2(r.position, Vector2(3, r.size.y)), col if known else DIM)
		_text(r.position + Vector2(8, 9), str(t.get("name", "?")), 9, (GOLD if i == tech_i else TEXT) if known else DIM, 150)
		_text(r.position + Vector2(8, 19), (tr("Ready after %s s") % Loc.dec(Techs.charge_time(t))) if known else tr("Learned at level %d") % lvl, 7, SOFT if known else DIM)
		var tag := tr("ALWAYS") if picked == t["id"] else (tr("LV %d") % lvl)
		_text_r(r.position + Vector2(r.size.x - 6, 9), tag, 7, GOOD if picked == t["id"] else (col.lightened(0.2) if known else DIM))
		y += 25
	_text(Vector2(16, y + 6), tr("Charging: ") + (tr("always %s") % Techs.find(picked).get("name", "?") if picked != "" else tr("by hold length")), 8, GOLD)

	# Right: the highlighted tech, then the Ink colours.
	var rx := 320.0
	var rw := vs.x - rx - 8
	var right := Rect2(rx, 62, rw, vs.y - 62 - 18)
	UiSkin.panel(self, right, "ledger")
	var ry := right.position.y + 16
	if not techs.is_empty():
		var t2: Dictionary = techs[tech_i]
		var known2 := int(t2.get("level", 1)) <= wl
		var col2 := Color(str(t2.get("color", "ffffff")))
		_text(Vector2(rx + 8, ry), str(t2.get("name", "?")), 11, col2.lightened(0.3) if known2 else SOFT)
		_text_r(Vector2(right.end.x - 8, ry), (tr("Known") if known2 else tr("Level %d") % int(t2.get("level", 1))), 8, GOOD if known2 else SOFT)
		ry += 11
		_text(Vector2(rx + 8, ry), tech_facts(t2), 7, GOLD, rw - 16)
		ry += _wrap(Vector2(rx + 8, ry + 9), str(t2.get("desc", "")), rw - 16, 8, Color(0.82, 0.8, 0.76) if known2 else SOFT) + 10
	draw_rect(Rect2(rx + 8, ry, rw - 16, 1), Color(0.63, 0.48, 0.31, 0.6))
	ry += 12
	_text(Vector2(rx + 8, ry), tr("Ink colours"), 10, PAPER)
	_text_r(Vector2(right.end.x - 8, ry), tr("spend Ink on a colour to train it"), 7, DIM)
	ry += 6
	var used := Skills.colors_of(id)
	var abil := Abilities.for_ids(PartyPicker.hero_data(id).get("abilities", []), id)
	for c in Skills.INKS:
		var lv := Skills.ink_level(id, c)
		var on: bool = c in used
		var cc := Skills.ink_color(c)
		draw_rect(Rect2(rx + 8, ry + 3, 6, 6), cc if on else Color(cc, 0.35))
		_text(Vector2(rx + 18, ry + 9), Skills.ink_name(c), 8, TEXT if on else DIM)
		_text(Vector2(rx + 52, ry + 9), tr("Lv %d") % lv, 8, GOLD if on else DIM)
		_bar(Rect2(rx + 76, ry + 5, 46, 2), Skills.ink_fraction(id, c), cc if on else Color(cc, 0.3))
		var mine := abil.filter(func(a): return str(a.get("ink", "")) == c)
		var line := ", ".join(mine.map(func(a): return tr("%s (tier %d)") % [a.get("name", "?"), int(a.get("tier", 1))])) if on else str(Skills.ink_info(c).get("desc", ""))
		_text(Vector2(rx + 128, ry + 9), line, 7, TEXT if on else DIM, rw - 136)
		ry += 12
		if on:
			for a in mine:
				var nxt := Abilities.next_tier_text(a)
				var cut := Skills.cooldown_cut(lv)
				var bits := []
				if cut > 0.0:
					bits.append(tr("cooldown -%d%%") % int(round(cut * 100.0)))
				if nxt != "":
					bits.append(tr("next ") + nxt)
				if not bits.is_empty():
					_text(Vector2(rx + 128, ry + 6), "%s: %s" % [a.get("name", "?"), "; ".join(bits)], 7, SOFT, rw - 136)
					ry += 9
	ry += 4
	_wrap(Vector2(rx + 8, ry + 8), tr("Every colour: tier 2 abilities at level 2, tier 3 at level 4; shorter cooldowns at 3 and 5."), rw - 16, 7, DIM)


## One line of hard numbers for a tech: "x2.4 damage, all round, 3 hits, stuns 1 s".
static func tech_facts(t: Dictionary) -> String:
	var parts := []
	if float(t.get("mult", 0)) > 0.0:
		parts.append(Loc.t("x%s damage") % _n(t["mult"]))
	var k: Dictionary = t.get("knives", {})
	if not k.is_empty():
		parts.append(Loc.t("%d knives x%s") % [int(k.get("count", 1)), _n(k.get("mult", 1))])
	if float(t.get("mult", 0)) > 0.0:
		parts.append(Loc.t("all round") if float(t.get("arc", 90)) >= 179.0 else (Loc.t("a line") if float(t.get("arc", 90)) <= 12.0 else Loc.t("in front")))
	if int(t.get("hits", 1)) > 1:
		parts.append(Loc.t("%d hits") % int(t["hits"]))
	if int(t.get("chain", 1)) > 1:
		parts.append(Loc.t("%d in a row") % int(t["chain"]))
	if (t.get("spread", []) as Array).size() > 1:
		parts.append(Loc.t("%d lines") % (t["spread"] as Array).size())
	if float(t.get("knock", 0)) < 0.0:
		parts.append(Loc.t("pulls in"))
	var stun := maxf(float(t.get("stun", 0)), float(t.get("last", {}).get("stun", 0)))
	if stun > 0.0:
		parts.append(Loc.t("stuns %s s") % _n(stun))
	if float(t.get("mark", 0)) > 0.0:
		parts.append(Loc.t("Audits %s s") % _n(t["mark"]))
	if float(t.get("delay", 0)) > 0.0:
		parts.append(Loc.t("goes off after %s s") % _n(t["delay"]))
	if int(t.get("heal", 0)) > 0:
		parts.append(Loc.t("heals %d") % int(t["heal"]))
	return ", ".join(parts)


static func _n(x) -> String:
	var f := float(x)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.1))
