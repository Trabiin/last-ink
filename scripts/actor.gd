class_name Actor
extends CharacterBody2D
## Shared base for heroes and enemies: HP, knockback, hit flash.

signal died(actor: Actor)

var max_hp := 40
var hp := 40
var move_speed := 80.0
var facing := Vector2.DOWN
var knockback := Vector2.ZERO
var flash_t := 0.0
var invuln_t := 0.0
var dead := false
var radius := 6.0
var number_color := Color.WHITE
var anim_t := 0.0


func _ready() -> void:
	hp = max_hp
	var shape := CircleShape2D.new()
	shape.radius = radius
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	collision_mask = 1


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if dead or invuln_t > 0.0:
		return false
	amount = _adjust_damage(Settings.difficulty_damage(self, amount))  # Options: difficulty
	if amount <= 0:
		return true  # soaked (a hero's shield): no knockback, no flash
	hp = max(hp - amount, 0)
	var away := global_position - from
	if away.length() < 0.01:
		away = Vector2.RIGHT.rotated(randf() * TAU)
	knockback = away.normalized() * force
	flash_t = 0.12
	Fx.damage_number(get_parent(), global_position + Vector2(0, -16), str(amount), number_color)
	_on_hit()
	Audio.hit(self is Hero, hp <= 0)
	if hp <= 0:
		dead = true
		_on_death()
		died.emit(self)
	return true


## Lets a subclass shrink or soak a hit before it lands (abilities: shields, guard).
func _adjust_damage(amount: int) -> int:
	return amount


func _on_hit() -> void:
	pass


func _on_death() -> void:
	pass


## Returns WHITE while the hit flash is active (a soft tint with reduced flashing), else the given color.
func c(col: Color) -> Color:
	return Access.flash(col) if flash_t > 0.0 else col


func draw_shadow(r := 7.0) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
