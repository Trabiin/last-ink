class_name BossFight
extends MissionObjectives
## The "boss" objective kind (issue #17): one big fight in its own arena, with a boss HP bar,
## an intro talk when the party walks up, a mid-fight talk at the phase change and an outro
## once the boss is down. Objective hands the mission's objective here when kind == "boss".
##
## objective: {"kind": "boss", "boss": "auditor", "label": "Strike out the Auditor"}
## The map marks where the boss stands with "@mark<char> boss". The arena has no Blank and no
## stream of Nibblers; phase 2 calls in a few adds (BOSSES[id].adds).
## Talks (data/dialogue.json): <boss>_intro, <boss>_phase2, <boss>_outro. Each plays once per
## campaign, so retrying after a wipe goes straight back into the fight (from the autosave made
## at the arena entrance; there are no autosaves mid-fight).

const BOSSES := {
	"auditor": {
		"script": preload("res://scripts/auditor.gd"),
		"name": "THE AUDITOR", "title": "Concord Office of Corrections",
		"adds": "nibbler", "adds_max": 3, "adds_every": 13.0,
	},
}
const WAKE_RANGE := 150.0

var boss: Enemy
var info := {}
var stage := "approach"  # approach, fight, outro, end
var stage_t := 0.0
var adds_t := 0.0
var bar: Control


func setup(p_obj: Dictionary, p_main) -> void:
	obj = p_obj
	kind = "boss"
	main = p_main
	var id: String = obj.get("boss", "auditor")
	info = BOSSES.get(id, BOSSES["auditor"])
	main.respawn_t = 1e9  # no Nibbler stream from the (absent) Blank in a boss arena
	var spots: Array = main.area.markers.get("boss", [])
	boss = info["script"].new()
	boss.position = spots[0] if not spots.is_empty() else Vector2(main.world.x / 2.0, 96.0)
	boss.facing = Vector2.DOWN
	main.entities.add_child(boss)
	boss.floor_node = main.area
	boss.arena = Rect2(Vector2(24, 24), main.world - Vector2(48, 40))
	boss.died.connect(main._on_enemy_died)  # XP and the kill count like any enemy
	boss.phase_changed.connect(_on_phase)
	pointer = MissionObjectives.Pointer.new()
	pointer.obj = self
	main.hud.get_parent().add_child(pointer)
	bar = BossBar.new()
	bar.fight = self
	main.hud.get_parent().add_child(bar)
	# One autosave at the arena entrance with everyone fresh; none during the fight, so
	# "Try again" never drops a battered party back in front of a fully healed boss.
	main.autosave()
	main.autosave_t = 1e9


func _talk_id(suffix: String) -> String:
	return "%s_%s" % [obj.get("boss", "auditor"), suffix]


func on_kill() -> void:
	pass


func update(delta: float) -> void:
	main.respawn_t = 1e9
	main.autosave_t = 1e9
	stage_t += delta
	match stage:
		"approach":
			var lead: Hero = main.leader
			if lead and (lead.global_position.distance_to(boss.global_position) < WAKE_RANGE or stage_t > 20.0):
				stage = "fight"
				stage_t = 0.0
				boss.wake()
				if not Dialogue.is_seen("talk:" + _talk_id("intro")):
					main.play_talk(_talk_id("intro"))
		"fight":
			if boss.dead:
				stage = "outro"
				stage_t = 0.0
				for e in main.get_tree().get_nodes_in_group("enemies"):  # the clerks scatter
					if e != boss and not (e as Actor).dead:
						Fx.burst(main.entities, (e as Node2D).global_position, [Color.WHITE, Color.BLACK], 10, 60.0)
						(e as Node).queue_free()
				return
			if boss.phase == 2:
				adds_t -= delta
				if adds_t <= 0.0:
					adds_t = float(info["adds_every"])
					_call_adds()
		"outro":
			if stage_t > 2.4:
				stage = "end"
				stage_t = 0.0
				if not Dialogue.is_seen("talk:" + _talk_id("outro")):
					main.play_talk(_talk_id("outro"))
		"end":
			pass


func _on_phase(_p: int) -> void:
	main.hud.say(tr("FINAL NOTICE. He is not holding back any more."), 3.0)
	Audio.sfx("burst", 0.6)
	adds_t = 1.2
	if not Dialogue.is_seen("talk:" + _talk_id("phase2")):
		main.play_talk(_talk_id("phase2"))


## A few clerks join in phase 2, from the edges of the arena.
func _call_adds() -> void:
	var count: int = main.get_tree().get_nodes_in_group("enemies").filter(func(e): return e != boss).size()
	var want: int = int(info["adds_max"]) - count
	for i in mini(want, 2):
		var x: float = 40.0 if randf() < 0.5 else main.world.x - 40.0
		var pos := Vector2(x, randf_range(80.0, main.world.y - 80.0))
		for e in EnemyKinds.spawn(main.entities, pos, main.mission, str(info["adds"])):
			e.died.connect(main._on_enemy_died)
		Fx.burst(main.entities, pos + Vector2(0, -6), [Color.WHITE, Color.BLACK], 8, 50.0)


func done() -> bool:
	return stage == "end" and stage_t > 0.6


func failed() -> bool:
	return false  # a wiped party is the usual game over


func fail_text() -> String:
	return ""


func text() -> String:
	match stage:
		"approach":
			return tr("Face the Auditor at the tollgate")
		"fight":
			return str(obj.get("label", tr("Strike out the Auditor")))
	return tr("The Auditor is struck out")


func target_pos():
	return boss.global_position if stage == "approach" and is_instance_valid(boss) else null


func exit_visible() -> bool:
	return false


## The boss HP bar along the top of the screen.
class BossBar extends Control:
	var fight  # BossFight
	var shown := 0.0  # fades in when the fight starts
	var lag := 1.0  # the white "recent damage" part of the bar

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		var on: bool = fight.stage == "fight" or (fight.stage == "outro" and fight.stage_t < 1.5)
		shown = move_toward(shown, 1.0 if on else 0.0, delta * 3.0)
		var r := 0.0
		if is_instance_valid(fight.boss):
			r = clampf(float(fight.boss.hp) / float(fight.boss.max_hp), 0.0, 1.0)
		lag = maxf(r, move_toward(lag, r, delta * 0.35)) if lag > r else r
		queue_redraw()

	func _draw() -> void:
		if shown <= 0.0:
			return
		# Bottom centre, above the party panels (the top is where banter and tips go).
		var vs := get_viewport_rect().size
		var w := minf(240.0, vs.x - 300.0)
		var x := (vs.x - w) / 2.0
		var y := vs.y - 58.0
		var a := shown
		var f := ThemeDB.fallback_font
		var title: String = fight.info["name"]
		draw_string_outline(f, Vector2(x, y - 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10), 3, Color(0, 0, 0, 0.85 * a))
		draw_string(f, Vector2(x, y - 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(10), Color(0.96, 0.92, 0.82, a))
		draw_rect(Rect2(x - 2, y - 1, w + 4, 9), Color(0.05, 0.04, 0.08, 0.8 * a))
		var r := 0.0
		var phase := 1
		if is_instance_valid(fight.boss):
			r = clampf(float(fight.boss.hp) / float(fight.boss.max_hp), 0.0, 1.0)
			phase = fight.boss.phase
		draw_rect(Rect2(x, y + 1, w * lag, 5), Color(1, 1, 1, 0.7 * a))
		draw_rect(Rect2(x, y + 1, w * r, 5), Color("d2463c" if phase == 1 else "8a1f2a", a))
		var px := x + w * Auditor.PHASE2_AT  # where Final Notice starts
		draw_line(Vector2(px, y - 1), Vector2(px, y + 8), Color(0.96, 0.92, 0.82, 0.8 * a), 1.0)
		var sub: String = fight.info["title"] if phase == 1 else tr("Final Notice")
		var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7)).x
		draw_string_outline(f, Vector2(x + w - sw, y - 4), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), 2, Color(0, 0, 0, 0.8 * a))
		draw_string(f, Vector2(x + w - sw, y - 4), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, Access.fs(7), Color(0.8, 0.76, 0.68, a) if phase == 1 else Color("ff8a7a", a))
