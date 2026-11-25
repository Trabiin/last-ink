class_name Blot
extends Enemy
## The Blot: the knot of white that holds an erased province down. It does not move; it pulses
## and spits Nibblers (the Reclaim objective does the spitting). Break it and the Blank lets go.
## It is an Enemy so heroes and allies hit it like anything else.

var total_hp := 220


func _ready() -> void:
	super._ready()
	max_hp = total_hp
	hp = max_hp
	xp = 20
	radius = 14.0
	for c in get_children():
		if c is CollisionShape2D:
			(c.shape as CircleShape2D).radius = 12.0
	sprite.visible = false


func _physics_process(delta: float) -> void:
	anim_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	knockback = Vector2.ZERO


func _on_hit() -> void:
	pass


func _on_death() -> void:
	for i in 3:
		Fx.burst(get_parent(), global_position + Vector2(randf_range(-10, 10), randf_range(-24, -4)), [Color.WHITE, Color("d9d9d9"), Color.BLACK], 22, 130.0)
	remove_from_group("enemies")
	collision_layer = 0
	dying_t = 0.0


func _process(delta: float) -> void:
	if dying_t >= 0.0:
		dying_t += delta
		modulate.a = maxf(1.0 - dying_t * 1.5, 0.0)
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	draw_shadow(16.0)
	var pulse := 1.0 + sin(anim_t * 3.0) * 0.08
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Outer ragged paper, then an ink core that breathes.
	for layer in 3:
		var r: float = [18.0, 13.0, 7.0][layer] * pulse
		var col: Color = [Color("f3f1ea"), Color("d8d5cc"), Color("15101a")][layer]
		if flash_t > 0.0 and layer < 2:
			col = Color("ff9b8a")
		var pts := PackedVector2Array()
		for i in 18:
			var a := TAU * i / 18.0
			var wob := 1.0 + 0.18 * sin(a * 3.0 + anim_t * (2.0 + layer)) + 0.1 * rng.randf()
			pts.append(Vector2(cos(a), sin(a) * 0.8) * r * wob + Vector2(0, -16))
		draw_colored_polygon(pts, col)


func _draw_overlay() -> void:
	if dying_t >= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = static_seed + int(anim_t * (2.0 if Access.reduce_flashing else 10.0))  # reduced flashing: slow drift
	for i in 10:
		var p := Vector2(rng.randf_range(-22, 22), rng.randf_range(-40, 2))
		overlay.draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.9) if i % 2 else Color(0, 0, 0, 0.8))
	UiSkin.field_bar(overlay, -43, 36, float(hp) / max_hp, "enemy", Access.danger_patterns and hp * 4 <= max_hp)
