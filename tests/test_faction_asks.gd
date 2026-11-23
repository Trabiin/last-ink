extends "res://tests/test_case.gd"
## Faction asks (issue #131): data/factions.json "asks", scripts/faction_asks.gd, the Diplomacy rows,
## the journal's Factions section and the save step 20261123_faction_asks.

const FIXTURE := "res://tests/fixtures/saves/20261123_faction_asks__table_day42_guild_pact.json"
const KINDS := ["expedition", "raid", "salvage", "fray", "lamp", "deliver", "shun"]
const REWARD_KEYS := ["standing", "gilt", "supplies", "ink", "insight", "renown", "mats", "boon", "recruit"]
const FAIL_KEYS := ["standing", "fine", "trouble", "hex"]

var Empire: Node
var Saves: Node


func before_each() -> void:
	Empire = autoload("Empire")
	Saves = autoload("Saves")
	Empire.reset()
	if Story.active() and not Missions.cleared(Story.BREAKOUT):
		Empire.missions_cleared.append(Story.BREAKOUT)  # the Command Table is running
	Empire.buildings["guildhall"] = 1


## Puts an ask on offer for its faction, whatever the dice say.
func _offer(id: String) -> String:
	var a := FactionAsks.ask(id)
	var fid: String = a["faction"]
	Empire.standing[fid] = maxi(Empire.standing_of(fid), Empire.tier_min(str(a.get("tier", "hostile"))))
	if a.has("below"):
		Empire.standing[fid] = mini(Empire.standing_of(fid), Empire.tier_min(str(a["below"])) - 1)
	check(FactionAsks.offer(fid, id), "%s could not be offered: %s" % [id, FactionAsks.offer_blocker(a)])
	return fid


func _dawn() -> void:
	Empire.day += 1
	Empire._advance_diplomacy()


# ---------------------------------------------------------------- data

func test_ask_data() -> void:
	var seen := {}
	for fid in Empire.faction_ids():
		var asks := FactionAsks.asks_of(fid)
		check(asks.size() >= 2, "%s: needs at least two asks, has %d" % [fid, asks.size()])
		for a in asks:
			var w := "factions.json ask " + str(a.get("id", "?"))
			check(not seen.has(a["id"]), "%s: id used twice" % w)
			seen[a["id"]] = true
			for k in ["name", "tier", "kind", "days", "text", "done_text", "fail_text", "reward", "fail"]:
				check(a.has(k), "%s: missing %s" % [w, k])
			check(str(a.get("kind", "")) in KINDS, "%s: unknown kind %s" % [w, a.get("kind", "")])
			var tiers: Array = Empire.tier_data.map(func(t): return t["id"])
			check(str(a.get("tier", "")) in tiers, "%s: unknown tier" % w)
			check(not a.has("below") or str(a["below"]) in tiers, "%s: unknown below tier" % w)
			if a.has("below"):
				check(Empire.tier_rank(str(a["below"])) > Empire.tier_rank(str(a["tier"])), "%s: below must be above tier" % w)
			check(int(a.get("days", 0)) >= 3, "%s: deadline too short to act on" % w)
			check(int(a.get("refuse", 0)) <= 0, "%s: refusing should never pay" % w)
			for k in a.get("reward", {}):
				check(k in REWARD_KEYS, "%s: unknown reward %s" % [w, k])
			check(int(a["reward"].get("standing", 0)) > 0, "%s: doing it should win standing" % w)
			for k in a.get("fail", {}):
				check(k in FAIL_KEYS, "%s: unknown consequence %s" % [w, k])
			check(int(a["fail"].get("standing", 0)) < int(a.get("refuse", 0)), "%s: failing should cost more than refusing" % w)
			for m in a["reward"].get("mats", {}):
				check(Armory.is_mat(str(m)), "%s: unknown material %s" % [w, m])
			if a["reward"].has("recruit"):
				check(Empire.recruit_data.has(str(a["reward"]["recruit"])), "%s: unknown recruit" % w)
			if a["reward"].has("boon"):
				check(str(a["reward"]["boon"].get("kind", "")) in ["intel", "truce", "ward"], "%s: unknown boon" % w)
			match str(a["kind"]):
				"expedition":
					var j: Dictionary = Empire.job(str(a.get("job", "")))
					check(not j.is_empty(), "%s: job %s missing from expeditions.json" % [w, a.get("job", "")])
					check(str(j.get("ask", "")) == a["id"], "%s: its job must name it under \"ask\"" % w)
				"raid":
					check(Empire.faction_data.has(str(a.get("target", ""))) and a["target"] != fid, "%s: bad raid target" % w)
					check(MissionTypes.data()["raid"]["factions"].has(str(a["target"])), "%s: target can't be raided" % w)
				"shun":
					check(Empire.faction_data.has(str(a.get("rival", ""))) and a["rival"] != fid, "%s: bad rival" % w)
				"deliver":
					check(not a.get("cost", {}).is_empty(), "%s: nothing to deliver" % w)
				"fray":
					check(int(a.get("max", 0)) > 10, "%s: needs a max Fray" % w)
	# Every request-only job belongs to a real ask, and is off the board until accepted.
	for jid in Empire.job_data:
		var aid = str(Empire.job_data[jid].get("ask", ""))
		if aid != "":
			check(not FactionAsks.ask(aid).is_empty(), "expedition %s names unknown ask %s" % [jid, aid])
			check(not jid in Empire.job_ids(), "expedition %s is on the board before its ask is accepted" % jid)


# ---------------------------------------------------------------- the flow

func test_offers_arrive_one_per_faction() -> void:
	for i in 12:
		_dawn()
	for fid in Empire.faction_ids():
		if not Journal.faction_known(fid):  # a faction under the fog never asks (the Abbey and Erasers before Chapter 2)
			continue
		var st: Dictionary = FactionAsks.state()
		check(st["offers"].has(fid) or st["active"].has(fid) or int(st["next"].get(fid, 0)) > Empire.day,
			"%s never asked anything in 12 days" % fid)
	var alerts := Alerts.inst().alerts.filter(func(a): return a["target"].get("view", "") == "diplomacy")
	check(not alerts.is_empty(), "an offer leaves an alert that goes to Diplomacy")


func test_refusing_and_ignoring_cost_standing() -> void:
	var fid := _offer("guild_dues")
	var before = Empire.standing_of(fid)
	check(FactionAsks.refuse(fid) != "", "refuse says something")
	check_eq(Empire.standing_of(fid), before - 3, "refusing costs its refuse standing")
	check(FactionAsks.offer_of(fid).is_empty(), "the offer is gone")
	check(FactionAsks.offer(fid, "guild_dues") == false, "not asked again straight away")
	# Ignored: the offer lapses after offer_days.
	var fid2 := _offer("coven_letters")
	var b2 = Empire.standing_of(fid2)
	for i in int(FactionAsks.rules()["offer_days"]):
		_dawn()
	check(FactionAsks.offer_of(fid2).is_empty(), "the offer lapsed")
	check(Empire.standing_of(fid2) <= b2 - 3, "silence counts as a no")


func test_deliver_ask_pays_and_grants_boon() -> void:
	var fid := _offer("concord_backtithe")
	check(FactionAsks.accept(fid) != "", "accepted")
	check(FactionAsks.offer_of(fid).is_empty() and not FactionAsks.active_of(fid).is_empty(), "now active")
	Empire.res["gilt"] = 0
	check(FactionAsks.deliver_blocker(fid) != "", "can't hand over without the coin")
	Empire.res["gilt"] = 100
	Empire.res["supplies"] = 50
	var before = Empire.standing_of(fid)
	check(FactionAsks.deliver(fid) != "", "handed over")
	check_eq(Empire.res["gilt"], 65, "back-tithe Gilt paid")
	check_eq(Empire.res["supplies"], 40, "back-tithe Supplies paid")
	check(Empire.standing_of(fid) >= before + 10, "standing reward")
	check(Empire.next_trouble_day >= Empire.day + 8, "truce boon holds trouble off")
	check(FactionAsks.active_of(fid).is_empty(), "done and gone")
	var rows := Journal.faction_quests().filter(func(r): return str(r["id"]).begins_with("ask_concord_backtithe"))
	check(rows.size() == 1 and rows[0]["state"] == "done", "journal shows it done")


func test_expedition_ask_opens_its_job_and_resolves() -> void:
	var fid := _offer("guild_cut")
	check(not "ask_guild_cut" in Empire.job_ids(), "off the board while only offered")
	FactionAsks.accept(fid)
	check("ask_guild_cut" in Empire.job_ids(), "on the board once accepted")
	var row: Array = Journal.faction_quests().filter(func(r): return r["id"] == "ask_guild_cut")
	check(row.size() == 1 and int(row[0]["days"]) == 6 and row[0]["target"].get("view", "") == "expeditions", "journal row with countdown and go-there")
	var gilt = int(Empire.res["gilt"])
	var lines := FactionAsks.on_expedition("ask_guild_cut", false)
	check(not lines.is_empty() and not FactionAsks.active_of(fid).is_empty(), "a failed run can be tried again")
	lines = FactionAsks.on_expedition("ask_guild_cut", true)
	check(not lines.is_empty() and FactionAsks.active_of(fid).is_empty(), "a good run completes it")
	check_eq(int(Empire.res["gilt"]), gilt + 35, "Gilt reward")
	check(not "ask_guild_cut" in Empire.job_ids(), "off the board again")


func test_expired_ask_hits_back() -> void:
	var fid := _offer("guild_cut")
	FactionAsks.accept(fid)
	var before = Empire.standing_of(fid)
	for i in 6:
		_dawn()
	check(FactionAsks.active_of(fid).is_empty(), "the deadline ended it")
	check(Empire.standing_of(fid) <= before - 6, "failing costs standing")
	check(FactionAsks.state()["log"].any(func(e): return e["id"] == "guild_cut" and e["outcome"] == "failed"), "logged as failed")


func test_squad_out_at_deadline_gets_to_finish() -> void:
	var fid := _offer("guild_cut")
	FactionAsks.accept(fid)
	Empire.expeditions.append({"job": "ask_guild_cut", "squad": ["bran"], "start": Empire.day, "finish": Empire.day + 99})
	for i in 7:
		_dawn()
	check(not FactionAsks.active_of(fid).is_empty(), "still waiting on the squad")
	FactionAsks.on_expedition("ask_guild_cut", true)
	check(FactionAsks.active_of(fid).is_empty(), "the squad's report settles it")


func test_raid_ask_resolves_on_a_raid() -> void:
	var fid := _offer("concord_audit")
	FactionAsks.accept(fid)
	var gallows = Empire.territory().find("gallows")
	var t := FactionAsks.target(fid)
	check(t.get("province", "") == "gallows", "go-there points at Guild land next to yours")
	var m := {"type": "raid", "faction": "guild", "province": "gallows", "id": "raid_gallows"}
	var dry := MissionTypes.apply(m, "success", true)
	check(dry.any(func(l): return str(l).contains("request is done")), "the results preview says so")
	check(not FactionAsks.active_of(fid).is_empty(), "a dry run changes nothing")
	MissionTypes.apply(m, "success")
	check(FactionAsks.active_of(fid).is_empty(), "the raid completed it")
	check(gallows["owner"] == "guild", "the raid did not change hands")


func test_salvage_ask_needs_the_right_place() -> void:
	var t = Empire.territory()
	var spot := ""
	for pid in FactionAsks.near_home("coven", true):
		if t.find(pid)["owner"] in ["you", "free"]:
			spot = pid
			break
	if not check(spot != "", "some land next to the woods"):
		return
	t.find(spot)["fray"] = 60
	t.find(spot)["owner"] = "free" if spot != "hollowmark" else "you"
	var fid := _offer("coven_hedgebooks")
	FactionAsks.accept(fid)
	MissionTypes.apply({"type": "salvage", "province": "saltreed" if spot != "saltreed" else "tithe", "id": "salvage_x"}, "success")
	if not "saltreed" in FactionAsks.near_home("coven", true):
		check(not FactionAsks.active_of(fid).is_empty(), "salvage far from the woods doesn't count")
	MissionTypes.apply({"type": "salvage", "province": spot, "id": "salvage_" + spot}, "success")
	check(FactionAsks.active_of(fid).is_empty(), "salvage next to the woods completes it")


func test_shun_ask_tears_up_and_watches_pacts() -> void:
	Empire.pacts.append("guild")
	var fid := _offer("coven_no_barges")
	FactionAsks.accept(fid)
	check(not "guild" in Empire.pacts, "accepting tears up the pact")
	check(not FactionAsks.pact_breaks("guild").is_empty(), "Diplomacy knows a new pact breaks it")
	Empire.pacts.append("guild")
	FactionAsks.check()
	check(FactionAsks.active_of(fid).is_empty(), "signing again breaks it at once")
	check(FactionAsks.state()["log"].any(func(e): return e["id"] == "coven_no_barges" and e["outcome"] == "failed"), "and it failed")


func test_fray_ask_holds_or_breaks() -> void:
	var near := FactionAsks.near_home("coven")
	if near.is_empty():  # make sure some of your land touches the woods
		Empire.territory().find("lampwick")["owner"] = "you"
		near = FactionAsks.near_home("coven")
	check(not near.is_empty(), "your land borders the Gutterwoods")
	for pid in near:
		Empire.territory().find(pid)["fray"] = 10
	var fid := _offer("coven_treeline")
	FactionAsks.accept(fid)
	Empire.territory().find(near[0])["fray"] = 60
	FactionAsks.check()
	check(FactionAsks.active_of(fid).is_empty(), "fraying past the line fails it")
	var hexed = Empire.fray_sources(Empire.territory().find(near[0])).any(func(s): return str(s[0]).contains("hex"))
	check(hexed, "the Coven's hex shows in Fray sources")


func test_lamp_ask_brings_a_recruit() -> void:
	var near := FactionAsks.near_home("coven")
	if near.is_empty():
		Empire.territory().find("lampwick")["owner"] = "you"
		near = FactionAsks.near_home("coven")
	var fid := _offer("coven_lamp")
	FactionAsks.accept(fid)
	Empire.lamps[near[0]] = 1
	FactionAsks.check()
	check(FactionAsks.active_of(fid).is_empty(), "the lamp completed it")
	check(Empire.is_visitor("biscuits"), "Mr. Biscuits waits at the gate")


# ---------------------------------------------------------------- screens and saves

func test_diplomacy_rows_and_actions() -> void:
	var cmd := await goto("res://scenes/command.tscn", 15)
	if not check(cmd != null and cmd.diplomacy_view != null, "command table has diplomacy"):
		return
	var fid := _offer("guild_dues")
	var view: Control = cmd.diplomacy_view
	view.open()
	check(view._rows[view.sel]["kind"] == "offer", "opens on the waiting request")
	var kinds: Array = view._rows.filter(func(r): return r["faction"] == fid).map(func(r): return r["kind"])
	check("offer" in kinds and "refuse" in kinds, "accept and refuse rows")
	view._pick(view.sel)
	check(not FactionAsks.active_of(fid).is_empty(), "Enter on the request accepts it")
	check(view._rows.any(func(r): return r["kind"] == "ask" and r["faction"] == fid), "the accepted request is listed")
	await frames(2)  # draws (and scrolls) without errors
	FactionAsks._fail(fid, "test")  # ends while the screen is open
	await frames(2)
	check(not view._rows.any(func(r): return r["kind"] == "ask" and r["faction"] == fid), "the list follows the change")
	view.close()


func test_save_round_trip() -> void:
	var fid := _offer("guild_cut")
	FactionAsks.accept(fid)
	_offer("concord_backtithe")
	var d: Dictionary = JSON.parse_string(JSON.stringify(Empire.to_dict()))
	Empire.from_dict(d)
	check(FactionAsks.is_active("guild_cut"), "accepted ask kept")
	check_eq(str(FactionAsks.offer_of("concord").get("id", "")), "concord_backtithe", "offer kept")
	check("ask_guild_cut" in Empire.job_ids(), "its job is still on the board")


func test_old_save_gets_asks_spread_out() -> void:
	var r: Dictionary = Saves.parse(FileAccess.get_file_as_string(FIXTURE))
	check_eq(r["status"], Saves.GOOD, "fixture loads")
	var e: Dictionary = r["data"]["empire"]
	check(e.has("asks"), "the step adds asks")
	var days: Array = e["asks"]["next"].values()
	days.sort()
	check_eq(days, [44, 45, 46], "first asks spread over the next days")
	Empire.from_dict(e)
	check(FactionAsks.state()["offers"].is_empty() and FactionAsks.state()["active"].is_empty(), "nothing asked yet")
	check("guild" in Empire.pacts, "the old pact survives")
