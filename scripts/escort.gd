class_name Escort
extends Hero
## Someone who can't fight, brought along on a personal mission (issue #113): Quill, Tobble, Sister
## Hild. They follow the leader, shy away from anything with teeth and never swing. Enemies go for
## them like any hero (they are in the "heroes" group), so keeping them standing is the job.
## A step can send them somewhere (go_to) and they walk there and wait, working whatever is there.

const FOLLOW := 26.0
const SHY := 46.0

var dest := Vector2.INF  # where a step sent them; INF = follow the leader
var arrived := false


func _ready() -> void:
	super._ready()
	peaceful = true  # no techs, no abilities, no swings


func go_to(p: Vector2) -> void:
	dest = p
	arrived = false


func follow() -> void:
	dest = Vector2.INF
	arrived = false


func _ai(delta: float) -> Vector2:
	var leader: Hero = party.leader if party else null
	if detour_t > 0.0:  # walked into a tree: step round it, like the allies do
		detour_t -= delta
		return detour_dir
	if stuck_t > 0.35:
		stuck_t = 0.0
		detour_t = 0.4
		var aim := dest if dest != Vector2.INF else (leader.global_position if leader else global_position + Vector2.RIGHT)
		detour_dir = (aim - global_position).normalized().rotated(PI / 2.0 * ai_side)
		ai_side = -ai_side
		return detour_dir
	var threat := _nearest_enemy(global_position, SHY)
	if dest != Vector2.INF:
		var to := dest - global_position
		arrived = to.length() < 10.0
		if arrived:
			if threat != null:  # flinch, but don't wander off the job
				facing = (threat.global_position - global_position).normalized()
			return Vector2.ZERO
		return path_dir(dest) * (0.75 if threat != null else 1.0)
	if threat != null:
		var away := (global_position - threat.global_position).normalized()
		if leader != null and not leader.dead:
			away = (away + (leader.global_position - global_position).normalized() * 0.6).normalized()
		return away
	if leader == null or leader.dead:
		return Vector2.ZERO
	var to_leader := leader.global_position - global_position
	if to_leader.length() > 380.0:
		global_position = leader.global_position - leader.facing * 18.0
		return Vector2.ZERO
	if to_leader.length() > FOLLOW:
		return path_dir(leader.global_position) * (1.0 if to_leader.length() > FOLLOW * 2.0 else 0.6)
	return Vector2.ZERO
