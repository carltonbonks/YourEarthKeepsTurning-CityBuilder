class_name BuildHand
extends RefCounted
## Blueprints (`run.hand`), like Against the Storm's: each round's build phase offers a few buildings to draft,
## weighted toward what the town needs, and a drafted building stays on offer for the rest of the run.
## Basic buildings (homes and food) are always on offer and never drafted. Ageing up is its own card whenever
## it can be raised, and the building the next age-up needs is always among the offers until it is drafted.
## Ordering pays the building's cost (RunState.build) as often as its max allows.
## A row (data/combos.json) can be drafted too: it orders its two buildings side by side for less, and only
## rows make a combo. A row is a payoff you earn (Yusuf, 2026-10-22): it is offered only once the town has one of
## its buildings (a basic, a blueprint or one standing), and drafting it adds just the other one and the bonus. Once the open rings are nearly full (clear_when_full in
## data/town.json), the draft also offers to clear the next ring of plots for its clear_cost, in place of a building (`ring_offer`, `clear_ring`).
## Numbers are in data/balance.json (blueprint_*, build_need_weight, build_new_weight, build_redraw_cost).

var run: RunState
## This round's draft offers, each {"building": type, "need": why the town wants it ("" if nothing in particular)}.
var cards: Array[Dictionary] = []
## The ageing-up card ({} when no age-up building can be ordered).
var milestone := {}
## Row offers in the draft, each {"row": id from data/combos.json, "need": why the town wants either building}.
var rows: Array[Dictionary] = []
## Buildings drafted this run, in the order they were taken: on offer for good.
var blueprints: Array[String] = []
## Rows drafted this run.
var row_blueprints: Array[String] = []
## Drafts left to take (unspent picks carry over to the next round).
var picks := 0
## Rerolls of the offers used this round.
var redraws := 0
var _dealt_round := -1
var _dealt_age := ""


func _init(run_state: RunState) -> void:
	run = run_state


## Deals fresh offers for the round (called as the build phase begins). The first round brings
## blueprint_first_picks drafts and every later one blueprint_picks; reaching a new age adds blueprint_age_picks.
func deal() -> void:
	redraws = 0
	if _dealt_round != run.round_number:
		var content := run.content
		picks += content.int_num("blueprint_first_picks") if _dealt_round < 0 else content.int_num("blueprint_picks")
		if _dealt_age != "" and _dealt_age != run.age:
			picks += content.int_num("blueprint_age_picks")
		_dealt_round = run.round_number
		_dealt_age = run.age
	_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10))


## Rerolls the offers, once a round while a draft is left, for shells.
func can_redraw() -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and redraws == 0 and int(run.stock["shells"]) >= redraw_cost() \
		and not run.has_effect("no_redraw")


func redraw() -> bool:
	if not can_redraw():
		return false
	run.stock["shells"] = int(run.stock["shells"]) - redraw_cost()
	redraws += 1
	var before := labels()
	_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10 + redraws), before)
	run.record.note_action({"kind": "redraw", "cost": redraw_cost()})
	run.record.note_list("build_hands", {"cards": labels()})
	return true


func redraw_cost() -> int:
	return run.content.int_num("build_redraw_cost")


## Basic buildings (homes and food, `basic` in data/buildings.json) that can go up now: always on offer,
## as many as the town can pay for, never drafted.
func basics() -> Array[String]:
	var out: Array[String] = []
	var types := run.content.buildings.keys()
	types.sort()
	for type: String in types:
		if run.content.buildings[type].get("basic", false) and eligible(type):
			out.append(type)
	return out


## True if this building type can be ordered from the hand: a basic, a blueprint or the ageing-up card.
func offers(type: String) -> bool:
	return run.content.buildings[type].get("basic", false) or milestone.get("building", "") == type or blueprints.has(type)


## True if this row has been drafted.
func offers_row(id: String) -> bool:
	return row_blueprints.has(id)


func can_order_row(id: String) -> bool:
	return offers_row(id) and run.can_build_row(id)


## Orders both buildings of a drafted row, side by side.
func order_row(id: String) -> bool:
	return can_order_row(id) and run.build_row(id)


## The drafted row that has this building in it ("" if none).
func row_with(type: String) -> String:
	for id in row_blueprints:
		var row: Dictionary = run.content.combos[id]
		if row["building"] == type or row["partner"] == type:
			return id
	return ""


func can_order(type: String) -> bool:
	return offers(type) and run.can_build(type)


func order(type: String) -> bool:
	if not can_order(type) or not run.build(type):
		return false
	if milestone.get("building", "") == type:
		milestone = {}
	return true


## True if this building is among the offers and a draft is left.
func can_draft(type: String) -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and cards.any(func(c: Dictionary) -> bool: return c["building"] == type)


## Drafts an offered building for the rest of the run; fresh offers follow while drafts are left.
func draft(type: String) -> bool:
	if not can_draft(type):
		return false
	_take(type)
	run.record.note_action({"kind": "blueprint", "building": type})
	_after_draft()
	return true


func can_draft_row(id: String) -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and rows.any(func(c: Dictionary) -> bool: return c["row"] == id)


func can_clear_ring() -> bool:
	return ring_offer() and run.can_afford(run.ring_cost())


## Takes the draft's ring offer: pays to clear the next ring of plots, which opens for good.
func clear_ring() -> bool:
	if not can_clear_ring():
		return false
	var cost := run.ring_cost()
	for r: String in cost:
		run.stock[r] = int(run.stock[r]) - int(cost[r])
	run.open_ring()
	run.record.note_action({"kind": "clear_ring", "ring": run.rings_open})
	run.tell("Townsfolk clear the ground for a new ring of plots round the town.")
	_after_draft()
	return true


## True while the draft offers to clear the next ring: a draft is left, a ring is still closed and the open rings
## are nearly full. It is checked live, so it turns up as soon as building fills the town.
func ring_offer() -> bool:
	return run.phase == RunState.Phase.BUILD and picks > 0 and run.ring_closed() \
		and run.world.town.fullness() >= float(run.content.town["clear_when_full"])


## Drafts an offered row: the row for good, and both its buildings (unless basic) as blueprints.
func draft_row(id: String) -> bool:
	if not can_draft_row(id):
		return false
	row_blueprints.append(id)
	var row: Dictionary = run.content.combos[id]
	for type: String in [row["building"], row["partner"]]:
		if not run.content.buildings[type].get("basic", false) and not blueprints.has(type):
			_take(type)
	run.record.note_action({"kind": "blueprint", "row": id})
	_after_draft()
	return true


func _take(type: String) -> void:
	blueprints.append(type)
	run.record.note_list("blueprints", {"building": type})


func _after_draft() -> void:
	picks -= 1
	if picks > 0:
		_fill(SeededRng.stream(run.run_seed, "build_cards", run.round_number * 10 + 5 + blueprints.size()))
		run.record.note_list("build_hands", {"cards": labels()})
	else:
		cards = []
		rows = []


## Buildings that could be drafted now: not basic or ageing up, not drafted yet, in reach of the age, below their max,
## and whatever they require already drafted or standing.
func draftable(type: String) -> bool:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	var needs: String = def.get("requires", "")
	return not def.get("basic", false) and not def.has("ages_up") and not blueprints.has(type) \
		and content.age_reached(run.age, def.get("age", "")) \
		and run.world.count_buildings(type, false) < run.building_max(type) \
		and (needs == "" or blueprints.has(needs) or run.world.count_buildings(needs, false) > 0)


## The building the next age-up requires, if it is neither drafted nor standing ("" if none).
func ageing_need() -> String:
	var order: Array = run.content.ages["order"]
	var next := order.find(run.age) + 1
	if next >= order.size():
		return ""
	for type: String in run.content.buildings:
		var def: Dictionary = run.content.buildings[type]
		if def.get("ages_up", "") != order[next]:
			continue
		var needs: String = def.get("requires", "")
		if needs != "" and not blueprints.has(needs) and run.world.count_buildings(needs, false) == 0:
			return needs
	return ""


## The draft offers, for the run record.
func labels() -> Array:
	var out := cards.map(func(c: Dictionary) -> String: return c["building"])
	for c in rows:
		out.append("row:" + c["row"])
	if ring_offer():
		out.append("ring")
	return out


## Buildings that could go up now: in reach of the age, requirements met, below their max,
## enough people, and a free plot. Cost is not checked.
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
## its goods), "stall" (a workshop has nowhere to sell), "heroes" (no hero lodging drafted or standing),
## "ageing" (the next age-up needs it), "age" (new in the town's current age),
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
	if def.has("lodging") and not _any_lodging():
		return "heroes"
	if type == ageing_need():
		return "ageing"
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
	if def.has("runners") and _has_stall("provisions") and run.living_heroes().size() >= 2:
		return "runners"
	var own_age: String = def.get("age", "")
	if own_age != "" and own_age == run.age and run.world.count_buildings(type, false) == 0:
		return "age"
	return ""


func _makes_fuel(type: String) -> bool:
	return run.content.recipes_for(type).any(func(id: String) -> bool:
		return run.content.market["recipes"][id].get("makes", {}).has("fuel"))


## How many buildings each draft offers: blueprint_offers (rows count among them), plus relics' hand_bonus.
func size() -> int:
	return run.content.int_num("blueprint_offers") + int(run.mod("hand_bonus"))


func _fill(rng: SeededRng, avoid: Array = []) -> void:
	var content := run.content
	cards = []
	rows = []
	milestone = {}
	var types := content.buildings.keys()
	types.sort()
	for type: String in types:
		if content.buildings[type].has("ages_up") and eligible(type):
			milestone = {"building": type, "need": ""}
	if picks <= 0:
		return
	var weights := {}
	for type: String in types:
		if not draftable(type):
			continue
		# Rarer blueprints (data/rarity.json) come up less often, a little more as the run goes on.
		var weight := content.rarity_odds(content.rarity_of("building", type), run.round_number)
		if need(type) != "":
			weight *= content.num("build_need_weight")
		if run.world.count_buildings(type, false) == 0:
			weight *= content.num("build_new_weight")
		if run.tradition_favours(type):
			weight *= content.num("tradition_card_weight")
		# A reroll leans away from what was just offered, so it feels like a fresh deal.
		if avoid.has(type):
			weight *= 0.25
		weights[type] = weight
	var room := size()
	_fill_rows(rng, avoid)
	room -= rows.size()
	# The building the next age-up needs is always offered, so ageing up never waits on luck.
	var must := ageing_need()
	if must != "" and weights.has(must) and room > 0:
		weights.erase(must)
		cards.append({"building": must, "need": need(must)})
	while cards.size() < room and not weights.is_empty():
		var type := rng.weighted(weights)
		weights.erase(type)
		cards.append({"building": type, "need": need(type)})


## Offers up to row_cards rows not drafted yet whose buildings are in reach of the age, favouring rows the town needs.
func _fill_rows(rng: SeededRng, avoid: Array) -> void:
	var weights := {}
	var ids := run.content.combos.keys()
	ids.sort()
	for id: String in ids:
		if row_blueprints.has(id) or not _row_draftable(id):
			continue
		var weight := 1.0
		if row_need(id) != "":
			weight *= run.content.num("build_need_weight")
		if avoid.has("row:" + id):
			weight *= 0.25
		weights[id] = weight
	while rows.size() < run.content.int_num("row_cards") and not weights.is_empty():
		var id := rng.weighted(weights)
		weights.erase(id)
		rows.append({"row": id, "need": row_need(id)})


## A row can be drafted once the town has one of its buildings, both are in reach of the age and whatever they
## require is drafted or standing.
func _row_draftable(id: String) -> bool:
	var row: Dictionary = run.content.combos[id]
	if row_have(id) == "":
		return false
	for type: String in [row["building"], row["partner"]]:
		var def: Dictionary = run.content.buildings[type]
		var needs: String = def.get("requires", "")
		if not run.content.age_reached(run.age, def.get("age", "")) or (needs != "" and needs != row["building"] \
				and needs != row["partner"] and not blueprints.has(needs) and run.world.count_buildings(needs, false) == 0):
			return false
	return true


## True if the town has this building to build a row on: a basic, a blueprint or one standing.
func has_building(type: String) -> bool:
	return run.content.buildings[type].get("basic", false) or blueprints.has(type) or run.world.count_buildings(type, false) > 0


## The row's building the town already has ("" if neither): the row's own building first.
func row_have(id: String) -> String:
	var row: Dictionary = run.content.combos[id]
	for type: String in [row["building"], row["partner"]]:
		if has_building(type):
			return type
	return ""


## The buildings drafting this row would add as blueprints (the ones the town doesn't have yet).
func row_adds(id: String) -> Array[String]:
	var row: Dictionary = run.content.combos[id]
	var out: Array[String] = []
	for type: String in [row["building"], row["partner"]]:
		if not has_building(type):
			out.append(type)
	return out


## Rows that drafting this building would open up for later drafts (none the town can draft already).
func rows_opened_by(type: String) -> Array[String]:
	var out: Array[String] = []
	if has_building(type):
		return out
	var ids := run.content.combos.keys()
	ids.sort()
	for id: String in ids:
		var row: Dictionary = run.content.combos[id]
		if not row_blueprints.has(id) and row_have(id) == "" and (row["building"] == type or row["partner"] == type):
			out.append(id)
	return out


## Why the town wants a row: why it wants either of its buildings ("" if nothing in particular).
func row_need(id: String) -> String:
	var row: Dictionary = run.content.combos[id]
	var why := need(row["building"])
	return why if why != "" else need(row["partner"])


func _any_lodging() -> bool:
	for type: String in run.content.buildings:
		if run.content.buildings[type].has("lodging") and (blueprints.has(type) or run.world.count_buildings(type, false) > 0):
			return true
	return false


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
