class_name Chorus
extends Hero
## Showstopper (Saffron Kiss, abilities.gd kind "conjure", Chapter 3 #29): a chorus girl she sings into being. Her
## voice makes things exist for a few seconds, and this one is a gilded copy of the singer, mid high-kick.
## It stands where it was sung (it never walks or swings), pulls every enemy within the ability's radius onto
## itself, and enemies hit it like a hero (it is in the "heroes" group, with no party, so heals and auras skip it).
## When its time runs out or it is knocked down it bows out: a burst of damage around it (credited to the singer),
## and optionally a short Torch Song for the party nearby. One per singer.
## It never frees itself straight away: it goes dead and hidden first, so enemies holding it as their target see
## "dead" and pick someone else, and is freed a few seconds later.

const RETAUNT := 1.0
const GONE_AFTER := 8.0
const GILT := Color("f0c040")

var singer: Hero = null
var ability := {}
var life := 5.0
var retaunt_t := 0.0
var bowed := false
var gone_t := 0.0


func _ready() -> void:
	super._ready()
	peaceful = true
	party = null
	collision_layer = 0
	collision_mask = 0
	move_speed = 0.0
	add_to_group("heroes")
	add_to_group("chorus")
	invuln_t = 0.2


func _physics_process(delta: float) -> void:
	anim_t += delta
	if bowed:
		gone_t += delta
		if gone_t > GONE_AFTER:
			queue_free()
		return
	flash_t = maxf(flash_t - delta, 0.0)
	invuln_t = maxf(invuln_t - delta, 0.0)
	life -= delta
	retaunt_t -= delta
	if retaunt_t <= 0.0:
		retaunt_t = RETAUNT
		_pull()
	if life <= 0.0 or (singer != null and not is_instance_valid(singer)):
		bow()
		return
	velocity = knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	queue_redraw()


## Every enemy within radius drops what it was doing and goes for the chorus girl until she bows.
func _pull() -> void:
	var r := float(ability.get("radius", 90))
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(global_position) <= r:
			enemy.taunt(self, maxf(life, 0.1))


func _on_death() -> void:
	super._on_death()
	bow()


## Curtain: the burst, the optional song, then gone (hidden, out of every group, freed a little later).
func bow() -> void:
	if bowed:
		return
	bowed = true
	dead = true
	var parent := get_parent()
	var reach := float(ability.get("reach", 46))
	var col := Color(str(ability.get("color", "f0c040")))
	Fx.ring(parent, global_position, reach, col)
	Fx.burst(parent, global_position + Vector2(0, -14), [col, Color("fff1b8"), Color.WHITE], 22, 80.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		if enemy.taunter == self:
			enemy.taunt_t = 0.0
			enemy.target = null
		if enemy.global_position.distance_to(global_position) <= reach + enemy.radius:
			var dmg := int(ability.get("damage", 14))
			if singer != null and is_instance_valid(singer):
				TreePerks.strike(singer, enemy, dmg, global_position, float(ability.get("knock", 200)), ability)
			else:
				enemy.take_hit(dmg, global_position, float(ability.get("knock", 200)))
	if float(ability.get("song", 0)) > 0.0 and singer != null and is_instance_valid(singer):  # skill tree rider (issue #25)
		for o in get_tree().get_nodes_in_group("heroes"):
			var other := o as Hero
			if other and not other.dead and other.party == singer.party and other.global_position.distance_to(global_position) <= reach + 40.0:
				Abilities.sing_to(other, float(ability["song"]), 0.15, 0.2)
	remove_from_group("heroes")
	remove_from_group("chorus")
	visible = false
	set_physics_process(true)


func _process(_delta: float) -> void:
	if bowed:
		return
	_update_frame()
	if art_sprite != null:
		art_sprite.modulate = Color(1.35, 1.15, 0.6, 0.85)  # gilded, and not quite solid
	if body_sprite != null:
		body_sprite.modulate = Color(1.35, 1.15, 0.6, 0.85)
		outfit_sprite.modulate = Color(1.35, 1.15, 0.6, 0.85)
	if ground:
		ground.queue_redraw()
	if overlay:
		overlay.queue_redraw()


## Under her (Hero's ground layer, so it stays off the pixel FX layer the hero itself is on).
func _draw_ground() -> void:
	if bowed:
		return
	var g := ground
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	g.draw_circle(Vector2.ZERO, 5.5, Color(0, 0, 0, 0.3))
	# A spotlight pool under her, and the edge of her pull, faint.
	var k := clampf(life, 0.0, 1.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
	g.draw_circle(Vector2.ZERO, 12.0, Color(GILT, 0.18 * k))
	g.draw_arc(Vector2.ZERO, float(ability.get("radius", 90)), 0, TAU, 40, Color(GILT, 0.12 * k), 1.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	if bowed:
		return
	var total := maxf(float(ability.get("time", 5.0)), 0.1)
	UiSkin.field_bar(overlay, -28, 16, clampf(life / total, 0.0, 1.0), "brass")  # how long the song has left
	if hp < max_hp:
		UiSkin.field_bar(overlay, -24, 16, float(hp) / max_hp, "enemy", Access.danger_patterns and hp * 4 <= max_hp)
