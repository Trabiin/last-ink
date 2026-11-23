extends "res://tests/test_case.gd"
## The territory map's regions (issue #53): what the fog locks, what opening a region does, region
## pressure, the economy past nine provinces, and the Command Table's camera.

const COMMAND := "res://scenes/command.tscn"
## Act 1's borders from before the map grew. The bigger map must keep them, or Act 1 plays differently.
const ACT1_BORDERS := {
	"hollowmark": ["gallows", "gutterwoods", "meadow", "oldmill", "tithe"],
	"meadow": ["gutterwoods", "hollowmark", "lampwick", "oldmill", "saltreed", "whitewater"],
	"gutterwoods": ["gallows", "hollowmark", "meadow", "saltreed"],
	"oldmill": ["hollowmark", "lampwick", "meadow", "tithe"],
	"lampwick": ["meadow", "oldmill", "whitewater"],
	"saltreed": ["gutterwoods", "meadow", "whitewater"],
	"gallows": ["gutterwoods", "hollowmark", "tithe"],
	"tithe": ["gallows", "hollowmark", "oldmill"],
	"whitewater": ["lampwick", "meadow", "saltreed"],
}

var Empire: Node
var Saves: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	Empire.reset()


func _p(id: String) -> Dictionary:
	return Empire.territory().find(id)


func test_map_has_about_24_provinces_in_five_regions() -> void:
	var t: Territory = Empire.territory()
	check_eq(t.provinces.size(), 24, "provinces")
	check_eq(t.regions.size(), 5, "regions")
	for p in t.provinces:
		check(int(p["cells"]) > 300, "%s has room on the map (%d cells)" % [p["id"], int(p["cells"])])
		var c: Vector2 = p["center"] * Vector2(Empire.MAP_CELLS)
		check_eq(t.cell(int(c.x), int(c.y)), p["index"], "%s's label sits inside it" % p["id"])
	check_eq(Empire.regions_open, ["marches"], "a new campaign opens the Brack Marches only")


func test_act1_borders_are_unchanged() -> void:
	var t: Territory = Empire.territory()
	for id in ACT1_BORDERS:
		var nb := []
		for n in t.neighbors[_p(id)["index"]]:
			if t.provinces[n]["region"] == "marches":
				nb.append(t.provinces[n]["id"])
		nb.sort()
		check_eq(nb, ACT1_BORDERS[id], "%s borders" % id)
	var edge := t.provinces.filter(func(p): return p["region"] == "marches" and p["at_edge"]).map(func(p): return p["id"])
	edge.sort()
	check_eq(edge, ["saltreed", "whitewater"], "Act 1 provinces touching the Blank's wall")


func test_locked_regions_are_frozen_and_offer_nothing() -> void:
	var before := {}
	for p in Empire.territory().provinces:
		before[p["id"]] = int(p["fray"])
	Empire.surge = {"id": "halfwave", "day": Empire.day + 2}
	check(MissionTypes.for_province("halfwave").is_empty(), "no Defense past the fog")
	Empire.surge = {}
	for i in 6:
		Empire.day += 1
		Empire._advance_blank()
	for p in Empire.territory().provinces:
		if not Empire.province_open(p):
			check_eq(int(p["fray"]), before[p["id"]], "%s Fray frozen under the fog" % p["id"])
			check(Missions.list_for_province(p["id"]).is_empty(), "%s offers no missions" % p["id"])
			check(Empire.fray_sources(p).is_empty(), "%s lists no Fray sources" % p["id"])
	check(_p("saltreed")["fray"] != before["saltreed"], "the open map still frays")
	check(Empire.claim_blocker("candlemere").begins_with("Beyond the fog"), "no claims past the fog")
	if not Empire.surge.is_empty():
		check(Empire.province_open(_p(Empire.surge["id"])), "surges only gather on the open map")


func test_opening_a_region() -> void:
	var opened := []
	Empire.region_opened.connect(func(id): opened.append(id))
	check(Empire.open_region("abbey"), "opens")
	check(not Empire.open_region("abbey"), "only once")
	check(not Empire.open_region("nowhere"), "unknown regions are ignored")
	check_eq(opened, ["abbey"], "region_opened fired once")
	check(Empire.province_open(_p("candlemere")), "Candleford is on the map")
	check_eq(Empire.claim_blocker("candlemere"), "Too far. Claim the land in between first", "claims need a border")
	_p("oldmill")["owner"] = "you"
	Empire.res["gilt"] = 500
	Empire.res["supplies"] = 100
	check_eq(Empire.claim_blocker("candlemere"), "", "claimable from Old Mill Crossing")
	check(Empire.claim_blocker("abbey") != "", "the Abbey's own land cannot simply be claimed (issue #28: it is the Abbey's home)")
	var f0 := int(_p("ossuary")["fray"])
	Empire.day += 1
	Empire._advance_blank()
	check(int(_p("ossuary")["fray"]) != f0 or Empire.fray_rate(_p("ossuary")) == 0, "the Abbey frays once open")
	var front := BlankPlans.pick_target("frontier_frayest")
	check_eq(_p(front).get("region", ""), "abbey", "Verity's frontier is the newest region")
	for i in Empire.territory().region("abbey")["provinces"]:
		check(int(Empire.territory().provinces[i]["fray"]) <= int(_p(front)["fray"]), "and its frayest province")
	var d: Dictionary = Empire.to_dict()
	Empire.reset()
	check(not Empire.region_open("abbey"), "reset closes it")
	Empire.from_dict(d)
	check(Empire.region_open("abbey"), "saved and loaded")


func test_regions_open_by_story_conditions() -> void:
	var r: Dictionary = Empire.territory().region("spire")
	r["opens_when"] = {"day": 40}
	Empire.check_regions()
	check(not Empire.region_open("spire"), "not yet")
	Empire.day = 40
	Empire.check_regions()
	check(Empire.region_open("spire"), "opens when its conditions hold")
	r.erase("opens_when")


func test_region_pressure_is_listed() -> void:
	Empire.open_region("coast", true)
	var labels: Array = Empire.fray_sources(_p("saltgrave")).map(func(s): return s[0])
	check(labels.has("The sea forgets itself"), "the coast's pressure shows in the panel")
	labels = Empire.fray_sources(_p("hollowmark")).map(func(s): return s[0])
	check(not labels.has("The sea forgets itself"), "only in its own region")


func test_garrisons_past_nine_provinces() -> void:
	var held := ["meadow", "oldmill", "lampwick", "saltreed", "gallows", "tithe", "gutterwoods", "whitewater"]
	for id in held:
		_p(id)["owner"] = "you"
	check(not Empire.ledger().any(func(l): return str(l["label"]).begins_with("Garrisons")), "all nine Act 1 provinces cost nothing extra")
	for r in ["abbey", "spire"]:
		Empire.open_region(r, true)
	_p("candlemere")["owner"] = "you"
	_p("tollmarch")["owner"] = "you"
	var line := {}
	for l in Empire.ledger():
		if str(l["label"]).begins_with("Garrisons"):
			line = l
	check_eq(int(line.get("gilt", 0)), -2, "two past nine: 2 Gilt")
	check_eq(int(line.get("supplies", 0)), -2, "and 2 Supplies a day")


func test_mission_maps_come_from_the_biome_pool() -> void:
	var woods := ["res://maps/gutterwoods.txt", "res://maps/gutterwoods_b.txt", "res://maps/gutterwoods_c.txt"]
	check(MissionTypes.map_for("gutterwoods") in woods, "woods: %s" % MissionTypes.map_for("gutterwoods"))
	var meadow := ["res://maps/frayed_meadow.txt", "res://maps/meadow_b.txt", "res://maps/meadow_c.txt"]
	check(MissionTypes.map_for("whitewater") in meadow, "meadow: %s" % MissionTypes.map_for("whitewater"))
	check_eq(MissionTypes.map_for("lighthouse"), MissionTypes.MAP, "an empty pool falls back to the meadow")
	check(MissionTypes.map_for("abbey") in ["res://maps/abbey.txt", "res://maps/abbey_b.txt", "res://maps/abbey_c.txt"], "the Abbey has its own layouts (issue #28)")


func test_command_table_camera_and_fog() -> void:
	var cmd := await goto(COMMAND, 10)
	if cmd == null:
		return
	check(cmd.fog_tex != null, "fog baked")
	var hm: Dictionary = _p("hollowmark")
	check_eq(cmd._province_at(cmd._province_screen_pos(hm) + Vector2(0, 4)), hm["index"], "clicking Hollowmark finds it")
	cmd._toggle_fit()
	cmd._process_camera(5.0)  # let the camera arrive (headless frames are too short to rely on)
	check(absf(cmd.zoom - cmd.zoom_min()) < 0.01, "zoomed out to the whole map")
	check(cmd._map_rect().encloses(cmd._world_rect().grow(-1.0)) or cmd._world_rect().encloses(cmd._map_rect()), "the whole world fits")
	cmd.zoom_by(10.0)
	cmd._process_camera(5.0)
	check(absf(cmd.zoom - cmd.ZOOM_MAX) < 0.01, "zoom stops at the maximum")
	var before: Vector2 = cmd.cam
	cmd.selected = _p("lighthouse")["index"]
	cmd._follow(cmd.selected, true)
	cmd._process_camera(5.0)
	check(cmd.cam.distance_to(before) > 10.0, "the camera follows the selection")
	Empire.open_region("coast")
	await frames(2)
	cmd._process_camera(5.0)
	check(cmd.zoom < cmd.ZOOM_MAX, "opening a region flies the camera out to it")


## Re-baking the map (after a screen closes, at dawn) updates its textures in place. A card that pauses
## the game right after (a locked screen's "from day 4") stops the map being redrawn, and new textures
## left it drawing freed ones: the whole map went white.
func test_rebake_keeps_the_same_map_textures() -> void:
	var cmd := await goto(COMMAND, 10)
	if not check(cmd != null and cmd.scene_file_path == COMMAND, "command table running"):
		return
	var map_rid: RID = cmd.map_tex.get_rid()
	var fog_rid: RID = cmd.fog_tex.get_rid()
	_p("frayed_meadow")["fray"] = 90
	cmd._bake()
	check_eq(cmd.map_tex.get_rid(), map_rid, "the map texture is updated in place")
	check_eq(cmd.fog_tex.get_rid(), fog_rid, "the fog texture is updated in place")
