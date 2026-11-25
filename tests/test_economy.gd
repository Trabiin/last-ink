extends "res://tests/test_case.gd"
## The economy sim (issue #35, tools/economy_sim.gd and tools/economy_meter.gd): its books balance,
## it plays exactly like the balance bot, and a steady player's economy stays inside its bands for
## 90 days (nothing starved for upkeep, nothing piling up with nothing to buy).

const Bot := preload("res://tools/balance_bot.gd")
const Meter := preload("res://tools/economy_meter.gd")
const Sim := preload("res://tools/economy_sim.gd")


func _bank() -> Dictionary:
	var out := {}
	for k in Meter.KEYS:
		out[k] = int(Empire.res.get(k, 0))
	return out


func _run(bot, days: int) -> void:
	seed(1000)
	bot.start()
	Empire.rng.seed = 1000


func test_the_books_balance() -> void:
	var bot = Meter.new("steady")
	_run(bot, 0)
	var start := _bank()
	for d in 30:
		bot.play_day()
	var end := _bank()
	for k in Meter.KEYS:
		var total := 0
		for ph in bot.flows:
			for src in bot.flows[ph].get(k, {}):
				total += int(bot.flows[ph][k][src])
		check_eq(total, int(end[k]) - int(start[k]), "every %s is accounted for" % k)
	check(bot.flows.has("act1"), "Act 1 has flows")
	check(bot.flows["act1"]["gilt"].has("Missions"), "missions pay Gilt")
	check(bot.flows["act1"]["supplies"].has("Dawn: Upkeep"), "the dawn ledger lines are named")
	check(int(bot.phase_days.get("act1", 0)) > 0, "days are counted per chapter")


func test_the_meter_plays_like_the_bot() -> void:
	var plain = Bot.new("steady")
	_run(plain, 0)
	for d in 25:
		plain.play_day()
	var a := _bank()
	var metered = Meter.new("steady")
	_run(metered, 0)
	for d in 25:
		metered.play_day()
	# Two runs of the plain bot in one process already differ by a few coins (state the reset keeps
	# between campaigns), so the banks only have to agree closely; the decisions must match.
	var b := _bank()
	for k in a:
		check(absi(int(b[k]) - int(a[k])) <= 6, "%s close to the plain bot's (%d vs %d)" % [k, b[k], a[k]])
	check_eq(metered.events.map(func(e): return e[1]), plain.events.map(func(e): return e[1]), "same decisions")


func test_a_steady_economy_stays_in_its_bands() -> void:
	var bot = Meter.new("steady")
	_run(bot, 0)
	for d in 90:
		bot.play_day()
	var flags: Array = Sim.flags_for("steady", 0, bot, Sim._story_last_day(bot))
	check(flags.is_empty(), "no economy flags in 90 days: %s" % str(flags))
	check_eq(int(bot.short_days.get("ink", 0)) + int(bot.short_days.get("gilt", 0)), 0, "upkeep always paid")


func test_flags_name_the_cause() -> void:
	var bot = Meter.new("steady")
	bot.log = []
	for d in 40:
		bot.log.append({"day": d + 1, "gilt": 100, "supplies": 100, "ink": 2, "insight": 100 + d * 20, "hollowmark": true})
	bot.short_days = {"ink": 9}
	bot.capped = {"insight": 12}
	var flags: Array = Sim.flags_for("steady", 0, bot, 5)
	var text := "\n".join(flags)
	check(text.contains("Ink ran short for upkeep on 9 days"), "unpaid upkeep is a flag")
	check(text.contains("Ink was at or near empty"), "an empty store is a flag")
	check(text.contains("Insight piles up") and text.contains("nothing left to study from day 12"), "a pile says what ran out")
	check(text.contains("past the written story"), "a pile past the story says so")
