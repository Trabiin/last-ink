extends "res://tests/test_case.gd"
## Items, Forge and Market (issue #112): the data is complete and cross-referenced (every material has a
## source and a use, every result and icon exists), the satchel keeps its capacity rules, the Forge crafts
## and upgrades over days, the Market's stock is stable per rotation and buying works, status effects
## take hold, cure and expire, trinket perks apply, and the Forge & Market screen opens in town and at the
## Command Table.

const HUB := "res://scenes/hub.tscn"
const COMMAND := "res://scenes/command.tscn"
const MAIN := "res://scenes/main.tscn"

var Empire: Node


func before_each() -> void:
	Empire = autoload("Empire")
	runner.clear_scratch()
	Empire.reset()


func after_each() -> void:
	tree.paused = false
	Engine.time_scale = 1.0


func _icon(id: String) -> bool:
	return ResourceLoader.exists("res://assets/icons/%s.png" % id)


## The Forge built at a level with Pell as smith; the Market with Tobble as trader.
func _build(id: String, level: int, who: String) -> void:
	Empire.buildings[id] = level
	Empire.recruits[who] = {"role": "staff", "target": id, "injured": 0}


# ------------------------------------------------------------------ data

func test_consumables_are_complete() -> void:
	var ids := Satchel.ids()
	check(ids.size() >= 10 and ids.size() <= 14, "about a dozen consumables (%d)" % ids.size())
	var kinds := {}
	for id in ids:
		var it := Satchel.item(id)
		check(str(it.get("name", "")) != "" and str(it.get("desc", "")).length() > 20, "%s has a name and a blurb" % id)
		check(int(it.get("carry", 0)) > 0, "%s has a carry limit" % id)
		check(int(it.get("price", 0)) > 0, "%s has a price" % id)
		check(_icon(id), "%s has an icon" % id)
		kinds[str(it.get("target"))] = true
		for c in it.get("cures", []):
			check(c == "all" or c in Status.AILMENTS, "%s cures a real status (%s)" % [id, c])
		if it.has("buff"):
			check(str(it["buff"]["id"]) in Status.BOONS, "%s buffs with a real boon" % id)
		if it.has("throw"):
			var st := str(it["throw"].get("status", ""))
			check(st == "" or st in Status.AILMENTS, "%s throws a real status" % id)
		check(Armory.recipe(id).is_empty() == false or it.get("stall", false) or id in ["tonic", "salts", "draught"],
			"%s can be made or bought" % id)
	for k in ["hurt", "downed", "cure", "ink", "party", "hero", "throw"]:
		check(kinds.has(k), "a consumable of kind %s" % k)
	var ward := false
	for id in ids:
		if str(Satchel.item(id).get("buff", {}).get("id", "")) == "ward":
			ward = true
	check(ward, "there is a Blank ward")


func test_every_material_has_a_source_a_use_and_an_icon() -> void:
	var mats := Armory.materials()
	check(mats.size() >= 12, "materials exist (%d)" % mats.size())
	for k in mats:
		var m: Dictionary = mats[k]
		check(str(m.get("name", "")) != "" and str(m.get("blurb", "")).length() > 20, "%s has a name and blurb" % k)
		check(not Armory.sources(k).is_empty(), "%s drops somewhere" % k)
		check(not Armory.uses(k).is_empty(), "%s goes into something" % k)
		check(_icon(k), "%s has an icon" % k)
	var md := Armory.mats_data()
	for kind in md.get("enemies", {}):
		check(BossFight.BOSSES.has(kind) or not EnemyKinds.kind(kind).is_empty(), "drop table for a real enemy (%s)" % kind)
		for k in md["enemies"][kind].get("table", {}):
			check(Armory.is_mat(k), "%s drops a real material (%s)" % [kind, k])


func test_every_recipe_is_well_formed() -> void:
	var all := Armory.all_recipes()
	check(all.size() > 40, "plenty of recipes (%d)" % all.size())
	for r in all:
		var id := str(r["result"])
		check(Armory.result_name(id) != id, "%s has a name" % id)
		check(Armory.result_blurb(id).length() > 20, "%s has a blurb" % id)
		check(_icon(id), "%s has an icon" % id)
		check(not (r["mats"] as Dictionary).is_empty(), "%s needs materials" % id)
		for k in r["mats"]:
			check(Armory.is_mat(k), "%s needs a real material (%s)" % [id, k])
		check(int(r["tier"]) >= 1 and int(r["tier"]) <= 6, "%s has a tier" % id)
		check(int(r["days"]) >= 1, "%s takes time" % id)


func test_weapon_lines_have_six_tiers_and_gear_has_icons() -> void:
	for hero in Armory.forge_data().get("hero_mats", {}):
		var line := Armory.weapon_line(hero)
		check_eq(line.size(), 6, "%s has six weapons" % hero)
		for i in line.size():
			check_eq(Armory.tier_of(line[i]), i + 1, "%s tier %d" % [hero, i + 1])
		check(Armory.is_mat(str(Armory.forge_data()["hero_mats"][hero])), "%s has a signature material" % hero)
	var armour := 0
	var perked := 0
	for k in Progress.item_ids():
		var it := Progress.item(k)
		check(_icon(k), "%s has an icon" % k)
		if it.get("slot", "") == "armor":
			armour += 1
		if it.has("perks"):
			perked += 1
			check(Armory.perks_text(k) != "", "%s describes its perk" % k)
	check(armour >= 10, "armour across the tiers (%d)" % armour)
	check(perked >= 10, "build-defining trinkets (%d)" % perked)


func test_buildings_and_status_icons() -> void:
	for b in ["forge", "market"]:
		var bd: Dictionary = Empire.building_data.get(b, {})
		check_eq((bd.get("levels", []) as Array).size(), 3, "%s has 3 levels" % b)
		check(_icon(b), "%s has an icon" % b)
		for lv in [1, 2, 3]:
			check(ResourceLoader.exists("res://assets/buildings/%s_%d.png" % [b, lv]), "%s level %d sprite" % [b, lv])
	for s in Status.AILMENTS + Status.BOONS:
		check(_icon("status_" + s), "status %s has an icon" % s)
	check_eq(str(Empire.building_data["forge"].get("stat", "")), "craft", "the Forge is staffed with Craft")
	check_eq(str(Empire.building_data["market"].get("stat", "")), "charm", "the Market is staffed with Charm")


# ------------------------------------------------------------------ the satchel

func test_satchel_capacity_and_restock() -> void:
	check_eq(Armory.satchel_slots(), 10, "a fresh satchel holds 10")
	check_eq(Armory.pack_of("tonic"), 3, "starts packed with 3 Tonics")
	Armory.store("wormwood", 5)
	check_eq(Armory.set_pack("wormwood", 9), 4, "packing stops at the carry limit")
	check_eq(Satchel.count("wormwood"), 4, "packed Wormwood comes out of the stores at once")
	check_eq(Armory.stored("wormwood"), 1, "one left in the stores")
	Armory.set_pack("tonic", 6)
	check(Armory.pack_total() <= Armory.satchel_slots(), "the pack fits the satchel (%d)" % Armory.pack_total())
	# After a mission: used items come back as free rations first, then from the stores.
	Armory.store("tonic", 2)
	Empire.satchel["tonic"] = 0
	Empire.satchel["wormwood"] = 1
	Satchel.restock(true)
	check_eq(Satchel.count("tonic"), Armory.pack_of("tonic"), "Tonics topped up to the pack")
	check_eq(Satchel.count("wormwood"), 2, "used Wormwood only comes back from the stores")
	check_eq(Armory.stored("wormwood"), 0, "and the stores are empty")
	check(Armory.satchel_total() <= Armory.satchel_slots(), "the satchel never overflows")
	# Mid-mission pickups respect the room left.
	Empire.satchel = {"tonic": 6, "wormwood": 4}
	check(not Satchel.add("tonic"), "a full stack takes no more")
	Armory.state()["upgrades"].append("oilcloth_satchel")
	check_eq(Armory.satchel_slots(), 13, "an upgrade adds slots")
	# Unpacking sends extras back to the stores at the next restock.
	var before := Armory.stored("wormwood")
	Armory.set_pack("wormwood", 0)
	check_eq(Satchel.count("wormwood"), 0, "unpacked items leave the satchel")
	check_eq(Armory.stored("wormwood"), before + 4, "and wait in the stores")


# ------------------------------------------------------------------ the Forge

func test_forge_needs_a_building_and_a_smith() -> void:
	var r := Armory.recipe("marrow_broth")
	check_eq(Armory.craft_blocker(r), "build the Forge first", "no Forge, no crafting")
	Empire.buildings["forge"] = 1
	check_eq(Armory.craft_blocker(r), "the Forge needs a smith", "an empty Forge does nothing")
	_build("forge", 1, "pell")
	check(Armory.craft_blocker(r).begins_with("needs "), "short of materials says what is missing")
	check(Armory.forge_effect()["text"].contains("tier 3"), "level 1 works up to tier 3")
	var hi := Armory.upgrade_recipe(Armory.weapon_line("ash")[3])  # tier 5
	check(Armory.craft_blocker(hi) != "", "tier 5 is out of reach at level 1")


func test_forge_crafts_supplies_over_days() -> void:
	_build("forge", 1, "pell")
	var r := Armory.recipe("marrow_broth")
	for k in r["mats"]:
		Armory.add_mat(k, int(r["mats"][k]))
	Empire.res["gilt"] = 100
	check_eq(Armory.craft_blocker(r), "", "ready to start")
	check(Armory.start(r), "the job starts")
	check_eq(int(Empire.res["gilt"]), 100 - int(r["gilt"]), "Gilt paid")
	for k in r["mats"]:
		check_eq(Armory.mat_count(k), 0, "%s used up" % k)
	check_eq(Armory.benches_free(), 0, "the bench is busy")
	check_eq(Armory.craft_blocker(Armory.recipe("wormwood")), "every bench is busy", "one job at a time at level 1")
	Empire.day = int(Armory.jobs()[0]["done"])
	var done := Armory.dawn()
	check_eq(done.size(), 1, "the job finishes at dawn")
	check_eq(Armory.stored("marrow_broth"), int(r["makes"]), "the broth goes to the stores")
	check(Armory.jobs().is_empty(), "the bench is free again")


func test_forge_upgrades_a_carried_weapon() -> void:
	_build("forge", 1, "pell")
	var from := Armory.weapon_now("ash")
	if not check(from != "", "Ash carries a weapon"):
		return
	var r := Armory.upgrade_recipe(from)
	check(not r.is_empty(), "the weapon has an upgrade")
	for k in r["mats"]:
		Armory.add_mat(k, int(r["mats"][k]))
	Empire.res["gilt"] = 500
	check(Armory.start(r), "the upgrade starts")
	check_eq(Armory.weapon_now("ash"), from, "Ash keeps the old weapon while it is worked")
	check(Armory.craft_blocker(r) != "", "the same weapon can't go on two benches")
	Empire.day = int(Armory.jobs()[0]["done"])
	Armory.dawn()
	check_eq(Armory.weapon_now("ash"), str(r["result"]), "the new weapon is in Ash's hands")
	check_eq(Armory.tier_of(Armory.weapon_now("ash")), Armory.tier_of(from) + 1, "one tier up")


func test_forge_job_survives_a_save() -> void:
	_build("forge", 1, "pell")
	var r := Armory.recipe("wormwood")
	for k in r["mats"]:
		Armory.add_mat(k, int(r["mats"][k]))
	Armory.add_mat("scrap_iron", 4)
	Empire.res["gilt"] = 100
	Armory.start(r)
	var d: Dictionary = JSON.parse_string(JSON.stringify(Empire.to_dict()))
	Empire.reset()
	Empire.from_dict(d)
	check_eq(Armory.jobs().size(), 1, "the job is still on the bench")
	check_eq(Armory.mat_count("scrap_iron"), 4, "materials survive")


# ------------------------------------------------------------------ the Market

func test_market_income_and_stable_stock() -> void:
	check(Armory.stock().is_empty(), "no Market, no stalls")
	_build("market", 1, "tobble")
	var me := Armory.market_effect()
	check(int(me["gilt"]) > 0, "the Market earns Gilt")
	check(float(me["discount"]) > 0.0, "Charm brings prices down")
	var s1 := Armory.stock()
	check_eq(s1.size(), 4, "level 1 has 4 stalls")
	check_eq(JSON.stringify(Armory.stock()), JSON.stringify(s1), "the same stock on a second look")
	var seen := {}
	for st in s1:
		check(not seen.has(st["id"]), "one stall per thing")
		seen[st["id"]] = true
		check(st["kind"] in ["items", "materials", "gear"], "a real stall kind")
		if st["kind"] == "gear":
			check(Armory.tier_of(st["id"]) <= 2, "level 1 sells only low-tier gear")
	Empire.day += 3 * 4
	var later := []
	for i in 4:
		Empire.day += 3
		later.append(JSON.stringify(Armory.stock()))
	check(later.any(func(x): return x != JSON.stringify(s1)), "the stock rotates")
	check(Empire.ledger().any(func(l): return str(l.get("label", "")) == "Market stalls"), "the Market shows in the ledger")


func test_market_buying_and_selling() -> void:
	_build("market", 3, "tobble")
	Empire.res["gilt"] = 5000
	var st: Array = Armory.stock()
	check_eq(st.size(), 8, "level 3 has 8 stalls")
	for i in st.size():
		var stall: Dictionary = st[i]
		var left := Armory.stall_left(i, stall)
		var gilt := int(Empire.res["gilt"])
		check(Armory.buy(i, stall), "buy from stall %d" % i)
		check_eq(int(Empire.res["gilt"]), gilt - Armory.price(stall["kind"], stall["id"]), "paid for stall %d" % i)
		check_eq(Armory.stall_left(i, stall), left - 1, "stall %d has one fewer" % i)
	Armory.add_mat("scrap_iron", 2)
	var g := int(Empire.res["gilt"])
	check(Armory.sell_mat("scrap_iron"), "materials sell at the Market")
	check_eq(int(Empire.res["gilt"]), g + Armory.sell_price_mat("scrap_iron"), "for their value")
	Empire.res["gilt"] = 0
	check_eq(Armory.buy_blocker(0, st[0]) if Armory.stall_left(0, st[0]) > 0 else "not enough Gilt", "not enough Gilt", "no Gilt, no sale")


# ------------------------------------------------------------------ status effects and perks

func _mission() -> Node:
	Empire.reset()
	for id in ["bran", "ninefingers"]:
		Empire.recruits[id] = {"role": "party", "target": "", "injured": 0}
	Dialogue.mark_seen("talk:meadow_intro")
	Empire.active_mission = Missions.find("meadow_patrol").duplicate(true)
	return await goto(MAIN, 20)


func test_statuses_take_hold_cure_and_expire() -> void:
	var main := await _mission()
	if not check(main != null and main.leader != null, "mission running"):
		return
	for e in tree.get_nodes_in_group("enemies"):
		e.queue_free()
	await frames(2)
	var h: Hero = main.leader
	h.invuln_t = 999.0
	check(Status.apply(h, "poison", 3.0), "poison takes hold")
	check(Status.has(h, "poison"), "and shows")
	check_eq(Status.active(h)[0][0], "poison", "listed as active")
	h.hp = 3
	for i in 60:
		Status.tick(h, 0.1)
	check(h.hp >= 1, "poison never kills a hero")
	check(not Status.has(h, "poison"), "and wears off")
	Status.apply(h, "burn", 10.0)
	Satchel.add("wormwood")
	check(Satchel.use("wormwood", h, main.heroes) != "", "Wormwood can be used")
	check(not Status.has(h, "burn"), "Wormwood cures burn")
	check(not Status.apply(h, "poison", 5.0), "and wards off poison for a while")
	# Stun holds a hero still, then a short immunity follows.
	Status.apply(h, "stun", 0.3)
	check(Status.tick(h, 0.1), "a stunned hero is held")
	for i in 5:
		Status.tick(h, 0.1)
	check(not Status.apply(h, "stun", 1.0), "no stun-lock right after")
	# Erase blocks abilities and techs until cleared.
	Status.apply(h, "erase", 4.0)
	if not h.abilities.is_empty():
		check_eq(Abilities.blocker(h, 0), "erased", "Erased heroes can't use abilities")
	Satchel.add("fresh_ink")
	Satchel.use("fresh_ink", h, main.heroes)
	check(not Status.has(h, "erase"), "Fresh Ink clears Erase")
	# Boons change numbers and undo themselves.
	var dmg := h.base_damage
	Satchel.add("gutter_gin")
	Satchel.use("gutter_gin", h, main.heroes)
	check(h.base_damage > dmg, "Gutter Gin raises damage")
	Status.clear_all(h)
	check_eq(h.base_damage, dmg, "and it comes back down")
	Status.apply(h, "ward", 5.0)
	check(not Status.apply(h, "erase", 3.0), "the ward keeps Erase off")


func test_trinket_perks_apply() -> void:
	Progress.add_item("wormwood_sachet")
	check(Progress.equip("bran", "trinket", "wormwood_sachet"), "Bran wears the Wormwood Sachet")
	check("poison" in (Armory.perk("bran", "immune", []) as Array), "the Wormwood Sachet makes Bran immune to poison")
	check_eq(Armory.perk("ash", "lifesteal", 0.0), 0.0, "Ash has no lifesteal without the locket")
	check(Status.inflict_text("enforcer") != "", "enemies that inflict say so")


# ------------------------------------------------------------------ the screen

func _walk(v: Control) -> void:
	for t in v.TABS:
		v.open(t)
		await frames(2)
		check(v.visible and v.tab == t, "%s tab opens" % t)
		check(not v.rows.is_empty(), "%s tab has rows" % t)
		for i in mini(v.rows.size(), 50):
			v.sel = i
			v.queue_redraw()
			await frames(1)
	v.close()
	await frames(2)


func test_screen_in_town_and_at_the_table() -> void:
	_build("forge", 2, "pell")
	_build("market", 2, "tobble")
	Armory.add_mat("scrap_iron", 6)
	Armory.store("wormwood", 2)
	var hub := await goto(HUB, 15)
	if not check(hub != null and hub.armory_view != null, "the hub has the Forge & Market screen"):
		return
	Input.action_press("armory")
	await frames(1)
	Input.action_release("armory")
	await frames(2)
	check(hub.armory_view.visible, "M opens it in town")
	check(not hub.leader.controlled, "Ash stands still while it is open")
	hub.armory_view.close()
	await frames(2)
	await _walk(hub.armory_view)
	var cmd := await goto(COMMAND, 15)
	if not check(cmd != null and cmd.armory_view != null, "the Command Table has it too"):
		return
	cmd._on_menu("armory")
	await frames(2)
	check(cmd.armory_view.visible, "the Command menu opens it")
	cmd.armory_view.close()
	await frames(2)
	await _walk(cmd.armory_view)
