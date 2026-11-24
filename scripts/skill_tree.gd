class_name SkillTree
## Per-hero skill trees (issue #25). Every field hero has a root node and two branches of five nodes that
## reflect who they are (Bran: Bodyguard or Turncoat). Nodes are bought in order with Skill Points, one per
## level past 1, and change how the hero plays: stats, ability variants (new riders, wider arcs, shorter
## cooldowns), passives (scripts/tree_perks.gd) and who the ally AI goes for. The last node of each branch
## is a capstone, and a hero holds only one. The deeper nodes need the hero's bond with Ash (Ash, who has
## no bond, needs bonds with the others instead). Unlearning a tree costs Gilt and only happens off-mission.
## Data: data/skill_trees.json. Screen: scripts/skill_tree_view.gd.
##
## State lives with the rest of a hero's progress (Empire.progress, scripts/progress.gd):
##   heroes[id]["tree"] = [node id, ...]   in the order they were learned

const FILE := "res://data/skill_trees.json"

static var _data := {}
static var _nodes := {}  # node id -> {"node", "hero", "branch" (index, -1 = root), "tier" (0 = root, 1-5)}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(FILE, FileAccess.READ)
		if f:
			var parsed = Loc.data(JSON.parse_string(f.get_as_text()), f.get_path().get_file())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		_index()
	return _data


static func _index() -> void:
	_nodes.clear()
	var trees: Dictionary = _data.get("trees", {})
	for hero in trees:
		var t: Dictionary = trees[hero]
		var root: Dictionary = t.get("root", {})
		if not root.is_empty():
			_nodes[str(root["id"])] = {"node": root, "hero": hero, "branch": -1, "tier": 0}
		var branches: Array = t.get("branches", [])
		for b in branches.size():
			var nodes: Array = branches[b].get("nodes", [])
			for i in nodes.size():
				_nodes[str(nodes[i]["id"])] = {"node": nodes[i], "hero": hero, "branch": b, "tier": i + 1}


static func has_tree(id: String) -> bool:
	return data().get("trees", {}).has(id)


static func tree(id: String) -> Dictionary:
	return data().get("trees", {}).get(id, {})


static func branches(id: String) -> Array:
	return tree(id).get("branches", [])


static func root(id: String) -> Dictionary:
	return tree(id).get("root", {})


## A node by id ({} if unknown).
static func node(node_id: String) -> Dictionary:
	data()
	return _nodes.get(node_id, {}).get("node", {})


static func info(node_id: String) -> Dictionary:
	data()
	return _nodes.get(node_id, {})


## Every node of a hero's tree: root, then branch 0 in order, then branch 1.
static func all_nodes(id: String) -> Array:
	var out := []
	if not root(id).is_empty():
		out.append(root(id))
	for b in branches(id):
		out.append_array(b.get("nodes", []))
	return out


# ---------------------------------------------------------------- state and points

static func learned(id: String) -> Array:
	var h := Progress.hero(id)
	if typeof(h.get("tree")) != TYPE_ARRAY:
		h["tree"] = []
	return h["tree"]


static func knows(id: String, node_id: String) -> bool:
	return node_id in learned(id)


static func cost(node_id: String) -> int:
	return int(node(node_id).get("cost", 1))


## Skill Points earned so far: per_level for every level past 1.
static func points_total(id: String) -> int:
	return maxi(Progress.level(id) - 1, 0) * int(data().get("points", {}).get("per_level", 1))


static func points_spent(id: String) -> int:
	var n := 0
	for k in learned(id):
		n += cost(k)
	return n


static func points_free(id: String) -> int:
	return maxi(points_total(id) - points_spent(id), 0)


## Field heroes on the roster with points they could spend on a node right now.
static func unspent_ids() -> Array:
	return Progress.field_ids().filter(func(id): return has_tree(id) and can_spend(id))


static func can_spend(id: String) -> bool:
	if points_free(id) <= 0:
		return false
	for n in all_nodes(id):
		if blocker(id, str(n["id"])) == "":
			return true
	return false


# ---------------------------------------------------------------- learning

## The node that must be known first ("" for the root).
static func requires(node_id: String) -> String:
	var inf := info(node_id)
	if inf.is_empty() or int(inf["tier"]) == 0:
		return ""
	if int(inf["tier"]) == 1:
		return str(root(inf["hero"]).get("id", ""))
	var nodes: Array = branches(inf["hero"])[int(inf["branch"])]["nodes"]
	return str(nodes[int(inf["tier"]) - 2]["id"])


static func is_capstone(node_id: String) -> bool:
	return bool(node(node_id).get("capstone", false))


## The capstone this hero already holds, other than node_id ("" if none).
static func other_capstone(id: String, node_id: String) -> String:
	for k in learned(id):
		if k != node_id and is_capstone(k):
			return k
	return ""


## What the node's bond gate asks for, in words ("" if it has none).
static func gate_text(id: String, node_id: String) -> String:
	var n := node(node_id)
	if n.has("bond"):
		return Loc.t("%s bond: %s") % [PartyPicker.short_of(id), Empire.bond_rank_name(int(n["bond"]))]
	if n.has("bonds"):
		var g: Array = n["bonds"]
		return Loc.n("%d bond at %s or closer", "%d bonds at %s or closer", int(g[1])) % [int(g[1]), Empire.bond_rank_name(int(g[0]))]
	return ""


static func gate_met(id: String, node_id: String) -> bool:
	var n := node(node_id)
	if n.has("bond") and Empire.bond_rank(id) < int(n["bond"]):
		return false
	if n.has("bonds"):
		var g: Array = n["bonds"]
		var have := Empire.bond_ids().filter(func(b): return Empire.bond_rank(b) >= int(g[0])).size()
		if have < int(g[1]):
			return false
	return true


## Why this hero can't learn this node now ("" if they can).
static func blocker(id: String, node_id: String) -> String:
	var inf := info(node_id)
	if inf.is_empty() or inf["hero"] != id:
		return Loc.t("not in this tree")
	if knows(id, node_id):
		return "learned"
	var need := requires(node_id)
	if need != "" and not knows(id, need):
		return Loc.t("learn %s first") % node(need).get("name", need)
	if is_capstone(node_id) and other_capstone(id, node_id) != "":
		return Loc.t("holds %s (one capstone per hero)") % node(other_capstone(id, node_id)).get("name", "")
	if not gate_met(id, node_id):
		return Loc.t("needs %s") % gate_text(id, node_id)
	if points_free(id) < cost(node_id):
		return Loc.n("needs %d Skill Point", "needs %d Skill Points", cost(node_id)) % cost(node_id)
	return ""


static func learn(id: String, node_id: String) -> bool:
	if blocker(id, node_id) != "":
		return false
	learned(id).append(node_id)
	return true


## Gilt to unlearn this hero's whole tree.
static func respec_cost(id: String) -> int:
	var r: Dictionary = data().get("respec", {})
	return int(r.get("base", 30)) + int(r.get("per_point", 10)) * points_spent(id)


static func respec_blocker(id: String, on_mission := false) -> String:
	if learned(id).is_empty():
		return Loc.t("nothing learned yet")
	if on_mission:
		return Loc.t("only in Hollowmark or at the Command Table")
	if int(Empire.res.get("gilt", 0)) < respec_cost(id):
		return Loc.t("needs %d Gilt") % respec_cost(id)
	return ""


static func respec(id: String) -> bool:
	if respec_blocker(id) != "":
		return false
	Empire.res["gilt"] = int(Empire.res["gilt"]) - respec_cost(id)
	learned(id).clear()
	return true


# ---------------------------------------------------------------- effects

static func _effects(id: String) -> Array:
	var out := []
	for k in learned(id):
		var n := node(k)
		if not n.is_empty():
			out.append(n.get("effects", {}))
	return out


## Stats the tree adds, like gear ({stat: amount}); Progress.bonus adds them in.
static func stats(id: String) -> Dictionary:
	var out := {}
	for e in _effects(id):
		var st: Dictionary = e.get("stats", {})
		for k in st:
			out[k] = float(out.get(k, 0.0)) + float(st[k])
	return out


## Passives from the tree: numbers add up, text values (kill_reset) are kept as they are.
static func perks(id: String) -> Dictionary:
	var out := {}
	for e in _effects(id):
		var p: Dictionary = e.get("perks", {})
		for k in p:
			if typeof(p[k]) == TYPE_STRING:
				out[k] = p[k]
			else:
				out[k] = float(out.get(k, 0.0)) + float(p[k])
	return out


## Who the ally AI goes for ("" = the preset's own choice). The last learned node that sets one wins.
static func focus(id: String) -> String:
	var f := ""
	for e in _effects(id):
		var ai: Dictionary = e.get("ai", {})
		if ai.has("focus"):
			f = str(ai["focus"])
	return f


## The ability with this hero's tree nodes applied on top of its Ink tier (Abilities.for_ids calls it).
## Per node: add (numbers added, a missing key counts as 0), mult (numbers multiplied), set (values
## replaced, including the ally AI rule "ai"), set_missing (only where the ability has no value yet).
## "tree" lists the names of the nodes that changed it, for menus.
static func mod_ability(id: String, a: Dictionary) -> Dictionary:
	var aid := str(a.get("id", ""))
	var names := []
	for k in learned(id):
		var n := node(k)
		var m: Dictionary = n.get("effects", {}).get("abilities", {}).get(aid, {})
		if m.is_empty():
			continue
		names.append(str(n.get("name", k)))
		var add: Dictionary = m.get("add", {})
		for key in add:
			a[key] = float(a.get(key, 0.0)) + float(add[key])
		var mult: Dictionary = m.get("mult", {})
		for key in mult:
			if a.has(key):
				a[key] = float(a[key]) * float(mult[key])
		var set_: Dictionary = m.get("set", {})
		for key in set_:
			a[key] = set_[key].duplicate(true) if typeof(set_[key]) == TYPE_DICTIONARY else set_[key]
		var miss: Dictionary = m.get("set_missing", {})
		for key in miss:
			if not a.has(key):
				a[key] = miss[key]
	if names.is_empty():
		return a
	a["cooldown"] = maxf(snappedf(float(a.get("cooldown", 1.0)), 0.1), 1.0)
	a["cost"] = maxi(int(round(float(a.get("cost", 0)))), 0)
	if a.has("count"):
		a["count"] = int(round(float(a["count"])))
	a["tree"] = names
	return a


## Puts the tree's passives on a hero in the field (Progress.apply_to calls it; safe to call again after
## learning a node mid-mission: everything is worked out from the hero's base data, never stacked).
static func apply_perks(h: Hero) -> void:
	var p := perks(h.hero_id)
	h.perks = p
	h.ai_focus = focus(h.hero_id)
	var hd := PartyPicker.hero_data(h.hero_id)
	h.ink_regen = Abilities.REGEN + float(p.get("ink_regen", 0.0))
	h.poise = float(hd.get("poise", 1.0)) * (1.0 - clampf(float(p.get("poise_cut", 0.0)), 0.0, 0.9))
	var heal: Dictionary = hd.get("heal", {})
	if not heal.is_empty():
		h.heal_every = float(heal.get("every", 6.0)) / (1.0 + float(p.get("heal_rate", 0.0)))
	if not h.last_stand_set:  # once a mission: a mid-mission refresh never gives it back
		h.last_stand_left = int(p.get("last_stand", 0))
		h.last_stand_set = h.last_stand_left > 0


## After a node is learned mid-mission: the hero standing in the field gets it at once.
## before = Progress.bonus(id) from before learning.
static func refresh_live(h: Hero, before: Dictionary) -> void:
	Progress.apply_delta(h, before, Progress.bonus(h.hero_id))
	h.refresh_abilities()
	apply_perks(h)
	if h.last_stand_left <= 0 and int(h.perks.get("last_stand", 0)) > 0 and not h.last_stand_spent:
		h.last_stand_left = int(h.perks["last_stand"])


# ---------------------------------------------------------------- saves

## Cleans a saved hero's tree (from Progress.from_save): unknown or other heroes' nodes are dropped, and so
## is anything the saved level can no longer pay for or reach (a cut or re-costed node).
static func clean_into(id: String, src: Dictionary, out: Dictionary) -> void:
	var t = src.get("tree")
	var clean := []
	if typeof(t) == TYPE_ARRAY:
		var budget := maxi(int(out.get("level", 1)) - 1, 0) * int(data().get("points", {}).get("per_level", 1))
		var caps := 0
		for k in t:
			var nid := str(k)
			var inf := info(nid)
			if inf.is_empty() or inf["hero"] != id or nid in clean:
				continue
			var need := requires(nid)
			if need != "" and not need in clean:
				continue
			if is_capstone(nid):
				if caps > 0:
					continue
				caps += 1
			if cost(nid) > budget:
				continue
			budget -= cost(nid)
			clean.append(nid)
	out["tree"] = clean
