class_name TechFx
extends Node2D
## How a charged tech's blast looks (issue #24): one short-lived node per blast, drawn in code in the
## tech's colour. data/techs.json gives each tech an "fx" motif; size, direction and arc come from the blast.
##
##   burst   a disc of ink that pops, with droplets flying out        (Full Stop, Ellipsis)
##   slash   bright crescent cuts crossing the area                   (Comma Splice, Cut and Run, ...)
##   sweep   a wedge with a leading edge that sweeps across it         (Breach of Contract, Severance, ...)
##   line    a narrow thrust with a glint at the tip                   (Skewer, Twin Prongs, Flourish, ...)
##   beam    a thick bar with a white core, struck along a line        (Redaction, Concord Breaker, Balestra)
##   seal    a square stamp that drops and lands with cross-hatching    (Final Demand, Repossession, Writ)
##   shock   rings of force rolling outward on the ground              (Through the Door, Bar Brawl, ...)
##   spiral  arms curling inward: a pull                               (Fine Print, Hook and Haul, ...)
##   pillar  a column of light from the ground and a ring at its foot  (The End, Closing Time)
##   shards  spikes bursting outward                                   (Liquidation, Knife Storm)
##   splash  blobs of broth thrown out and falling back                (Stir the Pot, Simmer, ...)
##   stars   twinkling stars across the area                           (Bone Broth)
##   coins   coins thrown up, glinting, raining down                   (Compound Interest, Garnish)
##   petals  petals whirling out and drifting down                     (Curtain Call)

const MOTIFS := ["burst", "slash", "sweep", "line", "beam", "seal", "shock", "spiral", "pillar", "shards", "splash", "stars", "coins", "petals"]
const LIFE := {"pillar": 0.6, "seal": 0.5, "coins": 0.7, "petals": 0.8, "stars": 0.7, "splash": 0.6, "shock": 0.5}
const FLAT := 0.55  # ground ellipses: how squashed a circle on the floor looks from this angle

var motif := "burst"
var dir := Vector2.RIGHT
var reach := 30.0
var half := PI
var color := Color.WHITE
var life := 0.0
var max_life := 0.45
var bits: Array = []  # per-motif particles: [pos, vel, size, spin]


static func spawn(parent: Node, kind: String, at: Vector2, d: Vector2, r: float, h: float, col: Color, _delayed := false) -> TechFx:
	var f := TechFx.new()
	f.motif = kind if kind in MOTIFS else "burst"
	f.position = at
	f.dir = d.normalized() if d.length() > 0.01 else Vector2.RIGHT
	f.reach = r
	f.half = h
	f.color = col
	f.max_life = float(LIFE.get(f.motif, 0.45))
	f.z_index = 40
	f._seed()
	parent.add_child(f)
	return f


## A point inside the blast's area (disc or wedge), for scattering particles.
func _point_in(rng: RandomNumberGenerator, frac := 1.0) -> Vector2:
	var a := rng.randf() * TAU if half >= PI - 0.01 else dir.angle() + rng.randf_range(-half, half)
	return Vector2.from_angle(a) * reach * frac * sqrt(rng.randf())


func _seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(motif) ^ int(position.x * 13.0) ^ int(position.y * 7.0)
	match motif:
		"burst":
			for i in 14:
				var a := rng.randf() * TAU if half >= PI - 0.01 else dir.angle() + rng.randf_range(-half, half)
				bits.append([Vector2.ZERO, Vector2.from_angle(a) * rng.randf_range(reach * 1.5, reach * 3.0), rng.randf_range(1.0, 2.5), 0.0])
		"shards":
			var n := 10 if half >= PI - 0.01 else 6
			for i in n:
				var a := (float(i) / n) * TAU + rng.randf_range(-0.2, 0.2) if half >= PI - 0.01 else dir.angle() + lerpf(-half, half, float(i) / maxf(n - 1, 1))
				bits.append([Vector2.from_angle(a), Vector2.ZERO, rng.randf_range(0.6, 1.0), 0.0])
		"splash":
			for i in 12:
				var a := rng.randf() * TAU
				bits.append([Vector2.ZERO, Vector2.from_angle(a) * rng.randf_range(reach * 0.8, reach * 1.8), rng.randf_range(1.5, 3.0), rng.randf_range(40.0, 70.0)])
		"stars":
			for i in 9:
				bits.append([_point_in(rng), Vector2.ZERO, rng.randf_range(2.0, 4.0), rng.randf() * TAU])
		"coins":
			for i in 12:
				bits.append([_point_in(rng, 0.8), Vector2(rng.randf_range(-20, 20), rng.randf_range(-90, -50)), rng.randf_range(1.5, 2.5), rng.randf() * TAU])
		"petals":
			for i in 16:
				var a := rng.randf() * TAU
				bits.append([Vector2.from_angle(a) * rng.randf_range(2.0, 8.0), Vector2.from_angle(a + 0.6) * rng.randf_range(reach * 0.9, reach * 1.6), rng.randf_range(1.5, 2.6), rng.randf() * TAU])
		"slash":
			for i in 3:
				bits.append([Vector2.ZERO, Vector2.ZERO, rng.randf_range(0.7, 1.0), rng.randf_range(-0.6, 0.6)])


func _process(delta: float) -> void:
	life += delta
	if life >= max_life:
		queue_free()
		return
	match motif:
		"burst", "splash", "petals":
			for b in bits:
				b[0] += b[1] * delta
				b[1] *= 0.86
		"coins":
			for b in bits:
				b[0] += b[1] * delta
				b[1].y += 260.0 * delta
	queue_redraw()


func _ground_ring(r: float, col: Color, width := 1.5) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, FLAT))
	draw_arc(Vector2.ZERO, r, 0, TAU, 36, col, width)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _wedge(r: float, col: Color, a0: float, a1: float) -> void:
	if half >= PI - 0.01:
		draw_circle(Vector2.ZERO, r, col)
		return
	var n := clampi(int(rad_to_deg(a1 - a0) / 12.0), 1, 16)
	var pts := PackedVector2Array([Vector2.ZERO])
	for k in n + 1:
		pts.append(Vector2.from_angle(lerpf(a0, a1, float(k) / n)) * r)
	draw_colored_polygon(pts, col)


func _draw() -> void:
	var t := life / max_life
	var a := 1.0 - t
	var hi := color.lightened(0.5)
	match motif:
		"burst":
			draw_circle(Vector2.ZERO, reach * (0.4 + 0.6 * minf(t * 3.0, 1.0)), Color(color, 0.45 * a))
			_ground_ring(reach * (0.5 + 0.6 * t), Color(hi, a), 2.0)
			for b in bits:
				draw_rect(Rect2(b[0] - Vector2(b[2], b[2]) / 2.0, Vector2(b[2], b[2])), Color(color.lightened(0.2), a))
		"slash":
			var base := dir.angle()
			for i in bits.size():
				var b: Array = bits[i]
				var show := clampf((t - i * 0.12) * 4.0, 0.0, 1.0)
				if show <= 0.0:
					continue
				var span := minf(half, 1.2) if half < PI - 0.01 else 1.3
				var c := base + float(b[3]) + (PI if i == 1 and half >= PI - 0.01 else 0.0)
				var r: float = reach * float(b[2])
				var fade := Color(hi, a * show)
				draw_arc(Vector2.ZERO, r, c - span * show, c + span * show, 14, fade, 2.5)
				draw_arc(Vector2.ZERO, r - 3.0, c - span * show * 0.8, c + span * show * 0.8, 12, Color(color, a * 0.7), 1.5)
		"sweep":
			var lead := lerpf(-half, half, minf(t * 2.2, 1.0)) if half < PI - 0.01 else TAU * minf(t * 2.2, 1.0) - PI
			var a0 := dir.angle() - (half if half < PI - 0.01 else PI)
			_wedge(reach * (0.7 + 0.3 * t), Color(color, 0.35 * a), a0, dir.angle() + lead)
			var edge := Vector2.from_angle(dir.angle() + lead)
			draw_line(edge * 4.0, edge * reach, Color(hi, a), 2.5)
			draw_arc(Vector2.ZERO, reach, a0, dir.angle() + lead, 18, Color(hi, a * 0.8), 1.5)
		"line":
			var ln := reach * minf(t * 4.0, 1.0)
			var w := clampf(tan(minf(half, 0.6)) * reach, 2.0, 5.0)
			var side := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([side * w, dir * ln, -side * w]), Color(color, 0.6 * a))
			draw_line(Vector2.ZERO, dir * ln, Color(hi, a), 1.0)
			var tip := dir * ln
			draw_line(tip - side * 4.0 * a, tip + side * 4.0 * a, Color(Color.WHITE, a), 1.0)
			draw_line(tip - dir * 4.0 * a, tip + dir * 4.0 * a, Color(Color.WHITE, a), 1.0)
		"beam":
			var len2 := reach * minf(t * 6.0, 1.0)
			var w2 := clampf(tan(minf(half, 0.6)) * reach, 4.0, 9.0) * (1.0 + (0.0 if Access.reduce_flashing else 0.3 * sin(life * 60.0)))  # the beam's crackle is a 10 Hz flicker
			var side2 := dir.orthogonal()
			var quad := PackedVector2Array([side2 * w2, side2 * w2 + dir * len2, -side2 * w2 + dir * len2, -side2 * w2])
			draw_colored_polygon(quad, Color(color.darkened(0.35), 0.9 * a))
			draw_line(Vector2.ZERO, dir * len2, Color(hi, a), 1.0)
			draw_line(side2 * w2, side2 * w2 + dir * len2, Color(hi, a * 0.8), 1.0)
			draw_line(-side2 * w2, -side2 * w2 + dir * len2, Color(hi, a * 0.8), 1.0)
		"seal":
			var drop := maxf(0.0, 1.0 - t * 5.0)  # falls in, then lands
			var s := reach * 0.75 * (1.0 + drop * 0.6)
			var off := Vector2(0, -24.0 * drop)
			draw_set_transform(off, 0.0, Vector2(1.0, FLAT))
			var sq := PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s), Vector2(-s, -s)])
			draw_colored_polygon(PackedVector2Array([Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)]), Color(color, 0.35 * a))
			draw_polyline(sq, Color(hi, a), 2.0)
			for k in 4:  # cross-hatching of the seal's face
				var f := -s + (k + 1) * s * 2.0 / 5.0
				draw_line(Vector2(f, -s), Vector2(-s, f), Color(color, 0.7 * a), 1.0)
			draw_arc(Vector2.ZERO, s * 0.55, 0, TAU, 24, Color(hi, a), 1.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if drop <= 0.0:
				_ground_ring(reach * (1.0 + t * 0.4), Color(color, a * 0.8), 1.5)
		"shock":
			for k in 3:
				var tk := clampf((t - k * 0.15) / 0.7, 0.0, 1.0)
				if tk > 0.0:
					_ground_ring(reach * tk, Color(hi if k == 0 else color, (1.0 - tk) * 0.9), 2.5 - k * 0.5)
			draw_circle(Vector2.ZERO, reach * 0.25 * a, Color(Color.WHITE, Access.calm(0.5 * a)))
		"spiral":
			var spin := life * 9.0
			for k in 6:
				var pts := PackedVector2Array()
				for j in 8:
					var u := float(j) / 7.0
					var rr := reach * (1.0 - t * 0.7) * (1.0 - u * 0.85)
					pts.append(Vector2.from_angle(spin + k * TAU / 6.0 + u * 2.2) * rr * Vector2(1.0, FLAT + 0.2))
				draw_polyline(pts, Color(hi if k % 2 == 0 else color, a), 1.5)
			_ground_ring(reach * (1.0 - t * 0.6), Color(color, a * 0.6), 1.0)
		"pillar":
			var w3 := reach * 0.35 * (1.0 - t * 0.5)
			var hgt := 70.0 * minf(t * 4.0, 1.0)
			draw_rect(Rect2(-w3, -hgt, w3 * 2.0, hgt), Color(color, 0.35 * a))
			draw_rect(Rect2(-w3 * 0.35, -hgt, w3 * 0.7, hgt), Color(Color.WHITE, Access.calm(0.6 * a)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, FLAT))
			draw_circle(Vector2.ZERO, reach * minf(t * 2.5, 1.0), Color(color, 0.3 * a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_ground_ring(reach * (0.6 + 0.5 * t), Color(hi, a), 2.5)
		"shards":
			var g := minf(t * 3.0, 1.0)
			for b in bits:
				var d: Vector2 = b[0]
				var len3: float = reach * float(b[2]) * g
				var side3 := d.orthogonal() * 2.5
				var base_p := d * len3 * 0.2
				draw_colored_polygon(PackedVector2Array([base_p + side3, d * len3, base_p - side3]), Color(hi, a))
			_ground_ring(reach * 0.5 * g, Color(color, a * 0.7), 1.5)
		"splash":
			_ground_ring(reach * (0.4 + 0.6 * t), Color(color, a * 0.8), 2.0)
			for b in bits:
				var arc_y := -float(b[3]) * sin(t * PI)  # thrown up, falling back
				var p: Vector2 = b[0] * Vector2(1.0, FLAT) + Vector2(0, arc_y * 0.5)
				draw_circle(p, float(b[2]) * (1.0 - t * 0.4), Color(color.lightened(0.15), a))
		"stars":
			for b in bits:
				var tw := 0.5 + 0.5 * sin(life * 14.0 + float(b[3]))
				var s2: float = float(b[2]) * tw * a
				var p2: Vector2 = b[0] * Vector2(1.0, FLAT)
				draw_line(p2 - Vector2(s2, 0), p2 + Vector2(s2, 0), Color(hi, a), 1.0)
				draw_line(p2 - Vector2(0, s2), p2 + Vector2(0, s2), Color(hi, a), 1.0)
				draw_circle(p2, 0.8, Color(Color.WHITE, a))
			draw_circle(Vector2.ZERO, reach * 0.8 * minf(t * 3.0, 1.0), Color(color, 0.18 * a))
		"coins":
			_ground_ring(reach * (0.5 + 0.5 * t), Color(color, a * 0.7), 1.5)
			for b in bits:
				var p3: Vector2 = b[0] * Vector2(1.0, FLAT)
				var flip := absf(sin(life * 16.0 + float(b[3])))
				draw_set_transform(p3, 0.0, Vector2(maxf(flip, 0.2), 1.0))
				draw_circle(Vector2.ZERO, float(b[2]), Color(color, a))
				draw_circle(Vector2(-0.5, -0.5), float(b[2]) * 0.4, Color(Color.WHITE, a * flip))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"petals":
			for b in bits:
				var p4: Vector2 = b[0] * Vector2(1.0, FLAT) + Vector2(0, 14.0 * t * t)
				draw_set_transform(p4, float(b[3]) + life * 5.0, Vector2(1.0, 0.5))
				draw_circle(Vector2.ZERO, float(b[2]), Color(color.lightened(0.2 * sin(float(b[3]))), a))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_ground_ring(reach * minf(t * 2.0, 1.0), Color(hi, a * 0.7), 1.5)
