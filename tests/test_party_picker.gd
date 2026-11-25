extends "res://tests/test_case.gd"
## The party picker (scripts/party_picker.gd): heroes nobody has found yet stay off the list (no names,
## no stats, only a count and the rescue rumours), and every line of text stays inside its row, card,
## button or panel at each text size, with and without the readable font, on narrow, wide and tall screens.

const SIZES := [Vector2(640, 360), Vector2(853, 360), Vector2(640, 480), Vector2(1138, 360)]

var Empire: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Empire.reset()


func after_each() -> void:
	Access.text_size = 0
	Access.readable_font = false
	Access.apply_font()
	Empire.reset()


func _field() -> Array:
	return Empire.recruit_data.keys().filter(func(id): return Empire.recruit_data[id].get("tier", "") == "field")


func _join(id: String, role := "idle", target := "") -> void:
	Empire.recruits[id] = {"role": role, "target": target, "injured": 0}


func _picker() -> PartyPicker:
	var p := PartyPicker.new()
	tree.root.add_child(p)
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)  # so open() and a test size stick without warnings
	p.open({"id": "test", "name": "Raid: Coven stores"})
	return p


func test_unfound_heroes_stay_hidden() -> void:
	for id in _field():
		Empire.recruits.erase(id)
	_join("ash", "party")
	_join("bran", "party")
	var p := _picker()
	await frames(3)
	check_eq(p._ids(), ["ash", "bran"], "only joined heroes get a row")
	check_eq(p._row_rects.size(), 2, "two rows")
	var text := " ".join(p.drawn_text.map(func(d): return str(d[2])))
	for id in p._unfound():
		var r: Dictionary = Empire.recruit(id)
		for s in [str(r["name"]), str(r.get("title", ""))]:
			check(s == "" or not s in text, "%s's %s is not on screen" % [id, s])
	var lost: int = p._unfound().size()
	check(("%d more heroes" % lost) in text, "the card counts the %d unfound heroes (%s)" % [lost, text])
	check("witch in the Gutterwoods" in text, "a rescue rumour still points the way (%s)" % text)
	check(p._card_rect.size != Vector2.ZERO, "the card is drawn")
	# Up from the top wraps to "Set out", never onto a hidden hero; the detail panel only ever shows joined heroes.
	p.sel = 0
	for k in 4:
		p.sel = posmod(p.sel - 1, p._ids().size() + 1)
		check(p.sel <= p._ids().size(), "focus stays on rows that exist")
	p.queue_free()


func test_no_card_once_everyone_joined() -> void:
	for id in _field():
		_join(id)
	var p := _picker()
	await frames(3)
	check(p._unfound().is_empty(), "nobody left to find")
	check_eq(p._card_rect, Rect2(), "no card")
	p.queue_free()


## Three rosters: the start, half way with long "Busy" lines, and everyone with a full party.
func _setups() -> Array:
	return [
		["start", func():
			for id in _field():
				Empire.recruits.erase(id)
			_join("ash", "party")
			_join("bran", "party")],
		["half, busy", func():
			for id in _field():
				Empire.recruits.erase(id)
			var f := _field()
			for i in f.size() / 2 + 1:
				_join(f[i])
			Empire.recruits["ash"]["role"] = "party"
			Empire.recruits[f[1]]["injured"] = 12
			Empire.recruits[f[2]]["role"] = "staff"
			Empire.recruits[f[2]]["target"] = "guildhall"],
		["everyone", func():
			var f := _field()
			for id in f:
				_join(id)
			Empire.recruits["ash"]["role"] = "party"
			Empire.recruits[f[1]]["role"] = "party"
			Empire.recruits[f[2]]["role"] = "party"
			Empire.recruits[f[3]]["role"] = "expedition"],
	]


func test_text_stays_inside_its_boxes() -> void:
	Access.load_settings()
	for setup in _setups():
		Empire.reset()
		setup[1].call()
		for readable in [false, true]:
			for ts in Access.TEXT_SIZES.size():
				Access.text_size = ts
				Access.readable_font = readable
				Access.apply_font()
				var p := _picker()
				p.font = ThemeDB.fallback_font
				for vs in SIZES:
					p.size = vs
					var where := "%s, text size %d%s, %dx%d" % [setup[0], ts, " readable" if readable else "", vs.x, vs.y]
					var bad := false
					for s in p._ids().size() + 1:
						p.sel = s
						p.queue_redraw()
						await frames(2)
						bad = not _check_layout(p, vs, "%s, focus %d" % [where, s])
						if bad:
							break
					if bad:
						break
				p.queue_free()
				await frames(1)


func _check_layout(p: PartyPicker, vs: Vector2, where: String) -> bool:
	var screen := Rect2(Vector2.ZERO, vs).grow(0.5)
	var n0 := failures.size()
	check(not p.drawn_text.is_empty(), "%s: nothing drawn" % where)
	for d in p.drawn_text:
		var t: Rect2 = d[0]
		var b: Rect2 = d[1]
		if not check(b.grow(0.5).encloses(t), "%s: \"%s\" %s runs out of its box %s" % [where, d[2], t, b]):
			break
		if not check(screen.encloses(b), "%s: box %s for \"%s\" is off screen" % [where, b, d[2]]):
			break
	var rows: Array = p._row_rects.filter(func(r): return (r as Rect2).size != Vector2.ZERO)
	for i in rows.size():
		var r: Rect2 = rows[i]
		check(screen.encloses(r), "%s: row %s off screen" % [where, r])
		check(not r.intersects(p._go_rect) and not r.intersects(p._card_rect), "%s: row %s runs into the buttons or the card" % [where, r])
		if i > 0:
			check(not r.intersects(rows[i - 1]), "%s: rows %d and %d overlap" % [where, i - 1, i])
	if p.sel < p._ids().size():
		check((p._row_rects[p.sel] as Rect2).size != Vector2.ZERO, "%s: the focused row is on screen" % where)
	check(screen.encloses(p._go_rect) and screen.encloses(p._back_rect), "%s: buttons on screen" % where)
	check(not p._go_rect.intersects(p._back_rect), "%s: buttons overlap" % where)
	return failures.size() == n0
