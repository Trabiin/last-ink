extends RefCounted
## Chapter 4 (issue #30): the Harbour Moot became a faction with land.
##
## - Trevail Harbour (province "saltgrave") belongs to the Harbour Moot. Old saves have it as free land; it gets its
##   new owner unless the player already holds it or the Blank has it.
## - The coast region opens with Chapter 4's first beat (ch4_tide, then: open_region:coast), so nothing is opened
##   here: an old campaign past the end of Chapter 3 sees that beat on its next visit to town.
## Standing with the new faction needs nothing here: factions missing from a save start at their "start".

const OWNERS := {"saltgrave": "moot"}


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
