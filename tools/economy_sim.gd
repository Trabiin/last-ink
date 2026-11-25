extends SceneTree
## Economy sim (issue #35): runs the Command layer for N days with the metered balance bot
## (tools/economy_meter.gd, which plays exactly like tools/balance_bot.gd) and writes where every
## Gilt, Supply, Ink, Insight and Renown came from and went, chapter by chapter, so a runaway or a
## starved resource shows up with its cause next to it.
##
##   godot --headless --audio-driver Dummy --path . -s tools/economy_sim.gd -- [days] [policies] [seeds] [out_dir]
##   godot ... -s tools/economy_sim.gd -- 120 steady,casual,rush 3 /tmp/economy
##
## Writes <out_dir>/economy.md and prints it. tools/balance_sim.gd is the overall report (story pace,
## levels, Fray, land); this one is the money. Flags are explained in docs/BALANCE.md ("Economy sim").
## Never touches the player's saves.

const KEYS := ["gilt", "supplies", "ink", "insight", "renown"]
const NAMES := {"gilt": "Gilt", "supplies": "Supplies", "ink": "Ink", "insight": "Insight", "renown": "Renown"}
const PHASES := ["act1", "ch2", "ch3", "ch4", "ch5", "ch6", "after"]
const PHASE_NAMES := {"act1": "Act 1", "ch2": "Chapter 2", "ch3": "Chapter 3", "ch4": "Chapter 4", "ch5": "Chapter 5",
	"ch6": "Chapter 6", "after": "After the last chapter"}
## Banks past these, still climbing over the last 20 days, read as "nothing worth buying" (same bands as
## tools/balance_sim.gd, plus Renown, which only gates the story).
const PILE := {"gilt": 1500, "supplies": 600, "ink": 120, "insight": 150}
const SHORT_DAYS := 5  # unpaid upkeep days (level 4+ buildings working a tier down) before it is a flag
const DRY_SHARE := 0.4  # a resource at or near zero this share of the days after day 20 = starved

var Meter: GDScript
var _frame := 0
var days := 120
var policies := ["steady", "casual", "rush"]
var seeds := 3
var out_dir := "user://economy/"


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		days = int(a[0])
	if a.size() > 1:
		policies = Array(a[1].split(",", false))
	if a.size() > 2:
		seeds = int(a[2])
	if a.size() > 3:
		out_dir = a[3].trim_suffix("/") + "/"


func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:  # autoloads exist from the first frame on
		_run()
		quit(0)
	return false


func _run() -> void:
	Meter = load("res://tools/economy_meter.gd")
	var Empire = root.get_node("Empire")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var saves = root.get_node_or_null("Saves")
	if saves != null:
		saves.dir = "user://balance_scratch/"
	var lines := ["# Economy sim", "", "%d days per run, %d seed(s) per policy. Amounts are per day, averaged over every seed's days in that chapter." % [days, seeds], ""]
	var flags := []
	var runs := ["| Policy | Seed | Ch2 day | Ch3 day | Story last moved | Nothing to study from | Builders done from | Unpaid upkeep days (Gilt / Supplies / Ink) | Gilt end (peak) | Supplies end | Ink end | Insight end |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|"]
	var sections := []
	for pol in policies:
		var agg := {}  # phase -> res -> src -> total over every seed
		var agg_days := {}
		for s in seeds:
			var bot = Meter.new(pol)
			seed(1000 + s)
			bot.start()
			Empire.rng.seed = 1000 + s
			var peak := {}
			for d in days:
				bot.play_day()
				for k in KEYS:
					peak[k] = maxi(int(peak.get(k, 0)), int(Empire.res.get(k, 0)))
				if not bot.log[-1]["hollowmark"]:
					break
			for ph in bot.flows:
				agg[ph] = agg.get(ph, {})
				agg_days[ph] = int(agg_days.get(ph, 0)) + int(bot.phase_days.get(ph, 0))
				for k in bot.flows[ph]:
					agg[ph][k] = agg[ph].get(k, {})
					for src in bot.flows[ph][k]:
						agg[ph][k][src] = int(agg[ph][k].get(src, 0)) + int(bot.flows[ph][k][src])
			var story_day := _story_last_day(bot)
			var last: Dictionary = bot.log[-1]
			runs.append("| %s | %d | %s | %s | %d | %s | %s | %d / %d / %d | %d (%d) | %d | %d | %d |" % [pol, s, _d(bot.phase_first.get("ch2", -1)),
				_d(bot.phase_first.get("ch3", -1)), story_day, _d(bot.capped.get("insight", -1)), _d(bot.capped.get("gilt", -1)),
				int(bot.short_days.get("gilt", 0)), int(bot.short_days.get("supplies", 0)), int(bot.short_days.get("ink", 0)),
				last["gilt"], int(peak.get("gilt", 0)), last["supplies"], last["ink"], last["insight"]])
			flags.append_array(flags_for(pol, s, bot, story_day))
		sections.append_array(_policy_section(pol, agg, agg_days))
	lines.append("## Flags")
	lines.append("")
	if flags.is_empty():
		lines.append("None.")
	for f in flags:
		lines.append("- " + f)
	lines.append("")
	lines.append("## Runs")
	lines.append("")
	lines.append("Story last moved: the last day a story conversation played (past it the sim is playing on with no story left to reach). Nothing to study from / Builders done from: the first day every study or building level the map had open was done, so that resource had nothing left to buy until a chapter opens more.")
	lines.append("")
	lines.append_array(runs)
	lines.append("")
	lines.append_array(sections)
	var text := "\n".join(lines) + "\n"
	var f := FileAccess.open(out_dir + "economy.md", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(text)


func _d(v: int) -> String:
	return str(v) if v >= 0 else "-"


static func _story_last_day(bot) -> int:
	var out := 0
	for e in bot.events:
		if str(e[1]).begins_with("story: "):
			out = maxi(out, int(e[0]))
	return out


## Per chapter, per resource: every source and sink a day, biggest first.
func _policy_section(pol: String, agg: Dictionary, agg_days: Dictionary) -> Array:
	var out := ["## %s" % pol, ""]
	for ph in PHASES:
		if not agg.has(ph) or int(agg_days.get(ph, 0)) <= 0:
			continue
		var n := float(agg_days[ph])
		out.append("### %s (%d days per run on average)" % [PHASE_NAMES[ph], int(round(n / seeds))])
		out.append("")
		out.append("| Resource | Net a day | Comes from (a day) | Goes to (a day) |")
		out.append("|---|---|---|---|")
		for k in KEYS:
			var by: Dictionary = agg[ph].get(k, {})
			if by.is_empty():
				continue
			var gains := []
			var spends := []
			var net := 0.0
			for src in by:
				var v := float(by[src]) / n
				net += v
				if absf(v) < 0.05:
					continue
				if v > 0:
					gains.append([src, v])
				else:
					spends.append([src, v])
			gains.sort_custom(func(a, b): return a[1] > b[1])
			spends.sort_custom(func(a, b): return a[1] < b[1])
			out.append("| %s | %+.1f | %s | %s |" % [NAMES[k], net, _list(gains), _list(spends)])
		out.append("")
	return out


func _list(items: Array) -> String:
	if items.is_empty():
		return "-"
	return ", ".join(items.slice(0, 6).map(func(e): return "%s %+.1f" % [e[0], e[1]]))


## The economy's guard rails in words a designer can act on. Shared with tests/test_economy.gd.
static func flags_for(pol: String, s: int, bot, story_day: int) -> Array:
	var out := []
	var tag := "%s/s%d" % [pol, s]
	var log: Array = bot.log
	if pol == "idle" or log.size() < 30:
		return out
	# Starved: upkeep that went unpaid (level 4 and 5 buildings fall back to level 3).
	for k in ["gilt", "ink"]:
		var n := int(bot.short_days.get(k, 0))
		if n > SHORT_DAYS:
			out.append("%s: %s ran short for upkeep on %d days (level 4 and 5 buildings worked as level 3)." % [tag, NAMES[k], n])
	# Starved: a resource sitting at or near zero most days (whatever buys it is stuck).
	for k in ["gilt", "ink", "insight"]:
		var dry := 0
		var counted := 0
		for snap in log.slice(20):
			counted += 1
			if int(snap.get(k, 0)) <= (5 if k != "gilt" else int(bot.RESERVE["gilt"]) / 2):
				dry += 1
		if counted > 0 and float(dry) / counted >= DRY_SHARE:
			out.append("%s: %s was at or near empty on %d of %d days after day 20." % [tag, NAMES[k], dry, counted])
	# Runaway: a bank past its band and still climbing over the last 20 days.
	var tail := log.slice(maxi(0, log.size() - 20))
	for k in PILE:
		var v0 := int(tail[0].get(k, 0))
		var v1 := int(tail[-1].get(k, 0))
		if v1 > int(PILE[k]) and v1 > v0:
			var when := ""
			var cap := int(bot.capped.get("insight" if k == "insight" else "gilt", -1))
			if story_day > 0 and int(tail[-1]["day"]) > story_day + 10:
				when = " (past the written story: it last moved on day %d)" % story_day
			if k in ["insight", "gilt"] and cap > 0:
				when += "; nothing left to %s from day %d" % ["study" if k == "insight" else "build", cap]
			out.append("%s: %s piles up (%d by day %d, %+d over the last 20 days)%s." % [tag, NAMES[k], v1, tail[-1]["day"], v1 - v0, when])
	return out
