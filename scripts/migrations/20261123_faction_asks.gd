extends RefCounted
## Faction asks arrive (issue #131, scripts/faction_asks.gd): the campaign gains
## empire.asks = {"next", "offers", "active", "ended", "effects", "log"}.
##
## Dated after 20261122_relationships so it runs last of the current steps.
##
## An older save has never been asked anything: nothing is on offer, nothing accepted, nothing ended.
## So the three factions don't all knock on the same dawn, their first asks are spread over the next
## few days (two, three and four days after the day the save was made, in data/factions.json order).
## A save that already has asks, or has no campaign, is left alone.


static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY or empire.is_empty() or empire.has("asks"):
		return save
	var today := maxi(int(empire.get("day", 1)), 1)
	var next := {}
	var i := 0
	for fid in _faction_ids():
		next[fid] = today + 2 + i
		i += 1
	empire["asks"] = {"next": next, "offers": {}, "active": {}, "ended": {}, "effects": [], "log": []}
	return save


## The factions this step knew (frozen: factions added later schedule their first ask themselves, at the
## first dawn they are on the open map, issue #28).
static func _faction_ids() -> Array:
	return ["guild", "coven", "concord"]
