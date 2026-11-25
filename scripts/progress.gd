class_name Progress
## Party progression (issue #15): XP and levels per field hero, gear (weapon, armor, trinket),
## the shared bag of spare gear, gear drops and the Hollowmark shop. Numbers live in data/gear.json.
##
## State is saved with the campaign in Empire.progress:
##   {"heroes": {id: {"xp": int, "level": int, "gear": {"weapon": id, "armor": id, "trinket": id},
##                    "weapon": {...}, "inks": {...}, "tech": id}},   (skill levels: scripts/skills.gd)
##    "bag": {item_id: count}}
## Base fighting stats come from data/heroes.json; stats() adds levels and gear on top.

const FILE := "res://data/gear.json"
const SLOTS := ["weapon", "armor", "trinket"]
const SLOT_NAMES := {"weapon": "Weapon", "armor": "Armor", "trinket": "Trinket"}
const STAT_ORDER := ["hp", "damage", "power_rate", "speed", "reach", "guard", "ink", "heal"]
const STAT_NAMES := {"hp": "Max HP", "damage": "Damage", "power_rate": "Gauge", "speed": "Speed", "reach": "Reach",
	"guard": "Guard", "ink": "Ink", "heal": "Poultice"}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f:
			var parsed = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func item(id: String) -> Dictionary:
	return data().get("items", {}).get(id, {})


static func item_ids() -> Array:
	return data().get("items", {}).keys()


# ---------------------------------------------------------------- state

static func state() -> Dictionary:
	if Empire.progress.is_empty():
		Empire.progress = fresh()
	return Empire.progress


static func fresh() -> Dictionary:
	var bag := {}
	var start: Dictionary = data().get("start", {}).get("bag", {})
	for k in start:
		bag[k] = int(start[k])
	return {"heroes": {}, "bag": bag}


## Cleans up a saved progress dictionary (unknown items and heroes are dropped).
static func from_save(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY or d.is_empty():
		return out
	out["bag"] = {}
	var bag: Dictionary = d.get("bag", {})
	for k in bag:
		if not item(k).is_empty() and int(bag[k]) > 0:
			out["bag"][k] = int(bag[k])
	out["armory"] = Armory.clean(d.get("armory", {}))  # materials, stores, satchel, Forge, Market (issue #112)
	var hs: Dictionary = d.get("heroes", {})
	for id in hs:
		var h: Dictionary = hs[id]
		var gear := {}
		var g: Dictionary = h.get("gear", {})
		for s in SLOTS:
			var iid := str(g.get(s, ""))
			if iid != "" and item(iid).get("slot", "") == s:
				gear[s] = iid
		out["heroes"][id] = {"xp": maxi(int(h.get("xp", 0)), 0), "level": clampi(int(h.get("level", 1)), 1, max_level()), "gear": gear}
		Skills.clean_into(h, out["heroes"][id])  # weapon and Ink skill levels (issue #24)
		SkillTree.clean_into(str(id), h, out["heroes"][id])  # skill tree (issue #25)
	return out


static func hero(id: String) -> Dictionary:
	var hs: Dictionary = state()["heroes"]
	if not hs.has(id):
		var gear := {}
		var w := str(data().get("start", {}).get("gear", {}).get(id, ""))
		if w != "":
			gear["weapon"] = w
		hs[id] = {"xp": 0, "level": 1, "gear": gear}
	return hs[id]


static func bag() -> Dictionary:
	return state()["bag"]


static func count(item_id: String) -> int:
	return int(bag().get(item_id, 0))


static func add_item(item_id: String, n := 1) -> void:
	if item(item_id).is_empty():
		return
	bag()[item_id] = count(item_id) + n


static func take_item(item_id: String, n := 1) -> bool:
	if count(item_id) < n:
		return false
	bag()[item_id] = count(item_id) - n
	if bag()[item_id] <= 0:
		bag().erase(item_id)
	return true


## Field heroes on the roster: Ash, then the rest of the party, then the bench.
static func field_ids() -> Array:
	var party := []
	var bench := []
	for id in Empire.roster_ids():
		if Empire.recruit(id).get("tier", "") != "field":
			continue
		if id == "ash":
			party.push_front(id)
		elif Empire.role_of(id) == "party":
			party.append(id)
		else:
			bench.append(id)
	return party + bench


# ---------------------------------------------------------------- levels

static func max_level() -> int:
	return int(data().get("levels", {}).get("max", 20))


## A field hero who joins late arrives seasoned (issue #138): at one level under the average of the
## three best field heroes already on the roster, and, once Chapter 2 has opened the Abbey, with the
## weapon one tier under what the open map's Forge works (tier 3 in Chapter 2, tier 4 in Chapter 3),
## so a single Forge upgrade brings them level with everyone else. Never lowers anything. Returns a
## line for the notice, or "" when nothing changed (Act 1 joiners close to the party, light recruits).
static func seasoned_join(id: String) -> String:
	if Empire.recruit(id).get("tier", "") != "field" or id == "ash":
		return ""
	var lv := []
	for rid in Empire.recruits:
		if rid != id and Empire.recruit(rid).get("tier", "") == "field":
			lv.append(level(rid))
	lv.sort()
	lv.reverse()
	var top := lv.slice(0, 3)
	var h := hero(id)
	var said := []
	if not top.is_empty():
		var sum := 0
		for v in top:
			sum += int(v)
		var want := mini(max_level(), int(floor(float(sum) / top.size())) - 1)
		if want > int(h["level"]):
			h["level"] = want
			h["xp"] = 0
			said.append(Loc.t("level %d") % want)
	var open := Armory.open_tier()
	if open >= 4:
		var line := Armory.weapon_line(id)
		var now := str(h["gear"].get("weapon", ""))
		var now_tier := int(item(now).get("tier", 1)) if now != "" else 0
		for w in line:
			if int(item(w).get("tier", 1)) == open - 1 and open - 1 > now_tier:
				h["gear"]["weapon"] = w
				said.append(item(w).get("name", w))
	if said.is_empty():
		return ""
	return Loc.t("%s has kept up on the road: %s.") % [Empire.short_name(id), Loc.list(said)]


static func level(id: String) -> int:
	return int(hero(id)["level"])


## XP needed to go from this level to the next (0 at max level).
static func xp_to_next(lvl: int) -> int:
	if lvl >= max_level():
		return 0
	var lv: Dictionary = data().get("levels", {})
	return int(round(float(lv.get("xp_base", 20)) * pow(float(lv.get("xp_growth", 1.3)), lvl - 1)))


## Total XP from level 1 to this level (the boss test and tests use it to set a party's level).
static func xp_to_reach(lvl: int) -> int:
	var total := 0
	for l in range(1, mini(lvl, max_level())):
		total += xp_to_next(l)
	return total


static func xp_fraction(id: String) -> float:
	var need := xp_to_next(level(id))
	return 1.0 if need <= 0 else clampf(float(hero(id)["xp"]) / need, 0.0, 1.0)


static func growth(id: String) -> Dictionary:
	var g: Dictionary = data().get("growth", {})
	return g.get(id, g.get("_default", {"hp": 5, "damage": 1.0, "ink": 2}))


## Gives XP to each hero. Returns the level-ups: [{"id", "level", "gains": {stat: amount}}].
static func award(ids: Array, amount: int) -> Array:
	var ups := []
	if amount <= 0:
		return ups
	for id in ids:
		var h := hero(id)
		var before := level_stats(id, int(h["level"]))
		h["xp"] = int(h["xp"]) + amount
		while int(h["level"]) < max_level() and int(h["xp"]) >= xp_to_next(int(h["level"])):
			h["xp"] = int(h["xp"]) - xp_to_next(int(h["level"]))
			h["level"] = int(h["level"]) + 1
			var after := level_stats(id, int(h["level"]))
			var gains := {}
			for k in after:
				var d := int(after[k]) - int(before.get(k, 0))
				if d != 0:
					gains[k] = d
			ups.append({"id": id, "level": int(h["level"]), "gains": gains})
			before = after
		if int(h["level"]) >= max_level():
			h["xp"] = 0
	return ups


## What levels alone add at this level (level 1 adds nothing).
static func level_stats(id: String, lvl: int) -> Dictionary:
	var g := growth(id)
	var out := {}
	for k in g:
		out[k] = int(floor(float(g[k]) * (lvl - 1)))
	return out


static func gains_text(gains: Dictionary) -> String:
	var parts := []
	for k in STAT_ORDER:
		if gains.has(k):
			parts.append("+%s %s" % [stat_value(k, gains[k]), Loc.t(STAT_NAMES[k])])
	return ", ".join(parts)


## XP a day for benched field heroes while the Barracks stands (called at dawn), plus weapon drill
## (issue #24, scripts/skills.gd).
static func dawn() -> void:
	var lvl := Empire.level_of("barracks")
	if lvl <= 0:
		return
	var bench := field_ids().filter(func(id): return Empire.role_of(id) != "party")
	award(bench, int(data().get("barracks_xp", 6)) * lvl)
	for up in Skills.drill_bench():
		var t := Skills.tech_at(up["id"], up["level"])
		Empire.notice.emit(Loc.t("Barracks drill: %s's %s skill reached %d and learned %s.") % [
			PartyPicker.short_of(up["id"]), Skills.weapon_name(up["id"]), up["level"], t.get("name", Loc.t("a new tech"))], false)


static func barracks_xp() -> int:
	return int(data().get("barracks_xp", 6)) * Empire.level_of("barracks")


# ---------------------------------------------------------------- gear and stats

static func gear(id: String) -> Dictionary:
	return hero(id)["gear"]


static func gear_stats(id: String, override := {}) -> Dictionary:
	var out := {}
	var g := gear(id).duplicate()
	for s in override:
		if override[s] == "":
			g.erase(s)
		else:
			g[s] = override[s]
	for s in g:
		var st: Dictionary = item(g[s]).get("stats", {})
		for k in st:
			out[k] = float(out.get(k, 0.0)) + float(st[k])
	return out


## Everything levels, gear and the skill tree add for this hero: {stat: amount}. override: {slot: item id or ""}
## shows what the hero would have with different gear (the Gear screen's preview).
static func bonus(id: String, override := {}) -> Dictionary:
	var out := {}
	var ls := level_stats(id, level(id))
	for k in ls:
		out[k] = float(ls[k])
	var gs := gear_stats(id, override)
	for k in gs:
		out[k] = float(out.get(k, 0.0)) + float(gs[k])
	var ts := SkillTree.stats(id)  # skill tree nodes (issue #25)
	for k in ts:
		out[k] = float(out.get(k, 0.0)) + float(ts[k])
	return out


## Full fighting stats: data/heroes.json base plus levels and gear.
static func stats(id: String, override := {}) -> Dictionary:
	var hd := PartyPicker.hero_data(id)
	var b := bonus(id, override)
	var heal: Dictionary = hd.get("heal", {})
	return {
		"level": level(id),
		"hp": int(hd.get("hp", 40)) + int(b.get("hp", 0)),
		"damage": int(hd.get("damage", 10)) + int(b.get("damage", 0)),
		"power_rate": float(hd.get("power_rate", 0.95)) * (1.0 + float(b.get("power_rate", 0.0))),
		"speed": float(hd.get("speed", 68)) + float(b.get("speed", 0)),
		"reach": float(hd.get("reach", 20)) + float(b.get("reach", 0)),
		"guard": clampf(float(b.get("guard", 0.0)), 0.0, 0.6),
		"ink": int(hd.get("ink", 12)) + int(b.get("ink", 0)),  # Ink pool for abilities (issue #7)
		"heal": (int(heal.get("amount", 0)) + int(b.get("heal", 0))) if not heal.is_empty() else 0,
	}


## Puts levels and gear onto a fresh hero (after PartyPicker.apply set the base stats).
static func apply_to(h: Hero) -> void:
	var b := bonus(h.hero_id)
	h.max_hp += int(b.get("hp", 0))
	h.hp = h.max_hp
	h.base_damage += int(b.get("damage", 0))
	h.power_rate *= 1.0 + float(b.get("power_rate", 0.0))
	h.move_speed += float(b.get("speed", 0))
	h.reach += float(b.get("reach", 0))
	h.guard = clampf(float(b.get("guard", 0.0)), 0.0, 0.6)
	if h.heal_every > 0.0:
		h.heal_amount += int(b.get("heal", 0))
	h.max_ink += float(b.get("ink", 0))
	h.ink = h.max_ink
	SkillTree.apply_perks(h)  # skill tree passives (issue #25)


## Moves a hero in the field from one set of stats to another (a level-up or a gear change
## mid-mission). before/after come from bonus().
static func apply_delta(h: Hero, before: Dictionary, after: Dictionary) -> void:
	var dhp := int(after.get("hp", 0)) - int(before.get("hp", 0))
	h.max_hp = maxi(1, h.max_hp + dhp)
	if not h.dead:
		h.hp = clampi(h.hp + maxi(dhp, 0), 1, h.max_hp)
	h.base_damage += int(after.get("damage", 0)) - int(before.get("damage", 0))
	h.power_rate *= (1.0 + float(after.get("power_rate", 0.0))) / (1.0 + float(before.get("power_rate", 0.0)))
	h.move_speed += float(after.get("speed", 0)) - float(before.get("speed", 0))
	h.reach += float(after.get("reach", 0)) - float(before.get("reach", 0))
	h.guard = clampf(h.guard + float(after.get("guard", 0.0)) - float(before.get("guard", 0.0)), 0.0, 0.6)
	if h.heal_every > 0.0:
		h.heal_amount += int(after.get("heal", 0)) - int(before.get("heal", 0))
	var dink := float(after.get("ink", 0)) - float(before.get("ink", 0))
	h.max_ink = maxf(0.0, h.max_ink + dink)
	h.ink = clampf(h.ink + maxf(dink, 0.0), 0.0, h.max_ink)


## Can this hero wear this item? "" if yes, else why not.
static func wear_blocker(id: String, item_id: String) -> String:
	var it := item(item_id)
	if it.is_empty():
		return Loc.t("no such item")
	if not it.get("slot", "") in SLOTS:
		return Loc.t("that is not gear")
	var owner := str(it.get("hero", ""))
	if owner != "" and owner != id:
		return Loc.t("only %s can use it") % PartyPicker.short_of(owner)
	return ""


## Items in the bag that fit this slot for this hero.
static func options(id: String, slot: String) -> Array:
	var out := []
	for k in bag():
		if item(k).get("slot", "") == slot and wear_blocker(id, k) == "":
			out.append(k)
	out.sort_custom(func(a, b): return int(item(a).get("price", 0)) < int(item(b).get("price", 0)))
	return out


## Puts an item from the bag on (or takes the slot off with item_id ""). The old one goes back in the bag.
static func equip(id: String, slot: String, item_id: String) -> bool:
	if item_id != "" and (wear_blocker(id, item_id) != "" or item(item_id)["slot"] != slot or count(item_id) <= 0):
		return false
	var g := gear(id)
	var old := str(g.get(slot, ""))
	if item_id != "":
		take_item(item_id)
		g[slot] = item_id
	else:
		g.erase(slot)
	if old != "":
		add_item(old)
	return true


static func stat_value(k: String, v) -> String:
	match k:
		"power_rate", "guard":
			return "%d%%" % int(round(float(v) * 100.0))
		_:
			return str(int(round(float(v))))


## "+3 Damage, +10% Gauge" for an item's stats.
static func item_text(item_id: String) -> String:
	var it := item(item_id)
	var parts := []
	var st: Dictionary = it.get("stats", {})
	for k in STAT_ORDER:
		if st.has(k):
			var v := float(st[k])
			parts.append("%s%s %s" % ["+" if v > 0 else "-", stat_value(k, absf(v)), Loc.t(STAT_NAMES[k])])
	var perks := Armory.perks_text(item_id)  # build-defining trinkets (issue #112)
	if perks != "":
		parts.append(perks)
	return ", ".join(parts) if not parts.is_empty() else Loc.t("No bonus")


# ---------------------------------------------------------------- drops and shop

## Rolls for an item drop when an enemy falls. Returns an item id or "".
static func roll_drop(m: Dictionary) -> String:
	var d: Dictionary = m.get("drops", data().get("drops", {}))
	if randf() >= float(d.get("chance", 0.0)):
		return ""
	var table: Dictionary = d.get("table", {})
	var total := 0
	for k in table:
		total += int(table[k])
	if total <= 0:
		return ""
	var r := randi() % total
	for k in table:
		r -= int(table[k])
		if r < 0:
			return k
	return ""


static func mission_xp(m: Dictionary) -> int:
	return int(m.get("xp", data().get("mission_xp", 12)))


## What the shop sells right now (needs research for the better stock).
static func shop_stock() -> Array:
	var out := []
	for k in item_ids():
		var it := item(k)
		if not it.get("shop", true) or int(it.get("price", 0)) <= 0:
			continue
		out.append(k)
	var order := {"weapon": 0, "armor": 1, "trinket": 2}
	out.sort_custom(func(a, b):
		var sa: int = order.get(item(a)["slot"], 9)
		var sb: int = order.get(item(b)["slot"], 9)
		return sa < sb if sa != sb else int(item(a)["price"]) < int(item(b)["price"]))
	return out


static func shop_blocker(item_id: String) -> String:
	var it := item(item_id)
	var need := str(it.get("needs", ""))
	if need != "" and not Empire.has_research(need):
		return Loc.t("needs %s (research)") % Empire.research_node(need).get("name", need)
	if int(Empire.res.get("gilt", 0)) < int(it.get("price", 0)):
		return Loc.t("not enough Gilt")
	return ""


static func buy(item_id: String) -> bool:
	if shop_blocker(item_id) != "":
		return false
	Empire.res["gilt"] = int(Empire.res["gilt"]) - int(item(item_id)["price"])
	add_item(item_id)
	return true


static func sell_price(item_id: String) -> int:
	return int(item(item_id).get("price", 0)) / 2


static func sell(item_id: String) -> bool:
	if count(item_id) <= Armory.reserved(item_id) or sell_price(item_id) <= 0:  # not while the Forge is reworking it (#112)
		return false
	take_item(item_id)
	Empire.res["gilt"] = int(Empire.res["gilt"]) + sell_price(item_id)
	return true


## Who is wearing one of these (for the shop's "worn by" note).
static func worn_by(item_id: String) -> Array:
	var out := []
	for id in state()["heroes"]:
		if item_id in (gear(id) as Dictionary).values():
			out.append(id)
	return out
