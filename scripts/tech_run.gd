class_name TechRun
extends Node2D
## The blasts of a tech that go off after the release (issue #24): the later hits of a multi-hit tech,
## the seals or full stops of a chain marching forward, and delayed techs (The End, Simmer, Closing Time,
## Writ of Erasure, Curtain Call). Lives in the world beside the heroes and removes itself when done.
##
## Telegraph: every blast still to come is marked on the ground in the tech's colour, with a ring that
## closes in on its edge and meets it the moment it goes off, so enemies and players can read when and
## where. Uses scaled time, so the quick menu's slow motion slows it too.

const SHOW_AHEAD := 0.9  # seconds before a blast that its mark appears

var hero: Hero
var tech: Dictionary
var pending: Array = []  # blasts from Techs.blasts(), sorted by time
var state: Dictionary
var t := 0.0
var color := Color.WHITE


static func start(parent: Node, h: Hero, tk: Dictionary, later: Array, st: Dictionary) -> TechRun:
	var r := TechRun.new()
	r.hero = h
	r.tech = tk
	r.pending = later.duplicate()
	r.pending.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	r.state = st
	r.color = Color(str(tk.get("color", "ffe08a")))
	r.z_index = -1  # on the ground, under the actors
	parent.add_child(r)
	FxLayer.adopt(r, true)  # drawn as pixel art on the ground picture (scripts/fx_layer.gd)
	return r


func _process(delta: float) -> void:
	t += delta
	while not pending.is_empty() and float(pending[0]["time"]) <= t:
		var b: Dictionary = pending.pop_front()
		if is_instance_valid(hero):
			Techs.pulse(hero, tech, b, state)
	if pending.is_empty() or not is_instance_valid(hero):
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	for b in pending:
		var left := float(b["time"]) - t
		if left > SHOW_AHEAD:
			continue
		var k := 1.0 - clampf(left / SHOW_AHEAD, 0.0, 1.0)  # 0 when it appears, 1 when it goes off
		var flick := 0.5 + 0.5 * sin(t * (10.0 + 20.0 * k))
		var mark: Dictionary = b.duplicate()
		mark["at"] = (b["at"] as Vector2) - global_position
		Techs.draw_blast(self, mark, color, 0.4 + 0.5 * k * flick, 0.08 + 0.18 * k, k)
		# The closing ring: meets the blast's edge as it goes off.
		var c: Vector2 = mark["at"]
		var reach: float = b["reach"]
		draw_arc(c, reach * (1.6 - 0.6 * k), 0, TAU, 36, Color(color.lightened(0.4), 0.3 + 0.6 * k), 1.0)
		if float(tech.get("delay", 0)) > 0.0:
			# Delayed techs show what is coming: a little glyph at the centre in the tech's colour.
			_glyph(c, reach, k)


func _glyph(c: Vector2, reach: float, k: float) -> void:
	var col := Color(color.lightened(0.3), 0.5 + 0.5 * k)
	match str(tech.get("fx", "")):
		"splash":  # bubbles rising off the pot
			for i in 5:
				var ph := fmod(t * 1.6 + i * 0.37, 1.0)
				var p := c + Vector2(cos(i * 2.1) * reach * 0.4, -ph * 12.0)
				draw_arc(p, 1.5 + ph * 1.5, 0, TAU, 8, col, 1.0)
		"seal":  # the seal's shadow growing as it falls
			var s := reach * 0.6 * k
			draw_rect(Rect2(c - Vector2(s, s * 0.55), Vector2(s * 2.0, s * 1.1)), Color(0, 0, 0, 0.25 * k))
		"petals":
			for i in 6:
				var a := t * 3.0 + i * TAU / 6.0
				draw_circle(c + Vector2.from_angle(a) * reach * 0.5 * (1.0 - k * 0.5), 1.5, col)
		_:  # pillar and the rest: a written line pulsing at the centre
			draw_line(c - Vector2(reach * 0.3, 0), c + Vector2(reach * 0.3, 0), col, 1.0)
			draw_circle(c, 2.0 + 2.0 * k, Color(col, 0.6))
