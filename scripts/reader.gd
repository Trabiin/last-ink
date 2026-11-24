class_name Reader
extends Enemy
## Eraser Reader (issues #28, #206): one of Verity's archivists, who reads the names before the fire.
## Pattern: chases and lunges with a lit taper like a Nibbler (Enemy). Every few seconds, from a little way
## off, it stops and reads a name aloud from its ledger (READ_TIME; the tell: a warning sign over its head,
## the name written out letter by letter above it, and a dashed ring on the floor showing how far its voice
## carries). While it reads, every other Eraser inside the ring is spurred on and hits harder
## (Enemy.rally, the chevrons over their heads). A name read to the end keeps them spurred a little longer,
## and the Reader comes on fast for the lunge that follows, which hits harder too. Any hit interrupts the
## reading and staggers it, so the answer is to go for the Reader first (the ally AI does: priority()).

const READ_EVERY := 7.0
const READ_FIRST := 1.5
const READ_TIME := 1.6
const READ_MIN := 36.0  # closer than this it just lunges
const READ_MAX := 110.0
const RALLY_R := 80.0  # how far the voice carries
const RALLY_AFTER := 2.5  # a finished reading keeps the others spurred this long
const NAMED_MULT := 1.5  # the lunge after a finished reading
const NAMED_SPEED := 1.6  # ... and how fast it comes on for it
const NAMED_FOR := 3.0  # seconds it stays eager before giving up on the named lunge
const INTERRUPT_STAGGER := 0.9

## Extra state past Enemy.State.
enum { S_READ = 10 }

## Names it reads, when data/enemies.json gives none ("names" under the reader).
const NAMES := ["Ada Thole", "Wm. Pellory", "Mercy Gaunt", "Tam Hobb", "Old Sorrel", "Jory Fenn", "Agnes Lark"]  # no-tr: proper names

var damage := 7  # its taper lunge (data/enemies.json overrides it)
var read_cd := READ_FIRST
var named_t := 0.0  # > 0: a name was read to the end and the next lunge is for it
var name_text := ""
var base_speed := -1.0
var ring: FloorMark = null


func _ready() -> void:
	super._ready()
	read_cd = READ_FIRST + randf_range(0.0, 2.0)  # a pair doesn't read in chorus


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	if base_speed < 0.0:
		base_speed = move_speed  # EnemyKinds.spawn sets the data's speed after _ready
	if state == S_READ:
		_read_process(delta)
		return
	var pd := delta * Assists.pace()
	read_cd -= pd
	if named_t > 0.0:
		named_t -= pd
		if named_t <= 0.0 or state == State.RECOVER:  # it lunged (or gave up): back to its usual pace
			named_t = 0.0
			move_speed = base_speed
	if state == State.CHASE and read_cd <= 0.0 and named_t <= 0.0 and target != null and not target.dead and stun_left() <= 0.0:
		var d := target.global_position.distance_to(global_position)
		if d >= READ_MIN and d <= READ_MAX:
			_start_reading()
			return
	super._physics_process(delta)


func _start_reading() -> void:
	_set_state(S_READ, READ_TIME)
	if state != S_READ:
		return  # stunned
	var names: Array = EnemyKinds.kind(Journal.kind_of(self)).get("names", NAMES)
	name_text = str(names[randi() % names.size()]) if not names.is_empty() else ""
	Audio.sfx("talk", 0.62, -4.0, tr("An Eraser reads a name aloud"))
	if ring == null or not is_instance_valid(ring):
		ring = FloorMark.put(self, _paint_ring)
	queue_redraw()


func _read_process(delta: float) -> void:
	var pd := delta * Assists.pace()  # enemy speed assist (issue #192): a slower pace reads slower
	anim_t += pd
	flash_t = maxf(flash_t - pd, 0.0)
	taunt_t = maxf(taunt_t - pd, 0.0)
	state_t -= pd
	if target and not target.dead:
		facing = (target.global_position - global_position).normalized()
	for e in _erasers_in_reach():
		e.rally(0.25)  # refreshed every frame: it ends a moment after the reading stops
	velocity = knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * pd)
	_slide()
	if ring != null and is_instance_valid(ring):
		ring.global_position = global_position
	if state_t <= 0.0:
		for e in _erasers_in_reach():
			e.rally(RALLY_AFTER)
		Fx.damage_number(get_parent(), global_position + Vector2(0, -30), tr("Struck out!"), Color("ffd166"))
		named_t = NAMED_FOR
		move_speed = base_speed * NAMED_SPEED
		read_cd = READ_EVERY + randf_range(-0.5, 1.0)
		_end_reading()
		_set_state(State.CHASE, 0.0)
	queue_redraw()


## Every other Eraser (data/enemies.json "faction": "erasers") its voice reaches.
func _erasers_in_reach() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e == self or e.dead or e.global_position.distance_to(global_position) > RALLY_R:
			continue
		if str(EnemyKinds.kind(Journal.kind_of(e)).get("faction", "")) == "erasers":
			out.append(e)
	return out


func _end_reading() -> void:
	if ring != null and is_instance_valid(ring):
		ring.queue_free()
	ring = null


func reading() -> bool:
	return state == S_READ and dying_t < 0.0


func priority() -> int:
	return 1 if reading() else 0


func lunge_damage() -> int:
	return roundi(damage * NAMED_MULT) if named_t > 0.0 else damage


func _set_state(s: int, t: float) -> void:
	var was := state
	super._set_state(s, t)
	if was == S_READ and state != S_READ:
		_end_reading()  # interrupted, stunned or finished: the ring goes


func _on_hit() -> void:
	if state == S_READ:  # the reading breaks off mid-name
		read_cd = READ_EVERY * 0.6
		Fx.damage_number(get_parent(), global_position + Vector2(0, -30), tr("Interrupted!"), Color("e8e6f0"))
		_set_state(State.STAGGER, INTERRUPT_STAGGER)
		return
	super._on_hit()


func _on_death() -> void:
	_end_reading()
	super._on_death()


func _exit_tree() -> void:
	_end_reading()


func _process(delta: float) -> void:
	if art == null or dying_t >= 0.0 or flash_t > 0.0 or state != S_READ:
		super._process(delta)
		return
	# Reading from the ledger: a "read" animation when the final art has one, else the first attack frame held.
	if art.has("read"):
		art.apply(sprite, "read", art_row(), anim_t)
	else:
		art.apply_frame(sprite, "attack", art_row(), 0)
	sprite.position = Vector2(0, sin(anim_t * 9.0) * 0.5)
	queue_redraw()
	overlay.queue_redraw()


## The ring on the floor: how far the voice carries, filling as the reading goes on.
func _paint_ring(ci: CanvasItem) -> void:
	if state != S_READ:
		return
	Telegraph.aura(ci, Vector2.ZERO, RALLY_R, clampf(1.0 - state_t / READ_TIME, 0.0, 1.0))


func _draw_overlay() -> void:
	super._draw_overlay()
	if dying_t >= 0.0 or state != S_READ:
		return
	Telegraph.alert(overlay, Vector2(-2, -14), 10)
	if name_text == "":
		return
	# The name, written out as it is read, in ink-outlined cream letters (like the damage numbers).
	var k := clampf(1.0 - state_t / READ_TIME, 0.0, 1.0)
	var shown := name_text.substr(0, ceili(name_text.length() * minf(k * 1.4, 1.0)))
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
	var at := Vector2(-w / 2.0, -34.0)
	for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		overlay.draw_string(font, at + o, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(0.08, 0.05, 0.08, 0.9))
	overlay.draw_string(font, at, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color("f3ead2"))
