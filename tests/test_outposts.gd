extends TestCase
## Outposts (data/buildings.json "outpost"): buildings out in the wilds by a far node, with big yields,
## that enemies wreck and the shifting earth can take.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	run.stock["wood"] = 999
	run.stock["stone"] = 999
	run.world.enemies = [] as Array[Unit]
	return run


func _camp(run: RunState) -> Dictionary:
	check(run.build("woodcutters_camp"), "a woodcutters' camp can go up")
	var b: Dictionary = run.world.buildings[-1]
	b["work_left"] = 0.0
	return b


func test_an_outpost_stands_by_the_farthest_grove() -> void:
	var run := _run()
	var b := _camp(run)
	check_eq(int(b["plot"]), -1, "no plot in the town")
	var node: Dictionary = run.world.nodes[int(b["node"])]
	check_eq(node["gives"], "wood", "by a wood node")
	for other in run.world.nodes:
		if other["gives"] == "wood" and run.world.node_active(other) and int(other["amount"]) > 0:
			check(other["pos"].length() <= node["pos"].length() + 0.01, "the farthest one")
	check(b["pos"].distance_to(node["pos"]) < 40.0, "right beside it")


func test_an_outpost_brings_goods_each_dawn() -> void:
	var run := _run()
	var b := _camp(run)
	var node: Dictionary = run.world.nodes[int(b["node"])]
	var amount := int(node["amount"])
	var wood := int(run.stock["wood"])
	run.world.market.outposts_dawn()
	check_eq(int(run.stock["wood"]) - wood, mini(5, amount), "up to 5 wood")
	check_eq(int(node["amount"]), amount - mini(5, amount), "taken from its grove")


func test_an_enemy_close_by_wrecks_it() -> void:
	var run := _run()
	var b := _camp(run)
	var wolf := Unit.new()
	wolf.team = Unit.Team.ENEMY
	wolf.type_id = "wolf"
	wolf.display_name = "Wolf"
	wolf.spawned = true
	wolf.pos = b["pos"] + Vector2(10, 0)
	run.world.enemies.append(wolf)
	run.world._enemy_grid_ok = false
	run.world.market.outposts_tick()
	check(float(b["work_left"]) > 0.0, "wrecked: it must be raised again")
	var wood := int(run.stock["wood"])
	run.world.market.outposts_dawn()
	check_eq(int(run.stock["wood"]), wood, "a wrecked outpost brings nothing")


func test_an_outpost_whose_node_is_gone_moves() -> void:
	var run := _run()
	var b := _camp(run)
	var first := int(b["node"])
	run.world.nodes[first]["gone"] = true
	run.world.market.outposts_dawn()
	check(int(b["node"]) != first, "it moves to another grove")
	check(float(b["work_left"]) > 0.0, "and must be raised again")


func test_one_outpost_per_node() -> void:
	var run := _run()
	_camp(run)
	var taken: int = run.world.buildings[-1]["node"]
	check(run.world.market.outpost_node("woodcutters_camp") != taken, "another camp would use another grove")


func test_an_outpost_brings_more_for_each_turn_of_the_earth_it_rides() -> void:
	var run := _run()
	var b := _camp(run)
	var node: Dictionary = run.world.nodes[int(b["node"])]
	node["amount"] = 99
	node["max"] = 99
	check(run.world.earth.ring_at(b["pos"]) >= 0, "it stands out on the plates")
	var rd: Dictionary = run.content.plates["outpost_ride"]
	for n in int(rd["cap"]) + 2:
		run.world.earth.shift()
	check_eq(run.world.market.ride_bonus(b), int(rd["cap"]) * int(rd["bonus"]), "more for each turn it stood, up to a cap")
	var wood := int(run.stock["wood"])
	run.world.market.outposts_dawn()
	check_eq(int(run.stock["wood"]) - wood, 5 + run.world.market.ride_bonus(b), "brought in at dawn")
	run.world.market.outposts_tick()
	var wolf := Unit.new()
	wolf.team = Unit.Team.ENEMY
	wolf.type_id = "wolf"
	wolf.display_name = "Wolf"
	wolf.spawned = true
	wolf.pos = b["pos"] + Vector2(10, 0)
	run.world.enemies.append(wolf)
	run.world._enemy_grid_ok = false
	run.world.market.outposts_tick()
	check_eq(run.world.market.ride_bonus(b), 0, "a wrecked outpost starts again")
