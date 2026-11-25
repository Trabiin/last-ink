extends Control
## Code-drawn HUD: party HP and power gauges, banter line, banners.

var party  # main.gd
var banter_text := ""
var banter_t := 0.0
var center_text := ""
var sign_text := ""
var help_t := 14.0
var _ghost := {}  # hero instance id -> the HP fraction the bar's draining "just lost" part still shows


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The control hints show once (first mission of a save); after that only on F1, so no text sits on screen.
	if Dialogue.is_seen("hint:mission"):
		help_t = 0.0
	else:
		Dialogue.mark_seen("hint:mission")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		help_t = 0.0 if help_t > 0.0 else 10.0


func say(text: String, duration := 3.5) -> void:
	banter_text = text
	banter_t = duration


func _process(delta: float) -> void:
	# Redraws while paused too (a conversation or menu opening must clear the old picture), but the
	# timers only run in play, so the control hints wait until the opening talk is over.
	if not get_tree().paused:
		banter_t = maxf(banter_t - delta, 0.0)
		if party:
			for h in party.heroes:  # the lost-HP ghost waits a moment, then drains
				var hid := str(h.get_instance_id())
				var r := clampf(float(h.hp) / maxf(h.max_hp, 1), 0.0, 1.0)
				if _ghost.has(hid) and _ghost[hid] > r:
					_ghost[hid] = maxf(r, float(_ghost[hid]) - delta * 0.35)
		help_t = maxf(help_t - delta, 0.0)
	queue_redraw()


func _text(pos: Vector2, s: String, size := 10, col := Color.WHITE, outline := true) -> void:
	var font := ThemeDB.fallback_font
	if outline:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), 3, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)


func _text_centered(y: float, s: String, size := 10, col := Color.WHITE) -> void:
	var w := ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
	_text(Vector2((size_px().x - w) / 2.0, y), s, size, col)


func size_px() -> Vector2:
	return get_viewport_rect().size


const INK_COL := Color("7fa8ec")


## The leader's abilities, bottom-right: key, name, Ink cost, cooldown sweep.
func _draw_ability_bar(hero: Hero, vs: Vector2) -> void:
	var n := hero.abilities.size()
	if n == 0:
		return
	var has_icons := UiSkin.icon(str(hero.abilities[0].get("id", ""))) != null
	var w := 94.0 if has_icons else 84.0
	var x := vs.x - 8.0 - n * (w + 4.0) + 4.0
	var y := vs.y - 38.0
	_text(Vector2(x, y - 4), tr("Ink %d / %d") % [floori(hero.ink), int(hero.max_ink)], 8, INK_COL)
	for i in n:
		var a: Dictionary = hero.abilities[i]
		var why := Abilities.blocker(hero, i)
		var r := Rect2(x, y, w, 32)
		UiSkin.panel(self, r, "button", Color.WHITE if why == "" else Color(0.6, 0.6, 0.65))
		var col := Abilities.color_of(a)
		var cd: float = hero.cooldowns[i]
		if cd > 0.0:  # cooling down: the slot is shaded from the right, with a brass edge where it stands
			var cw := roundf((w - 4.0) * cd / float(a.get("cooldown", 1.0)))
			draw_rect(Rect2(x + w - 2.0 - cw, y + 2, cw, 28), Color(UiSkin.BAR_INK, 0.5))
			draw_rect(Rect2(x + w - 2.0 - cw, y + 2, 1, 28), Color(UiSkin.BRASS[1], 0.8))
		UiSkin.tab(self, Rect2(x + 1, y + 2, 6, 28), col, why != "")  # the ability's colour, as a ribbon
		var txt_col := Color.WHITE if why == "" else Color(0.6, 0.6, 0.6)
		var ox := 0.0  # text starts after the ability's icon
		if UiSkin.draw_icon(self, str(a.get("id", "")), Rect2(x + 8, y + 6, 20, 20), Color.WHITE if why == "" else Color(0.5, 0.5, 0.55)):
			ox = 21.0
		var k := Prompts.key("ability_%d" % (i + 1))  # 1-4, or LB / RB / LT / RT on a pad
		if k == "":
			k = str(i + 1)
		_text(Vector2(x + 9 + ox, y + 10), k, 9, UiSkin.ramp(col)[3], false)
		var kw := ThemeDB.fallback_font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		var nx := x + 13 + ox + kw  # long names at large text sizes end in "..." inside the slot
		_text(Vector2(nx, y + 10), Access.fit(ThemeDB.fallback_font, str(a.get("name", "")), Access.fs(8), r.end.x - 5.0 - nx), 8, txt_col, false)
		var cost_col := INK_COL if why != "ink" else Color("c4504a")
		_text(Vector2(x + 9 + ox, y + 22), tr("%d Ink") % int(a.get("cost", 0)), 8, cost_col, false)
		if cd > 0.0:
			_text(Vector2(x + 46 + ox, y + 22), Loc.dec(cd) + "s", 8, Color(0.8, 0.8, 0.85), false)
		x += w + 4.0


func _draw() -> void:
	if party == null:
		return
	if party.dialogue_box and party.dialogue_box.visible:
		return  # conversations have the screen to themselves (their title sits where the objective does), like in town
	var vs := size_px()
	# Party panels, bottom-left
	var x := 8.0
	for h in party.heroes:
		var hero: Hero = h
		var y := vs.y - 38.0
		# Art pass heroes get a face icon cut from their sprite; the plate grows to fit it.
		var face: Texture2D = hero.art.face() if hero.art != null else null
		var fw := 24.0 if face != null else 0.0
		var panel := Rect2(x, y, 112 + fw, 32)
		UiSkin.panel(self, panel, "ledger")
		if not hero.dead:
			Status.draw_icons(self, hero, Vector2(panel.position.x + 3, y - 13))  # ailments and boons (issue #112)
		if hero.controlled:
			UiSkin.highlight(self, panel)
		if face != null:
			draw_rect(Rect2(x + 3, y + 6, 20, 20), Color(0.16, 0.15, 0.2, 0.9))
			draw_texture_rect(face, Rect2(x + 3, y + 6, 20, 20), false, Color(0.45, 0.45, 0.45) if hero.dead else Color.WHITE)
			x += fw
		var name_col := Color(0.6, 0.6, 0.6) if hero.dead else Color.WHITE
		var pct := int(round(hero.power * 100.0))
		var pcol := Color("f2c25c") if pct >= 100 else Color(0.8, 0.8, 0.85)
		# The gauge sits against the plate's right edge, the level just left of it, and the name gets
		# what is left (trimmed with "..."), so nothing runs into the frame at large text sizes.
		var hf := ThemeDB.fallback_font
		var pct_s := "%d%%" % pct
		var px := minf(x + 82, panel.end.x - 6.0 - hf.get_string_size(pct_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x)
		var lv_s := tr("Lv%d") % Progress.level(hero.hero_id)
		var lx := minf(x + 58, px - 4.0 - hf.get_string_size(lv_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x)
		_text(Vector2(x + 5, y + 10), Access.fit(hf, hero.hero_name + (tr("  (down)") if hero.dead else ""), Access.fs(9), lx - 3.0 - (x + 5)), 9, name_col, false)
		if not hero.charge_ready:  # a ready charged tech shows TECH here instead
			_text(Vector2(px, y + 10), pct_s, 9, pcol, false)
		_text(Vector2(lx, y + 10), lv_s, 8, Color(0.75, 0.72, 0.6), false)
		# XP: a thin plum line along the top edge of the panel
		UiSkin.bar(self, Rect2(x + 5, y + 2, 102, 1), Progress.xp_fraction(hero.hero_id), "xp", {"frame": false})
		# HP: shaded pixel bar, a notch every 10 HP, the part just lost draining away in bone,
		# and stripes once it is low (with danger patterns on) so the warning never rests on colour.
		var ratio := clampf(float(hero.hp) / hero.max_hp, 0.0, 1.0)
		var hid := str(hero.get_instance_id())
		var ghost: float = maxf(float(_ghost.get(hid, ratio)), ratio)
		_ghost[hid] = ghost
		UiSkin.bar(self, Rect2(x + 5, y + 14, 102, 4), ratio, UiSkin.hp_ramp(ratio),
			{"notch": UiSkin.notch_every(102, hero.max_hp), "ghost": ghost, "hatch": Access.danger_patterns and ratio <= 0.25 and not hero.dead})
		# Power gauge: brass, lamplight once full; while a charged tech fills, the tech's own colour with a
		# notch for every tech this hold can reach.
		var charging: bool = hero.charging and hero.charge_t >= Techs.TAP  # charged tech filling (issues #8, #24)
		if charging:
			var tcol := Techs.color_of(hero)
			var marks := []
			for st in Techs.stages(hero):
				marks.append(float(st[0]))
			UiSkin.bar(self, Rect2(x + 5, y + 21, 102, 2), Techs.fill(hero), UiSkin.RAMP["power_full"] if hero.charge_ready else UiSkin.ramp(tcol), {"notches": marks})
			if hero.charge_ready:
				UiSkin.draw_icon(self, "tech_" + hero.hero_id, Rect2(x + 99, y + 2, 10, 10))
				var tw := ThemeDB.fallback_font.get_string_size(tr("TECH"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
				_text(Vector2(minf(x + 80, x + 97 - tw), y + 10), tr("TECH"), 9, UiSkin.RAMP["power_full"][3], false)
		else:
			UiSkin.bar(self, Rect2(x + 5, y + 21, 102, 2), hero.power, "power_full" if pct >= 100 else "power", {"notches": [0.25, 0.5, 0.75]})
		# Ink (abilities, issue #7)
		if hero.max_ink > 0.0:
			UiSkin.bar(self, Rect2(x + 5, y + 25, 102, 2), hero.ink / hero.max_ink, "ink")
		x += 118.0
	if party.leader and not party.touch_active():
		_draw_ability_bar(party.leader, vs)

	# Mission name and objective, top-left
	_text(Vector2(8, 14), party.mission.get("name", party.area.area_name), 10, Color(0.9, 0.88, 0.8))
	var done: bool = party.objective.done()
	_text(Vector2(8, 26), party.objective.text() + (tr("  done") if done else ""), 9, Color("9fd3a8") if done else Color("ffd166"))
	var yy0 := 38.0
	var found := Missions.res_text(party.found)
	var gear_found: Array = party.found_items.map(func(i): return Progress.item(i).get("name", i))
	if not gear_found.is_empty():
		found = (found + ", " if found != "" else "") + ", ".join(gear_found)
	if found != "":
		var lit: bool = party.found_flash > 0.0
		_text(Vector2(8, yy0), tr("Found: %s") % found, 8, Color("ffe7a3") if lit else Color(0.75, 0.75, 0.75))
		yy0 += 12.0
	var perks: Array = party.boosts.get("lines", [])
	if not perks.is_empty():
		_text(Vector2(8, yy0), tr("Research: %s") % ", ".join(perks), 8, Color("d7b8f0"))

	if banter_t > 0.0:
		var a := clampf(banter_t / 0.4, 0.0, 1.0)
		_text_centered(58.0, banter_text, 10, Color(1, 1, 1, a))
	if sign_text != "":
		UiSkin.sign(self, vs, vs.y * 0.62, sign_text)
	if help_t > 0.0 and not party.touch_active():
		var a2 := clampf(help_t / 1.0, 0.0, 1.0)
		# Matches the device in use (issue #23): keys on a keyboard, button names on a pad.
		# Touch names no keys (you tap instead), but this list only shows while the touch buttons are
		# hidden, i.e. a keyboard is in play: so a last tap (a touchscreen laptop) still gets key names.
		var pad := Prompts.pad()
		var dev := Prompts.PAD if pad else Prompts.KEYS
		var abil := "%s %s %s %s" % [Prompts.key("ability_1", dev), Prompts.key("ability_2", dev), Prompts.key("ability_3", dev), Prompts.key("ability_4", dev)]
		var lines_h := [
			tr("Move: %s") % (tr("left stick / D-pad") if pad else tr("WASD / arrows")),
			Techs.how_to(dev),
			tr("Swap hero: %s") % Prompts.key("swap", dev),
			tr("Pause: %s") % Prompts.key("pause", dev),
			tr("Abilities: %s") % abil.strip_edges(),
			tr("Quick menu: %s") % Prompts.key("quick_menu", dev),
			"" if pad else tr("F1: show or hide this"),
		]
		for li in lines_h.size():
			_text(Vector2(vs.x - Access.px(150.0), 96 + Access.px(11.0) * li), lines_h[li], 8, Color(1, 1, 1, a2))  # clear of the banter panel
	if center_text != "":
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.95, 0.94, 0.9, 0.55))
		var lines2 := center_text.split("\n")
		var y2 := vs.y / 2.0 - 8.0 * lines2.size()
		for line in lines2:
			_text_centered(y2, line, 14, Color.WHITE)
			y2 += 20.0
