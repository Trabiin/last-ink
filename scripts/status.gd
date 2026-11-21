class_name Status
extends RefCounted
## Status effects (issue #112) on heroes and enemies, and the timed boons field items give.
##
## Ailments:  poison - loses HP over time; on a hero it stops at 1 HP (on an enemy it can kill).
##            burn   - loses HP faster, for a shorter time, and can kill.
##            stun   - can't move, swing or cast (heroes: then a few seconds immune; enemies use Enemy.stun).
##            erase  - the Blank's touch: no Ink abilities, no charged techs, no Ink coming back.
## Boons:     might (damage x1.25), guard (25% less damage taken), haste (faster feet and gauge),
##            ward (proof against the Blank: no Erase, the white's edge doesn't burn, Blank-born
##            creatures lose interest unless close, 25% less damage taken).
##
## State sits on the actor as meta "status" ({id: {"left", "dps", "acc", "tick", "source", "undo"}}) and
## "status_immune" ({id: seconds}), so Actor needs no new fields. Hero and Enemy call tick() every
## physics frame. Enemies say what they inflict in data/enemies.json ("inflict": {status, chance, time}),
## applied through struck() after a hit lands. Icons: assets/icons/status_<id>.png; every status also
## has its own shape over the head (draw_marks), so none is told apart by colour alone (#34).

const AILMENTS := ["poison", "burn", "stun", "erase"]
const BOONS := ["might", "guard", "haste", "ward"]
const NAMES := {"poison": "Poison", "burn": "Burn", "stun": "Stun", "erase": "Erased",
	"might": "Might", "guard": "Iron skin", "haste": "Haste", "ward": "Ward"}
const COLORS := {"poison": Color("8fd16a"), "burn": Color("ff9a3c"), "stun": Color("ffe58a"), "erase": Color("e8e6f0"),
	"might": Color("ff6b5a"), "guard": Color("8fa7e8"), "haste": Color("7fe0d8"), "ward": Color("f4d58a")}
const TICK := 0.5  # seconds between damage ticks
const HERO_POISON := 0.02  # share of max HP a second
const HERO_BURN := 0.035
const ENEMY_DPS := {"poison": 3.0, "burn": 5.0}
const STUN_IMMUNE := 3.0  # seconds a hero can't be stunned again after one ends
const MIGHT := 1.25
const GUARD_CUT := 0.25
const HASTE_SPEED := 0.2
const HASTE_GAUGE := 0.25
const WARD_CUT := 0.25
const REVIVE_DELAY := 2.0


static func name_of(id: String) -> String:
	return Loc.t(str(NAMES.get(id, id.capitalize())))


static func color_of(id: String) -> Color:
	return COLORS.get(id, Color.WHITE)


static func _all(t: Node) -> Dictionary:
	if t == null or not is_instance_valid(t):
		return {}
	if not t.has_meta("status"):
		t.set_meta("status", {})
	return t.get_meta("status")


static func has(t: Node, id: String) -> bool:
	return float(_all(t).get(id, {}).get("left", 0.0)) > 0.0


static func left(t: Node, id: String) -> float:
	return float(_all(t).get(id, {}).get("left", 0.0))


## Active statuses on an actor, ailments first: [[id, seconds left], ...].
static func active(t: Node) -> Array:
	var out := []
	var s := _all(t)
	for id in AILMENTS + BOONS:
		if float(s.get(id, {}).get("left", 0.0)) > 0.0:
			out.append([id, float(s[id]["left"])])
	return out


static func _hero_id(t: Node) -> String:
	return str(t.get("hero_id")) if t is Hero else ""


## Can this status take hold right now? (trinkets, a short immunity after a cure or a stun, the ward)
static func immune(t: Node, id: String) -> bool:
	if not id in AILMENTS:
		return false
	var im: Dictionary = t.get_meta("status_immune", {}) if t.has_meta("status_immune") else {}
	if float(im.get(id, 0.0)) > 0.0:
		return true
	if id == "erase" and has(t, "ward"):
		return true
	if t is Hero:
		return id in (Armory.perk(_hero_id(t), "immune", []) as Array)
	return false


static func grant_immunity(t: Node, ids: Array, seconds: float) -> void:
	if seconds <= 0.0:
		return
	var im: Dictionary = t.get_meta("status_immune", {}) if t.has_meta("status_immune") else {}
	for id in ids:
		im[id] = maxf(float(im.get(id, 0.0)), seconds)
	t.set_meta("status_immune", im)


## Puts a status on an actor for `seconds`. opts: {"dps": HP a second for poison/burn, "source": Hero}.
## Re-applying refreshes the time and keeps the stronger dps. Returns false if it didn't take.
static func apply(t: Node, id: String, seconds: float, opts := {}) -> bool:
	if t == null or not is_instance_valid(t) or not t is Actor or (t as Actor).dead or seconds <= 0.0:
		return false
	if immune(t, id):
		if t is Hero:
			Fx.damage_number(t.get_parent(), (t as Node2D).global_position + Vector2(0, -26), Loc.t("resisted"), Color("d8d0c0"))
		return false
	if id == "stun" and t is Enemy:
		(t as Enemy).stun(seconds)
		return true
	var s := _all(t)
	var e: Dictionary = s.get(id, {})
	var fresh := float(e.get("left", 0.0)) <= 0.0
	e["left"] = maxf(float(e.get("left", 0.0)), seconds)
	if opts.has("dps"):
		e["dps"] = maxf(float(e.get("dps", 0.0)), float(opts["dps"]))
	if opts.get("source") != null:
		e["source"] = opts["source"]
	s[id] = e
	if fresh:
		_on_start(t, id, e)
	return true


static func _on_start(t: Node, id: String, e: Dictionary) -> void:
	var pos := (t as Node2D).global_position
	match id:
		"stun":
			if t is Hero:
				Techs.cancel(t as Hero)
				(t as Hero).swing_t = 0.0
		"erase":
			if t is Hero:
				Techs.cancel(t as Hero)
		"might":
			if t is Hero:
				var add := roundi((t as Hero).base_damage * (MIGHT - 1.0))
				(t as Hero).base_damage += add
				e["undo"] = add
		"haste":
			if t is Hero:
				var h := t as Hero
				var sp := h.move_speed * HASTE_SPEED
				var pr := h.power_rate * HASTE_GAUGE
				h.move_speed += sp
				h.power_rate += pr
				e["undo"] = [sp, pr]
	if id in AILMENTS and t is Hero:
		Fx.damage_number(t.get_parent(), pos + Vector2(0, -26), name_of(id), color_of(id))
		Audio.sfx("hurt" if id != "stun" else "alert", 1.2, -8.0)


static func _on_end(t: Node, id: String, e: Dictionary) -> void:
	match id:
		"might":
			if t is Hero:
				(t as Hero).base_damage -= int(e.get("undo", 0))
		"haste":
			if t is Hero and typeof(e.get("undo")) == TYPE_ARRAY:
				(t as Hero).move_speed -= float(e["undo"][0])
				(t as Hero).power_rate -= float(e["undo"][1])
		"stun":
			if t is Hero:
				grant_immunity(t, ["stun"], STUN_IMMUNE)


## Removes statuses ("all" = every ailment). Returns how many were removed.
static func cure(t: Node, ids: Array) -> int:
	var list: Array = AILMENTS if "all" in ids else ids
	var n := 0
	var s := _all(t)
	for id in list:
		if float(s.get(id, {}).get("left", 0.0)) > 0.0:
			_on_end(t, id, s[id])
			s.erase(id)
			n += 1
	return n


## Clears everything (death, mission end). Boons are undone too.
static func clear_all(t: Node) -> void:
	var s := _all(t)
	for id in s.keys():
		if float(s[id].get("left", 0.0)) > 0.0:
			_on_end(t, id, s[id])
	s.clear()


static func cured_by(t: Node, ids: Array) -> bool:
	for id in (AILMENTS if "all" in ids else ids):
		if has(t, id):
			return true
	return false


## Runs the clocks. Returns true while the actor can't act (a stunned hero).
static func tick(t: Actor, delta: float) -> bool:
	if t.has_meta("status_immune"):
		var im: Dictionary = t.get_meta("status_immune")
		for k in im.keys():
			im[k] = float(im[k]) - delta
			if float(im[k]) <= 0.0:
				im.erase(k)
	if t is Hero:
		_revive_check(t as Hero, delta)
	if t.dead:
		if t.has_meta("status") and not (t.get_meta("status") as Dictionary).is_empty():
			clear_all(t)
		return false
	if not t.has_meta("status"):
		return false
	var s: Dictionary = t.get_meta("status")
	if s.is_empty():
		return false
	for id in s.keys():
		var e: Dictionary = s[id]
		e["left"] = float(e["left"]) - delta
		if id == "poison" or id == "burn":
			e["tick"] = float(e.get("tick", TICK)) - delta
			if float(e["tick"]) <= 0.0:
				e["tick"] = TICK
				_dot(t, id, e)
				if t.dead:
					return false
		if id == "erase" and t is Hero:
			var h := t as Hero
			h.ink = maxf(h.ink - h.ink_regen * delta, 0.0)  # nothing comes back while Erased
		if float(e["left"]) <= 0.0:
			_on_end(t, id, e)
			s.erase(id)
	return t is Hero and has(t, "stun")


static func _dot(t: Actor, id: String, e: Dictionary) -> void:
	var dps := float(e.get("dps", 0.0))
	if dps <= 0.0:
		dps = (t.max_hp * (HERO_POISON if id == "poison" else HERO_BURN)) if t is Hero else float(ENEMY_DPS.get(id, 3.0))
	e["acc"] = float(e.get("acc", 0.0)) + dps * TICK
	var amount := int(floor(float(e["acc"])))
	if amount <= 0:
		return
	e["acc"] = float(e["acc"]) - amount
	if e.get("source") != null and is_instance_valid(e["source"]):
		t.set_meta("status_source", e["source"])
	hurt(t, amount, color_of(id), id == "poison" and t is Hero)


## Damage that skips the hit reaction (no knockback, flash or stagger), used by ticks and perks.
## floor_one: stop at 1 HP. A lethal amount goes through take_hit so death runs as usual. Bosses and
## Blots take it as a hit without knockback, so their own rules (the Auditor's untouchable phases, his
## phase change) still apply; an Audited enemy takes its mark's extra like any other damage.
static func hurt(t: Actor, amount: int, col: Color, floor_one := false) -> void:
	if t.dead or amount <= 0:
		return
	if t is Enemy and ((t as Enemy).boss or t is Blot):
		t.take_hit(amount, t.global_position, 0.0)
		return
	amount = Settings.difficulty_damage(t, amount)
	if t is Enemy:
		amount = t._adjust_damage(amount)
	if floor_one:
		amount = mini(amount, t.hp - 1)
		if amount <= 0:
			return
	if amount >= t.hp:
		t.invuln_t = 0.0
		t.take_hit(amount, t.global_position, 0.0)
		return
	t.hp -= amount
	Fx.damage_number(t.get_parent(), t.global_position + Vector2(randf_range(-4, 4), -14), str(amount), col)


# ---------------------------------------------------------------- what boons do in a fight

## Swing damage multiplier from boons and trinkets (Might, Widow's Ribbon).
static func swing_mult(h: Hero) -> float:
	var m := 1.0
	var ls: Dictionary = Armory.perk(h.hero_id, "last_stand", {})
	if not ls.is_empty() and h.hp <= h.max_hp * float(ls.get("below", 0.3)):
		m *= float(ls.get("damage", 1.0))
	return m


## Incoming damage after Iron Tea, the ward and Widow's Ribbon (called from Hero._adjust_damage).
static func adjust_incoming(h: Hero, amount: int) -> int:
	var cut := 0.0
	if has(h, "guard"):
		cut += GUARD_CUT
	if has(h, "ward"):
		cut += WARD_CUT
	var ls: Dictionary = Armory.perk(h.hero_id, "last_stand", {})
	if not ls.is_empty() and h.hp <= h.max_hp * float(ls.get("below", 0.3)):
		cut += float(ls.get("guard", 0.0))
	if cut <= 0.0:
		return amount
	return maxi(1, roundi(amount * (1.0 - minf(cut, 0.7))))


## Is this Blank-born enemy put off by a warded hero at this distance?
static func warded_from(e: Node, h: Hero, dist: float) -> bool:
	return has(h, "ward") and dist > 40.0 and bool(EnemyKinds.kind(Journal.kind_of(e)).get("blank", false))


## A hero's swing landed on an enemy (after the hit): trinket perks. Called from Hero._apply_hit.
static func swing_landed(h: Hero, enemy: Enemy, dmg: int) -> void:
	var pk := Armory.perks(h.hero_id)
	if pk.is_empty():
		return
	if pk.has("first_strike") and not enemy.has_meta("struck_" + h.hero_id):
		enemy.set_meta("struck_" + h.hero_id, true)
		var extra := roundi(dmg * (float(pk["first_strike"]) - 1.0))
		if extra > 0 and not enemy.dead:
			hurt(enemy, extra, Color("ffd166"))
	else:
		enemy.set_meta("struck_" + h.hero_id, true)
	if pk.has("lifesteal") and h.hp < h.max_hp:
		var heal := maxi(1, roundi(dmg * float(pk["lifesteal"])))
		heal = mini(heal, h.max_hp - h.hp)
		h.hp += heal
		Fx.damage_number(h.get_parent(), h.global_position + Vector2(0, -18), "+%d" % heal, Color("9fe07a"))
	if pk.has("stun_on_full") and h.swing_power >= 1.0 and not enemy.dead:
		enemy.stun(float(pk["stun_on_full"]))


## A hero is about to take a hit from `from`: Thornwire bites back at whoever is that close.
static func thorns(h: Hero, from: Vector2) -> void:
	var n := float(Armory.perk(h.hero_id, "thorns", 0.0))
	if n <= 0.0 or h.dead:
		return
	var best: Enemy = null
	var best_d := 30.0
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.dead:
			continue
		var d := en.global_position.distance_to(from)
		if d < best_d and en.global_position.distance_to(h.global_position) < 40.0:
			best_d = d
			best = en
	if best != null:
		hurt(best, int(n), Color("d0c0ff"))


## An enemy fell: Inkblot Brooch and Gilt Tooth on heroes close by. Returns Gilt picked up.
static func enemy_fell(e: Node2D, heroes: Array) -> int:
	var gilt := 0
	for h in heroes:
		var hero := h as Hero
		if hero == null or hero.dead or hero.global_position.distance_to(e.global_position) > 90.0:
			continue
		var pk := Armory.perks(hero.hero_id)
		if pk.has("ink_on_kill") and hero.max_ink > 0.0:
			hero.ink = minf(hero.ink + float(pk["ink_on_kill"]), hero.max_ink)
		gilt += int(pk.get("gilt_on_kill", 0))
	return gilt


## Second Signature: once a mission, a hero who falls gets back up after a moment.
static func _revive_check(h: Hero, delta: float) -> void:
	if not h.dead:
		return
	if h.has_meta("signature_used"):
		var t := float(h.get_meta("signature_t", -1.0))
		if t > 0.0:
			t -= delta
			h.set_meta("signature_t", t)
			if t <= 0.0:
				h.revive()
				h.hp = maxi(1, roundi(h.max_hp * float(Armory.perk(h.hero_id, "revive_once", 0.3))))
				Fx.damage_number(h.get_parent(), h.global_position + Vector2(0, -28), Loc.t("Signed again!"), Color("ffe08a"))
		return
	if float(Armory.perk(h.hero_id, "revive_once", 0.0)) > 0.0:
		h.set_meta("signature_used", true)
		h.set_meta("signature_t", REVIVE_DELAY)


# ---------------------------------------------------------------- enemies inflicting them

## An enemy's hit landed on a hero: roll its "inflict" from data/enemies.json.
static func struck(enemy: Node, hero: Node) -> void:
	if enemy != null:
		struck_kind(Journal.kind_of(enemy), hero)


## The same, for a hit from something an enemy of this kind threw (a Spitter's glob).
static func struck_kind(kind: String, hero: Node) -> void:
	if hero == null or not hero is Hero or (hero as Hero).dead:
		return
	var inf := inflict_of(kind)
	if inf.is_empty() or randf() >= float(inf.get("chance", 0.0)):
		return
	apply(hero, str(inf.get("status", "")), float(inf.get("time", 4.0)))


## What a kind inflicts: data/enemies.json "inflict" (the Auditor, a boss without an entry there, Erases).
static func inflict_of(kind: String) -> Dictionary:
	if kind == "auditor":
		return {"status": "erase", "chance": 0.35, "time": 4.0}
	return EnemyKinds.kind(kind).get("inflict", {})


## What an enemy kind inflicts, for the codex and the briefing: "Erase (35%)", or "".
static func inflict_text(kind: String) -> String:
	var inf := inflict_of(kind)
	if inf.is_empty():
		return ""
	return "%s (%d%%)" % [name_of(str(inf.get("status", ""))), int(round(float(inf.get("chance", 0.0)) * 100.0))]


# ---------------------------------------------------------------- thrown items

## Throws a field item from the hero you control. Returns how many enemies it caught (-1: nothing in range).
static func throw_item(it: Dictionary, thrower: Hero) -> int:
	var th: Dictionary = it.get("throw", {})
	var center := thrower.global_position
	if not th.get("self", false):
		var target := nearest_enemy(thrower, float(it.get("range", 160)))
		if target == null:
			return -1
		center = target.global_position
	var r := float(th.get("radius", 40))
	var n := 0
	for e in thrower.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.dead or en.global_position.distance_to(center) > r:
			continue
		n += 1
		if int(th.get("damage", 0)) > 0:
			en.take_hit(int(th["damage"]), center, 60.0)
		if str(th.get("status", "")) != "" and not en.dead:
			apply(en, str(th["status"]), float(th.get("time", 3.0)), {"source": thrower})
	var col := color_of(str(th.get("status", "burn")))
	Fx.burst(thrower.get_parent(), center + Vector2(0, -6), [col, col.lightened(0.5), Color.WHITE], 22, r * 1.6)
	if thrower.party:
		thrower.party.shake(3.0)
	Audio.sfx("swing", 0.6, -2.0)
	return n


static func nearest_enemy(h: Hero, max_dist: float) -> Enemy:
	var best: Enemy = null
	var best_d := max_dist
	for e in h.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.dead:
			continue
		var d := en.global_position.distance_to(h.global_position)
		if d < best_d:
			best_d = d
			best = en
	return best


# ---------------------------------------------------------------- drawing

## Little shapes over an actor's head, one per status, each its own silhouette (drop, flame, stars,
## torn square; boons: up-arrow, shield, chevrons, candle flame). top: y of the row.
static func draw_marks(ci: CanvasItem, t: Node, top: float) -> void:
	var list := active(t)
	if list.is_empty():
		return
	var x := -float(list.size() - 1) * 4.5
	var tm := Time.get_ticks_msec() / 1000.0
	for a in list:
		var id: String = a[0]
		var c := Vector2(x, top)
		var col := color_of(id)
		var blink := float(a[1]) < 1.5 and not Access.reduce_flashing and int(tm * 8.0) % 2 == 0
		if blink:
			col.a = 0.4
		ci.draw_circle(c, 4.0, Color(0.06, 0.05, 0.08, 0.75 * col.a))
		match id:
			"poison":  # a drop
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(2, 0), c + Vector2(0, 2.5), c + Vector2(-2, 0)]), col)
			"burn":  # a flame
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3.5), c + Vector2(2.2, 1), c + Vector2(0, 2.5), c + Vector2(-2.2, 1), c + Vector2(-0.6, -0.8)]), col)
			"stun":  # three stars
				for k in 3:
					var ang := tm * 5.0 + k * TAU / 3.0
					ci.draw_rect(Rect2(c + Vector2(cos(ang), sin(ang)) * 2.4 - Vector2(0.5, 0.5), Vector2(1.2, 1.2)), col)
			"erase":  # a torn white square, struck through
				ci.draw_rect(Rect2(c - Vector2(2.2, 2.2), Vector2(4.4, 4.4)), col, false, 1.0)
				ci.draw_line(c + Vector2(-2.5, 2.5), c + Vector2(2.5, -2.5), Color(0.9, 0.2, 0.25, col.a), 1.0)
			"might":  # an up arrow
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(2.5, 0), c + Vector2(-2.5, 0)]), col)
				ci.draw_rect(Rect2(c + Vector2(-0.8, 0), Vector2(1.6, 2.5)), col)
			"guard":  # a shield
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-2.5, -2.5), c + Vector2(2.5, -2.5), c + Vector2(2, 1), c + Vector2(0, 3), c + Vector2(-2, 1)]), col)
			"haste":  # chevrons
				ci.draw_polyline(PackedVector2Array([c + Vector2(-2.5, -2), c + Vector2(-0.5, 0), c + Vector2(-2.5, 2)]), col, 1.0)
				ci.draw_polyline(PackedVector2Array([c + Vector2(0.5, -2), c + Vector2(2.5, 0), c + Vector2(0.5, 2)]), col, 1.0)
			"ward":  # a candle
				ci.draw_rect(Rect2(c + Vector2(-1, -0.5), Vector2(2, 3)), Color(0.95, 0.92, 0.85, col.a))
				ci.draw_circle(c + Vector2(0, -2), 1.2, col)
		x += 9.0


## Status icons with their seconds left, in a row from pos (the party plates).
static func draw_icons(ci: CanvasItem, t: Node, pos: Vector2, size := 10.0) -> void:
	var x := pos.x
	var font := ThemeDB.fallback_font
	for a in active(t):
		var id: String = a[0]
		var r := Rect2(Vector2(x, pos.y), Vector2(size, size))
		ci.draw_rect(r.grow(1), Color(0.05, 0.04, 0.07, 0.85))
		if not UiSkin.draw_icon(ci, "status_" + id, r):
			ci.draw_rect(r, color_of(id))
		ci.draw_rect(r.grow(1), color_of(id), false, 1.0)
		ci.draw_string(font, Vector2(x + size + 2, pos.y + size - 1), str(ceili(float(a[1]))), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), color_of(id))
		x += size + 12.0
