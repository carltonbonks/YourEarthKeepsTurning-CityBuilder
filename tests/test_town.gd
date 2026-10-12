extends TestCase
## The ring town, pathfinding, trails and roads (Town, Pathing).


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func _rich(run: RunState) -> void:
	for r: String in ["wood", "stone", "shells"]:
		run.stock[r] = 999


## Starts the first day with no dawn newcomer and no monsters around.
func _start_day(run: RunState) -> void:
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	run.world.dens.clear()


func _advance(run: RunState, seconds: float) -> void:
	for i in int(seconds / run.world.dt):
		run.step()


func test_plots_never_overlap() -> void:
	var town := _run().world.town
	var owner := {}
	for k in town.plots.size():
		check(not town.plots[k]["cells"].is_empty(), "plot %d covers some ground" % k)
		for i in town.plots[k]["cells"]:
			check(not owner.has(i), "square %d is in two plots" % i)
			owner[i] = k


func test_buildings_never_wall_off_the_hearth() -> void:
	var run := _run()
	_rich(run)
	var built := 0
	while run.build("hut"):
		built += 1
	var w := run.world
	check(built > 30, "the opening rings hold many huts (%d)" % built)
	check(w.pathing.connected(Vector2.ZERO, Vector2(w.town.outer_edge() + 30.0, 0.0)), "the hearth can still be reached from the wilds")
	for b in w.buildings:
		check(w.pathing.connected(Vector2.ZERO, b["pos"]), "every building can be walked to")


func test_buildings_go_where_they_like() -> void:
	var run := _run()
	_rich(run)
	run.build("hut")
	run.build("hunting_lodge")
	var town := run.world.town
	check_eq(int(town.plots[run.world.buildings[0]["plot"]]["ring"]), 0, "a hut goes in the inner ring")
	check_eq(int(town.plots[run.world.buildings[1]["plot"]]["ring"]), 2, "the hunting lodge goes in the outer ring")


func test_outer_ring_opens_with_the_bronze_age() -> void:
	var run := _run()
	var town := run.world.town
	var bronze_ring := town.plots.filter(func(p: Dictionary) -> bool: return p["age"] == "bronze")
	check(not bronze_ring.is_empty(), "there is a bronze-age ring")
	check(not town.ring_open(bronze_ring[0]), "it is closed in the stone age")
	run.age = "bronze"
	check(town.ring_open(bronze_ring[0]), "it opens in the bronze age")


func test_buildings_keep_off_paved_ground() -> void:
	var run := _run()
	_rich(run)
	var town := run.world.town
	# Pave every inner-ring plot: a hut, which likes the inner ring, goes further out instead.
	for k in town.plots.size():
		if int(town.plots[k]["ring"]) == 0:
			for i in town.plots[k]["cells"]:
				run.world.pathing.set_ground(i, Pathing.FIRST_ROAD)
	check(run.build("hut"), "a hut can be ordered")
	check(int(town.plots[run.world.buildings[0]["plot"]]["ring"]) > 0, "it keeps off the paved inner ring")


func test_building_over_paving_lifts_the_stones() -> void:
	var run := _run()
	_rich(run)
	var town := run.world.town
	for k in town.plots.size():
		for i in town.plots[k]["cells"]:
			if not run.world.pathing.is_solid(i):
				run.world.pathing.set_ground(i, Pathing.FIRST_ROAD)
	var stone := int(run.stock["stone"])
	var cost := int(run.content.buildings["hut"]["cost"].get("stone", 0))
	check(run.build("hut"), "with nothing else free, the hut goes on paving")
	var plot: Dictionary = town.plots[run.world.buildings[0]["plot"]]
	check(int(run.stock["stone"]) > stone - cost, "the lifted stone goes back into stock (%d -> %d)" % [stone, run.stock["stone"]])
	for i in plot["cells"]:
		check(not run.world.pathing.is_road(i), "no road under the hut")


func test_walkers_go_round_buildings() -> void:
	var run := _run()
	_rich(run)
	for n in 10:
		run.build("hut")
	var w := run.world
	var u := Unit.new()
	u.team = Unit.Team.ENEMY
	u.speed = 50.0
	var b: Dictionary = w.buildings[0]
	u.pos = (b["pos"] as Vector2).normalized() * 300.0
	var arrived := false
	for t in 600:
		if w.walk_toward(u, Vector2.ZERO, 30.0):
			arrived = true
			break
		check(not w.pathing.is_solid(w.pathing.index_of(u.pos)), "the walker never walks through a building")
	check(arrived, "the walker reaches the hearth")


func test_roads_are_faster() -> void:
	var run := _run()
	var w := run.world
	var times := []
	for paved in [false, true]:
		if paved:
			for x in range(-210, 211, 4):
				for y in [292, 300, 308]:
					w.pathing.set_ground(w.pathing.index_of(Vector2(x, y)), Pathing.FIRST_ROAD)
		var u := Unit.new()
		u.team = Unit.Team.FOLK
		u.speed = 50.0
		u.pos = Vector2(-190, 300)
		var ticks := 0
		while not w.walk_toward(u, Vector2(190, 300), 2.0) and ticks < 2000:
			ticks += 1
		times.append(ticks)
	check(times[1] < times[0] * 0.8, "the paved road is quicker (%d vs %d ticks)" % [times[1], times[0]])


## Wears a worn path from the hearth out to (0, 240), as if many feet had walked it.
func _wear_path(run: RunState) -> void:
	var p := run.world.pathing
	for y in range(30, 240, 4):
		p.tread(Vector2(0, y), 100.0)
	p.wear_trails()
	p.wear_trails()


func test_stone_layers_pave_busy_paths() -> void:
	for with_yard in [false, true]:
		var run := _run()
		_rich(run)
		_wear_path(run)
		check(run.world.pathing.busy_paths.size() > 0, "the busy path is listed")
		run.world.folk_ai.add_folk("craftsperson")
		if with_yard:
			check(run.build("stone_yard"), "the yard can be ordered")
			run.world.buildings[-1]["work_left"] = 0.0
		var stone := int(run.stock["stone"])
		_start_day(run)
		_advance(run, 25.0)
		var paved := int(run.world.town.paved_counts().get("stone_path", 0))
		if with_yard:
			check(paved > 0, "craftspeople pave the worn path (%d squares)" % paved)
			check(int(run.stock["stone"]) < stone, "paving uses stone")
		else:
			check_eq(paved, 0, "nothing is paved without a stone-layers' yard")


func test_feet_wear_trails() -> void:
	var p := _run().world.pathing
	var i := p.index_of(Vector2(300, 300))
	p.tread(Vector2(300, 300), 5.0)
	p.wear_trails()
	check_eq(p.ground[i], Pathing.TRAIL, "a walked square becomes a trail")
	p.wear_trails()
	check_eq(p.ground[i], Pathing.TRAIL, "light use doesn't wear it deeper")
	p.tread(Vector2(300, 300), 30.0)
	p.wear_trails()
	check_eq(p.ground[i], Pathing.PATH, "a busy trail becomes a worn path")
	check(p.busy_paths.has(i), "and is listed for paving")
	check(p.speeds[Pathing.PATH] > p.speeds[Pathing.TRAIL], "a worn path is quicker than a trail")
	for n in 8:
		p.wear_trails()
	check_eq(p.ground[i], Pathing.PLAIN, "an unused path fades back to plain ground")


func test_layout_is_seeded() -> void:
	var a := _run(77).world.town
	var b := _run(77).world.town
	var c := _run(78).world.town
	var obstacles := func(t: Town) -> Array:
		return range(t.plots.size()).filter(func(k: int) -> bool: return t.plots[k]["obstacle"] != "")
	check_eq(obstacles.call(a), obstacles.call(b), "same seed, same obstacles")
	check_eq(a.thickets, b.thickets, "same seed, same thickets")
	check(a.thickets != c.thickets, "another seed, other thickets")


func test_record_has_paths_and_town() -> void:
	var run := _run()
	var bot := AutoPlayer.new()
	while run.round_number < 2 and not run.is_over():
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(bot.pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic("")
	var record := run.to_record()
	check(int(record["format"]) >= 10, "record format 10 or later")
	var town: Dictionary = record["rounds"][0]["town"]
	for key in ["paved", "trails", "paths", "plots_by_ring", "gates"]:
		check(town.has(key), "the round's town has %s" % key)
	check(int(town["trails"]) > 0, "feet wore some trails")
	check(record.has("plots"), "the record lists where buildings stand")
