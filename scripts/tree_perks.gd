class_name TreePerks
## The passives skill tree nodes give a hero in the field (issue #25, data/skill_trees.json "perks"; the
## tree itself is scripts/skill_tree.gd). Hero.perks holds the summed values; the hooks below are called
## where heroes hit, get hit, heal, kill and revive.
##
## Every perk key a node may use, and what it does (tests/test_skill_trees.gd checks the data against it):
const PERKS := {
	# Hitting (TreePerks.strike: swings, abilities, techs, thrown knives)
	"dmg_low_hp": "more damage while the hero is under 40% HP",
	"dmg_wounded": "more damage to enemies under 35% HP",
	"dmg_fresh": "more damage to enemies still at full HP",
	"dmg_marked": "more damage to marked (Audited) enemies",
	"dmg_stunned": "more damage to stunned enemies",
	"dmg_poisoned": "more damage to poisoned enemies",
	"crit": "chance for a hit to land half again as hard",
	"leech": "heals the hero for this share of the damage they deal",
	"poison": "full swings poison for this much a second (4 s)",
	"swing_stun": "full-power swings stun for this many seconds",
	"tech_mult": "charged techs deal this much more",
	"aura_damage": "allies within 70 px deal this much more",
	# Killing
	"kill_ink": "Ink for the hero on each kill",
	"kill_ink_party": "Ink for each ally within 90 px on each kill",
	"kill_heal": "HP for the hero on each kill",
	"kill_gauge": "a kill refills the power gauge",
	"kill_gilt": "Gilt into the mission's loot on each kill",
	"kill_vanish": "a kill puts the hero out of sight for this many seconds",
	"kill_reset": "a kill resets this ability's cooldown (an ability id)",
	# Getting hit
	"evade": "chance for a hit to miss completely",
	"bodyguard": "share of the damage aimed at allies within 56 px that lands on the hero instead",
	"aura_guard": "allies within 70 px take this much less damage",
	"thorns": "enemies that hit the hero take this share back",
	"last_stand": "once a mission, a killing blow leaves the hero on 1 HP",
	"poise_cut": "knockback moves the hero this much less",
	# Healing and Ink
	"heal_power": "heals the hero gives are this much bigger",
	"heal_rate": "the passive poultice comes this much more often",
	"heal_bill": "Gilt into the mission's loot for every healing ability cast",
	"ink_regen": "extra Ink a second",
	"revive_speed": "fallen allies near the hero get up this much faster",
}
## Who the ally AI goes for (data "ai": {"focus": ...}, AllyAI.steer).
const FOCUS := {
	"wounded": "the most hurt enemy nearby",
	"marked": "marked enemies first",
	"leader_threat": "whatever is attacking the leader",
	"elite": "the toughest enemy nearby",
}
const AURA_RANGE := 70.0
const BODYGUARD_RANGE := 56.0
const POISON_TIME := 4.0
const LOW_HP := 0.4
const WOUNDED := 0.35

static var _redirecting := false


static func p(h: Hero, key: String) -> float:
	if h == null or not is_instance_valid(h):
		return 0.0
	var v = h.perks.get(key, 0.0)
	return float(v) if typeof(v) != TYPE_STRING else 0.0


static func _allies(h: Hero, r: float, at := Vector2.INF) -> Array:
	var out := []
	var c := h.global_position if at == Vector2.INF else at
	for o in h.get_tree().get_nodes_in_group("heroes"):
		var other := o as Hero
		if other and other != h and not other.dead and other.party == h.party and other.global_position.distance_to(c) <= r:
			out.append(other)
	return out


# ---------------------------------------------------------------- hitting

## A hero's hit on an enemy, with the tree on top: damage bonuses, crits, then the ability's riders
## (a: poison, leech, mark, taunt) and kill rewards. source: "swing", "ability", "tech" or "knife".
## Returns what take_hit returned.
static func strike(h: Hero, enemy: Enemy, dmg: int, from: Vector2, knock: float, a := {}, source := "ability") -> bool:
	if h == null or not is_instance_valid(h):
		return enemy.take_hit(dmg, from, knock)
	var mult := 1.0 + damage_bonus(h, enemy)
	if source == "tech":
		mult += p(h, "tech_mult")
	var crit := p(h, "crit") > 0.0 and randf() < p(h, "crit")
	if crit:
		mult *= 1.5
	var before := enemy.hp
	var landed := enemy.take_hit(maxi(1, roundi(dmg * mult)), from, knock)
	if not landed:
		return false
	var dealt := before - enemy.hp
	if crit and dealt > 0:
		Fx.damage_number(h.get_parent(), enemy.global_position + Vector2(0, -30), Loc.t("Sharp!"), Color("ffe08a"))
	var leech := p(h, "leech") + float(a.get("leech", 0.0))
	if leech > 0.0 and dealt > 0 and not h.dead:
		_heal_self(h, int(round(dealt * leech)))
	if not enemy.dead:
		var venom := float(a.get("poison", 0.0)) + (p(h, "poison") if source == "swing" and h.swing_power >= 1.0 else 0.0)
		if venom > 0.0:
			poison(enemy, venom, POISON_TIME, h)
		if float(a.get("mark", 0.0)) > 0.0:
			enemy.mark(float(a["mark"]), float(a.get("mark_mult", 1.25)))
		if float(a.get("taunt", 0.0)) > 0.0:
			enemy.taunt(h, float(a["taunt"]))
		if source == "swing" and h.swing_power >= 1.0 and p(h, "swing_stun") > 0.0:
			enemy.stun(p(h, "swing_stun"))
	else:
		killed(h, enemy)
	return true


## The extra damage share this hero's tree (and allies' auras) gives against this enemy.
static func damage_bonus(h: Hero, enemy: Enemy) -> float:
	var b := 0.0
	if not h.perks.is_empty():
		if p(h, "dmg_low_hp") > 0.0 and float(h.hp) < h.max_hp * LOW_HP:
			b += p(h, "dmg_low_hp")
		if p(h, "dmg_wounded") > 0.0 and float(enemy.hp) < enemy.max_hp * WOUNDED:
			b += p(h, "dmg_wounded")
		if p(h, "dmg_fresh") > 0.0 and enemy.hp >= enemy.max_hp:
			b += p(h, "dmg_fresh")
		if p(h, "dmg_marked") > 0.0 and enemy.marked():
			b += p(h, "dmg_marked")
		if p(h, "dmg_stunned") > 0.0 and enemy.stun_left() > 0.0:
			b += p(h, "dmg_stunned")
		if p(h, "dmg_poisoned") > 0.0 and poisoned(enemy):
			b += p(h, "dmg_poisoned")
	var aura := 0.0
	for o in _allies(h, AURA_RANGE):
		aura = maxf(aura, p(o, "aura_damage"))
	if enemy.charmed_by(h):  # Beguile (Hortense): she hits what she has charmed harder
		b += enemy.charm_mult - 1.0
	if h.song_t > 0.0:  # Saffron's Torch Song: everyone it reaches hits harder while it lasts
		b += h.song_boost
	return b + aura


# ---------------------------------------------------------------- kills

## Kill rewards for the hero who landed the blow (once per enemy).
static func killed(h: Hero, enemy: Node) -> void:
	if enemy.has_meta("tree_credited") or h == null or not is_instance_valid(h) or h.dead:
		return
	enemy.set_meta("tree_credited", true)
	if h.perks.is_empty():
		return
	var parent := h.get_parent()
	if p(h, "kill_ink") > 0.0:
		h.ink = minf(h.ink + p(h, "kill_ink"), h.max_ink)
	if p(h, "kill_ink_party") > 0.0:
		for o in _allies(h, 90.0):
			o.ink = minf(o.ink + p(h, "kill_ink_party"), o.max_ink)
			Fx.damage_number(parent, o.global_position + Vector2(0, -24), Loc.t("+%d Ink") % int(p(h, "kill_ink_party")), Color("6aa8ff"))
	if p(h, "kill_heal") > 0.0:
		_heal_self(h, int(p(h, "kill_heal")))
	if p(h, "kill_gauge") > 0.0:
		h.power = 1.0
	if p(h, "kill_gilt") > 0.0:
		pay(h, int(p(h, "kill_gilt")), enemy.global_position)
	if p(h, "kill_vanish") > 0.0:
		h.vanish(maxf(h.vanish_t, p(h, "kill_vanish")), 1.3, 1.0)
		Fx.burst(parent, h.global_position + Vector2(0, -8), [Color("2a2438"), Color("4a4060")], 10, 40.0)
	var reset := str(h.perks.get("kill_reset", ""))
	if reset != "":
		for i in h.abilities.size():
			if str(h.abilities[i].get("id", "")) == reset and h.cooldowns[i] > 0.0:
				h.cooldowns[i] = 0.0
				Fx.damage_number(parent, h.global_position + Vector2(0, -30), Loc.t("Again!"), Color("ffd166"))


## An enemy fell (main.gd): kills that no strike credited (poison, burn) go to whoever put the status on
## it (Status sets "status_source" on each damage tick).
static func enemy_died(e: Node) -> void:
	if e.has_meta("tree_credited") or not e.has_meta("status_source"):
		return
	var src = e.get_meta("status_source")
	if is_instance_valid(src) and src is Hero:
		killed(src, e)


## Gilt that goes home with the mission's loot (dropped if the party is wiped, like any other find).
static func pay(h: Hero, gilt: int, at: Vector2) -> void:
	if gilt <= 0 or h.party == null or not ("found" in h.party):
		return
	var found: Dictionary = h.party.found
	found["gilt"] = int(found.get("gilt", 0)) + gilt
	Fx.damage_number(h.get_parent(), at + Vector2(0, -22), Loc.t("+%d Gilt") % gilt, Color("ffd166"))


static func _heal_self(h: Hero, amount: int) -> void:
	amount = mini(amount, h.max_hp - h.hp)
	if amount <= 0:
		return
	h.hp += amount
	Fx.damage_number(h.get_parent(), h.global_position + Vector2(0, -18), "+%d" % amount, Color("9fe07a"))


# ---------------------------------------------------------------- getting hit

## Before a hit lands on h (Hero.take_hit). Returns the amount h still takes: a miss (evade) is 0, a
## bodyguard nearby takes part of it. -1 means the hit was dodged outright.
static func incoming(h: Hero, amount: int, from: Vector2) -> int:
	if p(h, "evade") > 0.0 and randf() < p(h, "evade"):
		Fx.damage_number(h.get_parent(), h.global_position + Vector2(0, -18), Loc.t("missed"), Color(0.8, 0.8, 0.85))
		h.invuln_t = maxf(h.invuln_t, 0.25)
		return -1
	if _redirecting:
		return amount
	var guard: Hero = null
	var best := 0.0
	for o in _allies(h, BODYGUARD_RANGE):
		if p(o, "bodyguard") > best and o.invuln_t <= 0.0:
			best = p(o, "bodyguard")
			guard = o
	if guard == null:
		return amount
	var part := int(round(amount * clampf(best, 0.0, 0.9)))
	if part <= 0:
		return amount
	_redirecting = true
	guard.take_hit(part, from, 0.0)
	_redirecting = false
	Fx.burst(h.get_parent(), guard.global_position.lerp(h.global_position, 0.5) + Vector2(0, -10), [Color("6a9ae8"), Color.WHITE], 6, 30.0)
	return maxi(amount - part, 1)


## Inside Hero._adjust_damage, after shields and armor: auras from allies, then the last stand.
static func adjust(h: Hero, amount: int) -> int:
	var aura := 0.0
	for o in _allies(h, AURA_RANGE):
		aura = maxf(aura, p(o, "aura_guard"))
	if aura > 0.0:
		amount = maxi(1, roundi(amount * (1.0 - aura)))
	if amount >= h.hp and h.last_stand_left > 0:
		h.last_stand_left -= 1
		h.last_stand_spent = true
		amount = maxi(h.hp - 1, 0)
		h.invuln_t = maxf(h.invuln_t, 1.5)
		Fx.damage_number(h.get_parent(), h.global_position + Vector2(0, -30), Loc.t("Not today!"), Color("ffd166"))
		Fx.burst(h.get_parent(), h.global_position + Vector2(0, -10), [Color("ffd166"), Color.WHITE], 16, 60.0)
	return amount


## After a hit landed on h: thorns go back to whoever threw it (the nearest enemy to where it came from).
static func hit_back(h: Hero, taken: int, from: Vector2) -> void:
	if taken <= 0 or p(h, "thorns") <= 0.0 or _redirecting:
		return
	var best: Enemy = null
	var best_d := 48.0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Enemy
		if enemy and not enemy.dead and enemy.global_position.distance_to(from) < best_d:
			best_d = enemy.global_position.distance_to(from)
			best = enemy
	if best:
		var back := maxi(1, int(round(taken * p(h, "thorns"))))
		if best.take_hit(back, h.global_position, 40.0) and best.dead:
			killed(h, best)


# ---------------------------------------------------------------- heals and revives

## A heal this hero gives, made bigger by heal_power.
static func heal_amount(h: Hero, amount: int) -> int:
	return int(round(amount * (1.0 + p(h, "heal_power"))))


## How much faster a fallen hero gets up with these heroes standing near (main.gd _update_revive).
static func revive_mult(fallen: Hero, heroes: Array) -> float:
	var best := 0.0
	for o in heroes:
		var other := o as Hero
		if other and other != fallen and not other.dead and other.global_position.distance_to(fallen.global_position) <= 48.0:
			best = maxf(best, p(other, "revive_speed"))
	return 1.0 + best


# ---------------------------------------------------------------- poison

## Poisons an enemy for dps a second over secs, credited to source: the shared poison status (issue #112,
## scripts/status.gd), the same one Reedlings put on heroes and the poison mark shows. Ticks skip the hit reaction, so a
## poisoned Nibbler isn't staggered every tick; a kill pays source's tree rewards (enemy_died).
static func poison(enemy: Enemy, dps: float, secs: float, source: Hero) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.dead or dps <= 0.0:
		return
	Status.apply(enemy, "poison", secs, {"dps": dps, "source": source})


static func poisoned(enemy: Enemy) -> bool:
	return Status.has(enemy, "poison")
