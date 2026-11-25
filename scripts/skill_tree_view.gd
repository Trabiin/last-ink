class_name SkillTreeView
extends Control
## The skill tree screen (issue #25, scripts/skill_tree.gd): one hero's tree at a time, the root at the
## bottom and the two personality branches climbing to their capstones, with the chosen node's details on
## the right. Opened from the Gear screen's Tree tab (K in town and at the Command Table, Party gear on a
## mission) and from the quick menu's Tree tab mid-fight. On a mission, what is learned takes effect at once;
## unlearning (for Gilt) only happens at home.
##
## Keyboard and pad: arrows / d-pad / stick walk the tree (Down from the root reaches Unlearn), Enter / A
## learns, Tab / Y next hero, Esc / B / K closes. Opened from the Gear screen it shows that screen's tab row
## (TabStrip), and Q / E (LB / RB) or a tap there move on to the next tab. Mouse and touch: tap a hero, tap a node to look at it,
## tap it again to learn it.

signal closed
signal tab_picked(i: int)  # a tab of the Gear screen's row was picked while this one is open

const GOLD := Color("ffd166")
const GOOD := Color("9fd18b")
const BAD := Color("ff9b8a")
const TEXT := Color("ece6da")
const DIM := Color(0.42, 0.41, 0.44)
const SOFT := Color(0.62, 0.6, 0.62)
const PAPER := Color("f3efe4")
const XP_COL := Color("b49bcc")
const NODE := Vector2(156, 32)
const RESET := "reset"

var party  # main.gd on a mission: heroes in the field get what is learned right away
var where := "town"  # "town" or "mission" (no unlearning out there)
var hero_i := 0
var sel := ""  # selected node id, or RESET
var _ids: Array = []
var _hero_rects: Array = []
var _node_rects := {}  # node id -> Rect2
var _reset_rect := Rect2()
var _learn_rect := Rect2()
var _confirm_reset := ""  # hero id whose unlearn waits for a second press
var opened_frame := -1
var closed_frame := -1
var flash := ""
var flash_t := 0.0
var _t := 0.0
var font: Font
var tabs: TabStrip = null  # the Gear screen's tab row, when opened from its Tree tab


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ThemeDB.fallback_font


## Opens on this hero (or the first on the list). at: "town" or "mission".
func open(at := "town", hero_id := "") -> void:
	where = at
	visible = true
	opened_frame = Engine.get_process_frames()
	_ids = Progress.field_ids()
	if party != null and where == "mission":
		_ids = party.heroes.map(func(h): return (h as Hero).hero_id)
	_ids = _ids.filter(func(id): return SkillTree.has_tree(id))
	hero_i = maxi(_ids.find(hero_id), 0) if hero_id != "" else 0
	_start_on_hero()


func close() -> void:
	visible = false
	closed_frame = Engine.get_process_frames()
	closed.emit()


func hero_id() -> String:
	return _ids[hero_i] if hero_i < _ids.size() else ""


## Puts the cursor where it is most useful: the first node that can be learned, else the root.
func _start_on_hero() -> void:
	_confirm_reset = ""
	var id := hero_id()
	sel = str(SkillTree.root(id).get("id", ""))
	for n in SkillTree.all_nodes(id):
		if SkillTree.blocker(id, str(n["id"])) == "":
			sel = str(n["id"])
			return


func _say(s: String) -> void:
	flash = s
	flash_t = 3.0


# ---------------------------------------------------------------- input

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	flash_t = maxf(flash_t - delta, 0.0)
	queue_redraw()
	if Engine.get_process_frames() == opened_frame or _ids.is_empty():
		if _ids.is_empty() and (Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause")):
			close()
		return
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("gear"):
		close()
		return
	if tabs != null and TabStrip.pressed() != 0:
		tab_picked.emit(tabs.stepped(TabStrip.pressed()))
		return
	if Input.is_action_just_pressed("swap") and TabStrip.pressed() == 0:
		_set_hero(posmod(hero_i + 1, _ids.size()))
		return
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		_step("up")
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		_step("down")
	elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left"):
		_step("left")
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
		_step("right")
	if Input.is_action_just_pressed("ui_accept"):
		_act()


func _set_hero(i: int) -> void:
	hero_i = i
	_start_on_hero()


## Walks the tree: up climbs a branch, left/right crosses to the other branch, down goes back towards the
## root and, from the root, to Unlearn.
func _step(dir: String) -> void:
	_confirm_reset = ""
	var id := hero_id()
	var root_id := str(SkillTree.root(id).get("id", ""))
	var br := SkillTree.branches(id)
	if sel == RESET:
		if dir == "up" or dir == "left":
			sel = root_id
		return
	if sel == root_id:
		match dir:
			"up", "left":
				sel = _at(0, 1)
			"right":
				sel = _at(1, 1)
			"down":
				sel = RESET
		return
	var inf := SkillTree.info(sel)
	if inf.is_empty():
		sel = root_id
		return
	var b := int(inf["branch"])
	var tier := int(inf["tier"])
	match dir:
		"up":
			sel = _at(b, mini(tier + 1, (br[b]["nodes"] as Array).size()))
		"down":
			sel = root_id if tier <= 1 else _at(b, tier - 1)
		"left", "right":
			var other := 1 - b if br.size() > 1 else b
			if (dir == "left" and b == 0) or (dir == "right" and b == br.size() - 1):
				sel = RESET if dir == "right" else sel
				return
			sel = _at(other, mini(tier, (br[other]["nodes"] as Array).size()))


func _at(branch: int, tier: int) -> String:
	var br := SkillTree.branches(hero_id())
	if branch < 0 or branch >= br.size():
		return sel
	var nodes: Array = br[branch]["nodes"]
	return str(nodes[clampi(tier - 1, 0, nodes.size() - 1)]["id"])


func _act() -> void:
	if sel == RESET:
		_reset()
	else:
		_learn(sel)


func _learn(node_id: String) -> void:
	var id := hero_id()
	var n := SkillTree.node(node_id)
	var why := SkillTree.blocker(id, node_id)
	if why == "learned":
		_say(tr("%s already knows %s.") % [PartyPicker.short_of(id), n.get("name", "")])
		return
	if why != "":
		_say(tr("Can't yet: %s.") % why)
		Audio.sfx("error")
		return
	var before := Progress.bonus(id)
	SkillTree.learn(id, node_id)
	_apply_live(id, before)
	Audio.sfx("levelup")
	_say(tr("%s learned %s.") % [PartyPicker.short_of(id), n.get("name", "")])


func _reset() -> void:
	var id := hero_id()
	var why := SkillTree.respec_blocker(id, where == "mission")
	if why != "":
		_say(tr("Can't unlearn: %s.") % why)
		return
	if _confirm_reset != id:
		_confirm_reset = id
		_say(tr("Press again to unlearn %s's whole tree for %d Gilt.") % [PartyPicker.short_of(id), SkillTree.respec_cost(id)])
		return
	var cost := SkillTree.respec_cost(id)
	SkillTree.respec(id)
	_confirm_reset = ""
	_say(tr("%s's tree is blank again (%d Gilt). %d Skill Points to spend.") % [PartyPicker.short_of(id), cost, SkillTree.points_free(id)])
	_start_on_hero()


## On a mission, the hero standing in the field changes at once.
func _apply_live(id: String, before: Dictionary) -> void:
	if party == null:
		return
	for h in party.heroes:
		if (h as Hero).hero_id == id:
			SkillTree.refresh_live(h, before)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:  # pointing at a node (or Reset) focuses it, like the arrow keys
		for k in _node_rects:
			if (_node_rects[k] as Rect2).has_point(event.position) and sel != k:
				_confirm_reset = ""
				sel = k
		if _reset_rect.has_point(event.position) and sel != RESET:
			sel = RESET
		return
	if not Prompts.tapped(event):
		return
	var p: Vector2 = event.position
	if _close_rect().has_point(p):
		close()
		return
	if tabs != null:
		var ti := tabs.hit(p)
		if ti >= 0:
			if ti != tabs.current:
				tab_picked.emit(ti)
			return
	for i in _hero_rects.size():
		if (_hero_rects[i] as Rect2).has_point(p):
			if i != hero_i:
				_set_hero(i)
			return
	for k in _node_rects:
		if (_node_rects[k] as Rect2).has_point(p):
			if sel == k:
				_learn(k)
			else:
				_confirm_reset = ""
				sel = k
			return
	if _learn_rect.has_point(p) and sel != RESET:
		_learn(sel)
		return
	if _reset_rect.has_point(p):
		if sel != RESET:
			sel = RESET
		_reset()


func _close_rect() -> Rect2:
	return Rect2(Vector2(size.x - 56, 6), Vector2(50, 16))


# ---------------------------------------------------------------- drawing

func _text(pos: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	# Text cut by its width ends in "..." rather than mid-letter (long names at large text sizes).
	draw_string(font, pos, Access.fit(font, s, Access.fs(fsize), width) if width > 0.0 else s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), col)


func _text_c(center: Vector2, s: String, fsize: int, col: Color, width := -1.0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).x
	if width > 0.0:
		w = minf(w, width)
	_text(Vector2(center.x - w / 2.0, center.y), s, fsize, col, width)


func _text_r(right: Vector2, s: String, fsize: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(fsize)).x
	_text(right - Vector2(w, 0), s, fsize, col)


func _wrap(pos: Vector2, s: String, width: float, fsize: int, col: Color) -> float:
	draw_multiline_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize), -1, col)
	return font.get_multiline_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, width, Access.fs(fsize)).y + (Access.fs(fsize) - fsize)  # bigger text (issue #34) also sits lower on its baseline


func _draw() -> void:
	var vs := size
	UiSkin.screen(self, vs)
	var cr := _close_rect()
	UiSkin.panel(self, cr, "button")
	_text(cr.position + Vector2(9, 12), tr("Close"), 9, Color(0.75, 0.72, 0.7))
	draw_string(UiSkin.TITLE_FONT, Vector2(8, 20), tr("Skill tree"), HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(16), PAPER)
	var px := 100.0
	if tabs != null:
		px = tabs.draw(self, font, Vector2(100, 7), 9) + 10.0
	_hero_rects.clear()
	_node_rects.clear()
	_reset_rect = Rect2()
	_learn_rect = Rect2()
	if _ids.is_empty():
		_text(Vector2(8, 50), tr("No field heroes with a skill tree yet."), 10, BAD)
		return
	var id := hero_id()
	_text(Vector2(px, 19), tr("Skill Points: %d free of %d") % [SkillTree.points_free(id), SkillTree.points_total(id)], 9, GOLD)
	_text_r(Vector2(vs.x - 64, 19), tr("Gilt: %d") % int(Empire.res.get("gilt", 0)), 9, GOLD)
	_draw_chips(vs)
	var split := minf(392.0, vs.x * 0.61)
	_draw_tree(Rect2(8, 58, split - 12, vs.y - 58 - 16))
	_draw_details(Rect2(split, 58, vs.x - split - 8, vs.y - 58 - 16))
	var help := Prompts.help([["updown", "climb"], ["leftright", "branch"], ["ui_accept", "learn"], ["swap", "hero"], [["ui_cancel", "gear"], "close"]],
		tr("Tap a node to look, tap again to learn; tap a hero to switch"))
	_text(Vector2(8, vs.y - 5), help, 7, Color(0.5, 0.48, 0.52))
	if flash_t > 0.0:
		var a := clampf(flash_t / 0.4, 0.0, 1.0)
		var fw := font.get_string_size(flash, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(9)).x
		var fr := Rect2(vs.x - fw - 20, vs.y - 34, fw + 12, 15)
		UiSkin.toast(self, fr, a)
		_text(fr.position + Vector2(6, 11), flash, 9, Color(1, 0.9, 0.7, a))


## Hero chips across the top, with a gold pip on anyone who has a node they could learn right now.
func _draw_chips(vs: Vector2) -> void:
	var x := 8.0
	var cw := minf(96.0, (vs.x - 16.0 - 4.0 * (_ids.size() - 1)) / _ids.size())
	for i in _ids.size():
		var hid: String = _ids[i]
		var r := Rect2(x, 30, cw, 22)
		_hero_rects.append(r)
		var on := i == hero_i
		UiSkin.row(self, r, on)
		_text(r.position + Vector2(5, 10), PartyPicker.short_of(hid), 9, GOLD if on else TEXT, cw - 26)
		_text_r(r.position + Vector2(cw - 4, 10), tr("Lv%d") % Progress.level(hid), 8, SOFT)
		var free := SkillTree.points_free(hid)
		var spent := SkillTree.points_spent(hid)
		_text(r.position + Vector2(5, 19), (Loc.n("%d pt free", "%d pts free", free) % free) if free > 0 else tr("%d spent") % spent, 7, GOLD if free > 0 else DIM)
		if SkillTree.can_spend(hid):
			draw_circle(r.position + Vector2(cw - 6, 17), 2.0 + 0.6 * sin(_t * 5.0), GOLD)
		x += cw + 4


func _node_color(id: String, node_id: String) -> Color:
	var inf := SkillTree.info(node_id)
	if int(inf.get("branch", -1)) < 0:
		return Color("d8cfa8")
	return Color(str(SkillTree.branches(id)[int(inf["branch"])].get("color", "d8cfa8")))


## The tree: branch names on top, five nodes up each side, the root at the bottom between them.
func _draw_tree(area: Rect2) -> void:
	UiSkin.panel(self, area, "ledger")
	var id := hero_id()
	var br := SkillTree.branches(id)
	if br.size() < 2:
		return
	var cols := [area.position.x + area.size.x * 0.27, area.position.x + area.size.x * 0.73]
	var w := minf(NODE.x, area.size.x * 0.45)
	var top := area.position.y + 26.0
	# Six even rows: five branch steps, then the root.
	var row := (area.end.y - 6.0 - top) / 6.0
	var nh := minf(NODE.y, row - 9.0)
	var root_c := Vector2(area.position.x + area.size.x * 0.5, top + row * 5.5)
	var centers := {}
	var root_id := str(SkillTree.root(id).get("id", ""))
	centers[root_id] = root_c
	for b in 2:
		var head: Dictionary = br[b]
		var col := Color(str(head.get("color", "d8cfa8")))
		var done := 0
		for n in head["nodes"]:
			if SkillTree.knows(id, str(n["id"])):
				done += 1
		_text_c(Vector2(cols[b], area.position.y + 16), "%s  %d/%d" % [head.get("name", "?"), done, (head["nodes"] as Array).size()], 10, col.lightened(0.25))
		UiSkin.brush(self, Vector2(cols[b] - 40, area.position.y + 19), 80, col)
		var nodes: Array = head["nodes"]
		for i in nodes.size():
			centers[str(nodes[i]["id"])] = Vector2(cols[b], top + row * (nodes.size() - 1 - i + 0.5))
	# Links first, under the nodes: lit when both ends are learned.
	for nid in centers:
		var need := SkillTree.requires(nid)
		if need == "" or not centers.has(need):
			continue
		var a: Vector2 = centers[need]
		var c: Vector2 = centers[nid]
		var lit := SkillTree.knows(id, nid) and SkillTree.knows(id, need)
		var col2 := _node_color(id, nid)
		var p0 := a + Vector2(0, -nh / 2.0)
		var p1 := c + Vector2(0, nh / 2.0)
		if need == root_id:
			var mid := Vector2(c.x, (p0.y + p1.y) / 2.0)
			draw_polyline(PackedVector2Array([p0, Vector2(p0.x, mid.y), mid, p1]), Color(col2, 0.9) if lit else Color(0.3, 0.28, 0.32), 2.0 if lit else 1.0)
		else:
			draw_line(p0, p1, Color(col2, 0.9) if lit else Color(0.3, 0.28, 0.32), 2.0 if lit else 1.0)
	for nid in centers:
		var c3: Vector2 = centers[nid]
		_draw_node(id, nid, Rect2(c3 - Vector2(w, nh) / 2.0, Vector2(w, nh)))


func _draw_node(id: String, node_id: String, r: Rect2) -> void:
	_node_rects[node_id] = r
	var n := SkillTree.node(node_id)
	var col := _node_color(id, node_id)
	var known := SkillTree.knows(id, node_id)
	var why := SkillTree.blocker(id, node_id)
	var ready := why == ""
	var locked_gate := not known and not SkillTree.gate_met(id, node_id)
	var on := sel == node_id
	var fill := Color(col.darkened(0.62), 0.95) if known else Color(0.09, 0.08, 0.11, 0.95)
	draw_rect(r, fill)
	UiSkin.tab(self, r, col, not (known or ready))
	if SkillTree.is_capstone(node_id):  # capstones wear a double frame
		draw_rect(r.grow(2.0), Color(col, 0.55 if known or ready else 0.25), false, 1.0)
	if ready:
		draw_rect(r, Color(GOLD, 0.55 + 0.35 * sin(_t * 4.0)), false, 1.0)
	elif known:
		draw_rect(r, Color(col.lightened(0.2), 0.8), false, 1.0)
	else:
		draw_rect(r, Color(0.32, 0.3, 0.34), false, 1.0)
	if on:
		UiSkin.highlight(self, r.grow(1.0), GOLD)
	var name_col := PAPER if known else (GOLD if ready else (DIM if locked_gate else SOFT))
	_text(r.position + Vector2(8, r.size.y * 0.5 - 2), str(n.get("name", "?")), 9, name_col, r.size.x - 34)
	var sub := ""
	if known:
		sub = tr("Learned")
	elif ready:
		sub = Loc.n("Learn: %d pt", "Learn: %d pts", SkillTree.cost(node_id)) % SkillTree.cost(node_id)
	elif locked_gate:
		sub = SkillTree.gate_text(id, node_id)
	elif why.begins_with("holds"):
		sub = tr("Other capstone held")
	else:
		sub = Loc.n("%d pt", "%d pts", SkillTree.cost(node_id)) % SkillTree.cost(node_id)
	_text(r.position + Vector2(8, r.size.y - 4), sub, 8, GOOD if known else (GOLD if ready else DIM), r.size.x - 22)
	# Cost pips, top right.
	for k in SkillTree.cost(node_id):
		var pc := r.position + Vector2(r.size.x - 8 - k * 6, 8)
		var pts := PackedVector2Array([pc + Vector2(0, -2.5), pc + Vector2(2.5, 0), pc + Vector2(0, 2.5), pc + Vector2(-2.5, 0)])
		draw_colored_polygon(pts, col if known else (GOLD if ready else Color(0.4, 0.38, 0.42)))
	if locked_gate:
		_lock(r.position + Vector2(r.size.x - 9, r.size.y - 9))


## A small padlock for nodes behind a bond rank.
func _lock(at: Vector2) -> void:
	draw_arc(at + Vector2(0, -2), 2.2, PI, TAU, 8, SOFT, 1.0)
	draw_rect(Rect2(at + Vector2(-3, -1.5), Vector2(6, 4.5)), SOFT)


func _draw_details(area: Rect2) -> void:
	UiSkin.panel(self, area, "ledger")
	var id := hero_id()
	var x := area.position.x + 8
	var w := area.size.x - 16
	# Reset button pinned to the bottom of the panel, under the page.
	_reset_rect = Rect2(x, area.end.y - 22, w, 16)
	var rwhy := SkillTree.respec_blocker(id, where == "mission")
	UiSkin.panel(self, _reset_rect, "button", Color(1, 1, 1, 1.0 if rwhy == "" else 0.55))
	if sel == RESET:
		UiSkin.highlight(self, _reset_rect.grow(1.0), GOLD)
	var rlabel := (tr("Unlearn all: %d Gilt") % SkillTree.respec_cost(id)) if not SkillTree.learned(id).is_empty() else tr("Unlearn all")
	if _confirm_reset == id:
		rlabel = tr("Press again: unlearn for %d Gilt") % SkillTree.respec_cost(id)
	_text_c(_reset_rect.position + Vector2(w / 2.0, 11), rlabel, 8, (GOLD if sel == RESET else TEXT) if rwhy == "" else DIM, w - 8)
	# The rest is written up on a ledger page (LedgerPage), on its lines.
	var pg := LedgerPage.begin(self, Rect2(area.position + Vector2(5, 5), Vector2(area.size.x - 10, _reset_rect.position.y - area.position.y - 9)), font)
	if sel == RESET:
		pg.heading(tr("Unlearn the tree"), 12)
		pg.para(tr("Every node %s has learned is forgotten and every Skill Point comes back, to spend another way. Costs %d Gilt, plus %d for each point spent.") % [
			PartyPicker.short_of(id), int(SkillTree.data().get("respec", {}).get("base", 30)), int(SkillTree.data().get("respec", {}).get("per_point", 10))], 8, LedgerPage.INK)
		pg.skip()
		pg.line((tr("Ready: %d Gilt.") % SkillTree.respec_cost(id)) if rwhy == "" else tr("Can't: %s.") % rwhy, 8, LedgerPage.GOLD if rwhy == "" else LedgerPage.RED)
		_learn_rect = Rect2()
		return
	var n := SkillTree.node(sel)
	if n.is_empty():
		return
	var inf := SkillTree.info(sel)
	var col := _node_color(id, sel)
	var branch_name := tr("Root") if int(inf["branch"]) < 0 else str(SkillTree.branches(id)[int(inf["branch"])].get("name", ""))
	var tag := branch_name if int(inf["branch"]) < 0 else "%s, %s" % [branch_name, tr("capstone") if SkillTree.is_capstone(sel) else tr("step %d of 5") % int(inf["tier"])]
	pg.heading(str(n.get("name", "?")), 14, LedgerPage.ink(col))
	pg.line(tag, 8, LedgerPage.ink(col), Loc.n("%d Skill Point", "%d Skill Points", SkillTree.cost(sel)) % SkillTree.cost(sel), LedgerPage.GOLD)
	pg.para(str(n.get("desc", "")), 8, LedgerPage.INK)
	pg.para(str(n.get("flavor", "")), 8, LedgerPage.INK_SOFT)
	if int(inf["branch"]) >= 0 and int(inf["tier"]) == 1:
		pg.para(str(SkillTree.branches(id)[int(inf["branch"])].get("blurb", "")), 7, LedgerPage.INK_SOFT)
	if SkillTree.is_capstone(sel):
		pg.para(tr("Capstone: a hero can hold only one. Unlearn the tree to switch."), 7, LedgerPage.INK_SOFT)
	var gate := SkillTree.gate_text(id, sel)
	if gate != "":
		var met := SkillTree.gate_met(id, sel)
		pg.line((tr("Needs %s") if not met else tr("Unlocked by %s")) % gate, 8, LedgerPage.GREEN if met else LedgerPage.RED)
		if not met and id != "ash":
			pg.para(tr("Bonds grow by fighting beside %s, talking in Hollowmark and giving them work they like%s.") % [PartyPicker.short_of(id), Prompts.tag("bonds")], 7, LedgerPage.INK_SOFT)
		elif not met:
			pg.para(tr("Ash is written by the people around them: grow your bonds with the others%s.") % Prompts.tag("bonds"), 7, LedgerPage.INK_SOFT)
	# Learn button, on the next two lines of the page (or its last two, if the text ran long).
	var why := SkillTree.blocker(id, sel)
	pg.line_i = mini(pg.line_i, pg.lines - 2)
	var br := pg.space(2)
	_learn_rect = Rect2(br.position.x, br.end.y - 16.0, br.size.x, 15.0)
	if why == "learned":
		_text_c(_learn_rect.get_center() + Vector2(0, 4), tr("Learned"), 9, LedgerPage.GREEN, _learn_rect.size.x)
	else:
		UiSkin.panel(self, _learn_rect, "button", Color(1, 1, 1, 1.0 if why == "" else 0.5))
		var label := (tr("%s  Learn for %d") % [Prompts.confirm(), SkillTree.cost(sel)]) if why == "" else tr("Can't yet: %s") % why
		_text_c(_learn_rect.get_center() + Vector2(0, 4), label, 8, GOLD if why == "" else DIM, _learn_rect.size.x - 8)
	# The abilities this node changes, as they read with it (a preview until it is learned).
	for aid in n.get("effects", {}).get("abilities", {}):
		var a := _ability_with(id, str(aid), sel)
		if a.is_empty() or pg.left() < 2:
			continue
		pg.line("%s %s" % [a.get("name", aid), Loc.t("now") if why == "learned" else tr("with it")], 8, LedgerPage.GOLD)
		var facts := tr("%d Ink, %s s cooldown.  ") % [int(a.get("cost", 0)), Abilities._num(a.get("cooldown", 1))]
		pg.para(facts + Abilities.desc_of(a), 7, LedgerPage.INK)
	if pg.left() >= 2:
		var names := SkillTree.learned(id).map(func(k): return str(SkillTree.node(k).get("name", k)))
		pg.line(tr("Learned so far"), 8, LedgerPage.INK_SOFT)
		pg.para(", ".join(names) if not names.is_empty() else tr("Nothing yet."), 7, LedgerPage.INK_SOFT if names.is_empty() else LedgerPage.INK)


## The ability as this hero would have it with node_id learned too (or as it is, once learned).
func _ability_with(id: String, aid: String, node_id: String) -> Dictionary:
	var list: Array = SkillTree.learned(id)
	var added := not node_id in list
	if added:
		list.append(node_id)
	var out := {}
	for a in Abilities.for_ids(PartyPicker.hero_data(id).get("abilities", []), id):
		if str(a.get("id", "")) == aid:
			out = a
	if added:
		list.erase(node_id)
	return out
