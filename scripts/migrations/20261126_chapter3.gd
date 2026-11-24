extends RefCounted
## Chapter 3 (issue #29): the Velvet Nobility became a faction with land.
##
## - The Velvet Causeway (province "causeway") belongs to the Velvet Nobility. Old saves have it as Concord land;
##   it gets its new owner unless the player already holds it or the Blank has it.
## - The Causeway region opens with Chapter 3's first beat (ch3_invitation, then: open_region:causeway), so
##   nothing is opened here: an old campaign past the end of Chapter 2 sees that beat on its next visit to town.
## Standing with the new faction needs nothing here: factions missing from a save start at their "start".

const OWNERS := {"causeway": "velvet"}


static func migrate(save: Dictionary) -> Dictionary:
	var empire: Dictionary = save.get("empire", {})
	if empire.is_empty():
		return save
	var provinces = empire.get("provinces", [])
	if typeof(provinces) == TYPE_ARRAY:
		for p in provinces:
			if typeof(p) == TYPE_DICTIONARY and OWNERS.has(str(p.get("id", ""))) and not str(p.get("owner", "")) in ["you", "erased"]:
				p["owner"] = OWNERS[str(p["id"])]
	return save
