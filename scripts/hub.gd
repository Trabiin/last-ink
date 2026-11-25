extends Node2D
## Hollowmark, the walkable hub town. Ash walks around, the people on your roster stand at
## their posts (and move when you reassign them), and the Command Table opens the territory map.
##
## The Command clock keeps running here: time in town is time the Blank gets to work.
## No fighting in town: the attack button talks and uses things instead.

const HeroScript := preload("res://scripts/hero.gd")
const HudScript := preload("res://scripts/hub_hud.gd")
const TouchScript := preload("res://scripts/touch.gd")
const RosterView := preload("res://scripts/roster_view.gd")
const BuildingsView := preload("res://scripts/buildings_view.gd")
const ExpeditionView := preload("res://scripts/expedition_view.gd")
const ResearchView := preload("res://scripts/research_view.gd")
const DiplomacyView := preload("res://scripts/diplomacy_view.gd")
const BondsView := preload("res://scripts/bonds_view.gd")
const GearViewScript := preload("res://scripts/gear_view.gd")
const NewcomersView := preload("res://scripts/newcomers_view.gd")
const SceneView := preload("res://scripts/scene_view.gd")
const SiteScript := preload("res://scripts/building_site.gd")
const DialogueBox := preload("res://scripts/dialogue_box.gd")
const ChapterCard := preload("res://scripts/chapter_card.gd")
const JournalView := preload("res://scripts/journal_view.gd")
const BanterScript := preload("res://scripts/banter.gd")

const MAP := "res://maps/hollowmark.txt"
static var map_override := ""  # tools/shot.gd map=<name>: show another town layout (art mockups)
const TITLE_SCENE := "res://scenes/title.tscn"
const AUTOSAVE_EVERY := 60.0
const TALK_RANGE := 26.0
const TABLE_SIZE := Vector2(46, 26)  # the Command Table's "use" area (its collision is data/footprints.json)
var table_art: Texture2D = preload("res://assets/props/command_table.png")
const LAMP_FLAME_Y := 10.0  # lantern centre, from the top of the Wardlamp sprite
## What staff say about their building when you talk to them, before what it is doing right now.
const STAFF_LINES := {
	"command_table": "Every order crosses this table. I make sure fewer of them cost bread.",
	"barracks": "Up, down, up, down. They hate me. They'll live longer.",
	"infirmary": "Hold still. This will hurt, which is how you know it's working.",
	"inkworks": "Soot, gall, a little blood. Don't ask whose.",
	"scriptorium": "The margins are where the truth hides. I'm writing it down before the Blank does.",
	"guildhall": "Everybody wants something done and nobody wants to do it. That's my cut.",
}

var heroes: Array = []  # just Ash: in town you walk alone
var leader: Hero
var npcs := {}  # recruit id -> Hero (standing, not controlled)
var entities: Node2D
var camera: Camera2D
var area: Area
var world := Vector2.ZERO
var hud  # hub_hud.gd
var touch  # touch.gd
var roster_view
var buildings_view
var expedition_view
var research_view
var diplomacy_view
var bonds_view
var gear_view  # gear_view.gd: party gear and the shop (issue #15)
var armory_view  # armory_view.gd: Forge & Market (issue #112)
var journal_view  # journal_view.gd: quest log, people, codex, history (issue #114)
var newcomers_view
var scene_view  # bond scenes started by talking to someone in town
var dialogue_box  # dialogue_box.gd: talking to people in town
var chapter_card  # chapter_card.gd: "Chapter 1 complete" and friends (issue #18)
## The grey "wants a word" heart over the betrayal's top candidate (issue #186).
const GREY_HEART := Color(0.55, 0.53, 0.58)
var story_beat := {}  # the story beat whose talk is playing (data/story.json beats)
var banter  # banter.gd: people calling out as Ash walks past
var sites := {}  # building id -> building_site.gd on its plot
var lamp: StaticBody2D  # Hollowmark's own Wardlamp, drawn once it is lit (solid once built)
var _lamp_key := ""  # which footprint the Wardlamp has: "wardlamp_<level>", or ""
var menu: InkMenu
var slot_menu: InkMenu
var slot_mode := ""
var menu_closed_frame := -1
var table_pos := Vector2.ZERO  # bottom-centre of the Command Table
var table_body: StaticBody2D
var target := {}  # what the attack button would use: {"kind": "npc"/"table", "id", "pos", "label"}
var talk_index := {}  # recruit id -> next line to say
var pitched := {}  # visitor id -> true once they have made their pitch (talk again to take them on)
var autosave_t := AUTOSAVE_EVERY
var leaving := false


func _ready() -> void:
	get_tree().paused = false
	Empire.fit_speed()  # the Assists may have changed since the clock was last set
	entities = Node2D.new()
	entities.y_sort_enabled = true
	area = Area.new()
	add_child(area)
	area.build(map_override if map_override != "" else MAP, entities)
	world = area.world_size()
	Art.set_blank_x(1e9)  # no Blank inside the walls (yet)
	add_child(entities)
	_build_walls()
	_build_table()
	_build_sites()

	var look: Dictionary = Empire.recruit("ash").get("look", {})
	leader = _make_person("ash", area.party_start, look)
	leader.controlled = true
	leader.peaceful = true
	leader.party = self
	leader.collision_layer = 2
	heroes = [leader]
	_place_people()
	_spawn_townsfolk()
	add_child(FxLayer.new())  # effects drawn as pixel art (scripts/fx_layer.gd)
	var ambience := Ambience.new()  # day/night light, lantern after dark, pollen and fireflies
	ambience.party = self
	ambience.live = true
	add_child(ambience)

	var tags := Node2D.new()
	tags.z_index = 20
	add_child(tags)
	tags.draw.connect(_draw_tags.bind(tags))
	tags.set_process(true)
	set_meta("tags", tags)

	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(world.x)
	camera.limit_bottom = int(world.y)
	add_child(camera)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.hub = self
	layer.add_child(hud)
	layer.add_child(_alert_tray())  # alerts with "go there" and the pinned story goal (issue #22)
	touch = TouchScript.new()
	layer.add_child(touch)
	banter = BanterScript.new()
	banter.top = 26.0
	layer.add_child(banter)

	var roster_layer := CanvasLayer.new()
	roster_layer.layer = 4
	add_child(roster_layer)
	roster_view = RosterView.new()
	roster_view.visible = false
	roster_layer.add_child(roster_view)
	roster_view.closed.connect(_place_people)
	buildings_view = BuildingsView.new()
	buildings_view.visible = false
	roster_layer.add_child(buildings_view)
	buildings_view.closed.connect(_place_people)
	expedition_view = ExpeditionView.new()
	expedition_view.visible = false
	roster_layer.add_child(expedition_view)
	expedition_view.closed.connect(_place_people)
	research_view = ResearchView.new()
	research_view.visible = false
	roster_layer.add_child(research_view)
	diplomacy_view = DiplomacyView.new()
	diplomacy_view.visible = false
	roster_layer.add_child(diplomacy_view)
	diplomacy_view.closed.connect(_place_people)  # envoys leave town
	bonds_view = BondsView.new()
	bonds_view.visible = false
	roster_layer.add_child(bonds_view)
	newcomers_view = NewcomersView.new()
	newcomers_view.visible = false
	roster_layer.add_child(newcomers_view)
	newcomers_view.closed.connect(_place_people)  # someone taken on leaves the gate
	gear_view = GearViewScript.new()
	gear_view.visible = false
	roster_layer.add_child(gear_view)
	armory_view = ArmoryView.new()
	armory_view.visible = false
	roster_layer.add_child(armory_view)
	journal_view = JournalView.new()  # quest log and codex (issue #114)
	journal_view.visible = false
	roster_layer.add_child(journal_view)
	journal_view.go.connect(alert_go)
	Empire.lead_arrived.connect(func(_id): _place_people())
	scene_view = SceneView.new()
	scene_view.visible = false
	roster_layer.add_child(scene_view)
	dialogue_box = DialogueBox.new()
	dialogue_box.visible = false
	roster_layer.add_child(dialogue_box)
	dialogue_box.finished.connect(_on_talk_finished)
	chapter_card = ChapterCard.new()
	roster_layer.add_child(chapter_card)
	chapter_card.closed.connect(func(): call_deferred("_story_check"))
	Empire.expedition_returned.connect(func(_r): _place_people())
	Empire.expedition_returned.connect(func(_r): call_deferred("_story_check"))
	Empire.lead_arrived.connect(func(_id): call_deferred("_story_check"))

	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 5
	menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(menu_layer)
	menu = InkMenu.new()
	menu.visible = false
	menu_layer.add_child(menu)
	menu.chosen.connect(_on_menu)
	slot_menu = InkMenu.new()
	slot_menu.visible = false
	slot_menu.top = 0.2
	menu_layer.add_child(slot_menu)
	slot_menu.chosen.connect(_on_slot)

	Empire.day_passed.connect(_on_day_passed)
	Empire.notice.connect(_on_notice)
	Empire.hollowmark_lost.connect(_on_hollowmark_lost)
	HelpWatch.attach(self)  # explainers, the story's paced unlocks and first-time tips (issue #115)

	if not Saves.pending.is_empty():
		var d: Dictionary = Saves.pending
		Saves.pending = {}
		if d.has("x"):
			leader.global_position = Vector2(float(d["x"]), float(d["y"]))
			leader.facing = Vector2.DOWN
		hud.say(tr("Loaded. Hollowmark is still here. Mostly."), 2.5)
	if not Empire.last_mission.is_empty():  # home from a mission: say what came back with you
		var r: Dictionary = Empire.last_mission
		Empire.last_mission = {}
		var pay := Missions.res_text(r.get("pay", {}))
		hud.toast(tr("Back from %s.") % r.get("name", tr("the field")))
		hud.toast_t = 5.0
		if pay != "":
			hud.notice(tr("Brought home: %s") % pay, false)
	camera.global_position = leader.global_position
	camera.reset_smoothing()
	if Empire.territory().find("hollowmark").get("owner", "") == "erased":
		_on_hollowmark_lost()
	else:
		call_deferred("_story_check")  # the story picks up where it left off (issue #18)


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.collision_layer = 1
	add_child(walls)
	var t := 40.0
	for r in [Rect2(-t, -t, world.x + 2 * t, t), Rect2(-t, world.y, world.x + 2 * t, t),
			Rect2(-t, 0, t, world.y), Rect2(world.x, 0, t, world.y)]:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.position + r.size / 2.0
		walls.add_child(col)


func _build_table() -> void:
	var spots: Array = area.markers.get("table", [])
	var tl: Vector2 = spots[0] if not spots.is_empty() else world / 2.0
	# The marker is the table's top-left tile; the table covers three tiles by two.
	table_pos = tl + Vector2(16, 20)
	table_body = StaticBody2D.new()
	table_body.collision_layer = 1
	table_body.position = table_pos
	Footprints.attach(table_body, Footprints.poly("props", "command_table"))
	table_body.draw.connect(_draw_table)
	entities.add_child(table_body)


## Building plots from the map's site_<id> marks, and the spot for Hollowmark's Wardlamp.
func _build_sites() -> void:
	for id in Empire.building_ids():
		var mark: String = Empire.building(id).get("site", "")
		var spots: Array = area.markers.get(mark, [])
		if mark == "" or spots.is_empty():
			continue
		var site = SiteScript.new()
		site.id = id
		# The mark is the plot's top-left tile centre; the site's origin is the plot's bottom-centre.
		site.position = (spots[0] as Vector2) - Vector2(8, 8) + Vector2(40, 77)
		entities.add_child(site)
		sites[id] = site
	var lamp_spots: Array = area.markers.get("lamp", [])
	if not lamp_spots.is_empty():
		lamp = StaticBody2D.new()
		lamp.collision_layer = 1
		lamp.position = lamp_spots[0]
		lamp.draw.connect(_draw_lamp)
		entities.add_child(lamp)


func _make_person(id: String, pos: Vector2, look: Dictionary) -> Hero:
	var h: Hero = HeroScript.new()
	h.hero_name = Empire.recruit(id).get("name", id)
	h.outfit = look.get("outfit", "archer")
	var cols := {}
	for k in look.get("colors", {}):
		cols[k] = Color(look["colors"][k])
	if not cols.is_empty():
		h.colors = cols
	h.move_speed = 70.0
	h.position = pos
	h.set_meta("id", id)
	entities.add_child(h)
	return h


## Where a recruit stands right now: the hall if they govern Hollowmark, the gate if they are
## in your party, the tavern while injured, otherwise their usual post.
func post_of(id: String) -> String:
	var st: Dictionary = Empire.recruits.get(id, {})
	if int(st.get("injured", 0)) > 0:
		return "tavern"
	if st.get("role", "") == "governor":
		return "hall" if st.get("target", "") == "hollowmark" else ""  # elsewhere: not in town
	if st.get("role", "") == "party":
		return "gate"
	if st.get("role", "") in ["expedition", "envoy", Betrayal.AWAY_ROLE]:
		return ""  # out of town: with a squad, living with a faction, or gone with the Vacancy (issue #186)
	if st.get("role", "") == "staff":
		if st.get("target", "") == "command_table":
			return "table_side"
		return "bld:" + st.get("target", "") if sites.has(st.get("target", "")) else "tavern"
	return Empire.recruit(id).get("post", "tavern")


## How many people stand side by side at one post before the rest spill elsewhere.
const POST_ROOM := 5
## The posts anyone can stand at (not the Command Table, which is for staff on duty there).
const OPEN_POSTS := ["hall", "tavern", "stores", "graveyard", "gate", "market", "well", "bench"]


## The open-air post with the most room left ("" when every one is full).
func _roomiest_post(used: Dictionary) -> String:
	var best := ""
	for p in OPEN_POSTS:
		if area.markers.has(p) and int(used.get(p, 0)) < POST_ROOM and (best == "" or int(used.get(p, 0)) < int(used.get(best, 0))):
			best = p
	return best


## Puts every recruit at their post. Called on start and whenever the roster closes.
func _place_people() -> void:
	var used := {}
	var seen := {}
	for id in Empire.roster_ids():
		if id == "ash":
			continue
		var post := post_of(id)
		var spots: Array = area.markers.get(post, [])
		if post.begins_with("bld:"):
			var n0: int = used.get(post, 0)
			spots = [sites[post.substr(4)].post_pos(n0) - Vector2([0, 18, -18, 36, -36][n0 % 5], 0)]
		if post == "" or spots.is_empty():
			if npcs.has(id):
				npcs[id].queue_free()
				npcs.erase(id)
			continue
		# Five stand side by side at a post; anyone past that goes to the emptiest open-air post instead
		# of standing on someone's head (issue #27: the roster heads for about 50).
		if not post.begins_with("bld:") and int(used.get(post, 0)) >= POST_ROOM:
			var spill := _roomiest_post(used)
			if spill != "":
				post = spill
				spots = area.markers[spill]
		seen[id] = true
		var n: int = used.get(post, 0)
		used[post] = n + 1
		# Several people at one post stand side by side.
		var pos: Vector2 = spots[0] + Vector2([0, 18, -18, 36, -36][n % 5], 0)
		var npc: Hero = npcs.get(id)
		if npc == null:
			npc = _make_person(id, pos, Empire.recruit(id).get("look", {}))
			npc.collision_layer = 1  # Ash bumps into people instead of walking through them
			npc.collision_mask = 0
			npcs[id] = npc
		npc.global_position = pos
	# Newcomers waiting to be taken on stand just inside the south gate.
	var vspots: Array = area.markers.get("visitors", [])
	var vn := 0
	for id in Empire.visitors:
		if Empire.recruits.has(id) or vspots.is_empty():
			continue
		seen[id] = true
		var vpos: Vector2 = vspots[0] + Vector2([0, 18, -18, 36, -36, 54, 72][vn % 7], 0)
		vn += 1
		var vnpc: Hero = npcs.get(id)
		if vnpc == null:
			vnpc = _make_person(id, vpos, Empire.recruit(id).get("look", {}))
			vnpc.collision_layer = 1
			vnpc.collision_mask = 0
			npcs[id] = vnpc
		vnpc.global_position = vpos
	for id in npcs.keys():
		if not seen.has(id):
			npcs[id].queue_free()
			npcs.erase(id)


## A few townsfolk strolling the plaza: more by day, a couple of night owls after dark.
func _spawn_townsfolk() -> void:
	if not SpriteSet.has_art("folk_man"):
		return
	var blockers: Array = []  # [position, radius]
	var walls: Array = []  # [origin, footprint polygon]: townsfolk have no collision, so they keep off these
	for p in area.props:
		var pts: PackedVector2Array = p.collision_poly
		if pts.size() >= 3:
			walls.append([p.position, pts])
	for id in sites:
		blockers.append([sites[id].position + Vector2(0, -36), 52.0])
	blockers.append([table_pos, 34.0])
	for id in area.markers:
		for m in area.markers[id]:
			blockers.append([m, 24.0])
	var free := {}
	for y in area.size_tiles.y:
		for x in area.size_tiles.x:
			if not area._is_dirt(x, y):
				continue
			var c := Vector2(x * 16 + 8, y * 16 + 8)
			var ok := true
			for b in blockers:
				if c.distance_to(b[0]) < b[1]:
					ok = false
					break
			for w in walls:
				if ok and Footprints.covers(w[1], w[0], c, 10.0):
					ok = false
			if ok:
				free[Vector2i(x, y)] = true
	var keys := free.keys()
	if keys.is_empty():
		return
	var n := int(round(lerpf(6.0, 2.0, Ambience.darkness(Empire.day_t))))
	for i in n:
		var f := Townsfolk.new()
		f.body_id = Townsfolk.BODIES[i % Townsfolk.BODIES.size()]
		f.free = free
		var c: Vector2i = keys[randi() % keys.size()]
		f.position = Vector2(c * 16) + Vector2(8, 8)
		entities.add_child(f)


func shake(_amount: float) -> void:
	pass


func touch_active() -> bool:
	return touch != null and touch.visible


# ---------------------------------------------------------------- talking and using things

func _find_target() -> Dictionary:
	var p := leader.global_position
	var best := {}
	var best_d := TALK_RANGE
	for id in npcs:
		var d: float = (npcs[id] as Node2D).global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = {"kind": "npc", "id": id, "pos": (npcs[id] as Node2D).global_position, "label": tr("Talk to %s") % Empire.recruit(id)["name"]
				+ (tr("  (something on their mind)") if Betrayal.marked(id) else (tr("  (wants a word)") if Empire.bond_next_scene(id) > 0 else "")) + (tr("  (looking for work)") if Empire.is_visitor(id) else "")}
	# The table is wide: measure to its nearest edge, not its middle.
	var tr := Rect2(table_pos - Vector2(TABLE_SIZE.x / 2.0, TABLE_SIZE.y), TABLE_SIZE)
	var nearest := Vector2(clampf(p.x, tr.position.x, tr.end.x), clampf(p.y, tr.position.y, tr.end.y))
	if nearest.distance_to(p) < minf(best_d, 18.0):
		best = {"kind": "table", "id": "table", "pos": table_pos, "label": tr("Use the Command Table")}
		best_d = nearest.distance_to(p)
	for id in sites:
		var site = sites[id]
		site.highlight = false
		var sr: Rect2 = site.plot_rect()
		var np := Vector2(clampf(p.x, sr.position.x, sr.end.x), clampf(p.y, sr.position.y, sr.end.y))
		var d := np.distance_to(p)
		if d < minf(best_d, 14.0) and best.is_empty():
			var b := Empire.building(id)
			var lv := Empire.level_of(id)
			var verb := tr("Check on") if lv > 0 or Empire.construction.get("id", "") == id else tr("Plan")
			best = {"kind": "site", "id": id, "pos": site.global_position, "label": tr("%s the %s") % [verb, b["name"]]}
			best_d = d
	if best.get("kind", "") == "site":
		sites[best["id"]].highlight = true
	return best


func _use(t: Dictionary) -> void:
	if t.is_empty():
		return
	if t["kind"] == "table":
		_open_table()
		return
	if t["kind"] == "site":
		if t["id"] == "guildhall" and Empire.level_of("guildhall") > 0:
			expedition_view.open()  # the Guildhall's job board
		elif t["id"] == "scriptorium" and Empire.level_of("scriptorium") > 0:
			research_view.open()  # the Scriptorium's desks
		elif (t["id"] == "forge" or t["id"] == "market") and Empire.level_of(t["id"]) > 0:
			armory_view.open(t["id"])  # the Forge's benches, the Market's stalls (issue #112)
		else:
			buildings_view.open(t["id"])
		touch.release_all()
		return
	var id: String = t["id"]
	if Empire.is_visitor(id):
		_talk_visitor(id)
		return
	var seed_talk := Betrayal.seed_talk(id)
	if seed_talk != "" and int(Empire.recruits[id]["injured"]) <= 0:  # Chapter 4 on: something on their mind (issue #186)
		(npcs[id] as Hero).facing = (leader.global_position - (npcs[id] as Node2D).global_position).normalized()
		Empire.bond_talk(id)
		touch.release_all()
		dialogue_box.play(seed_talk)
		return
	var ready_rank := Empire.bond_next_scene(id)
	if ready_rank > 0:  # they have something to say: play their bond scene
		(npcs[id] as Hero).facing = (leader.global_position - (npcs[id] as Node2D).global_position).normalized()
		Empire.bond_talk(id)
		scene_view.play(id, ready_rank)
		touch.release_all()
		return
	var ended := Relationships.take_ended_lines(id)  # an ex says their piece, once (issue #116)
	if not ended.is_empty():
		(npcs[id] as Hero).facing = (leader.global_position - (npcs[id] as Node2D).global_position).normalized()
		Empire.bond_talk(id)
		touch.release_all()
		dialogue_box.play_lines(ended)
		return
	var r := Empire.recruit(id)
	var lines: Array = r.get("lines", [])
	var npc: Hero = npcs[id]
	npc.facing = (leader.global_position - npc.global_position).normalized()
	var short_name := Empire.short_name(id)
	var line := "..."
	if int(Empire.recruits[id]["injured"]) > 0:
		line = Loc.n("Still stitching myself back together. Ask me again in %d day.", "Still stitching myself back together. Ask me again in %d days.", int(Empire.recruits[id]["injured"])) % int(Empire.recruits[id]["injured"])
	elif Empire.role_of(id) == "governor":
		line = tr("I keep the hall and the ledgers. Hollowmark holds while I'm here. Mostly.")
	elif Empire.role_of(id) == "staff":
		var bid: String = Empire.recruits[id]["target"]
		line = tr("%s Right now: %s.") % [Loc.t(STAFF_LINES.get(bid, tr("Working."))), Empire.current_effect(bid)["text"].to_lower()]
	elif not lines.is_empty():
		var i: int = talk_index.get(id, 0)
		line = Prompts.fill(str(lines[i % lines.size()]))
		if Relationships.talk_line(id, i) != "":  # sweet nothings (issue #116)
			line = Relationships.talk_line(id, i)
		talk_index[id] = i + 1
	var gained := Empire.bond_talk(id)
	var bond_note := tr("   (bond +%d)") % gained if gained > 0 else ""
	touch.release_all()
	var first := Dialogue.first_talk(id)
	if first != "" and int(Empire.recruits[id]["injured"]) <= 0:
		dialogue_box.play(first)  # the first proper chat: their introduction
		talk_index[id] = 0
		if gained > 0:
			dialogue_box.title += tr("   ·   Bond with %s +%d") % [short_name, gained]
		return
	if Betrayal.marked(id):
		line = Betrayal.redact(line)  # the Vacancy is already at their words (issue #186)
	dialogue_box.play_lines([[id, line + bond_note]])


## A newcomer at the gate: the first chat is their pitch, the next one takes them on (if you can pay).
func _talk_visitor(id: String) -> void:
	var r := Empire.recruit(id)
	var npc: Hero = npcs[id]
	npc.facing = (leader.global_position - npc.global_position).normalized()
	var who := Empire.short_name(id)
	var cost := Empire.hire_cost(id)
	var price := "free" if cost.is_empty() else Empire.cost_text(cost)
	if not pitched.has(id):
		pitched[id] = true
		hud.say(tr("%s: %s   (Talk again to take them on: %s.)") % [who, r.get("pitch", tr("Looking for work.")), price], 6.0)
		return
	var why := Empire.hire_blocker(id)
	if why != "":
		hud.say(tr("%s: Come back when you can afford me. (%s: %s.)") % [who, price, why], 4.5)
		return
	if Empire.hire(id):
		pitched.erase(id)
		hud.say("%s: %s" % [who, r.get("welcome", tr("Glad to be here."))], 5.0)
		_place_people()


# ---------------------------------------------------------------- the story (issue #18)

## The Command Table, unless the Concord still has it under seal (before the end of Chapter 1).
func _open_table() -> void:
	if Story.command_on():
		_leave(Saves.COMMAND_SCENE)
	else:
		hud.say(tr("The Concord's clerks have the table under seal. Not yours. Not yet."), 3.0)


## Plays the next story beat in town if one is due and nothing else is on screen.
func _story_check() -> void:
	if leaving or not is_inside_tree() or menu.visible or dialogue_box.visible or chapter_card.visible or Help.busy():
		return
	if roster_view.visible or buildings_view.visible or expedition_view.visible or research_view.visible \
			or diplomacy_view.visible or bonds_view.visible or scene_view.visible or newcomers_view.visible or gear_view.visible:
		return
	if armory_view.visible:
		return
	var b := Story.next_beat()
	if b.is_empty():
		return
	story_beat = b
	touch.release_all()
	dialogue_box.play(b["talk"])


func _on_talk_finished(id: String) -> void:
	if story_beat.is_empty() or story_beat.get("talk", "") != id:
		return
	var b := story_beat
	story_beat = {}
	var then: String = b.get("then", "")
	if then.begins_with("launch:"):  # straight into a story mission (the Chapter 1 breakout)
		var m := Missions.find(then.substr(7))
		if not m.is_empty():
			# No autosave here: loading the last one replays the scene before the mission.
			leaving = true
			Missions.launch(m)
			return
	for step in then.split(",", false):
		if step.strip_edges().begins_with("open_region:"):  # a chapter opens its region of the map (issue #53)
			Empire.open_region(step.strip_edges().substr(12))
	var card: Array = b.get("card", [])
	if card.size() >= 2:
		chapter_card.show_card(card[0], card[1])
	else:
		call_deferred("_story_check")


# ---------------------------------------------------------------- clock, notices, leaving

func _on_day_passed(d: int) -> void:
	call_deferred("_story_check")
	hud.toast(tr("Day %d begins.") % d, tr("Supplies ran out. People are going hungry.") if Empire.hungry else "")


func _on_notice(_text: String, _warning: bool) -> void:
	pass  # notices now live in Alerts and show in the alert tray (issue #22)


# ---------------------------------------------------------------- alerts (issue #22)

func _alert_tray() -> Control:
	var tray := preload("res://scripts/alert_tray.gd").new()
	tray.host = self
	tray.origin = Vector2(6, 50)  # under the framed status panel
	tray.width = 300.0
	return tray


## The alert tray stays quiet while a screen, menu or conversation is open.
func alerts_blocked() -> bool:
	return leaving or get_tree().paused or menu.visible or roster_view.visible or buildings_view.visible \
		or expedition_view.visible or research_view.visible or diplomacy_view.visible or bonds_view.visible \
		or scene_view.visible or newcomers_view.visible or gear_view.visible or dialogue_box.visible \
		or chapter_card.visible or Engine.get_process_frames() == menu_closed_frame \
		or journal_view.visible or armory_view.visible


## "Go there" from town: screens open right here; provinces and missions are on the Command Table.
func alert_go(target: Dictionary) -> void:
	match target.get("view", ""):
		"buildings": buildings_view.open()
		"expeditions": expedition_view.open()
		"research": research_view.open()
		"diplomacy": diplomacy_view.open()
		"bonds": bonds_view.open()
		"newcomers": newcomers_view.open()
		_:
			if not target.has("province"):
				return
			if not Story.command_on():
				hud.say(tr("The Concord's clerks have the table under seal. Not yours. Not yet."), 3.0)
				return
			Alerts.focus = target
			_leave(Saves.COMMAND_SCENE)


func _on_hollowmark_lost() -> void:
	# The Command Table shows the ending screen for a lost town.
	call_deferred("_go_command_unsaved")


func _go_command_unsaved() -> void:
	if leaving:
		return
	leaving = true
	get_tree().paused = false
	get_tree().change_scene_to_file(Saves.COMMAND_SCENE)


func snapshot() -> Dictionary:
	return {"scene": Saves.HUB_SCENE, "area_name": tr("Hollowmark"),
		"x": leader.global_position.x, "y": leader.global_position.y}


func autosave() -> void:
	if not leaving and Empire.territory().find("hollowmark").get("owner", "") != "erased":
		Saves.save("auto", snapshot())


func _leave(scene: String) -> void:
	if leaving:
		return
	autosave()
	leaving = true
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_inside_tree() and leader:
			autosave()


# ---------------------------------------------------------------- menu

func open_menu(note := "") -> void:
	menu.setup(tr("Hollowmark"), [
		{"id": "resume", "label": tr("Resume")},
		{"id": "table", "label": tr("Command Table"), "detail": tr("the territory map")},
		{"id": "journal", "label": tr("Journal"), "detail": tr("quests, people, codex, history") + Prompts.tag("journal")},
		{"id": "roster", "label": tr("Roster"), "detail": Prompts.key("roster")},
		{"id": "buildings", "label": tr("Buildings"), "detail": Prompts.key("buildings")},
		{"id": "expeditions", "label": tr("Expeditions"), "detail": Prompts.key("expeditions"), "enabled": Help.is_open("expeditions"), "note": "(%s)" % Help.locked_note("expeditions")},
		{"id": "research", "label": tr("Research"), "detail": Prompts.key("research"), "enabled": Help.is_open("research"), "note": "(%s)" % Help.locked_note("research")},
		{"id": "diplomacy", "label": tr("Diplomacy"), "detail": Prompts.key("diplomacy"), "enabled": Help.is_open("diplomacy"), "note": "(%s)" % Help.locked_note("diplomacy")},
		{"id": "bonds", "label": tr("Bonds"), "detail": Prompts.key("bonds"), "enabled": Help.is_open("bonds"), "note": "(%s)" % Help.locked_note("bonds")},
		{"id": "newcomers", "label": tr("Newcomers"), "detail": Prompts.key("newcomers")},
		{"id": "gear", "label": tr("Party gear & shop"), "detail": Prompts.key("gear")},
		{"id": "armory", "label": tr("Forge & Market"), "detail": Prompts.key("armory")},
		{"id": "help", "label": tr("Help"), "detail": tr("explainers, tips and controls")},
		{"id": "report", "label": tr("Report a bug"), "detail": tr("or send feedback")},
	] + Survey.menu_items() + [  # playtest builds only (issue #168)
		{"id": "save", "label": tr("Save game")},
		{"id": "load", "label": tr("Load game"), "enabled": Saves.latest_slot() != "", "note": tr("(no saves yet)")},
		{"id": "options", "label": tr("Options")},
		{"id": "title", "label": tr("Quit to title")},
	], note)
	menu.visible = true
	get_tree().paused = true
	touch.release_all()


func _close_menu() -> void:
	menu.visible = false
	slot_menu.visible = false
	get_tree().paused = false
	menu_closed_frame = Engine.get_process_frames()


func _on_menu(id: String) -> void:
	match id:
		"resume", "cancel":
			_close_menu()
		"table":
			if Story.command_on():
				_leave(Saves.COMMAND_SCENE)
			else:
				_close_menu()
				_open_table()
		"journal":
			_close_menu()
			journal_view.open("quests")
		"roster":
			_close_menu()
			roster_view.open()
		"buildings":
			_close_menu()
			buildings_view.open()
		"expeditions":
			_close_menu()
			expedition_view.open()
		"research":
			_close_menu()
			research_view.open()
		"diplomacy":
			_close_menu()
			diplomacy_view.open()
		"bonds":
			_close_menu()
			bonds_view.open()
		"newcomers":
			_close_menu()
			newcomers_view.open()
		"gear":
			_close_menu()
			gear_view.open("town")
		"armory":
			_close_menu()
			armory_view.open()
		"help":  # issue #115
			menu.visible = false
			HelpView.popup(self).closed.connect(func(): menu.visible = true)
		"report":  # issue #146
			menu.visible = false
			FeedbackView.popup(self).closed.connect(func(): menu.visible = true)
		"survey":  # issue #168
			menu.visible = false
			SurveyView.popup(self).closed.connect(func(): menu.visible = true)
		"options":
			menu.visible = false
			OptionsView.popup(self).closed.connect(func(): menu.visible = true)
		"save", "load":
			slot_mode = id
			menu.visible = false
			slot_menu.setup(tr("Save to which slot?") if id == "save" else tr("Load which save?"), Saves.slot_items(id == "save"))
			slot_menu.visible = true
		"title":
			_leave(TITLE_SCENE)


func _on_slot(id: String) -> void:
	if id == "back" or id == "cancel":
		slot_menu.visible = false
		menu.visible = true
		return
	if slot_mode == "load":
		Saves.load_and_play(id)
		return
	var ok := Saves.save(id, snapshot())
	slot_menu.visible = false
	open_menu((tr("Saved to %s.") % Saves.slot_label(id)) if ok else tr("Saving failed. Your browser may be blocking storage."))


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	# The clock only runs once Ash runs the town (end of Chapter 1), and stops for story scenes.
	if Story.command_on() and not dialogue_box.visible and not chapter_card.visible:
		# A screen open in town (roster, buildings...) holds the clock at 1x, as on the Command Table.
		Empire.hold_1x = roster_view.visible or buildings_view.visible or expedition_view.visible or research_view.visible \
				or diplomacy_view.visible or bonds_view.visible or scene_view.visible or newcomers_view.visible \
				or gear_view.visible or journal_view.visible or armory_view.visible
		Empire.tick_frame(delta)
		Empire.hold_1x = false
	Empire.playtime += minf(delta, Empire.MAX_TICK)  # not the hours a suspended Deck slept (issue #149)
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE_EVERY
		autosave()
	camera.global_position = leader.global_position + Vector2(0, -10)
	camera.position_smoothing_speed = Access.follow_speed(7.0)  # reduce camera motion (issue #192)
	# People turn to look at Ash when Ash comes close.
	for id in npcs:
		var npc: Hero = npcs[id]
		var to := leader.global_position - npc.global_position
		npc.facing = to.normalized() if to.length() < 70.0 else Vector2.DOWN
	target = _find_target()
	(get_meta("tags") as Node2D).queue_redraw()
	table_body.queue_redraw()
	if lamp:
		lamp.queue_redraw()
		_refresh_lamp_footprint()

	var frame := Engine.get_process_frames()
	var screen_open: bool = roster_view.visible or buildings_view.visible or expedition_view.visible or research_view.visible \
			or diplomacy_view.visible or bonds_view.visible or scene_view.visible or newcomers_view.visible or gear_view.visible \
			or dialogue_box.visible or chapter_card.visible
	screen_open = screen_open or journal_view.visible or armory_view.visible
	if screen_open or frame == armory_view.closed_frame or frame == journal_view.closed_frame or frame == roster_view.closed_frame or frame == buildings_view.closed_frame \
			or frame == expedition_view.closed_frame or frame == research_view.closed_frame \
			or frame == diplomacy_view.closed_frame or frame == bonds_view.closed_frame \
			or frame == scene_view.closed_frame or frame == newcomers_view.closed_frame or frame == menu_closed_frame \
			or frame == gear_view.closed_frame or frame == dialogue_box.closed_frame or frame == chapter_card.closed_frame:
		leader.controlled = not screen_open
		return
	leader.controlled = true
	banter.check_zones("hollowmark", leader.global_position, npcs.keys())
	if Input.is_action_just_pressed("pause"):
		open_menu()
		return
	if Input.is_action_just_pressed("roster"):
		roster_view.open()
		return
	if Input.is_action_just_pressed("buildings"):
		buildings_view.open()
		return
	if Input.is_action_just_pressed("expeditions"):
		expedition_view.open()
		return
	if Input.is_action_just_pressed("research"):
		research_view.open()
		return
	if Input.is_action_just_pressed("diplomacy"):
		diplomacy_view.open()
		return
	if Input.is_action_just_pressed("bonds"):
		bonds_view.open()
		return
	if Input.is_action_just_pressed("newcomers"):
		newcomers_view.open()
		return
	if Input.is_action_just_pressed("gear"):
		gear_view.open("town")
		return
	if Input.is_action_just_pressed("armory"):
		armory_view.open()
		return
	if Input.is_action_just_pressed("journal"):
		journal_view.open()
		return
	for i in Empire.SPEED_KEYS.size():
		if Input.is_action_just_pressed("clock_speed_%d" % i):
			Empire.pick_speed(Empire.SPEED_KEYS[i])
	if Input.is_action_just_pressed("clock_slower"):
		Empire.step_speed(-1)
	elif Input.is_action_just_pressed("clock_faster"):
		Empire.step_speed(1)
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("ui_accept"):
		_use(target)
	hud.sign_text = ""
	for p in area.props:
		if p.kind == "sign" and (p as Node2D).global_position.distance_to(leader.global_position) < 34.0:
			hud.sign_text = p.text


# ---------------------------------------------------------------- drawing

## The Command Table: the art pass sprite with its shadow, outlined in gold while Ash can use it.
func _draw_table() -> void:
	var c := table_body
	var tw := float(table_art.get_width())
	var th := float(table_art.get_height())
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	c.draw_circle(Vector2(0, 2), tw * 0.5, Color(0, 0, 0, 0.25))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	c.draw_texture(table_art, Vector2(-tw / 2.0, -th + 3.0))
	if target.get("kind", "") == "table":
		c.draw_rect(Rect2(-tw / 2.0 - 2.0, -th + 1.0, tw + 4.0, th + 4.0), Color("ffd166"), false, 1.0)


## The Wardlamp is solid once it stands (its post while it goes up, then the level's footprint).
func _refresh_lamp_footprint() -> void:
	var lv := int(Empire.lamps.get("hollowmark", 0))
	var key := "wardlamp_%d" % clampi(lv, 1, 2) if lv > 0 or Empire.lamp_jobs.has("hollowmark") else ""
	if key == _lamp_key:
		return
	_lamp_key = key
	for c in lamp.get_children():
		if c is CollisionShape2D:
			c.queue_free()
	if key != "":
		var pts := Footprints.poly("props", key)
		Footprints.attach(lamp, pts)
		Footprints.eject(lamp, pts)


## Hollowmark's Wardlamp: an iron post with an ink-blue flame, brighter at level 2.
func _draw_lamp() -> void:
	var lv := int(Empire.lamps.get("hollowmark", 0))
	var going_up := Empire.lamp_jobs.has("hollowmark")
	if lv == 0 and not going_up:
		return
	var c := lamp
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	c.draw_circle(Vector2(0, 2), 6.0, Color(0, 0, 0, 0.25))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if c.get_node_or_null("Art") != null:
		c.get_node("Art").visible = lv > 0
	var h := 30.0 if lv > 0 else 30.0 * Empire.job_progress(Empire.lamp_jobs["hollowmark"])
	var art_path := "res://assets/props/wardlamp_%d.png" % clampi(lv, 1, 2)
	if lv > 0 and ResourceLoader.exists(art_path):
		# Art pass: the lamp sprite, with the glow drawn in code around its lantern.
		var tex: Texture2D = load(art_path)
		var spr: Sprite2D = c.get_node_or_null("Art")
		if spr == null:
			spr = Sprite2D.new()
			spr.name = "Art"  # no-tr: node name
			spr.centered = false
			spr.material = Art.art_world_material()
			spr.show_behind_parent = true
			c.add_child(spr)
		spr.texture = tex
		spr.position = Vector2(-tex.get_width() / 2.0, -tex.get_height() + 2.0)
		var fl := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.011)
		var gl := 10.0 + 6.0 * lv
		var lc := Vector2(0, -tex.get_height() + LAMP_FLAME_Y)
		c.draw_circle(lc, gl, Color(0.55, 0.65, 1.0, 0.10 * fl))
		c.draw_circle(lc, gl * 0.5, Color(0.6, 0.7, 1.0, 0.18 * fl))
		return
	c.draw_rect(Rect2(-1.5, -h, 3, h), Color("2e2a33"))
	c.draw_rect(Rect2(-4, -2, 8, 3), Color("2e2a33"))
	if lv > 0:
		var flick := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.011)
		var glow := 10.0 + 6.0 * lv
		c.draw_circle(Vector2(0, -h - 4), glow, Color(0.55, 0.65, 1.0, 0.10 * flick))
		c.draw_circle(Vector2(0, -h - 4), glow * 0.5, Color(0.6, 0.7, 1.0, 0.18 * flick))
		c.draw_rect(Rect2(-4, -h - 9, 8, 8), Color("3a3442"))
		c.draw_rect(Rect2(-2.5, -h - 7.5, 5, 5), Color(0.75, 0.82, 1.0, flick))
		c.draw_colored_polygon(PackedVector2Array([Vector2(-5, -h - 9), Vector2(5, -h - 9), Vector2(0, -h - 13)]), Color("2e2a33"))


func _draw_tags(canvas: Node2D) -> void:
	var font := ThemeDB.fallback_font
	# The one Ash would talk to goes first; other names that would overlap a drawn one are skipped.
	var order: Array = npcs.keys()
	if order.has(target.get("id", "")):
		order.erase(target["id"])
		order.push_front(target["id"])
	var drawn: Array = []
	for id in order:
		var npc: Hero = npcs[id]
		var d := npc.global_position.distance_to(leader.global_position)
		if d > 80.0:
			continue
		var a := clampf((80.0 - d) / 25.0, 0.0, 1.0)
		var r := Empire.recruit(id)
		var name_s: String = r["name"]
		var w := font.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6)).x
		var p := npc.global_position + Vector2(-w / 2.0, -26)
		if Empire.is_visitor(id) and target.get("id", "") != id:  # a gold "!" over newcomers looking for work
			var bob := sin(Time.get_ticks_msec() * 0.006)
			var bp := npc.global_position + Vector2(-1.5, -35 + bob)
			canvas.draw_string_outline(font, bp, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), 2, Color(0, 0, 0, 0.8 * a))
			canvas.draw_string(font, bp, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9), Color("ffd166", a))
		if Betrayal.marked(id):  # the heart goes grey: something else has their attention (issue #186)
			var gc := npc.global_position + Vector2(0, -38 + sin(Time.get_ticks_msec() * 0.003) * 0.8)
			Art.draw_heart(canvas, gc, 4.0, Color(GREY_HEART, a))
		var box := Rect2(p + Vector2(-2, -6), Vector2(w + 4, 8))
		if drawn.any(func(o): return (o as Rect2).intersects(box)):
			continue
		drawn.append(box)
		var col := Color("ffd166", a) if target.get("id", "") == id else Color(0.95, 0.93, 0.88, a)
		canvas.draw_string_outline(font, p, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6), 2, Color(0, 0, 0, 0.8 * a))
		canvas.draw_string(font, p, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(6), col)
		if Betrayal.marked(id):
			continue  # grey heart already drawn above
		if Empire.bond_next_scene(id) > 0:  # a heart: they want a word
			var hc := npc.global_position + Vector2(0, -38 + sin(Time.get_ticks_msec() * 0.005) * 1.5)
			Art.draw_heart(canvas, hc, 4.0, Color("ff8fa3"))
			continue
		if target.get("id", "") == id:
			var y := -33.0 + sin(Time.get_ticks_msec() * 0.006)
			var tip := npc.global_position + Vector2(0, y)
			canvas.draw_colored_polygon(PackedVector2Array([tip + Vector2(-2.5, -3), tip + Vector2(2.5, -3), tip]), Color("ffd166"))

