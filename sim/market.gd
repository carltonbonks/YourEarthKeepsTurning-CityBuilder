class_name Market
extends RefCounted
## The town's economy in the World: workshops, stalls and building-posted prizes.
##
## Workshops turn raw goods into gear and provisions, one good at a time, while a
## craftsperson works the bench. Each good goes to the stall that sells its kind.
## Heroes passing through town buy what they like (see HeroAI) with their own
## shells, and the shells go to the settlement. The player only chooses buildings
## and prices. Buildings with a "prize" pay heroes for kills of tagged creatures.

var w: World
## Prize shells per creature tag posted by finished buildings (see "prize" in data/buildings.json), refreshed each tick.
var _prizes := {}
## Extra XP share per prize tag (a prize's "xp"), rebuilt with the prizes.
var _prize_xp := {}
## How far an outpost stands from its node, on the town's side.
const OUTPOST_OFFSET := 26.0


func _init(world: World) -> void:
	w = world


## The finished stall that sells a kind of good, or -1.
func stall_index(kind: String) -> int:
	for i in w.buildings.size():
		var b := w.buildings[i]
		if float(b["work_left"]) <= 0.0 and w.content.buildings[b["type"]].get("stall", {}).get("sells", "") == kind:
			return i
	return -1


## The cheapest provision on any finished stall that has `effect` ("energy" or "heal"): {stall, index, price}, or {}.
## Runners fetch from here (FolkAI._run_errand).
func provision_on_stall(effect: String) -> Dictionary:
	var best := {}
	for i in w.buildings.size():
		var b := w.buildings[i]
		if float(b["work_left"]) > 0.0 or not w.content.buildings[b["type"]].has("stall"):
			continue
		for j in b["goods"].size():
			var good: Dictionary = b["goods"][j]
			var r: Dictionary = w.content.market["recipes"][good["recipe"]]
			if not r.has("provision") or not w.content.market["provisions"][r["provision"]].has(effect):
				continue
			var price := w.run.price_of(good)
			if best.is_empty() or price < int(best["price"]):
				best = {"stall": i, "index": j, "price": price}
	return best


## Goods on a kind's stall plus those being made for it right now.
func _stall_load(kind: String) -> int:
	var s := stall_index(kind)
	var held: int = 0 if s < 0 else w.buildings[s]["goods"].size()
	for b in w.buildings:
		if b["craft"] != "" and w.content.market["recipes"][b["craft"]].get("stall", "") == kind:
			held += 1
	return held


## What a workshop should make next: something its stall has room for and the
## settlement can supply, favouring what the stall has least of. "" if nothing.
func next_recipe(index: int) -> String:
	var b := w.buildings[index]
	var options := w.content.recipes_for(b["type"])
	var best := ""
	var best_score := INF
	for k in options.size():
		var id: String = options[(k + int(b["made"])) % options.size()]
		var r: Dictionary = w.content.market["recipes"][id]
		if not w.run.can_afford(r["needs"]):
			continue
		var score := 0.0
		if r.has("makes"):
			# Smelting fills the settlement's stock, up to what it wants to keep.
			var good: String = r["makes"].keys()[0]
			var keep := float(r.get("keep", 99))
			if r.has("keep_nights"):
				keep = w.run.fuel_needed_tonight() * float(r["keep_nights"])
			if float(w.run.stock[good]) >= keep:
				continue
			score = float(w.run.stock[good]) / keep * float(w.content.market["stall_capacity"])
		else:
			var s := stall_index(r["stall"])
			if s < 0 or _stall_load(r["stall"]) >= int(w.content.market["stall_capacity"]):
				continue
			score = w.buildings[s]["goods"].filter(func(g: Dictionary) -> bool: return g["recipe"] == id).size()
		if score < best_score:
			best_score = score
			best = id
	return best


## A finished workshop with a free bench and something to make, the emptiest stall first. -1 if none.
func workshop_needing_hands(unit: Unit) -> int:
	var best := -1
	var best_load := INF
	for i in w.buildings.size():
		var b := w.buildings[i]
		var def: Dictionary = w.content.buildings[b["type"]]
		if not def.has("workshop") or float(b["work_left"]) > 0.0:
			continue
		var hands := w.folk.filter(func(u: Unit) -> bool: return u != unit and u.task == "craft" and u.task_index == i).size()
		if hands >= int(def["workshop"]["slots"]):
			continue
		var next: String = b["craft"] if b["craft"] != "" else next_recipe(i)
		if next == "":
			continue
		var r: Dictionary = w.content.market["recipes"][next]
		var held: float = _stall_load(r["stall"]) if r.has("stall") else 0.0
		# A master goes to their own bench first.
		if unit.master_of == b["type"]:
			held -= 100.0
		if held < best_load:
			best_load = held
			best = i
	return best


## Takes the goods for the next recipe from stock and starts work on it.
func start_craft(index: int) -> bool:
	var id := next_recipe(index)
	if id == "":
		return false
	var r: Dictionary = w.content.market["recipes"][id]
	for res: String in r["needs"]:
		w.run.stock[res] = int(w.run.stock[res]) - int(r["needs"][res])
	var b := w.buildings[index]
	b["craft"] = id
	b["craft_left"] = float(r["work"])
	b["craft_tier"] = w.run.craft_tier(id)
	return true


func finish_craft(index: int, crafter: Unit = null) -> void:
	var b := w.buildings[index]
	var id: String = b["craft"]
	var r: Dictionary = w.content.market["recipes"][id]
	var master := {}
	if crafter != null:
		crafter.made[b["type"]] = int(crafter.made.get(b["type"], 0)) + 1
		var key := w.run.record.impact_key(crafter)
		if not key.is_empty():
			w.run.record.note_impact(key[0], key[1], "made", 1.0)
		if crafter.master_of == b["type"]:
			master = w.run.craft_trait(crafter)
	if r.has("makes"):
		for good: String in r["makes"]:
			w.run.stock[good] = int(w.run.stock[good]) + int(r["makes"][good])
		b["craft"] = ""
		b["made"] = int(b["made"]) + 1
		w.run.record.note_crafted(id)
		return
	var good := {"recipe": id, "tier": int(b["craft_tier"]) + int(master.get("extra_tier", 0))}
	if r.has("item"):
		var affixes := []
		var chance := float(w.content.market["affix_chance"]) if master.is_empty() else float(master.get("affix_chance", 0.0))
		if w.rng.randf() < chance:
			var ids: Array = w.content.items["affixes"].keys().filter(func(a: String) -> bool:
				return a != "cursed" and not w.content.items["affixes"][a].get("earth_only", false))
			ids.sort()
			affixes.append(w.rng.pick(ids))
		good["item"] = Loot.make(r["item"], int(good["tier"]), affixes)
	b["craft"] = ""
	b["made"] = int(b["made"]) + 1
	w.run.record.note_crafted(id)
	var s := stall_index(r["stall"])
	if s >= 0:
		w.buildings[s]["goods"].append(good)
	if good.has("item"):
		w.run.tell("The %s finishes a %s for the %s." % [w.content.buildings[b["type"]]["name"].to_lower(),
			Loot.describe(w.content, good["item"]), w.content.buildings[w.buildings[s]["type"]]["name"].to_lower() if s >= 0 else "market"])


## Rebuilds the posted prizes from the finished buildings; World.step() calls this every tick.
func refresh_prizes() -> void:
	_prizes = _posted_prizes()
	_prize_xp = {}
	var effects := {}
	for b in w.buildings:
		var def: Dictionary = w.content.buildings[b["type"]]
		if float(b["work_left"]) > 0.0:
			continue
		var prize: Dictionary = def.get("prize", {})
		if prize.has("xp"):
			_prize_xp[prize["tag"]] = float(_prize_xp.get(prize["tag"], 0.0)) + float(prize["xp"])
		for key: String in def.get("effects", {}):
			effects[key] = float(effects.get(key, 0.0)) + float(def["effects"][key])
	w.building_effects = effects


## Extra XP share a hero earns for killing this creature type, from buildings whose prize carries "xp".
func prize_xp(type_id: String) -> float:
	var total := 0.0
	for tag: String in _prize_xp:
		if w.content.has_tag("enemy", type_id, tag):
			total += float(_prize_xp[tag])
	return total


func _posted_prizes() -> Dictionary:
	var out := {}
	for b in w.buildings:
		var prize: Dictionary = w.content.buildings[b["type"]].get("prize", {})
		if not prize.is_empty() and float(b["work_left"]) <= 0.0:
			out[prize["tag"]] = int(out.get(prize["tag"], 0)) + int(prize["shells"])
	return out


## Prize shells posted on a creature type.
func prize_for(type_id: String) -> int:
	var total := 0
	for tag: String in _prizes:
		if w.content.has_tag("enemy", type_id, tag):
			total += int(_prizes[tag])
	return total


## The settlement gets hides and bone from carcasses, plus extra from buildings that skin that kind of creature.
func carcass(victim: Unit) -> void:
	var got: Dictionary = w.content.enemies[victim.type_id].get("yields", {}).duplicate()
	for b in w.buildings:
		var prize: Dictionary = w.content.buildings[b["type"]].get("prize", {})
		if prize.is_empty() or float(b["work_left"]) > 0.0 or not w.content.unit_has_tag(victim, prize["tag"]):
			continue
		for res: String in prize.get("yields", {}):
			got[res] = int(got.get(res, 0)) + int(prize["yields"][res])
	for res: String in got:
		w.run.stock[res] = int(w.run.stock[res]) + int(got[res])
		w.run.record.note_economy("yields", int(got[res]), res)


func pay_prizes(hero: Unit, victim: Unit) -> void:
	var paid := mini(prize_for(victim.type_id), int(w.run.stock["shells"]))
	if paid <= 0:
		return
	w.run.stock["shells"] = int(w.run.stock["shells"]) - paid
	hero.gold += paid
	hero.mood_events["prize"] = int(hero.mood_events.get("prize", 0)) + 1
	w.run.record.note_economy("prizes", paid)


# --- Outposts (data/buildings.json "outpost") -----------------------------------------------------

## The node an outpost of this type would stand by: the farthest stocked node of its goods from the hearth
## that no other outpost works (-1 if none).
func outpost_node(type: String) -> int:
	var post: Dictionary = w.content.buildings[type]["outpost"]
	var taken := {}
	for b in w.buildings:
		if b.has("node"):
			taken[int(b["node"])] = true
	var best := -1
	for i in w.nodes.size():
		var node: Dictionary = w.nodes[i]
		if node["gives"] != post["gives"] or not w.node_active(node) or int(node["amount"]) <= 0 or taken.has(i):
			continue
		if best < 0 or node["pos"].length() > w.nodes[best]["pos"].length():
			best = i
	return best


## Places an outpost by its node, a little on the town's side of it. False if no node is free.
func add_outpost(type: String) -> bool:
	var node := outpost_node(type)
	if node < 0:
		return false
	w.buildings.append({"type": type, "plot": -1, "node": node, "pos": _outpost_pos(node),
		"work_left": float(w.content.buildings[type]["work"]), "cooldown_left": 0.0, "hp": 0.0,
		"goods": [], "craft": "", "craft_left": 0.0, "craft_tier": 1, "made": 0})
	return true


func _outpost_pos(node: int) -> Vector2:
	var at: Vector2 = w.nodes[node]["pos"]
	return at - at.normalized() * OUTPOST_OFFSET


## Each step: an outpost rides its node across the shifting earth, and a standing outpost with an enemy close
## by is wrecked: it brings nothing until craftspeople raise it again.
func outposts_tick() -> void:
	for i in w.buildings.size():
		var b: Dictionary = w.buildings[i]
		if not b.has("node"):
			continue
		b["pos"] = _outpost_pos(int(b["node"]))
		if float(b["work_left"]) > 0.0:
			continue
		var post: Dictionary = w.content.buildings[b["type"]]["outpost"]
		var foe := w.nearest_enemy(b["pos"], float(post["raid_radius"]))
		if foe != null:
			b["work_left"] = float(w.content.buildings[b["type"]]["work"]) * float(post["rebuild_share"])
			w.run.record.note_count("outposts_wrecked", 1, b["type"])
			w.run.tell("A %s wrecks the %s out by the %s." % [foe.display_name.to_lower(),
				w.content.buildings[b["type"]]["name"].to_lower(), w.content.world["nodes"][w.nodes[int(b["node"])]["type"]]["name"].to_lower()])


## At dawn each standing outpost brings in goods from its node. One whose node the earth took (or that was
## worked out) moves to the next free node of its kind and must be raised again.
func outposts_dawn() -> void:
	for i in w.buildings.size():
		var b: Dictionary = w.buildings[i]
		if not b.has("node"):
			continue
		var node: Dictionary = w.nodes[int(b["node"])]
		if not w.node_active(node) or int(node["amount"]) <= 0:
			var name: String = w.content.buildings[b["type"]]["name"]
			b["node"] = -1
			var next := outpost_node(b["type"])
			if next < 0:
				b["node"] = int(w.nodes.find(node))
				continue
			b["node"] = next
			b["pos"] = _outpost_pos(next)
			b["work_left"] = float(w.content.buildings[b["type"]]["work"])
			w.run.record.note_count("outposts_moved", 1, b["type"])
			w.run.tell("The %s's %s is gone; it must be raised again by another." % [name.to_lower(),
				w.content.world["nodes"][node["type"]]["name"].to_lower()])
			continue
		if float(b["work_left"]) > 0.0:
			continue
		var post: Dictionary = w.content.buildings[b["type"]]["outpost"]
		var got := mini(int(post["take"]), int(node["amount"]))
		node["amount"] = int(node["amount"]) - got
		var good: String = post["gives"]
		w.run.stock[good] = int(w.run.stock.get(good, 0)) + got
		w.run.record.note_count("outpost_goods", got, good)

