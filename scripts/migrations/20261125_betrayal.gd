extends RefCounted
## The climax betrayal (issue #186, scripts/betrayal.gd): the campaign's relations gain
## empire.relations.betrayal = {"fell", "betrayer", "day"}.
##
## Dated after 20261124_names so it runs last of the current steps.
##
## The leverage score asks whether a candidate's home "fell once and was reclaimed", which older builds never
## wrote down. Two things in an old save prove a fall: a province erased right now, and a cleared Reclaim
## mission (id "reclaim_<province>"; you can only reclaim erased land). Each counts once per province, so an
## old save can under-count repeat falls but never invents one. Nobody has betrayed anyone yet.
## A save that already has the field, or has no campaign, is left alone.


static func migrate(save: Dictionary) -> Dictionary:
	var empire = save.get("empire", {})
	if typeof(empire) != TYPE_DICTIONARY or empire.is_empty():
		return save
	var rel = empire.get("relations", {})
	if typeof(rel) != TYPE_DICTIONARY:
		rel = {}
	if rel.has("betrayal"):
		return save
	var fell := {}
	for p in empire.get("provinces", []):
		if typeof(p) == TYPE_DICTIONARY and str(p.get("owner", "")) == "erased":
			fell[str(p.get("id", ""))] = 1
	for mid in empire.get("missions_cleared", []):
		var s := str(mid)
		if s.begins_with("reclaim_"):
			fell[s.trim_prefix("reclaim_")] = 1
	fell.erase("")
	rel["betrayal"] = {"fell": fell, "betrayer": "", "day": 0}
	empire["relations"] = rel
	return save
