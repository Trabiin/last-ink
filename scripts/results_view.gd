extends Control
## Mission results (issue #5, redone 2026-11-25): an open ledger over the paused mission. The left page leads with
## what changed (Payoff.entries: the people you saved walking into Hollowmark, the province's name inking back in,
## one line from someone who went); the right page keeps the accounts (objective, time, finds, rewards, Fray) and
## the way home. The left page's beats come in one after another and the accounts fade in after them.
##
## Enter / A / a tap: the first press shows everything at once, the next returns to Hollowmark (the button too).
## Reduce motion shows everything at once.

signal confirmed

const GOLD := Color("ffd166")
const PAPER := Color("f3f1ea")
const DIM := Color(0.68, 0.66, 0.66)
const LABEL_W := 84.0
const FIRST_BEAT := 0.45  # seconds before the first change is written in
const BEAT := 1.25  # seconds between changes
const INK_TIME := 0.9  # how long a name takes to ink in (or drain out)
const ACCOUNTS_AFTER := 0.7  # after the last change starts, the accounts page fades in
const WALK_TIME := 3.0  # how long the walkers take to reach the gate
const MAX_WALKERS := 12
const STAGGER := 0.14  # seconds between walkers setting off

var result := {}
var changes: Array = []  # Payoff.entries(result)
var _t := 0.0
var _btn := Rect2()
var _shown_frame := 0
var _skip := false  # everything shown at once (a press, or reduce motion)
var _sound_i := -1  # the last change that played its sound
var drawn_text: Array = []  # [rect, page box, text] for the layout tests (LedgerPage.log)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func open(r: Dictionary, party = null) -> void:
	result = r
	changes = Payoff.entries(r, party)
	_t = 0.0
	_skip = Access.reduce_motion
	_sound_i = -1
	_shown_frame = Engine.get_process_frames()
	visible = true
	Audio.sfx("fanfare" if r.get("outcome", "") == "success" else "error")
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		var i := _beat_index()
		if i > _sound_i and not _skip:
			_sound_i = i
			if i >= 0 and i < changes.size():
				Audio.sfx("ui_move" if changes[i]["kind"] != "lost" else "ui_back")
		queue_redraw()


## When change i starts.
func beat_time(i: int) -> float:
	return FIRST_BEAT + BEAT * i


## The last change that has started (-1 before the first).
func _beat_index() -> int:
	if _skip:
		return changes.size() - 1
	return mini(int(floorf((_t - FIRST_BEAT) / BEAT)), changes.size() - 1) if _t >= FIRST_BEAT else -1


## Seconds since change i started (big once everything shows).
func _since(i: int) -> float:
	return 99.0 if _skip else _t - beat_time(i)


## When the accounts page starts to fade in.
func accounts_time() -> float:
	return beat_time(maxi(changes.size() - 1, 0)) + ACCOUNTS_AFTER


## 0..1: the accounts page and the button.
func accounts_alpha() -> float:
	return 1.0 if _skip else clampf((_t - accounts_time()) / 0.4, 0.0, 1.0)


func all_shown() -> bool:
	return _skip or _t >= accounts_time() + 0.4


func _input(event: InputEvent) -> void:
	if not visible or Engine.get_process_frames() - _shown_frame < 20:
		return  # a beat so a held attack button does not skip the screen
	var go := event.is_action_pressed("ui_accept")
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
	if tap:
		go = _btn.grow(6).has_point(event.position) or not all_shown()
	if not go:
		return
	get_viewport().set_input_as_handled()
	if not all_shown():
		_skip = true  # first press: show the rest at once
		queue_redraw()
		return
	visible = false
	confirmed.emit()


func _text(pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), col)


func _text_c(cx: float, y: float, s: String, size: int, col: Color) -> void:
	var w := ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size)).x
	draw_string_outline(ThemeDB.fallback_font, Vector2(cx - w / 2.0, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(size), 4, Color(0, 0, 0, 0.8 * col.a))
	_text(Vector2(cx - w / 2.0, y), s, size, col)


## The accounts' rows as [label, value, ink], in order.
func _rows() -> Array:
	var outcome: String = result["outcome"]
	var rows := []
	var obj_note := tr("done") if outcome == "success" else tr("not finished")
	rows.append([tr("Objective"), "%s  (%s)" % [result.get("objective", ""), obj_note], LedgerPage.INK if outcome == "success" else LedgerPage.INK_SOFT])
	var secs := int(result.get("time", 0.0))
	rows.append([tr("Time"), tr("%d:%02d    Nibblers dispersed: %d") % [secs / 60, secs % 60, int(result.get("kills", 0))], LedgerPage.INK])
	var found := Missions.res_text(result.get("found", {}))
	if outcome == "wiped":
		rows.append([tr("Found"), (tr("Dropped it all: %s") % found) if found != "" else tr("Nothing"), LedgerPage.RED])
	else:
		rows.append([tr("Found"), found if found != "" else tr("Nothing"), LedgerPage.INK])
	if outcome == "success":
		var rew := Missions.res_text(result.get("rewards", {}))
		if rew != "":
			rows.append([tr("Reward"), rew, LedgerPage.INK])
	var fray := int(result.get("fray", 0))
	if fray != 0:
		var now := int(result.get("fray_now", 0))
		rows.append([tr("Fray"), tr("%s %d to %d (the Blank pulls back)") % [result["province"], now, clampi(now + fray, 0, 99)], LedgerPage.GREEN])
	for line in result.get("lines", []):
		rows.append(["", str(line), LedgerPage.INK])
	return rows


func _fade(c: Color, a: float) -> Color:
	return Color(c, c.a * a)


## The ledger lies open: what changed on the left page, the accounts on the right.
func _draw() -> void:
	if result.is_empty():
		return
	drawn_text = []
	var font := ThemeDB.fallback_font
	var vs := get_viewport_rect().size
	var a := clampf(_t / 0.35, 0.0, 1.0) if not _skip else 1.0
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.03, 0.07, 0.72 * a))
	var w := minf(612.0, vs.x - 16.0)
	var h := minf(318.0, vs.y - 34.0)
	var top := floorf((vs.y - h) / 2.0 - 8.0 + (1.0 - a) * 12.0)
	var x0 := floorf((vs.x - w) / 2.0)
	var half := floorf(w / 2.0)
	var left := Rect2(x0, top, half - 1.0, h)
	var right := Rect2(x0 + half + 1.0, top, w - half - 1.0, h)
	_draw_changes(left, font)
	_draw_accounts(right, font)
	# The spine between the pages.
	draw_line(Vector2(x0 + half, top + 4.0), Vector2(x0 + half, top + h - 4.0), Color(LedgerPage.EDGE, 0.8), 2.0)
	_text_c(vs.x / 2.0, top + h + 16.0, Prompts.confirm() if all_shown() else tr("%s to see it all") % Prompts.confirm(), 8, Color(0.75, 0.72, 0.66, 0.9))


# ---------------------------------------------------------------- left page: what changed

func _draw_changes(box: Rect2, font: Font) -> void:
	var outcome: String = result["outcome"]
	var pg := LedgerPage.begin(self, box, font, 9)
	pg.log = drawn_text
	pg.heading(result["title"], 16, LedgerPage.GOLD if outcome == "success" else LedgerPage.INK)
	var sub: String = result["name"]
	if result.get("first_clear", false):
		sub += "  ·  " + tr("First clear")
	pg.line(sub, 8, LedgerPage.INK_SOFT)
	pg.skip()
	var shown := _beat_index()
	for i in changes.size():
		var e: Dictionary = changes[i]
		var since := _since(i)
		var vis := i <= shown
		var al := clampf(since / 0.35, 0.0, 1.0) if vis else 0.0
		match str(e["kind"]):
			"place", "lost":
				_draw_place(pg, e, since, al, vis)
			"people":
				_draw_people(pg, e, since, al, vis)
			"person":
				_draw_person(pg, e, since, al, vis)
			"line":
				_draw_line(pg, e, al, vis)
		if pg.full():
			break


## The text under a change, written once its beat has come (the lines are kept either way, so nothing jumps).
func _para(pg: LedgerPage, s: String, al: float, vis: bool, col := LedgerPage.INK) -> void:
	if vis:
		pg.para(s, 9, _fade(col, al))
	else:
		pg.line_i += LedgerPage.lines_for(s, pg.font, 9, pg.x1 - pg.x0)


## A province's name, big: inked back in letter by letter from the white, or (lost) drained pale. A change with
## no province is just its line.
func _draw_place(pg: LedgerPage, e: Dictionary, since: float, al: float, vis: bool) -> void:
	var pid := str(e.get("province_id", ""))
	var p := Empire.territory().find(pid) if pid != "" else {}
	var lost := str(e["kind"]) == "lost"
	if not p.is_empty() and not e.get("faint", false):
		var r := pg.space(2)
		if r.size != Vector2.ZERO:
			var pname := str(p.get("name", ""))
			var k := clampf(since / INK_TIME, 0.0, 1.0) if vis else 0.0
			_ink_name(r, pname, (1.0 - k) if lost else k, lost, vis)
	_para(pg, str(e["text"]), al, vis, LedgerPage.INK_SOFT if lost or e.get("faint", false) else LedgerPage.INK)


## Writes `label` centred in r. `inked` 0..1 is how much of it, left to right, is in ink; the rest is white, the
## Blank's colour, with only a pencil ghost of the letters.
func _ink_name(r: Rect2, label: String, inked: float, lost: bool, vis: bool) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(17)).x
	var x := floorf(r.get_center().x - w / 2.0)
	var y := floorf(r.end.y - 4.0)
	var n := label.length()
	var white := Color("f4f1e8")
	var ghost := Color(LedgerPage.INK_SOFT, 0.28)
	for i in n:
		var ch := label[i]
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(17)).x
		var share := clampf(inked * n - i, 0.0, 1.0)  # this letter's ink
		draw_string(font, Vector2(x + 1, y + 1), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(17), ghost if vis or lost else Color(ghost, 0.15))
		var col := white.lerp(LedgerPage.INK, share)
		if not vis and not lost:
			col = Color(white, 0.55)
		draw_string(font, Vector2(x, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(17), col)
		if share > 0.0 and share < 1.0:  # the wet edge: a blot where the ink is still running in
			draw_circle(Vector2(x + cw * share, y - Access.fs(17) * 0.35), 1.5, Color(LedgerPage.INK, 0.6))
		x += cw
	drawn_text.append([Rect2(r.get_center().x - w / 2.0, r.position.y, w, r.size.y), r, label])


## Little ink figures walking along a ruled line into Hollowmark's gate (count of them), or for a surge that never
## landed, standing at their own doors.
func _draw_people(pg: LedgerPage, e: Dictionary, since: float, al: float, vis: bool) -> void:
	var r := pg.space(2)
	if r.size != Vector2.ZERO and vis:
		var n := clampi(int(e.get("count", 6)), 1, MAX_WALKERS)
		var gate := Vector2(r.end.x - 48.0, r.end.y - 2.0)
		if e.get("stay", false):
			for i in n:
				var hx := r.position.x + 10.0 + i * (r.size.x - 40.0) / maxf(n, 1)
				_house(Vector2(hx, r.end.y - 2.0), al)
				_walker(Vector2(hx + 6.0, r.end.y - 2.0), 0.0, al, i)
		else:
			_gate(gate, al)
			# They come in one after another from the left edge and queue up at the gate.
			var x0 := r.position.x + 4.0
			var from := str(e.get("from", ""))
			if from != "":  # where they come from, at the start of the line they walk along
				_text(Vector2(r.position.x + 2.0, r.end.y - 2.0), from, 7, _fade(LedgerPage.INK_SOFT, al))
				x0 += ThemeDB.fallback_font.get_string_size(from, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x + 8.0
			for i in n:
				var stop := gate.x - 10.0 - i * 8.0
				var t0 := i * STAGGER
				var walk := clampf((since - t0) / (WALK_TIME - STAGGER * (n - 1) * 0.5), 0.0, 1.0)
				if since < t0:
					continue
				var px := lerpf(x0, stop, ease(walk, 0.9))
				_walker(Vector2(px, r.end.y - 2.0), (since - t0) * 7.0 + i * 1.7 if walk < 1.0 else 0.0, al, i)
	_para(pg, str(e["text"]), al, vis)


## One named figure walks in, with their name over their head.
func _draw_person(pg: LedgerPage, e: Dictionary, since: float, al: float, vis: bool) -> void:
	var r := pg.space(2)
	if r.size != Vector2.ZERO and vis:
		var gate := Vector2(r.end.x - 48.0, r.end.y - 2.0)
		_gate(gate, al)
		var walk := clampf(since / WALK_TIME, 0.0, 1.0)
		var px := lerpf(r.position.x + 10.0, gate.x - 12.0, ease(walk, 0.8))
		_walker(Vector2(px, r.end.y - 2.0), since * 6.0 if walk < 1.0 else 0.0, al, 3, Dialogue.accent(str(e.get("who", ""))))
		var nm := Payoff.speaker_name(str(e.get("who", "")))
		var fw := ThemeDB.fallback_font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
		_text(Vector2(px - fw / 2.0, r.end.y - 17.0), nm, 7, _fade(LedgerPage.INK_SOFT, al))
	_para(pg, str(e["text"]), al, vis)


## A party member's line, with their portrait in the margin.
func _draw_line(pg: LedgerPage, e: Dictionary, al: float, vis: bool) -> void:
	var who := str(e.get("who", ""))
	var text := "\"%s\"" % str(e["text"])
	var nm := Payoff.speaker_name(who)
	var pw := 34.0
	var wrap := InkMenu.wrap_px(pg.font, text, Access.fs(9), pg.x1 - pg.x0 - pw - 4.0)
	var need := maxi(wrap.size() + 1, 4)
	var r := pg.space(need)
	if r.size == Vector2.ZERO or not vis:
		return
	var pr := Rect2(r.position.x, r.position.y + 1.0, pw, r.size.y - 2.0)
	if Dialogue.portrait(who) != null:
		Dialogue.draw_portrait(self, pr, who, "", 1.0 - al)
	var tx := r.position.x + pw + 4.0
	var y := pg.rule_y(pg.line_i - need) - 1.0
	_text(Vector2(tx, y), nm, 8, _fade(Dialogue.accent(who).darkened(0.35), al))
	for ln in wrap:
		y += pg.lh
		_text(Vector2(tx, y), ln, 9, _fade(LedgerPage.INK, al))
		drawn_text.append([Rect2(tx, y - 9.0, pg.x1 - tx, pg.lh), pg.box, ln])


## An ink doodle of a person, feet at p. phase swings the legs (0 = standing).
func _walker(p: Vector2, phase: float, al: float, i: int, col := LedgerPage.INK) -> void:
	var c := _fade(col, al)
	var bob := absf(sin(phase)) * 1.0
	var tall := 9.0 + float(i % 3)  # some taller, some children
	if i % 5 == 4:
		tall = 6.0
	var hip := p + Vector2(0, -tall * 0.45 - bob)
	var neck := p + Vector2(0, -tall + 2.0 - bob)
	draw_circle(neck + Vector2(0, -2.0), 1.6, c)
	draw_line(neck, hip, c, 1.0)
	var sw := sin(phase) * 2.0
	draw_line(hip, p + Vector2(sw, 0), c, 1.0)
	draw_line(hip, p + Vector2(-sw, 0), c, 1.0)
	draw_line(neck + Vector2(0, 1.5), neck + Vector2(-sw * 0.8 - 1.0, 4.0), c, 1.0)
	if i % 4 == 1:  # a bundle on the back
		draw_rect(Rect2(neck + Vector2(-3.5, 0.5), Vector2(2.5, 3.0)), c)


## Hollowmark's gate, doodled: two posts, a lintel and a little flag.
func _gate(p: Vector2, al: float) -> void:
	var c := _fade(LedgerPage.INK, al)
	draw_line(p + Vector2(-6, 0), p + Vector2(-6, -13), c, 1.0)
	draw_line(p + Vector2(6, 0), p + Vector2(6, -13), c, 1.0)
	draw_line(p + Vector2(-8, -13), p + Vector2(8, -13), c, 1.0)
	draw_line(p + Vector2(0, -13), p + Vector2(0, -18), c, 1.0)
	draw_rect(Rect2(p + Vector2(0, -18), Vector2(4, 2.5)), _fade(LedgerPage.RED, al))
	_text(p + Vector2(10, -2), tr("Hollowmark"), 7, _fade(LedgerPage.INK_SOFT, al))


func _house(p: Vector2, al: float) -> void:
	var c := _fade(LedgerPage.INK_SOFT, al)
	draw_rect(Rect2(p + Vector2(-4, -6), Vector2(8, 6)), c, false, 1.0)
	draw_line(p + Vector2(-5, -6), p + Vector2(0, -10), c, 1.0)
	draw_line(p + Vector2(5, -6), p + Vector2(0, -10), c, 1.0)


# ---------------------------------------------------------------- right page: the accounts

func _draw_accounts(box: Rect2, font: Font) -> void:
	var outcome: String = result["outcome"]
	var aa := accounts_alpha()
	var pg := LedgerPage.begin(self, box, font, 9)
	pg.log = drawn_text if aa > 0.0 else null
	if aa <= 0.0:
		return  # a blank page, waiting for the sums
	pg.heading(tr("The accounts"), 12, _fade(LedgerPage.INK, aa))
	var sub := str(result.get("province", ""))
	pg.line(sub if sub != "" else " ", 8, _fade(LedgerPage.INK_SOFT, aa))
	pg.skip()
	for r in _rows():
		pg.field(r[0], r[1], LABEL_W, 9, _fade(LedgerPage.INK_SOFT, aa), _fade(r[2], aa))
	pg.skip()
	var pay := Missions.res_text(result.get("pay", {}))
	pg.field(tr("Brought home"), pay if pay != "" else tr("Nothing but bruises"), LABEL_W, 9, _fade(LedgerPage.INK, aa), _fade(LedgerPage.GOLD if pay != "" else LedgerPage.INK_SOFT, aa))
	# The button, on the page's last lines
	var room := pg.space(2)
	var bw := minf(170.0, box.size.x - 30.0)
	var cx := box.get_center().x
	var by := (room.end.y - 22.0) if room.size != Vector2.ZERO else box.end.y - 30.0
	by = maxf(by, box.end.y - 34.0)
	_btn = Rect2(floorf(cx - bw / 2.0), floorf(by), bw, 22.0)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	UiSkin.panel(self, _btn, "button", Color(1.05 + 0.15 * pulse, 1.0 + 0.1 * pulse, 0.9, aa))
	UiSkin.frame(self, _btn.grow(1.0))
	_text_c(cx, _btn.position.y + 15.0, tr("Return to Hollowmark"), 10, _fade(GOLD, aa))
