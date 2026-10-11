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


func _init(world: World) -> void:
	w = world


## The finished stall that sells a kind of good, or -1.
func stall_index(kind: String) -> int:
	for i in w.buildings.size():
		var b := w.buildings[i]
		if float(b["work_left"]) <= 0.0 and w.content.buildings[b["type"]].get("stall", {}).get("sells", "") == kind:
			return i
	return -1


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
			if int(w.run.stock[good]) >= int(r.get("keep", 99)):
				continue
			score = float(w.run.stock[good]) / float(r.get("keep", 99)) * float(w.content.market["stall_capacity"])
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
		if crafter.master_of == b["type"]:
			master = w.run.craft_trait(crafter)
	if r.has("makes"):
		for good: String in r["makes"]:
			w.run.stock[good] = int(w.run.stock[good]) + int(r["makes"][good])
		b["craft"] = ""
		b["made"] = int(b["made"]) + 1
		w.run.note_crafted(id)
		return
	var good := {"recipe": id, "tier": int(b["craft_tier"]) + int(master.get("extra_tier", 0))}
	if r.has("item"):
		var affixes := []
		var chance := float(w.content.market["affix_chance"]) if master.is_empty() else float(master.get("affix_chance", 0.0))
		if w.rng.randf() < chance:
			var ids: Array = w.content.items["affixes"].keys().filter(func(a: String) -> bool: return a != "cursed")
			ids.sort()
			affixes.append(w.rng.pick(ids))
		good["item"] = Loot.make(r["item"], int(good["tier"]), affixes)
	b["craft"] = ""
	b["made"] = int(b["made"]) + 1
	w.run.note_crafted(id)
	var s := stall_index(r["stall"])
	if s >= 0:
		w.buildings[s]["goods"].append(good)
	if good.has("item"):
		w.run.tell("The %s finishes a %s for the %s." % [w.content.buildings[b["type"]]["name"].to_lower(),
			Loot.describe(w.content, good["item"]), w.content.buildings[w.buildings[s]["type"]]["name"].to_lower() if s >= 0 else "market"])


## Rebuilds the posted prizes from the finished buildings; World.step() calls this every tick.
func refresh_prizes() -> void:
	_prizes = _posted_prizes()


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
		if w.content.enemy_has_tag(type_id, tag):
			total += int(_prizes[tag])
	return total


## The settlement gets hides and bone from carcasses, plus extra from buildings that skin that kind of creature.
func carcass(victim: Unit) -> void:
	var got: Dictionary = w.content.enemies[victim.type_id].get("yields", {}).duplicate()
	for b in w.buildings:
		var prize: Dictionary = w.content.buildings[b["type"]].get("prize", {})
		if prize.is_empty() or float(b["work_left"]) > 0.0 or not w.content.enemy_has_tag(victim.type_id, prize["tag"]):
			continue
		for res: String in prize.get("yields", {}):
			got[res] = int(got.get(res, 0)) + int(prize["yields"][res])
	for res: String in got:
		w.run.stock[res] = int(w.run.stock[res]) + int(got[res])
		w.run.note_economy("yields", int(got[res]), res)


func pay_prizes(hero: Unit, victim: Unit) -> void:
	var paid := mini(prize_for(victim.type_id), int(w.run.stock["shells"]))
	if paid <= 0:
		return
	w.run.stock["shells"] = int(w.run.stock["shells"]) - paid
	hero.gold += paid
	hero.mood_events["prize"] = int(hero.mood_events.get("prize", 0)) + 1
	w.run.note_economy("prizes", paid)
