class_name Hero
extends Actor
## A party member. Either player-controlled or driven by the ally AI.
## Visuals: an art pass sprite set (scripts/sprite_set.gd, data/sprites.json) when the character has one,
## otherwise the old paper doll (CC0 Puny Characters body + outfit layers, recolored per hero).

const SWING_TIME := 0.24
const REVIVE_TIME := 2.5

var hero_name := tr("Ash")
var hero_id := "ash"  # recruit id (data/recruits.json, data/heroes.json); banter speakers use it
## Paper doll: the shared body layer plus one outfit layer, both recolored in code.
var outfit := "archer"
var colors := {
	"skin": Color("e9c4a6"), "cloth": Color("4a4f8a"), "leather": Color("5a4636"),
	"boots": Color("2e2838"), "trim": Color("d9d4e8"),
}
var body_sprite: Sprite2D
var outfit_sprite: Sprite2D
## Art pass sprite (null while this character still uses the paper doll).
var art: SpriteSet
var art_sprite: Sprite2D
var _art_id := ""
var _anim := ""
var _anim_t := 0.0
var overlay: Node2D
var controlled := false
var party  # main.gd or hub.gd: gives access to leader, shake()
var peaceful := false  # in town the attack button talks instead

# Mana-style attack power gauge: refills after each swing; early swings hit weaker.
var power := 1.0
var power_rate := 0.95
var base_damage := 10
var reach := 20.0
var arc := deg_to_rad(70.0)
## Weapon trail drawn in code over every swing (data/heroes.json "trail"): a sweep, or a jab for pikes.
var trail_color := Color("e8e4d8")
var trail_thrust := false
var swing_t := 0.0
var swing_power := 1.0
var swing_hit_done := false
var moving := false

# AI state
var ai_target: Enemy
var ai_side := 1.0
var stuck_t := 0.0
var detour_t := 0.0
var detour_dir := Vector2.ZERO

var revive_progress := 0.0

## Ally AI presets (issue #9): Aggressive, Balanced, Keep Distance, Support. The logic lives in scripts/ally_ai.gd.
const AI_STYLES := AllyAI.PRESETS
var ai_style := "balanced"
# Passive poultice (Mother Gristle): every heal_every seconds, patch the most hurt ally in range.
var heal_every := 0.0
var heal_amount := 0
var heal_range := 80.0
var heal_t := 3.0
# Armor (issue #15): this fraction of every hit is blocked. Set by Progress.apply_to from gear.
var guard := 0.0

# Abilities and Ink (issue #7; what each one does lives in scripts/abilities.gd).
var abilities: Array = []  # ability dicts from data/abilities.json, slot i = key i+1
var cooldowns: Array = []  # seconds left per slot
var max_ink := 0.0
var ink := 0.0
var ink_regen := Abilities.REGEN
var cast_t := 0.0  # brief casting pose
var cast_color := Color.WHITE
var shield_hp := 0  # Rewrite: soaks this much damage
var shield_t := 0.0
var guard_t := 0.0  # Hold the Line: takes guard_cut less damage while > 0
var guard_cut := 0.0
var dash_t := 0.0  # Strikethrough / Long Thrust
var dash_dir := Vector2.ZERO
var dash_speed := 0.0
var dash_ability := {}
var dash_hit: Array = []
var ai_ability_t := 0.0
## Lamps Out (Jessamy): out of sight while vanish_t > 0, moving faster; the next swing that lands is a crit.
var vanish_t := 0.0
var vanish_speed := 1.0
var crit_next := 1.0
## Wading through something that drags at the feet (a Whitewasher's wet stripe, scripts/white_stripe.gd):
## it sets mire_t each frame the hero stands in it; feet move at mire_mult of their speed while it lasts.
var mire_t := 0.0
var mire_mult := 1.0
## Big Ottoline: this fraction of knockback still moves her (1 = normal, data/heroes.json "poise").
var poise := 1.0
## Riposte (Fauvette): while parry_t > 0 the next hit is turned aside and answered (abilities.gd kind "parry").
var parry_t := 0.0
var parry_ability := {}
## Torch Song (Saffron, abilities.gd kind "song", Chapter 3): while song_t > 0 this hero deals song_boost more
## damage (TreePerks.damage_bonus) and the power gauge fills song_rate faster.
var song_t := 0.0
var song_boost := 0.0
var song_rate := 0.0
## Skill tree (issue #25, scripts/skill_tree.gd): passives the hero's learned nodes give (summed values,
## handled in scripts/tree_perks.gd), who the ally AI goes for, and the once-a-mission last stand.
var perks := {}
var ai_focus := ""
var ai_focus_t := 0.0
var last_stand_left := 0
var last_stand_set := false
var last_stand_spent := false

# Charged tech (issue #8; rules, blast and glow live in scripts/techs.gd).
var charging := false
var charge_t := 0.0
var charge_ready := false
var tech_flash_t := 0.0
## Weapon skill levels (#24): the hero knows several techs. Holding Attack longer reaches the next one;
## charge_stage is the last one reached (0 = none yet). tech_flash_color tints the release flash.
var charge_stage := 0
var tech_flash_color := Color.WHITE
## Allies charge techs too (scripts/ally_techs.gd): ai_charging marks a charge the AI started.
var ai_charging := false
var tech_mode := "auto"  # "auto" (the preset decides) or "call" (only when ordered from the quick menu)
var ai_tech_order_t := 0.0  # > 0 while a quick menu order to fire the tech stands
var ai_tech_cd := 0.0
var ai_tech_hold := 0.0
var ai_think_t := 0.0
var ai_tech_dir := Vector2.DOWN
var ai_tech_focus: Enemy = null
var ai_tech_spot := Vector2.ZERO  # where it is walking to land the tech
var ai_tech_promise := false  # a tech looks worth it: the preset holds its swing so the gauge can fill
var ai_tech_full_t := 0.0  # seconds the gauge has sat full while a tech was promised
var ai_tech := {}  # the tech the AI is charging (AllyTechs.techs_of picks among the hero's techs)


func _ready() -> void:
	radius = 5.0
	super._ready()
	build_doll()
	collision_layer = 2
	number_color = Color("ff6b6b")
	# Missions often open on a conversation, which pauses the tree before _process ever runs, so the
	# body would keep the Puny doll until the talk ended. Pick the art (and its first frame) right away:
	# deferred, because whoever spawned us sets hero_id / the "id" meta after add_child.
	_update_frame.call_deferred()


func _physics_process(delta: float) -> void:
	anim_t += delta
	flash_t = max(flash_t - delta, 0.0)
	invuln_t = max(invuln_t - delta, 0.0)
	var held := Status.tick(self, delta)  # poison, burn, stun, Erase and boons (issue #112)

	if dead:
		knockback = knockback.move_toward(Vector2.ZERO, 600.0 * delta)
		velocity = knockback
		move_and_slide()
		queue_redraw()
		return

	if heal_every > 0.0:
		_update_heal(delta)
	_update_abilities(delta)
	if held:  # stunned: no moving, swinging or casting until it wears off
		velocity = knockback
		knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		moving = false
		queue_redraw()
		return

	if dash_t > 0.0:
		dash_t -= delta
		velocity = dash_dir * dash_speed
		move_and_slide()
		Abilities.dash_hits(self)
		moving = true
		queue_redraw()
		return

	if swing_t > 0.0:
		swing_t -= delta
		if not swing_hit_done and swing_t <= SWING_TIME * 0.6:
			swing_hit_done = true
			_apply_hit()
	else:
		power = min(power + power_rate * (1.0 + (song_rate if song_t > 0.0 else 0.0)) * delta, 1.0)

	var dir := Vector2.ZERO
	if controlled and party and party.get("quick_open") == true:
		dir = Vector2.ZERO  # the quick menu has the controls (time is slowed, not stopped)
	elif controlled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if not peaceful:
			Techs.control(self, delta)  # tap = swing; full gauge + hold = charged tech
		if not peaceful:  # (the quick menu branch above already keeps these quiet while it is open)
			for i in abilities.size():
				if Input.is_action_just_pressed("ability_%d" % (i + 1)):
					Abilities.use(self, i)
	else:
		dir = _ai(delta)

	if dir.length() > 0.1 and swing_t <= 0.0 and not ai_charging:  # a charging ally keeps its aim while it steps
		facing = dir.normalized()
	var spd := (vanish_speed if vanish_t > 0.0 else 1.0) * move_speed * (0.3 if swing_t > 0.0 or cast_t > 0.0 else (Techs.CHARGE_SPEED if charging else 1.0))
	if mire_t > 0.0:
		mire_t -= delta
		spd *= mire_mult
	velocity = dir * spd + knockback
	knockback = knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	moving = dir.length() > 0.1

	if not controlled and dir.length() > 0.3 and get_real_velocity().length() < 8.0:
		stuck_t += delta
	else:
		stuck_t = 0.0
	queue_redraw()


func try_attack() -> void:
	if swing_t > 0.0 or dead:
		return
	swing_t = SWING_TIME
	swing_power = power
	power = 0.0
	swing_hit_done = false
	Audio.sfx("swing", 0.85 + 0.25 * swing_power, -6.0 + 6.0 * swing_power)


func _apply_hit() -> void:
	var dmg := maxi(1, roundi(base_damage * swing_power * crit_next * Status.swing_mult(self)))
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var to := enemy.global_position - global_position
		if to.length() <= reach + enemy.radius and absf(facing.angle_to(to)) <= arc:
			if TreePerks.strike(self, enemy, dmg, global_position, 120.0 + 160.0 * swing_power, {}, "swing"):
				hit_any = true
				Status.swing_landed(self, enemy, dmg)  # trinket perks: first strike, lifesteal, stun (issue #112)
	if hit_any and crit_next > 1.0:
		Fx.damage_number(get_parent(), global_position + Vector2(0, -30), tr("Ambush!"), Color("c9b8ff"))
		crit_next = 1.0
		vanish_t = 0.0  # striking gives her away
	if hit_any and swing_power >= 1.0:
		ink = minf(ink + Abilities.HIT_GAIN, max_ink)  # a full-power hit that lands writes a little Ink
	if hit_any:
		gain_skill("weapon", "", Skills.swing_points(swing_power))  # weapon skill grows with use (issue #24)
	if hit_any and party:
		party.shake(1.5 + 2.0 * swing_power)
		Rumble.landed(self, swing_power)  # only when this is the hero you control (issue #149)


## Rewrite's shield soaks first, then Hold the Line's guard cuts what's left.
func _adjust_damage(amount: int) -> int:
	if shield_hp > 0:
		var soaked := mini(shield_hp, amount)
		shield_hp -= soaked
		amount -= soaked
		if amount <= 0:
			Fx.damage_number(get_parent(), global_position + Vector2(0, -16), Loc.t("blocked"), Color("9fd8ff"))
			invuln_t = 0.3
			return 0
	amount = Status.adjust_incoming(self, amount)  # Iron Tea, the ward, Widow's Ribbon (issue #112)
	if guard_t > 0.0:
		amount = maxi(1, roundi(amount * (1.0 - guard_cut)))
	if guard > 0.0:  # armor (issue #15)
		amount = maxi(1, roundi(amount * (1.0 - guard)))
	if party != null:
		amount = TreePerks.adjust(self, amount)  # allies' guard auras and the last stand (issue #25)
	return amount


func take_hit(amount: int, from: Vector2, force := 160.0) -> bool:
	if not dead and invuln_t <= 0.0 and parry_t <= 0.0 and amount > 0 and party != null:
		amount = TreePerks.incoming(self, amount, from)  # skill tree: evading, a bodyguard nearby (issue #25)
		if amount < 0:
			return true
	if parry_t > 0.0 and not dead and amount > 0:
		Abilities.riposte(self, from)
		return true
	if amount > 0 and not dead and invuln_t <= 0.0:
		Status.thorns(self, from)  # Thornwire Bracelet bites back (issue #112)
	var before := hp
	var landed := super.take_hit(amount, from, force * poise)
	TreePerks.hit_back(self, before - hp, from)  # skill tree thorns (issue #25)
	if hp < before:
		AllyTechs.interrupted(self, before - hp)  # a heavy blow breaks an ally's charge
		if dead:
			Rumble.downed(self)  # the pad, when this is the hero you control (issue #149)
		else:
			Rumble.hurt(self, float(before - hp) / maxf(1.0, float(max_hp)))
	return landed


## Out of sight for t seconds (enemies' _find_target skips hidden heroes; bosses still see).
func vanish(t: float, speed_mult: float, crit: float) -> void:
	vanish_t = t
	vanish_speed = speed_mult
	crit_next = maxf(crit_next, crit)


func hidden() -> bool:
	return vanish_t > 0.0 and not dead


## Weapon and Ink skill points (issue #24, scripts/skills.gd). kind "weapon" or "ink" (color = the
## ability's Ink colour). Only counts on missions; the scene hears about level-ups through skill_up().
func gain_skill(kind: String, color: String, pts: int) -> void:
	if pts <= 0 or peaceful or party == null or not party.has_method("skill_up"):
		return
	var ups: Array = Skills.add_weapon(hero_id, pts) if kind == "weapon" else Skills.add_ink(hero_id, color, pts)
	for lvl in ups:
		if kind == "ink":
			refresh_abilities()
		party.skill_up(self, kind, color, int(lvl))


## Re-reads the abilities at the hero's current Ink levels (a tier change mid-mission), keeping cooldowns.
func refresh_abilities() -> void:
	var ids := abilities.map(func(a): return str(a.get("id", "")))
	var fresh := Abilities.for_ids(ids, hero_id)
	if fresh.size() == abilities.size():
		abilities = fresh


func set_abilities(ids: Array, ink_pool: float) -> void:
	abilities = Abilities.for_ids(ids, hero_id)
	cooldowns = []
	cooldowns.resize(abilities.size())
	cooldowns.fill(0.0)
	max_ink = ink_pool
	ink = ink_pool


func start_dash(a: Dictionary) -> void:
	dash_ability = a
	dash_dir = facing.normalized()
	dash_t = 0.18
	dash_speed = float(a.get("distance", 70)) / dash_t
	dash_hit.clear()
	invuln_t = maxf(invuln_t, dash_t + 0.1)  # dashing through a lunge is the point
	swing_t = 0.0


func _update_abilities(delta: float) -> void:
	for i in cooldowns.size():
		cooldowns[i] = maxf(cooldowns[i] - delta, 0.0)
	if max_ink > 0.0:
		ink = minf(ink + ink_regen * delta, max_ink)
	cast_t = maxf(cast_t - delta, 0.0)
	tech_flash_t = maxf(tech_flash_t - delta, 0.0)
	Techs.tick(self)
	guard_t = maxf(guard_t - delta, 0.0)
	parry_t = maxf(parry_t - delta, 0.0)
	song_t = maxf(song_t - delta, 0.0)
	if vanish_t > 0.0:
		vanish_t -= delta
		if vanish_t <= 0.0:
			Fx.burst(get_parent(), global_position + Vector2(0, -8), [Color("2a2438"), Color("4a4060")], 10, 40.0)
	if shield_t > 0.0:
		shield_t -= delta
		if shield_t <= 0.0:
			shield_hp = 0


func _on_hit() -> void:
	invuln_t = 0.7
	if party:
		party.shake(3.0)


func _on_death() -> void:
	revive_progress = 0.0
	swing_t = 0.0
	dash_t = 0.0
	Techs.cancel(self)
	shield_hp = 0
	guard_t = 0.0
	vanish_t = 0.0
	crit_next = 1.0
	parry_t = 0.0
	song_t = 0.0


func revive() -> void:
	dead = false
	hp = max_hp / 2
	invuln_t = 1.0
	revive_progress = 0.0
	Fx.burst(get_parent(), global_position + Vector2(0, -12), [Color("ffe08a"), Color.WHITE], 16, 70.0)


func _update_heal(delta: float) -> void:
	heal_t -= delta
	if heal_t > 0.0:
		return
	var best: Hero = null
	var best_ratio := 1.0
	for h in get_tree().get_nodes_in_group("heroes"):
		var other := h as Hero
		if other == null or other.dead or other.hp >= other.max_hp:
			continue
		if other.global_position.distance_to(global_position) > heal_range:
			continue
		var ratio := float(other.hp) / float(other.max_hp)
		if ratio < best_ratio and other.max_hp - other.hp >= mini(heal_amount, 3):
			best_ratio = ratio
			best = other
	if best == null:
		heal_t = 0.5  # nobody needs it: look again soon
		return
	var amount := mini(TreePerks.heal_amount(self, heal_amount), best.max_hp - best.hp)
	best.hp += amount
	Fx.damage_number(get_parent(), best.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
	Fx.burst(get_parent(), best.global_position + Vector2(0, -10), [Color("9fbf6a"), Color("dff5b0")], 10, 40.0)
	heal_t = heal_every


# ---------------------------------------------------------------- ally AI

func _ai(delta: float) -> Vector2:
	var leader: Hero = party.leader if party else null
	if leader == null or leader == self or leader.dead:
		return Vector2.ZERO
	var to_leader := leader.global_position - global_position
	if to_leader.length() > 380.0:
		global_position = leader.global_position - leader.facing * 18.0
		return Vector2.ZERO

	if detour_t > 0.0:
		detour_t -= delta
		return detour_dir
	if stuck_t > 0.35:
		stuck_t = 0.0
		detour_t = 0.4
		detour_dir = to_leader.normalized().rotated(PI / 2.0 * ai_side)
		ai_side = -ai_side
		return detour_dir

	return AllyAI.steer(self, leader, delta)


func _nearest_enemy(from: Vector2, max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_dist
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or enemy.untargetable():
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = enemy
	return best


# ---------------------------------------------------------------- paper doll

func build_doll() -> void:
	body_sprite = _layer(Art.BODY, Art.recolor_material("body", colors))
	outfit_sprite = _layer(Art.OUTFITS[outfit], Art.recolor_material(outfit, colors))
	art_sprite = Sprite2D.new()
	art_sprite.visible = false
	add_child(art_sprite)
	overlay = Node2D.new()
	add_child(overlay)
	overlay.draw.connect(_draw_overlay)


## Which sprite set this body wears: the town sets "id" meta on people, missions set hero_id.
func art_id() -> String:
	return str(get_meta("id")) if has_meta("id") else hero_id


func _refresh_art() -> void:
	var want := art_id()
	if want == _art_id:
		return
	_art_id = want
	art = SpriteSet.of(want)
	var on := art != null
	art_sprite.visible = on
	body_sprite.visible = not on
	outfit_sprite.visible = not on


func _layer(tex: Texture2D, mat: ShaderMaterial) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = 24
	s.vframes = 8
	s.offset = Vector2(0, -7)  # feet of the 32x32 Puny frame sit on the node origin
	s.material = mat
	add_child(s)
	return s


## Puny Characters sheet: rows are 8 directions clockwise from facing down,
## columns 0-3 walk, 4-7 sword swing, 19 hurt flash, 22-23 knocked down.
static func dir_row(v: Vector2) -> int:
	return posmod(roundi((PI / 2.0 - v.angle()) / (PI / 4.0)), 8)


func _update_frame() -> void:
	if body_sprite == null:
		return
	_refresh_art()
	var blink := invuln_t > 0.0 and not dead and Access.strobe(invuln_t, 10.0)
	modulate.a = 0.3 if vanish_t > 0.0 else ((0.7 if Access.reduce_flashing else 0.45) if blink else 1.0)  # reduced: held see-through, no blinking  # Lamps Out: a shadow of herself
	if art != null:
		_update_art()
		return
	var col := 0
	if dead:
		col = 23
	elif flash_t > 0.0:
		col = 19
	elif swing_t > 0.0:
		col = 4 + clampi(int((1.0 - swing_t / SWING_TIME) * 4.0), 0, 3)
	elif cast_t > 0.0:
		col = 4 + clampi(int((1.0 - cast_t / SWING_TIME) * 4.0), 0, 3)
	elif dash_t > 0.0:
		col = 5
	elif moving:
		col = int(anim_t * 9.0) % 4
	var frame := dir_row(facing) * 24 + col
	body_sprite.frame = frame
	outfit_sprite.frame = frame


## Picks the art pass animation from the hero's state. Timed actions (swing, cast, dash, tech)
## follow their own timers so the pose always matches the hit; the rest just play.
func _update_art() -> void:
	var row := dir_row(facing)
	var anim := "idle"
	var progress := -1.0  # 0..1 through a timed action, or -1 to play at the animation's fps
	if dead:
		anim = "ko"
	elif tech_flash_t > 0.0 and art.has("tech"):
		anim = "tech"  # release: second half of the clip
		progress = 0.5 + 0.5 * (1.0 - tech_flash_t / 0.35)
	elif charging and charge_t >= Techs.TAP and art.has("tech"):
		anim = "tech"  # wind-up: hold the crouch, flickering between its last two frames
		var n := art.frames_of("tech")
		var hold := clampi(n / 2 - 2 + (int(charge_t * 8.0) % 2), 0, n - 1)
		progress = (float(hold) + 0.5) / float(n)
	elif dash_t > 0.0:
		anim = "attack"
		progress = 0.7
	elif swing_t > 0.0:
		anim = "attack"
		progress = 1.0 - swing_t / SWING_TIME
	elif cast_t > 0.0:
		anim = "cast" if art.has("cast") else "attack"
		progress = 1.0 - cast_t / SWING_TIME
	elif flash_t > 0.0 or (invuln_t > 0.45 and art.has("hurt")):
		anim = "hurt"
	elif moving:
		anim = "walk"
	if not art.has(anim):
		anim = "idle" if art.has("idle") else "rot"
	if anim != _anim:
		_anim = anim
		_anim_t = 0.0
	else:
		_anim_t += get_process_delta_time()
	if progress >= 0.0:
		var n2 := art.frames_of(anim)
		art.apply_frame(art_sprite, anim, row, clampi(int(progress * n2), 0, n2 - 1))
	else:
		art.apply(art_sprite, anim, row, _anim_t)


func _process(_delta: float) -> void:
	_update_frame()
	queue_redraw()
	if overlay:
		overlay.queue_redraw()


func _draw() -> void:
	# Drawn before the child sprites, so it sits underneath them.
	draw_shadow(5.5)
	if not dead:
		Techs.draw_area(self, self)  # where a charging tech will land, on the ground


func _draw_overlay() -> void:
	if dead:
		if revive_progress > 0.0:
			overlay.draw_arc(Vector2(0, -6), 10.0, -PI / 2.0, -PI / 2.0 + TAU * revive_progress / REVIVE_TIME, 24, Color("ffe08a"), 1.5)
		return
	if shield_hp > 0:
		overlay.draw_arc(Vector2(0, -7), 11.0, 0, TAU, 24, Color("9fd8ff", 0.45 + 0.2 * sin(anim_t * 6.0)), 1.0)
	if parry_t > 0.0:  # Riposte: a crimson guard arc in front of her, ready to turn a blow
		var fa := facing.angle()
		overlay.draw_arc(Vector2(0, -7), 12.0, fa - 1.0, fa + 1.0, 12, Color("e0405a", 0.9), 1.5)
	if guard_t > 0.0:
		overlay.draw_arc(Vector2(0, -7), 12.5, PI * 0.15, PI * 0.85, 12, Color("f2a65a", 0.7), 1.5)
	if song_t > 0.0:  # Torch Song: a gold note drifts up beside the head while the song lasts
		var ny := -18.0 - fmod(anim_t * 10.0, 10.0)
		var na := clampf(song_t, 0.0, 1.0) * (1.0 - fmod(anim_t * 10.0, 10.0) / 12.0)
		var nc := Color("f0c040", na)
		overlay.draw_circle(Vector2(8, ny), 1.3, nc)
		overlay.draw_line(Vector2(9.2, ny), Vector2(9.2, ny - 4.0), nc, 1.0)
		overlay.draw_line(Vector2(9.2, ny - 4.0), Vector2(11.0, ny - 3.0), nc, 1.0)
	if cast_t > 0.0:
		overlay.draw_circle(Vector2(0, -22), 2.0 * cast_t / SWING_TIME + 0.5, Color(cast_color, 0.9))
	Status.draw_marks(overlay, self, -27.0)  # status shapes over the head (issue #112)
	if dash_t > 0.0:
		for k in 3:
			var back := -dash_dir * (6.0 + 6.0 * k)
			overlay.draw_line(back + Vector2(0, -10), back + Vector2(0, -2), Color(1, 1, 1, 0.5 - 0.15 * k), 2.0)
	Techs.draw(self, overlay)
	if controlled:
		var y := -21.0 + sin(anim_t * 4.0) * 1.0
		overlay.draw_colored_polygon(PackedVector2Array([Vector2(-2.5, y - 3), Vector2(2.5, y - 3), Vector2(0, y)]), Color("ffd166"))
	if swing_t > 0.0:
		_draw_trail(1.0 - swing_t / SWING_TIME)


## The weapon trail: a fading sweep (or a jab) in the hero's colour, gold on a full-power swing.
func _draw_trail(t: float) -> void:
	var full := swing_power >= 1.0
	var col := Color("ffe08a") if full else trail_color
	var fade := 1.0 - maxf(t - 0.6, 0.0) / 0.4  # the tail fades over the last part of the swing
	var c0 := Vector2(0, -8)
	if trail_thrust:
		var tip := c0 + facing * lerpf(8.0, reach, minf(t * 1.6, 1.0))
		var back := c0 + facing * 6.0
		overlay.draw_line(back, tip, Color(col, 0.35 * fade), 4.0)
		overlay.draw_line(back.lerp(tip, 0.4), tip, Color(col, 0.8 * fade), 1.5)
		overlay.draw_circle(tip, 1.5 if full else 1.0, Color(col.lightened(0.4), fade))
		return
	var a0 := facing.angle() - arc
	var head := a0 + 2.0 * arc * minf(t * 1.25, 1.0)
	var tail := maxf(a0, head - arc * 1.2)
	var r := reach - 4.0
	# Three strokes: a wide soft band, the main line and a bright edge.
	overlay.draw_arc(c0, r - 2.0, tail, head, 14, Color(col, 0.22 * fade), 5.0)
	overlay.draw_arc(c0, r, tail, head, 14, Color(col, 0.65 * fade), 1.5)
	overlay.draw_arc(c0, r + 1.0, lerpf(tail, head, 0.5), head, 8, Color(col.lightened(0.5), 0.9 * fade), 1.0)
