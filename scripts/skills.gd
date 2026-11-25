class_name Skills
## Weapon and Ink skill levels (issue #24), Mana style: using something makes you better at it.
##
## Weapon skill: one per field hero, for their signature weapon (data/heroes.json "weapon"), level 1 to 5.
## Landed swings and techs give points (data/gear.json "skills"); every level teaches the next of the
## hero's five charged techs (data/techs.json). The Barracks drills benched heroes, but only up to
## barracks_cap: the last techs are learned in real fights.
##
## Ink skill: each hero has a level 1 to 5 in every Ink colour (red, blue, gold, green, black; and white, which only
## Ilse can hold, Chapter 4 #30: menus show it only for heroes with a White Ink ability). Spending
## Ink on an ability of that colour raises it (data/abilities.json "ink_skill"). Levels 2 and 4 put the
## colour's abilities on their stronger tiers; 3 and 5 shorten their cooldowns.
##
## State lives with the rest of a hero's progress (Empire.progress, scripts/progress.gd):
##   heroes[id]["weapon"] = {"xp": int, "level": int}
##   heroes[id]["inks"]   = {color: {"xp": int, "level": int}}   (colours never used are left out)
##   heroes[id]["tech"]   = picked tech id, or "" to choose by how long Attack is held

const INKS := ["red", "blue", "gold", "green", "black", "white"]
## Colours only listed for heroes who use them (Ilse alone touches White Ink).
const RARE_INKS := ["white"]


static func _skills() -> Dictionary:
	return Progress.data().get("skills", {})


static func max_level() -> int:
	return int(_skills().get("max", 5))


# ---------------------------------------------------------------- weapon

static func weapon(id: String) -> Dictionary:
	var h := Progress.hero(id)
	if typeof(h.get("weapon")) != TYPE_DICTIONARY:
		h["weapon"] = {"xp": 0, "level": 1}
	return h["weapon"]


static func weapon_level(id: String) -> int:
	return clampi(int(weapon(id).get("level", 1)), 1, max_level())


## Points from this weapon level to the next (0 at the top).
static func weapon_to_next(lvl: int) -> int:
	var xs: Array = _skills().get("weapon_xp", [80, 180, 320, 520])
	if lvl >= max_level() or lvl - 1 >= xs.size():
		return 0
	return int(xs[lvl - 1])


static func weapon_fraction(id: String) -> float:
	var need := weapon_to_next(weapon_level(id))
	return 1.0 if need <= 0 else clampf(float(weapon(id).get("xp", 0)) / need, 0.0, 1.0)


static func weapon_name(id: String) -> String:
	return str(PartyPicker.hero_data(id).get("weapon", Loc.t("Weapon")))


## Adds weapon points. Returns the new levels reached (usually [] or [n]). cap: highest level these
## points can reach (the Barracks stops at barracks_cap); points past a cap are kept but go no further.
static func add_weapon(id: String, pts: int, cap := -1) -> Array:
	var ups := []
	if pts <= 0:
		return ups
	var w := weapon(id)
	var top := max_level() if cap < 0 else mini(cap, max_level())
	var lvl := weapon_level(id)
	if lvl >= top:
		return ups
	w["xp"] = int(w.get("xp", 0)) + pts
	while lvl < top and int(w["xp"]) >= weapon_to_next(lvl):
		w["xp"] = int(w["xp"]) - weapon_to_next(lvl)
		lvl += 1
		ups.append(lvl)
	w["level"] = lvl
	if lvl >= max_level():
		w["xp"] = 0
	elif lvl >= top:
		w["xp"] = mini(int(w["xp"]), weapon_to_next(lvl) - 1)  # drills top out just short of the next level
	return ups


## Points a landed swing is worth (0 for a weak, early swing).
static func swing_points(power: float) -> int:
	if power >= 1.0:
		return int(_skills().get("swing", 2))
	if power >= 0.5:
		return int(_skills().get("light_swing", 1))
	return 0


static func tech_points() -> int:
	return int(_skills().get("tech", 4))


## Barracks drill at dawn: benched field heroes gain weapon points, up to barracks_cap.
## Returns the level-ups: [{"id", "level"}].
static func drill_bench() -> Array:
	var out := []
	var lvl := Empire.level_of("barracks")
	if lvl <= 0:
		return out
	var pts := int(_skills().get("barracks", 5)) * lvl
	for id in Progress.field_ids():
		if Empire.role_of(id) == "party":
			continue
		for n in add_weapon(id, pts, barracks_cap()):
			out.append({"id": id, "level": n})
	return out


static func barracks_cap() -> int:
	return int(_skills().get("barracks_cap", 3))


static func barracks_points() -> int:
	return int(_skills().get("barracks", 5)) * Empire.level_of("barracks")


# ---------------------------------------------------------------- techs

## Every tech this hero has (5), in level order.
static func all_techs(id: String) -> Array:
	return Techs.list(id)


## The techs this hero knows at their weapon level.
static func known_techs(id: String) -> Array:
	return all_techs(id).slice(0, weapon_level(id))


## The tech learned at this weapon level ({} if none).
static func tech_at(id: String, lvl: int) -> Dictionary:
	var all := all_techs(id)
	return all[lvl - 1] if lvl >= 1 and lvl <= all.size() else {}


## The picked tech id, or "" (by hold length). A pick the hero no longer knows reads as "".
static func pick(id: String) -> String:
	var p := str(Progress.hero(id).get("tech", ""))
	if p == "" or not known_techs(id).any(func(t): return t["id"] == p):
		return ""
	return p


static func set_pick(id: String, tech_id: String) -> void:
	Progress.hero(id)["tech"] = tech_id


static func picked_tech(id: String) -> Dictionary:
	var p := pick(id)
	for t in known_techs(id):
		if t["id"] == p:
			return t
	return {}


# ---------------------------------------------------------------- Ink colours

static func ink_data() -> Dictionary:
	return Abilities.data().get("ink_skill", {})


static func ink_info(color: String) -> Dictionary:
	return Abilities.data().get("inks", {}).get(color, {})


static func ink_name(color: String) -> String:
	return str(ink_info(color).get("name", color.capitalize()))


static func ink_color(color: String) -> Color:
	return Color(str(ink_info(color).get("color", "9fd8ff")))


static func _ink(id: String, color: String) -> Dictionary:
	var h := Progress.hero(id)
	if typeof(h.get("inks")) != TYPE_DICTIONARY:
		h["inks"] = {}
	var inks: Dictionary = h["inks"]
	if typeof(inks.get(color)) != TYPE_DICTIONARY:
		inks[color] = {"xp": 0, "level": 1}
	return inks[color]


static func ink_level(id: String, color: String) -> int:
	var inks = Progress.hero(id).get("inks", {})
	if typeof(inks) != TYPE_DICTIONARY or typeof(inks.get(color)) != TYPE_DICTIONARY:
		return 1
	return clampi(int(inks[color].get("level", 1)), 1, ink_max())


static func ink_xp(id: String, color: String) -> int:
	var inks = Progress.hero(id).get("inks", {})
	if typeof(inks) != TYPE_DICTIONARY or typeof(inks.get(color)) != TYPE_DICTIONARY:
		return 0
	return int(inks[color].get("xp", 0))


static func ink_max() -> int:
	return int(ink_data().get("max", 5))


static func ink_to_next(lvl: int) -> int:
	var xs: Array = ink_data().get("xp", [30, 70, 120, 190])
	if lvl >= ink_max() or lvl - 1 >= xs.size():
		return 0
	return int(xs[lvl - 1])


static func ink_fraction(id: String, color: String) -> float:
	var need := ink_to_next(ink_level(id, color))
	return 1.0 if need <= 0 else clampf(float(ink_xp(id, color)) / need, 0.0, 1.0)


## Adds Ink colour points (the Ink spent). Returns the new levels reached.
static func add_ink(id: String, color: String, pts: int) -> Array:
	var ups := []
	if pts <= 0 or not color in INKS:
		return ups
	var s := _ink(id, color)
	var lvl := clampi(int(s.get("level", 1)), 1, ink_max())
	if lvl >= ink_max():
		return ups
	s["xp"] = int(s.get("xp", 0)) + pts
	while lvl < ink_max() and int(s["xp"]) >= ink_to_next(lvl):
		s["xp"] = int(s["xp"]) - ink_to_next(lvl)
		lvl += 1
		ups.append(lvl)
	s["level"] = lvl
	if lvl >= ink_max():
		s["xp"] = 0
	return ups


## How much shorter this colour's cooldowns are at this level (0.15 = 15%).
static func cooldown_cut(lvl: int) -> float:
	var cuts: Dictionary = ink_data().get("cooldown_cut", {})
	var best := 0.0
	for k in cuts:
		if lvl >= int(k):
			best = maxf(best, float(cuts[k]))
	return best


## The colours this hero's abilities use, in INKS order.
static func colors_of(id: String) -> Array:
	var used := {}
	for a in Abilities.for_ids(PartyPicker.hero_data(id).get("abilities", [])):
		used[str(a.get("ink", ""))] = true
	return INKS.filter(func(c): return used.has(c))


## What a colour level does, for menus: "stronger tier", "cooldowns -15%".
static func ink_level_text(lvl: int) -> String:
	if lvl == 2 or lvl == 4:
		return Loc.t("tier %d abilities") % (2 if lvl == 2 else 3)
	var cut := cooldown_cut(lvl)
	if cut > 0.0 and cut > cooldown_cut(lvl - 1):
		return Loc.t("cooldowns -%d%%") % int(round(cut * 100.0))
	return ""


# ---------------------------------------------------------------- saves

## Cleans a saved hero's skill fields (from Progress.from_save). Unknown colours and picks are dropped.
static func clean_into(src: Dictionary, out: Dictionary) -> void:
	var w = src.get("weapon")
	if typeof(w) == TYPE_DICTIONARY:
		out["weapon"] = {"xp": maxi(int(w.get("xp", 0)), 0), "level": clampi(int(w.get("level", 1)), 1, max_level())}
	var inks = src.get("inks")
	if typeof(inks) == TYPE_DICTIONARY:
		var clean := {}
		for c in inks:
			if c in INKS and typeof(inks[c]) == TYPE_DICTIONARY:
				clean[c] = {"xp": maxi(int(inks[c].get("xp", 0)), 0), "level": clampi(int(inks[c].get("level", 1)), 1, ink_max())}
		out["inks"] = clean
	var t := str(src.get("tech", ""))
	if t != "" and Techs.find(t).is_empty():
		t = ""
	out["tech"] = t
