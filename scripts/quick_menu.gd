class_name QuickMenu
extends Control
## The quick menu (issue #6): one button opens it mid-fight and time slows to 10% instead of pausing.
## Tabs: Items, Abilities, Techs (which charged tech, orders to allies), Tree (skill trees, issue #25),
## Party (take control, AI behaviour), Equip.
## A plain list, never a ring.
## Every action is two presses: pick a row, then pick from its short list (or it acts at once).
##
## Keyboard: C opens/closes, arrows/WASD move, Q/E (or left/right) change tab, J/Enter picks, X/Esc backs out.
## Gamepad: Back opens/closes, d-pad/stick move, LB/RB (or left/right) change tab, A picks, B backs out.
## The tab keys sit either side of the tab row (TabStrip), read from the live bindings.
## 1-4 and the shoulders/triggers are left alone: they are ability hotkeys (issue #7).
## Mouse and touch: tap a tab, tap a row, tap outside the panel to close.

signal closed

const TABS := ["Items", "Abilities", "Techs", "Tree", "Party", "Equip", "Options"]
const SLOW := 0.1
const W := 420.0
const ROW_H := 30.0
const GOLD := Color("ffd166")
const TEXT := Color(0.92, 0.9, 0.86)
const DIM := Color(0.55, 0.55, 0.58)
const PANEL := Color(0.06, 0.05, 0.09, 0.92)

var party  # main.gd
var tab := 0
var rows: Array = []  # {"id", "label", "right", "detail", "enabled", "hero"}
var sel := 0
var sub: Array = []  # the short list a row opens: {"id", "label", "right", "enabled"}
var sub_sel := 0
var sub_title := ""
var note := ""
var note_t := 0.0
var _t := 0.0
var _panel := Rect2()
var _strip := TabStrip.new()  # the tab row with its switch keys either side
var _row_rects: Array = []  # one per row (Rect2() for a row scrolled out of sight)
var _top := 0  # first row shown when the list is taller than the screen
var _follow := true  # keep the focused row in view (false after the wheel or a finger scrolled)
var _drag := {}  # a finger on the list (Prompts.list_steps / list_tap)
var _sub_rects: Array = []
var _sub_panel := Rect2()
var _hero_data := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var parsed = Loc.load_json("res://data/heroes.json")
	_hero_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	# This menu only exists on missions, so it is where battle speed (Options) switches on and off.
	Settings.in_battle = true
	Settings.slowed = false
	Settings.refresh_time_scale(SLOW)


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	sub = []
	note = ""
	Settings.slowed = true
	Settings.refresh_time_scale(SLOW)
	_rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	sub = []
	Settings.slowed = false
	Settings.refresh_time_scale(SLOW)
	closed.emit()


func _exit_tree() -> void:
	# Never leave the whole game in slow motion (or at battle speed) once the mission scene goes.
	Settings.in_battle = false
	Settings.slowed = false
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- rows

func _heroes() -> Array:
	return party.heroes if party else []


func _style_name(style: String) -> String:
	return str(_hero_data.get("styles", {}).get(style, {}).get("name", style.capitalize()))


func _style_desc(style: String) -> String:
	return str(_hero_data.get("styles", {}).get(style, {}).get("desc", ""))


## The Techs tab's second line: which tech the hero charges and how it is used (issues #8, #24).
func _tech_line(h: Hero) -> String:
	var known := Skills.known_techs(h.hero_id)
	if known.is_empty():
		return tr("No charged techs")
	var picked := Skills.picked_tech(h.hero_id)
	if h.controlled:
		var held := (tr("Always %s") % picked.get("name", "?")) if not picked.is_empty() else \
			(tr("%s, hold longer for %d more") % [known[0].get("name", "?"), known.size() - 1] if known.size() > 1 else str(known[0].get("name", "?")))
		return tr("%s  (hold Attack on a full gauge)") % held
	var what := (tr("Always %s") % picked.get("name", "?")) if not picked.is_empty() else \
		(tr("Picks from %d techs") % known.size() if known.size() > 1 else str(known[0].get("name", "?")))
	var mode := AllyTechs.mode_of(h)
	var how := (tr("Auto, ") + str(AllyTechs.PRESET_RULE.get(AllyTechs.preset_of(h), ""))) if mode == "auto" else str(AllyTechs.MODE_NAMES[mode])
	return "%s  (%s, %s)" % [what, how, AllyTechs.state_text(h)]


## What the hero wears, slot by slot, for the Equip tab: "Weapon: Notched Axe  ·  Armor: none  ·  Trinket: none".
func _gear_line(h: Hero) -> String:
	var worn := Progress.gear(h.hero_id)
	var parts := []
	for slot in Progress.SLOTS:
		var item_id := str(worn.get(slot, ""))
		parts.append("%s: %s" % [Loc.t(Progress.SLOT_NAMES[slot]), Progress.item(item_id).get("name", item_id) if item_id != "" else tr("none")])
	return "  ·  ".join(parts)


func _hd(h: Hero) -> Dictionary:
	return _hero_data.get("heroes", {}).get(h.hero_id, {})


## The hero's hotkeyed Ink abilities (issue #7, scripts/abilities.gd).
func _abilities_of(h: Hero) -> Array:
	if not ("abilities" in h) or typeof(h.get("abilities")) != TYPE_ARRAY:
		return []
	return h.get("abilities")


func _abilities_script():
	const PATH := "res://scripts/abilities.gd"
	return load(PATH) if ResourceLoader.exists(PATH) else null


func _ability_blocker(h: Hero, i: int) -> String:
	var ab = _abilities_script()
	return str(ab.blocker(h, i)) if ab else tr("not ready")


## The full gear screen (issue #15), when it exists: the Equip tab hands over to it.
func _open_gear() -> bool:
	const PATH := "res://scripts/gear_view.gd"
	if not ResourceLoader.exists(PATH) or party == null:
		return false
	var gv = load(PATH).new()
	get_parent().add_child(gv)
	gv.party = party
	close()
	# The gear screen doesn't stop the fight itself: pause underneath it (this layer runs while paused).
	get_tree().paused = true
	party.touch.release_all()
	gv.open("mission")
	gv.closed.connect(func():
		if is_inside_tree():
			get_tree().paused = false
		gv.queue_free())
	return true


## The Tree tab's right-hand note: points to spend, or how much is learned.
func _tree_right(id: String) -> String:
	var free := SkillTree.points_free(id)
	if SkillTree.can_spend(id):
		return tr("%d Skill Point%s to spend") % [free, "" if free == 1 else "s"]
	return tr("%d/%d nodes") % [SkillTree.learned(id).size(), SkillTree.all_nodes(id).size()]


## The Tree tab's second line: how far along each branch the hero is.
func _tree_line(id: String) -> String:
	var parts := []
	for b in SkillTree.branches(id):
		var done := (b["nodes"] as Array).filter(func(n): return SkillTree.knows(id, str(n["id"]))).size()
		parts.append("%s %d/%d" % [b.get("name", "?"), done, (b["nodes"] as Array).size()])
	return "  ·  ".join(parts) + tr("  (pick to open the tree)")


## The skill tree screen (issue #25) over the fight, paused underneath until it closes.
func _open_tree(hero_id: String) -> void:
	if party == null:
		return
	var tv := SkillTreeView.new()
	get_parent().add_child(tv)
	tv.party = party
	close()
	get_tree().paused = true
	party.touch.release_all()
	tv.open("mission", hero_id)
	tv.closed.connect(func():
		if is_inside_tree():
			get_tree().paused = false
		tv.queue_free())


## The options screen (issue #14) over the fight, which stays paused underneath until it closes.
func _open_options() -> void:
	close()
	get_tree().paused = true
	party.touch.release_all()
	OptionsView.popup(get_parent()).closed.connect(func():
		if is_inside_tree():
			get_tree().paused = false)


func _rebuild() -> void:
	rows = []
	match TABS[tab]:
		"Items":
			if Satchel.carried().is_empty():
				rows.append({"id": "", "label": tr("The satchel is empty"), "right": "%d/%d" % [Armory.satchel_total(), Armory.satchel_slots()],
					"detail": tr("Pack it in town: Forge & Market, Satchel tab."), "enabled": true, "info": true})
			for id in Satchel.carried():  # issue #112: only what is packed
				var it := Satchel.item(id)
				var why := Satchel.blocker(id, _heroes())
				rows.append({"id": id, "icon": id, "label": str(it.get("name", id)), "right": "x%d" % Satchel.count(id),
					"detail": str(it.get("desc", "")) if why == "" else "%s  (%s)" % [it.get("desc", ""), why],
					"enabled": why == ""})
		"Abilities":
			for h in _heroes():
				var hero: Hero = h
				var list := _abilities_of(hero)
				if list.is_empty():  # a hero with no Ink abilities in data/heroes.json fights with Attack and their tech
					rows.append({"id": hero.hero_id, "label": hero.hero_name, "right": tr("No Ink abilities"),
						"detail": str(_hd(hero).get("special", "")), "enabled": true, "info": true})
				else:
					var ink := tr("Ink %d/%d") % [int(hero.get("ink")), int(hero.get("max_ink"))]
					rows.append({"id": hero.hero_id, "label": hero.hero_name + (tr("  (down)") if hero.dead else ""), "right": ink,
						"detail": ", ".join(list.map(func(a): return str(a.get("name", "?")))), "enabled": not hero.dead, "hero": hero})
		"Techs":  # issue #24: weapon skill level, which tech, and orders for allies
			for h in _heroes():
				var hero: Hero = h
				var state := tr("  (down)") if hero.dead else (tr("  (you)") if hero.controlled else "")
				rows.append({"id": hero.hero_id, "label": "%s%s" % [hero.hero_name, state],
					"right": tr("%s Lv %d  %d/%d techs") % [Skills.weapon_name(hero.hero_id), Skills.weapon_level(hero.hero_id),
						Skills.known_techs(hero.hero_id).size(), Skills.all_techs(hero.hero_id).size()],
					"detail": _tech_line(hero), "enabled": true, "hero": hero})
		"Tree":  # issue #25: Skill Points to spend; picking a hero opens their tree (the fight pauses)
			for h in _heroes():
				var hero: Hero = h
				rows.append({"id": hero.hero_id, "label": hero.hero_name + (tr("  (down)") if hero.dead else ""),
					"right": _tree_right(hero.hero_id), "detail": _tree_line(hero.hero_id), "enabled": true, "hero": hero})
		"Party":
			for h in _heroes():
				var hero: Hero = h
				var state := tr("  (down)") if hero.dead else (tr("  (you)") if hero.controlled else "")
				rows.append({"id": hero.hero_id, "label": hero.hero_name + state, "right": tr("AI: ") + _style_name(hero.ai_style),
					"detail": _style_desc(hero.ai_style), "enabled": true, "hero": hero})
		"Equip":
			for h in _heroes():
				var hero: Hero = h
				rows.append({"id": hero.hero_id, "label": tr("%s  Lv %d") % [hero.hero_name, Progress.level(hero.hero_id)],
					"right": tr("DMG %d  Reach %d") % [hero.base_damage, int(hero.reach)],
					"detail": _gear_line(hero), "enabled": true, "info": true})
		"Options":  # issue #14: a summary here, the full screen one press away
			rows.append({"id": "speed", "label": tr("Battle speed"), "right": Settings.battle_speed_name(),
				"detail": tr("Pick to open Options"), "enabled": true})
			rows.append({"id": "difficulty", "label": tr("Difficulty"), "right": Loc.t(Settings.DIFFICULTIES[Settings.difficulty]),
				"detail": Loc.t(Settings.DIFFICULTY_INFO[Settings.difficulty]), "enabled": true})
			rows.append({"id": "more", "label": tr("All options"), "right": tr("text, shake, sound, controls"),
				"detail": "", "enabled": true})
	sel = clampi(sel, 0, maxi(rows.size() - 1, 0))
	if not rows.is_empty() and not rows[sel].get("enabled", true):
		_move(1)


func _set_tab(i: int) -> void:
	tab = posmod(i, TABS.size())
	sub = []
	sel = 0
	_top = 0
	_follow = true
	_rebuild()


func _move(step: int) -> void:
	_follow = true
	if sub.size() > 0:
		for n in sub.size():
			sub_sel = posmod(sub_sel + step, sub.size())
			if sub[sub_sel].get("enabled", true):
				return
		return
	for n in rows.size():
		sel = posmod(sel + step, rows.size())
		if rows[sel].get("enabled", true):
			return


func _say(s: String) -> void:
	note = s
	note_t = 2.5


## First press: act on the row (or open its short list).
func _pick_row(i: int) -> void:
	if i < 0 or i >= rows.size():
		return
	var r: Dictionary = rows[i]
	sel = i
	if not r.get("enabled", true):
		return
	if TABS[tab] == "Equip" and _open_gear():
		return
	if TABS[tab] == "Tree":
		_open_tree(str(r["id"]))
		return
	if TABS[tab] == "Options":
		_open_options()
		return
	if TABS[tab] == "Items" and str(r.get("id", "")) == "":
		_say(tr("Nothing packed. The Forge & Market screen's Satchel tab packs it before a mission."))
		return
	if r.get("info", false) or (TABS[tab] == "Abilities" and not r.has("hero")):
		_say(tr("%s has no Ink abilities: Attack, and the charged tech on a full gauge.") % r.get("label", "") if TABS[tab] == "Abilities" else tr("The gear screen can't open right now."))
		return
	match TABS[tab]:
		"Items":
			var id: String = r["id"]
			if not Satchel.needs_target(id):  # party items and throwables (issue #112)
				_use_item(id, null)
				return
			sub_title = tr("Use %s on") % Satchel.item(id).get("name", id)
			sub = []
			var best := -1
			var best_ratio := 2.0
			for h in _heroes():
				var hero: Hero = h
				var ok := Satchel.can_target(id, hero)
				var ails := Status.active(hero).filter(func(a): return a[0] in Status.AILMENTS).map(func(a): return Status.name_of(a[0]))
				var right := Loc.t("down") if hero.dead else (tr("Ink %d/%d") % [int(hero.ink), int(hero.max_ink)] if str(Satchel.item(id).get("target", "")) == "ink" else tr("HP %d/%d") % [hero.hp, hero.max_hp])
				if not ails.is_empty() and not hero.dead:
					right += "  " + ", ".join(ails)
				sub.append({"id": "item:%s:%d" % [id, sub.size()], "label": hero.hero_name, "right": right, "enabled": ok})
				var ratio := float(hero.hp) / float(hero.max_hp)
				if ok and ratio < best_ratio:  # start on whoever needs it most
					best_ratio = ratio
					best = sub.size() - 1
			sub_sel = maxi(best, 0)
		"Abilities":
			var hero: Hero = r["hero"]
			sub_title = hero.hero_name
			sub = []
			var list := _abilities_of(hero)
			for i2 in list.size():
				var why := _ability_blocker(hero, i2)
				sub.append({"id": "ability:%d" % i2, "icon": str(list[i2].get("id", "")), "label": str(list[i2].get("name", "?")),
					"right": (tr("%d Ink") % int(list[i2].get("cost", 0))) if why == "" else why, "enabled": why == ""})
			sub_sel = sub.size() - 1
			_move(1)  # first usable one
		"Party":
			var hero: Hero = r["hero"]
			sub_title = hero.hero_name
			sub = [{"id": "lead", "label": tr("Take control"), "right": "",
				"enabled": not hero.dead and not hero.controlled}]
			for style in Hero.AI_STYLES:
				sub.append({"id": "ai:" + style, "label": tr("AI: ") + _style_name(style),
					"right": Loc.t("current") if style == hero.ai_style else "", "enabled": true})
			sub_sel = 0 if sub[0]["enabled"] else 1 + Hero.AI_STYLES.keys().find(hero.ai_style)
		"Techs":
			_tech_sub(r["hero"])


## The Techs tab's short list for one hero: choose by hold length or always one tech (known ones;
## the rest show the weapon level that teaches them), then orders for an ally (scripts/ally_techs.gd).
func _tech_sub(hero: Hero) -> void:
	sub_title = tr("%s: %s Lv %d") % [hero.hero_name, Skills.weapon_name(hero.hero_id), Skills.weapon_level(hero.hero_id)]
	sub = []
	var picked := Skills.pick(hero.hero_id)
	var known := Skills.known_techs(hero.hero_id).size()
	sub.append({"id": "pick:", "label": tr("By hold length"), "right": Loc.t("current") if picked == "" else "", "enabled": known > 0})
	for t in Skills.all_techs(hero.hero_id):
		var lvl := int(t.get("level", 1))
		var ok := lvl <= known
		sub.append({"id": "pick:" + str(t["id"]), "label": str(t.get("name", "?")),
			"right": (tr("current") if picked == t["id"] else tr("%s s") % Loc.dec(Techs.charge_time(t))) if ok else tr("Lv %d") % lvl, "enabled": ok,
			"desc": str(t.get("desc", ""))})
	sub_sel = 0
	for i in sub.size():
		if sub[i]["id"] == "pick:" + picked:
			sub_sel = i
	if known > 0:
		var why := AllyTechs.order_blocker(hero)
		var next := Techs.charge_options(hero)
		var tname := str(next.back().get("name", "tech")) if not picked.is_empty() or next.size() == 1 else tr("best tech")
		sub.append({"id": "tech_now", "label": tr("Unleash ") + tname, "right": why if why != "" else AllyTechs.state_text(hero), "enabled": why == ""})
		for m in AllyTechs.MODES:
			sub.append({"id": "tech:" + m, "label": tr("On its own: ") + str(AllyTechs.MODE_NAMES[m]),
				"right": Loc.t("current") if m == AllyTechs.mode_of(hero) else "", "enabled": true})


## Second press: the choice from the short list.
func _pick_sub(i: int) -> void:
	if i < 0 or i >= sub.size() or not sub[i].get("enabled", true):
		return
	var id: String = sub[i]["id"]
	var r: Dictionary = rows[sel]
	if id.begins_with("item:"):
		var parts := id.split(":")
		_use_item(parts[1], _heroes()[int(parts[2])])
	elif id.begins_with("ability:"):
		var hero: Hero = r["hero"]
		var i3 := int(id.substr(8))
		var ab = _abilities_script()
		if ab and ab.use(hero, i3):
			_say("%s: %s." % [hero.hero_name, _abilities_of(hero)[i3].get("name", "?")])
	elif id == "lead":
		var hero: Hero = r["hero"]
		party.take_control(hero)
		_say(tr("You now control %s.") % hero.hero_name)
	elif id.begins_with("pick:"):
		var hero: Hero = r["hero"]
		var tid := id.substr(5)
		Skills.set_pick(hero.hero_id, tid)
		if hero.charging and not hero.ai_charging:
			Techs.cancel(hero)
		var t := Techs.find(tid)
		_say((tr("%s will charge %s every time (%s s).") % [hero.hero_name, t.get("name", "?"), Loc.dec(Techs.charge_time(t))]) if tid != ""
			else tr("%s: hold Attack longer to reach stronger techs.") % hero.hero_name)
	elif id == "tech_now":
		var hero: Hero = r["hero"]
		AllyTechs.order(hero)
		var tname := str(Techs.current(hero).get("name", "tech")) if not Skills.picked_tech(hero.hero_id).is_empty() else tr("the best tech it knows")
		Fx.damage_number(hero.get_parent(), hero.global_position + Vector2(0, -26), tname + "!", Techs.color_of(hero))
		_say(tr("%s will unleash %s at the best target.") % [hero.hero_name, tname] if hero.power >= 1.0
			else tr("%s will unleash %s once the gauge is full.") % [hero.hero_name, tname])
	elif id.begins_with("tech:"):
		var hero: Hero = r["hero"]
		var mode := id.substr(5)
		AllyTechs.set_mode(hero, mode)
		_say(tr("%s's tech: %s.") % [hero.hero_name, Loc.t(AllyTechs.MODE_NAMES[mode])])
	elif id.begins_with("ai:"):
		var hero: Hero = r["hero"]
		var style := id.substr(3)
		hero.ai_style = style
		hero.ai_target = null
		Empire.ai_presets[hero.hero_id] = style  # sticks for the next mission too
		Fx.damage_number(hero.get_parent(), hero.global_position + Vector2(0, -26), _style_name(style), Color("8fa7e8"))
		_say("%s: %s." % [hero.hero_name, _style_name(style)])
	sub = []
	_rebuild()


func _use_item(id: String, h: Hero) -> void:
	var line := Satchel.use(id, h, _heroes())
	if line != "":
		_say(line)
	sub = []
	_rebuild()


func _back() -> void:
	if sub.size() > 0:
		sub = []
	else:
		close()


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_hover(event.position)
		return
	# A list taller than the screen scrolls under the wheel or a finger; the focus stays put.
	var on_list: bool = sub.is_empty() and "position" in event and _panel.has_point(event.position)
	var steps := Prompts.list_steps(event, _drag, ROW_H, on_list)
	if steps != 0 or event is InputEventScreenDrag:
		if steps != 0:
			_top += steps
			_follow = false
		get_viewport().set_input_as_handled()
		return
	var tap: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		# A finger acts when it lifts without having dragged, so scrolling the list never uses an item.
		var row := _row_at(event.position) if sub.is_empty() else -1
		if event.pressed:
			_drag["down_row"] = row
			tap = row < 0  # tabs, the short list and outside the panel answer at once
		else:
			if row >= 0 and row == int(_drag.get("down_row", -1)) and float(_drag.get("moved", 0.0)) < 8.0:
				_pick_row(row)
			_drag["down_row"] = -1
	if tap:
		_tap(event.position)
	elif event is InputEventScreenTouch or event is InputEventMouseButton:
		pass  # releases
	elif event.is_action_pressed("quick_menu"):
		close()
	elif event.is_action_pressed("pause"):
		close()
		party.set_paused(true)
	elif event.is_action_pressed("ui_cancel"):
		_back()
	elif event.is_action_pressed("ui_down", true):
		_move(1)
	elif event.is_action_pressed("ui_up", true):
		_move(-1)
	elif event.is_action_pressed("ui_accept"):
		if sub.size() > 0:
			_pick_sub(sub_sel)
		else:
			_pick_row(sel)
	elif TabStrip.step(event) != 0:
		_set_tab(tab + TabStrip.step(event))
	elif event.is_action_pressed("move_left"):
		_set_tab(tab - 1)
	elif event.is_action_pressed("move_right"):
		_set_tab(tab + 1)
	# The menu owns all input while it is open: nothing reaches the fight underneath.
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _hover(p: Vector2) -> void:
	if sub.size() > 0:
		for i in _sub_rects.size():
			if (_sub_rects[i] as Rect2).has_point(p) and sub[i].get("enabled", true):
				sub_sel = i
		return
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(p) and rows[i].get("enabled", true):
			sel = i


func _row_at(p: Vector2) -> int:
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(p):
			return i
	return -1


func _tap(p: Vector2) -> void:
	if sub.size() > 0:
		for i in _sub_rects.size():
			if (_sub_rects[i] as Rect2).has_point(p):
				sub_sel = i
				_pick_sub(i)
				return
		if not _sub_panel.has_point(p):
			sub = []  # tapping elsewhere just closes the short list
		return
	var ti := _strip.hit(p)
	if ti >= 0:
		_set_tab(ti)
		return
	for i in _row_rects.size():
		if (_row_rects[i] as Rect2).has_point(p):
			_pick_row(i)
			return
	if not _panel.grow(6).has_point(p):
		close()


# ---------------------------------------------------------------- drawing

func _process(delta: float) -> void:
	if not visible:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	_t += real
	note_t = maxf(note_t - real, 0.0)
	if party and (party.game_over or party.ending):
		close()
		return
	# HP and gauges keep moving underneath (slowly), so refresh what the rows say.
	if sub.is_empty():
		_rebuild()
	queue_redraw()


func _str(font: Font, pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)


func _str_right(font: Font, right_x: float, y: float, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
	draw_string(font, Vector2(right_x - w, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)


func _marker(x: float, y: float) -> void:
	var mx := x + sin(_t * 5.0) * 1.5
	draw_circle(Vector2(mx, y - 4.0), 3.0, GOLD)
	draw_colored_polygon(PackedVector2Array([Vector2(mx - 2.6, y - 5.5), Vector2(mx + 2.6, y - 5.5), Vector2(mx, y - 10.5)]), GOLD)


func _draw() -> void:
	var vs := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, 0.35))
	var w := minf(W, vs.x - 24.0)
	# As many rows as fit on the screen; a longer list scrolls with the focus (or the wheel / a finger).
	var shown := mini(rows.size(), maxi(int((vs.y - 24.0 - 74.0) / ROW_H), 3))
	if _follow:
		_top = clampi(_top, sel - shown + 1, sel)
	_top = clampi(_top, 0, maxi(rows.size() - shown, 0))
	if not _follow and sub.is_empty() and (sel < _top or sel >= _top + shown):
		# Scrolled away from the focus: it moves to the nearest row still in view, so it never hides.
		var order := range(_top, _top + shown) if sel < _top else range(_top + shown - 1, _top - 1, -1)
		for i in order:
			if rows[i].get("enabled", true):
				sel = i
				break
	var h := 44.0 + maxf(shown, 3) * ROW_H + 30.0
	_panel = Rect2((vs.x - w) / 2.0, maxf(12.0, (vs.y - h) / 2.0 - 20.0), w, h)
	UiSkin.panel(self, _panel, "ledger")

	# Tabs across the top.
	_strip.labels = TABS.map(func(t): return Loc.t(t))
	_strip.current = tab
	_strip.draw(self, font, _panel.position + Vector2(8, 6), 10, w - 16)
	draw_line(Vector2(_panel.position.x + 6, _panel.position.y + 27), Vector2(_panel.end.x - 6, _panel.position.y + 27), Color(1, 1, 1, 0.12))

	# Rows.
	_row_rects.clear()
	var y := _panel.position.y + 34.0
	var x0 := _panel.position.x + 22.0
	var x1 := _panel.end.x - 12.0
	for i in rows.size():
		if i < _top or i >= _top + shown:
			_row_rects.append(Rect2())
			continue
		var row: Dictionary = rows[i]
		var on: bool = row.get("enabled", true)
		var rr := Rect2(_panel.position.x + 4, y, w - 8, ROW_H - 2)
		_row_rects.append(rr)
		if i == sel and sub.is_empty():
			draw_rect(rr, Color(1, 1, 1, 0.06))
		var col := (GOLD if i == sel else TEXT) if on else DIM
		var tx := x0
		if UiSkin.draw_icon(self, str(row.get("icon", "")), Rect2(x0, y + 3, 22, 22), Color.WHITE if on else Color(1, 1, 1, 0.45)):
			tx = x0 + 27.0
		_str(font, Vector2(tx, y + 12), str(row["label"]), 11, col)
		_str_right(font, x1, y + 12, str(row.get("right", "")), 10, col if on else DIM)
		_str(font, Vector2(tx, y + 24), str(row.get("detail", "")), 8, Color(0.68, 0.66, 0.64) if on else Color(0.45, 0.45, 0.48))
		if i == sel:
			_marker(x0 - 12.0, y + 12)
		y += ROW_H
	if rows.size() > shown:  # more above or below: small arrows on the frame
		var ax := _panel.end.x - 14.0
		if _top > 0:
			draw_colored_polygon(PackedVector2Array([Vector2(ax - 4, _panel.position.y + 36), Vector2(ax + 4, _panel.position.y + 36), Vector2(ax, _panel.position.y + 31)]), GOLD)
		if _top + shown < rows.size():
			var by := _panel.position.y + 34.0 + shown * ROW_H
			draw_colored_polygon(PackedVector2Array([Vector2(ax - 4, by - 4), Vector2(ax + 4, by - 4), Vector2(ax, by + 1)]), GOLD)

	# Footer: last result, or how to drive it.
	var fy := _panel.end.y - 9.0
	if note_t > 0.0:
		_str(font, Vector2(x0, fy), note, 9, Color("9fe07a"))
	else:
		var hint := tr("Tap a tab or row.  Tap outside to close.") if (party and party.touch_active()) or Prompts.touch() \
			else Prompts.help([["ui_accept", "pick"], ["ui_cancel", "back"], ["quick_menu", "close"]])
		if sub_sel >= 0 and sub_sel < sub.size() and str(sub[sub_sel]["id"]).begins_with("ai:"):
			hint = _style_desc(str(sub[sub_sel]["id"]).substr(3))  # what the highlighted AI preset does (issue #9)
		elif sub_sel >= 0 and sub_sel < sub.size() and str(sub[sub_sel]["id"]).begins_with("tech:"):
			hint = str(AllyTechs.MODE_DESC.get(str(sub[sub_sel]["id"]).substr(5), ""))
		elif sub_sel >= 0 and sub_sel < sub.size() and str(sub[sub_sel]["id"]) == "tech_now":
			hint = tr("Charges as soon as the gauge allows and fires at the best target in reach.")
		elif sub_sel >= 0 and sub_sel < sub.size() and str(sub[sub_sel]["id"]) == "pick:":
			hint = tr("Hold Attack on a full gauge: each tech it knows is ready a little later than the last.")
		elif sub_sel >= 0 and sub_sel < sub.size() and str(sub[sub_sel]["id"]).begins_with("pick:"):
			hint = tr("Charges only this tech, ready after %s s of holding.") % Loc.dec(Techs.charge_time(Techs.find(str(sub[sub_sel]["id"]).substr(5))))
		_str(font, Vector2(x0, fy), hint, 8, DIM)
	_str_right(font, x1, fy, tr("time slowed"), 8, Color(0.7, 0.8, 1.0, 0.6 + 0.3 * sin(_t * 3.0)))

	# The short list a row opened, beside it.
	_sub_rects.clear()
	if sub.size() > 0:
		var sw := 170.0
		# A tech's description sits under the list while it is highlighted (Techs tab).
		var desc := str(sub[sub_sel].get("desc", "")) if sub_sel >= 0 and sub_sel < sub.size() else ""
		var desc_h := font.get_multiline_string_size(desc, HORIZONTAL_ALIGNMENT_LEFT, sw - 20.0, Access.fs(8)).y + 8.0 if desc != "" else 0.0
		var sh := 26.0 + sub.size() * 18.0 + desc_h
		var anchor: Rect2 = _row_rects[sel] if sel < _row_rects.size() else _panel
		var sx := minf(_panel.end.x - sw - 8.0, vs.x - sw - 6.0)
		var sy := clampf(anchor.position.y, 6.0, vs.y - sh - 6.0)
		_sub_panel = Rect2(sx, sy, sw, sh)
		UiSkin.panel(self, _sub_panel, "ledger")
		_str(font, Vector2(sx + 10, sy + 14), sub_title, 9, Color(0.75, 0.73, 0.7))
		var yy := sy + 30.0
		for i in sub.size():
			var s: Dictionary = sub[i]
			var on: bool = s.get("enabled", true)
			var col := (GOLD if i == sub_sel else TEXT) if on else DIM
			_sub_rects.append(Rect2(sx + 2, yy - 13, sw - 4, 17))
			var lx := sx + 20.0
			if UiSkin.draw_icon(self, str(s.get("icon", "")), Rect2(sx + 18, yy - 12, 14, 14), Color.WHITE if on else Color(1, 1, 1, 0.45)):
				lx += 17.0
			_str(font, Vector2(lx, yy), str(s["label"]), 10, col)
			_str_right(font, sx + sw - 8, yy, str(s.get("right", "")), 8, col if on else DIM)
			if i == sub_sel:
				_marker(sx + 10, yy)
			yy += 18.0
		if desc != "":
			draw_multiline_string(font, Vector2(sx + 10, yy - 4), desc, HORIZONTAL_ALIGNMENT_LEFT, sw - 20.0, Access.fs(8), -1, Color(0.78, 0.76, 0.72))
