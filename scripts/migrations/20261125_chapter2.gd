extends RefCounted
## Chapter 2 (issue #28): Saint Ledger's Abbey and the Erasers became factions with land, and the end of Act 1
## now lifts the fog over the Abbey's region.
##
## - Saint Ledger's Abbey (province "abbey") belongs to the Abbey and the Bonefield Cloister ("ossuary") to the
##   Erasers. Old saves have them as Concord and free land; they get their new owners unless the player already
##   holds them or the Blank has them.
## - A campaign that already saw the End of Act 1 opens the Abbey region, which the act1_end beat now does
##   (then: open_region:abbey). Chapter 2's first beat then plays on the next visit to Hollowmark.
## Standing with the two new factions needs nothing here: factions missing from a save start at their "start".

const OWNERS := {"abbey": "abbey", "ossuary": "erasers"}


static func migrate(save: Dictionary) -> Dictionary:
	var empire: Dictionary = save.get("empire", {})
	if empire.is_empty():
		return save
	var provinces = empire.get("provinces", [])
	if typeof(provinces) == TYPE_ARRAY:
		for p in provinces:
			if typeof(p) == TYPE_DICTIONARY and OWNERS.has(str(p.get("id", ""))) and not str(p.get("owner", "")) in ["you", "erased"]:
				p["owner"] = OWNERS[str(p["id"])]
	var seen = empire.get("dialogue", {})
	if typeof(seen) == TYPE_DICTIONARY and seen.has("talk:act1_end"):
		var regions: Array = empire.get("regions", ["marches"])
		if not "abbey" in regions:
			regions.append("abbey")
		empire["regions"] = regions
	return save
