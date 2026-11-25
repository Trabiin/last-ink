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
	v["boost_pct"] = int(round(float(a.get("boost", 0)) * 100.0))  # Chapter 3 kinds
	v["rate_pct"] = int(round(float(a.get("rate", 0)) * 100.0))
	v["weak_pct"] = int(round((1.0 - float(a.get("mult", 1))) * 100.0))
	v["slow_pct"] = int(round((1.0 - float(a.get("slow", 1))) * 100.0))
	v["erase_pct"] = int(round(float(a.get("erase", 0)) * 100.0))  # Chapter 4 (#30)
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
	if kind == "song" and int(a.get("heal", 0)) > 0:
		parts.append(Loc.t("Heals everyone it reaches %d.") % int(a["heal"]))
	if kind == "weaken" and int(a.get("damage", 0)) > 0:
		parts.append(Loc.t("Hits each of them for %d.") % int(a["damage"]))
	if kind == "blink" and float(a.get("vanish", 0)) > 0.0:
		parts.append(Loc.t("She stays out of sight for %s s after.") % _num(a["vanish"]))
	if kind == "shadow" and float(a.get("weaken_hits", 0)) > 0.0:
		parts.append(Loc.t("Every punch signs its target up to the Small Print for %s s.") % _num(a["weaken_hits"]))
	if kind == "unwrite" and int(a.get("pierce_heal", 0)) > 0:
		parts.append(Loc.t("Every enemy it unwrites heals her %d.") % int(a["pierce_heal"]))
	if kind == "conjure" and float(a.get("song", 0)) > 0.0:
		parts.append(Loc.t("When it bows out, the party nearby gets %s s of Torch Song.") % _num(a["song"]))
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
		"charm":
			_charm(h, a, parent)
		"blink":
			_blink(h, a, parent)
		"song":
			_song(h, a, parent)
		"conjure":
			_conjure(h, a, parent)
		"weaken":
			_weaken(h, a, parent)
		"shadow":
			_shadow(h, a, parent)
		"unwrite":
			_unwrite(h, a, parent)
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


# ---------------------------------------------------------------- Chapter 3 kinds (#29)

## Beguile (Hortense): a blown kiss down a cone. Every enemy in it (radius, arc degrees either side of facing) stops
## fighting for time s and takes mult times damage from her (Enemy.charm). Bosses only flinch.
static func _charm(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 70))
	var half := deg_to_rad(float(a.get("arc", 50)))
	var col := color_of(a)
	Fx.sweep(parent, h.global_position + Vector2(0, -8), h.facing.angle(), half, r, col)
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead:
			continue
		var to := enemy.global_position - h.global_position
		if to.length() <= r + enemy.radius and absf(h.facing.angle_to(to)) <= half:
			enemy.charm(float(a.get("time", 3.0)), h, float(a.get("mult", 1.5)))
			Fx.burst(parent, enemy.global_position + Vector2(0, -14), [col, Color("ffd6e8")], 5, 25.0)
			if float(a.get("mark", 0)) > 0.0:  # skill tree rider (issue #25)
				enemy.mark(float(a["mark"]), float(a.get("mark_mult", 1.25)))


## Masked Step (Hortense): gone, and back behind her target (the one she is fighting, else the nearest enemy within
## range, preferring the ones in front), with the point already in: damage, a short stun, a moment untouchable.
## Nobody near: she steps forward instead.
static func _blink(h: Hero, a: Dictionary, parent: Node) -> void:
	var rng := float(a.get("range", 110))
	var col := color_of(a)
	var tgt: Enemy = h.ai_target if h.ai_target != null and is_instance_valid(h.ai_target) and not h.ai_target.dead \
		and h.ai_target.global_position.distance_to(h.global_position) <= rng else null
	if tgt == null:
		var best := INF
		for e in h.get_tree().get_nodes_in_group("enemies"):
			var enemy := e as Enemy
			if enemy == null or enemy.dead:
				continue
			var to := enemy.global_position - h.global_position
			if to.length() > rng:
				continue
			var score := to.length() * (1.0 if absf(h.facing.angle_to(to)) < 1.6 else 2.2)  # in front first
			if score < best:
				best = score
				tgt = enemy
	Fx.burst(parent, h.global_position + Vector2(0, -8), [Color("1a1830"), col, Color("e8e2f8")], 14, 50.0)
	if tgt == null:
		h.move_and_collide(h.facing.normalized() * 40.0)
		Fx.burst(parent, h.global_position + Vector2(0, -8), [Color("1a1830"), col], 10, 40.0)
		h.invuln_t = maxf(h.invuln_t, 0.25)
		return
	var dir := (tgt.global_position - h.global_position).normalized()
	if dir.length() < 0.1:
		dir = h.facing.normalized()
	var gap := tgt.radius + h.radius + 6.0
	var dest := h.global_position
	for turn in [0.0, PI / 2.0, -PI / 2.0, PI]:  # behind it if the ground is free there, else beside it
		var p := tgt.global_position + dir.rotated(turn) * gap
		if not h.test_move(Transform2D(0.0, p), Vector2(0.5, 0.0)):
			dest = p
			break
	h.global_position = dest
	h.facing = (tgt.global_position - h.global_position).normalized()
	h.invuln_t = maxf(h.invuln_t, 0.35)
	h.swing_t = 0.0
	Fx.burst(parent, h.global_position + Vector2(0, -8), [Color("1a1830"), col, Color("e8e2f8")], 14, 50.0)
	Fx.sweep(parent, h.global_position + Vector2(0, -6), h.facing.angle(), deg_to_rad(10), h.global_position.distance_to(tgt.global_position) + 8.0, col)
	if TreePerks.strike(h, tgt, int(a.get("damage", 18)), h.global_position, float(a.get("knock", 140)), a):
		tgt.stun(float(a.get("stun", 0)))
	if float(a.get("vanish", 0)) > 0.0:  # skill tree (issue #25)
		h.vanish(float(a["vanish"]), 1.2, 1.0)
	if h.party:
		h.party.shake(2.0)


## Torch Song (Saffron): everyone in the party within radius (her too) deals boost more damage and refills the gauge
## rate faster for time s (Hero.song_t). Optional heal for each of them.
static func _song(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 90))
	var col := color_of(a)
	Fx.ring(parent, h.global_position, r, col)
	for o in h.get_tree().get_nodes_in_group("heroes"):
		var other := o as Hero
		if other == null or other.dead or other.party != h.party or other.global_position.distance_to(h.global_position) > r:
			continue
		sing_to(other, float(a.get("time", 6.0)), float(a.get("boost", 0.2)), float(a.get("rate", 0.3)))
		if int(a.get("heal", 0)) > 0:
			var amount := mini(TreePerks.heal_amount(h, int(a["heal"])), other.max_hp - other.hp)
			if amount > 0:
				other.hp += amount
				Fx.damage_number(parent, other.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))
		Fx.burst(parent, other.global_position + Vector2(0, -16), [col, Color("fff1b8")], 6, 30.0)


## Puts a hero under the Torch Song (the ability, Saffron's techs and the Chorus bowing out all use it).
static func sing_to(other: Hero, time: float, boost: float, rate: float) -> void:
	if other.song_t > 0.0:
		other.song_boost = maxf(other.song_boost, boost)
		other.song_rate = maxf(other.song_rate, rate)
	else:
		other.song_boost = boost
		other.song_rate = rate
	other.song_t = maxf(other.song_t, time)


## Showstopper (Saffron): she sings a chorus girl into being in front of her (scripts/chorus.gd). It stands for time s
## with hp of its own, pulls every enemy within radius onto itself, and bows out with a burst of damage around it.
static func _conjure(h: Hero, a: Dictionary, parent: Node) -> void:
	for c in h.get_tree().get_nodes_in_group("chorus"):  # one chorus girl per singer
		if (c as Chorus).singer == h:
			(c as Chorus).bow()
	var c := Chorus.new()
	c.singer = h
	c.hero_id = h.hero_id  # wears the singer's own sprite, gilded (chorus.gd)
	c.hero_name = h.hero_name
	c.ability = a
	c.max_hp = int(a.get("hp", 40))
	c.hp = c.max_hp
	c.life = float(a.get("time", 5.0))
	var at := h.global_position + h.facing.normalized() * 26.0
	if h.test_move(h.global_transform, at - h.global_position):
		at = h.global_position + h.facing.normalized() * 10.0
	c.position = at
	parent.add_child(c)
	Fx.burst(parent, at + Vector2(0, -12), [color_of(a), Color("fff1b8"), Color.WHITE], 18, 60.0)


## Small Print (Nan): a contract slapped on everything within radius. For time s their hits deal mult of their damage
## and they move at slow of their speed (Enemy.weaken; bosses half that).
static func _weaken(h: Hero, a: Dictionary, parent: Node) -> void:
	var r := float(a.get("radius", 70))
	var col := color_of(a)
	Fx.ring(parent, h.global_position, r, col)
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or enemy.global_position.distance_to(h.global_position) > r:
			continue
		enemy.weaken(float(a.get("time", 6.0)), float(a.get("mult", 0.6)), float(a.get("slow", 0.7)))
		Fx.burst(parent, enemy.global_position + Vector2(0, -12), [Color("e8e2d0"), col], 5, 25.0)
		if int(a.get("damage", 0)) > 0:  # skill tree rider (issue #25)
			TreePerks.strike(h, enemy, int(a["damage"]), h.global_position, 40.0, {})


## Tally's Turn (Nan): her shadow peels off and fights on its own for time s (scripts/tally_shadow.gd): it darts at
## the nearest enemy and punches for damage every few tenths of a second. Casting again calls the old one back first.
static func _shadow(h: Hero, a: Dictionary, parent: Node) -> void:
	for t in h.get_tree().get_nodes_in_group("shadows"):
		if (t as TallyShadow).owner_hero == h:
			(t as TallyShadow).fade()
	var t := TallyShadow.new()
	t.owner_hero = h
	t.ability = a
	t.life = float(a.get("time", 6.0))
	t.position = h.global_position + h.facing.normalized().orthogonal() * 10.0
	parent.add_child(t)
	Fx.burst(parent, t.position + Vector2(0, -8), [Color("1a1424"), color_of(a)], 14, 45.0)


# ---------------------------------------------------------------- Chapter 4 kinds (#30)

## Unwrite (Ilse, White Ink): a straight white line from her spear point, reach long and width wide. Enemies on it that
## are at or under erase of their health (and any Salt Wight's heap) are taken off the page outright (Enemy.erase_out);
## the rest take damage and a short stun. Bosses never unwrite: they take the damage. Things out of reach (under the
## ink, up in the air) are missed.
static func _unwrite(h: Hero, a: Dictionary, parent: Node) -> void:
	var reach := float(a.get("reach", 90))
	var width := float(a.get("width", 16))
	var col := color_of(a)
	var dir := h.facing.normalized()
	Fx.sweep(parent, h.global_position + Vector2(0, -6), dir.angle(), deg_to_rad(5), reach, Color.WHITE)
	for i in 4:
		Fx.burst(parent, h.global_position + Vector2(0, -6) + dir * reach * (0.25 + 0.25 * i), [Color.WHITE, col], 4, 25.0)
	var erased := 0
	var hit_any := false
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or enemy.untargetable():
			continue
		var local := (enemy.global_position - h.global_position).rotated(-dir.angle())
		if local.x < -enemy.radius or local.x > reach + enemy.radius or absf(local.y) > width / 2.0 + enemy.radius:
			continue
		hit_any = true
		if not enemy.boss and (enemy.heaped() or float(enemy.hp) <= float(enemy.max_hp) * float(a.get("erase", 0.25))):
			enemy.erase_out()
			erased += 1
			continue
		if TreePerks.strike(h, enemy, int(a.get("damage", 14)), h.global_position, float(a.get("knock", 120)), a):
			enemy.stun(float(a.get("stun", 0)))
	if erased > 0 and int(a.get("pierce_heal", 0)) > 0:  # skill tree rider (issue #25)
		TreePerks._heal_self(h, int(a["pierce_heal"]) * erased)
	if hit_any and h.party:
		h.party.shake(2.5 if erased > 0 else 1.5)
		Rumble.landed(h, 0.8)


## The enemy Unwrite would take off the page right now (or the best one to hit), within range in front of her or
## not: used by the ally rule "line". Erasable ones first, then the nearest.
static func unwrite_target(h: Hero, a: Dictionary, rng: float) -> Enemy:
	var best: Enemy = null
	var best_score := INF
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy == null or enemy.dead or enemy.untargetable():
			continue
		var d := enemy.global_position.distance_to(h.global_position)
		if d > rng:
			continue
		var erasable := not enemy.boss and (enemy.heaped() or float(enemy.hp) <= float(enemy.max_hp) * float(a.get("erase", 0.25)))
		var score := d - (1000.0 if erasable else 0.0)
		if score < best_score:
			best_score = score
			best = enemy
	return best


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
	for i in h.abilities.size():
		if blocker(h, i) == "" and rule_fires(h, i):
			return i
	return -1


## Whether ability slot i's own "ai" rule (data/abilities.json) says now. The Chapter 3 kinds (OWN_RULE) use it
## under every preset (AllyAI.pick_ability); Balanced uses it for everything.
static func rule_fires(h: Hero, i: int) -> bool:
	var leader: Hero = h.party.leader if h.party else null
	var rule: Dictionary = h.abilities[i].get("ai", {})
	match str(rule.get("when", "")):
		"hurt":
			var r := float(h.abilities[i].get("radius", 60))
			for o in h.get_tree().get_nodes_in_group("heroes"):
				var other := o as Hero
				if other and not other.dead and other.party == h.party \
						and other.global_position.distance_to(h.global_position) <= r \
						and float(other.hp) / other.max_hp < float(rule.get("below", 0.5)):
					return true
		"crowd":
			if _count_near(h, h.global_position, float(rule.get("range", 32))) >= int(rule.get("count", 2)):
				_face_crowd(h, float(rule.get("range", 32)))
				return true
		"target":
			var tgt: Enemy = h.ai_target
			if tgt and is_instance_valid(tgt) and not tgt.dead:
				var d := tgt.global_position.distance_to(h.global_position)
				if d <= float(rule.get("range", 60)) and d > 20.0:
					h.facing = (tgt.global_position - h.global_position).normalized()
					return true
		"windup":
			for e in h.get_tree().get_nodes_in_group("enemies"):
				var enemy := e as Enemy
				if enemy and not enemy.dead and enemy.target == h and enemy.state == Enemy.State.WINDUP \
						and enemy.global_position.distance_to(h.global_position) <= float(rule.get("range", 40)):
					return true
		"self_hurt":
			if float(h.hp) / h.max_hp < float(rule.get("below", 0.5)) and _count_near(h, h.global_position, float(rule.get("range", 40))) >= 1:
				return true
		"threat":
			if leader and _count_near(h, leader.global_position, float(rule.get("range", 60))) >= int(rule.get("count", 2)):
				return true
		"line":  # Unwrite (Chapter 4): only worth White Ink on something it would unwrite, or on a boss in reach
			var tgt := unwrite_target(h, h.abilities[i], float(rule.get("range", 80)))
			if tgt != null and (tgt.boss or tgt.heaped() or float(tgt.hp) <= float(tgt.max_hp) * float(h.abilities[i].get("erase", 0.25))):
				h.facing = (tgt.global_position - h.global_position).normalized()
				return true
	return false


## Cones (Beguile) want to point at the crowd: turn to face the middle of the enemies within r.
static func _face_crowd(h: Hero, r: float) -> void:
	if not h.abilities.any(func(a): return str(a.get("kind", "")) == "charm"):
		return
	var sum := Vector2.ZERO
	var n := 0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(h.global_position) <= r:
			sum += enemy.global_position - h.global_position
			n += 1
	if n > 0 and sum.length() > 0.1:
		h.facing = sum.normalized()


static func _count_near(h: Hero, at: Vector2, r: float) -> int:
	var n := 0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(at) <= r:
			n += 1
	return n
