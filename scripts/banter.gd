extends Control
## Walking banter (issue #11): short lines at the top of the screen that never stop the game.
## A small face, the speaker's name and typewriter text; each line stays up a moment, then the
## next one in the queue follows.
##
## Lines come from three places:
##   - zones in data/dialogue.json "banter" -> <map id>: walk into the rect (in tiles) and the
##     lines play once per campaign, if everyone the zone "needs" is present (call check_zones);
##   - named events in "events" (event("first_kill", present));
##   - code, via say() / add().

const TILE := 16.0
const TEXT := Color("ece6da")

var queue: Array = []  # [speaker, text, expression] waiting to be shown
var _cur: Array = []
var _shown := 0.0
var _hold := 0.0
var _fade := 0.0
var gap := 0.0  # wait before the next line
var top := 6.0  # distance from the top of the screen (Hollowmark moves it below its buttons)
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font


func say(who: String, text: String, expr := "") -> void:
	queue.append([who, text, expr])


func add(ls: Array, front := false) -> void:
	var n := Dialogue.lines(ls)
	if front:
		queue = n + queue
	else:
		queue.append_array(n)


func busy() -> bool:
	return not _cur.is_empty() or not queue.is_empty()


## Queue an event's lines if everyone speaking in them is present. Returns true if it played.
func event(event_id: String, present: Array) -> bool:
	var ls := Dialogue.event_lines(event_id)
	if ls.is_empty() or not _all_present(ls, present):
		return false
	Dialogue.mark_seen("event:" + event_id)
	add(ls, bool(Dialogue.data().get("events", {}).get(event_id, {}).get("urgent", false)))
	return true


## Walk-in zones: play any zone the leader stands in whose speakers are all present.
## present = ids of who could speak (party members on a mission, people standing in town).
func check_zones(map_id: String, world_pos: Vector2, present: Array) -> void:
	var tile := world_pos / TILE
	for z in Dialogue.banter_zones(map_id):
		var key := "banter:" + String(z.get("id", ""))
		if Dialogue.is_seen(key):
			continue
		var r: Array = z.get("rect", [0, 0, 0, 0])
		if not Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])).has_point(tile):
			continue
		var ls := Dialogue.lines(z.get("lines", []))
		var needs: Array = z.get("needs", [])
		if not _all_present(ls, present) or needs.any(func(n): return not present.has(n)):
			continue
		Dialogue.mark_seen(key)
		add(ls)


func _all_present(ls: Array, present: Array) -> bool:
	for l in ls:
		if l[0] != "" and not present.has(l[0]):
			return false
	return true


func to_save() -> Array:
	return ([_cur] if not _cur.is_empty() else []) + queue


func from_save(a) -> void:
	queue = []
	_cur = []
	if typeof(a) == TYPE_ARRAY:
		for l in a:
			if typeof(l) == TYPE_ARRAY or typeof(l) == TYPE_DICTIONARY:
				queue.append(Dialogue.line(l))
	gap = 1.5


func _process(delta: float) -> void:
	if _cur.is_empty():
		gap -= delta
		if gap <= 0.0 and not queue.is_empty():
			_cur = queue.pop_front()
			if Betrayal.marked(String(_cur[0])):  # Chapter 4 on: black bars in the top candidate's banter (issue #186)
				_cur = [_cur[0], Betrayal.redact(String(_cur[1])), _cur[2]]
			DialogueLog.track(self, _cur, "banter")
			_shown = 0.0
			_hold = 1.8 + String(_cur[1]).length() * 0.035
			_fade = 0.0
		elif queue.is_empty():
			queue_redraw()
			return
	if not _cur.is_empty():
		var cps := Dialogue.chars_per_sec()
		var n := Dialogue.plain(String(_cur[1])).length()
		_shown = 99999.0 if cps <= 0.0 else _shown + delta * cps
		_fade = minf(_fade + delta * 5.0, 1.0)
		if _shown >= n:
			_hold -= delta
			if _hold <= 0.0:
				_cur = []
				gap = 0.35
		var done := _shown >= Dialogue.plain(String(_cur[1])).length() if not _cur.is_empty() else true
		modulate.a = clampf(minf(_fade, _hold / 0.3) if done else _fade, 0.0, 1.0)
	queue_redraw()


func _panel_rect() -> Rect2:
	var vs := get_viewport_rect().size
	var w := minf(310.0, vs.x - 16.0)
	var x := maxf(vs.x / 2.0 - w / 2.0, minf(240.0, vs.x - w - 8.0))
	return Rect2(x, top, w, 40)


func _draw() -> void:
	if _cur.is_empty():
		return
	var r := _panel_rect()
	var who: String = _cur[0]
	var tw := r.size.x - (49.0 if who != "" else 14.0)
	var need := font.get_multiline_string_size(Dialogue.plain(String(_cur[1])), HORIZONTAL_ALIGNMENT_LEFT, tw, Access.fs(9)).y
	r.size.y = maxf(r.size.y, need + (22.0 if who != "" else 12.0))
	UiSkin.page(self, r)  # the same torn ledger page as the dialogue box
	var tx := r.position.x + 8
	if who != "":
		var face := Rect2(r.position + Vector2(5, 5), Vector2(30, 30))
		Dialogue.draw_face(self, face, who, _cur[2])
		tx = face.end.x + 7
		draw_string(font, Vector2(tx, r.position.y + 13), Dialogue.display_name(who), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9),
			Dialogue.accent(who).darkened(0.35))
	Dialogue.draw_text(self, font, Vector2(tx, r.position.y + (25 if who != "" else 15)), String(_cur[1]), r.end.x - tx - 6,
		Access.fs(9), UiSkin.PAGE_INK if who != "" else UiSkin.PAGE_INK_SOFT, mini(int(_shown), 1 << 30))
