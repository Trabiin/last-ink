class_name Alerts
extends Node
## Objectives, alerts and map markers (issue #22): the one place that knows what needs you next.
##
## Every Empire.notice lands here. A notice that points somewhere (a province, a mission, a screen)
## becomes an alert with a "go there": it stays in the tray until you act on it, dismiss it, or two
## days pass. Plain notices just fade after a few seconds, like before.
##
## Where a notice points is worked out without touching the code that sends it:
##   - the typed Empire signals sent right after a notice (building_finished, expedition_returned,
##     research_finished, bond_ready) point it at their screen;
##   - newcomers at the gate point at the Newcomers screen;
##   - otherwise the first province named in the text.
## New missions are spotted by polling what the map offers (story, Reclaim and Rescue missions;
## Defense already comes with the surge notice).
##
## The store is one node parked under the Empire autoload, so alerts survive scene changes
## (town -> map -> mission -> home). Use Alerts.inst(). Nothing here is saved: after a load the
## tray starts empty and the missions on offer count as already known.

const KEEP_DAYS := 2.0  # an alert nobody acted on goes stale after this many in-game days
const FADE := 7.0  # seconds a plain notice stays up
const MAX_ALERTS := 6
const MAX_PLAIN := 3

static var _inst: Alerts
## A target to go to as soon as the Command Table opens (town -> map).
static var focus := {}

var alerts: Array = []  # {text, warning, target, day, frame, id}
var plain: Array = []  # [text, warning, time left]
var known_missions := {}  # mission id -> true: what the map offered at the last scan
var seeded := false
var last_day := -1
var last_playtime := 0.0
var scan_t := 0.0
var next_id := 1
var last_notice := {}  # {"frame", "alert": bool}: the newest notice, for _retarget


static func inst() -> Alerts:
	if not is_instance_valid(_inst):
		_inst = Alerts.new()
		_inst.name = "Alerts"  # no-tr: node name
		_inst.process_mode = Node.PROCESS_MODE_ALWAYS
		var empire: Node = (Engine.get_main_loop() as SceneTree).root.get_node("Empire")
		empire.add_child(_inst)
		empire.notice.connect(_inst._on_notice)
		empire.building_finished.connect(func(_id): _inst._retarget({"view": "buildings"}))
		empire.expedition_returned.connect(func(_r): _inst._retarget({"view": "expeditions"}))
		empire.research_finished.connect(func(_id): _inst._retarget({"view": "research"}))
		empire.bond_ready.connect(func(_id): _inst._retarget({"view": "bonds"}))
		_inst._reseed()
	return _inst


## The town -> map hand-off: returns the pending target once.
static func take_focus() -> Dictionary:
	var f := focus
	focus = {}
	return f


func _process(delta: float) -> void:
	for n in plain:
		n[2] -= delta
	plain = plain.filter(func(n): return n[2] > 0.0)
	scan_t -= delta
	if scan_t <= 0.0:
		scan_t = 0.5
		scan()


# ---------------------------------------------------------------- incoming

## A one-off line from the scene itself (not from the Empire): shown, never kept.
func say(text: String, warning := false) -> void:
	_plain(text, warning)


func _on_notice(text: String, warning: bool) -> void:
	var target := {}
	if text.contains("south gate"):
		target = {"view": "newcomers"}
	else:
		var pid := _province_in(text)
		if pid != "":
			target = {"province": pid}
	if target.is_empty():
		_plain(text, warning)
	else:
		add(text, warning, target)
	last_notice = {"frame": Engine.get_process_frames(), "alert": not target.is_empty()}


func _plain(text: String, warning: bool) -> void:
	plain = plain.filter(func(n): return n[0] != text)
	plain.append([text, warning, FADE])
	while plain.size() > MAX_PLAIN:
		plain.pop_front()


## Adds an alert that points somewhere. A repeat of the same text replaces the old one.
func add(text: String, warning: bool, target: Dictionary) -> void:
	alerts = alerts.filter(func(a): return a["text"] != text)
	alerts.append({"id": next_id, "text": text, "warning": warning, "target": target,
		"day": _now(), "frame": Engine.get_process_frames()})
	next_id += 1
	while alerts.size() > MAX_ALERTS:
		alerts.pop_front()
	var audio := get_node_or_null("/root/Audio")  # music and SFX (issue #20), when it is there
	if audio and audio.has_method("sfx"):
		audio.sfx("alert", 1.0, 0.0, _caption(text, warning))


## The caption for an alert's bell (issue #192): what kind of news it is, in a few words.
func _caption(text: String, warning: bool) -> String:
	if text.contains("gathering against"):
		return tr("Warning bell: a Blank surge is coming")
	if text.contains("surged into"):
		return tr("Warning bell: the Blank surged")
	if text.contains("has been erased"):
		return tr("Warning bell: land erased")
	return tr("Warning bell") if warning else tr("Bell: news")


## A typed Empire signal right after a notice: point that notice at its screen.
func _retarget(target: Dictionary) -> void:
	if int(last_notice.get("frame", -1)) != Engine.get_process_frames():
		return  # no notice came with it
	var was_alert: bool = last_notice["alert"]
	last_notice = {}
	if was_alert and not alerts.is_empty():
		alerts[-1]["target"] = target
	elif not was_alert and not plain.is_empty():  # it was a plain notice: promote it
		var n: Array = plain.pop_back()
		add(n[0], n[1], target)


func _province_in(text: String) -> String:
	var best := ""
	var best_len := 0
	for p in Empire.territory().provinces:
		var n: String = p["name"]
		if n.length() > best_len and text.contains(n):
			best = p["id"]
			best_len = n.length()
	return best


func _now() -> float:
	return float(Empire.day) + float(Empire.day_t)


# ---------------------------------------------------------------- polling

## Spots new missions, drops alerts that went stale, and notices a load or a New Game.
func scan() -> void:
	if Empire.day < last_day or absf(Empire.playtime - last_playtime) > 30.0:
		_reseed()  # a different campaign was loaded (or a New Game started)
		return
	last_day = Empire.day
	last_playtime = Empire.playtime
	var now := _offered_missions()
	if seeded:
		for id in now:
			if not known_missions.has(id):
				var m: Dictionary = now[id]
				var pname: String = Empire.territory().find(m.get("province", "")).get("name", "?")
				var kind := tr("Story mission") if m.get("story", false) else tr("New mission")
				add("%s: %s (%s)." % [kind, m.get("name", id), pname], false, {"province": m.get("province", ""), "mission": id})
	known_missions = now
	seeded = true
	var t := _now()
	alerts = alerts.filter(func(a): return _still_good(a, t))


func _reseed() -> void:
	alerts = []
	plain = []
	known_missions = _offered_missions()
	seeded = true
	last_day = Empire.day
	last_playtime = Empire.playtime


## id -> mission for every story, Reclaim and Rescue mission that can be launched right now.
func _offered_missions() -> Dictionary:
	var out := {}
	if not Story.command_on():
		return out  # Chapter 1 runs on story beats; the map is not yours yet
	for p in Empire.territory().provinces:
		for m in Missions.list_for_province(p["id"]):
			var typ: String = m.get("type", "")
			if str(m.get("blocker", "")) != "" or typ == "defense":
				continue
			if m.get("story", false) or typ in ["reclaim", "rescue"]:
				out[m["id"]] = m
	return out


func _still_good(a: Dictionary, t: float) -> bool:
	if t - float(a["day"]) > KEEP_DAYS:
		return false
	var mid: String = a["target"].get("mission", "")
	if mid != "" and not known_missions.has(mid):
		return false  # taken, cleared or gone
	var v: String = a["target"].get("view", "")
	if v == "expeditions" and Empire.unread_reports() == 0:
		return false  # already read
	if v == "newcomers" and Empire.visitors.is_empty():
		return false
	if v == "bonds" and Empire.bond_ready_ids().is_empty():
		return false
	return true


# ---------------------------------------------------------------- acting on them

## Newest first.
func pending() -> Array:
	var out := alerts.duplicate()
	out.reverse()
	return out


func dismiss(id: int) -> void:
	alerts = alerts.filter(func(a): return int(a["id"]) != id)


## Province ids with an alert pointing at them (for the map pins).
func flagged_provinces() -> Dictionary:
	var out := {}
	for a in alerts:
		var pid: String = a["target"].get("province", "")
		if pid != "":
			out[pid] = a["warning"] or out.get(pid, false)
	return out


# ---------------------------------------------------------------- the pinned goal

## The story goal that is up next, with where to go for it:
## {"text", "hint", "target"} or {} when the checklist is clear.
static func goal() -> Dictionary:
	for g in Story.data().get("goals", []):
		if g.has("show") and not Story.meets(g["show"]):
			continue
		if Story.meets(g.get("done", {})):
			continue
		return {"text": g.get("text", ""), "hint": g.get("hint", ""), "target": goal_target(g.get("done", {}))}
	return {}


## Where a story goal can be worked on: its mission on the map, the gate, or a rescue (the journal uses it too).
static func goal_target(done: Dictionary) -> Dictionary:
	for id in done.get("cleared", []):
		var m := Missions.find(id)
		if not m.is_empty() and Missions.offered(m) and not Missions.cleared(id):
			return {"province": m.get("province", ""), "mission": id}
	for rid in done.get("joined", []):
		if Empire.recruits.has(rid):
			continue
		if Empire.is_visitor(rid):
			return {"view": "newcomers"}
		for jid in Empire.job_ids():
			var j := Empire.job(jid)
			if j.get("recruit", "") == rid:
				return {"province": j.get("province", ""), "mission": "rescue_" + rid}
	return {}


## What Tab does right now: the newest alert, else the story goal. {} = nothing to go to.
func next_target() -> Dictionary:
	if not alerts.is_empty():
		return alerts[-1]
	var g := goal()
	if not g.get("target", {}).is_empty():
		return {"id": -1, "text": g["text"], "target": g["target"]}
	return {}
