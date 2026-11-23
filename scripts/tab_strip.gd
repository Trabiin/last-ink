class_name TabStrip
extends RefCounted
## The tab row every tabbed screen shares (Party gear, Forge & Market, the Journal, the quick menu):
## the tabs plus a button glyph on either side, so how to switch is right there instead of in the footer.
##   keyboard  [Q] Equip  Skills  Tree [E]
##   Xbox pad  [LB] ...  [RB]      PlayStation [L1] ... [R1]      Nintendo [L] ... [R]
##   touch     <  ...  >           (tap a glyph or a tab)
## Glyph labels come from the live bindings through Prompts.key(), so a rebound key or a swapped pad shows
## at once. Every screen switches tabs the same way: the tab_prev / tab_next actions (Q / E and LB / RB by
## default, rebindable in Options), a click or tap on a tab, or a click or tap on either glyph.
##
## Use: keep one TabStrip per screen, set `labels` and `current` before drawing, call draw() from _draw(),
## step with TabStrip.pressed() (polling screens) or TabStrip.step(event) (event screens), and pass clicks
## and taps to hit().

const PREV := "tab_prev"
const NEXT := "tab_next"
const GOLD := Color("e8c65a")
const SOFT := Color(0.72, 0.69, 0.66)
const KEY_INK := Color("f3e3c3")
const GAP := 4.0

var labels: Array = []  # what each tab says
var current := 0
var rects: Array = []  # Rect2 per tab, from the last draw (for clicks and taps)
var prev_rect := Rect2()
var next_rect := Rect2()


func _init(tab_labels: Array = [], at := 0) -> void:
	labels = tab_labels
	current = at


## How tall the row is at this font size (grows with Text size in Accessibility).
static func height(fsize := 9) -> float:
	return maxf(15.0, Access.fs(fsize) + 6.0)


## Draws the row with its top-left at `at`. With width > 0 the tabs share that width evenly (glyphs
## included); otherwise each tab is as wide as its label. Returns the x where the row ends.
func draw(ci: CanvasItem, font: Font, at: Vector2, fsize := 9, width := 0.0) -> float:
	var h := height(fsize)
	var sfsize := Access.fs(fsize)
	rects.clear()
	var x := at.x
	prev_rect = glyph(ci, font, Vector2(x, at.y), h, PREV, -1, fsize)
	x = prev_rect.end.x + GAP
	var next_w := glyph_width(font, NEXT, h, fsize)
	var even := 0.0
	if width > 0.0 and labels.size() > 0:
		even = (at.x + width - next_w - GAP - x - GAP * (labels.size() - 1)) / labels.size()
	for i in labels.size():
		var label := str(labels[i])
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sfsize).x
		var w := even if even > 0.0 else lw + 14.0
		var r := Rect2(x, at.y, w, h)
		rects.append(r)
		var on := i == current
		UiSkin.panel(ci, r, "button", Color(1.25, 1.15, 0.95) if on else Color(0.75, 0.72, 0.7))
		var shown := Access.fit(font, label, sfsize, w - 8.0) if lw > w - 8.0 else label
		var sw := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, sfsize).x
		ci.draw_string(font, Vector2(r.position.x + (w - sw) / 2.0, _baseline(font, r, sfsize)), shown,
			HORIZONTAL_ALIGNMENT_LEFT, -1, sfsize, GOLD if on else SOFT)
		x += w + GAP
	next_rect = glyph(ci, font, Vector2(x, at.y), h, NEXT, 1, fsize)
	return next_rect.end.x


## -1 for the tab to the left, 1 for the right, 0 for neither, this frame (screens that poll Input).
static func pressed() -> int:
	if InputMap.has_action(PREV) and Input.is_action_just_pressed(PREV):
		return -1
	if InputMap.has_action(NEXT) and Input.is_action_just_pressed(NEXT):
		return 1
	return 0


## The same from one input event (screens that use _input or _unhandled_input).
static func step(event: InputEvent) -> int:
	if event.is_echo():
		return 0
	if InputMap.has_action(PREV) and event.is_action_pressed(PREV):
		return -1
	if InputMap.has_action(NEXT) and event.is_action_pressed(NEXT):
		return 1
	return 0


## The tab a click or tap at p picks (a glyph steps from the current tab, wrapping round), or -1.
func hit(p: Vector2) -> int:
	if labels.is_empty():
		return -1
	for i in rects.size():
		if (rects[i] as Rect2).has_point(p):
			return i
	if prev_rect.grow(2.0).has_point(p):
		return posmod(current - 1, labels.size())
	if next_rect.grow(2.0).has_point(p):
		return posmod(current + 1, labels.size())
	return -1


## The index after stepping d tabs from the current one, wrapping round.
func stepped(d: int) -> int:
	return posmod(current + d, maxi(labels.size(), 1))


# ---------------------------------------------------------------- glyphs

## What the glyph for this action says on the device in use: "Q", "LB", "R1"... or "" for an arrow
## (touch, or nothing bound on this device).
static func glyph_label(action: String) -> String:
	return Prompts.key(action)


static func glyph_width(font: Font, action: String, h: float, fsize := 9) -> float:
	var label := glyph_label(action)
	if label == "":
		return roundf(h * 0.8)
	var sfsize := Access.fs(fsize)
	return maxf(h, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sfsize).x + 10.0)


## Draws one glyph with its top-left at `at`: a small brass-rimmed key with the bound key or button on it,
## or an ink arrow pointing `dir` on touch. Returns its rect (tappable).
static func glyph(ci: CanvasItem, font: Font, at: Vector2, h: float, action: String, dir: int, fsize := 9) -> Rect2:
	var label := glyph_label(action)
	var r := Rect2(at, Vector2(glyph_width(font, action, h, fsize), h))
	if label == "":
		_arrow(ci, r, dir)
		return r
	var sfsize := Access.fs(fsize)
	var cap := r.grow_individual(-1, -2, -1, -1)  # a touch smaller than a tab, so it reads as a key
	UiSkin.panel(ci, cap, "button", Color(0.5, 0.48, 0.5))
	var sw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sfsize).x
	ci.draw_string(font, Vector2(cap.position.x + (cap.size.x - sw) / 2.0, _baseline(font, cap, sfsize)), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sfsize, KEY_INK)
	return r


## A small gold arrowhead with a darker ink edge, the same as the quick menu's row marker.
static func _arrow(ci: CanvasItem, r: Rect2, dir: int) -> void:
	var c := r.get_center()
	var s := minf(r.size.y * 0.32, 5.0)
	var tip := Vector2(c.x + s * dir, c.y)
	var pts := PackedVector2Array([tip, Vector2(c.x - s * 0.7 * dir, c.y - s), Vector2(c.x - s * 0.7 * dir, c.y + s)])
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 1))
	ci.draw_colored_polygon(shadow, Color(0.1, 0.07, 0.05, 0.8))
	ci.draw_colored_polygon(pts, GOLD)


static func _baseline(font: Font, r: Rect2, sfsize: int) -> float:
	var asc := font.get_ascent(sfsize)
	var desc := font.get_descent(sfsize)
	return roundf(r.position.y + (r.size.y - (asc + desc)) / 2.0 + asc)
