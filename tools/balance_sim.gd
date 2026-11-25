extends SceneTree
## Balance sim (issue #35): runs the Command layer for N days with a scripted player
## (tools/balance_bot.gd) and writes what happened, so runaway or starved economies show up
## without playing for hours.
##
##   godot --headless --audio-driver Dummy --path . -s tools/balance_sim.gd -- [days] [policies] [seeds] [out_dir]
##   godot ... -s tools/balance_sim.gd -- 60 steady,casual,idle,rush 3 /tmp/balance
##
## Writes <out_dir>/<policy>_s<seed>.csv (one row a day) and <out_dir>/report.md (the findings),
## and prints the report. Flags are listed at the top of the report; docs/BALANCE.md explains them.
## Never touches the player's saves (nothing is saved).

var Bot: GDScript  # loaded after the first frame: it names autoloads and class_names

var _frame := 0
var days := 60
var policies := ["steady", "casual", "idle", "rush"]
var seeds := 3
var out_dir := "user://balance/"


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
	if _frame == 2:
		_run()
		quit(0)
	return false


func _run() -> void:
	Bot = load("res://tools/balance_bot.gd")
	var Empire = root.get_node("Empire")
	var Missions = load("res://scripts/missions.gd")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var saves = root.get_node_or_null("Saves")
	if saves != null:
		saves.dir = "user://balance_scratch/"
	var lines := ["# Balance sim", "", "%d days per run, %d seed(s) per policy." % [days, seeds], ""]
	var flags := []
	var table := ["| Policy | Seed | Day reached | Held (max) | Erased | Gilt end | Gilt peak | Supplies end | Ink end | Insight end | Hungry days | Party Lv | Buildings | Research | Missions | Act 1 boss day | Boss Lv |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
	var timelines := []
	var chapters := ["| Policy | Seed | " + " | ".join(MILESTONES.map(func(x): return x[1])) + " |", "|---|---|" + "---|".repeat(MILESTONES.size())]
	var loot := []
	for pol in policies:
		for s in seeds:
			var bot = Bot.new(pol)
			seed(1000 + s)
			bot.start()
			Empire.rng.seed = 1000 + s
			var hungry := 0
			var held_max := 0
			var gilt_peak := 0
			var boss_day := -1
			var boss_lv := 0
			var lost_day := -1
			for d in days:
				bot.play_day()
				var snap: Dictionary = bot.log[-1]
				hungry += 1 if snap["hungry"] else 0
				held_max = maxi(held_max, snap["held"])
				gilt_peak = maxi(gilt_peak, snap["gilt"])
				if boss_day < 0 and Missions.cleared("auditor_duel"):
					boss_day = snap["day"]
					boss_lv = snap["level"]
				if not snap["hollowmark"]:
					lost_day = snap["day"]
					break
			var last: Dictionary = bot.log[-1]
			_write_csv(out_dir + "%s_s%d.csv" % [pol, s], bot.log)
			table.append("| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d | %s | %s |" % [pol, s, last["day"], held_max, last["erased"],
				last["gilt"], gilt_peak, last["supplies"], last["ink"], last["insight"], hungry, last["level"], last["buildings"], last["research"],
				bot.missions_run, str(boss_day) if boss_day > 0 else "-", str(boss_lv) if boss_day > 0 else "-"])
			flags.append_array(_flags(pol, s, bot, hungry, lost_day))
			var cells := []
			for ms in MILESTONES:
				var sd: Array = bot.story_days.get(ms[0], [])
				cells.append("d%d Lv%d" % [sd[0], sd[1]] if not sd.is_empty() else "-")
			chapters.append("| %s | %d | %s |" % [pol, s, " | ".join(cells)])
			loot.append_array(_loot_lines(pol, s, bot))
			if s == 0:
				timelines.append([pol, bot])
	lines.append("## Flags")
	lines.append("")
	if flags.is_empty():
		lines.append("None.")
	for f in flags:
		lines.append("- " + f)
	lines.append("")
	lines.append("## Runs")
	lines.append("")
	lines.append_array(table)
	lines.append("")
	lines.append("## Story: day cleared and party level")
	lines.append("")
	lines.append_array(chapters)
	lines.append("")
	lines.append("## Regional materials and Forge upgrades (issue #138)")
	lines.append("")
	lines.append("Per mission fought in the region: how many of its tier 4-6 materials came home. Upgrades: weapon")
	lines.append("upgrades started at that tier, and the day of the first and last.")
	lines.append("")
	lines.append("| Policy | Seed | Region | Missions | Materials per mission | Upgrades (first, last day) |")
	lines.append("|---|---|---|---|---|---|")
	lines.append_array(loot)
	for tl in timelines:
		lines.append("")
		lines.append("## %s (seed 0): every 5 days" % tl[0])
		lines.append("")
		lines.append("| Day | Gilt | Net | Supplies | Net | Ink | Net | Renown | Insight | Held | Erased | Max Fray | Party Lv | Roster |")
		lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
		for snap in tl[1].log:
			if int(snap["day"]) % 5 == 0:
				lines.append("| %d | %d | %+d | %d | %+d | %d | %+d | %d | %d | %d | %d | %d | %d | %d |" % [snap["day"], snap["gilt"], snap["net_gilt"],
					snap["supplies"], snap["net_supplies"], snap["ink"], snap["net_ink"], snap["renown"], snap["insight"], snap["held"],
					snap["erased"], snap["fray_max"], snap["level"], snap["roster"]])
		lines.append("")
		lines.append("Firsts: " + ", ".join(tl[1].events.filter(func(e): return not str(e[1]).begins_with("expedition")).map(func(e): return "d%d %s" % [e[0], e[1]])))
		lines.append("")
		lines.append("Missions by type: " + str(tl[1].missions_by_type))
	var text := "\n".join(lines) + "\n"
	var f := FileAccess.open(out_dir + "report.md", FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(text)


const MILESTONES := [["auditor_duel", "Auditor"], ["ch2_candleford", "Wax Barges"], ["ch2_hall", "Copying Hall"],
	["ch2_crypt", "Crypts"], ["ch2_abbot", "Abbot"], ["ch3_quay", "Quay"], ["ch3_masquerade", "Masquerade"],
	["ch3_wharf", "Wharf"], ["ch3_host", "Host"]]
const REGION_TIER := {"abbey": 4, "causeway": 5, "coast": 6, "spire": 6}


static func _loot_lines(pol: String, s: int, bot) -> Array:
	var out := []
	var mats: Dictionary = Armory.mats_data().get("materials", {})
	for region in REGION_TIER:
		var n := int(bot.missions_by_region.get(region, 0))
		if n == 0:
			continue
		var got: Dictionary = bot.mats_by_region.get(region, {})
		var per := []
		for k in got:
			if str(mats.get(k, {}).get("region", "")) == region:
				per.append("%s %.1f" % [mats[k].get("name", k), float(got[k]) / n])
		var ups: Array = bot.upgrades.filter(func(u): return int(u[2]) == int(REGION_TIER[region]))
		var when := "%d (d%d, d%d)" % [ups.size(), ups[0][0], ups[-1][0]] if not ups.is_empty() else "0"
		out.append("| %s | %d | %s | %d | %s | %s |" % [pol, s, region, n, ", ".join(per), when])
	return out


## The guard rails, in words a designer can act on. Shared with tests/test_balance.gd.
static func _flags(pol: String, s: int, bot, hungry: int, lost_day: int) -> Array:
	var out := []
	var tag := "%s/s%d" % [pol, s]
	var log: Array = bot.log
	if lost_day > 0 and pol != "idle":
		out.append("%s: Hollowmark was erased on day %d." % [tag, lost_day])
	if pol == "idle" and lost_day > 0 and lost_day < 20:
		out.append("%s: a player who does nothing loses Hollowmark on day %d (too fast: under 20 days)." % [tag, lost_day])
	if pol != "idle" and hungry > 3:
		out.append("%s: %d hungry days (Supplies ran out)." % [tag, hungry])
	var tail := log.slice(maxi(0, log.size() - 10))
	if log.size() >= 30:
		var g0: int = tail[0]["gilt"]
		var g1: int = tail[-1]["gilt"]
		if g1 > 1500 and g1 - g0 > 150:
			out.append("%s: Gilt runs away (%d by day %d, still +%d over the last 10 days) with nothing left to spend it on." % [tag, g1, tail[-1]["day"], g1 - g0])
		var i1: int = tail[-1]["insight"]
		if i1 > 150:
			out.append("%s: Insight piles up (%d) once research is done." % [tag, i1])
		var k1: int = tail[-1]["ink"]
		if k1 > 120:
			out.append("%s: Ink piles up (%d)." % [tag, k1])
		var s1: int = tail[-1]["supplies"]
		if s1 > 600:
			out.append("%s: Supplies pile up (%d)." % [tag, s1])
	return out


func _write_csv(path: String, log: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null or log.is_empty():
		return
	var keys: Array = log[0].keys()
	f.store_line(",".join(keys))
	for snap in log:
		f.store_line(",".join(keys.map(func(k): return str(snap[k]))))
	f.close()
