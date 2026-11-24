class_name TallyShadow
extends Node2D
## Tally's Turn (Nan Cripps & Tally, abilities.gd kind "shadow", Chapter 3 #29). Tally is Nan's shadow, and the honest
## half of the act; for a few seconds he peels off the ground and fights on his own. He darts at the nearest enemy
## within LEASH of Nan and punches it every few tenths of a second (credited to Nan, so her tree's riders count),
## then slides back under her feet. A shadow goes where it likes: he walks through walls, and nothing can hit him.
## He wears Nan's own sprite, inked flat.

const LEASH := 150.0
const SPEED := 120.0
const INK := Color(0.07, 0.05, 0.1, 0.78)

var owner_hero: Hero = null
var ability := {}
var life := 6.0
var punch_t := 0.3
var target: Enemy = null
var facing := Vector2.DOWN
var anim_t := 0.0
var punch_show := 0.0
var fading := 0.0
var sprite: Sprite2D
var art: SpriteSet


func _ready() -> void:
	add_to_group("shadows")
	sprite = Sprite2D.new()
	add_child(sprite)
	if owner_hero != null:
		art = SpriteSet.of(owner_hero.art_id())
	sprite.visible = art != null
	sprite.modulate = INK


func fade() -> void:
	if fading <= 0.0:
		fading = 0.001


func _physics_process(delta: float) -> void:
	anim_t += delta
	punch_show = maxf(punch_show - delta, 0.0)
	if fading > 0.0:
		fading += delta
		modulate.a = clampf(1.0 - fading / 0.35, 0.0, 1.0)
		if fading > 0.35:
			queue_free()
		return
	life -= delta
	punch_t -= delta
	if life <= 0.0 or owner_hero == null or not is_instance_valid(owner_hero) or owner_hero.dead:
		_back_home()
		return
	if target == null or not is_instance_valid(target) or target.dead \
			or target.global_position.distance_to(owner_hero.global_position) > LEASH:
		target = _pick()
	var goal := owner_hero.global_position + owner_hero.facing.orthogonal() * 12.0
	if target != null:
		goal = target.global_position - (target.global_position - global_position).normalized() * (target.radius + 6.0)
	var to := goal - global_position
	if to.length() > 2.0:
		facing = to.normalized()
		global_position += facing * minf(SPEED * delta, to.length())
	if target != null and global_position.distance_to(target.global_position) <= target.radius + 12.0 and punch_t <= 0.0:
		punch_t = float(ability.get("every", 0.7))
		_punch()
	queue_redraw()


func _pick() -> Enemy:
	var best: Enemy = null
	var best_d := LEASH
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var d := enemy.global_position.distance_to(owner_hero.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _punch() -> void:
	facing = (target.global_position - global_position).normalized()
	punch_show = 0.18
	var a := ability
	if TreePerks.strike(owner_hero, target, int(a.get("damage", 6)), global_position, float(a.get("knock", 90)), a):
		if float(a.get("weaken_hits", 0)) > 0.0 and not target.dead:  # skill tree rider (issue #25)
			target.weaken(float(a["weaken_hits"]), 0.75, 0.85)
	Fx.burst(get_parent(), target.global_position + Vector2(0, -10), [Color("1a1424"), Color("8a7aa0")], 4, 30.0)


## Slides back under Nan's feet and is gone.
func _back_home() -> void:
	if owner_hero != null and is_instance_valid(owner_hero):
		Fx.burst(get_parent(), owner_hero.global_position + Vector2(0, -6), [Color("1a1424"), Color("4a3e5a")], 8, 30.0)
	fade()


func _process(_delta: float) -> void:
	if art == null:
		queue_redraw()
		return
	var row := Hero.dir_row(facing)
	if punch_show > 0.0 and art.has("attack"):
		var n := art.frames_of("attack")
		art.apply_frame(sprite, "attack", row, clampi(int((1.0 - punch_show / 0.18) * n), 0, n - 1))
	else:
		art.apply(sprite, "walk" if art.has("walk") else "idle", row, anim_t)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.35 * modulate.a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if art == null:  # no sprite set yet: a flat ink figure
		draw_rect(Rect2(-4, -18, 8, 16), INK)
		draw_circle(Vector2(0, -21), 3.5, INK)
