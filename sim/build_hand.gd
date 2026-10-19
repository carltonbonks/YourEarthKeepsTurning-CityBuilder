class_name BuildHand
extends RefCounted
## Building cards (`run.hand`): each round's build phase deals a hand of buildings to order from,
## weighted toward what the town needs, plus a card for ageing up whenever it can be raised.
## Basic buildings (homes and food) are always on offer and never dealt, like Against the Storm's basics.
## Ordering a card pays the building's cost (RunState.build) and uses the card up.
## Numbers are in data/balance.json (build_hand_size, build_need_weight, build_new_weight, build_redraw_cost).

var run: RunState
## This round's cards, each {"building": type, "need": why the town wants it ("" if nothing in particular)}.
var cards: Array[Dictionary] = []
## The ageing-up card ({} when no age-up building can be ordered).
var milestone := {}
## Redraws used this round.
var redraws := 0


func _init(run_state: RunState) -> void:
	run = run_state


## Deals a fresh hand for the round (called as the build phase begins).
func deal() -> void:
	redraws = 0
	_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10))


## Deals new cards in place of the unused ones, once a round, for shells.
func can_redraw() -> bool:
	return run.phase == RunState.Phase.BUILD and redraws == 0 and int(run.stock["shells"]) >= redraw_cost()


func redraw() -> bool:
	if not can_redraw():
		return false
	run.stock["shells"] = int(run.stock["shells"]) - redraw_cost()
	redraws += 1
	var before := cards.map(func(c: Dictionary) -> String: return c["building"])
	_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10 + redraws), before)
	run.record.note_action({"kind": "redraw", "cost": redraw_cost()})
	run.record.note_list("build_hands", {"cards": labels()})
	return true


func redraw_cost() -> int:
	return run.content.int_num("build_redraw_cost")


## Basic buildings (homes and food, `basic` in data/buildings.json) that can go up now: always on offer,
## as many as the town can pay for, never dealt as cards.
func basics() -> Array[String]:
	var out: Array[String] = []
	var types := run.content.buildings.keys()
	types.sort()
	for type: String in types:
		if run.content.buildings[type].get("basic", false) and eligible(type):
			out.append(type)
	return out


## True if this building type is on a card in hand (the ageing-up card and basic buildings count).
func offers(type: String) -> bool:
	return run.content.buildings[type].get("basic", false) or milestone.get("building", "") == type or cards.any(func(c: Dictionary) -> bool: return c["building"] == type)


## Orders the building on a card in hand and uses the card up.
func can_order(type: String) -> bool:
	return offers(type) and run.can_build(type)


func order(type: String) -> bool:
	if not can_order(type) or not run.build(type):
		return false
	if run.content.buildings[type].get("basic", false):
		return true
	if milestone.get("building", "") == type:
		milestone = {}
	else:
		for i in cards.size():
			if cards[i]["building"] == type:
				cards.remove_at(i)
				break
	return true


## The building types listed in hand, for the run record.
func labels() -> Array:
	var out := cards.map(func(c: Dictionary) -> String: return c["building"])
	if not milestone.is_empty():
		out.append(milestone["building"])
	return out


## Buildings that could go on a card now: in reach of the age, requirements met, below their max,
## enough people, and a free plot. Cost is not checked: a card you can't pay for yet still shows.
func eligible(type: String) -> bool:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	var needs: String = def.get("requires", "")
	return content.age_reached(run.age, def.get("age", "")) \
		and run.world.count_buildings(type, false) < run.building_max(type) \
		and (needs == "" or run.world.count_buildings(needs, false) > 0) \
		and run.population() >= int(def.get("min_people", 0)) \
		and not (def.has("ages_up") and content.age_reached(run.age, def["ages_up"])) \
		and run.world.town.choose_plot(type) >= 0


## Why the town wants a building now: "housing", "food", "beds", "regrow" (the nodes it tends are picked over),
## "fuel" (it makes fuel and there is less than two nights' worth), "supply" (a stall has nobody making
## its goods), "stall" (a workshop has nowhere to sell), "age" (new in the town's current age),
## or "" for nothing in particular.
func need(type: String) -> String:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	if def.has("housing") and not def.has("lodging") and run.housing() - run.population() <= 2:
		return "housing"
	if (def.get("daily", {}).has("food") or type == "drying_rack") \
			and float(run.stock["food"]) < run.food_needed_today() * 3.0:
		return "food"
	if def.has("lodging") and run.world.hero_ai.count_lodgings() > 0 and free_beds() <= 0:
		return "beds"
	if def.has("tends") and run.world.nodes_fullness(def["tends"]["tag"]) < content.num("build_tend_below"):
		return "regrow"
	if def.has("workshop") and _makes_fuel(type) and float(run.stock["fuel"]) < run.fuel_needed_tonight() * 2.0:
		return "fuel"
	if def.has("workshop"):
		for id in content.recipes_for(type):
			var kind: String = content.market["recipes"][id].get("stall", "")
			if kind == "":
				continue
			if _has_stall(kind) and not _supplied(kind):
				return "supply"
			if not _has_stall(kind) and run.world.count_buildings(type, false) > 0:
				return "stall"
	if run.world.buildings.any(func(b: Dictionary) -> bool: return content.buildings[b["type"]].has("workshop")) \
			and not run.world.buildings.any(func(b: Dictionary) -> bool: return content.buildings[b["type"]].has("stall")) \
			and content.buildings.values().any(func(d: Dictionary) -> bool: return d.has("stall") and d.get("requires", "") == type):
		return "stall"
	if def.has("stall") and not _has_stall(def["stall"]["sells"]) and _supplied(def["stall"]["sells"]):
		return "stall"
	var own_age: String = def.get("age", "")
	if own_age != "" and own_age == run.age and run.world.count_buildings(type, false) == 0:
		return "age"
	return ""


func _makes_fuel(type: String) -> bool:
	return run.content.recipes_for(type).any(func(id: String) -> bool:
		return run.content.market["recipes"][id].get("makes", {}).has("fuel"))


## How many cards a hand holds: build_hand_size, plus build_hand_per_age for every age past the first.
func size() -> int:
	return run.content.int_num("build_hand_size") + run.content.int_num("build_hand_per_age") * run.content.ages["order"].find(run.age)


func _fill(rng: SeededRng, avoid: Array = []) -> void:
	var content := run.content
	cards = []
	milestone = {}
	var weights := {}
	var types := content.buildings.keys()
	types.sort()
	for type: String in types:
		if not eligible(type) or content.buildings[type].get("basic", false):
			continue
		if content.buildings[type].has("ages_up"):
			milestone = {"building": type, "need": ""}
			continue
		var weight := 1.0
		if need(type) != "":
			weight *= content.num("build_need_weight")
		if run.world.count_buildings(type, false) == 0:
			weight *= content.num("build_new_weight")
		# A redraw leans away from what was just in hand, so it feels like a fresh deal.
		if avoid.has(type):
			weight *= 0.25
		weights[type] = weight
	while cards.size() < size() and not weights.is_empty():
		var type := rng.weighted(weights)
		weights.erase(type)
		cards.append({"building": type, "need": need(type)})


func free_beds() -> int:
	var beds := 0
	for b in run.world.buildings:
		var def: Dictionary = run.content.buildings[b["type"]]
		if def.has("lodging"):
			beds += int(def["lodging"]["beds"])
	return beds - run.living_heroes().size()


func _has_stall(kind: String) -> bool:
	for type: String in run.content.buildings:
		if run.content.buildings[type].get("stall", {}).get("sells", "") == kind and run.world.count_buildings(type, false) > 0:
			return true
	return false


func _supplied(kind: String) -> bool:
	for id: String in run.content.market["recipes"]:
		var r: Dictionary = run.content.market["recipes"][id]
		if r.get("stall", "") == kind and run.world.count_buildings(r["workshop"], false) > 0:
			return true
	return false
