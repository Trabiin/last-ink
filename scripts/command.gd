extends Control
## The Command Table: the territory map of the Inklands, a panel for the selected province,
## and the day clock (which only runs while this scene is open and unpaused).
##
## The map is the painted Inklands (assets/ui/map_painted.jpg) with the provinces rasterised from
## Territory over it as translucent washes: owner colours, borders, the Blank's whitening (Fray)
## and the fog over regions the story has not opened yet (issue #53). Roads and labels are drawn
## in code. The map pans and zooms (wheel, drag, pinch, + and -, the right stick, the buttons in
## its corner) and follows the selection. Keyboard, gamepad, mouse and touch all select provinces.

const TITLE_SCENE := "res://scenes/title.tscn"
const MAP_ORIGIN := Vector2(4, 22)
const MAP_VIEW := Vector2(428, 332)  # the map's window on screen; the world inside pans and zooms
const MAP_CELLS := Empire.MAP_CELLS
const ZOOM_MAX := 3.2  # screen pixels per map cell, fully zoomed in
const ZOOM_READ := 1.5  # below this the map shows region names over province names
const FOG := Color("cfc6b4")
const AUTOSAVE_EVERY := 60.0
const PANEL_X := 440.0

const OWNER_NAMES := {
	"you": "Held by you", "free": "Unclaimed", "concord": "The Gilded Concord",
	"coven": "The Gutterwood Coven", "guild": "The Mercenary Guild", "erased": "Erased by the Blank",
}
const OWNER_COLORS := {
	"you": Color("6f9a5a"), "free": Color("7a7060"), "concord": Color("a8833e"),
	"coven": Color("4d6e66"), "guild": Color("8a5a4a"), "erased": Color("eeebe2"),
}
const SEA_COLOR := Color("15111b")
const SEA_PARCH := Color("8f8270")  # parchment map (docs/ART_STYLE.md palette)
const SEA_INK := Color("5a3e28")
const LAND_PARCH := Color("d6cdba")
const BORDER_COLOR := Color("2a2019")
const PAPER := Color("eeebe2")
const GOLD := Color("ffd166")
const RES_NAMES := {"gilt": "Gilt", "supplies": "Supplies", "ink": "Ink"}

var territory: Territory
var map_tex: ImageTexture
var painted_tex: Texture2D = load("res://assets/ui/map_painted.jpg")  # painted island under the washes (Phase 8)
var selected := 0
var hovered := -1
var outlines: Array = []  # per province: PackedVector2Array of border cells
var blank_edge := PackedVector2Array()  # white cells touching colour: where static crawls
var t := 0.0
var font: Font
var menu: InkMenu
var slot_menu: InkMenu
var slot_mode := ""
var menu_closed_frame := -1
var toast := ""
var toast2 := ""  # second, warning line (hunger and the like)
var toast_t := 0.0
var show_ledger := false
var ledger_hover := false
var deltas := {}  # resource -> net change shown floating by the bar after dawn
var deltas_t := 0.0
var notices: Array = []  # [text, warning, time left]
var over_menu: InkMenu
var brief_menu: InkMenu  # mission briefing: Go / Back
var brief_mission := {}
var roster_view
const RosterView := preload("res://scripts/roster_view.gd")
const BuildingsView := preload("res://scripts/buildings_view.gd")
var buildings_view
const GovernorView := preload("res://scripts/governor_view.gd")
var governor_view
const ExpeditionView := preload("res://scripts/expedition_view.gd")
var expedition_view
const ResearchView := preload("res://scripts/research_view.gd")
var research_view
const DiplomacyView := preload("res://scripts/diplomacy_view.gd")
var diplomacy_view
const BondsView := preload("res://scripts/bonds_view.gd")
var bonds_view
const GearViewScript := preload("res://scripts/gear_view.gd")
var gear_view  # gear_view.gd: party gear and the shop (issue #15)
var armory_view  # armory_view.gd: Forge & Market (issue #112)
const NewcomersView := preload("res://scripts/newcomers_view.gd")
var newcomers_view
const JournalView := preload("res://scripts/journal_view.gd")
var journal_view  # quest log, people, codex, history (issue #114)
var party_picker  # party_picker.gd: who goes on the mission
var autosave_t := AUTOSAVE_EVERY
var fog_tex: ImageTexture  # mist over the regions the story has not opened (issue #53)
var _cv: CanvasItem = self  # what the draw helpers draw on: this, the clipped map canvas or the overlay
var map_clip: Control  # clips everything drawn on the map to its window
var map_canvas: Control
var overlay: Control  # buttons, legend, panel and toasts, drawn over the map
# Camera: `cam` is the map cell at the centre of the window, `zoom` screen pixels per cell.
var zoom := 2.0
var cam := Vector2.ZERO
var zoom_to := 2.0
var cam_to := Vector2.ZERO
var drag_from := Vector2.INF  # where a mouse or one-finger drag started (screen)
var drag_cam := Vector2.ZERO
var dragged := false  # moved far enough to count as a pan, not a tap
var touches := {}  # touch index -> position, for pinch zoom
var pinch_d := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	font = ThemeDB.fallback_font
	territory = Empire.territory()
	_bake()
	var hm := territory.find("hollowmark")
	selected = hm.get("index", 0)
	Saves.pending = {}  # Empire.from_dict already restored everything Command needs
	Empire.day_passed.connect(_on_day_passed)
	Empire.ledger_settled.connect(_on_ledger_settled)
	Empire.notice.connect(_on_notice)
	Empire.hollowmark_lost.connect(_on_hollowmark_lost)
	Empire.region_opened.connect(_on_region_opened)
	# The map: a clipped window. Inside it, a full-screen layer, so everything drawn there uses
	# screen coordinates and anything outside the window is cut off.
	map_clip = Control.new()
	map_clip.clip_contents = true
	map_clip.position = MAP_ORIGIN
	map_clip.size = MAP_VIEW
	map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_clip)
	var inner := Control.new()
	inner.position = -MAP_ORIGIN
	inner.size = Vector2(1280, 720)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_clip.add_child(inner)
	var paint_canvas := Control.new()  # the painting and the fog, smoothly filtered
	paint_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	paint_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	inner.add_child(paint_canvas)
	paint_canvas.draw.connect(_draw_paint.bind(paint_canvas))
	map_canvas = Control.new()  # washes, borders, roads and labels, crisp pixels
	map_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(map_canvas)
	map_canvas.draw.connect(_draw_map.bind(map_canvas))
	var watch := preload("res://scripts/blank_watch.gd").new()  # the Blank's creep, made visible (issue #33)
	watch.cmd = self
	inner.add_child(watch)
	inner.add_child(_alert_tray())  # alerts with "go there", map markers and the pinned story goal (issue #22)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.draw.connect(_draw_overlay.bind(overlay))
	frame_regions(Empire.regions_open, true)

	var roster_layer := CanvasLayer.new()
	roster_layer.layer = 4
	add_child(roster_layer)
	roster_view = RosterView.new()  # opened from the map or carried over from town
	roster_view.visible = false
	roster_layer.add_child(roster_view)
	buildings_view = BuildingsView.new()
	buildings_view.visible = false
	roster_layer.add_child(buildings_view)
	governor_view = GovernorView.new()
	governor_view.visible = false
	roster_layer.add_child(governor_view)
	governor_view.closed.connect(_bake)  # a claim recolours the map
	expedition_view = ExpeditionView.new()
	expedition_view.visible = false
	roster_layer.add_child(expedition_view)
	expedition_view.closed.connect(_bake)  # scouting can lower a province's Fray
	research_view = ResearchView.new()
	research_view.visible = false
	roster_layer.add_child(research_view)
	diplomacy_view = DiplomacyView.new()
	diplomacy_view.visible = false
	roster_layer.add_child(diplomacy_view)
	diplomacy_view.closed.connect(_bake)  # a ceded province changes colour
	bonds_view = BondsView.new()
	bonds_view.visible = false
	roster_layer.add_child(bonds_view)
	newcomers_view = NewcomersView.new()
	newcomers_view.visible = false
	roster_layer.add_child(newcomers_view)
	party_picker = PartyPicker.new()
	party_picker.visible = false
	roster_layer.add_child(party_picker)
	gear_view = GearViewScript.new()
	gear_view.visible = false
	roster_layer.add_child(gear_view)
	armory_view = ArmoryView.new()
	armory_view.visible = false
	roster_layer.add_child(armory_view)
	journal_view = JournalView.new()
	journal_view.visible = false
	roster_layer.add_child(journal_view)
	journal_view.go.connect(alert_go)
	party_picker.confirmed.connect(_launch_mission)
	party_picker.roster_requested.connect(_roster_from_picker)

	var layer := CanvasLayer.new()
	layer.layer = 5
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	menu = InkMenu.new()
	menu.visible = false
	layer.add_child(menu)
	menu.chosen.connect(_on_menu)
	slot_menu = InkMenu.new()
	slot_menu.visible = false
	slot_menu.top = 0.2
	layer.add_child(slot_menu)
	slot_menu.chosen.connect(_on_slot)
	over_menu = InkMenu.new()
	over_menu.visible = false
	over_menu.dim = 0.6
	layer.add_child(over_menu)
	over_menu.chosen.connect(_on_over)
	brief_menu = InkMenu.new()
	brief_menu.visible = false
	brief_menu.top = 0.24
	brief_menu.title_size = 18
	layer.add_child(brief_menu)
	brief_menu.chosen.connect(_on_brief)
	HelpWatch.attach(self)  # explainers, the story's paced unlocks and first-time tips (issue #115)
	if Empire.territory().find("hollowmark").get("owner", "") == "erased":
		call_deferred("_show_lost")  # lost while walking around town


func _on_day_passed(d: int) -> void:
	_bake()  # the Blank moved: re-whiten the map
	toast = tr("Day %d begins.") % d
	toast2 = tr("Supplies ran out. People are going hungry.") if Empire.hungry else ""
	toast_t = 3.5 if toast2 == "" else 5.0


## The story opened a region: lift its fog and fly the camera over to it.
func _on_region_opened(rid: String) -> void:
	_bake()
	frame_regions([rid])


func _on_notice(_text: String, _warning: bool) -> void:
	pass  # notices now live in Alerts and show in the alert tray (issue #22)


# ---------------------------------------------------------------- alerts (issue #22)

func _alert_tray() -> Control:
	var tray := preload("res://scripts/alert_tray.gd").new()
	tray.host = self
	tray.on_map = true
	tray.origin = MAP_ORIGIN + Vector2(4, MAP_VIEW.y - 16)  # stacks up from just above the legend
	tray.grow_up = true
	tray.width = 270.0
	return tray


## The alert tray stays quiet while a screen, menu or briefing is open.
func alerts_blocked() -> bool:
	var frame := Engine.get_process_frames()
	return get_tree().paused or menu.visible or slot_menu.visible or over_menu.visible or brief_menu.visible \
		or frame == menu_closed_frame or roster_view.visible or buildings_view.visible or governor_view.visible \
		or expedition_view.visible or research_view.visible or diplomacy_view.visible or bonds_view.visible \
		or newcomers_view.visible or party_picker.visible or gear_view.visible \
		or journal_view.visible or armory_view.visible


## "Go there": select the province (and open the mission's briefing when it can be played now),
## or open the screen the alert is about.
func alert_go(target: Dictionary) -> void:
	if target.has("province"):
		var p := territory.find(target["province"])
		if p.is_empty():
			return
		selected = p["index"]
		_follow(selected, true)
		var mid: String = target.get("mission", "")
		if mid != "":
			for m in Missions.list_for_province(p["id"]):
				if m.get("id", "") == mid and str(m.get("blocker", "")) == "":
					_open_brief(m)
		return
	match target.get("view", ""):
		"buildings": buildings_view.open()
		"expeditions": expedition_view.open()
		"research": research_view.open()
		"diplomacy": diplomacy_view.open()
		"bonds": bonds_view.open()
		"newcomers": newcomers_view.open()
		"town": _leave(Saves.HUB_SCENE)


func _on_hollowmark_lost() -> void:
	# Defer: this arrives mid-tick, and the menu pauses the tree.
	call_deferred("_show_lost")


func _show_lost() -> void:
	over_menu.setup(tr("Hollowmark has been erased."), [
		{"id": "load", "label": tr("Load game"), "enabled": Saves.latest_slot() != ""},
		{"id": "title", "label": tr("Quit to title")},
	], tr("No town, no table, no one left to write you down."))
	over_menu.visible = true
	get_tree().paused = true


func _on_over(id: String) -> void:
	match id:
		"load":
			over_menu.visible = false
			slot_mode = "load"
			slot_menu.setup(tr("Load which save?"), Saves.slot_items(false))
			slot_menu.visible = true
		"title":
			get_tree().paused = false
			get_tree().change_scene_to_file(TITLE_SCENE)  # no autosave: the town is gone


func _on_ledger_settled(net: Dictionary) -> void:
	deltas = net
	deltas_t = 2.5


# ---------------------------------------------------------------- menu and saving

func _menu_items(note := "") -> void:
	menu.setup(tr("Command"), [
		{"id": "resume", "label": tr("Resume")},
		{"id": "town", "label": tr("Back to Hollowmark"), "detail": tr("walk around town")},
		{"id": "roster", "label": tr("Roster"), "detail": Prompts.key("roster")},
		{"id": "buildings", "label": tr("Buildings"), "detail": Prompts.key("buildings")},
		{"id": "expeditions", "label": tr("Expeditions"), "detail": Prompts.key("expeditions"), "enabled": Help.is_open("expeditions"), "note": "(%s)" % Help.locked_note("expeditions")},
		{"id": "research", "label": tr("Research"), "detail": Prompts.key("research"), "enabled": Help.is_open("research"), "note": "(%s)" % Help.locked_note("research")},
		{"id": "diplomacy", "label": tr("Diplomacy"), "detail": Prompts.key("diplomacy"), "enabled": Help.is_open("diplomacy"), "note": "(%s)" % Help.locked_note("diplomacy")},
		{"id": "bonds", "label": tr("Bonds"), "detail": Prompts.key("bonds"), "enabled": Help.is_open("bonds"), "note": "(%s)" % Help.locked_note("bonds")},
		{"id": "newcomers", "label": tr("Newcomers"), "detail": Prompts.key("newcomers")},
		{"id": "gear", "label": tr("Party gear & shop"), "detail": Prompts.key("gear")},
		{"id": "armory", "label": tr("Forge & Market"), "detail": Prompts.key("armory")},
		{"id": "journal", "label": tr("Journal"), "detail": Prompts.key("journal")},
		{"id": "help", "label": tr("Help"), "detail": tr("explainers, tips and controls")},
		{"id": "report", "label": tr("Report a bug"), "detail": tr("or send feedback")},
	] + Survey.menu_items() + [  # playtest builds only (issue #168)
		{"id": "save", "label": tr("Save game")},
		{"id": "load", "label": tr("Load game"), "enabled": Saves.latest_slot() != "", "note": tr("(no saves yet)")},
		{"id": "options", "label": tr("Options")},
		{"id": "title", "label": tr("Quit to title")},
	], note)


func _open_menu() -> void:
	_menu_items()
	menu.visible = true
	get_tree().paused = true


func _close_menu() -> void:
	menu.visible = false
	slot_menu.visible = false
	get_tree().paused = false
	menu_closed_frame = Engine.get_process_frames()  # the closing key must not also act on the map


func _on_menu(id: String) -> void:
	match id:
		"resume", "cancel":
			_close_menu()
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
			OptionsView.popup(self).closed.connect(func():
				menu.visible = true
				_bake())  # map markings may have changed (issue #192)
		"save", "load":
			slot_mode = id
			menu.visible = false
			slot_menu.setup(tr("Save to which slot?") if id == "save" else tr("Load which save?"), Saves.slot_items(id == "save"))
			slot_menu.visible = true
		"town":
			_leave(Saves.HUB_SCENE)
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
		"journal":
			_close_menu()
			journal_view.open()
		"title":
			_leave(TITLE_SCENE)


func _on_slot(id: String) -> void:
	if id == "back" or id == "cancel":
		slot_menu.visible = false
		(over_menu if Empire.territory().find("hollowmark")["owner"] == "erased" else menu).visible = true
		return
	if slot_mode == "load":
		Saves.load_and_play(id)
		return
	var ok := Saves.save(id, snapshot())
	slot_menu.visible = false
	_menu_items((tr("Saved to %s.") % Saves.slot_label(id)) if ok else tr("Saving failed. Your browser may be blocking storage."))
	menu.visible = true


func snapshot() -> Dictionary:
	return {"scene": Saves.COMMAND_SCENE, "area_name": tr("Command Table")}


func autosave() -> void:
	Saves.save("auto", snapshot())


## Leaves Command for another scene, autosaving first so the empire is never lost.
func _leave(scene: String) -> void:
	autosave()
	get_tree().paused = false
	get_tree().change_scene_to_file(scene)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_inside_tree():
			autosave()


## The map's window on screen.
func _map_rect() -> Rect2:
	return Rect2(MAP_ORIGIN, MAP_VIEW)


## Where the whole world lands on screen at the current pan and zoom.
func _world_rect() -> Rect2:
	return Rect2(_cell_to_screen(Vector2.ZERO), Vector2(MAP_CELLS) * zoom)


func _cell_to_screen(c: Vector2) -> Vector2:
	return MAP_ORIGIN + MAP_VIEW / 2.0 + (c - cam) * zoom


func _screen_to_cell(pos: Vector2) -> Vector2:
	return (pos - MAP_ORIGIN - MAP_VIEW / 2.0) / zoom + cam


func _province_screen_pos(p: Dictionary) -> Vector2:
	return _cell_to_screen((p["center"] as Vector2) * Vector2(MAP_CELLS))


# ---------------------------------------------------------------- camera (issue #53)

## Zoomed all the way out, the whole Inklands fits the window.
func zoom_min() -> float:
	return minf(MAP_VIEW.x / MAP_CELLS.x, MAP_VIEW.y / MAP_CELLS.y)


## Keeps the camera over the world: no panning off into nothing. A world smaller than the window
## (zoomed out) sits in its middle.
func _clamp_cam(c: Vector2, z: float) -> Vector2:
	var half := MAP_VIEW / 2.0 / z
	var out := c
	for a in 2:
		if half[a] * 2.0 >= MAP_CELLS[a]:
			out[a] = MAP_CELLS[a] / 2.0
		else:
			out[a] = clampf(c[a], half[a], MAP_CELLS[a] - half[a])
	return out


## Fits the camera round the given regions (all of them when the list is empty).
func frame_regions(ids: Array, instant := false) -> void:
	var box := Rect2()
	for r in territory.regions:
		if ids.is_empty() or r["id"] in ids:
			box = r["frame"] if box.size == Vector2.ZERO else box.merge(r["frame"])
	if box.size == Vector2.ZERO:
		box = Rect2(Vector2.ZERO, Vector2(MAP_CELLS))
	zoom_to = clampf(minf(MAP_VIEW.x / box.size.x, MAP_VIEW.y / box.size.y), zoom_min(), 2.2)
	cam_to = _clamp_cam(box.get_center(), zoom_to)
	if instant:
		zoom = zoom_to
		cam = cam_to


## Zooms by `f`, keeping the map point under `at` (screen) where it is.
func zoom_by(f: float, at := Vector2.INF) -> void:
	if at == Vector2.INF:
		at = MAP_ORIGIN + MAP_VIEW / 2.0
	var anchor := _screen_to_cell(at)
	var nz := clampf(zoom_to * f, zoom_min(), ZOOM_MAX)
	# Solve for the camera that keeps `anchor` under `at` at the new zoom.
	cam_to = _clamp_cam(anchor - (at - MAP_ORIGIN - MAP_VIEW / 2.0) / nz, nz)
	zoom_to = nz
	if at != MAP_ORIGIN + MAP_VIEW / 2.0:
		zoom = zoom_to  # wheel and pinch zoom track the pointer exactly
		cam = cam_to


## Pans so a province is well inside the window (keyboard, gamepad and "go there" selection).
func _follow(i: int, centre := false) -> void:
	if i < 0:
		return
	var pos := _province_screen_pos(territory.provinces[i])
	var inner := _map_rect().grow(-48.0)
	if centre or not inner.has_point(pos):
		cam_to = _clamp_cam((territory.provinces[i]["center"] as Vector2) * Vector2(MAP_CELLS), zoom_to)


func _process_camera(delta: float) -> void:
	var k := Access.ease_k(delta, 9.0)  # reduced camera motion jumps instead of sweeping (issue #192)
	zoom = lerpf(zoom, zoom_to, k)
	cam = cam.lerp(cam_to, k)
	if absf(zoom - zoom_to) < 0.002:
		zoom = zoom_to
	if cam.distance_to(cam_to) < 0.05:
		cam = cam_to
	cam = _clamp_cam(cam, zoom)


## The zoom buttons in the map's top-left corner: in, out, whole map.
func _zoom_button_rect(i: int) -> Rect2:
	return Rect2(MAP_ORIGIN + Vector2(6 + i * 19, 20), Vector2(17, 15))


# ---------------------------------------------------------------- baking

## Cells from a sea cell to the nearest land, up to 5 (for coast ripples on the parchment map).
func _sea_dist(x: int, y: int) -> int:
	for d in range(1, 6):
		for o in [Vector2i(d, 0), Vector2i(-d, 0), Vector2i(0, d), Vector2i(0, -d)]:
			var c := territory.cell(x + o.x, y + o.y)
			if c >= 0 and c != territory.SEA:
				return d
	return 9


var _cells := {}  # per-cell values that never change, worked out by the first bake (see _bake_static)


## Noise and borders per map cell. The grid never changes, so this runs once per scene and keeps the
## daily re-bake cheap (it runs at every dawn).
func _bake_static() -> void:
	var w := MAP_CELLS.x
	var h := MAP_CELLS.y
	var grain := FastNoiseLite.new()
	grain.seed = 3
	grain.frequency = 0.09
	var patch := FastNoiseLite.new()
	patch.seed = 11
	patch.frequency = 0.06
	patch.fractal_octaves = 2
	var mist := FastNoiseLite.new()
	mist.seed = 23
	mist.frequency = 0.03
	mist.fractal_octaves = 4
	var minx := []
	var maxx := []
	for p in territory.provinces:
		minx.append(1e9)
		maxx.append(-1e9)
	for y in h:
		for x in w:
			var r := territory.cell(x, y)
			if r >= 0:
				minx[r] = minf(minx[r], x)
				maxx[r] = maxf(maxx[r], x)
	var g := PackedFloat32Array()
	var n := PackedFloat32Array()
	var m := PackedFloat32Array()
	var east := PackedFloat32Array()
	var flags := PackedByteArray()  # 1 = province border, 2 = region border, 4 = the Blank's wall
	g.resize(w * h)
	n.resize(w * h)
	m.resize(w * h)
	east.resize(w * h)
	flags.resize(w * h)
	for y in h:
		# The Blank itself: a wobbling wall of paper down the far east edge, over land and sea.
		var edge := Territory.wall_x(y, h)
		for x in w:
			var i := y * w + x
			var r := territory.cell(x, y)
			g[i] = grain.get_noise_2d(x, y)
			var f := 4 if float(x) / w > edge else 0
			if r >= 0:
				n[i] = (patch.get_noise_2d(x, y) + 1.0) * 0.5
				# Clouds of mist: mostly thin, thick in drifts, so the painting peeks through the fog.
				m[i] = clampf((mist.get_noise_2d(x, y) + 0.35) * 1.4, 0.0, 1.0)
				east[i] = (x - float(minx[r])) / maxf(float(maxx[r]) - float(minx[r]), 1.0)
				if _is_border(x, y, r):
					f |= 1
				if _is_region_border(x, y, r):
					f |= 2
			flags[i] = f
	_cells = {"g": g, "n": n, "m": m, "east": east, "flags": flags}


func _bake() -> void:
	if _cells.is_empty():
		_bake_static()
	var w := MAP_CELLS.x
	var h := MAP_CELLS.y
	var g: PackedFloat32Array = _cells["g"]
	var nz: PackedFloat32Array = _cells["n"]
	var mz: PackedFloat32Array = _cells["m"]
	var east: PackedFloat32Array = _cells["east"]
	var flags: PackedByteArray = _cells["flags"]
	var px := PackedByteArray()
	px.resize(w * h * 4)
	var fog := PackedByteArray()
	fog.resize(w * h * 4)
	# What each province looks like today.
	var open := []
	var wash := []
	var fray := []
	var erased := []
	var hatch := Access.map_symbols  # Unravelling land is hatched, not only greyer (issue #192)
	for p in territory.provinces:
		open.append(Empire.province_open(p))
		wash.append(owner_color(p["owner"]))
		fray.append(float(p["fray"]) / 100.0)
		erased.append(p["owner"] == "erased")
	outlines = []
	for p in territory.provinces:
		outlines.append(PackedVector2Array())
	var white := PackedByteArray()
	white.resize(w * h)
	var border := Color(BORDER_COLOR, 0.8) if painted_tex else BORDER_COLOR
	for y in h:
		for x in w:
			var i := y * w + x
			var r := territory.cell(x, y)
			var f := flags[i]
			var col := Color(0, 0, 0, 0)
			var is_white := false
			if f & 4:
				col = PAPER
				is_white = true
			elif r == territory.SEA:
				if not painted_tex:  # no painting: the inked parchment sea
					var coast := _sea_dist(x, y)
					col = SEA_PARCH.darkened(0.06 * g[i])
					if coast > 5 and int(y + sin(x * 0.3) * 1.5) % 10 == 0 and (x / 4 + y / 10) % 4 == 0:
						col = SEA_INK  # short wave dashes out at sea
					if coast == 2 and (x + y) % 2 == 0:
						col = SEA_INK  # a dotted ripple along the shore
			elif not open[r]:
				# Beyond the fog: no wash, the painting shows through the drifting mist layer.
				var m := mz[i]
				var fc := FOG.lightened(0.1 * m)
				var o := i * 4
				fog[o] = int(fc.r8)
				fog[o + 1] = int(fc.g8)
				fog[o + 2] = int(fc.b8)
				fog[o + 3] = int(255.0 * (0.3 + 0.62 * m))
				if f & 2:
					col = Color(BORDER_COLOR, 0.55)
				if f & 1:
					outlines[r].append(Vector2(x, y))  # fogged provinces still highlight when picked
			else:
				var fr: float = fray[r]
				var gg := g[i]
				if erased[r] or fr >= 1.0 or fr > (1.0 - east[i]) * 0.75 + nz[i] * 0.45:
					col = PAPER.darkened(0.05 if gg > 0.3 else 0.0)
					is_white = true
				else:
					var oc: Color = wash[r]
					if painted_tex:
						# A translucent wash of the owner's colour over the painting; unclaimed land stays bare.
						var lum := LAND_PARCH.lerp(oc, 0.62 + gg * 0.12).get_luminance()
						col = oc.lerp(Color(lum, lum, lum), fr * 0.6)
						col.a = 0.1 if territory.provinces[r]["owner"] == "free" else 0.34 + gg * 0.06
					else:
						# A watercolour wash of the owner's colour over the parchment, mottled by the grain;
						# Fray drains colour from the whole province, like the field shader does.
						col = LAND_PARCH.lerp(oc, 0.62 + gg * 0.12)
						var grey := col.get_luminance()
						col = col.lerp(Color(grey, grey, grey), fr * 0.6)
				if hatch and fr >= UNRAVEL and not is_white and (x + y) % 4 == 0:
					col = MARK_INK.lerp(Color(col, 1.0), 0.45)
					col.a = 0.6 if painted_tex else 1.0
				if f & 1:
					col = border
					is_white = false
					outlines[r].append(Vector2(x, y))
			var o2 := i * 4
			px[o2] = int(col.r8)
			px[o2 + 1] = int(col.g8)
			px[o2 + 2] = int(col.b8)
			px[o2 + 3] = int(col.a8)
			white[i] = 1 if is_white else 0
	blank_edge = PackedVector2Array()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if white[y * w + x] == 1 and (white[y * w + x - 1] == 0 or white[y * w + x + 1] == 0 or white[(y - 1) * w + x] == 0 or white[(y + 1) * w + x] == 0):
				blank_edge.append(Vector2(x, y))
	map_tex = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px))
	fog_tex = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, fog))


## Under the fog only the outline of the region shows, not its provinces.
func _is_region_border(x: int, y: int, r: int) -> bool:
	var rid: String = territory.provinces[r]["region"]
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := territory.cell(x + o.x, y + o.y)
		if c >= 0 and territory.provinces[c]["region"] != rid:
			return true
	return false


## The wash colour for an owner: yours, unclaimed, erased, or the faction's own colour.
func owner_color(owner: String) -> Color:
	if OWNER_COLORS.has(owner):
		return OWNER_COLORS[owner]
	var c = Empire.faction(owner).get("color", "")
	return Color(str(c)) if str(c) != "" else Color("7a6a8a")


func owner_name(owner: String) -> String:
	if OWNER_NAMES.has(owner):
		return Loc.t(OWNER_NAMES[owner])
	return str(Empire.faction(owner).get("name", owner.capitalize()))


func _is_border(x: int, y: int, r: int) -> bool:
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if territory.cell(x + o.x, y + o.y) != r:
			return true
	return false


# ---------------------------------------------------------------- input

func _process(delta: float) -> void:
	t += delta
	Empire.tick(delta)
	Empire.playtime += delta
	toast_t = maxf(toast_t - delta, 0.0)
	deltas_t = maxf(deltas_t - delta, 0.0)
	for n in notices:
		n[2] -= delta
	notices = notices.filter(func(n): return n[2] > 0.0)
	autosave_t -= delta
	if autosave_t <= 0.0:
		autosave_t = AUTOSAVE_EVERY
		autosave()
	_process_camera(delta)
	queue_redraw()
	for c in map_canvas.get_parent().get_children():
		(c as CanvasItem).queue_redraw()
	overlay.queue_redraw()
	var frame := Engine.get_process_frames()
	if frame == menu_closed_frame or roster_view.visible or frame == roster_view.closed_frame \
			or buildings_view.visible or frame == buildings_view.closed_frame \
			or governor_view.visible or frame == governor_view.closed_frame \
			or expedition_view.visible or frame == expedition_view.closed_frame \
			or research_view.visible or frame == research_view.closed_frame \
			or diplomacy_view.visible or frame == diplomacy_view.closed_frame \
			or bonds_view.visible or frame == bonds_view.closed_frame \
			or newcomers_view.visible or frame == newcomers_view.closed_frame \
			or party_picker.visible or frame == party_picker.closed_frame \
			or gear_view.visible or frame == gear_view.closed_frame \
			or journal_view.visible or frame == journal_view.closed_frame \
			or armory_view.visible or frame == armory_view.closed_frame:
		return
	if Input.is_action_just_pressed("roster"):
		roster_view.open()
		return
	if Input.is_action_just_pressed("buildings"):
		buildings_view.open()
		return
	if Input.is_action_just_pressed("govern"):
		_open_governor()
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
	for i in Empire.SPEEDS.size():
		if Input.is_action_just_pressed("clock_speed_%d" % i):
			Empire.set_speed(i)
	if Input.is_action_just_pressed("clock_slower"):
		Empire.set_speed(Empire.speed - 1)
	elif Input.is_action_just_pressed("clock_faster"):
		Empire.set_speed(Empire.speed + 1)
	if Input.is_action_just_pressed("ledger"):
		show_ledger = not show_ledger
	if Input.is_action_just_pressed("map_zoom_in"):
		zoom_by(1.4)
	elif Input.is_action_just_pressed("map_zoom_out"):
		zoom_by(1.0 / 1.4)
	elif Input.is_action_just_pressed("map_zoom_toggle"):
		_toggle_fit()
	var pan := Input.get_vector("map_pan_left", "map_pan_right", "map_pan_up", "map_pan_down")
	if pan != Vector2.ZERO:
		cam_to = _clamp_cam(cam_to + pan * delta * 260.0 / zoom, zoom_to)
		cam = _clamp_cam(cam.lerp(cam_to, 0.5), zoom)
	var dir := Vector2.ZERO
	if Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left"):
		dir = Vector2.LEFT
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
		dir = Vector2.RIGHT
	elif Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		dir = Vector2.UP
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		dir = Vector2.DOWN
	if dir != Vector2.ZERO:
		_step(dir)
		_follow(selected)
	if Input.is_action_just_pressed("ui_accept"):
		_activate(selected)
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		_open_menu()


## Moves the selection to the best province in a direction: close, and roughly that way.
## Fogged regions count as one stop each (their middle province), so the stick does not wander
## through provinces nobody can use yet.
func _step(dir: Vector2) -> void:
	var from: Vector2 = territory.provinces[selected]["center"]
	var best := -1
	var best_score := 1e9
	var stops := {}
	for r in territory.regions:
		if Empire.region_open(r["id"]):
			continue
		var mid: Vector2 = (r["bounds"] as Rect2).get_center() / Vector2(MAP_CELLS)
		var near := -1
		for i in r["provinces"]:
			if near < 0 or (territory.provinces[i]["center"] as Vector2).distance_to(mid) < (territory.provinces[near]["center"] as Vector2).distance_to(mid):
				near = i
		stops[near] = true
	for p in territory.provinces:
		if p["index"] == selected or not (Empire.province_open(p) or stops.has(p["index"])):
			continue
		var d: Vector2 = (p["center"] as Vector2) - from
		var cosang := d.normalized().dot(dir)
		if cosang < 0.35:
			continue
		var score := d.length() / (cosang * cosang)
		if score < best_score:
			best_score = score
			best = p["index"]
	if best >= 0:
		selected = best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hovered = _province_at(event.position)
		ledger_hover = _res_rect().has_point(event.position)
		if drag_from != Vector2.INF:
			_drag_to(event.position)
		return
	if event is InputEventMouseButton:
		var pos: Vector2 = event.position
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _map_rect().has_point(pos):
				zoom_by(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, pos)
				accept_event()
			return
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed and _map_rect().has_point(pos):
				_drag_start(pos)
				dragged = true  # these buttons only ever pan
			elif not event.pressed:
				drag_from = Vector2.INF
			return
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_release(pos)
			return
	if event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() >= 2:
			var ks := touches.keys()
			var a: Vector2 = touches[ks[0]]
			var b: Vector2 = touches[ks[1]]
			var d := a.distance_to(b)
			if pinch_d > 0.0:
				zoom_by(d / pinch_d, (a + b) / 2.0)
			pinch_d = d
		elif drag_from != Vector2.INF:
			_drag_to(event.position)
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() >= 2:  # a second finger: pinch, and the first finger's tap is off
				var ks := touches.keys()
				pinch_d = (touches[ks[0]] as Vector2).distance_to(touches[ks[1]])
				dragged = true
				return
		else:
			touches.erase(event.index)
			pinch_d = 0.0
			if touches.is_empty():
				_release(event.position)
			return
	if not Prompts.tapped(event):
		return
	var tp: Vector2 = event.position
	var zb := _zoom_button_at(tp)
	if zb >= 0:
		match zb:
			0: zoom_by(1.4)
			1: zoom_by(1.0 / 1.4)
			2: _toggle_fit()
		return
	if _map_rect().has_point(tp) and not _over_map_buttons(tp):
		_drag_start(tp)  # the tap happens on release, unless the pointer moved: then it was a pan
		return
	if _governor_button_rect().has_point(tp) and _can_govern(selected):
		_open_governor()
	elif _play_rect().has_point(tp):
		_activate(selected)
	elif _roster_button_rect().has_point(tp):
		roster_view.open()
	elif _buildings_button_rect().has_point(tp):
		buildings_view.open()
	elif _expeditions_button_rect().has_point(tp):
		expedition_view.open()
	elif _research_button_rect().has_point(tp):
		research_view.open()
	elif _diplomacy_button_rect().has_point(tp):
		diplomacy_view.open()
	elif _journal_button_rect().has_point(tp):
		journal_view.open()
	elif _town_button_rect().has_point(tp):
		_leave(Saves.HUB_SCENE)
	elif _res_rect().has_point(tp):
		show_ledger = not show_ledger
	elif _menu_button_rect().has_point(tp):
		_open_menu()
	else:
		for sp in Empire.SPEEDS.size():
			if _speed_rect(sp).has_point(tp):
				Empire.set_speed(sp)


## The screen buttons that sit over the map's top edge.
func _over_map_buttons(pos: Vector2) -> bool:
	for r in [_roster_button_rect(), _buildings_button_rect(), _town_button_rect(), _expeditions_button_rect(),
			_research_button_rect(), _diplomacy_button_rect(), _journal_button_rect()]:
		if (r as Rect2).has_point(pos):
			return true
	return false


func _zoom_button_at(pos: Vector2) -> int:
	for i in 3:
		if _zoom_button_rect(i).has_point(pos):
			return i
	return -1


## Whole map <-> the open regions.
func _toggle_fit() -> void:
	if zoom_to <= zoom_min() + 0.05:
		frame_regions(Empire.regions_open)
	else:
		zoom_to = zoom_min()
		cam_to = _clamp_cam(Vector2(MAP_CELLS) / 2.0, zoom_to)


func _drag_start(pos: Vector2) -> void:
	drag_from = pos
	drag_cam = cam
	dragged = false


func _drag_to(pos: Vector2) -> void:
	if not dragged and pos.distance_to(drag_from) > 5.0:
		dragged = true
	if dragged:
		cam = _clamp_cam(drag_cam - (pos - drag_from) / zoom, zoom)
		cam_to = cam


## Pointer up on the map: a tap selects (a second tap on the selected province plays its mission).
func _release(pos: Vector2) -> void:
	if drag_from == Vector2.INF:
		return
	var tap := not dragged
	drag_from = Vector2.INF
	if not tap:
		return
	var i := _province_at(pos)
	if i >= 0:
		if i == selected:
			_activate(i)
		selected = i


func _province_at(pos: Vector2) -> int:
	if not _map_rect().has_point(pos):
		return -1
	var c := _screen_to_cell(pos).floor()
	return territory.cell(int(c.x), int(c.y))


func _mission(i: int) -> Dictionary:
	return Missions.for_province(territory.provinces[i]["id"])


func _activate(i: int) -> void:
	if not Empire.province_open(territory.provinces[i]):
		return
	var m := _mission(i)
	if not m.is_empty():
		_open_brief(m)


## The briefing: what the mission is, what it asks, what it pays. Go launches it.
func _open_brief(m: Dictionary) -> void:
	brief_mission = m
	var lines := []
	for line in _wrap_words(m.get("brief", ""), 64):
		lines.append(line)
	lines.append("")
	lines.append(tr("%s mission   ·   Threat %s") % [Missions.type_name(m), Missions.threat_text(m)])  # #113
	lines.append(tr("Objective: ") + Objective.describe(m.get("objective", {})))
	if m.has("force"):
		lines.append(tr("Personal: %s comes along, whoever else you pick.") % Empire.short_name(m["force"]))
	elif m.has("escort"):
		lines.append(tr("Escort: %s can't fight. Keep them on their feet.") % Empire.short_name(m["escort"]))
	lines.append(tr("Expect: ") + EnemyKinds.names(m))
	var rew := Missions.reward_text(m)
	if rew != "":
		lines.append(tr("Reward: ") + rew)
	if int(m.get("until_day", -1)) >= Empire.day:
		var left := int(m["until_day"]) - Empire.day
		lines.append(tr("Offered today only.") if left == 0 else tr("Offered for %d more day%s.") % [left, "" if left == 1 else "s"])
	if int(m.get("fray", 0)) < 0:
		lines.append(tr("Pushes the Blank back: %d Fray in %s") % [int(m["fray"]), territory.find(m.get("province", "")).get("name", "")])
	if m.has("cost_text"):
		lines.append(tr("Cost: ") + m["cost_text"])
	lines.append(tr("The clock stops while you are away."))
	var blocker: String = str(m.get("blocker", ""))
	var items := [{"id": "go", "label": tr("Set out"), "enabled": blocker == "", "note": "(%s)" % blocker}]
	# Other missions in the same province: switch the briefing to them.
	var others := Missions.list_for_province(m.get("province", "")).filter(func(o): return o.get("id", "") != m.get("id", ""))
	for o in others:
		items.append({"id": "other:" + str(o["id"]), "label": tr("Instead: ") + str(o["name"])})
	items.append({"id": "back", "label": tr("Back")})
	brief_menu.setup(m.get("name", tr("Mission")), items, "\n".join(lines))
	brief_menu.visible = true
	get_tree().paused = true


func _on_brief(id: String) -> void:
	if id.begins_with("other:"):
		for o in Missions.list_for_province(brief_mission.get("province", "")):
			if "other:" + str(o["id"]) == id:
				_open_brief(o)
				return
	brief_menu.visible = false
	get_tree().paused = false
	menu_closed_frame = Engine.get_process_frames()
	if id == "go":
		party_picker.open(brief_mission)  # pick who goes; Set out there calls _launch_mission


## Leaves for a mission: autosave the empire, then load the mission's map.
func _launch_mission(m: Dictionary) -> void:
	autosave()  # the clock stops here: missions take no Command time
	Missions.launch(m)


func _wrap_words(s: String, width: int) -> Array:
	var out := []
	var cur := ""
	for w in s.split(" "):
		if cur != "" and (cur + " " + w).length() > width:
			out.append(cur)
			cur = w
		else:
			cur = w if cur == "" else cur + " " + w
	if cur != "":
		out.append(cur)
	return out


## R in the party picker: sort people out in the Roster, then come back to the picker.
func _roster_from_picker() -> void:
	roster_view.open()
	roster_view.closed.connect(party_picker.reopen, CONNECT_ONE_SHOT)


func _open_governor() -> void:
	if _can_govern(selected):
		governor_view.open(territory.provinces[selected]["id"])


## The governor screen opens for your provinces and for unclaimed ones (to claim them).
func _can_govern(i: int) -> bool:
	return territory.provinces[i]["owner"] in ["you", "free"] and Empire.province_open(territory.provinces[i])


var _gov_button_y := -100.0  # set while drawing the panel


func _governor_button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 92, _gov_button_y - 10), Vector2(86, 14))


func _roster_button_rect() -> Rect2:
	return Rect2(Vector2(MAP_ORIGIN.x + MAP_VIEW.x - 74, MAP_ORIGIN.y + 4), Vector2(70, 16))


func _buildings_button_rect() -> Rect2:
	var rb := _roster_button_rect()
	return Rect2(rb.position - Vector2(80, 0), Vector2(76, 16))


func _town_button_rect() -> Rect2:
	var bb := _buildings_button_rect()
	return Rect2(bb.position - Vector2(58, 0), Vector2(54, 16))


func _expeditions_button_rect() -> Rect2:
	var tb := _town_button_rect()
	return Rect2(tb.position - Vector2(86, 0), Vector2(82, 16))


## Second row, under Roster.
func _research_button_rect() -> Rect2:
	var rb := _roster_button_rect()
	return Rect2(Vector2(rb.end.x - 96, rb.end.y + 3), Vector2(96, 16))


## Second row, left of Research.
func _diplomacy_button_rect() -> Rect2:
	var rs := _research_button_rect()
	return Rect2(rs.position - Vector2(90, 0), Vector2(86, 16))


## Second row, left of Diplomacy (issue #114).
func _journal_button_rect() -> Rect2:
	var db := _diplomacy_button_rect()
	return Rect2(db.position - Vector2(78, 0), Vector2(74, 16))


func _speed_rect(i: int) -> Rect2:
	return Rect2(Vector2(452 + i * 34, 3), Vector2(31, 15))


func _menu_button_rect() -> Rect2:
	return Rect2(Vector2(size.x - 46, 3), Vector2(42, 15))


func _play_rect() -> Rect2:
	return Rect2(PANEL_X, size.y - 34, size.x - PANEL_X - 6, 26)


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, outline := 0) -> void:
	if outline > 0:
		_cv.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), outline, Color(0, 0, 0, 0.85 * col.a))
	_cv.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize), col)


func _text_c(center: Vector2, s: String, fsize: int, col: Color, outline := 0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	_text(center - Vector2(w / 2.0, 0), s, fsize, col, outline)


## "  R" (keyboard), "  Y" (pad) or "" (touch, or no button): the shortcut on a button label.
func _k(action: String) -> String:
	var k := Prompts.key(action)
	return "" if k == "" else "  " + k


func _draw() -> void:
	_cv = self
	draw_rect(Rect2(Vector2.ZERO, size), Color("0e0b12"))
	UiSkin.panel(self, _map_rect().grow(5.0), "ledger")  # brass-cornered frame round the parchment
	draw_rect(_map_rect(), SEA_PARCH.darkened(0.12))  # open sea past the edge of the world


## The painting and the fog over locked regions (smooth filtering).
func _draw_paint(c: CanvasItem) -> void:
	var wr := _world_rect()
	if painted_tex:
		c.draw_texture_rect(painted_tex, wr, false)
	if fog_tex:
		# Two layers of the same mist, drifting against each other, so the fog billows.
		var drift := Vector2.ZERO if Access.reduce_motion else Vector2(sin(t * 0.13), cos(t * 0.09)) * 2.5 * zoom
		c.draw_texture_rect(fog_tex, Rect2(wr.position + drift, wr.size), false, Color(1, 1, 1, 0.75))
		c.draw_texture_rect(fog_tex, Rect2(wr.position - drift * 0.7 + Vector2(0, zoom), wr.size), false, Color(1, 1, 1, 0.55))


## Everything else on the map (crisp pixels), clipped to the map's window.
func _draw_map(c: CanvasItem) -> void:
	_cv = c
	_cv.draw_texture_rect(map_tex, _world_rect(), false)
	_draw_roads()
	_draw_static()
	_draw_outline(selected, GOLD)
	if hovered >= 0 and hovered != selected:
		_draw_outline(hovered, Color(1, 1, 1, 0.55))
	_draw_labels()
	_draw_region_names()
	_cv = self


## Buttons, legend, the province panel and toasts, over the map.
func _draw_overlay(c: CanvasItem) -> void:
	_cv = c
	_cv.draw_rect(_map_rect(), Color("2a2019"), false, 1.0)
	_draw_zoom_buttons()
	# Top bar
	_text(MAP_ORIGIN + Vector2(6, 14), tr("THE INKLANDS"), 10, Color(0.85, 0.82, 0.76, 0.8), 3)
	_draw_resources()
	_draw_clock()
	var rb := _roster_button_rect()
	UiSkin.panel(_cv, rb, "button")
	_text_c(Vector2(rb.get_center().x, rb.position.y + 12), tr("Roster (%d)") % Empire.recruits.size() + _k("roster"), 9, Color(0.85, 0.82, 0.76))
	var bb := _buildings_button_rect()
	UiSkin.panel(_cv, bb, "button")
	var busy := "" if Empire.construction.is_empty() else " *"
	_text_c(Vector2(bb.get_center().x, bb.position.y + 12), tr("Buildings%s") % busy + _k("buildings"), 9, GOLD if busy != "" else Color(0.85, 0.82, 0.76))
	var tb := _town_button_rect()
	UiSkin.panel(_cv, tb, "button")
	_text_c(Vector2(tb.get_center().x, tb.position.y + 12), tr("To town"), 9, Color(0.85, 0.82, 0.76))
	var eb := _expeditions_button_rect()
	if not _draw_locked_button(eb, tr("Expeditions"), "expeditions"):
		UiSkin.panel(_cv, eb, "button")
		var unread := Empire.unread_reports()
		var out := Empire.expeditions.size()
		var etext := tr("Expeditions")
		if unread > 0:
			etext = tr("Reports (%d)") % unread
		elif out > 0:
			etext = tr("Squads out: %d") % out
		_text_c(Vector2(eb.get_center().x, eb.position.y + 12), etext + _k("expeditions"), 9, GOLD if unread > 0 else Color(0.85, 0.82, 0.76))
	var rsb := _research_button_rect()
	if not _draw_locked_button(rsb, tr("Research"), "research"):
		UiSkin.panel(_cv, rsb, "button")
		var rtext := tr("Research")
		var rcol := Color(0.85, 0.82, 0.76)
		if Empire.research_active != "":
			var stalled := float(Empire.research_pace()["pace"]) <= 0.0
			rtext = tr("Research %d%%%s") % [int(Empire.research_fraction(Empire.research_active) * 100), tr(" (stalled)") if stalled else ""]
			rcol = Color(1, 0.55, 0.5) if stalled else Color("d7b8f0")
		_text_c(Vector2(rsb.get_center().x, rsb.position.y + 12), rtext + _k("research"), 9, rcol)
	var db := _diplomacy_button_rect()
	if not _draw_locked_button(db, tr("Diplomacy"), "diplomacy"):
		UiSkin.panel(_cv, db, "button")
		var dtext := tr("Diplomacy")
		var dcol := Color(0.85, 0.82, 0.76)
		if Empire.surge.get("id", "") != "" and Empire.surge.get("aid", "") == "" and Empire.territory().find(Empire.surge["id"]).get("owner", "") == "you" \
				and Empire.faction_ids().any(func(f): return Empire.deal_blocker(f, "aid") == ""):
			dtext = tr("Ask for aid!")
			dcol = GOLD
		_text_c(Vector2(db.get_center().x, db.position.y + 12), dtext + _k("diplomacy"), 9, dcol)
	var jb := _journal_button_rect()
	UiSkin.panel(_cv, jb, "button")
	var jnew := Journal.unread_count() > 0
	_text_c(Vector2(jb.get_center().x, jb.position.y + 12), tr("Journal%s") % (" *" if jnew else "") + _k("journal"), 9, GOLD if jnew else Color(0.85, 0.82, 0.76))
	_draw_legend()
	_draw_panel()
	if toast_t > 0.0:
		var a := clampf(toast_t / 0.5, 0.0, 1.0)
		_text_c(Vector2(_map_rect().get_center().x, MAP_ORIGIN.y + 22), toast, 12, Color(1, 0.95, 0.85, a), 4)
		if toast2 != "":
			_text_c(Vector2(_map_rect().get_center().x, MAP_ORIGIN.y + 36), toast2, 9, Color(1, 0.55, 0.5, a), 4)
	if show_ledger or ledger_hover:
		_draw_ledger()
	if Empire.SPEEDS[Empire.speed] == 0:
		_text_c(Vector2(_map_rect().get_center().x, MAP_ORIGIN.y + MAP_VIEW.y - 24), tr("TIME PAUSED"), 11, Color(1, 1, 1, 0.55 + 0.25 * sin(t * 3.0)), 4)
	_cv = self


## A screen the story has not opened yet (issue #115): a dimmed button with a padlock and the day it
## opens. Returns false (and draws nothing) when the screen is open.
func _draw_locked_button(r: Rect2, label: String, screen: String) -> bool:
	if Help.is_open(screen):
		return false
	UiSkin.panel(_cv, r, "button", Color(0.55, 0.52, 0.5))
	var note := Help.locked_note(screen)
	var s := "%s: %s" % [label, note]
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x
	var x := r.get_center().x - (w + 9.0) / 2.0
	var lk := Vector2(x + 3, r.position.y + 9)  # padlock: shackle over a body
	_cv.draw_arc(lk + Vector2(0, -2), 2.0, PI, TAU, 6, Color(0.6, 0.57, 0.53), 1.0)
	_cv.draw_rect(Rect2(lk + Vector2(-3, -1), Vector2(6, 5)), Color(0.6, 0.57, 0.53))
	_text(Vector2(x + 9, r.position.y + 11), s, 8, Color(0.6, 0.57, 0.53))
	return true


func _draw_zoom_buttons() -> void:
	var labels := ["+", "-", tr("All") if zoom_to > zoom_min() + 0.05 else tr("Back")]
	for i in 3:
		var r := _zoom_button_rect(i)
		if i == 2:
			r.size.x = 30
		UiSkin.panel(_cv, r, "button")
		_text_c(Vector2(r.get_center().x, r.position.y + 11), labels[i], 9, Color(0.85, 0.82, 0.76))
	# How to move the map, for the first moments on the table and whenever the pointer is on the buttons.
	var near := Rect2(_zoom_button_rect(0).position, Vector2(70, 15)).grow(4.0).has_point(get_local_mouse_position())
	var a := 1.0 if near else clampf((9.0 - t) / 2.0, 0.0, 1.0)
	if a > 0.0:
		var hint := tr("Wheel or + / - to zoom, drag to pan")
		if Prompts.touch():
			hint = tr("Pinch to zoom, drag to pan")
		elif Prompts.pad():
			hint = tr("Right stick pans, LT zooms")
		_text(_zoom_button_rect(0).position + Vector2(0, 25), hint, 7, Color(0.9, 0.87, 0.8, 0.85 * a), 3)


func _res_rect() -> Rect2:
	return Rect2(Vector2(2, 1), Vector2(222, 19))


const RES_COLORS := {"gilt": Color("e8c66a"), "supplies": Color("b7c98a"), "ink": Color("8fa7e8"), "renown": Color("e8a0c8")}


func _draw_res_icon(k: String, c: Vector2) -> void:
	if UiSkin.draw_icon(_cv, k, Rect2(c - Vector2(6, 6), Vector2(12, 12))):  # art pass icon, else the code-drawn mark
		return
	var col: Color = RES_COLORS[k]
	match k:
		"gilt":  # a coin
			_cv.draw_circle(c, 4.0, col)
			_cv.draw_circle(c, 2.0, col.darkened(0.35))
		"supplies":  # a sack
			_cv.draw_rect(Rect2(c + Vector2(-3, -2), Vector2(6, 6)), col)
			_cv.draw_rect(Rect2(c + Vector2(-1.5, -4), Vector2(3, 2)), col.darkened(0.3))
		"ink":  # a drop
			_cv.draw_circle(c + Vector2(0, 1), 3.0, col)
			_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-2.6, 0), c + Vector2(2.6, 0), c + Vector2(0, -5)]), col)
		"renown":  # a star-ish diamond
			_cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(4, 0), c + Vector2(0, 5), c + Vector2(-4, 0)]), col)


func _draw_resources() -> void:
	var net := Empire.daily_net()
	var x := 8.0
	for k in ["gilt", "supplies", "ink", "renown"]:
		_draw_res_icon(k, Vector2(x + 3, 10))
		var v := int(Empire.res[k])
		var col := Color("ece6da")
		if k == "supplies" and (Empire.hungry or v + int(net["supplies"]) < 0):
			col = Color("ff8a7a")
		_text(Vector2(x + 10, 15), str(v), 10, col)
		var w := font.get_string_size(str(v), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10)).x
		if net.has(k) and int(net[k]) != 0:
			var n := int(net[k])
			_text(Vector2(x + 12 + w, 15), ("+%d" if n > 0 else "%d") % n, 8, Color("9fd18b") if n > 0 else Color("ff8a7a"))
		if deltas_t > 0.0 and deltas.has(k) and int(deltas[k]) != 0:
			var d := int(deltas[k])
			var rise := (2.5 - deltas_t) * 6.0
			_text(Vector2(x + 10, 30 - rise + 10), ("+%d" if d > 0 else "%d") % d, 10, Color(0.62, 0.82, 0.55, minf(deltas_t, 1.0)) if d > 0 else Color(1, 0.55, 0.5, minf(deltas_t, 1.0)), 3)
		x += 56.0


## The ledger: where every point of daily income and upkeep comes from.
func _draw_ledger() -> void:
	var lines := Empire.ledger()
	var r := Rect2(Vector2(6, 22), Vector2(300, 54 + 13 * lines.size()))
	_cv.draw_rect(r, Color(0.06, 0.05, 0.08, 0.95))
	_cv.draw_rect(r, Color(0.45, 0.4, 0.48), false, 1.0)
	var y := r.position.y + 14
	_text(Vector2(r.position.x + 8, y), tr("Daily ledger"), 10, Color("f3efe4"))
	_text(Vector2(r.position.x + 150, y), tr("Gilt"), 8, RES_COLORS["gilt"])
	_text(Vector2(r.position.x + 182, y), tr("Supplies"), 8, RES_COLORS["supplies"])
	_text(Vector2(r.position.x + 226, y), tr("Ink"), 8, RES_COLORS["ink"])
	y += 14
	for line in lines:
		_text(Vector2(r.position.x + 8, y), line["label"], 9, Color(0.85, 0.83, 0.78))
		if line["note"] != "":
			_text(Vector2(r.position.x + 248, y), line["note"], 7, Color(0.6, 0.58, 0.6))
		var cx := [150, 182, 226]
		var ks := ["gilt", "supplies", "ink"]
		for i in 3:
			var v := int(line[ks[i]])
			if v != 0:
				_text(Vector2(r.position.x + cx[i], y), ("+%d" if v > 0 else "%d") % v, 9, Color("9fd18b") if v > 0 else Color("ff8a7a"))
		y += 13
	_cv.draw_line(Vector2(r.position.x + 8, y - 8), Vector2(r.end.x - 8, y - 8), Color(0.3, 0.27, 0.33))
	var net := Empire.daily_net()
	_text(Vector2(r.position.x + 8, y + 3), tr("Each dawn"), 9, Color("f3efe4"))
	var cx2 := [150, 182, 226]
	var ks2 := ["gilt", "supplies", "ink"]
	for i in 3:
		var v := int(net[ks2[i]])
		_text(Vector2(r.position.x + cx2[i], y + 3), ("+%d" if v >= 0 else "%d") % v, 9, Color("9fd18b") if v > 0 else (Color("ff8a7a") if v < 0 else Color(0.6, 0.58, 0.6)))
	_text(Vector2(r.position.x + 8, r.end.y - 6), tr("L / Back / tap the bar to toggle"), 7, Color(0.5, 0.48, 0.52))


func _draw_clock() -> void:
	# Day and time, with a little sun or moon and a bar through the day.
	var x := 236.0
	var night := Empire.day_t < 0.25 or Empire.day_t > 0.83
	if night:
		_cv.draw_circle(Vector2(x, 10), 4.0, Color("d8d4e8"))
		_cv.draw_circle(Vector2(x + 2, 9), 3.5, Color("0e0b12"))
	else:
		_cv.draw_circle(Vector2(x, 10), 4.0, GOLD)
	_text(Vector2(x + 9, 15), tr("Day %d") % Empire.day, 11, Color("ece6da"))
	_text(Vector2(x + 58, 15), Empire.clock_text(), 9, Color(0.75, 0.72, 0.7))
	_cv.draw_rect(Rect2(x + 92, 8, 100, 4), Color(0.18, 0.16, 0.2))
	_cv.draw_rect(Rect2(x + 92, 8, 100 * Empire.day_t, 4), Color(0.75, 0.72, 0.68))
	for i in Empire.SPEEDS.size():
		var r := _speed_rect(i)
		var on := i == Empire.speed
		_cv.draw_rect(r, Color(0.22, 0.17, 0.08) if on else Color(0.1, 0.09, 0.12))
		_cv.draw_rect(r, GOLD if on else Color(0.3, 0.27, 0.33), false, 1.0)
		var label := "II" if i == 0 else "%dx" % Empire.SPEEDS[i]  # no-tr: pause symbol
		_text_c(Vector2(r.get_center().x, r.position.y + 11), label, 9, GOLD if on else Color(0.75, 0.72, 0.7))
	var mr := _menu_button_rect()
	_cv.draw_rect(mr, Color(0.1, 0.09, 0.12))
	_cv.draw_rect(mr, Color(0.3, 0.27, 0.33), false, 1.0)
	_text_c(Vector2(mr.get_center().x, mr.position.y + 11), tr("Menu"), 9, Color(0.75, 0.72, 0.7))


func _draw_roads() -> void:
	var drawn := {}
	var view := _map_rect().grow(30.0)
	for p in territory.provinces:
		var a: int = p["index"]
		for b in territory.neighbors[a]:
			var key := Vector2i(mini(a, b), maxi(a, b))
			if drawn.has(key):
				continue
			drawn[key] = true
			var q: Dictionary = territory.provinces[b]
			if not (Empire.province_open(p) and Empire.province_open(q)):
				continue  # no roads drawn into the fog
			var p1 := _province_screen_pos(p)
			var p2 := _province_screen_pos(q)
			if not (view.has_point(p1) or view.has_point(p2)):
				continue
			var lost: bool = p["owner"] == "erased" or q["owner"] == "erased"
			var col := Color(0.12, 0.1, 0.14, 0.35 if lost else 0.75)
			# Dashed road.
			var n := int(p1.distance_to(p2) / 6.0)
			for i in n:
				if i % 2 == 0:
					_cv.draw_line(p1.lerp(p2, float(i) / n), p1.lerp(p2, float(i + 1) / n), col, 1.5)


func _draw_static() -> void:
	if blank_edge.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 10.0)
	var view := _map_rect()
	var dots := int(90.0 * clampf(zoom / 2.0, 0.6, 1.6))
	for i in dots:
		var c: Vector2 = blank_edge[rng.randi() % blank_edge.size()]
		var pos := _cell_to_screen(c) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		if not view.has_point(pos):
			continue
		var col := Color(0.06, 0.05, 0.07, 0.75) if rng.randf() < 0.5 else Color(0.98, 0.97, 0.94, 0.9)
		_cv.draw_rect(Rect2(pos, Vector2(2, 2)), col)


func _draw_outline(i: int, col: Color) -> void:
	var pulse := 0.75 + 0.25 * sin(t * 4.0) if col == GOLD else 1.0
	var c := Color(col, col.a * pulse)
	var sz := Vector2(ceilf(zoom), ceilf(zoom))
	for cell in outlines[i]:
		_cv.draw_rect(Rect2(_cell_to_screen(cell).floor(), sz), c)


func _draw_labels() -> void:
	var view := _map_rect().grow(40.0)
	var fsize := 9 if zoom >= ZOOM_READ else 8
	# Zoomed right out over a big realm, region names take over: provinces keep their dot, and only
	# the picked, hovered and busy ones keep their names.
	var overview := _overview()
	for p in territory.provinces:
		if not Empire.province_open(p):
			continue  # the fog shows the region's name instead
		var pos := _province_screen_pos(p)
		if not view.has_point(pos):
			continue
		if overview and p["index"] != selected and p["index"] != hovered and Empire.surge.get("id", "") != p["id"] \
				and MissionTypes.for_province(p["id"]).filter(func(m): return m["type"] != "defense").is_empty():
			if Access.map_symbols:
				_owner_mark(_cv, p["owner"], pos + Vector2(0, -9), 3.0)
			else:
				_cv.draw_circle(pos + Vector2(0, -9), 2.0, Color("15111b"))
			continue
		var col := Color("f3efe4")
		if p["owner"] == "erased":
			col = Color(0.35, 0.34, 0.36)
		if p["id"] == "hollowmark" and p["owner"] == "you":
			# A little ink-black tower for the capital.
			_cv.draw_rect(Rect2(pos + Vector2(-3, -15), Vector2(6, 8)), Color("15111b"))
			_cv.draw_colored_polygon(PackedVector2Array([pos + Vector2(-4, -15), pos + Vector2(4, -15), pos + Vector2(0, -20)]), Color("15111b"))
			_cv.draw_rect(Rect2(pos + Vector2(-1, -12), Vector2(2, 3)), GOLD)
		elif p["owner"] == "you":
			# Your flag on the rest of your land.
			_cv.draw_line(pos + Vector2(-1, -6), pos + Vector2(-1, -16), Color("15111b"), 1.0)
			_cv.draw_colored_polygon(PackedVector2Array([pos + Vector2(-1, -16), pos + Vector2(5, -14), pos + Vector2(-1, -12)]), owner_color("you").lightened(0.2))
		elif Access.map_symbols:
			_owner_mark(_cv, p["owner"], pos + Vector2(0, -9), 3.0)
		else:
			_cv.draw_circle(pos + Vector2(0, -9), 2.0, Color("15111b"))
		_text_c(pos + Vector2(0, 2), p["name"], fsize, col, 0 if p["owner"] == "erased" else 4)
		if Access.map_symbols and p["owner"] != "erased":
			_fray_chip(pos + Vector2(font.get_string_size(p["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x / 2.0 + 3.0, 2.0), int(p["fray"]))
		if Empire.surge.get("id", "") == p["id"]:
			# A gathering surge: a pulsing red ring and a countdown.
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			_cv.draw_arc(pos + Vector2(0, -6), 14.0 + pulse * 3.0, 0, TAU, 32, Color(1, 0.35, 0.3, 0.5 + 0.4 * pulse), 2.0)
			var dl := Empire.surge_days_left()
			_text_c(pos + Vector2(0, 13), tr("Surge %s") % (tr("today") if dl <= 0 else tr("in %d day%s") % [dl, "" if dl == 1 else "s"]), 8, Color(1, 0.55, 0.5), 3)
		# Type missions on offer: Reclaim, Rescue, Raid, Salvage, Personal (Defense already shows as the surge ring).
		var tags := []
		for tm in MissionTypes.for_province(p["id"]):
			if tm["type"] != "defense":
				tags.append(tm)
		var ty := 13.0 + (10.0 if Empire.surge.get("id", "") == p["id"] else 0.0)
		for tm in tags:
			var tcol: Color = MissionTypes.TYPE_COLORS[tm["type"]]
			if tm["blocker"] != "":
				tcol = tcol.darkened(0.45)
			_cv.draw_circle(pos + Vector2(-font.get_string_size(Loc.t(MissionTypes.TYPE_NAMES[tm["type"]]), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x / 2.0 - 5, ty - 3), 2.0 + (0.6 * sin(t * 4.0) if tm["blocker"] == "" else 0.0), tcol)
			_text_c(pos + Vector2(0, ty), Loc.t(MissionTypes.TYPE_NAMES[tm["type"]]), 8, tcol, 3)
			ty += 10.0


## True when zoomed out far over a realm of several open regions: region names over province names.
func _overview() -> bool:
	return zoom < 1.25 and Empire.regions_open.size() >= 2


## Region names: big over the fog of a locked region, with the chapter that opens it; over open
## regions only in the overview (see _overview()).
func _draw_region_names() -> void:
	for r in territory.regions:
		var open := Empire.region_open(r["id"])
		if open and not _overview():
			continue  # zoomed in, the province names say enough
		var lp: Array = r.get("label", [])
		var at: Vector2 = Vector2(lp[0], lp[1]) * Vector2(MAP_CELLS) if lp.size() == 2 else (r["bounds"] as Rect2).get_center()
		var pos := _cell_to_screen(at)
		var big := 13 if zoom >= 1.2 else 11
		# Keep the name out from under the screen buttons along the map's top edge: lower it when the
		# region reaches further down than they do, or leave it out.
		var half := font.get_string_size(str(r["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(big)).x / 2.0
		var clear_y := MAP_ORIGIN.y + 76.0
		var bottom := _cell_to_screen((r["bounds"] as Rect2).end).y
		if pos.y < clear_y and pos.x + half > MAP_ORIGIN.x + 128.0:
			if bottom < clear_y + 20.0:
				continue  # only a sliver of it shows up there: the fog speaks for itself
			pos.y = clear_y
		if not _map_rect().grow(60.0).has_point(pos):
			continue
		if open:
			_text_c(pos, str(r["name"]).to_upper(), big, Color(0.98, 0.95, 0.86, 0.85), 4)
			continue
		_text_c(pos, str(r["name"]).to_upper(), big, Color("f6f1e4"), 5)
		var ch := int(r.get("chapter", 0))
		var sub := (tr("Chapter %d") % ch) if ch > 0 else tr("Later in the story")
		_text_c(pos + Vector2(0, 12), sub + tr("  ·  beyond the fog"), 8, Color(0.25, 0.2, 0.16, 0.95), 0)


## A province under the fog: what the region is, what is rumoured there, and when the story opens it.
func _draw_region_panel(r: Dictionary, x: float, w: float) -> void:
	var y := 42.0
	_text(Vector2(x, y), str(r.get("name", tr("Uncharted"))), 15, Color("f3efe4"))
	y += 15
	_cv.draw_rect(Rect2(x, y - 7, 7, 7), FOG)
	_text(Vector2(x + 11, y), tr("Beyond the fog"), 9, Color(0.8, 0.78, 0.74))
	y += 20
	_text(Vector2(x, y), str(r.get("mood", "")), 9, Color("e8d9a8"))
	y += 16
	var hint: String = r.get("hint", "")
	_cv.draw_multiline_string(font, Vector2(x, y), hint, HORIZONTAL_ALIGNMENT_LEFT, w, Access.fs(9), -1, Color(0.85, 0.83, 0.78))
	y += 13 * ceilf(font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x / w) + 10
	var n: int = (r.get("provinces", []) as Array).size()
	_text(Vector2(x, y), tr("Provinces"), 9, Color(0.7, 0.68, 0.7))
	_text(Vector2(x + 60, y), tr("%d, uncharted") % n, 9, Color(0.85, 0.83, 0.78))
	y += 13
	var ch := int(r.get("chapter", 0))
	_text(Vector2(x, y), tr("Opens"), 9, Color(0.7, 0.68, 0.7))
	_text(Vector2(x + 60, y), (tr("with Chapter %d of the story") % ch) if ch > 0 else tr("later in the story"), 9, Color(0.85, 0.83, 0.78))
	y += 18
	_cv.draw_multiline_string(font, Vector2(x, y), tr("Nobody you could send has been past the fog. The Blank's work there waits until the story takes you in, and so does yours."),
		HORIZONTAL_ALIGNMENT_LEFT, w, Access.fs(9), -1, Color(0.62, 0.6, 0.62))
	var pr := _play_rect()
	_text_c(Vector2(pr.get_center().x, pr.position.y + 16), tr("No missions past the fog"), 8, Color(0.45, 0.44, 0.47))


func _draw_legend() -> void:
	var x := MAP_ORIGIN.x + 4
	var y := MAP_ORIGIN.y + MAP_VIEW.y - 8
	var keys := ["you", "free"]
	for fid in Empire.faction_ids():  # factions whose home is on the open map (Chapter 2 adds the Abbey, the Erasers)
		if Journal.faction_known(fid):
			keys.append(fid)
	for k in keys:
		var label: String = tr("Yours") if k == "you" else (tr("Unclaimed") if k == "free" else str(Empire.faction(k).get("short", k)))
		x = _legend_entry(x, y, k, label)


func _draw_panel() -> void:
	var p: Dictionary = territory.provinces[selected]
	var x := PANEL_X
	var w := size.x - PANEL_X - 6
	UiSkin.panel(_cv, Rect2(x - 6, 20, w + 10, size.y - 22), "ledger")
	if not Empire.province_open(p):
		_draw_region_panel(territory.region_of(p), x, w)
		return
	var y := 42.0
	_text(Vector2(x, y), p["name"], 15, Color("f3efe4"))
	y += 11
	var reg := territory.region_of(p)
	_text(Vector2(x, y), "%s  ·  %s" % [reg.get("name", ""), territory.biomes.get(p.get("biome", ""), {}).get("name", "")], 8, Color(0.62, 0.6, 0.62))
	y += 13
	var owner: String = p["owner"]
	_cv.draw_rect(Rect2(x, y - 7, 7, 7), owner_color(owner))
	if Access.map_symbols:
		_owner_mark(_cv, owner, Vector2(x + 3.5, y - 3.5), 2.2)
	_text(Vector2(x + 11, y), owner_name(owner), 9, Color(0.8, 0.78, 0.74))
	if owner in Empire.faction_ids():
		var tier := Empire.tier_of(owner)
		_text(Vector2(x + 11, y + 11), tr("Standing: %s %+d   Diplomacy%s") % [Empire.tier_name(tier), Empire.standing_of(owner), Prompts.tag("diplomacy")], 8,
			Color("9fd18b") if Empire.has_perk(owner) else (Color("ff9b8a") if tier == "hostile" else Color(0.7, 0.68, 0.7)))
		y += 10
	y += 18

	# Fray
	var fray := int(p["fray"])
	var state := tr("Safe") if fray < 25 else (tr("Fraying") if fray < 60 else (tr("Unravelling") if fray < 100 else tr("Erased")))
	_text(Vector2(x, y), tr("Fray"), 9, Color(0.7, 0.68, 0.7))
	var ftext := "%d / 100   %s" % [fray, state]
	_text(Vector2(x + 30, y), ftext, 9, Color("f3efe4") if fray < 60 else Color("ff9b8a"))
	if Access.map_symbols and owner != "erased":  # the same box the map shows by the name, so its look is learned here
		_fray_chip(Vector2(x + 36 + font.get_string_size(ftext, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x, y), fray)
	y += 5
	_cv.draw_rect(Rect2(x, y, w, 5), Color(0.15, 0.13, 0.17))
	_cv.draw_rect(Rect2(x, y, w * fray / 100.0, 5), Color(0.85, 0.84, 0.8).lerp(PAPER, fray / 100.0))
	y += 16
	if owner != "erased":
		var rate := Empire.fray_rate(p)
		var rcol := Color("ff8a7a") if rate > 0 else (Color("9fd18b") if rate < 0 else Color(0.7, 0.68, 0.7))
		var eta := ""
		if rate > 0:
			eta = tr("   erased in ~%d days") % ceili((100.0 - fray) / rate)
		_text(Vector2(x, y), tr("Per day: %s%d%s") % ["+" if rate > 0 else "", rate, eta], 9, rcol)
		y += 11
		for src in Empire.fray_sources(p):
			var v := int(src[1])
			_text(Vector2(x + 6, y), ("+%d" if v > 0 else "%d") % v, 8, Color("ff9b8a") if v > 0 else Color("9fd18b"))
			_text(Vector2(x + 24, y), src[0], 8, Color(0.7, 0.68, 0.7))
			y += 10
		if Empire.surge.get("id", "") == p["id"]:
			_text(Vector2(x, y + 1), tr("Surge gathering: +%d Fray when it lands") % Empire.surge_fray(), 8, Color(1, 0.55, 0.5))
			y += 11
		y += 6
	else:
		y += 2

	# Output
	var out: Dictionary = p.get("output", {})
	var parts := []
	for k in ["gilt", "supplies", "ink"]:
		if out.has(k):
			parts.append("+%d %s" % [out[k], Loc.t(RES_NAMES[k])])
	var out_label := tr("Lost output") if owner == "erased" else (tr("Output per day") if owner == "you" else tr("Would give"))
	_text(Vector2(x, y), out_label, 9, Color(0.7, 0.68, 0.7))
	y += 12
	_text(Vector2(x, y), "   ".join(parts) if not parts.is_empty() else Loc.t("nothing"), 9, Color("e8d9a8") if owner != "erased" else Color(0.55, 0.54, 0.56))
	y += 17

	# Governor and sites
	_text(Vector2(x, y), tr("Governor"), 9, Color(0.7, 0.68, 0.7))
	var gov := Empire.governor_of(p["id"])
	var gov_text := "-"
	var gov_col := Color(0.85, 0.83, 0.78)
	if owner == "you":
		if gov != "":
			gov_text = tr("%s (%s fit)") % [Empire.recruit(gov)["name"], Empire.governor_fit(gov, p["id"])]
		else:
			gov_text = tr("none posted!")
			gov_col = Color("ff9b8a")
	elif owner == "free":
		gov_text = tr("claim it to post one")
	_text(Vector2(x + 52, y), gov_text, 9, gov_col)
	_gov_button_y = y if _can_govern(selected) else -100.0
	if _can_govern(selected):
		y += 13
		var fav: String = p.get("favors", "charm")
		_text(Vector2(x, y), tr("Wants"), 9, Color(0.7, 0.68, 0.7))
		_text(Vector2(x + 52, y), tr("high %s") % Loc.t(Empire.STAT_NAMES[fav]), 9, Color(0.85, 0.83, 0.78))
		var gb := _governor_button_rect()
		gb.position.y += 13  # sits beside the "Wants" line, under the name
		_gov_button_y += 13
		_cv.draw_rect(gb, Color(0.22, 0.17, 0.08))
		_cv.draw_rect(gb, GOLD, false, 1.0)
		var label := (tr("Claim") if owner == "free" else (tr("Change") if gov != "" else tr("Post one"))) + "  G"
		_text_c(Vector2(gb.get_center().x, gb.position.y + 10), label, 8, GOLD)
	y += 13
	var sites: Array = p.get("sites", [])
	_text(Vector2(x, y), tr("Sites"), 9, Color(0.7, 0.68, 0.7))
	_text(Vector2(x + 52, y), ", ".join(sites) if not sites.is_empty() else tr("none left"), 9, Color(0.85, 0.83, 0.78))
	y += 13
	var nb := []
	var fogged := {}
	for b in territory.neighbors[selected]:
		var q: Dictionary = territory.provinces[b]
		if Empire.province_open(q):
			nb.append(q["name"])
		elif not fogged.has(q["region"]):
			fogged[q["region"]] = true
			nb.append(tr("the fog over %s") % territory.region_of(q).get("name", "?"))
	_text(Vector2(x, y), tr("Borders"), 9, Color(0.7, 0.68, 0.7))
	_cv.draw_multiline_string(font, Vector2(x + 52, y), ", ".join(nb), HORIZONTAL_ALIGNMENT_LEFT, w - 52, Access.fs(9), -1, Color(0.85, 0.83, 0.78))
	y += 13 * ceilf(font.get_string_size(", ".join(nb), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x / (w - 52)) + 8

	# Flavour
	_cv.draw_multiline_string(font, Vector2(x, y), p["blurb"], HORIZONTAL_ALIGNMENT_LEFT, w, Access.fs(9), -1, Color(0.62, 0.6, 0.62))

	# Mission button
	var m := _mission(selected)
	var r := _play_rect()
	if not m.is_empty():
		var more := Missions.list_for_province(p["id"]).size() - 1
		var blocked: bool = str(m.get("blocker", "")) != ""
		_cv.draw_rect(r, Color(0.22, 0.17, 0.08) if not blocked else Color(0.12, 0.11, 0.13))
		_cv.draw_rect(r, GOLD if not blocked else Color(0.45, 0.42, 0.4), false, 1.0)
		var label: String = m["name"] if m.has("type") else tr("Play: ") + m["name"]
		_text_c(Vector2(r.get_center().x, r.position.y + 12), label + (tr("  (+%d more)") % more if more > 0 else ""), 9, GOLD if not blocked else Color(0.7, 0.67, 0.62))
		var sub := (tr("Tap again") if Prompts.touch() else Prompts.key("ui_accept")) if not blocked else tr("Locked: ") + str(m["blocker"])
		_text_c(Vector2(r.get_center().x, r.position.y + 22), sub, 8, Color(0.75, 0.7, 0.55) if not blocked else Color(1, 0.6, 0.5))
	else:
		var note := tr("No missions here right now")
		_text_c(Vector2(r.get_center().x, r.position.y + 16), note, 8, Color(0.45, 0.44, 0.47))


# ---------------------------------------------------------------- map markings without colour (issue #192)

const MARK_INK := Color("15111b")
const UNRAVEL := 0.6  # Fray from which a province counts as Unravelling (and is hatched on the map)
## Each owner's shape on the map, the legend and the panel, so ownership never rests on colour alone.
## Yours keeps its flag (and the capital its tower). A faction without an entry takes the next spare shape.
const OWNER_MARKS := {"free": "ring", "erased": "cross", "concord": "square", "coven": "triangle", "guild": "diamond", "abbey": "hex", "erasers": "bar"}
const SPARE_MARKS := ["hex", "bar", "dot"]


func _owner_mark(ci: CanvasItem, owner: String, c: Vector2, r: float, col := MARK_INK) -> void:
	var shape: String = OWNER_MARKS.get(owner, "")
	if owner == "you":
		shape = "flag"
	elif shape == "":
		var ids: Array = Empire.faction_ids()
		shape = SPARE_MARKS[posmod(ids.find(owner), SPARE_MARKS.size())]
	match shape:
		"flag":
			ci.draw_line(c + Vector2(-r * 0.6, r), c + Vector2(-r * 0.6, -r), col, 1.0)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r), c + Vector2(r, -r * 0.4), c + Vector2(-r * 0.6, r * 0.2)]), col)
		"ring":
			ci.draw_arc(c, r * 0.8, 0, TAU, 12, col, 1.0)
		"cross":
			ci.draw_line(c + Vector2(-r, -r) * 0.7, c + Vector2(r, r) * 0.7, col, 1.0)
			ci.draw_line(c + Vector2(r, -r) * 0.7, c + Vector2(-r, r) * 0.7, col, 1.0)
		"square":
			ci.draw_rect(Rect2(c - Vector2(r, r) * 0.75, Vector2(r, r) * 1.5), col)
		"triangle":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)]), col)
		"diamond":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)
		"hex":
			var pts := PackedVector2Array()
			for i in 6:
				pts.append(c + Vector2.RIGHT.rotated(TAU * i / 6.0) * r)
			ci.draw_colored_polygon(pts, col)
		"bar":
			ci.draw_rect(Rect2(c - Vector2(r, r * 0.4), Vector2(r * 2.0, r * 0.8)), col)
		_:
			ci.draw_circle(c, r * 0.7, col)


## The Fray number in a little box after a province's name (left edge at at.x, baseline at.y). Safe land
## gets a plain box, Fraying a double top rule, Unravelling a hatched box, so the state reads without the
## red text too. Returns the box's right edge.
func _fray_chip(at: Vector2, fray: int) -> float:
	var s := str(fray)
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
	var h := Access.px(8.0)
	var r := Rect2(at.x, at.y - h + 1.0, tw + 4.0, h)
	_cv.draw_rect(r, Color(0.96, 0.93, 0.86, 0.9))
	if fray >= int(UNRAVEL * 100.0):
		for i in range(0, int(r.size.x + r.size.y), 3):
			var a := r.position + Vector2(minf(i, r.size.x), maxf(0.0, i - r.size.x))
			var b := r.position + Vector2(maxf(0.0, i - r.size.y), minf(i, r.size.y))
			_cv.draw_line(a, b, Color(MARK_INK, 0.3), 1.0)
	_cv.draw_rect(r, MARK_INK, false, 1.0)
	if fray >= 25 and fray < int(UNRAVEL * 100.0):
		_cv.draw_line(r.position + Vector2(0, 1.5), r.position + Vector2(r.size.x, 1.5), MARK_INK, 1.0)
	_cv.draw_string(font, Vector2(r.position.x + 2.0, at.y - 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), MARK_INK)
	return r.end.x


## One owner in the legend: its colour swatch (with its shape on it when map markings are on) and its
## name. Returns where the next entry starts.
func _legend_entry(x: float, y: float, owner: String, label: String) -> float:
	var marks := Access.map_symbols
	var sw := 8.0 if marks else 6.0
	_cv.draw_rect(Rect2(x, y - sw, sw, sw), owner_color(owner))
	_cv.draw_rect(Rect2(x, y - sw, sw, sw), BORDER_COLOR, false, 1.0)
	if marks:
		_owner_mark(_cv, owner, Vector2(x + sw / 2.0, y - sw / 2.0), 2.4)
	_text(Vector2(x + sw + 3, y), label, 8, Color(0.85, 0.83, 0.78), 3)
	return x + sw + 9 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(8)).x + 4


