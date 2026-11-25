extends "res://tests/test_case.gd"
## Pixel-art HUD, bars and effects (docs/ART_STYLE.md "UI bars and rows" and "Effects"): the bar kit's ramps
## and notches, the FX palette kept in step with tools/style_palette.hex, the pixel FX layer in a real
## mission (effects and the heroes' effect overlays on its layer, the main view skipping it, everything put
## back when the mission ends), no leader arrow except the brief marker after a swap (or always, by option),
## and the colour-blind stripes on low bars.

const MAIN := "res://scenes/main.tscn"

var _cfg_backup = null


func before_each() -> void:
	_cfg_backup = FileAccess.get_file_as_bytes(Settings.PATH) if FileAccess.file_exists(Settings.PATH) else null
	Access._loaded = true
	Access.reset()
	autoload("Saves").pending = {}
	autoload("Empire").reset()


func after_each() -> void:
	tree.paused = false
	Access.reset()
	if _cfg_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))
	else:
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_backup)
		f.close()
	Access._loaded = false
	Access.load_settings()
	Access.apply()


func _launch(id: String) -> Node:
	Missions.launch(Missions.find(id))
	var main := await wait_scene(MAIN)
	if main == null:
		return null
	await frames(5)
	if main.dialogue_box.visible:
		main.dialogue_box._close()  # the mission's opening talk
	await frames(3)
	return main


# ---------------------------------------------------------------- the kit

func test_palette_matches_the_style_file() -> void:
	var want := []
	var f := FileAccess.open("res://tools/style_palette.hex", FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("#"):
			want.append(line.substr(1, 6).to_lower())
	check_eq(FxLayer.STYLE, want, "FxLayer.STYLE is tools/style_palette.hex, in order")
	var pal := FxLayer.palette_colors()
	check_eq(pal.size(), FxLayer.STYLE.size() + FxLayer.EXTRA.size(), "FX palette = style + accent tints")
	check(not Color("f3eee2") in pal, "paper white stays the Blank's alone")


func test_ramps_run_dark_to_light() -> void:
	for k in UiSkin.RAMP:
		var r: Array = UiSkin.RAMP[k]
		check_eq(r.size(), 4, "%s has four steps" % k)
		for i in 3:
			check((r[i] as Color).get_luminance() < (r[i + 1] as Color).get_luminance(), "%s: step %d darker than %d" % [k, i, i + 1])
	var built := UiSkin.ramp(Color("ffd166"))  # a bright data colour, as techs and Ink colours give
	for i in 3:
		check(built[i].get_luminance() < built[i + 1].get_luminance(), "a built ramp runs dark to light")
	check(built[1].s <= 0.63, "and is muted (saturation %.2f)" % built[1].s)
	check(built[1].v < Color("ffd166").v, "and darker than the raw colour")


func test_hp_ramp_and_notches() -> void:
	check_eq(UiSkin.hp_ramp(1.0), UiSkin.RAMP["hp"], "healthy: moss")
	check_eq(UiSkin.hp_ramp(0.4), UiSkin.RAMP["hp_mid"], "under half: brass")
	check_eq(UiSkin.hp_ramp(0.2), UiSkin.RAMP["hp_low"], "under a quarter: crimson")
	check_eq(UiSkin.notch_every(102, 52), 102.0 * 10.0 / 52.0, "one notch per 10 HP")
	check_eq(UiSkin.notch_every(102, 8), 0.0, "no notches when there is less than one")
	check_eq(UiSkin.notch_every(20, 300), 0.0, "no notches closer than 4 px")


## Every bar shape draws without errors in every option combination, including empty and odd sizes.
func test_bars_draw() -> void:
	var c := Control.new()
	c.size = Vector2(200, 100)
	tree.root.add_child(c)
	c.draw.connect(func():
		for f in [0.0, 0.004, 0.5, 1.0, 1.4]:
			UiSkin.bar(c, Rect2(2.3, 3.7, 100.4, 4.0), f, "hp", {"notch": 9.8, "ghost": 0.8, "hatch": true})
			UiSkin.bar(c, Rect2(2, 12, 60, 1), f, "xp", {"frame": false, "notches": [0.25, 0.5, 0.75]})
			UiSkin.bar(c, Rect2(2, 20, 0.4, 3), f, Color("c9a0e8"), {"dim": true})
			UiSkin.field_bar(c, 30.0, 12.0, f, "enemy", true)
		UiSkin.row(c, Rect2(2, 40, 80, 20), true)
		UiSkin.row(c, Rect2(2, 62, 80, 20), true, false)
		UiSkin.row(c, Rect2(2, 84, 2, 2), false)
		UiSkin.tab(c, Rect2(90, 40, 60, 26), "rust")
		UiSkin.tab(c, Rect2(90, 70, 60, 3), "slate", true)
		UiSkin.swatch(c, Rect2(160, 40, 6, 6), Color("e89a8a"), true)
		UiSkin.scrollbar(c, Rect2(190, 0, 3, 100), 30.0, 20.0)
		UiSkin.scrollbar(c, Rect2(190, 0, 3, 100), 120.0, 20.0)
		UiSkin.panel(c, Rect2(-7, -7, 900, 600), "ledger")  # bigger than the grain: clipped, never stretched
		UiSkin.panel(c, Rect2(4, 4, 3, 3), "ledger", Color(1, 1, 1, 0.5))
		UiSkin.grain(c, Rect2(250.6, 130.2, 40, 1)))
	c.queue_redraw()
	await frames(2)
	c.queue_free()
	check(true, "drawn")


## Text and rows go on the panel's face, inside the frame and its inner shadow (Ojon, 2026-11-25).
func test_panel_inner_clears_the_frame() -> void:
	var img: Image = UiSkin.TEX["ledger"].get_image()
	var r := Rect2(100, 100, 200, 120)
	var inn := UiSkin.inner(r)
	# In the 9-slice's own pixels: the face starts 9 px into the texture, drawn 2 px outside r.
	var face := img.get_pixel(31, 31)
	for d in range(9, 14):
		check_eq(img.get_pixel(d, 31), face, "the panel face starts right after the frame (%d px in)" % d)
	check(inn.position.x >= r.position.x - 2.0 + 9.0, "inner() starts on the face")
	check(inn.end.x <= r.end.x + 2.0 - 9.0, "and ends before the far frame")


## Ledger pages (Ojon, 2026-11-25): text goes on the ruled lines and between the margins, at every text
## size, and a page that runs out of lines stops instead of writing past its bottom.
func test_ledger_page_keeps_text_on_its_lines() -> void:
	var c := Control.new()
	c.size = Vector2(300, 200)
	tree.root.add_child(c)
	var font := ThemeDB.fallback_font
	for ts in Access.TEXT_SIZES.size():
		Access.text_size = ts
		var got := {}
		c.draw.connect(func():
			var pg := LedgerPage.begin(c, Rect2(10, 10, 220, 150), font)
			got["pg"] = pg
			got["first"] = pg.first
			pg.heading("A heading")
			pg.line("one line", 8, LedgerPage.INK, "12")
			pg.para("word ".repeat(400))
			got["left"] = pg.left(), CONNECT_ONE_SHOT)
		c.queue_redraw()
		await frames(2)
		var pg: LedgerPage = got.get("pg")
		if not check(pg != null, "the page drew"):
			continue
		check(pg.x0 > pg.box.position.x + 20.0, "text starts past the red margin (size %d)" % ts)
		check(pg.x1 < pg.box.end.x - 6.0, "and ends before the right edge")
		check_eq(pg.rule_y(3) - pg.rule_y(2), pg.lh, "the lines are evenly ruled")
		check(pg.lh >= font.get_height(Access.fs(8)) + 2.0, "with room for the text size (size %d)" % ts)
		check(pg.rule_y(pg.lines - 1) <= pg.box.end.y - 6.0, "the last line is on the page")
		check_eq(got["left"], 0, "a long text fills the page and stops")
		var img: Image = LedgerPage.paper(Vector2i(pg.box.size), pg.lh, pg.first - pg.box.position.y).get_image()
		check(img.get_pixel(int(pg.box.size.x / 2), int(pg.box.size.y / 2)).a > 0.9, "the paper is solid in the middle")
	Access.text_size = 0
	c.queue_free()


## Fields, the text log the layout tests read, the light paper and ruled dialogue text (pass of 2026-11-25).
func test_ledger_fields_and_ruled_dialogue() -> void:
	var c := Control.new()
	c.size = Vector2(300, 200)
	tree.root.add_child(c)
	var font := ThemeDB.fallback_font
	var got := {}
	c.draw.connect(func():
		var pg := LedgerPage.begin(c, Rect2(10, 10, 220, 150), font, 9)
		pg.log = []
		pg.heading("Report")
		got["n"] = pg.field("Found", "word ".repeat(12), 60.0, 9)
		got["empty"] = pg.field("Time", "", 60.0, 9)
		got["pg"] = pg, CONNECT_ONE_SHOT)
	c.queue_redraw()
	await frames(2)
	var pg: LedgerPage = got.get("pg")
	if not check(pg != null, "the page drew"):
		c.queue_free()
		return
	check(int(got["n"]) > 1, "a long value wraps onto more ruled lines")
	check_eq(got["empty"], 1, "an empty value still takes its line")
	check_eq(pg.line_i, 1 + int(got["n"]) + 1, "each line written moves down one rule")
	for d in pg.log:
		var r: Rect2 = d[0]
		check(pg.box.encloses(r), "\"%s\" stays on the page" % d[2])
		check(r.position.x >= pg.x0 - 0.5 and r.end.x <= pg.x1 + 0.5, "\"%s\" stays between the margins" % d[2])
	var lh := pg.lh
	var a := Dialogue.line_count(font, "one two three four five six seven eight nine ten", 60.0, Access.fs(10))
	check(a > 1, "draw_text's wrap is counted (%d lines)" % a)
	var plain := LedgerPage.paper(Vector2i(220, 150), lh, 20.0).get_image()
	var light := LedgerPage.paper(Vector2i(220, 150), lh, 20.0, true).get_image()
	check(plain.get_data() != light.get_data(), "the light page is its own paper")
	c.queue_free()


func test_leader_marker_option_persists() -> void:
	check_eq(Access.leader_marker, 0, "default: only after a swap")
	Access.leader_marker = 1
	Access.save()
	Access._loaded = false
	Access.leader_marker = 0
	Access.load_settings()
	check_eq(Access.leader_marker, 1, "Always is kept")
	Access.reset()
	check_eq(Access.leader_marker, 0, "reset puts it back")


# ---------------------------------------------------------------- in a mission

func test_fx_layer_in_a_mission() -> void:
	var main := await _launch("meadow_patrol")
	if main == null:
		return
	var layer: FxLayer = null
	for c in main.get_children():
		if c is FxLayer:
			layer = c
	if not check(layer != null, "the mission has a pixel FX layer"):
		return
	check(FxLayer.active == layer, "and it is the active one")
	var vp := main.get_viewport()
	check(vp.canvas_cull_mask & FxLayer.BIT == 0, "the main view skips the FX layer")
	check(vp.canvas_cull_mask & FxLayer.GROUND_BIT == 0, "and the ground FX layer")
	check(layer.ground_view.canvas_cull_mask == FxLayer.GROUND_BIT, "the ground view draws only its layer")
	check(layer.ground_sprite.get_parent() == main and layer.ground_sprite.get_index() < main.entities.get_index(), "the ground picture sits in the world under the actors")
	check(layer.view.canvas_cull_mask == FxLayer.BIT, "the FX view draws only it")
	check(layer.view.world_2d == vp.world_2d, "and shares the world")
	# Effects join it; damage numbers stay crisp on the world.
	Fx.burst(main.entities, main.leader.global_position, [Color.WHITE], 6, 40.0)
	Fx.damage_number(main.entities, main.leader.global_position, "7", Color.WHITE)
	var tfx := TechFx.spawn(main.entities, "slash", main.leader.global_position, Vector2.RIGHT, 20.0, 0.6, Color("e8c66a"))
	await frames(1)
	var burst: Fx = null
	var number: Fx = null
	for n in main.entities.get_children():
		if n is Fx:
			if (n as Fx).kind == Fx.Kind.BURST:
				burst = n
			elif (n as Fx).kind == Fx.Kind.NUMBER:
				number = n
	check(burst != null and burst.visibility_layer == FxLayer.BIT, "a burst is on the FX layer only")
	check(number != null and number.visibility_layer & FxLayer.BIT == 0, "a damage number is not")
	check(tfx.visibility_layer == FxLayer.BIT, "a tech blast is on the FX layer")
	check(main.entities.visibility_layer & FxLayer.BIT != 0 and main.entities.visibility_layer & 1 != 0, "the entities node is on both")
	for h in main.heroes:
		var hero: Hero = h
		check(hero.fx_overlay.visibility_layer == FxLayer.BIT, "%s's effect overlay is on the FX layer" % hero.hero_id)
		check(hero.overlay.visibility_layer & FxLayer.BIT == 0, "%s's status marks are not" % hero.hero_id)
		check(hero.ground.visibility_layer == FxLayer.GROUND_BIT, "%s's shadow is on the ground FX layer" % hero.hero_id)
	# The FX view follows the camera on whole world pixels and covers the screen.
	await frames(2)
	var zoom: float = main.camera.zoom.x
	var view := vp.get_visible_rect().size / zoom
	check(layer.sprite.position == layer.sprite.position.floor(), "the FX picture sits on whole pixels")
	check(Vector2(layer.view.size) >= view, "the FX picture covers the view (%s for %s)" % [layer.view.size, view])
	# Effects animate on held frames.
	var b2 := Fx.new()
	b2.kind = Fx.Kind.RING
	b2.max_life = 1.0
	main.entities.add_child(b2)
	await frames(1)
	check(b2.visibility_layer == FxLayer.GROUND_BIT, "a ring lies on the ground FX layer")
	var first := b2.shown
	b2._process(Fx.STEP * 0.4)
	check_eq(b2.shown, first, "a ring holds its frame for less than a step")
	b2._process(Fx.STEP)
	check(b2.shown > first, "and moves on after a step")
	# Leaving the mission puts the main view back.
	var gs: Sprite2D = layer.ground_sprite
	layer.queue_free()
	await frames(1)
	check(vp.canvas_cull_mask & FxLayer.BIT != 0, "without the layer the main view draws effects again")
	check(vp.canvas_cull_mask & FxLayer.GROUND_BIT != 0, "and ground effects")
	check(not is_instance_valid(gs) or gs.is_queued_for_deletion(), "the ground picture goes with it")


func test_no_leader_arrow_but_a_swap_marker() -> void:
	var main := await _launch("meadow_patrol")
	if main == null or main.heroes.size() < 2:
		return
	var first: Hero = main.heroes[0]
	var second: Hero = main.heroes[1]
	check_eq(first.leader_cue_t, 0.0, "no marker over the hero you start with")
	main._set_leader(second)
	check(second.leader_cue_t > 0.0, "a swap shows the marker over the new hero")
	check_eq(first.leader_cue_t, 0.0, "and not over the old one")
	main._set_leader(second)
	check(second.leader_cue_t <= Hero.LEADER_CUE, "picking the same hero again adds nothing")
	await tree.create_timer(Hero.LEADER_CUE + 0.3).timeout
	check_eq(second.leader_cue_t, 0.0, "the marker fades out by itself")
	Access.leader_marker = 1
	second.fx_overlay.queue_redraw()
	await frames(2)
	check(second.controlled, "Always: still drawn over the controlled hero (no errors)")
