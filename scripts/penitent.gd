class_name Penitent
extends Enemy
## Blotted Penitent (issues #28, #206): a monk of Saint Ledger's the Blank half ate, still doing penance.
## Pattern: shuffles in and swings its scourge like a Nibbler's lunge (Enemy). Every few seconds, when a hero
## is in reach, it grabs instead:
##   hunch (GRAB_WINDUP, the tell: a warning sign over its head, it shakes, and a hatched circle on the floor
##   shows where its hands will close) -> reach (a short shuffle forward, hands out) -> hold.
## A hero caught in the hold can't move, swing or cast (a stun that says "Held!") and is slowly wiped:
## a little damage that never kills, and Erased when the hold runs out. Any hit on the Penitent from
## someone else makes it let go and reel back for a long moment, so a party member (or the ally AI, which
## treats a hold as the most urgent thing on the field, see priority()) is the answer. Alone, the held hero
## can shorten it by pressing Attack. Hits don't stop the hunch (it is set on its penance): step back out of
## the circle instead, and a whiff leaves it open.
## The hold runs on real time: the enemy speed assist slows everything else down, never makes a hold longer.

const GRAB_EVERY := 5.5  # seconds between grabs
const GRAB_FIRST := 2.0
const GRAB_WINDUP := 0.95
const GRAB_REACH := 0.28
const GRAB_REACH_SPEED := 70.0
const GRAB_AHEAD := 16.0  # the hands' circle sits this far in front of it ...
const GRAB_RADIUS := 11.0  # ... and is this big
const HOLD_TIME := 2.0
const STRUGGLE := 0.3  # each press of Attack by a held, player-steered hero takes this off the hold
const WIPE_EVERY := 0.5
const WIPE_DAMAGE := 2
const ERASE_TIME := 3.5
const LET_GO_STAGGER := 1.4
const MISS_RECOVER := 0.9

## Extra states past Enemy.State.
enum { S_HUNCH = 10, S_REACH = 11, S_HOLD = 12 }

var damage := 7  # its scourge swing (data/enemies.json overrides it)
var grab_cd := GRAB_FIRST
var reach_dir := Vector2.DOWN
var held: Hero = null
var hold_left := 0.0
var wipe_t := 0.0
static var _hint_told := false


func _ready() -> void:
	super._ready()
	grab_cd = GRAB_FIRST + randf_range(0.0, 1.5)  # a pair doesn't grab in step


func _physics_process(delta: float) -> void:
	if dying_t >= 0.0:
		return
	if state >= S_HUNCH:
		_grab_process(delta)
		return
	grab_cd -= delta * Assists.pace()
	if state == State.CHASE and grab_cd <= 0.0 and _can_grab(target):
		_set_state(S_HUNCH, GRAB_WINDUP)
		Audio.sfx("block", 0.6, -10.0, "-")  # cloth and old bones creaking
		queue_redraw()
		return
	super._physics_process(delta)


func _can_grab(h: Hero) -> bool:
	if h == null or h.dead or stun_left() > 0.0:
		return false
	if h.global_position.distance_to(global_position) > LUNGE_RANGE:
		return false
	return not Status.immune(h, "stun") and not Status.has(h, "stun")  # never two holds on one hero


func _grab_process(delta: float) -> void:
	var pd := delta * Assists.pace()  # enemy speed assist (issue #192): the hunch and reach play slower
	anim_t += pd
	flash_t = maxf(flash_t - pd, 0.0)
	taunt_t = maxf(taunt_t - pd, 0.0)
	match state:
		S_HUNCH:
			state_t -= pd
			if target and not target.dead:
				facing = (target.global_position - global_position).normalized()
			velocity = knockback
			if state_t <= 0.0:
				reach_dir = facing
				_set_state(S_REACH, GRAB_REACH)
		S_REACH:
			state_t -= pd
			velocity = reach_dir * GRAB_REACH_SPEED + knockback
			var h := _hero_in_hands()
			if h != null:
				_take_hold(h)
			elif state_t <= 0.0:
				grab_cd = GRAB_EVERY * 0.5 + randf_range(0.0, 1.5)
				_set_state(State.RECOVER, MISS_RECOVER)
		S_HOLD:
			_hold_process(delta)  # real time, see the class comment
			velocity = knockback
	knockback = knockback.move_toward(Vector2.ZERO, 700.0 * pd)
	_slide()
	queue_redraw()


## Where its hands will close, in world space.
func _hands_at() -> Vector2:
	return global_position + (reach_dir if state == S_REACH else facing) * GRAB_AHEAD


func _hero_in_hands() -> Hero:
	var at := _hands_at()
	for n in get_tree().get_nodes_in_group("heroes"):
		var h := n as Hero
		if h != null and not h.dead and h.global_position.distance_to(at) <= GRAB_RADIUS + h.radius:
			return h
	return null


func _take_hold(h: Hero) -> void:
	grab_cd = GRAB_EVERY + randf_range(-0.5, 1.0)
	if h.invuln_t > 0.0 or h.parry_t > 0.0 or h.dash_t > 0.0 \
			or not Status.apply(h, "stun", HOLD_TIME + 0.5, {"label": tr("Held!")}):
		_set_state(State.RECOVER, MISS_RECOVER)  # dodged through it, or proof against holds: it grabs air
		return
	held = h
	hold_left = HOLD_TIME
	wipe_t = WIPE_EVERY
	facing = (h.global_position - global_position).normalized() if h.global_position != global_position else facing
	_set_state(S_HOLD, HOLD_TIME)
	Audio.sfx("hurt", 0.7, -6.0, tr("A Penitent grabs hold"))
	if h.controlled and not _hint_told:
		_hint_told = true
		var scene := get_tree().current_scene
		if scene != null and scene.get("hud") != null:
			scene.hud.say(tr("Held! Press Attack to struggle, or let an ally hit the Penitent to break its grip."), 4.0)


func _hold_process(delta: float) -> void:
	if held == null or not is_instance_valid(held) or held.dead:
		_release(false)
		_set_state(State.RECOVER, 0.6)
		return
	hold_left -= delta
	if held.controlled and Input.is_action_just_pressed("attack"):
		hold_left -= STRUGGLE
		held.flash_t = 0.06
		Fx.burst(get_parent(), held.global_position + Vector2(0, -8), [Color("e8e6f0"), Color.BLACK], 3, 30.0)
	state_t = hold_left
	var to := held.global_position - global_position
	if to.length() > 0.5:
		facing = to.normalized()
	held.knockback = Vector2.ZERO
	held.global_position = held.global_position.lerp(global_position + facing * (GRAB_AHEAD - 4.0), minf(1.0, delta * 10.0))
	wipe_t -= delta
	if wipe_t <= 0.0:
		wipe_t = WIPE_EVERY
		Status.hurt(held, Empire.damage_to_party(roundi(WIPE_DAMAGE * hit_mult())), Status.color_of("erase"), true)  # never kills
	if hold_left <= 0.0:
		_release(true)
		_set_state(State.RECOVER, 0.8)


## Lets go of the held hero. wiped: the hold ran its course, so it leaves the hero Erased and shoves them off.
func _release(wiped: bool) -> void:
	var h := held
	held = null
	if h == null or not is_instance_valid(h):
		return
	Status.cure(h, ["stun"])  # ends the hold (and, like any stun, leaves a few seconds' immunity: no chain grabs)
	if h.dead:
		return
	if wiped:
		Status.apply(h, "erase", ERASE_TIME, {"label": tr("Wiped!")})
		h.knockback = facing * 120.0


func holding() -> Hero:
	return held


func priority() -> int:
	return 2 if held != null else 0


func lunge_damage() -> int:
	return damage


func _on_hit() -> void:
	match state:
		S_HOLD:  # someone came to help: it lets go and reels
			_release(false)
			Fx.damage_number(get_parent(), global_position + Vector2(0, -26), tr("Let go!"), Color("ffe08a"))
			grab_cd = maxf(grab_cd, GRAB_EVERY)
			_set_state(State.STAGGER, LET_GO_STAGGER)
		S_HUNCH, S_REACH:
			pass  # set on it: hits land but don't stop the grab, stepping back does
		_:
			super._on_hit()


func stun(t: float) -> void:
	if held != null and not dead and t > 0.0:
		_release(false)
	super.stun(t)


func _on_death() -> void:
	_release(false)
	super._on_death()


func _exit_tree() -> void:
	_release(false)  # the mission ended or the scene changed mid-hold: never leave a hero stuck


func _process(delta: float) -> void:
	if art == null or dying_t >= 0.0 or flash_t > 0.0 or state < S_HUNCH:
		super._process(delta)
		return
	# Until the final art brings its own "grab" animation, the scourge swing's frames stand in.
	var anim := "grab" if art.has("grab") else "attack"
	var n := art.frames_of(anim)
	var i := 1
	match state:
		S_REACH:
			i = 2 + int((1.0 - state_t / GRAB_REACH) * float(n - 3))
		S_HOLD:
			i = n - 2 + int(anim_t * 4.0) % 2  # wringing
	art.apply_frame(sprite, anim, art_row(), clampi(i, 0, n - 1))
	sprite.position = Vector2(randf_range(-0.8, 0.8), 0.5) if state == S_HUNCH else Vector2.ZERO
	queue_redraw()
	overlay.queue_redraw()


func _draw() -> void:
	if dying_t >= 0.0:
		return
	draw_shadow(5.0)
	if state == S_HUNCH or state == S_REACH:  # where the hands will close, on the ground
		var k := clampf(1.0 - state_t / GRAB_WINDUP, 0.0, 1.0) if state == S_HUNCH else 1.0
		draw_set_transform(_hands_at() - global_position, 0.0, Vector2(1.0, 0.6))
		Telegraph.circle(self, Vector2.ZERO, GRAB_RADIUS, k)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_overlay() -> void:
	super._draw_overlay()
	if dying_t >= 0.0:
		return
	if state == S_HUNCH:
		Telegraph.alert(overlay, Vector2(-2, -14), 10)
	if state == S_HOLD and held != null and is_instance_valid(held):
		# Two blank white hands on the hero's shoulders, and a ring round them that empties as the hold runs out.
		var at := held.global_position - global_position
		for sx in [-1.0, 1.0]:
			var hp_ := at + Vector2(4.0 * sx, -11.0)
			overlay.draw_circle(hp_, 2.6, Color(0.08, 0.05, 0.08, 0.8))
			overlay.draw_circle(hp_, 1.8, Color("efece4"))
		var k := clampf(hold_left / HOLD_TIME, 0.0, 1.0)
		overlay.draw_arc(at + Vector2(0, -8), 11.0, -PI / 2.0, -PI / 2.0 + TAU * k, 24, Color(0.08, 0.05, 0.08, 0.8), 3.0)
		overlay.draw_arc(at + Vector2(0, -8), 11.0, -PI / 2.0, -PI / 2.0 + TAU * k, 24, Color("efece4"), 1.0)
