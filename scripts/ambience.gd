class_name Ambience
extends Node2D
## Art pass mood for the field (docs/ART_ROADMAP.md 3.7): light that follows the empire clock, a lantern
## glow on the leader after dark, and drifting motes (pollen by day, fireflies at dusk and night).
## The clock is frozen during missions, so the hour a mission was launched is the hour it is played at.
## All code, no textures beyond one generated radial gradient.

## Light colour through the day (day_t 0..1, midnight at 0).
const KEYS := [
	[0.00, Color(0.42, 0.47, 0.68)],
	[0.20, Color(0.48, 0.52, 0.72)],
	[0.27, Color(0.92, 0.76, 0.72)],  # dawn
	[0.36, Color(0.94, 0.90, 0.86)],  # the target plaza's muted afternoon (docs/ART_STYLE.md)
	[0.62, Color(0.96, 0.92, 0.87)],
	[0.74, Color(1.00, 0.80, 0.66)],  # dusk
	[0.82, Color(0.60, 0.56, 0.74)],
	[1.00, Color(0.42, 0.47, 0.68)],
]

var party  # main.gd or hub.gd: leader, camera
var day_t := 0.5
var live := false  # follow the running clock (Hollowmark); missions keep the hour they were launched at
var modulate_node: CanvasModulate
var lantern: Array  # Art.add_lamp lights that follow the leader
var motes: Array = []  # [pos, vel, phase]
var t := 0.0
var clouds: ColorRect  # drifting cloud shadows, fade out after dusk
var mist: ColorRect  # low drifting mist, thicker at dawn, dusk and night
var vignette: ColorRect
var _shadow_alpha := -1.0
var mood := {"grade": Color.WHITE, "mist": 1.0, "motes": Color(1.0, 0.97, 0.85)}  # the map's @mood (scripts/area.gd)


static func light_at(dt: float) -> Color:
	dt = fposmod(dt, 1.0)
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if dt <= b[0]:
			var k := smoothstep(0.0, 1.0, (dt - a[0]) / maxf(b[0] - a[0], 0.001))
			return (a[1] as Color).lerp(b[1], k)
	return KEYS[0][1]


## The light right now, with the biome's grade on top.
func lit_now() -> Color:
	if mood.get("page", false):
		return Color.WHITE  # a map written as words (issue #186): plain page light, no hour, no weather
	var c := light_at(day_t) * (mood["grade"] as Color)
	c.a = 1.0
	return c


## 0 in full daylight, 1 at deep night.
static func darkness(dt: float) -> float:
	var c := light_at(dt)
	return clampf((1.0 - (c.r + c.g + c.b) / 3.0) / 0.45, 0.0, 1.0)


func _ready() -> void:
	z_index = 5  # motes float above the actors
	day_t = Empire.day_t
	if party != null and "area" in party and party.area != null and "mood" in party.area:
		mood = party.area.mood
	modulate_node = CanvasModulate.new()
	modulate_node.color = lit_now()
	get_parent().add_child.call_deferred(modulate_node)
	lantern = Art.add_lamp(self, Vector2.ZERO, Color(1.0, 0.82, 0.55), 205)
	var n := 26
	for i in n:
		motes.append([Vector2(randf_range(-340, 340), randf_range(-200, 200)), Vector2(randf_range(-6, 6), randf_range(-4, 2)), randf() * TAU])


func _noise(freq: float, seed_n: int) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.seed = seed_n
	fn.frequency = freq
	fn.fractal_octaves = 3
	nt.noise = fn
	return nt


func _fx_rect(shader: Shader, z: int, noise: NoiseTexture2D) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(1400, 900)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if noise != null:
		mat.set_shader_parameter("noise", noise)
	r.material = mat
	r.z_index = z
	add_child(r)
	return r


## Scene effects (docs/ART_STYLE.md "Sitting in the world"), all tuned live from Options > Visual effects.
## Each is a rect that follows the camera; Ambience sits at z 5, so these land over the actors and under the
## name tags (z 20). Clouds and vignette multiply; mist mixes in.
func _add_effects() -> void:
	clouds = _fx_rect(preload("res://shaders/cloud_shadows.gdshader"), -1, _noise(0.012, 3))
	mist = _fx_rect(preload("res://shaders/ground_mist.gdshader"), -1, _noise(0.02, 9))
	vignette = _fx_rect(preload("res://shaders/vignette.gdshader"), 10, null)
	if party != null and "area" in party and party.area != null:
		for c in party.area.get_children():  # the ground takes lamp light through the shadowed light only
			if c is CanvasItem and c != party.entities:
				c.light_mask = Art.LIGHT_GROUND


func _update_effects() -> void:
	var cam := Vector2.ZERO
	var view := Vector2(640, 360)
	if party != null and party.camera != null:
		cam = party.camera.get_screen_center_position()
		view = get_viewport_rect().size / party.camera.zoom
	for r in [clouds, mist]:
		r.global_position = cam - r.size / 2.0
	vignette.size = view + Vector2(4, 4)
	vignette.global_position = cam - vignette.size / 2.0
	var lit := lit_now()
	var undo := Vector3(1.0 / lit.r, 1.0 / lit.g, 1.0 / lit.b)
	var dark := 0.0 if mood.get("page", false) else darkness(day_t)
	var cm := clouds.material as ShaderMaterial
	cm.set_shader_parameter("strength", 0.22 * Settings.fxf("clouds") * (1.0 - dark))
	cm.set_shader_parameter("scale", lerpf(220.0, 900.0, Settings.fxf("cloud_size")))
	cm.set_shader_parameter("wind", Vector2(2.5, 1.0) * lerpf(0.0, 14.0, Settings.fxf("wind")))
	cm.set_shader_parameter("undo", undo)
	var page: bool = mood.get("page", false)
	clouds.visible = Settings.fx_value("clouds") > 0 and not page
	var mm := mist.material as ShaderMaterial
	# Mist hangs about all day but thickens towards dawn, dusk and night.
	var dt := fposmod(day_t, 1.0)
	var dusk := maxf(dark, maxf(1.0 - absf(dt - 0.27) / 0.07, 1.0 - absf(dt - 0.75) / 0.07))
	var biome_mist: float = mood["mist"]
	mm.set_shader_parameter("amount", Settings.fxf("mist") * lerpf(0.2 * biome_mist, 1.0, dusk) * minf(biome_mist, 1.6))
	mm.set_shader_parameter("wind", Vector2(3.0, 0.6) * lerpf(0.3, 1.0, Settings.fxf("wind")))
	mist.visible = Settings.fx_value("mist") > 0 and not page
	var vm := vignette.material as ShaderMaterial
	vm.set_shader_parameter("amount", Settings.fxf("vignette") * lerpf(0.55, 0.85, dark))
	vm.set_shader_parameter("undo", undo)
	vignette.visible = Settings.fx_value("vignette") > 0
	var sa := Art.SHADOW_COLOR.a * Settings.fxf("shadows")
	if absf(sa - _shadow_alpha) > 0.001:
		_shadow_alpha = sa
		for sh in get_tree().get_nodes_in_group("cast_shadow"):
			sh.modulate.a = sa
			sh.visible = sa > 0.0
	Art.set_lamp(lantern, 0.0 if page else 0.6 * dark)


func _process(delta: float) -> void:
	t += delta
	if clouds == null:
		_add_effects()
	if live and absf(Empire.day_t - day_t) > 0.0005:
		day_t = Empire.day_t
		modulate_node.color = lit_now()
	_update_effects()
	if party != null and party.leader != null and is_instance_valid(party.leader):
		for l in lantern:
			l.global_position = party.leader.global_position + Vector2(0, -8)
	for m in motes:
		m[0] += m[1] * delta + Vector2(sin(t * 0.7 + m[2]) * 3.0, cos(t * 0.9 + m[2]) * 2.0) * delta
	queue_redraw()


func _draw() -> void:
	if party == null or party.camera == null:
		return
	var cam: Vector2 = party.camera.get_screen_center_position()
	var dark := 0.0 if mood.get("page", false) else darkness(day_t)
	var lit := lit_now()
	var undo := Color(1.0 / lit.r, 1.0 / lit.g, 1.0 / lit.b)  # motes give off their own light: cancel the dusk tint
	for m in motes:
		# Motes live in a box around the camera and wrap, so the screen always has a few.
		var p: Vector2 = m[0]
		var local := Vector2(fposmod(p.x - cam.x + 340.0, 680.0) - 340.0, fposmod(p.y - cam.y + 200.0, 400.0) - 200.0)
		var wp := cam + local
		if dark > 0.35:  # fireflies
			var a := 0.35 + 0.65 * maxf(sin(t * 2.2 + m[2] * 3.0), 0.0)
			draw_circle(wp, 1.8, Color(1.0, 0.9, 0.45, 0.18 * a) * undo)
			draw_rect(Rect2(wp, Vector2(1, 1)), Color(1.0, 0.95, 0.6, a) * undo)
		else:  # pollen and seed fluff in the light
			var mc: Color = mood["motes"]
			draw_rect(Rect2(wp, Vector2(1, 1)), Color(mc.r, mc.g, mc.b, 0.45 + 0.25 * sin(t + m[2])))
