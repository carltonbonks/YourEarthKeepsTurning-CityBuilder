extends TestCase
## Upkeep buildings: the forester's hut makes nearby wild plants regrow faster, the charcoal pit turns wood into fuel when fuel runs low.


func _run() -> RunState:
	return RunState.new(Content.load_default(), 4821)


## Orders a building and finishes it on the spot.
func _raise(run: RunState, type: String) -> int:
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	check(run.build(type), "can order a %s" % type)
	var i := run.world.buildings.size() - 1
	run.world.buildings[i]["work_left"] = 0.0
	run.on_building_done(type)
	return i


func test_forester_regrows_nearby_plants_only() -> void:
	var run := _run()
	var w := run.world
	w.nodes.clear()
	var hut := _raise(run, "forester")
	var at: Vector2 = w.buildings[hut]["pos"]
	var out := at.normalized()
	w._add_node("grove", at + out * 100.0)
	w._add_node("rocks", at + out * 100.0)
	w._add_node("grove", -at.normalized() * 500.0)
	for node in w.nodes:
		node["amount"] = 0
	w._tend_nodes()
	check_eq(int(w.nodes[0]["amount"]), roundi(24 * 0.15), "the grove beside the hut regrows a share of its size")
	check_eq(int(w.nodes[1]["amount"]), 0, "rocks are not plants")
	check_eq(int(w.nodes[2]["amount"]), 0, "a grove across the map is out of reach")
	check_eq(w.node_regrowth(w.nodes[0]), run.content.int_num("node_regrow_per_day") + roundi(24 * 0.15), "the tooltip's regrowth counts the hut")
	check_eq(int(run.to_record()["rounds"][0]["tended"].get("wood", 0)), roundi(24 * 0.15), "tending is recorded")


func test_forester_stands_by_the_plants() -> void:
	var run := _run()
	var w := run.world
	w.nodes.clear()
	w._add_node("grove", Vector2(320, 0))
	w._add_node("brush", Vector2(300, 60))
	_raise(run, "forester")
	check(w.node_regrowth(w.nodes[0]) > run.content.int_num("node_regrow_per_day"), "the hut places itself within reach of the grove")


func test_charcoal_pit_only_works_when_fuel_is_low() -> void:
	var run := _run()
	var pit := _raise(run, "charcoal_pit")
	run.stock["wood"] = 30
	run.stock["fuel"] = run.fuel_needed_tonight() * 2
	check_eq(run.world.market.next_recipe(pit), "", "with two nights of fuel the pit leaves the wood alone")
	run.stock["fuel"] = 0
	check_eq(run.world.market.next_recipe(pit), "pit_charcoal", "with the fire low it makes charcoal")
	check(run.world.market.start_craft(pit), "the craft starts")
	check_eq(int(run.stock["wood"]), 27, "3 wood go in")
	run.world.market.finish_craft(pit)
	check_eq(int(run.stock["fuel"]), 6, "and come out as 6 fuel")


func test_cards_recommend_upkeep_when_needed() -> void:
	var run := _run()
	run.stock["fuel"] = 0
	check_eq(run.hand.need("charcoal_pit"), "fuel", "low fuel recommends the charcoal pit")
	run.stock["fuel"] = 99
	check(run.hand.need("charcoal_pit") != "fuel", "plenty of fuel does not")
	check(run.hand.need("forester") != "regrow", "fresh woods don't need tending")
	for node in run.world.nodes:
		if run.content.has_tag("node", node["type"], "plant"):
			node["amount"] = 0
	check_eq(run.hand.need("forester"), "regrow", "picked-over woods recommend the forester")
