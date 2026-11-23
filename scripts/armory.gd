class_name Armory
extends RefCounted
## Items, Forge and Market (issue #112): forge materials, the town stores behind the satchel, the
## satchel's size and packing, the Forge's jobs, the Market's rotating stock, and the perks of
## build-defining trinkets. Data: data/materials.json, data/forge.json, data/market.json, plus the
## gear (data/gear.json) and field items (data/items.json) it works with.
##
## State is saved inside the party's progress, Empire.progress["armory"]:
##   {"mats": {material: n},            materials in the town stores
##    "stores": {item: n},              field items kept in town (the satchel is Empire.satchel)
##    "pack": {item: n},                what the player packs into the satchel before each mission
##    "jobs": [{"result", "kind", "hero", "from", "makes", "done"}],   Forge work, done at dawn on day "done"
##    "upgrades": [id],                 satchel upgrades made at the Forge
##    "market": {"seed": int, "rotation": int, "bought": {stall: n}}}

const MATERIALS_FILE := "res://data/materials.json"
const FORGE_FILE := "res://data/forge.json"
const MARKET_FILE := "res://data/market.json"
## The region whose materials and gear each tier stands for (tiers 2 and 3 are the starting region's).
const TIER_REGIONS := {4: ["abbey"], 5: ["causeway"], 6: ["coast", "spire"]}

static var _mats := {}
static var _forge := {}
static var _market := {}


static func _load(path: String) -> Dictionary:
	var parsed = Loc.load_json(path)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func mats_data() -> Dictionary:
	if _mats.is_empty():
		_mats = _load(MATERIALS_FILE)
	return _mats


static func forge_data() -> Dictionary:
	if _forge.is_empty():
		_forge = _load(FORGE_FILE)
	return _forge


static func market_data() -> Dictionary:
	if _market.is_empty():
		_market = _load(MARKET_FILE)
	return _market


# ---------------------------------------------------------------- state

static func state() -> Dictionary:
	var p := Progress.state()
	if typeof(p.get("armory")) != TYPE_DICTIONARY or (p["armory"] as Dictionary).is_empty():
		p["armory"] = fresh()
	return p["armory"]


static func fresh() -> Dictionary:
	var pack := {}
	var start := Satchel.start_stock()
	for k in start:
		if int(start[k]) > 0:
			pack[k] = int(start[k])
	return {"mats": {}, "stores": {}, "pack": pack, "jobs": [], "upgrades": [],
		"market": {"seed": randi() % 1000000, "rotation": -1, "bought": {}}}


## Cleans up a saved armory dictionary: unknown materials, items, recipes and upgrades are dropped.
static func clean(d) -> Dictionary:
	var out := fresh()
	if typeof(d) != TYPE_DICTIONARY or (d as Dictionary).is_empty():
		return out
	for k in _dict(d.get("mats")):
		if is_mat(k) and int(d["mats"][k]) > 0:
			out["mats"][k] = int(d["mats"][k])
	for k in _dict(d.get("stores")):
		if not Satchel.item(k).is_empty() and int(d["stores"][k]) > 0:
			out["stores"][k] = int(d["stores"][k])
	if typeof(d.get("pack")) == TYPE_DICTIONARY:
		out["pack"] = {}
		for k in d["pack"]:
			if not Satchel.item(k).is_empty() and int(d["pack"][k]) > 0:
				out["pack"][k] = mini(int(d["pack"][k]), carry(k))
	for j in (d.get("jobs", []) if typeof(d.get("jobs")) == TYPE_ARRAY else []):
		if typeof(j) == TYPE_DICTIONARY and _result_known(str(j.get("result", ""))):
			out["jobs"].append({"result": str(j["result"]), "kind": str(j.get("kind", "gear")), "hero": str(j.get("hero", "")),
				"from": str(j.get("from", "")), "makes": maxi(int(j.get("makes", 1)), 1), "done": int(j.get("done", 0))})
	for u in (d.get("upgrades", []) if typeof(d.get("upgrades")) == TYPE_ARRAY else []):
		if satchel_upgrades().has(str(u)) and not str(u) in out["upgrades"]:
			out["upgrades"].append(str(u))
	var m := _dict(d.get("market"))
	if not m.is_empty():
		out["market"] = {"seed": int(m.get("seed", out["market"]["seed"])), "rotation": int(m.get("rotation", -1)), "bought": {}}
		for k in _dict(m.get("bought")):
			out["market"]["bought"][str(k)] = int(m["bought"][k])
	return out


static func _dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func _result_known(id: String) -> bool:
	return not Progress.item(id).is_empty() or not Satchel.item(id).is_empty() or satchel_upgrades().has(id)


# ---------------------------------------------------------------- materials

static func materials() -> Dictionary:
	return mats_data().get("materials", {})


static func is_mat(id: String) -> bool:
	return materials().has(id)


static func mat(id: String) -> Dictionary:
	return materials().get(id, {})


static func mat_name(id: String) -> String:
	return str(mat(id).get("name", id))


static func mat_count(id: String) -> int:
	return int(state()["mats"].get(id, 0))


static func add_mat(id: String, n := 1) -> void:
	if not is_mat(id) or n <= 0:
		return
	state()["mats"][id] = mat_count(id) + n


static func has_mats(need: Dictionary) -> bool:
	for k in need:
		if mat_count(k) < int(need[k]):
			return false
	return true


static func take_mats(need: Dictionary) -> bool:
	if not has_mats(need):
		return false
	for k in need:
		state()["mats"][k] = mat_count(k) - int(need[k])
		if int(state()["mats"][k]) <= 0:
			state()["mats"].erase(k)
	return true


## "3 Scrap Iron, 2 Blank Pith".
static func mats_text(need: Dictionary) -> String:
	var parts := []
	for k in need:
		parts.append("%d %s" % [int(need[k]), mat_name(k)])
	return ", ".join(parts)


## What one kill drops: the kind's own table, plus the region's when the mission is outside the
## Brack Marches or the kind has none (so a chapter's new enemies drop its materials). {id: n}
static func roll_mats(kind: String, mission: Dictionary) -> Dictionary:
	var out := {}
	var own: Dictionary = mats_data().get("enemies", {}).get(kind, {})
	_roll_table(own, out)
	var p := Empire.territory().find(str(mission.get("province", "")))
	var region := str(p.get("region", ""))
	if region != "" and (own.is_empty() or region != "marches"):
		_roll_table(mats_data().get("regions", {}).get(region, {}), out)
	return out


static func _roll_table(t: Dictionary, out: Dictionary) -> void:
	if t.is_empty() or randf() >= float(t.get("chance", 0.0)):
		return
	var id := _weighted(t.get("table", {}), randi())
	if id != "":
		out[id] = int(out.get(id, 0)) + randi_range(1, maxi(int(t.get("most", 1)), 1))


static func _weighted(table: Dictionary, r: int) -> String:
	var total := 0
	for k in table:
		total += int(table[k])
	if total <= 0:
		return ""
	r = posmod(r, total)
	for k in table:
		r -= int(table[k])
		if r < 0:
			return k
	return ""


## Where a material comes from, for the Materials tab: "Tithe Enforcers, Concord raids".
static func sources(id: String) -> Array:
	var out := []
	var en: Dictionary = mats_data().get("enemies", {})
	for kind in en:
		if (en[kind].get("table", {}) as Dictionary).has(id):
			out.append(_kind_plural(kind))
	var mt = Loc.load_json("res://data/mission_types.json")
	if typeof(mt) == TYPE_DICTIONARY:
		var fs: Dictionary = mt.get("raid", {}).get("factions", {})
		for fid in fs:
			if (fs[fid].get("cache", {}) as Dictionary).has(id):
				out.append(Loc.t("%s raids") % Empire.faction(fid).get("short", fid.capitalize()))
		if (mt.get("salvage", {}).get("pile", {}) as Dictionary).has(id):
			out.append(Loc.t("Salvage piles"))
	var rg: Dictionary = mats_data().get("regions", {})
	for rid in rg:
		if (rg[rid].get("table", {}) as Dictionary).has(id) and rid != "marches":
			out.append(Loc.t("anything in %s") % Empire.territory().region(rid).get("name", rid))
	if _market_sells_mats() and region_ok(str(mat(id).get("region", ""))):
		out.append(Loc.t("the Market"))
	return out


static func _kind_plural(kind: String) -> String:
	if BossFight.BOSSES.has(kind):
		return Loc.t(str(BossFight.BOSSES[kind]["plural"]))
	return str(EnemyKinds.kind(kind).get("plural", kind.capitalize()))


## Every recipe a material goes into (result ids), for the Materials tab and the tests.
static func uses(id: String) -> Array:
	var out := []
	for r in all_recipes():
		if (r["mats"] as Dictionary).has(id) and not r["result"] in out:
			out.append(r["result"])
	return out


static func region_ok(rid: String) -> bool:
	return rid == "" or rid == "marches" or Empire.region_open(rid)


# ---------------------------------------------------------------- stores and the satchel

static func stored(id: String) -> int:
	return int(state()["stores"].get(id, 0))


static func store(id: String, n := 1) -> void:
	if Satchel.item(id).is_empty() or n <= 0:
		return
	state()["stores"][id] = stored(id) + n


static func unstore(id: String, n: int) -> int:
	var take := mini(n, stored(id))
	if take > 0:
		state()["stores"][id] = stored(id) - take
		if int(state()["stores"][id]) <= 0:
			state()["stores"].erase(id)
	return take


static func satchel_upgrades() -> Dictionary:
	return market_data().get("satchel", {}).get("upgrades", {})


static func has_upgrade(id: String) -> bool:
	return id in state()["upgrades"]


## The satchel's total size: base plus every upgrade made at the Forge.
static func satchel_slots() -> int:
	var n := int(market_data().get("satchel", {}).get("base", 10))
	for u in state()["upgrades"]:
		n += int(satchel_upgrades().get(u, {}).get("slots", 0))
	return n


static func carry(id: String) -> int:
	return int(Satchel.item(id).get("carry", 3))


static func pack_of(id: String) -> int:
	return int(state()["pack"].get(id, 0))


static func pack_total(skip := "") -> int:
	var n := 0
	for k in state()["pack"]:
		if k != skip:
			n += int(state()["pack"][k])
	return n


static func satchel_total() -> int:
	var n := 0
	for k in Empire.satchel:
		n += int(Empire.satchel[k])
	return n


## Most of this item that can be packed now: its carry limit, and what room the satchel has left.
static func pack_room(id: String) -> int:
	return mini(carry(id), satchel_slots() - pack_total(id))


## Sets how many of an item go out on every mission (clamped to what fits), then repacks.
static func set_pack(id: String, n: int) -> int:
	n = clampi(n, 0, maxi(pack_room(id), 0))
	if n <= 0:
		state()["pack"].erase(id)
	else:
		state()["pack"][id] = n
	restock(false)
	return n


## Repacks the satchel from the stores: anything over what you packed goes back to the stores, then
## each item is filled up to its pack, from free rations first (after a mission, up to the item's
## "start") and then from the stores.
static func restock(rations: bool) -> void:
	for id in Satchel.ids():
		var have := Satchel.count(id)
		var want := pack_of(id)
		if have > want:
			store(id, have - want)
			have = want
		if have < want and rations:
			var free := clampi(mini(int(Satchel.item(id).get("start", 0)), want) - have, 0, want - have)
			have += free
		if have < want:
			have += unstore(id, want - have)
		if have > 0:
			Empire.satchel[id] = have
		else:
			Empire.satchel.erase(id)


## Is there room in the satchel for one more of this item mid-mission?
static func satchel_room(id: String) -> bool:
	return Satchel.count(id) < carry(id) and satchel_total() < satchel_slots()


# ---------------------------------------------------------------- trinket perks

## Build-defining perks from what a hero wears (data/gear.json "perks"). Numbers add up, except
## tech_charge (multiplies) and last_stand (the strongest one); immune lists join.
static func perks(hero_id: String) -> Dictionary:
	var out := {}
	if hero_id == "" or not (Progress.state()["heroes"] as Dictionary).has(hero_id):
		return out
	var g: Dictionary = Progress.gear(hero_id)
	for slot in g:
		var pk: Dictionary = Progress.item(str(g[slot])).get("perks", {})
		for k in pk:
			match k:
				"immune":
					var list: Array = out.get("immune", [])
					for s in pk[k]:
						if not s in list:
							list.append(s)
					out["immune"] = list
				"tech_charge":
					out[k] = float(out.get(k, 1.0)) * float(pk[k])
				"last_stand":
					if float(pk[k].get("damage", 1.0)) > float(out.get(k, {}).get("damage", 0.0)):
						out[k] = pk[k]
				_:
					out[k] = float(out.get(k, 0.0)) + float(pk[k])
	return out


static func perk(hero_id: String, k: String, default = 0.0):
	return perks(hero_id).get(k, default)


## One line for a trinket's perks, for shops and the Gear screen.
static func perks_text(item_id: String) -> String:
	var pk: Dictionary = Progress.item(item_id).get("perks", {})
	var parts := []
	for k in pk:
		match k:
			"immune":
				parts.append(Loc.t("immune to %s") % Loc.t(" and ").join((pk[k] as Array).map(func(s): return Status.name_of(str(s)).to_lower())))
			"lifesteal":
				parts.append(Loc.t("heals %d%% of swing damage") % int(round(float(pk[k]) * 100.0)))
			"first_strike":
				parts.append(Loc.t("first hit on each enemy x%s") % str(snappedf(float(pk[k]), 0.1)))
			"ink_on_kill":
				parts.append(Loc.t("+%d Ink when an enemy falls nearby") % int(pk[k]))
			"gilt_on_kill":
				parts.append(Loc.t("+%d Gilt when an enemy falls nearby") % int(pk[k]))
			"thorns":
				parts.append(Loc.t("%d damage back to close attackers") % int(pk[k]))
			"last_stand":
				parts.append(Loc.t("below %d%% HP: x%s damage, +%d%% guard") % [int(round(float(pk[k].get("below", 0.3)) * 100.0)),
					str(snappedf(float(pk[k].get("damage", 1.0)), 0.1)), int(round(float(pk[k].get("guard", 0.0)) * 100.0))])
			"stun_on_full":
				parts.append(Loc.t("full-power swings stun %ss") % str(snappedf(float(pk[k]), 0.1)))
			"tech_charge":
				parts.append(Loc.t("techs charge %d%% faster") % int(round((1.0 - float(pk[k])) * 100.0)))
			"revive_once":
				parts.append(Loc.t("once a mission, back up at %d%% HP") % int(round(float(pk[k]) * 100.0)))
	return ", ".join(parts)


# ---------------------------------------------------------------- the Forge

static func forge_level() -> int:
	return Empire.level_of("forge")


static func forge_spec(level: int) -> Dictionary:
	var lv: Array = forge_data().get("levels", [])
	return lv[clampi(level, 1, lv.size()) - 1] if level > 0 and not lv.is_empty() else {"tier": 0, "benches": 0}


static func _working(staff: Array) -> Array:
	return staff.filter(func(r): return int(Empire.recruits.get(r, {}).get("injured", 0)) == 0)


static func craft_of(staff: Array) -> int:
	var n := 0
	for r in _working(staff):
		n += int(Empire.recruit(r).get("stats", {}).get("craft", 0))
	return n


## Days a job of base length takes with this much Craft at the Forge (at least one).
static func job_days(base: int, craft: int) -> int:
	var cb := float(forge_data().get("craft_base", 10))
	return maxi(1, ceili(float(base) * cb / (cb + float(craft))))


## What the Forge or the Market does at a level with a given staff (Empire.building_effect asks here).
static func building_effect(id: String, level: int, staff: Array) -> Dictionary:
	if id == "forge":
		var spec := forge_spec(level)
		if _working(staff).is_empty():
			return {"tier": 0, "benches": 0, "craft": 0, "text": Loc.t("Idle: needs a smith")}
		var craft := craft_of(staff)
		var cut := int(round((1.0 - float(forge_data().get("craft_base", 10)) / (float(forge_data().get("craft_base", 10)) + craft)) * 100.0))
		return {"tier": int(spec["tier"]), "benches": int(spec["benches"]), "craft": craft,
			"text": Loc.t("Works gear up to tier %d, %d job%s at a time, %d%% faster for Craft %d") % [int(spec["tier"]), int(spec["benches"]),
				"" if int(spec["benches"]) == 1 else "s", cut, craft]}
	if id == "market":
		if _working(staff).is_empty():
			return {"gilt": 0, "stalls": 0, "tier": 0, "discount": 0.0, "text": Loc.t("Idle: needs a trader")}
		var cfg: Dictionary = market_data().get("market", {})
		var inc: Dictionary = cfg.get("income", {})
		var charm := 0
		for r in _working(staff):
			charm += int(Empire.recruit(r).get("stats", {}).get("charm", 0))
		var held := 0
		for p in Empire.territory().provinces:
			if p["owner"] == "you":
				held += 1
		var gilt := int(inc.get("per_level", 2)) * level + charm / maxi(int(inc.get("charm_div", 2)), 1) + held / maxi(int(inc.get("provinces_per", 3)), 1)
		var disc := minf(float(cfg.get("discount", 0.01)) * charm, float(cfg.get("max_discount", 0.2)))
		var lv := market_spec(level)
		return {"gilt": gilt, "stalls": int(lv["stalls"]), "tier": int(lv["tier"]), "discount": disc,
			"text": Loc.t("+%d Gilt a day, %d stalls, prices -%d%%") % [gilt, int(lv["stalls"]), int(round(disc * 100.0))]}
	return {"text": ""}


static func forge_effect() -> Dictionary:
	return building_effect("forge", forge_level(), Empire.staff_of("forge"))


## A hero's weapon line, tier 1 first.
static func weapon_line(hero: String) -> Array:
	var out := []
	for k in Progress.item_ids():
		var it := Progress.item(k)
		if it.get("slot", "") == "weapon" and str(it.get("hero", "")) == hero:
			out.append(k)
	out.sort_custom(func(a, b): return int(Progress.item(a).get("tier", 1)) < int(Progress.item(b).get("tier", 1)))
	return out


## The weapon this hero carries now (or the best one in the bag), and what it upgrades to.
static func weapon_now(hero: String) -> String:
	return str(Progress.gear(hero).get("weapon", ""))


static func tier_of(id: String) -> int:
	var it := Progress.item(id)
	if not it.is_empty():
		return int(it.get("tier", 1))
	var r: Dictionary = forge_data().get("recipes", {}).get(id, {})
	return int(r.get("tier", 1))


## The upgrade recipe that turns `from` into the next weapon in its hero's line, or {}.
static func upgrade_recipe(from: String) -> Dictionary:
	var it := Progress.item(from)
	var hero := str(it.get("hero", ""))
	if hero == "":
		return {}
	var line := weapon_line(hero)
	var i := line.find(from)
	if i < 0 or i + 1 >= line.size():
		return {}
	var to: String = line[i + 1]
	var tier := tier_of(to)
	var spec: Dictionary = forge_data().get("weapon_upgrades", {}).get(str(tier), {})
	if spec.is_empty():
		return {}
	var need: Dictionary = (spec.get("mats", {}) as Dictionary).duplicate()
	var hm := str(forge_data().get("hero_mats", {}).get(hero, ""))
	if int(spec.get("hero_mat", 0)) > 0 and hm != "":
		need[hm] = int(need.get(hm, 0)) + int(spec["hero_mat"])
	return {"result": to, "kind": "weapon", "hero": hero, "from": from, "mats": need, "gilt": int(spec.get("gilt", 0)),
		"days": int(spec.get("days", 1)), "makes": 1, "tier": tier}


static func recipe(result: String) -> Dictionary:
	var r: Dictionary = forge_data().get("recipes", {}).get(result, {})
	if r.is_empty():
		return {}
	var kind := "gear"
	if not Satchel.item(result).is_empty():
		kind = "item"
	elif satchel_upgrades().has(result):
		kind = "upgrade"
	return {"result": result, "kind": kind, "hero": "", "from": "", "mats": r.get("mats", {}), "gilt": int(r.get("gilt", 0)),
		"days": int(r.get("days", 1)), "makes": int(r.get("makes", 1)), "tier": tier_of(result)}


## Every recipe: all weapon upgrades, then the listed ones.
static func all_recipes() -> Array:
	var out := []
	for hero in forge_data().get("hero_mats", {}):
		var line := weapon_line(hero)
		for i in range(line.size() - 1):
			var r := upgrade_recipe(line[i])
			if not r.is_empty():
				out.append(r)
	for k in forge_data().get("recipes", {}):
		out.append(recipe(k))
	return out


## The regions whose materials a recipe needs, still closed: [] when all are open.
static func closed_regions(r: Dictionary) -> Array:
	var out := []
	for k in r["mats"]:
		var rid := str(mat(k).get("region", ""))
		if not region_ok(rid) and not rid in out:
			out.append(rid)
	return out


static func region_name(rid: String) -> String:
	return str(Empire.territory().region(rid).get("name", rid.capitalize()))


static func jobs() -> Array:
	return state()["jobs"]


static func benches_free() -> int:
	return int(forge_effect().get("benches", 0)) - jobs().size()


## Is this weapon already on a Forge bench (for this hero)?
static func reserved(item_id: String) -> int:
	var n := 0
	for j in jobs():
		if j["from"] == item_id:
			n += 1
	return n


## Why this recipe can't be started right now, or "".
static func craft_blocker(r: Dictionary) -> String:
	if r.is_empty():
		return Loc.t("nothing to make")
	if forge_level() <= 0:
		return Loc.t("build the Forge first")
	var fe := forge_effect()
	if int(fe.get("benches", 0)) <= 0:
		return Loc.t("the Forge needs a smith")
	if int(r["tier"]) > int(fe.get("tier", 0)):
		return Loc.t("needs a level %d Forge") % _forge_level_for(int(r["tier"]))
	var closed := closed_regions(r)
	if not closed.is_empty():
		return Loc.t("needs materials from %s") % Loc.t(" and ").join(closed.map(func(x): return region_name(x)))
	if benches_free() <= 0:
		return Loc.t("every bench is busy")
	if r["kind"] == "upgrade" and (has_upgrade(r["result"]) or _queued(r["result"])):
		return Loc.t("already made")
	if r["kind"] == "weapon":
		if reserved(r["from"]) > 0:
			return Loc.t("already on a bench")
		if weapon_now(r["hero"]) != r["from"] and Progress.count(r["from"]) <= 0:
			return Loc.t("needs the %s") % Progress.item(r["from"]).get("name", r["from"])
	var short := []
	for k in r["mats"]:
		if mat_count(k) < int(r["mats"][k]):
			short.append(Loc.t("%d more %s") % [int(r["mats"][k]) - mat_count(k), mat_name(k)])
	if not short.is_empty():
		return Loc.t("needs ") + ", ".join(short)
	if int(Empire.res.get("gilt", 0)) < int(r["gilt"]):
		return Loc.t("not enough Gilt")
	return ""


static func _queued(result: String) -> bool:
	for j in jobs():
		if j["result"] == result:
			return true
	return false


static func _forge_level_for(tier: int) -> int:
	var lv: Array = forge_data().get("levels", [])
	for i in lv.size():
		if int(lv[i].get("tier", 0)) >= tier:
			return i + 1
	return lv.size()


## Days this recipe takes with the smiths at work now.
static func days_for(r: Dictionary) -> int:
	return job_days(int(r.get("days", 1)), int(forge_effect().get("craft", 0)))


## Puts a job on a bench: pays the Gilt and materials, takes a spare source weapon from the bag (a
## weapon the hero carries stays in their hands until the job is done).
static func start(r: Dictionary) -> bool:
	if craft_blocker(r) != "":
		return false
	take_mats(r["mats"])
	Empire.res["gilt"] = int(Empire.res["gilt"]) - int(r["gilt"])
	var from := ""
	if r["kind"] == "weapon":
		from = r["from"]
		if weapon_now(r["hero"]) != from:
			Progress.take_item(from)
			from = ""  # already in the smiths' hands
	jobs().append({"result": r["result"], "kind": r["kind"], "hero": r["hero"], "from": from, "makes": int(r["makes"]),
		"done": Empire.day + days_for(r)})
	return true


## Finishes every job due by today (called at dawn). Returns the finished jobs.
static func dawn() -> Array:
	var done := []
	var keep := []
	for j in jobs():
		if int(j["done"]) <= Empire.day:
			done.append(j)
		else:
			keep.append(j)
	state()["jobs"] = keep
	for j in done:
		_finish(j)
	if not done.is_empty():
		var names := done.map(func(j): return result_name(j["result"]) + ("" if int(j["makes"]) <= 1 else " x%d" % int(j["makes"])))
		Empire.notice.emit(Loc.t("The Forge finished: %s.") % ", ".join(names), false)
	return done


static func _finish(j: Dictionary) -> void:
	match str(j["kind"]):
		"weapon":
			var hero := str(j["hero"])
			var from := str(j["from"])
			var g: Dictionary = Progress.gear(hero)
			if from != "" and str(g.get("weapon", "")) == from:
				g["weapon"] = j["result"]  # swapped into the hero's hands
			elif from != "" and Progress.count(from) > 0:
				Progress.take_item(from)
				Progress.add_item(j["result"])
			else:
				Progress.add_item(j["result"])
		"item":
			store(j["result"], int(j["makes"]))
			restock(false)
		"upgrade":
			if not has_upgrade(j["result"]):
				state()["upgrades"].append(j["result"])
		_:
			Progress.add_item(j["result"])


static func result_name(id: String) -> String:
	if not Progress.item(id).is_empty():
		return str(Progress.item(id)["name"])
	if not Satchel.item(id).is_empty():
		return str(Satchel.item(id).get("name", id))
	return str(satchel_upgrades().get(id, {}).get("name", id))


static func result_blurb(id: String) -> String:
	if not Progress.item(id).is_empty():
		return str(Progress.item(id).get("blurb", ""))
	if not Satchel.item(id).is_empty():
		return str(Satchel.item(id).get("desc", ""))
	return str(satchel_upgrades().get(id, {}).get("blurb", ""))


## "in 2 days" / "at dawn" for a job.
static func job_eta(j: Dictionary) -> String:
	var d := int(j["done"]) - Empire.day
	return Loc.t("at dawn") if d <= 1 else Loc.t("in %d days") % d


# ---------------------------------------------------------------- the Market

static func market_level() -> int:
	return Empire.level_of("market")


static func market_spec(level: int) -> Dictionary:
	var lv: Array = market_data().get("market", {}).get("levels", [])
	return lv[clampi(level, 1, lv.size()) - 1] if level > 0 and not lv.is_empty() else {"stalls": 0, "tier": 0}


static func market_effect() -> Dictionary:
	return building_effect("market", market_level(), Empire.staff_of("market"))


static func _market_sells_mats() -> bool:
	return int(market_effect().get("stalls", 0)) > 0


static func rotation() -> int:
	return Empire.day / maxi(int(market_data().get("market", {}).get("rotation", 3)), 1)


## Days until the stock changes.
static func days_to_rotation() -> int:
	var per := maxi(int(market_data().get("market", {}).get("rotation", 3)), 1)
	return per - posmod(Empire.day, per)


## The highest gear tier the open map supports (tier 3 at the start; each region opens its tier).
static func open_tier() -> int:
	var t := 3
	for tier in TIER_REGIONS:
		for rid in TIER_REGIONS[tier]:
			if Empire.region_open(rid):
				t = maxi(t, int(tier))
	return t


## The Market's stalls this rotation: [{"kind": "items"|"materials"|"gear", "id", "qty"}]. Seeded by the
## campaign, the rotation and the Market's level, so a reload shows the same stock.
static func stock() -> Array:
	var me := market_effect()
	var stalls := int(me.get("stalls", 0))
	if stalls <= 0:
		return []
	var m: Dictionary = state()["market"]
	if int(m.get("rotation", -1)) != rotation():
		m["rotation"] = rotation()
		m["bought"] = {}
	var pool: Dictionary = market_data().get("market", {}).get("pool", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(m.get("seed", 0)), rotation(), market_level()])
	var cand := {"items": {}, "materials": {}, "gear": {}}
	var items: Dictionary = pool.get("items", {})
	for k in items:
		if not Satchel.item(k).is_empty():
			cand["items"][k] = int(items[k].get("weight", 1))
	for k in materials():
		var rid := str(mat(k).get("region", ""))
		if region_ok(rid) and int(mat(k).get("tier", 2)) <= int(me.get("tier", 2)):
			cand["materials"][k] = 4 if rid == "marches" else 3
	var top := mini(int(me.get("tier", 2)), open_tier())
	for k in Progress.item_ids():
		var it := Progress.item(k)
		if it.get("slot", "") != "weapon" and int(it.get("price", 0)) > 0 and int(it.get("tier", 1)) >= 2 and int(it.get("tier", 1)) <= top:
			cand["gear"][k] = 1 + (1 if it.has("perks") else 0)
	var out := []
	for i in stalls:
		var kinds := {}
		for kk in pool.get("kinds", {}):
			if not (cand[kk] as Dictionary).is_empty():
				kinds[kk] = int(pool["kinds"][kk])
		var kind := _weighted(kinds, rng.randi())
		if kind == "":
			break
		var id := _weighted(cand[kind], rng.randi())
		cand[kind].erase(id)  # one stall per thing
		var q: Array = items[id].get("qty", [1, 1]) if kind == "items" else pool.get(kind, {}).get("qty", [1, 1])
		out.append({"kind": kind, "id": id, "qty": rng.randi_range(int(q[0]), int(q[1]))})
	return out


static func stall_left(i: int, stall: Dictionary) -> int:
	return int(stall["qty"]) - int(state()["market"]["bought"].get(str(i), 0))


static func base_price(kind: String, id: String) -> int:
	match kind:
		"items":
			return int(Satchel.item(id).get("price", 10))
		"materials":
			return int(mat(id).get("value", 3)) * 2
	return int(Progress.item(id).get("price", 0))


static func price(kind: String, id: String) -> int:
	var cfg: Dictionary = market_data().get("market", {})
	var p := float(base_price(kind, id)) * float(cfg.get("markup", 1.15)) * (1.0 - float(market_effect().get("discount", 0.0)))
	return maxi(1, roundi(p))


static func stock_name(kind: String, id: String) -> String:
	match kind:
		"items":
			return str(Satchel.item(id).get("name", id))
		"materials":
			return mat_name(id)
	return str(Progress.item(id).get("name", id))


static func buy_blocker(i: int, stall: Dictionary) -> String:
	if stall_left(i, stall) <= 0:
		return Loc.t("sold out")
	if int(Empire.res.get("gilt", 0)) < price(stall["kind"], stall["id"]):
		return Loc.t("not enough Gilt")
	return ""


## Buys one from a stall: items go to the stores (and into the satchel if packed), materials to the
## stores, gear into the bag.
static func buy(i: int, stall: Dictionary) -> bool:
	if buy_blocker(i, stall) != "":
		return false
	Empire.res["gilt"] = int(Empire.res["gilt"]) - price(stall["kind"], stall["id"])
	var b: Dictionary = state()["market"]["bought"]
	b[str(i)] = int(b.get(str(i), 0)) + 1
	match str(stall["kind"]):
		"items":
			store(stall["id"])
			restock(false)
		"materials":
			add_mat(stall["id"])
		_:
			Progress.add_item(stall["id"])
	return true


static func sell_price_mat(id: String) -> int:
	return maxi(1, roundi(float(mat(id).get("value", 3)) * float(market_data().get("market", {}).get("sell_rate", 1.0))))


static func sell_mat(id: String) -> bool:
	if mat_count(id) <= 0 or market_level() <= 0 or int(market_effect().get("stalls", 0)) <= 0:
		return false
	take_mats({id: 1})
	Empire.res["gilt"] = int(Empire.res.get("gilt", 0)) + sell_price_mat(id)
	return true


# ---------------------------------------------------------------- mission pay

## Mission pickups and pay that are not resources: materials go to the stores, field items to the
## town stores. Returns true if it took care of the key.
static func bank(k: String, n: int) -> bool:
	if is_mat(k):
		add_mat(k, n)
		return true
	if not Satchel.item(k).is_empty():
		store(k, n)
		return true
	return false


## Names for pickups in a found/pay dictionary that are not resources: "2 Scrap Iron, Bitter Tonic".
static func found_text(d: Dictionary) -> String:
	var parts := []
	for k in d:
		var n := int(d[k])
		if n <= 0:
			continue
		if is_mat(k):
			parts.append("%d %s" % [n, mat_name(k)])
		elif not Satchel.item(k).is_empty():
			parts.append(("%d %s" % [n, Satchel.item(k).get("name", k)]) if n > 1 else str(Satchel.item(k).get("name", k)))
	return ", ".join(parts)
