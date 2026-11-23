class_name Techs
extends RefCounted
## Charged techs (issues #8, #24). Every field hero has five (data/techs.json), one per weapon skill level
## (scripts/skills.gd). With a full power gauge, hold Attack: after TAP seconds the hero starts to glow,
## after stage_hold[0] seconds the first tech is ready (flash + chime), and if the hero knows more, holding
## on reaches the next one at each later stage_hold (a brighter flash and a higher chime each time).
## Releasing fires the last one reached; letting go before the first is an ordinary full-power swing.
## A tech picked in the quick menu's Techs tab charges on its own instead (ready at its own stage time).
##
## A Hero keeps the state (charging, charge_t, charge_stage, charge_ready); this file holds the rules,
## the blasts, the glow, the ground preview of where it will land and the synthesized sounds (each tech
## has its own, built from the numbers in its "sound"). The look of each blast is scripts/tech_fx.gd;
## blasts that go off later (several hits, a chain marching forward, a delay) are run and marked on the
## ground by scripts/tech_run.gd. Allies under AI charge and fire the same techs: scripts/ally_techs.gd.

const PATH := "res://data/techs.json"
const TAP := 0.16  # held shorter than this: no glow at all, just a swing on release
const CHARGE_SPEED := 0.55  # movement multiplier while charging
const HIT_INK := 2.0  # Ink for a tech that lands (a full-power swing gives Abilities.HIT_GAIN)
const STEP_SAFE := 30.0  # a lunge at least this long can't be hit while it travels

static var _data := {}
static var _by_id := {}
static var _sounds := {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file())
			if parsed is Dictionary:
				_data = parsed
		_by_id = {}
		var all: Dictionary = _data.get("techs", {})
		for hero in all:
			var list = all[hero]
			if typeof(list) != TYPE_ARRAY:
				continue
			for i in list.size():
				var t: Dictionary = list[i].duplicate(true)
				t["level"] = i + 1
				t["hero"] = hero
				_by_id[str(t.get("id", ""))] = t
	return _data


## Seconds of holding before the tech learned at this weapon level is ready.
static func stage_time(level: int) -> float:
	var st: Array = _load().get("stage_hold", [1.0])
	if st.is_empty():
		return 1.0
	return float(st[clampi(level - 1, 0, st.size() - 1)])


## Hold time of the first tech (the original single-tech rule).
static func hold_time() -> float:
	return stage_time(1)


## How long this tech takes to charge.
static func charge_time(t: Dictionary) -> float:
	return stage_time(int(t.get("level", 1)))


## Every tech this hero has, in level order ([] if none).
static func list(id: String) -> Array:
	_load()
	var out := []
	for t in _data.get("techs", {}).get(id, []):
		var full: Dictionary = _by_id.get(str(t.get("id", "")), {})
		if not full.is_empty():
			out.append(full.duplicate(true))
	return out


## The hero's first tech (level 1), or {} if none.
static func for_hero(id: String) -> Dictionary:
	var l := list(id)
	return l[0] if not l.is_empty() else {}


## A tech by its id, or {}.
static func find(tech_id: String) -> Dictionary:
	_load()
	var t: Dictionary = _by_id.get(tech_id, {})
	return t.duplicate(true) if not t.is_empty() else {}


## The techs this hero can charge right now: the picked one, or every one it knows.
static func charge_options(h: Hero) -> Array:
	if Status.has(h, "erase"):
		return []  # Erased: no techs until it wears off (issue #112)
	var p := Skills.picked_tech(h.hero_id)
	return [p] if not p.is_empty() else Skills.known_techs(h.hero_id)


## The tech the hero's charge is on right now (the AI's choice, the pick, or the stage reached),
## or the first it would reach. {} if it has none.
static func current(h: Hero) -> Dictionary:
	if h.ai_charging and not h.ai_tech.is_empty():
		return h.ai_tech
	var opts := charge_options(h)
	if opts.is_empty():
		return {}
	return opts[clampi(h.charge_stage - 1, 0, opts.size() - 1)]


static func color_of(h: Hero) -> Color:
	return Color(str(current(h).get("color", "ffe08a")))


## The time the charge must reach for its top tech (the AI's or the pick: that one; by hold: the last known).
static func _goal_time(h: Hero) -> float:
	if h.ai_charging and not h.ai_tech.is_empty():
		return charge_time(h.ai_tech)
	var opts := charge_options(h)
	return charge_time(opts.back()) if not opts.is_empty() else hold_time()


## 0..1 progress of the glow towards the next tech (0 until TAP has passed, so a tap never flashes).
static func charge_ratio(h: Hero) -> float:
	if not h.charging:
		return 0.0
	var from := TAP
	var to := charge_time(current(h)) if not h.charge_ready else _next_time(h)
	if h.charge_ready:
		from = charge_time(current(h))
		if to <= from:
			return 1.0
	return clampf((h.charge_t - from) / maxf(to - from, 0.01), 0.0, 1.0)


## Stage time of the next tech a held charge would reach (the current one's if there is none).
static func _next_time(h: Hero) -> float:
	if h.ai_charging:
		return charge_time(current(h))
	var opts := charge_options(h)
	if h.charge_stage < opts.size():
		return charge_time(opts[h.charge_stage])
	return charge_time(current(h))


## For the HUD: [stage fraction of the bar, tech] for every tech this charge can reach, and the fill.
static func stages(h: Hero) -> Array:
	var opts: Array = [h.ai_tech] if h.ai_charging and not h.ai_tech.is_empty() else charge_options(h)
	var top := _goal_time(h)
	var out := []
	for t in opts:
		out.append([clampf(charge_time(t) / top, 0.0, 1.0), t])
	return out


static func fill(h: Hero) -> float:
	return clampf(h.charge_t / maxf(_goal_time(h), 0.01), 0.0, 1.0)


## Called every frame for the controlled hero while it can fight (not in town, quick menu closed).
## Replaces the old "attack pressed -> swing" so a full gauge waits for the release.
## Accessibility (issue #34): in Toggle mode the press that starts a charge latches it and the next press
## fires (or swings, if no tech was reached yet); with Hold to attack on, keeping Attack held swings again
## each time the gauge fills.
static func control(h: Hero, delta: float) -> void:
	if h.charging:
		var held := Input.is_action_pressed("attack")
		if Access.toggle_techs():
			held = not Input.is_action_just_pressed("attack")
		if held:
			h.charge_t += delta / float(Armory.perk(h.hero_id, "tech_charge", 1.0))  # Clockwork Heart (issue #112)
			_advance(h)
			return
		# Released.
		var ready := h.charge_ready
		var t := current(h)
		cancel(h)
		if ready:
			fire(h, t)
		else:
			h.try_attack()
		return
	if Input.is_action_just_pressed("attack"):
		if h.power >= 1.0 and h.swing_t <= 0.0 and not charge_options(h).is_empty():
			h.charging = true
			h.charge_t = 0.0
			h.charge_stage = 0
			h.charge_ready = false
		else:
			h.try_attack()
	elif Access.hold_attack and Input.is_action_pressed("attack") and h.power >= 1.0 and h.swing_t <= 0.0:
		h.try_attack()


## The HUD's one-line reminder of how techs are charged with the current option.
## `on` picks the device whose button names to show (Prompts.KEYS / PAD); empty follows the last one used.
static func how_to(on := "") -> String:
	if Access.toggle_techs():
		return Loc.t("Attack: %s, press when full: tech, press again: fire") % Prompts.key("attack", on)
	return Loc.t("Attack: %s, hold when full: tech") % Prompts.key("attack", on)


## Moves a player's charge on to every tech its hold time has reached.
static func _advance(h: Hero) -> void:
	var opts := charge_options(h)
	var n := 0
	for t in opts:
		if h.charge_t >= charge_time(t):
			n += 1
	if n > h.charge_stage:
		h.charge_stage = n
		h.charge_ready = true
		reached(h, n)


## The flash and chime when a charge reaches a tech (stage 1, 2, ...: each one brighter and higher).
static func reached(h: Hero, stage: int) -> void:
	var col := color_of(h)
	Fx.burst(h.get_parent(), h.global_position + Vector2(0, -10), [col, col.lightened(0.4), Color.WHITE], (14 + 4 * stage) if not Access.reduce_flashing else 8, 50.0 + 10.0 * stage)
	if stage > 1:
		Fx.damage_number(h.get_parent(), h.global_position + Vector2(0, -30), str(current(h).get("name", "")), col.lightened(0.3))
	play(h, "ready_%d" % clampi(stage, 1, 5))


## Every frame (from Hero._update_abilities): drops a charge the hero can no longer hold.
## A player's charge ends when control moves away or the quick menu opens; an ally's (AllyTechs)
## ends when the player takes control of that hero, so a hand-over never fires by itself.
static func tick(h: Hero) -> void:
	if not h.charging:
		return
	if h.dead or h.peaceful or h.dash_t > 0.0 or h.cast_t > 0.0 or h.controlled == h.ai_charging:
		cancel(h)
		return
	var menu_open: bool = h.party != null and h.party.get("quick_open") == true
	if menu_open and not h.ai_charging:
		cancel(h)


static func cancel(h: Hero) -> void:
	h.charging = false
	h.ai_charging = false
	h.ai_tech = {}
	h.charge_t = 0.0
	h.charge_stage = 0
	h.charge_ready = false


# ---------------------------------------------------------------- the blasts

## Every blast a tech makes, fired along dir by a hero standing at origin (after its lunge):
## [{"at": centre, "dir", "reach", "half" (radians), "time" (s after release), "p": the tech's numbers
## for that blast (the last of several hits takes "last" on top)}]. Knife-only techs have none.
static func blasts(t: Dictionary, origin: Vector2, dir: Vector2) -> Array:
	var out := []
	if float(t.get("mult", 0)) <= 0.0:
		return out
	var dirs := []
	var spread: Array = t.get("spread", [])
	if spread.is_empty():
		dirs.append(dir)
	else:
		for a in spread:
			dirs.append(dir.rotated(deg_to_rad(float(a))))
	var hits := maxi(1, int(t.get("hits", 1)))
	var chain := maxi(1, int(t.get("chain", 1)))
	var last: Dictionary = t.get("last", {})
	for d in dirs:
		for c in chain:
			for k in hits:
				var p := t
				if k == hits - 1 and hits > 1 and not last.is_empty():
					p = t.duplicate()
					for key in last:
						p[key] = last[key]
				out.append({
					"at": origin + d * (float(p.get("offset", 0)) + c * float(t.get("chain_gap", 0))),
					"dir": d,
					"reach": float(p.get("reach", 30)),
					"half": deg_to_rad(float(p.get("arc", 90))),
					"time": float(t.get("delay", 0)) + c * float(t.get("chain_delay", 0)) + k * float(t.get("every", 0)),
					"p": p,
				})
	return out


## Whether an enemy at `pos` (radius r) is inside one blast.
static func inside(b: Dictionary, pos: Vector2, r: float) -> bool:
	var to: Vector2 = pos - b["at"]
	if to.length() > float(b["reach"]) + r:
		return false
	if float(b["half"]) < PI - 0.01 and to.length() > 4.0 and absf((b["dir"] as Vector2).angle_to(to)) > float(b["half"]):
		return false
	return true


## Releases a tech. t: which one (from current()); empty = the hero's current one.
static func fire(h: Hero, t: Dictionary = {}) -> void:
	if t.is_empty():
		t = current(h)
	if t.is_empty() or h.dead:
		return
	var parent := h.get_parent()
	var col := Color(str(t.get("color", "ffe08a")))
	var dir := h.facing.normalized()
	var step := float(t.get("step", 0))
	if step > 0.0:
		if step >= STEP_SAFE:
			h.invuln_t = maxf(h.invuln_t, 0.3)  # a long lunge goes through the crowd untouched
			Fx.burst(parent, h.global_position + Vector2(0, -6), [col, Color(col, 0.5)], 10, 30.0)
		h.move_and_collide(dir * step)

	# Spend the gauge and play the swing pose; the normal swing hit is skipped.
	h.power = 0.0
	h.swing_t = Hero.SWING_TIME
	h.swing_power = 1.0
	h.swing_hit_done = true
	h.tech_flash_t = 0.35
	h.tech_flash_color = col
	Fx.damage_number(parent, h.global_position + Vector2(0, -36), str(t.get("name", "")), col.lightened(0.3))
	play(h, "arm" if float(t.get("delay", 0)) > 0.0 else str(t.get("id", "fire")), t)

	# What the hero does to itself: guard, vanishing, Ink for the party.
	if float(t.get("guard", 0)) > 0.0:
		h.guard_t = float(t.get("guard_time", 3))
		h.guard_cut = float(t["guard"])
	if float(t.get("vanish", 0)) > 0.0:
		h.vanish(float(t["vanish"]), 1.3, float(t.get("crit", 1.0)))
	if int(t.get("ink", 0)) > 0:
		for other in _allies(h, h.global_position, 120.0):
			other.ink = minf(other.ink + float(t["ink"]), other.max_ink)
			Fx.damage_number(parent, other.global_position + Vector2(0, -24), Loc.t("+%d Ink") % int(t["ink"]), Color("6aa8ff"))
	var knives: Dictionary = t.get("knives", {})
	if not knives.is_empty():
		_throw(h, t, knives, dir)

	var state := {"credited": false}
	var later := []
	for b in blasts(t, h.global_position, dir):
		if float(b["time"]) <= 0.0:
			pulse(h, t, b, state)
		else:
			later.append(b)
	if not later.is_empty():
		TechRun.start(parent, h, t, later, state)
	if not knives.is_empty() and blasts(t, h.global_position, dir).is_empty():
		credit(h, state)  # knives are their own reward: the throw counts as the tech landing
	if h.party:
		h.party.shake(2.5)


## One blast going off: its look, its damage and everything that rides on it. state is shared by all of
## one tech's blasts, so the reward for landing it (Ink, weapon skill) comes once.
static func pulse(h: Hero, t: Dictionary, b: Dictionary, state: Dictionary) -> void:
	if not is_instance_valid(h):
		return
	var parent := h.get_parent()
	if parent == null:
		return
	var p: Dictionary = b["p"]
	var col := Color(str(t.get("color", "ffe08a")))
	var center: Vector2 = b["at"]
	var dir: Vector2 = b["dir"]
	TechFx.spawn(parent, str(t.get("fx", "burst")), center, dir, float(b["reach"]), float(b["half"]), col, float(b["time"]) > 0.0)
	if float(b["time"]) > 0.0:
		play(h, str(t.get("id", "fire")) + ("" if float(t.get("delay", 0)) > 0.0 and int(t.get("hits", 1)) <= 1 else ":tick"), t)
	var dmg := maxi(1, roundi(h.base_damage * float(p.get("mult", 2.0))))
	var knock := float(p.get("knock", 260))
	var hit_any := false
	var dealt_total := 0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		if not inside(b, enemy.global_position, enemy.radius):
			continue
		var dealt := dmg
		if float(p.get("execute", 0)) > 0.0 and float(enemy.hp) <= enemy.max_hp * float(p["execute"]):
			dealt *= 2  # finishes off the wounded
			Fx.damage_number(parent, enemy.global_position + Vector2(0, -26), Loc.t("Finish!"), col.lightened(0.4))
		var before := enemy.hp
		# A pull (negative knock) drags towards the blast's centre; a push throws away from it.
		if TreePerks.strike(h, enemy, dealt, center - dir * 4.0, knock, {}, "tech"):  # + skill tree (#25)
			hit_any = true
			dealt_total += before - enemy.hp
			enemy.stun(float(p.get("stun", 0)))
			if float(p.get("mark", 0)) > 0.0:
				enemy.mark(float(p["mark"]), float(p.get("mark_mult", 1.5)))
			if float(p.get("taunt", 0)) > 0.0:
				enemy.taunt(h, float(p["taunt"]))
	if int(p.get("heal", 0)) > 0 or int(p.get("shield", 0)) > 0:
		for other in _allies(h, center, float(b["reach"]) + 8.0):
			var amount := mini(int(p.get("heal", 0)), other.max_hp - other.hp)
			if amount > 0:
				other.hp += amount
				Fx.damage_number(parent, other.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
			if int(p.get("shield", 0)) > 0:
				other.shield_hp = maxi(other.shield_hp, int(p["shield"]))
				other.shield_t = float(p.get("shield_time", 5.0))
	if float(p.get("leech", 0)) > 0.0 and dealt_total > 0:
		var pool := int(round(dealt_total * float(p["leech"])))
		for other in _allies(h, h.global_position, 90.0):
			var amount := mini(mini(pool, int(p.get("leech_cap", 12))), other.max_hp - other.hp)
			if amount > 0:
				other.hp += amount
				Fx.damage_number(parent, other.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
	if hit_any:
		credit(h, state)
		if h.party:
			h.party.shake(5.0)


## Landing a tech: Ink and weapon skill, once per tech however many blasts hit.
static func credit(h: Hero, state: Dictionary) -> void:
	if state.get("credited", false) or not is_instance_valid(h) or h.dead:
		return
	state["credited"] = true
	h.ink = minf(h.ink + HIT_INK, h.max_ink)
	h.gain_skill("weapon", "", Skills.tech_points())


static func _allies(h: Hero, at: Vector2, r: float) -> Array:
	var out := []
	for o in h.get_tree().get_nodes_in_group("heroes"):
		var other := o as Hero
		if other and not other.dead and other.party == h.party and other.global_position.distance_to(at) <= r:
			out.append(other)
	return out


static func _throw(h: Hero, t: Dictionary, k: Dictionary, dir: Vector2) -> void:
	var n := maxi(1, int(k.get("count", 1)))
	var span := deg_to_rad(float(k.get("arc", 30)))
	var full := span >= TAU - 0.01
	for i in n:
		var b := ThrownKnife.new()
		var a := (float(i) / n) * TAU if full else (i - (n - 1) / 2.0) * (span / maxf(n - 1, 1))
		b.dir = dir.rotated(a)
		b.speed = float(k.get("speed", 240))
		b.damage = maxi(1, roundi(h.base_damage * float(k.get("mult", 1.0))))
		b.knock = float(k.get("knock", 140))
		b.range_left = float(k.get("range", 120))
		b.pierce = bool(k.get("pierce", false))
		b.color = Color(str(t.get("color", "d8d2c4")))
		b.hero = h  # skill tree perks (issue #25)
		b.source = "tech"
		h.get_parent().add_child(b)
		b.global_position = h.global_position + Vector2(0, -8) + b.dir * 6.0


# ---------------------------------------------------------------- drawing

## Where the charging tech will land, drawn flat on the ground under the hero (c = the hero's own
## canvas, origin at its feet): every blast's ring or wedge in the tech colour, filling in as it charges
## and solid once ready. For allies it is the tell that says "stand clear, this is about to go off".
static func draw_area(h: Hero, c: Node2D) -> void:
	if not h.charging or h.charge_t < TAP:
		return
	var t := current(h)
	if t.is_empty() or h.facing.length() < 0.1:
		return
	var col := Color(str(t.get("color", "ffe08a")))
	var r := charge_ratio(h) if not h.charge_ready else 1.0
	var dir := h.facing.normalized()
	var a_line := 0.25 + 0.5 * r
	var a_fill := 0.06 + 0.1 * r
	if h.charge_ready:
		var pulse_a := 0.5 + 0.5 * sin(h.anim_t * 14.0)
		a_line = 0.75 + 0.2 * pulse_a
		a_fill = 0.16 + 0.06 * pulse_a
	var seen := {}
	for b in blasts(t, dir * float(t.get("step", 0)), dir):
		var key := "%d:%d:%d" % [roundi(b["at"].x), roundi(b["at"].y), roundi(b["reach"])]
		if seen.has(key):
			continue
		seen[key] = true
		draw_blast(c, b, col, a_line, a_fill, 0.35 + 0.65 * r)
	var k: Dictionary = t.get("knives", {})
	if not k.is_empty():  # knives: a spoke for each blade, out to its range
		var n := maxi(1, int(k.get("count", 1)))
		var span := deg_to_rad(float(k.get("arc", 30)))
		var full := span >= TAU - 0.01
		for i in n:
			var a := (float(i) / n) * TAU if full else (i - (n - 1) / 2.0) * (span / maxf(n - 1, 1))
			var d := dir.rotated(a)
			var far := float(k.get("range", 120)) * (0.35 + 0.65 * r)
			c.draw_line(d * 8.0, d * far, Color(col, a_line * 0.8), 1.0)
			c.draw_circle(d * far, 1.5, Color(col, a_line))


## One blast's area on canvas c: a disc for all-round blasts, a wedge otherwise. grow scales the fill.
static func draw_blast(c: CanvasItem, b: Dictionary, col: Color, a_line: float, a_fill: float, grow := 1.0) -> void:
	var center: Vector2 = b["at"]
	var reach: float = b["reach"]
	var half: float = b["half"]
	if half >= PI - 0.01:
		c.draw_circle(center, reach * grow, Color(col, a_fill))
		c.draw_arc(center, reach, 0, TAU, 40, Color(col, a_line), 1.0)
	else:
		var d: Vector2 = b["dir"]
		var a0 := d.angle() - half
		var a1 := d.angle() + half
		var n := clampi(int(rad_to_deg(half * 2.0) / 15.0), 1, 16)  # thin lines: few points, or the fan won't triangulate
		var pts := PackedVector2Array([center])
		for k in n + 1:
			pts.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / n)) * reach * grow)
		c.draw_colored_polygon(pts, Color(col, a_fill))
		var edge := PackedVector2Array([center])
		for k in n + 1:
			edge.append(center + Vector2.from_angle(lerpf(a0, a1, float(k) / n)) * reach)
		edge.append(center)
		c.draw_polyline(edge, Color(col, a_line), 1.0)


## The glow around a charging hero, drawn on its overlay (above the sprite). Each tech reached adds a
## ring, so a long hold reads at a glance.
static func draw(h: Hero, o: Node2D) -> void:
	if h.tech_flash_t > 0.0:
		var f := h.tech_flash_t / 0.35
		o.draw_circle(Vector2(0, -7), 14.0 * (1.2 - f * 0.4), Color(h.tech_flash_color, Access.calm(0.35 * f)))
	if not h.charging or h.charge_t < TAP:
		return
	var col := color_of(h)
	var r := charge_ratio(h)
	var stage := maxi(h.charge_stage, 1) if not h.ai_charging else 1
	if h.charge_ready:
		var pulse_a := Access.pulse(h.anim_t, 18.0)
		o.draw_circle(Vector2(0, -7), 11.0 + pulse_a * 2.0, Color(col, 0.22 + 0.12 * pulse_a))
		for s in stage:  # one ring per tech reached
			o.draw_arc(Vector2(0, -7), 13.0 + pulse_a * 1.5 + s * 2.5, 0, TAU, 28, Color(col.lightened(0.4), 0.95 - s * 0.12), 1.0 if s > 0 else 1.5)
		for k in 3 + stage:  # sparks orbiting the hero
			var a := h.anim_t * 7.0 + k * TAU / (3 + stage)
			o.draw_circle(Vector2(cos(a) * (12.0 + stage), -7 + sin(a) * 6.0), 1.2, Color.WHITE)
		if r < 1.0 and not h.ai_charging:
			# Filling towards the next tech it knows.
			var nxt := Color(str(charge_options(h)[mini(h.charge_stage, charge_options(h).size() - 1)].get("color", "ffffff")))
			o.draw_arc(Vector2(0, -7), 20.0, -PI / 2.0, -PI / 2.0 + TAU * r, 28, Color(nxt, 0.7), 1.0)
	else:
		# Ring closing in as it fills: big and faint at first, tight and bright when ready.
		var rad := lerpf(20.0, 12.0, r)
		o.draw_arc(Vector2(0, -7), rad, -PI / 2.0, -PI / 2.0 + TAU * r, 28, Color(col, 0.35 + 0.6 * r), 1.5)
		o.draw_circle(Vector2(0, -7), 9.0 * r, Color(col, 0.15 * r))


# ---------------------------------------------------------------- sound

## which: "ready_<n>" (a tech reached), "arm" (a delayed tech set down), a tech id (its own blast),
## "<tech id>:tick" (a later hit of the same tech, shorter and quieter). t: the tech, for its numbers.
static func play(h: Hero, which: String, t: Dictionary = {}) -> void:
	if not _sounds.has(which):
		_sounds[which] = _make(which, t)
	var p := AudioStreamPlayer.new()
	p.stream = _sounds[which]
	p.volume_db = -14.0 if which.ends_with(":tick") else -10.0
	p.bus = "SFX"  # no-tr: audio bus
	h.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _make(which: String, t: Dictionary) -> AudioStreamWAV:
	if which.begins_with("ready_"):
		return _chime(int(which.substr(6)))
	if which == "arm":
		return _synth({"tone": 1800, "sweep": -900, "noise": 0.9, "len": 0.18, "ring": 0.0, "thump": 0.0}, 3)
	var s: Dictionary = t.get("sound", {"tone": 180, "sweep": -300, "noise": 0.7, "len": 0.28, "ring": 0.0, "thump": 0.3})
	if which.ends_with(":tick"):
		s = s.duplicate()
		s["len"] = minf(float(s.get("len", 0.3)) * 0.6, 0.22)
	return _synth(s, hash(which) & 0xffff)


## A rising two-note chime; each later stage starts higher (a held charge climbs).
static func _chime(stage: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.32)
	var data := PackedByteArray()
	data.resize(n * 2)
	var base := 880.0 * pow(2.0, (stage - 1) * 3.0 / 12.0)
	for i in n:
		var t := float(i) / rate
		var freq := base if t < 0.09 else base * 1.4983
		var local := t if t < 0.09 else t - 0.09
		var s := sin(TAU * freq * t) * exp(-local * 14.0) * 0.6 + sin(TAU * freq * 2.0 * t) * exp(-local * 20.0) * 0.2
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data, rate)


## A blast built from a tech's numbers: a pitched body (tone, sweeping by `sweep` over the clip), filtered
## noise (noise), a bell overtone (ring) and a low boom (thump).
static func _synth(sd: Dictionary, seed_n: int) -> AudioStreamWAV:
	var rate := 22050
	var length := clampf(float(sd.get("len", 0.3)), 0.08, 1.0)
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var tone := float(sd.get("tone", 200))
	var sweep := float(sd.get("sweep", 0))
	var noise := clampf(float(sd.get("noise", 0.5)), 0.0, 1.0)
	var ring := clampf(float(sd.get("ring", 0.0)), 0.0, 1.0)
	var thump := clampf(float(sd.get("thump", 0.0)), 0.0, 1.0)
	var lp := 0.0
	var phase := 0.0
	var decay := 4.0 / length
	for i in n:
		var t := float(i) / rate
		var env := minf(t * 80.0, 1.0) * exp(-t * decay)
		var f := maxf(tone + sweep * (t / length), 30.0)
		phase += TAU * f / rate
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.12 + 0.5 * noise * (1.0 - t / length))
		var s := sin(phase) * (1.0 - noise * 0.6) * 0.45 * env
		s += lp * noise * 0.9 * env
		s += sin(phase * 2.76) * ring * 0.3 * exp(-t * decay * 0.5)
		s += sin(TAU * (70.0 - 30.0 * t / length) * t) * thump * 0.7 * exp(-t * 10.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
