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


func test_staked_road_keeps_its_ground_clear() -> void:
	var run := _run()
	_rich(run)
	check(run.stake_road([Vector2.ZERO, Vector2(260, 0)]), "a road can be staked")
	while run.build("hut"):
		pass
	var town := run.world.town
	for b in run.world.buildings:
		for i in town.plots[b["plot"]]["cells"]:
			check(town.staked[i] == 0, "no building stands on the staked road")
	check(run.unstake_road(), "the stakes can be pulled up")
	check_eq(town.staked_count(), 0, "no stakes left")


func test_road_bends_round_buildings() -> void:
	var run := _run()
	_rich(run)
	for n in 6:
		run.build("hut")
	var b: Dictionary = run.world.buildings[0]
	var far: Vector2 = (b["pos"] as Vector2).normalized() * 260.0
	var cells := run.world.town.route([Vector2.ZERO, far])
	check(cells.size() > 2, "a route is found")
	for i in cells:
		check(not run.world.pathing.is_solid(i), "the route never crosses a building")


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
			check(run.stake_road([Vector2(-200, 300), Vector2(200, 300)]), "staked a test road")
			for i in w.town.roads[-1]["cells"]:
				w.pathing.set_ground(i, Pathing.FIRST_ROAD)
		var u := Unit.new()
		u.team = Unit.Team.FOLK
		u.speed = 50.0
		u.pos = Vector2(-190, 300)
		var ticks := 0
		while not w.walk_toward(u, Vector2(190, 300), 2.0) and ticks < 2000:
			ticks += 1
		times.append(ticks)
	check(times[1] < times[0] * 0.8, "the paved road is quicker (%d vs %d ticks)" % [times[1], times[0]])


func test_stone_layers_pave_staked_roads() -> void:
	for with_yard in [false, true]:
		var run := _run()
		_rich(run)
		check(run.stake_road([Vector2.ZERO, Vector2(0, 240)]), "staked a road")
		run.world.folk_ai.add_folk("craftsperson")
		if with_yard:
			check(run.build("stone_yard"), "the yard can be ordered")
			run.world.buildings[-1]["work_left"] = 0.0
		var stone := int(run.stock["stone"])
		_start_day(run)
		_advance(run, 25.0)
		var paved := int(run.world.town.paved_counts().get("stone_path", 0))
		if with_yard:
			check(paved > 0, "craftspeople pave the staked road (%d squares)" % paved)
			check(int(run.stock["stone"]) < stone, "paving uses stone")
		else:
			check_eq(paved, 0, "nothing is paved without a stone-layers' yard")


func test_feet_wear_trails() -> void:
	var p := _run().world.pathing
	var i := p.index_of(Vector2(300, 300))
	p.tread(Vector2(300, 300), 10.0)
	p.wear_trails()
	check_eq(p.ground[i], Pathing.TRAIL, "a busy square becomes a trail")
	for n in 4:
		p.wear_trails()
	check_eq(p.ground[i], Pathing.PLAIN, "an unused trail fades")


func test_layout_is_seeded() -> void:
	var a := _run(77).world.town
	var b := _run(77).world.town
	var c := _run(78).world.town
	var obstacles := func(t: Town) -> Array:
		return range(t.plots.size()).filter(func(k: int) -> bool: return t.plots[k]["obstacle"] != "")
	check_eq(obstacles.call(a), obstacles.call(b), "same seed, same obstacles")
	check_eq(a.thickets, b.thickets, "same seed, same thickets")
	check(a.thickets != c.thickets, "another seed, other thickets")


func test_record_has_roads_and_town() -> void:
	var run := _run()
	run.stake_road([Vector2.ZERO, Vector2(250, 0)])
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
	check(int(record["format"]) >= 8, "record format 8 or later")
	var first: Dictionary = record["rounds"][0]
	check(first["actions"].any(func(a: Dictionary) -> bool: return a["kind"] == "road"), "the staked road is recorded")
	check(first.has("town") and int(first["town"]["staked"]) > 0, "the round records staked squares")
	check(record.has("plots"), "the record lists where buildings stand")
