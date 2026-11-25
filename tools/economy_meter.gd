extends "res://tools/balance_bot.gd"
## The balance bot with a meter on it (issue #35): plays exactly like tools/balance_bot.gd, but every
## decision step is wrapped so the economy sim can say where each Gilt, Supply, Ink and Insight came from
## and where it went. Used by tools/economy_sim.gd only.
##
## flows[phase][resource][source] = total change over the phase (gains positive, spending negative).
## Sources are the bot's steps ("Buildings", "Research", "Missions", ...) plus "Dawn: <ledger line>" for
## every line of the daily ledger and "Dawn: other" for what the clock moved beyond the ledger
## (expedition returns, faction trouble, bond perks, Blank events).

const KEYS := ["gilt", "supplies", "ink", "insight", "renown"]

var flows := {}  # phase -> resource -> source -> amount
var phase_days := {}  # phase -> days played in it
var phase_first := {}  # phase -> first day
var short_days := {}  # resource -> days a dawn could not pay level 4+ upkeep (Sinks "short")
var short_by_phase := {}  # phase -> resource -> days
var idle_research_days := 0  # days with a Scriptorium but nothing left to study
var idle_build_days := 0  # days the building crew stood idle because every level open was built
var capped := {}  # "insight"/"gilt" -> first day of the streak (still running) with nothing left to study/build
var _phase := "act1"


func _res() -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = int(Empire.res.get(k, 0))
	return out


func _add(src: String, before: Dictionary) -> void:
	var now := _res()
	var ph: Dictionary = flows.get(_phase, {})
	flows[_phase] = ph
	for k in KEYS:
		var d := int(now[k]) - int(before[k])
		if d == 0:
			continue
		var by: Dictionary = ph.get(k, {})
		ph[k] = by
		by[src] = int(by.get(src, 0)) + d


## Where the campaign is: act1, ch2, ch3, ... by the chapter openers seen so far ("after" once the
## last written chapter has ended: everything there is past the content the game has today).
func phase_now() -> String:
	var out := "act1"
	for ch in [["ch2", "ch2_bells"], ["ch3", "ch3_invitation"], ["ch4", "ch4_open"], ["ch5", "ch5_open"], ["ch6", "ch6_open"]]:
		if Dialogue.is_seen("talk:" + ch[1]):
			out = ch[0]
	for end in ["ch3_end", "ch4_end", "ch5_end", "ch6_end"]:
		if Dialogue.is_seen("talk:" + end) and not _later_chapter_open(end):
			out = "after"
	return out


func _later_chapter_open(end_talk: String) -> bool:
	var n := int(end_talk.substr(2, 1))
	return Dialogue.is_seen("talk:ch%d_open" % (n + 1)) or Dialogue.is_seen("talk:ch%d_invitation" % (n + 1))


func play_day() -> void:
	_phase = phase_now()
	phase_days[_phase] = int(phase_days.get(_phase, 0)) + 1
	if not phase_first.has(_phase):
		phase_first[_phase] = Empire.day
	var day_start := _res()
	var steps_start := _res()
	_step_sum = {}
	# Ledger lines as they stand this morning are what the next dawn pays (the bot changes a few
	# things during the day; the "Dawn: other" line catches the difference).
	var dawn := {}
	for line in Empire.ledger():
		var lab := _ledger_label(line)
		for k in ["gilt", "supplies", "ink"]:
			dawn[k] = dawn.get(k, {})
			dawn[k][lab] = int(dawn[k].get(lab, 0)) + int(line.get(k, 0))
	var ins := int(Empire.current_effect("scriptorium").get("insight", 0))
	super.play_day()
	# Everything the wrapped steps did not explain happened on the clock.
	var clock := {}
	var now := _res()
	for k in KEYS:
		clock[k] = int(now[k]) - int(day_start[k]) - int(_step_sum.get(k, 0))
	var ph: Dictionary = flows.get(_phase, {})
	flows[_phase] = ph
	for k in KEYS:
		var left := int(clock[k])
		var by: Dictionary = ph.get(k, {})
		ph[k] = by
		if dawn.has(k):
			for lab in dawn[k]:
				var v := int(dawn[k][lab])
				if v != 0:
					by["Dawn: " + lab] = int(by.get("Dawn: " + lab, 0)) + v
					left -= v
		if k == "insight" and ins > 0:
			by["Dawn: Scriptorium"] = int(by.get("Dawn: Scriptorium", 0)) + ins
			left -= ins
		if left != 0:
			by["Dawn: other"] = int(by.get("Dawn: other", 0)) + left
		if by.is_empty():
			ph.erase(k)
	for k in Sinks.state().get("short", []):
		short_days[k] = int(short_days.get(k, 0)) + 1
		var sp: Dictionary = short_by_phase.get(_phase, {})
		short_by_phase[_phase] = sp
		sp[k] = int(sp.get(k, 0)) + 1
	_note_caps()


var _step_sum := {}


func _end(src: String, before: Dictionary) -> void:
	var now := _res()
	for k in KEYS:
		_step_sum[k] = int(_step_sum.get(k, 0)) + int(now[k]) - int(before[k])
	_add(src, before)


func _ledger_label(line: Dictionary) -> String:
	var lab := str(line.get("label", ""))
	if lab.begins_with("  Governor"):
		return "Governors"
	for p in Empire.territory().provinces:
		if lab == str(p["name"]):
			return "Provinces"
	var cut := lab.find(" (")
	if cut > 0:
		lab = lab.substr(0, cut)
	return lab.strip_edges()


## The opening (prologue and breakout) is not counted: the flows start on the first Command day.
func start() -> void:
	super()
	flows = {}
	_step_sum = {}


# Every step the bot takes, metered. Same order and behaviour as the bot.
func _hire() -> void:
	var b := _res()
	super()
	_end("Hiring", b)


func _bonds() -> void:
	var b := _res()
	super()
	_end("Bonds", b)


func _claims() -> void:
	var b := _res()
	super()
	_end("Claims", b)


func _build() -> void:
	var b := _res()
	super()
	_end("Buildings (and hurrying)", b)


func _research() -> void:
	var b := _res()
	super()
	_end("Research", b)


func _forge() -> void:
	var b := _res()
	super()
	_end("Forge", b)


func _feast() -> void:
	var b := _res()
	super()
	_end("Feasts", b)


func _sell_surplus() -> void:
	var b := _res()
	super()
	_end("Market sales", b)


func _lamps() -> void:
	var b := _res()
	super()
	_end("Wardlamps", b)


func _expeditions() -> void:
	var b := _res()
	super()
	_end("Expedition costs", b)


func _diplomacy(story_only := false) -> void:
	var b := _res()
	super(story_only)
	_end("Diplomacy", b)


func _fight(m: Dictionary) -> void:
	var b := _res()
	super(m)
	_end("Missions", b)


func _story() -> void:
	var b := _res()
	super()
	_end("Story", b)


## Days the empire had nothing left to buy: the Scriptorium idle with nothing to study, the builders
## idle with every open level built. These are when a resource starts to pile up for good.
func _note_caps() -> void:
	if Empire.level_of("scriptorium") > 0 and Empire.research_active == "":
		var any := false
		for id in Empire.research_ids():
			if not id in Empire.research_done and Empire._research_lock(id) == "":
				any = true  # could be studied now, given the Insight
				break
		if not any:
			idle_research_days += 1
			if not capped.has("insight"):
				capped["insight"] = Empire.day
		else:
			capped.erase("insight")
	elif Empire.research_active != "":
		capped.erase("insight")
	if Empire.construction.is_empty():
		var any_b := false
		for bid in Empire.building_ids():
			var nl := Empire.next_level(bid)
			if not nl.is_empty() and str(nl.get("lock", "")) == "":
				any_b = true
				break
		if not any_b:
			idle_build_days += 1
			if not capped.has("gilt"):
				capped["gilt"] = Empire.day
		else:
			capped.erase("gilt")
	else:
		capped.erase("gilt")
