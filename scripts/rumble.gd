class_name Rumble
extends RefCounted
## Gamepad rumble (issue #149, Steam Deck / controller): a kick when your hero lands a hit or a tech,
## a harder one when your hero is hurt or goes down, and a quake for boss slams and the biggest blasts.
## Static like Settings; the strength is saved with the other options (Settings.rumble_i, Options >
## Rumble: Off, Light, Full).
##
## Only the hero you control rumbles the pad (allies hitting things don't), and only while you are
## playing on a gamepad: keyboard and touch players never get a buzzing controller on the desk.
## A weaker kick never cuts a stronger one short. Screen shake has its own option, so turning the
## shake off (motion sickness) keeps the rumble, and the other way round.

const LEVELS := ["Off", "Light", "Full"]
const LEVEL_MULT := [0.0, 0.5, 1.0]
const LEVEL_INFO := [
	"The controller never vibrates.",
	"Soft vibration on hits, techs and when your hero is hurt.",
	"Vibration on hits, techs, when your hero is hurt and when bosses slam the ground.",
]

## The last vibration asked for, for the tests: {"weak", "strong", "time", "device"}.
static var last := {}
static var _until := 0.0  # engine time when the current vibration ends
static var _power := 0.0  # its strength (the larger motor)


## Strength multiplier for the current option (0 when off).
static func scale() -> float:
	Settings.load_settings()
	return LEVEL_MULT[Settings.rumble_i]


## Your hero's swing or ability connected. power 0..1 (how charged the swing was).
static func landed(h: Node, power := 0.5) -> void:
	if _is_leader(h):
		kick(0.25 + 0.25 * clampf(power, 0.0, 1.0), 0.05 + 0.15 * clampf(power, 0.0, 1.0), 0.09)


## Your hero fired a tech (big = it hit hard: Full Stop, a crowd-wide blast).
static func tech(h: Node, big := false) -> void:
	if _is_leader(h):
		kick(0.6 if big else 0.45, 0.7 if big else 0.4, 0.28 if big else 0.18)


## Your hero took damage. share = how much of their max HP it took (0..1).
static func hurt(h: Node, share := 0.1) -> void:
	if _is_leader(h):
		var s := clampf(0.45 + share * 2.0, 0.45, 1.0)
		kick(s * 0.7, s, 0.16 + 0.2 * clampf(share * 3.0, 0.0, 1.0))


## Your hero went down.
static func downed(h: Node) -> void:
	if _is_leader(h):
		kick(1.0, 1.0, 0.45)


## The ground shook: boss slams and the biggest blasts (the mission scene's shake of 4.5 and up).
static func quake(amount: float) -> void:
	if amount >= 4.5:
		var s := clampf(amount / 7.0, 0.0, 1.0)
		kick(s * 0.8, s, 0.15 + amount * 0.04)


## Stops any vibration (a menu or conversation opening, the mission ending).
static func stop() -> void:
	_until = 0.0
	_power = 0.0
	for d in Input.get_connected_joypads():
		Input.stop_joy_vibration(d)


## The raw vibration, scaled by the option. weak/strong are the two motors (0..1), duration in seconds.
static func kick(weak: float, strong: float, duration: float) -> void:
	var m := scale()
	if m <= 0.0 or not Prompts.pad():
		return
	weak = clampf(weak * m, 0.0, 1.0)
	strong = clampf(strong * m, 0.0, 1.0)
	var now := Time.get_ticks_msec() / 1000.0
	var power := maxf(weak, strong)
	if now < _until and power < _power:
		return  # don't cut a stronger kick short
	_until = now + duration
	_power = power
	last = {"weak": weak, "strong": strong, "time": duration, "device": Prompts.pad_id}
	Input.start_joy_vibration(Prompts.pad_id, weak, strong, duration)


static func _is_leader(h: Node) -> bool:
	if h == null or not is_instance_valid(h):
		return false
	var party = h.get("party")
	return party != null and is_instance_valid(party) and party.get("leader") == h
