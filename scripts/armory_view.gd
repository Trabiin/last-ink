class_name ArmoryView
extends Control
## Forge & Market screen (issue #112). Opened with M in town and on the Command Table, from the menus,
## and by walking up to the Forge or the Market in Hollowmark.
##
## Tabs: Forge (weapon upgrades, armour, trinkets, field supplies and satchel upgrades, and what is on
## the benches), Market (the rotating stalls, and selling spare materials), Satchel (what goes out on
## every mission, the town stores behind it, and Tobble's supplies cart), Materials (what you have,
## where it comes from and what it makes). Up/Down choose, Enter acts, Left/Right change how many of
## an item is packed, Tab switches tabs, Esc or M closes. Mouse and touch: tap a row, tap again to act.

signal closed

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const PAPER := Color("f3efe4")
const MAT_COL := Color("c8d8a8")
const TABS := ["forge", "market", "satchel", "materials"]
const TAB_NAMES := {"forge": "Forge", "market": "Market", "satchel": "Satchel", "materials": "Materials"}
const SLOT_COLORS := {"weapon": Color("e89a8a"), "armor": Color("8fa7e8"), "trinket": Color("e8c66a"), "item": Color("9fd18b"), "upgrade": Color("c9a0e8")}
const ROW_H := 14.0
const LIST_W := 318.0

var tab := "forge"
var sel := 0
var scroll := 0
var closed_frame := -1
var opened_frame := -1
var flash := ""
var flash_t := 0.0
var font: Font
var rows: Array = []
var _row_rects: Array = []  # [rect, row index]
var _tab_rects := {}
var _minus_rects := {}  # row index -> rect (Satchel tab)
var _plus_rects := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font


func open(at := "") -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	opened_frame = Engine.get_process_frames()
	if at in TABS:
		tab = at
	elif Armory.forge_level() <= 0 and Armory.market_level() > 0:
		tab = "market"
	sel = 0
	scroll = 0
	Armory.restock(false)  # anything bought or found since is packed
	_rebuild()


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func _say(s: String) -> void:
	flash = s
	flash_t = 3.0


# ---------------------------------------------------------------- rows

## Rows: {"head": text} for section headings, else a selectable row with "kind" and its data.
func _rebuild() -> void:
	rows = []
	match tab:
		"forge":
			_forge_rows()
		"market":
			_market_rows()
		"satchel":
			_satchel_rows()
		"materials":
			for k in Armory.materials():
				rows.append({"kind": "mat", "id": k})
	sel = clampi(sel, 0, maxi(rows.size() - 1, 0))
	if not rows.is_empty() and rows[sel].has("head"):
		_move(1)


func _forge_rows() -> void:
	var jobs := Armory.jobs()
	if not jobs.is_empty():
		rows.append({"head": tr("On the benches")})
		for j in jobs:
			rows.append({"kind": "job", "job": j})
	rows.append({"head": tr("Weapons: upgrade to the next tier")})
	for hero in Progress.field_ids():
		var now := Armory.weapon_now(hero)
		var r := Armory.upgrade_recipe(now) if now != "" else {}
		rows.append({"kind": "weapon", "hero": hero, "recipe": r})
	var groups := {"armor": [], "trinket": [], "item": [], "upgrade": []}
	for k in Armory.forge_data().get("recipes", {}):
		var r := Armory.recipe(k)
		var g: String = Progress.item(k).get("slot", "") if r["kind"] == "gear" else r["kind"]
		if groups.has(g):
			groups[g].append(r)
	for g in ["armor", "trinket", "item", "upgrade"]:
		rows.append({"head": {"armor": tr("Armour"), "trinket": tr("Trinkets"), "item": tr("Field supplies"), "upgrade": tr("Satchel")}[g]})
		var list: Array = groups[g]
		list.sort_custom(func(a, b): return int(a["tier"]) < int(b["tier"]) if int(a["tier"]) != int(b["tier"]) else int(a["gilt"]) < int(b["gilt"]))
		for r in list:
			rows.append({"kind": "recipe", "recipe": r})


func _market_rows() -> void:
	var stock := Armory.stock()
	if not stock.is_empty():
		rows.append({"head": tr("Stalls  (new stock in %d day%s)") % [Armory.days_to_rotation(), "" if Armory.days_to_rotation() == 1 else "s"]})
		for i in stock.size():
			rows.append({"kind": "stall", "i": i, "stall": stock[i]})
	var have := Armory.materials().keys().filter(func(k): return Armory.mat_count(k) > 0)
	if not have.is_empty() and not stock.is_empty():
		rows.append({"head": tr("Sell spare materials")})
		for k in have:
			rows.append({"kind": "sell", "id": k})


func _satchel_rows() -> void:
	rows.append({"head": tr("Packed for every mission")})
	for id in Satchel.ids():
		rows.append({"kind": "pack", "id": id})


func _move(step: int) -> void:
	if rows.is_empty():
		return
	for n in rows.size():
		sel = posmod(sel + step, rows.size())
		if not rows[sel].has("head"):
			return


# ---------------------------------------------------------------- acting

func _act(i: int) -> void:
	if i < 0 or i >= rows.size() or rows[i].has("head"):
		return
	var row: Dictionary = rows[i]
	match str(row["kind"]):
		"weapon", "recipe":
			var r: Dictionary = row["recipe"]
			if r.is_empty():
				_say(tr("%s's weapon is as good as it gets.") % PartyPicker.short_of(row.get("hero", "")))
				return
			var why := Armory.craft_blocker(r)
			if why != "":
				_say(tr("Can't: %s.") % why)
				Audio.sfx("error")
				return
			var days := Armory.days_for(r)
			Armory.start(r)
			Audio.sfx("heavy", 1.2, -4.0)
			_say(tr("The smiths start on the %s. Ready %s.") % [Armory.result_name(r["result"]), tr("at dawn") if days <= 1 else tr("in %d days") % days])
		"job":
			var j: Dictionary = row["job"]
			_say(tr("%s: ready %s.") % [Armory.result_name(j["result"]), Armory.job_eta(j)])
		"stall":
			var st: Dictionary = row["stall"]
			var why2 := Armory.buy_blocker(int(row["i"]), st)
			if why2 != "":
				_say(tr("Can't: %s.") % why2)
				Audio.sfx("error")
				return
			var p := Armory.price(st["kind"], st["id"])
			Armory.buy(int(row["i"]), st)
			Audio.sfx("coin")
			var where: String = {"items": tr("the stores (packed if there's room)"), "materials": tr("the stores"), "gear": tr("the bag: equip it with K")}[st["kind"]]
			_say(tr("Bought %s for %d Gilt. It goes to %s.") % [Armory.stock_name(st["kind"], st["id"]), p, where])
		"sell":
			var k: String = row["id"]
			var gp := Armory.sell_price_mat(k)
			if Armory.sell_mat(k):
				Audio.sfx("coin")
				_say(tr("Sold a %s for %d Gilt.") % [Armory.mat_name(k), gp])
		"pack":
			_buy_from_tobble(str(row["id"]))
		"mat":
			var uses := Armory.uses(str(row["id"]))
			_say(tr("%s goes into %d recipe%s at the Forge.") % [Armory.mat_name(row["id"]), uses.size(), "" if uses.size() == 1 else "s"])
	_rebuild()


func _buy_from_tobble(id: String) -> void:
	var it := Satchel.item(id)
	if not it.get("stall", false):
		_say(tr("Tobble doesn't carry %s. Try the Market or the Forge.") % it.get("name", id))
		return
	var p := int(it.get("price", 10))
	if int(Empire.res.get("gilt", 0)) < p:
		_say(tr("Can't: not enough Gilt."))
		Audio.sfx("error")
		return
	Empire.res["gilt"] = int(Empire.res["gilt"]) - p
	Armory.store(id)
	Armory.restock(false)
	Audio.sfx("coin")
	_say(tr("Bought %s from Tobble for %d Gilt. It's in the stores%s.") % [it.get("name", id), p, tr(" and packed") if Satchel.count(id) >= Armory.pack_of(id) and Armory.pack_of(id) > 0 else ""])


func _pack_step(i: int, step: int) -> void:
	if i < 0 or i >= rows.size() or rows[i].get("kind", "") != "pack":
		return
	var id: String = rows[i]["id"]
	var before := Armory.pack_of(id)
	var now := Armory.set_pack(id, before + step)
	if now == before and step > 0:
		_say(tr("No more room: %s.") % (tr("the satchel is full") if Armory.pack_total() >= Armory.satchel_slots() else tr("carry at most %d") % Armory.carry(id)))
	else:
		Audio.sfx("ui_move")


# ---------------------------------------------------------------- input

func _process(delta: float) -> void:
	if not visible:
		return
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame:
		return
	var up := Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up")
	var down := Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down")
	var left := Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left")
	var right := Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right")
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("armory"):
		close()
		return
	if Input.is_action_just_pressed("swap"):
		_set_tab(TABS[(TABS.find(tab) + 1) % TABS.size()])
		return
	if up:
		_move(-1)
	elif down:
		_move(1)
	if tab == "satchel" and (left or right):
		_pack_step(sel, -1 if left else 1)
		_rebuild()
	elif left or right:
		_set_tab(TABS[posmod(TABS.find(tab) + (1 if right else -1), TABS.size())])
		return
	if Input.is_action_just_pressed("ui_accept"):
		_act(sel)


func _set_tab(t: String) -> void:
	tab = t
	sel = 0
	scroll = 0
	_rebuild()


func _gui_input(event: InputEvent) -> void:
	if not Prompts.tapped(event):
		return
	var p: Vector2 = event.position
	if _close_rect().has_point(p):
		close()
		return
	for t in _tab_rects:
		if (_tab_rects[t] as Rect2).has_point(p):
			_set_tab(t)
			return
	for i in _minus_rects:
		if (_minus_rects[i] as Rect2).has_point(p):
			sel = i
			_pack_step(i, -1)
			_rebuild()
			return
	for i in _plus_rects:
		if (_plus_rects[i] as Rect2).has_point(p):
			sel = i
			_pack_step(i, 1)
			_rebuild()
			return
	for rr in _row_rects:
		if (rr[0] as Rect2).has_point(p):
			if sel == int(rr[1]):
				_act(sel)
			sel = int(rr[1])
			return


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing helpers

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _text_r(right: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	_text(right - Vector2(w, 0), s, fsize, col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	if s == "":
		return 0.0
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _box(r: Rect2, on: bool) -> void:
	draw_rect(r, Color(0.16, 0.13, 0.09) if on else Color(0.09, 0.08, 0.11))
	if on:
		draw_rect(r, GOLD, false, 1.0)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	_text(Vector2(8, 20), tr("Forge & Market"), 15, PAPER)
	_tab_rects.clear()
	var tx := 128.0
	for t in TABS:
		var label: String = Loc.t(TAB_NAMES[t])
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x + 14
		var r := Rect2(tx, 8, w, 15)
		_tab_rects[t] = r
		_box(r, tab == t)
		_text(r.position + Vector2(7, 11), label, 9, GOLD if tab == t else SOFT)
		tx += w + 4
	UiSkin.draw_icon(self, "gilt", Rect2(tx + 8, 9, 12, 12))
	_text(Vector2(tx + 23, 19), "%d" % int(Empire.res.get("gilt", 0)), 9, GOLD)
	_text(Vector2(8, 38), _status_line(), 8, SOFT, vs.x - 16)
	_draw_list(vs)
	_draw_detail(vs)
	_text(Vector2(8, vs.y - 8), _help(), 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var fw := minf(font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x, vs.x - 40)
		draw_rect(Rect2(vs.x - fw - 18, vs.y - 21, fw + 12, 15), Color(0.1, 0.08, 0.06, 0.95 * a))
		_text(Vector2(vs.x - fw - 12, vs.y - 10), flash, 9, Color(1, 0.9, 0.7, a), fw + 4)


func _help() -> String:
	match tab:
		"satchel":
			return Prompts.help([["updown", "item"], ["leftright", tr("pack fewer / more")], ["ui_accept", tr("buy from Tobble")], ["swap", "tab"], [["ui_cancel", "armory"], "close"]], tr("Tap - and + to pack, tap an item twice to buy it from Tobble"))
		"materials":
			return Prompts.help([["updown", "material"], ["swap", "tab"], [["ui_cancel", "armory"], "close"]], tr("Tap a material"))
		"market":
			return Prompts.help([["updown", "choose"], ["ui_accept", tr("buy / sell one")], ["swap", "tab"], [["ui_cancel", "armory"], "close"]], tr("Tap a stall twice to buy one"))
	return Prompts.help([["updown", "choose"], ["ui_accept", tr("forge it")], ["swap", "tab"], [["ui_cancel", "armory"], "close"]], tr("Tap a recipe twice to forge it"))


func _status_line() -> String:
	match tab:
		"forge":
			if Armory.forge_level() <= 0:
				return tr("No Forge yet. Plan one on the Buildings screen%s; a smith with good Craft runs it.") % Prompts.tag("buildings")
			var fe := Armory.forge_effect()
			return tr("Forge level %d: %s. Benches busy: %d/%d.") % [Armory.forge_level(), fe["text"], Armory.jobs().size(), int(fe.get("benches", 0))]
		"market":
			if Armory.market_level() <= 0:
				return tr("No Market yet. Plan one on the Buildings screen%s; a charming trader runs it. Tobble's supplies are on the Satchel tab.") % Prompts.tag("buildings")
			return tr("Market level %d: %s.") % [Armory.market_level(), Armory.market_effect()["text"]]
		"satchel":
			var ups := (Armory.state()["upgrades"] as Array).map(func(u): return Armory.result_name(u))
			return tr("Satchel: %d of %d slots packed%s. Free rations top up tonics, salts and draughts after every mission; the rest comes from the stores.") % [
				Armory.pack_total(), Armory.satchel_slots(), (" (" + ", ".join(ups) + ")") if not ups.is_empty() else ""]
	return tr("Materials come from enemies, Raid caches and Salvage piles, and the Market. The Forge turns them into gear and supplies.")


func _row_label(row: Dictionary) -> Array:  # [icon id, name, right text, colour, right colour]
	match str(row["kind"]):
		"job":
			var j: Dictionary = row["job"]
			var who := (tr(" for ") + PartyPicker.short_of(j["hero"])) if str(j.get("hero", "")) != "" else ""
			var n := "" if int(j["makes"]) <= 1 else " x%d" % int(j["makes"])
			return [j["result"], Armory.result_name(j["result"]) + n + who, Armory.job_eta(j), TEXT, GOLD]
		"weapon":
			var r: Dictionary = row["recipe"]
			var now := Armory.weapon_now(row["hero"])
			if r.is_empty():
				return [now, "%s: %s" % [PartyPicker.short_of(row["hero"]), Progress.item(now).get("name", tr("no weapon"))], tr("top of the line"), SOFT, DIM]
			var why := Armory.craft_blocker(r)
			return [r["result"], "%s: %s" % [PartyPicker.short_of(row["hero"]), Armory.result_name(r["result"])], _short_why(why, r), TEXT if why == "" else SOFT, GOOD if why == "" else DIM]
		"recipe":
			var r2: Dictionary = row["recipe"]
			var why2 := Armory.craft_blocker(r2)
			var n2 := "" if int(r2["makes"]) <= 1 else " x%d" % int(r2["makes"])
			return [r2["result"], Armory.result_name(r2["result"]) + n2, _short_why(why2, r2), TEXT if why2 == "" else SOFT, GOOD if why2 == "" else DIM]
		"stall":
			var st: Dictionary = row["stall"]
			var left := Armory.stall_left(int(row["i"]), st)
			var icon: String = st["id"]
			return [icon, tr("%s  (%d left)") % [Armory.stock_name(st["kind"], st["id"]), left] if left > 0 else tr("%s  (sold out)") % Armory.stock_name(st["kind"], st["id"]),
				"%d G" % Armory.price(st["kind"], st["id"]), TEXT if left > 0 else DIM, GOLD if Armory.buy_blocker(int(row["i"]), st) == "" else BAD]
		"sell":
			return [row["id"], "%s  x%d" % [Armory.mat_name(row["id"]), Armory.mat_count(row["id"])], "+%d G" % Armory.sell_price_mat(row["id"]), TEXT, GOOD]
		"pack":
			var id: String = row["id"]
			return [id, str(Satchel.item(id).get("name", id)), "", TEXT, SOFT]
		"mat":
			var k: String = row["id"]
			var open := Armory.region_ok(str(Armory.mat(k).get("region", "")))
			return [k, Armory.mat_name(k), "x%d" % Armory.mat_count(k) if open or Armory.mat_count(k) > 0 else tr("not found yet"), TEXT if open else SOFT, MAT_COL if Armory.mat_count(k) > 0 else DIM]
	return ["", "?", "", TEXT, TEXT]


func _short_why(why: String, r: Dictionary) -> String:
	if why == "":
		var d := Armory.days_for(r)
		return "%d G, %s" % [int(r["gilt"]), tr("1 day") if d <= 1 else tr("%d days") % d]
	if why.begins_with("needs materials from"):
		return tr("Tier %d: later") % int(r["tier"])
	if why.begins_with("needs a level"):
		return why.trim_prefix("needs a ")
	if why.begins_with("needs ") and why.contains("more"):
		return tr("short of materials")
	return why


func _draw_list(vs: Vector2) -> void:
	_row_rects.clear()
	_minus_rects.clear()
	_plus_rects.clear()
	var top := 46.0
	var bottom := vs.y - 18.0
	var per := int((bottom - top) / ROW_H)
	if rows.is_empty():
		var empty: String = {"forge": tr("Nothing to forge yet."), "market": tr("The Market has nothing out: it needs a trader at work.") if Armory.market_level() > 0 else "",
			"satchel": "", "materials": ""}[tab]
		_text(Vector2(12, top + 14), empty, 9, SOFT, LIST_W)
		return
	if sel < scroll:
		scroll = maxi(sel - 1, 0)
	elif sel >= scroll + per:
		scroll = sel - per + 1
	scroll = clampi(scroll, 0, maxi(rows.size() - per, 0))
	var y := top
	for i in range(scroll, mini(rows.size(), scroll + per)):
		var row: Dictionary = rows[i]
		if row.has("head"):
			_text(Vector2(10, y + 10), str(row["head"]).to_upper(), 7, Color("a07a4e"))
			y += ROW_H
			continue
		var r := Rect2(8, y + 1, LIST_W, ROW_H - 2)
		_row_rects.append([r, i])
		var on := i == sel
		_box(r, on)
		var lab := _row_label(row)
		var nx := 6.0
		if lab[0] != "" and UiSkin.draw_icon(self, str(lab[0]), Rect2(r.position + Vector2(4, -1), Vector2(12, 12))):
			nx = 20.0
		elif lab[0] != "":
			var tone := _tone(row)
			draw_rect(Rect2(r.position + Vector2(5, 2), Vector2(8, 8)), Color(tone, 0.6))
			nx = 18.0
		if row["kind"] == "pack":
			_draw_pack_row(r, i, on, nx)
		else:
			_text(r.position + Vector2(nx, 9), str(lab[1]), 8, GOLD if on and lab[3] == TEXT else lab[3], LIST_W - nx - 96)
			_text_r(r.position + Vector2(LIST_W - 5, 9), str(lab[2]), 7, lab[4])
		y += ROW_H
	if rows.size() > per:  # a thin scroll bar
		var h := (bottom - top) * float(per) / rows.size()
		var sy := top + (bottom - top - h) * float(scroll) / maxf(rows.size() - per, 1)
		draw_rect(Rect2(LIST_W + 10, sy, 2, h), Color(0.6, 0.5, 0.35, 0.6))


func _tone(row: Dictionary) -> Color:
	match str(row["kind"]):
		"weapon":
			return SLOT_COLORS["weapon"]
		"recipe":
			var r: Dictionary = row["recipe"]
			return SLOT_COLORS.get(Progress.item(r["result"]).get("slot", r["kind"]), TEXT)
		"mat", "sell":
			return MAT_COL
	return SOFT


func _draw_pack_row(r: Rect2, i: int, on: bool, nx: float) -> void:
	var id: String = rows[i]["id"]
	var it := Satchel.item(id)
	_text(r.position + Vector2(nx, 9), str(it.get("name", id)), 8, GOLD if on else TEXT, 104)
	var mr := Rect2(r.position + Vector2(126, 1), Vector2(10, 10))
	var pr := Rect2(r.position + Vector2(168, 1), Vector2(10, 10))
	_minus_rects[i] = mr
	_plus_rects[i] = pr
	draw_rect(mr, Color(0.2, 0.17, 0.12))
	draw_rect(pr, Color(0.2, 0.17, 0.12))
	_text(mr.position + Vector2(3, 8), "-", 8, SOFT)
	_text(pr.position + Vector2(2, 8), "+", 8, SOFT)
	var packed := Armory.pack_of(id)
	var in_bag := Satchel.count(id)
	var pk_col := GOOD if packed > 0 and in_bag >= packed else (BAD if packed > in_bag else SOFT)
	_text_r(r.position + Vector2(164, 9), "%d/%d" % [packed, Armory.carry(id)], 8, pk_col)
	_text(r.position + Vector2(184, 9), tr("stores %d") % Armory.stored(id), 7, SOFT)
	if it.get("stall", false):
		_text_r(r.position + Vector2(LIST_W - 5, 9), tr("Tobble %d G") % int(it.get("price", 0)), 7, GOLD)


# ---------------------------------------------------------------- the detail panel

func _draw_detail(vs: Vector2) -> void:
	var rx := LIST_W + 18.0
	var rw := vs.x - rx - 8.0
	var box := Rect2(rx, 46, rw, vs.y - 46 - 18)
	UiSkin.panel(self, box, "ledger")
	if rows.is_empty() or sel >= rows.size() or rows[sel].has("head"):
		return
	var row: Dictionary = rows[sel]
	var x := rx + 10.0
	var w := rw - 20.0
	var y := box.position.y + 18.0
	match str(row["kind"]):
		"weapon", "recipe":
			var r: Dictionary = row["recipe"]
			if r.is_empty():
				var now := Armory.weapon_now(row["hero"])
				y = _item_head(now, x, y, w)
				_wrap(Vector2(x, y + 4), tr("Tier %d, the last of %s's line. Nothing in the Inklands improves on it.") % [Armory.tier_of(now), PartyPicker.short_of(row["hero"])], w, 8, SOFT)
				return
			y = _item_head(r["result"], x, y, w)
			if r["kind"] == "weapon":
				_text(Vector2(x, y), tr("From the %s (%s)") % [Progress.item(r["from"]).get("name", r["from"]),
					tr("in %s's hands until it's done") % PartyPicker.short_of(r["hero"]) if Armory.weapon_now(r["hero"]) == r["from"] else tr("from the bag")], 7, SOFT, w)
				y += 11
			y += _wrap(Vector2(x, y + 2), Armory.result_blurb(r["result"]), w, 8, Color(0.78, 0.76, 0.74)) + 6
			y = _needs(r, x, y, w)
			var why := Armory.craft_blocker(r)
			y += 4
			if why == "":
				var d := Armory.days_for(r)
				_text(Vector2(x, y + 8), tr("%s: forge it. Ready %s.") % [_ok_word(), tr("at dawn") if d <= 1 else tr("in %d days") % d], 8, GOOD, w)
			else:
				_wrap(Vector2(x, y + 8), tr("Can't yet: %s.") % why, w, 8, BAD)
		"job":
			var j: Dictionary = row["job"]
			y = _item_head(j["result"], x, y, w)
			_text(Vector2(x, y + 4), tr("On a bench. Ready %s.") % Armory.job_eta(j), 8, GOLD, w)
			_wrap(Vector2(x, y + 18), Armory.result_blurb(j["result"]), w, 8, Color(0.78, 0.76, 0.74))
		"stall":
			var st: Dictionary = row["stall"]
			match str(st["kind"]):
				"materials":
					y = _mat_head(st["id"], x, y, w)
				"items":
					y = _item_head(st["id"], x, y, w)
					y += _wrap(Vector2(x, y + 2), Armory.result_blurb(st["id"]), w, 8, Color(0.78, 0.76, 0.74)) + 4
					_text(Vector2(x, y + 8), tr("In the satchel %d, in the stores %d.") % [Satchel.count(st["id"]), Armory.stored(st["id"])], 8, SOFT, w)
				_:
					y = _item_head(st["id"], x, y, w)
					y += _wrap(Vector2(x, y + 2), Armory.result_blurb(st["id"]), w, 8, Color(0.78, 0.76, 0.74)) + 4
			var why2 := Armory.buy_blocker(int(row["i"]), st)
			_text(Vector2(x, box.end.y - 10), (tr("%s: buy one for %d Gilt.") % [_ok_word(), Armory.price(st["kind"], st["id"])]) if why2 == "" else tr("Can't: %s.") % why2, 8, GOOD if why2 == "" else BAD, w)
		"sell", "mat":
			_mat_head(row["id"], x, y, w)
			if row["kind"] == "sell":
				_text(Vector2(x, box.end.y - 10), tr("%s: sell one for %d Gilt.") % [_ok_word(), Armory.sell_price_mat(row["id"])], 8, GOOD, w)
		"pack":
			var id: String = row["id"]
			y = _item_head(id, x, y, w)
			y += _wrap(Vector2(x, y + 2), Armory.result_blurb(id), w, 8, Color(0.78, 0.76, 0.74)) + 6
			var it := Satchel.item(id)
			var lines := [tr("Packed: %d (carry at most %d).") % [Armory.pack_of(id), Armory.carry(id)], tr("In the satchel now: %d. In the stores: %d.") % [Satchel.count(id), Armory.stored(id)]]
			if int(it.get("start", 0)) > 0:
				lines.append(tr("Free rations: up to %d after every mission.") % int(it["start"]))
			if it.get("stall", false):
				lines.append(tr("Tobble sells them: %d Gilt (%s).") % [int(it.get("price", 0)), _ok_word()])
			if Armory.forge_data().get("recipes", {}).has(id):
				lines.append(tr("The Forge makes them: %s.") % Armory.mats_text(Armory.recipe(id)["mats"]))
			for l in lines:
				_text(Vector2(x, y + 8), l, 8, SOFT, w)
				y += 11


## Icon, name, tier and slot, and the stats line. Returns the y below it.
func _item_head(id: String, x: float, y: float, w: float) -> float:
	UiSkin.draw_icon(self, id, Rect2(x + w - 32, y - 10, 32, 32))
	_text(Vector2(x, y), Armory.result_name(id), 11, PAPER, w - 36)
	y += 12
	var it := Progress.item(id)
	if not it.is_empty():
		var owner := str(it.get("hero", ""))
		var what := tr("%s, tier %d, %s") % [{"weapon": tr("Weapon"), "armor": tr("Armour"), "trinket": tr("Trinket")}.get(it.get("slot", ""), tr("Gear")), int(it.get("tier", 1)),
			(tr("for ") + PartyPicker.short_of(owner)) if owner != "" else tr("anyone can wear it")]
		_text(Vector2(x, y), what, 8, SLOT_COLORS.get(it.get("slot", ""), TEXT), w - 36)
		y += 11
		y += _wrap(Vector2(x, y), Progress.item_text(id), w - 36, 8, GOOD)
		var owned := Progress.count(id) + Progress.worn_by(id).size()
		if owned > 0:
			_text(Vector2(x, y + 9), tr("You have %d.") % owned, 7, SOFT, w)
			y += 10
	elif not Satchel.item(id).is_empty():
		_text(Vector2(x, y), tr("Field item, used from the quick menu"), 8, SLOT_COLORS["item"], w - 36)
		y += 11
	else:
		_text(Vector2(x, y), tr("Satchel upgrade"), 8, SLOT_COLORS["upgrade"], w - 36)
		y += 11
	return y + 4


## The materials and Gilt a recipe takes, each marked by whether you have enough.
func _needs(r: Dictionary, x: float, y: float, w: float) -> float:
	_text(Vector2(x, y + 8), tr("Takes"), 8, Color(0.75, 0.72, 0.7))
	y += 11
	for k in r["mats"]:
		var need := int(r["mats"][k])
		var have := Armory.mat_count(k)
		var open := Armory.region_ok(str(Armory.mat(k).get("region", "")))
		UiSkin.draw_icon(self, k, Rect2(x, y, 10, 10))
		var note := "" if open else tr("  (%s, later in the story)") % Armory.region_name(str(Armory.mat(k).get("region", "")))
		_text(Vector2(x + 13, y + 8), "%s  %d/%d%s" % [Armory.mat_name(k), have, need, note], 8, GOOD if have >= need else (DIM if not open else BAD), w - 13)
		y += 11
	var g := int(r["gilt"])
	UiSkin.draw_icon(self, "gilt", Rect2(x, y, 10, 10))
	_text(Vector2(x + 13, y + 8), tr("%d Gilt") % g, 8, GOOD if int(Empire.res.get("gilt", 0)) >= g else BAD, w - 13)
	return y + 12


func _mat_head(k: String, x: float, y: float, w: float) -> float:
	UiSkin.draw_icon(self, k, Rect2(x + w - 32, y - 10, 32, 32))
	_text(Vector2(x, y), Armory.mat_name(k), 11, PAPER, w - 36)
	y += 12
	var m := Armory.mat(k)
	_text(Vector2(x, y), tr("Material, tier %d, %s. You have %d.") % [int(m.get("tier", 2)), Armory.region_name(str(m.get("region", ""))), Armory.mat_count(k)], 8, MAT_COL, w - 36)
	y += 6
	y += _wrap(Vector2(x, y + 8), str(m.get("blurb", "")), w, 8, Color(0.78, 0.76, 0.74)) + 6
	var src := Armory.sources(k)
	y += _wrap(Vector2(x, y + 8), tr("Found on: ") + (", ".join(src) if not src.is_empty() else tr("nothing you can reach yet")), w, 8, SOFT) + 4
	var uses := Armory.uses(k).map(func(u): return Armory.result_name(u))
	if uses.size() > 8:
		uses = uses.slice(0, 8) + [tr("and %d more") % (Armory.uses(k).size() - 8)]
	y += _wrap(Vector2(x, y + 8), tr("Makes: ") + ", ".join(uses), w, 8, SOFT)
	return y


## What to press to act on this device: "Enter", "A", "Tap twice" (issue #115).
func _ok_word() -> String:
	return tr("Tap twice") if Prompts.touch() else Prompts.confirm()
