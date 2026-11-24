extends Node2D
## Prototype: the Frayed Meadow. Builds the area in code, spawns the party
## (picked on the Command Table, Ash leads), Nibblers that crawl out of the Blank, and the HUD.

const HeroScript := preload("res://scripts/hero.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const RECOVER_CLEAR := 150.0  # px: no enemy this close to the leader... (recover assist, issue #192)
const RECOVER_WAIT := 3.0  # ...for this many seconds, and the party heals
const PropScript := preload("res://scripts/prop.gd")
const BlankScript := preload("res://scripts/blank.gd")
const HudScript := preload("res://scripts/hud.gd")
const TouchScript := preload("res://scripts/touch.gd")
const DialogueBox := preload("res://scripts/dialogue_box.gd")
const BanterScript := preload("res://scripts/banter.gd")
const ResultsView := preload("res://scripts/results_view.gd")
const GearViewScript := preload("res://scripts/gear_view.gd")

const TITLE_SCENE := "res://scenes/title.tscn"
const MAX_ENEMIES := 7
const RESPAWN_TIME := 6.0
const AUTOSAVE_EVERY := 60.0

var heroes: Array = []
var leader: Hero
var entities: Node2D
var blank: Blank
var camera: Camera2D
var hud  # hud.gd
var touch  # touch.gd
var area: Area
var world := Vector2.ZERO
var kills := 0
var downs := 0  # heroes who went down this mission (achievements, issue #150)
var shake_amount := 0.0
var respawn_t := 0.0
var blank_tick := 0.0
var game_over := false
var pause_menu: InkMenu
var boosts := {"damage": 0, "hp": 0, "revive": 1.0, "guard": 0.0, "power_rate": 1.0, "ink_regen": 1.0, "lines": []}  # from research
var over_menu: InkMenu
var banter  # banter.gd: walking banter at the top of the screen
var dialogue_box  # dialogue_box.gd: conversations (the game pauses while one plays)
var autosave_t := 3.0  # first autosave a few seconds into a new game
var slot_menu: InkMenu
var slot_mode := ""  # "save" or "load"
var map_path := "res://maps/frayed_meadow.txt"
var mission := {}  # the mission being played (scripts/missions.gd)
var objective: Objective
var found := {}  # what the party picked up on the way: resource -> amount
var found_flash := 0.0  # seconds the HUD's "Found" line stays lit after a pickup
var mission_time := 0.0
var ending := false  # the results screen is up (or about to be)
var results_view  # results_view.gd
var gear_view  # gear_view.gd: Party gear from the pause menu (issue #15)
var journal_view  # journal_view.gd: the journal from the pause menu (issue #114)
var found_items: Array = []  # gear picked up on the way (item ids); kept unless the party is wiped
var levels_gained := {}  # hero id -> level reached during this mission, for the results screen
var skills_gained: Array = []  # "Ash: Quill-knife 3 (Ellipsis)" lines for the results screen (issue #24)
var quick_menu: QuickMenu  # quick_menu.gd: items, abilities, party, equip with time slowed (issue #6)
var quick_open := false  # heroes read this: the menu has the controls while it is up
var skipping := false  # "Skip this fight" (Assists, issue #192): the story's talks play, then the results
var _skip_talks: Array = []
var _calm_t := 0.0  # seconds with no enemy near the leader (the recover assist)
var _recover_acc := 0.0


func _ready() -> void:
	randomize()
	# Which mission: a loaded save brings its own; otherwise the one launched from the map.
	mission = Saves.pending.get("mission", {}) if not Saves.pending.is_empty() else {}
	if mission.is_empty():
		mission = Missions.current()
	Empire.active_mission = mission
	map_path = mission.get("map", map_path)
	objective = Objective.new()
	objective.setup(mission.get("objective", {}), self)

	entities = Node2D.new()
	entities.y_sort_enabled = true
	area = Area.new()
	add_child(area)
	var layout: Dictionary = mission.get("layout", {})  # the map pool's per-mission layout (#113, MissionTypes.vary)
	if layout.has("blank"):
		area.blank_tiles = int(layout["blank"])
	area.build(map_path, entities)
	world = area.world_size()
	if layout.has("spawns"):  # only some of the map's spawn points wake up, so repeat visits differ
		var keep: Array[Vector2] = []
		for t in layout["spawns"]:
			keep.append(Vector2(int(t[0]) * 16 + 8, int(t[1]) * 16 + 8))
		area.spawns = keep
	if mission.get("respawn", true) == false:
		respawn_t = 1e9  # no stream of Nibblers out of the Blank (a raid on faction land)

	blank = Blank.new()
	blank.base_x = area.blank_x
	blank.height = world.y
	blank.width = world.x
	add_child(blank)
	area.blank_edge = blank.edge_x
	Art.set_blank_x(blank.base_x)

	add_child(entities)
	_build_walls()

	var start := area.party_start
	# Whoever was picked on the Command Table (party_picker.gd); Ash always leads.
	# Same body and animation rig for everyone; outfit layer + colors make the hero.
	var offsets := [Vector2.ZERO, Vector2(-20, 14), Vector2(20, 14)]
	var ids := PartyPicker.mission_party(mission)
	for i in ids.size():
		var look: Dictionary = Empire.recruit(ids[i]).get("look", {})
		var h := _make_hero(PartyPicker.short_of(ids[i]), start + offsets[i % offsets.size()],
			look.get("outfit", "archer"), PartyPicker.look_colors(look))
		PartyPicker.apply(h, ids[i])
		h.ai_style = AllyAI.preset_id(str(Empire.ai_presets.get(ids[i], h.ai_style)))  # picked in the quick menu's Party tab
		h.tech_mode = str(Empire.ai_techs.get(ids[i], "auto"))  # charged tech under AI: auto / on my call
	# The Barracks sends the party out tougher; research sharpens and armours them.
	boosts = Empire.mission_boosts()
	Empire.mission_kills_bonded = 0
	for h in heroes:
		h.max_hp += Empire.party_hp_bonus() + int(boosts["hp"])
		h.hp = h.max_hp
		h.base_damage += int(boosts["damage"])
		h.power_rate *= float(boosts["power_rate"])
		h.ink_regen *= float(boosts.get("ink_regen", 1.0))
	_set_leader(heroes[0])

	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world.x)
	camera.limit_bottom = int(world.y)
	add_child(camera)
	camera.global_position = leader.global_position
	camera.reset_smoothing()
	var ambience := Ambience.new()  # art pass: light by the empire clock, lantern, motes
	ambience.party = self
	add_child(ambience)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.party = self
	layer.add_child(hud)
	touch = TouchScript.new()
	touch.party = self
	layer.add_child(touch)
	banter = BanterScript.new()
	banter.gap = 1.0
	layer.add_child(banter)

	# Menus live on their own layer above the HUD and keep running while the tree is paused.
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 5
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	pause_menu = InkMenu.new()
	pause_menu.visible = false
	menu_layer.add_child(pause_menu)
	pause_menu.setup(tr("Paused"), _pause_items(), "")
	pause_menu.chosen.connect(_on_pause_choice)
	slot_menu = InkMenu.new()
	slot_menu.visible = false
	slot_menu.top = 0.2
	menu_layer.add_child(slot_menu)
	slot_menu.chosen.connect(_on_slot_choice)
	over_menu = InkMenu.new()
	over_menu.visible = false
	over_menu.dim = 0.55
	menu_layer.add_child(over_menu)
	over_menu.chosen.connect(_on_over_choice)
	dialogue_box = DialogueBox.new()
	dialogue_box.visible = false
	menu_layer.add_child(dialogue_box)
	dialogue_box.finished.connect(_on_dialogue_finished)
	results_view = ResultsView.new()
	results_view.visible = false
	menu_layer.add_child(results_view)
	results_view.confirmed.connect(_on_results_confirmed)
	gear_view = GearViewScript.new()
	gear_view.visible = false
	gear_view.party = self
	menu_layer.add_child(gear_view)
	gear_view.closed.connect(_on_gear_closed)
	quick_menu = QuickMenu.new()
	quick_menu.party = self
	menu_layer.add_child(quick_menu)
	quick_menu.closed.connect(func(): quick_open = false)

	var loaded := not Saves.pending.is_empty()
	if loaded:
		_apply_snapshot(Saves.pending)
		Saves.pending = {}
		camera.global_position = leader.global_position
		camera.reset_smoothing()
	for p in area.spawns:
		# A loaded game can put the party anywhere: don't drop Nibblers on top of them.
		if not loaded or p.distance_to(leader.global_position) > 120.0:
			_spawn_enemy(p)
	if not loaded:  # the first time out, Bran finds Ash; after that he just grumbles
		var intro := str(mission.get("intro", ""))  # a story mission's opening talk (issue #18)
		if intro != "" and not Dialogue.is_seen("talk:" + intro):
			play_talk(intro)
		elif not Dialogue.is_seen("talk:meadow_intro") and "bran" in present():
			play_talk("meadow_intro")
		else:
			banter.event("mission_start", present())
			banter.add(Relationships.banter_for(present()))  # friends and rivals sniping (issue #116)


## Who can speak right now: the party members still standing.
func present() -> Array:
	return heroes.filter(func(h): return not h.dead).map(func(h): return (h as Hero).hero_id)


## Play a conversation in the dialogue box. The fight waits until it is over.
func play_talk(talk_id: String) -> void:
	if dialogue_box.play(talk_id):
		quick_menu.close()
		get_tree().paused = true
		touch.release_all()


func _on_dialogue_finished(_id: String) -> void:
	get_tree().paused = false
	if skipping and not ending:
		_next_skip_talk()


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	add_child(walls)
	var t := 40.0
	for r in [
		Rect2(-t, -t, world.x + 2 * t, t),
		Rect2(-t, world.y, world.x + 2 * t, t),
		Rect2(-t, 0, t, world.y),
		Rect2(world.x, 0, t, world.y),
	]:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.position + r.size / 2.0
		walls.add_child(col)


func _make_hero(hero_name: String, pos: Vector2, outfit: String, colors: Dictionary) -> Hero:
	var h: Hero = HeroScript.new()
	h.hero_name = hero_name
	h.outfit = outfit
	h.colors = colors
	h.move_speed = 68.0
	h.party = self
	h.position = pos
	h.add_to_group("heroes")
	entities.add_child(h)
	heroes.append(h)
	h.died.connect(_on_hero_died)
	return h


func _spawn_enemy(pos: Vector2) -> void:
	for e in EnemyKinds.spawn(entities, pos, mission):  # the area's roster (#16): data/enemies.json
		e.died.connect(_on_enemy_died)


## The quick menu's Party tab: take control of a standing hero.
func take_control(h: Hero) -> void:
	if h != null and not h.dead and h in heroes:
		_set_leader(h)


func _set_leader(h: Hero) -> void:
	leader = h
	for other in heroes:
		(other as Hero).controlled = other == h


func shake(amount: float) -> void:
	shake_amount = maxf(shake_amount, amount * Settings.shake_scale())  # Options: screen shake
	Rumble.quake(amount)  # boss slams and the biggest blasts rumble the pad too (issue #149); not tied to the shake option


func touch_active() -> bool:
	return touch != null and touch.visible


func _on_enemy_died(_e: Actor) -> void:
	kills += 1
	TreePerks.enemy_died(_e)  # poison kills pay the poisoner's skill tree rewards (issue #25)
	Journal.defeated(Journal.kind_of(_e))  # the codex learns its weakness (issue #114)
	Empire.bond_fought(kills, heroes.map(func(h): return (h as Hero).hero_id))  # fighting beside Ash builds bonds
	banter.event("first_kill", present())
	if not ending:
		objective.on_kill()
		var got := Missions.roll_loot(mission)
		for k in got:
			found[k] = int(found.get(k, 0)) + int(got[k])
		if not got.is_empty():
			found_flash = 1.5
			Audio.sfx("coin")
		var item := Satchel.roll_drop()  # field items go straight into the satchel, or home if it's full
		if item != "":
			if Satchel.add(item):
				hud.say(tr("Found: %s (quick menu).") % Satchel.item(item).get("name", item), 2.0)
			else:
				found[item] = int(found.get(item, 0)) + 1
				found_flash = 1.5
				hud.say(tr("Found: %s. The satchel is full: it goes to the stores.") % Satchel.item(item).get("name", item), 2.5)
		var mats := Armory.roll_mats(Journal.kind_of(_e), mission)  # Forge materials (issue #112)
		for k in mats:
			found[k] = int(found.get(k, 0)) + int(mats[k])
			found_flash = 1.5
			Fx.damage_number(entities, (_e as Node2D).global_position + Vector2(0, -20), Armory.mat_name(k), Color("c8d8a8"))
		var tooth := Status.enemy_fell(_e as Node2D, heroes)  # Inkblot Brooch, Gilt Tooth
		if tooth > 0:
			found["gilt"] = int(found.get("gilt", 0)) + tooth
			found_flash = 1.5
	if kills == 10:
		banter.event("tenth_kill", present())
	_award_xp(int(_e.get("xp")) if _e.get("xp") != null else 0)
	if not ending:
		var drop := Progress.roll_drop(mission)
		if drop != "":
			found_items.append(drop)
			found_flash = 1.5
			Fx.damage_number(entities, _e.global_position + Vector2(0, -24), Progress.item(drop)["name"], Color("ffe7a3"))
			hud.say(tr("Found %s! It goes in the bag when you get home.") % Progress.item(drop)["name"], 3.0)


## Shared XP for the whole party (issue #15). Level-ups take effect on the spot.
func _award_xp(amount: int) -> Array:
	var ups := Progress.award(heroes.map(func(h): return (h as Hero).hero_id), amount)
	if not ups.is_empty():
		Audio.sfx("levelup")
	for up in ups:
		for h in heroes:
			var hero: Hero = h
			if hero.hero_id != up["id"]:
				continue
			Progress.apply_delta(hero, {}, up["gains"])
			levels_gained[hero.hero_id] = up["level"]
			Fx.damage_number(entities, hero.global_position + Vector2(0, -26), tr("LEVEL %d") % up["level"], Color("ffd166"))
			Fx.burst(entities, hero.global_position + Vector2(0, -10), [Color("ffd166"), Color.WHITE], 18, 60.0)
			hud.say(tr("%s reached level %d: %s, +1 Skill Point (skill tree in the quick menu)") % [hero.hero_name, up["level"], Progress.gains_text(up["gains"])], 3.5)
	return ups


## A weapon or Ink skill went up mid-fight (Hero.gain_skill, scripts/skills.gd): a toast over the hero,
## a line on the banner and a chime. A weapon level teaches a tech; Ink levels 2 and 4 raise a tier.
func skill_up(hero: Hero, kind: String, color: String, level: int) -> void:
	var line := ""
	var label := ""
	var col := Color("ffd166")
	if kind == "weapon":
		var t := Skills.tech_at(hero.hero_id, level)
		label = "%s %d" % [Skills.weapon_name(hero.hero_id).to_upper(), level]
		col = Color(str(t.get("color", "ffd166")))
		line = tr("%s's %s skill reached %d: learned %s. Hold Attack longer on a full gauge to reach it.") % [
			hero.hero_name, Skills.weapon_name(hero.hero_id), level, t.get("name", tr("a new tech"))]
		skills_gained.append("%s: %s %d (%s)" % [hero.hero_name, Skills.weapon_name(hero.hero_id), level, t.get("name", "")])
	else:
		label = tr("%s INK %d") % [Skills.ink_name(color).to_upper(), level]
		col = Skills.ink_color(color)
		var what := Skills.ink_level_text(level)
		var names := hero.abilities.filter(func(a): return str(a.get("ink", "")) == color).map(func(a): return str(a.get("name", "")))
		if what != "" and not names.is_empty():
			line = tr("%s's %s Ink reached %d: %s for %s.") % [hero.hero_name, Skills.ink_name(color), level, what, Loc.list(names)]
		else:
			line = tr("%s's %s Ink reached %d.") % [hero.hero_name, Skills.ink_name(color), level]
		skills_gained.append(tr("%s: %s Ink %d") % [hero.hero_name, Skills.ink_name(color), level])
	Fx.damage_number(entities, hero.global_position + Vector2(0, -34), label, col.lightened(0.3))
	Fx.burst(entities, hero.global_position + Vector2(0, -10), [col, col.lightened(0.5), Color.WHITE], 20, 70.0)
	Audio.sfx("levelup", 1.25)
	hud.say(line, 4.0)


## The journal from the pause menu (issue #114), made the first time it is asked for. The map is out of
## reach mid-mission, so "show on map" waits until the party is home.
func _journal() -> Control:
	if journal_view == null:
		journal_view = preload("res://scripts/journal_view.gd").new()
		journal_view.visible = false
		journal_view.can_go = false
		pause_menu.get_parent().add_child(journal_view)
		journal_view.closed.connect(_on_gear_closed)
	return journal_view


func _on_gear_closed() -> void:
	if get_tree().paused and not ending:
		pause_menu.set_deferred("visible", true)  # next frame, so the same Esc doesn't also close it


func _on_hero_died(a: Actor) -> void:
	downs += 1
	var alive := heroes.filter(func(h): return not h.dead)
	if alive.is_empty():
		game_over = true
		get_tree().create_timer(1.2).timeout.connect(_show_game_over)
		return
	if a == leader:
		_set_leader(alive[0])
		hud.say(tr("%s is down! You now control %s.") % [(a as Hero).hero_name, leader.hero_name], 3.0)


func _show_game_over() -> void:
	if ending:
		return
	var has_auto := Saves.exists("auto")
	over_menu.setup(tr("The party was erased."), [
		{"id": "retry", "label": tr("Try again"), "detail": tr("from the last autosave") if has_auto else tr("from the start of the area")},
		{"id": "retreat", "label": tr("Limp back to Hollowmark"), "detail": tr("end the mission and drop what you found")},
		{"id": "load", "label": tr("Load game"), "enabled": Saves.latest_slot() != ""},
		{"id": "title", "label": tr("Quit to title")},
	], tr("The Blank does not keep receipts."))
	over_menu.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not game_over and not ending:
		set_paused(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("swap") and not game_over:
		_swap()
	if event.is_action_pressed("quick_menu"):
		open_quick_menu()


## One button opens the quick menu mid-fight; time slows to 10% instead of stopping.
func open_quick_menu() -> void:
	if game_over or ending or get_tree().paused or quick_open:
		return
	touch.release_all()
	quick_open = true
	quick_menu.open()


func set_paused(on: bool) -> void:
	if on:
		quick_menu.close()
	get_tree().paused = on
	pause_menu.visible = on
	slot_menu.visible = false
	if on:
		pause_menu.setup(tr("Paused"), _pause_items(), "")
		touch.release_all()


func _pause_items() -> Array:
	return [
		{"id": "resume", "label": tr("Resume")},
		{"id": "gear", "label": tr("Party gear"), "detail": tr("levels and equipment")},
		{"id": "journal", "label": tr("Journal"), "detail": tr("quests, people, codex, history")},
		{"id": "help", "label": tr("Help"), "detail": tr("explainers, field notes and controls")},
		{"id": "report", "label": tr("Report a bug"), "detail": tr("or send feedback")},
	] + Survey.menu_items() + [  # playtest builds only (issue #168)
		{"id": "save", "label": tr("Save game")},
		{"id": "load", "label": tr("Load game"), "enabled": Saves.latest_slot() != "", "note": tr("(no saves yet)")},
		{"id": "retreat", "label": tr("Retreat to Hollowmark"), "detail": tr("end the mission, keep what you found")},
	] + _skip_items() + [
		{"id": "restart", "label": tr("Restart mission")},
		{"id": "options", "label": tr("Options")},
		{"id": "title", "label": tr("Quit to title")},
	]


## "Skip this fight" in story missions, when the assist is on (issue #192).
func _skip_items() -> Array:
	if not can_skip():
		return []
	return [{"id": "skip", "label": tr("Skip this fight"), "detail": tr("the story's conversations still play")}]


func can_skip() -> bool:
	Assists.load_settings()
	return Assists.skip_fights and bool(mission.get("story", false)) and not ending and not game_over and not skipping


## Skips the fight: any conversation the fight would have played and has not yet (a boss's opening,
## turn and last words) plays now, then the mission ends as won, with the full rewards.
func skip_fight() -> void:
	if not can_skip():
		return
	skipping = true
	set_paused(false)
	_skip_talks = []
	var inner = objective.inner
	if inner != null and inner.has_method("_talk_id"):
		for part in ["intro", "phase2", "outro"]:
			var tid: String = inner._talk_id(part)
			if not Dialogue.is_seen("talk:" + tid):
				_skip_talks.append(tid)
	_next_skip_talk()


func _next_skip_talk() -> void:
	while not _skip_talks.is_empty():
		var tid: String = _skip_talks.pop_front()
		if dialogue_box.play(tid):
			quick_menu.close()
			get_tree().paused = true
			touch.release_all()
			return
	ending = true
	hud.say(tr("Fight skipped."), 2.0)
	get_tree().create_timer(0.8).timeout.connect(_show_results.bind("success"))


func _on_pause_choice(id: String) -> void:
	match id:
		"skip":
			skip_fight()
		"resume", "cancel":
			set_paused(false)
		"save", "load":
			_open_slots(id, pause_menu)
		"gear":
			pause_menu.visible = false
			gear_view.open("mission")
		"journal":
			pause_menu.visible = false
			_journal().open()
		"help":  # issue #115
			pause_menu.visible = false
			HelpView.popup(self).closed.connect(_on_gear_closed)
		"report":  # issue #146
			pause_menu.visible = false
			FeedbackView.popup(self).closed.connect(func(): pause_menu.visible = true)
		"survey":  # issue #168
			pause_menu.visible = false
			SurveyView.popup(self).closed.connect(func(): pause_menu.visible = true)
		"retreat":
			pause_menu.visible = false
			_end_mission("retreat")
		"restart":
			get_tree().paused = false
			get_tree().reload_current_scene()
		"options":
			pause_menu.visible = false
			OptionsView.popup(self).closed.connect(func(): pause_menu.visible = true)
		"title":
			autosave()
			get_tree().paused = false
			get_tree().change_scene_to_file(TITLE_SCENE)


func _on_over_choice(id: String) -> void:
	match id:
		"retry":
			if not Saves.load_and_play("auto"):
				get_tree().reload_current_scene()
		"retreat":
			over_menu.visible = false
			_end_mission("wiped")
		"load":
			_open_slots("load", over_menu)
		"title":
			get_tree().change_scene_to_file(TITLE_SCENE)


var _slot_return: InkMenu


func _open_slots(mode: String, from: InkMenu) -> void:
	slot_mode = mode
	_slot_return = from
	from.visible = false
	slot_menu.setup(tr("Save to which slot?") if mode == "save" else tr("Load which save?"), Saves.slot_items(mode == "save"))
	slot_menu.visible = true


func _on_slot_choice(id: String) -> void:
	if id == "back" or id == "cancel":
		slot_menu.visible = false
		_slot_return.visible = true
		return
	if slot_mode == "load":
		Saves.load_and_play(id)
		return
	var ok := Saves.save(id, snapshot())
	slot_menu.visible = false
	_slot_return.visible = true
	pause_menu.setup(tr("Paused"), _pause_items(), (tr("Saved to %s.") % Saves.slot_label(id)) if ok else tr("Saving failed. Your browser may be blocking storage."))
	pause_menu.selected = 0


# ---------------------------------------------------------------- saving

## Everything needed to put the player back where they were. Enemies are not saved:
## the area's Nibblers respawn on load, like any action RPG's screen refresh.
func snapshot() -> Dictionary:
	var hs := []
	for h in heroes:
		var hero: Hero = h
		hs.append({"name": hero.hero_name, "hp": hero.hp, "x": hero.global_position.x, "y": hero.global_position.y,
			"dead": hero.dead, "power": hero.power, "ink": hero.ink})
	return {
		"map": map_path,
		"area_name": area.area_name,
		"scene": "res://scenes/main.tscn",
		"mission": mission,
		"objective": objective.to_save(),
		"found": found,
		"found_items": found_items,
		"mission_time": mission_time,
		"kills": kills,
		"downs": downs,
		"leader": heroes.find(leader),
		"heroes": hs,
		"banter": banter.to_save(),
	}


func _apply_snapshot(d: Dictionary) -> void:
	kills = int(d.get("kills", 0))
	downs = int(d.get("downs", 0))
	objective.from_save(d.get("objective", {"progress": kills}))
	mission_time = float(d.get("mission_time", 0.0))
	var f: Dictionary = d.get("found", {})
	for k in f:
		found[k] = int(f[k])
	banter.from_save(d.get("banter", []))
	found_items = (d.get("found_items", []) as Array).filter(func(i): return not Progress.item(str(i)).is_empty())
	var hs: Array = d.get("heroes", [])
	for i in mini(hs.size(), heroes.size()):
		var hero: Hero = heroes[i]
		var hd: Dictionary = hs[i]
		hero.global_position = Vector2(float(hd["x"]), float(hd["y"]))
		hero.hp = clampi(int(hd["hp"]), 0, hero.max_hp)
		hero.power = float(hd.get("power", 1.0))
		hero.ink = clampf(float(hd.get("ink", hero.max_ink)), 0.0, hero.max_ink)
		if bool(hd.get("dead", false)) or hero.hp <= 0:
			hero.hp = 0
			hero.dead = true
			hero._on_death()
	var li := int(d.get("leader", 0))
	if li >= 0 and li < heroes.size() and not heroes[li].dead:
		_set_leader(heroes[li])
	autosave_t = AUTOSAVE_EVERY
	hud.say(tr("Loaded. The Blank kept your place."), 2.5)


## Autosaves only when it is safe to drop back in: nobody down and no Nibbler close.
func can_autosave() -> bool:
	if game_over or ending or leader == null:
		return false
	for h in heroes:
		if (h as Hero).dead:
			return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node2D).global_position.distance_to(leader.global_position) < 110.0:
			return false
	return true


func autosave() -> void:
	if can_autosave():
		Saves.save("auto", snapshot())


## The window lost focus and the player wants the game paused then (DisplaySettings, issue #145):
## open the pause menu like the pause key does, so coming back lands on Resume, not mid-swing.
func pause_for_focus_loss() -> void:
	if not game_over and not ending and not get_tree().paused:
		set_paused(true)


func _notification(what: int) -> void:
	# Switching away from the tab (or closing it) usually blurs the page first.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()


func _swap() -> void:
	var idx := heroes.find(leader)
	for i in range(1, heroes.size()):
		var h: Hero = heroes[(idx + i) % heroes.size()]
		if not h.dead:
			_set_leader(h)
			return


func _process(delta: float) -> void:
	# The touch Swap button presses the action directly, which _unhandled_input does not see.
	if touch_active() and Input.is_action_just_pressed("swap") and not game_over:
		_swap()
	if touch_active() and Input.is_action_just_pressed("pause") and not game_over and not get_tree().paused:
		set_paused(true)
	if touch_active() and Input.is_action_just_pressed("quick_menu"):
		open_quick_menu()

	if camera and leader:
		camera.global_position = leader.global_position + Vector2(0, -10)
		camera.position_smoothing_speed = Access.follow_speed(7.0)  # reduce camera motion (issue #192)
		shake_amount = maxf(shake_amount - 20.0 * delta, 0.0)
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amount

	Empire.playtime += minf(delta, Empire.MAX_TICK)  # not the hours a suspended Deck slept (issue #149)
	autosave_t -= delta
	if autosave_t <= 0.0:
		if can_autosave():
			autosave()
			autosave_t = AUTOSAVE_EVERY
		else:
			autosave_t = 5.0  # try again soon, once things calm down
	_update_mission(delta)
	_update_blank_contact(delta)
	_update_revive(delta)
	_update_recover(delta)
	_update_respawn(delta)
	_update_banter(delta)
	_update_signs()


# ---------------------------------------------------------------- mission flow

func _update_mission(delta: float) -> void:
	found_flash = maxf(found_flash - delta, 0.0)
	if ending or game_over:
		return
	mission_time += delta
	objective.update(delta)
	if objective.done():
		ending = true
		hud.say(tr("Objective complete!"), 2.0)
		banter.event("mission_won", present())
		get_tree().create_timer(1.6).timeout.connect(_show_results.bind("success"))
	elif objective.failed():
		ending = true
		get_tree().create_timer(1.2).timeout.connect(_show_results.bind("wiped"))


## Ends the mission now: retreat from the pause menu, or the wiped party limping home.
func _end_mission(outcome: String) -> void:
	ending = true
	_show_results(outcome)


func _show_results(outcome: String) -> void:
	if not is_inside_tree():
		return
	quick_menu.close()
	get_tree().paused = true
	touch.release_all()
	var r := Missions.settle(mission, outcome, found, {"kills": kills, "downs": downs, "skipped": skipping, "time": mission_time, "objective": objective.text(), "fail": objective.fail_text(), "info": objective.info()})
	_progress_lines(r, outcome)
	results_view.open(r)


## XP, level-ups and gear found, for the results screen (issue #15).
func _progress_lines(r: Dictionary, outcome: String) -> void:
	var lines: Array = r.get("lines", [])
	if skipping and outcome == "success":
		lines.append(tr("Fight skipped."))
	if outcome == "success":
		var xp := Progress.mission_xp(mission)
		_award_xp(xp)
		lines.append(tr("+%d XP each for finishing the job.") % xp)
	if not levels_gained.is_empty():
		var parts := []
		for id in levels_gained:
			parts.append(tr("%s Lv %d") % [PartyPicker.short_of(id), levels_gained[id]])
		lines.append(tr("Level up: %s.") % ", ".join(parts))
	if not skills_gained.is_empty():
		lines.append(tr("Skills: %s.") % ", ".join(skills_gained))
		skills_gained = []
	if not found_items.is_empty():
		var names := found_items.map(func(i): return Progress.item(i)["name"])
		if outcome == "wiped":
			lines.append(tr("Lost on the way: %s.") % ", ".join(names))
		else:
			for i in found_items:
				Progress.add_item(i)
			var gk := Prompts.key("gear")
			lines.append((tr("Gear for the bag: %s (equip with %s).") % [", ".join(names), gk]) if gk != "" else tr("Gear for the bag: %s.") % ", ".join(names))
		found_items = []
	r["lines"] = lines


func _on_results_confirmed() -> void:
	Journal.record_mission(results_view.result)  # History tab (issue #114)
	Missions.go_home(results_view.result)


func _update_blank_contact(delta: float) -> void:
	blank_tick -= delta
	for h in heroes:
		var hero: Hero = h
		if hero.dead:
			continue
		var edge := blank.edge_x(hero.global_position.y)
		if hero.global_position.x > edge - 4.0:
			hero.knockback = Vector2(-160, 0)
			if blank_tick <= 0.0 and not Status.has(hero, "ward"):  # a Ward Candle keeps the edge from biting (issue #112)
				hero.invuln_t = 0.0
				hero.take_hit(3, hero.global_position + Vector2(10, 0), 160.0)
				if hero == leader:
					hud.say(tr("The Blank bites. It does not want you back. Yet."), 2.5)
	if blank_tick <= 0.0:
		blank_tick = 0.6


func _update_revive(delta: float) -> void:
	if leader == null or leader.dead:
		return
	var enemies_near := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node2D).global_position.distance_to(leader.global_position) < 110.0:
			enemies_near = true
			break
	for h in heroes:
		var hero: Hero = h
		if not hero.dead:
			continue
		if not enemies_near and hero.global_position.distance_to(leader.global_position) < 28.0:
			hero.revive_progress += delta * float(boosts["revive"]) * TreePerks.revive_mult(hero, heroes)  # + skill trees (#25)
			if hero.revive_progress >= Hero.REVIVE_TIME:
				hero.revive()
				hud.say(tr("%s is back on their feet.") % hero.hero_name, 2.5)
		else:
			hero.revive_progress = maxf(hero.revive_progress - delta, 0.0)


## The recover assist (issue #192): a few seconds with no enemy near the leader and the living heroes'
## health fills back up, a quarter of it a second.
func _update_recover(delta: float) -> void:
	if not Assists.recover or leader == null or leader.dead or ending or game_over:
		_calm_t = 0.0
		return
	var near := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node2D).global_position.distance_to(leader.global_position) < RECOVER_CLEAR:
			near = true
			break
	_calm_t = 0.0 if near else _calm_t + delta
	if _calm_t < RECOVER_WAIT:
		return
	_recover_acc += delta * 0.25
	if _recover_acc < 0.05:
		return
	for h in heroes:
		var hero: Hero = h
		if not hero.dead and hero.hp < hero.max_hp:
			hero.hp = mini(hero.max_hp, hero.hp + maxi(1, roundi(hero.max_hp * _recover_acc)))
	_recover_acc = 0.0


func _update_respawn(delta: float) -> void:
	if respawn_t > 1e8:
		return
	var count := get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.is_queued_for_deletion()).size()
	if count >= MAX_ENEMIES:
		return
	respawn_t -= delta
	if respawn_t <= 0.0:
		respawn_t = RESPAWN_TIME
		var y := randf_range(80, world.y - 80)
		_spawn_enemy(Vector2(blank.edge_x(y) - 16.0, y))


func _update_banter(_delta: float) -> void:
	if game_over:
		return
	if leader and leader.power < 0.5 and leader.swing_t > 0.0 and leader.swing_power < 0.5:
		banter.event("low_power", present())
	if leader:
		banter.check_zones(map_path.get_file().get_basename(), leader.global_position, present())


func _update_signs() -> void:
	var txt := ""
	if leader:
		for p in area.props:
			if p.kind == "sign" and (p as Node2D).global_position.distance_to(leader.global_position) < 34.0:
				txt = p.text
	hud.sign_text = txt
