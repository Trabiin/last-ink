class_name Assists
extends RefCounted
## Assists (issue #192): separate switches next to the difficulty, for anyone who wants the story without
## the fight getting in the way. Static like Settings and Access and saved in the same file
## (user://settings.cfg, section [assists]), so they are per device. They never lock anything: no
## achievement, ending, reward or story beat checks them, and the game never comments on them.
##
##   Assists.hero_damage(amount)   damage a hero takes after the difficulty (Settings.difficulty_damage)
##   Assists.pace()                1.0 or less: enemies scale their delta and speed by it (Enemy._slide)
##   Assists.recover               refill the party's health when no enemy is near (main.gd)
##   Assists.skip_fights           "Skip this fight" in the pause menu of story missions (main.gd)
##   Assists.gentle_blank()        the Blank presses less on the Command Table (Empire.fray_sources, surge_fray)
##   Assists.allow_pause           the clock gets its stop button back, and the Esc menu leaves the map in view
##   Assists.half_clock            the clock gets a 0.5x speed (Empire.speed_allowed)

const SECTION := "assists"

const DAMAGE := [100, 75, 50, 25]  # percent of the damage the party takes
const PACE := [1.0, 0.85, 0.7]
const PACE_NAMES := ["Normal", "Slower", "Slowest"]
const BLANK := ["Auto", "Gentle", "Full"]
const BLANK_INFO := [
	"Gentle on Story difficulty, full otherwise.",
	"Fray grows about 40% slower and surges hit softer, on any difficulty.",
	"The Blank presses as designed, on any difficulty.",
]
const GENTLE_SHARE := 0.4  # share of a province's daily Fray growth a gentle Blank takes off
const GENTLE_SURGE := 0.6  # a surge's Fray times this

static var damage_i := 0
static var pace_i := 0
static var recover := false
static var skip_fights := false
static var blank_i := 0
static var allow_pause := false
static var half_clock := false

static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(Settings.PATH) != OK:
		return
	damage_i = clampi(int(cfg.get_value(SECTION, "damage", damage_i)), 0, DAMAGE.size() - 1)
	pace_i = clampi(int(cfg.get_value(SECTION, "pace", pace_i)), 0, PACE.size() - 1)
	recover = bool(cfg.get_value(SECTION, "recover", recover))
	skip_fights = bool(cfg.get_value(SECTION, "skip_fights", skip_fights))
	blank_i = clampi(int(cfg.get_value(SECTION, "blank", blank_i)), 0, BLANK.size() - 1)
	allow_pause = bool(cfg.get_value(SECTION, "allow_pause", allow_pause))
	half_clock = bool(cfg.get_value(SECTION, "half_clock", half_clock))


static func save() -> void:
	load_settings()
	var cfg := ConfigFile.new()
	cfg.load(Settings.PATH)  # keep every other section
	cfg.set_value(SECTION, "damage", damage_i)
	cfg.set_value(SECTION, "pace", pace_i)
	cfg.set_value(SECTION, "recover", recover)
	cfg.set_value(SECTION, "skip_fights", skip_fights)
	cfg.set_value(SECTION, "blank", blank_i)
	cfg.set_value(SECTION, "allow_pause", allow_pause)
	cfg.set_value(SECTION, "half_clock", half_clock)
	cfg.save(Settings.PATH)


## Back to the defaults (the tests and the Assists page's reset row).
static func reset() -> void:
	load_settings()
	damage_i = 0
	pace_i = 0
	recover = false
	skip_fights = false
	blank_i = 0
	allow_pause = false
	half_clock = false
	save()


## Any assist switched on? (the Options row says so; nothing else looks)
static func any_on() -> bool:
	load_settings()
	return damage_i != 0 or pace_i != 0 or recover or skip_fights or blank_i == 1 or allow_pause or half_clock


## May the player stop the clock? (Empire.speed_allowed, and the Esc menu's view of the map)
static func pause_allowed() -> bool:
	load_settings()
	return allow_pause


static func half_clock_on() -> bool:
	load_settings()
	return half_clock


static func hero_damage(amount: int) -> int:
	if not _loaded:
		load_settings()
	if damage_i == 0 or amount <= 0:
		return amount
	return maxi(1, roundi(amount * DAMAGE[damage_i] / 100.0))


## Enemy pace: every enemy multiplies its frame's delta by this and moves at this share of its speed.
static func pace() -> float:
	if not _loaded:
		load_settings()
	return PACE[pace_i]


## Does the Blank press gently on the Command Table right now?
static func gentle_blank() -> bool:
	load_settings()
	if blank_i == 1:
		return true
	if blank_i == 2:
		return false
	Settings.load_settings()
	return Settings.difficulty == 0


## The Command Table line that takes a gentle Blank's share off a province's daily Fray growth, or [] when
## there is nothing to take off. `total` = the rate from every other source.
static func fray_source(total: int) -> Array:
	if total <= 0 or not gentle_blank():
		return []
	return [Loc.t("Gentle Blank (assist)"), -ceili(total * GENTLE_SHARE)]


static func surge_fray(fray: int) -> int:
	return roundi(fray * GENTLE_SURGE) if gentle_blank() else fray
