class_name Abilities
extends RefCounted
## Hotkeyed abilities and Ink (issue #7). Data lives in data/abilities.json; heroes list theirs
## in data/heroes.json. A Hero keeps its own Ink and cooldowns; this file holds what each kind does
## and when the ally AI reaches for one. Using an ability never pauses the fight.

const PATH := "res://data/abilities.json"
const MAX_SLOTS := 4
const REGEN := 0.4  # Ink per second, everyone
const HIT_GAIN := 1.0  # Ink for a full-power swing that lands
const AI_THINK := 0.3  # seconds between an ally's ability checks

static var _data := {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file())
			if parsed is Dictionary:
				_data = parsed
	return _data


static func data() -> Dictionary:
	return _load()


static func get_def(id: String) -> Dictionary:
	var d: Dictionary = _load().get("abilities", {}).get(id, {})
	if d.is_empty():
		return {}
	var out := d.duplicate(true)
	out["id"] = id
	return out


## The ability dictionaries a hero brings, from its list of ids (unknown ids are skipped).
## With hero_id, each one is on the tier that hero's skill in its Ink colour has reached (issue #24).
static func for_ids(ids: Array, hero_id := "") -> Array:
	var out := []
	for id in ids:
		var d := get_def(str(id))
		if not d.is_empty() and out.size() < MAX_SLOTS:
			out.append(SkillTree.mod_ability(hero_id, at_level(d, Skills.ink_level(hero_id, str(d.get("ink", ""))))) if hero_id != "" else d)  # + skill tree (#25)
	return out


## The ability as it is at this Ink colour level: tier values from level 2 and 4, shorter cooldowns
## from 3 and 5. "tier" (1-3) and "ink_level" are written in for menus.
static func at_level(base: Dictionary, lvl: int) -> Dictionary:
	var a := base.duplicate(true)
	var tiers: Dictionary = base.get("tiers", {})
	var tier := 1
	for need in [2, 4]:
		if lvl >= need and tiers.has(str(need)):
			var t: Dictionary = tiers[str(need)]
			for k in t:
				a[k] = t[k]
			tier += 1
	a["tier"] = tier
	a["ink_level"] = lvl
	a["cooldown"] = snappedf(float(base.get("cooldown", 1.0)) * (1.0 - Skills.cooldown_cut(lvl)), 0.1)
	return a


## The ability's description with its current numbers filled in (descs are templates, data/abilities.json).
static func desc_of(a: Dictionary) -> String:
	var v := {}
	for k in a:
		var x = a[k]
		if typeof(x) == TYPE_FLOAT and is_equal_approx(x, roundf(x)):
			x = int(x)
		v[k] = x
	v["guard_pct"] = int(round(float(a.get("guard", 0)) * 100.0))
	v["heal_pct"] = int(round(float(a.get("heal_ratio", 0)) * 100.0))
	v["mult_pct"] = int(round((float(a.get("mult", 1)) - 1.0) * 100.0))
	v["stun_text"] = (Loc.t(" Stuns for %s s.") % _num(a["stun"])) if float(a.get("stun", 0)) > 0.0 else ""
	v["shield_text"] = (Loc.t(" Adds a %d-point shield for %s s.") % [int(a["shield"]), _num(a.get("shield_time", 5))]) if int(a.get("shield", 0)) > 0 else ""
	v["pierce_text"] = Loc.t(" They go straight through.") if bool(a.get("pierce", false)) else ""
	return str(a.get("desc", "")).format(v) + tree_text(a)


## What skill tree nodes (issue #25) added that the ability's own description doesn't cover.
static func tree_text(a: Dictionary) -> String:
	var parts := []
	var kind := str(a.get("kind", ""))
	if float(a.get("poison", 0)) > 0.0:
		parts.append(Loc.t("Poisons what it hits for %s a second.") % _num(a["poison"]))
	if float(a.get("leech", 0)) > 0.0:
		parts.append(Loc.t("Heals the user for %d%% of the damage.") % int(round(float(a["leech"]) * 100.0)))
	if float(a.get("mark", 0)) > 0.0:
		parts.append(Loc.t("Marks what it hits: +%d%% damage taken for %s s.") % [int(round((float(a.get("mark_mult", 1.25)) - 1.0) * 100.0)), _num(a["mark"])])
	if float(a.get("taunt", 0)) > 0.0:
		parts.append(Loc.t("Everything hit goes for the user for %s s.") % _num(a["taunt"]))
	if int(a.get("ink_gift", 0)) > 0:
		parts.append(Loc.t("Gives everyone healed %d Ink.") % int(a["ink_gift"]))
	if float(a.get("poison_area", 0)) > 0.0:
		parts.append(Loc.t("Poisons every enemy in reach for %s a second.") % _num(a["poison_area"]))
	if int(a.get("self_shield", 0)) > 0:
		parts.append(Loc.t("Shields the user for %d.") % int(a["self_shield"]))
	if kind == "vanish" and int(a.get("heal", 0)) > 0:
		parts.append(Loc.t("Heals her %d.") % int(a["heal"]))
	if float(a.get("ink_ratio", 0)) > 0.0:
		parts.append(Loc.t("Allies also get %d%% of it as Ink.") % int(round(float(a["ink_ratio"]) * 100.0)))
	if kind == "mark" and int(a.get("damage", 0)) > 0:
		parts.append(Loc.t("Hits each of them for %d.") % int(a["damage"]))
	if kind == "mark" and float(a.get("stun", 0)) > 0.0:
		parts.append(Loc.t("Stuns them for %s s.") % _num(a["stun"]))
	if kind == "parry" and bool(a.get("aoe", false)):
		parts.append(Loc.t("The answer hits every enemy in reach."))
	return "" if parts.is_empty() else " " + " ".join(parts)


static func _num(x) -> String:
	var f := float(x)
	return str(int(f)) if is_equal_approx(f, roundf(f)) else str(snappedf(f, 0.1))


## What the next tier adds, for menus: "at Red 2: damage 22, reach 36" ("" at the top).
static func next_tier_text(a: Dictionary) -> String:
	var lvl := int(a.get("ink_level", 1))
	var tiers: Dictionary = a.get("tiers", {})
	for need in [2, 4]:
		if lvl < need and tiers.has(str(need)):
			var parts := []
			for k in tiers[str(need)]:
				var x = tiers[str(need)][k]
				parts.append(k.replace("_", " ") if typeof(x) == TYPE_BOOL else "%s %s" % [k.replace("_", " "), _num(x)])
			return Loc.t("at %s %d: %s") % [Skills.ink_name(str(a.get("ink", ""))), need, ", ".join(parts)]
	return ""


static func color_of(a: Dictionary) -> Color:
	return Color(str(a.get("color", "9fd8ff")))


## Why an ability can't be used right now ("" = it can).
static func blocker(h: Hero, i: int) -> String:
	if i < 0 or i >= h.abilities.size():
		return "none"
	if h.dead:
		return "down"
	if Status.has(h, "erase") or Status.has(h, "stun"):
		return "erased" if Status.has(h, "erase") else "stunned"  # issue #112
	if h.cooldowns[i] > 0.0:
		return "cooldown"
	if h.ink < float(h.abilities[i].get("cost", 0)):
		return "ink"
	if h.dash_t > 0.0 or h.swing_t > 0.0:
		return "busy"
	return ""


## Spend the Ink and do the thing. Returns false (and does nothing) if it can't be used.
static func use(h: Hero, i: int) -> bool:
	if blocker(h, i) != "":
		return false
	var a: Dictionary = h.abilities[i]
	h.ink -= float(a.get("cost", 0))
	h.gain_skill("ink", str(a.get("ink", "")), int(a.get("cost", 0)))  # spending a colour trains it (issue #24)
	h.cooldowns[i] = float(a.get("cooldown", 1.0))
	h.cast_t = Hero.SWING_TIME
	h.cast_color = color_of(a)
	Audio.sfx("cast", 0.9 + 0.2 * float(i))
	var parent := h.get_parent()
	match str(a.get("kind", "")):
		"heal":
			_heal(h, a, parent)
		"arc":
			_arc(h, a, parent)
		"dash":
			h.start_dash(a)
		"taunt":
			_taunt(h, a, parent)
		"bolt":
			_bolt(h, a, parent)
		"vanish":
			_vanish(h, a, parent)
		"drain":
			_drain(h, a, parent)
		"mark":
			_mark(h, a, parent)
		"parry":
			h.parry_t = float(a.get("time", 0.8))
			h.parry_ability = a
	Fx.damage_number(parent, h.global_position + Vector2(0, -26), str(a.get("name", "")), color_of(a))
	return true


static func _heal(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 56))
	var col := color_of(a)
	Fx.ring(parent, h.global_position, r, col)
	for o in h.get_tree().get_nodes_in_group("heroes"):
		var other := o as Hero
		if other == null or other.dead or other.global_position.distance_to(h.global_position) > r:
			continue
		if other.party != h.party:
			continue  # hub townsfolk are Heroes too
		var amount := mini(TreePerks.heal_amount(h, int(a.get("heal", 0))), other.max_hp - other.hp)
		other.hp += amount
		if amount > 0:
			Fx.damage_number(parent, other.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
		if int(a.get("shield", 0)) > 0:
			other.shield_hp = int(round(float(a["shield"])))
			other.shield_t = float(a.get("shield_time", 5.0))
		if int(a.get("ink_gift", 0)) > 0 and other.max_ink > 0.0:  # skill tree riders (issue #25)
			other.ink = minf(other.ink + float(a["ink_gift"]), other.max_ink)
			if other != h:
				Fx.damage_number(parent, other.global_position + Vector2(0, -26), Loc.t("+%d Ink") % int(a["ink_gift"]), Color("6aa8ff"))
		Fx.burst(parent, other.global_position + Vector2(0, -10), [col, Color.WHITE], 10, 40.0)
	if float(a.get("poison_area", 0)) > 0.0:
		for e in h.get_tree().get_nodes_in_group("enemies"):
			var enemy := e as Enemy
			if enemy and not enemy.dead and enemy.global_position.distance_to(h.global_position) <= r:
				TreePerks.poison(enemy, float(a["poison_area"]), TreePerks.POISON_TIME, h)
	if TreePerks.p(h, "heal_bill") > 0.0:
		TreePerks.pay(h, int(TreePerks.p(h, "heal_bill")), h.global_position)


static func _arc(h: Hero, a: Dictionary, parent: Node) -> void:
	var reach := float(a.get("reach", 30))
	var half := deg_to_rad(float(a.get("arc", 90)))
	var dmg := int(a.get("damage", 10))
	var col := color_of(a)
	Fx.sweep(parent, h.global_position + Vector2(0, -6), h.facing.angle(), half, reach, col)
	var hit_any := false
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var to := enemy.global_position - h.global_position
		if to.length() <= reach + enemy.radius and absf(h.facing.angle_to(to)) <= half:
			if TreePerks.strike(h, enemy, dmg, h.global_position, float(a.get("knock", 220)), a):
				hit_any = true
				enemy.stun(float(a.get("stun", 0)))
	if hit_any and h.party:
		h.party.shake(4.0 if a.has("stun") else 3.0)
		Rumble.landed(h, 1.0)  # issue #149


static func _taunt(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 100))
	var t := float(a.get("time", 4))
	Fx.ring(parent, h.global_position, r, color_of(a))
	h.guard_t = t
	h.guard_cut = float(a.get("guard", 0.5))
	if int(a.get("self_shield", 0)) > 0:  # skill tree (issue #25)
		h.shield_hp = maxi(h.shield_hp, int(a["self_shield"]))
		h.shield_t = maxf(h.shield_t, t)
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		if enemy.global_position.distance_to(h.global_position) <= r:
			enemy.taunt(h, t)


## A fan of thrown blades: count of them, spread degrees apart, centred on facing.
static func _bolt(h: Hero, a: Dictionary, parent: Node) -> void:
	var n := int(a.get("count", 1))
	var spread := deg_to_rad(float(a.get("spread", 12)))
	var col := color_of(a)
	for k in n:
		var b := ThrownKnife.new()
		b.dir = h.facing.normalized().rotated((k - (n - 1) / 2.0) * spread)
		b.speed = float(a.get("speed", 240))
		b.damage = int(a.get("damage", 8))
		b.knock = float(a.get("knock", 120))
		b.range_left = float(a.get("range", 150))
		b.pierce = bool(a.get("pierce", false))
		b.color = col
		b.hero = h  # skill tree perks and riders ride on the knife (issue #25)
		b.ability = a
		parent.add_child(b)
		b.global_position = h.global_position + Vector2(0, -8) + b.dir * 6.0


## Lamps Out: out of sight for time s. Enemies within radius forget the hero (bosses don't), she runs
## faster, and her next swing that lands hits crit times harder.
static func _vanish(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 120))
	Fx.burst(parent, h.global_position + Vector2(0, -8), [Color("2a2438"), Color("4a4060"), color_of(a)], 22, 60.0)
	h.vanish(float(a.get("time", 3.0)), float(a.get("speed", 1.3)), float(a.get("crit", 1.0)))
	if int(a.get("heal", 0)) > 0:  # skill tree (issue #25)
		TreePerks._heal_self(h, int(a["heal"]))
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or enemy.boss:
			continue
		if enemy.global_position.distance_to(h.global_position) <= r and enemy.target == h:
			enemy.target = null
			if enemy.taunter == h:
				enemy.taunt_t = 0.0


## Levy: damage every enemy in radius, then share heal_ratio of what was taken among the party nearby
## (each ally up to heal_cap).
static func _drain(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 64))
	var col := color_of(a)
	Fx.ring(parent, h.global_position, r, col)
	var taken := 0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or enemy.global_position.distance_to(h.global_position) > r:
			continue
		var before := enemy.hp
		if TreePerks.strike(h, enemy, int(a.get("damage", 8)), h.global_position, float(a.get("knock", 60)), a):
			taken += before - enemy.hp
			_coin_trail(parent, enemy.global_position, h.global_position, col)
	if taken <= 0:
		return
	var pool := TreePerks.heal_amount(h, int(round(taken * float(a.get("heal_ratio", 0.5)))))
	var cap := TreePerks.heal_amount(h, int(a.get("heal_cap", 12)))
	var ink_back := float(taken) * float(a.get("ink_ratio", 0.0))  # skill tree (issue #25)
	for o in h.get_tree().get_nodes_in_group("heroes"):
		var other := o as Hero
		if other == null or other.dead or other.party != h.party:
			continue
		if other.global_position.distance_to(h.global_position) > float(a.get("heal_radius", 90)):
			continue
		var amount := mini(mini(pool, cap), other.max_hp - other.hp)
		if amount > 0:
			other.hp += amount
			Fx.damage_number(parent, other.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
		if ink_back >= 1.0 and other.max_ink > 0.0:
			other.ink = minf(other.ink + ink_back, other.max_ink)
			Fx.damage_number(parent, other.global_position + Vector2(0, -26), Loc.t("+%d Ink") % int(ink_back), Color("6aa8ff"))


static func _coin_trail(parent: Node, from: Vector2, to: Vector2, col: Color) -> void:
	for k in 3:
		Fx.burst(parent, from.lerp(to, k / 3.0) + Vector2(0, -8), [col, Color("fff1b8")], 3, 20.0)


## Audit: every enemy in radius takes mult times damage from everything for time s.
static func _mark(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 80))
	Fx.ring(parent, h.global_position, r, color_of(a))
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(h.global_position) <= r:
			enemy.mark(float(a.get("time", 6)), float(a.get("mult", 1.5)))
			Fx.burst(parent, enemy.global_position + Vector2(0, -12), [color_of(a)], 4, 25.0)
			if int(a.get("damage", 0)) > 0:  # skill tree riders (issue #25)
				TreePerks.strike(h, enemy, int(a["damage"]), h.global_position, 40.0, {})
			if float(a.get("stun", 0)) > 0.0 and not enemy.dead:
				enemy.stun(float(a["stun"]))


## Riposte: the hit that just came in from `from` is turned aside, and whoever threw it (the nearest
## enemy to that point, within reach) takes damage and is stunned. One parry, one answer.
static func riposte(h: Hero, from: Vector2) -> void:
	var a := h.parry_ability
	var parent := h.get_parent()
	h.parry_t = 0.0
	h.invuln_t = maxf(h.invuln_t, 0.4)
	Fx.burst(parent, h.global_position + Vector2(0, -10), [color_of(a), Color.WHITE], 14, 70.0)
	Fx.damage_number(parent, h.global_position + Vector2(0, -30), Loc.t("Riposte!"), color_of(a).lightened(0.3))
	var best: Enemy = null
	var best_d := float(a.get("reach", 60))
	var others := []  # Bind and Answer (skill tree, issue #25): every enemy within reach is answered
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		if bool(a.get("aoe", false)) and enemy.global_position.distance_to(h.global_position) <= float(a.get("reach", 60)):
			others.append(enemy)
		var d := enemy.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = enemy
	if best == null and others.is_empty():
		return
	if best == null:
		best = others[0]
	others.erase(best)
	h.facing = (best.global_position - h.global_position).normalized()
	Fx.sweep(parent, h.global_position + Vector2(0, -6), h.facing.angle(), deg_to_rad(12), h.global_position.distance_to(best.global_position) + 6.0, color_of(a))
	for o in others:
		var to: Vector2 = (o as Enemy).global_position - h.global_position
		Fx.sweep(parent, h.global_position + Vector2(0, -6), to.angle(), deg_to_rad(10), to.length() + 6.0, color_of(a))
		if TreePerks.strike(h, o, int(a.get("damage", 20)), h.global_position, float(a.get("knock", 220)), a):
			o.stun(float(a.get("stun", 1.0)))
	if TreePerks.strike(h, best, int(a.get("damage", 20)), h.global_position, float(a.get("knock", 220)), a):
		best.stun(float(a.get("stun", 1.0)))
	h.ink = minf(h.ink + float(a.get("refund", 0)), h.max_ink)
	if h.party:
		h.party.shake(3.0)
	Rumble.landed(h, 1.0)  # issue #149


## Enemies a dash runs through (each one once per dash).
static func dash_hits(h: Hero) -> void:
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or h.dash_hit.has(enemy):
			continue
		if enemy.global_position.distance_to(h.global_position) <= h.radius + enemy.radius + 8.0:
			h.dash_hit.append(enemy)
			if TreePerks.strike(h, enemy, int(h.dash_ability.get("damage", 10)), h.global_position - h.dash_dir * 6.0,
					float(h.dash_ability.get("knock", 180)), h.dash_ability):
				enemy.stun(float(h.dash_ability.get("stun", 0)))
			if h.party:
				h.party.shake(2.0)
			Rumble.landed(h, 0.6)


# ---------------------------------------------------------------- ally AI

## Which ability an AI-driven ally wants to use right now, or -1.
static func ai_pick(h: Hero) -> int:
	var leader: Hero = h.party.leader if h.party else null
	for i in h.abilities.size():
		if blocker(h, i) != "":
			continue
		var rule: Dictionary = h.abilities[i].get("ai", {})
		match str(rule.get("when", "")):
			"hurt":
				var r := float(h.abilities[i].get("radius", 60))
				for o in h.get_tree().get_nodes_in_group("heroes"):
					var other := o as Hero
					if other and not other.dead and other.party == h.party \
							and other.global_position.distance_to(h.global_position) <= r \
							and float(other.hp) / other.max_hp < float(rule.get("below", 0.5)):
						return i
			"crowd":
				if _count_near(h, h.global_position, float(rule.get("range", 32))) >= int(rule.get("count", 2)):
					return i
			"target":
				var tgt: Enemy = h.ai_target
				if tgt and is_instance_valid(tgt) and not tgt.dead:
					var d := tgt.global_position.distance_to(h.global_position)
					if d <= float(rule.get("range", 60)) and d > 20.0:
						h.facing = (tgt.global_position - h.global_position).normalized()
						return i
			"windup":
				for e in h.get_tree().get_nodes_in_group("enemies"):
					var enemy := e as Enemy
					if enemy and not enemy.dead and enemy.target == h and enemy.state == Enemy.State.WINDUP \
							and enemy.global_position.distance_to(h.global_position) <= float(rule.get("range", 40)):
						return i
			"self_hurt":
				if float(h.hp) / h.max_hp < float(rule.get("below", 0.5)) and _count_near(h, h.global_position, float(rule.get("range", 40))) >= 1:
					return i
			"threat":
				if leader and _count_near(h, leader.global_position, float(rule.get("range", 60))) >= int(rule.get("count", 2)):
					return i
	return -1


static func _count_near(h: Hero, at: Vector2, r: float) -> int:
	var n := 0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(at) <= r:
			n += 1
	return n
