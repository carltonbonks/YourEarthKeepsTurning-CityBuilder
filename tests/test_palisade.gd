extends TestCase
## Palisades and gates (Town, Pathing, World.walk_toward, FolkAI).


func _run(seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	for r: String in ["wood", "stone", "shells"]:
		run.stock[r] = 999
	return run


## Waypoints round a closed ring.
func _ring(radius: float, steps := 24) -> Array:
	var out := []
	for n in steps + 1:
		out.append(Vector2.from_angle(TAU * n / steps) * radius)
	return out


## Raises every staked palisade square at once.
func _raise_all(run: RunState) -> void:
	var town := run.world.town
	var i := town.next_wall([])
	while i >= 0:
		check(town.build_wall(i), "the town can pay for the palisade")
		i = town.next_wall([])


func _walker(team: Unit.Team, at: Vector2) -> Unit:
	var u := Unit.new()
	u.team = team
	u.speed = 50.0
	u.attack = 5.0
	u.cooldown = 1.0
	u.pos = at
	return u


func test_roads_across_a_palisade_make_gates() -> void:
	var run := _run()
	check(run.stake_wall(_ring(184.0)), "a closed ring can be staked")
	check(run.world.town.gates.is_empty(), "no gates yet")
	check(run.stake_road([Vector2.ZERO, Vector2(260, 0)]), "a road out")
	check(run.world.town.gates.size() > 0, "the road makes a gate")
	check(run.unstake_road(), "pull the road up")
	check(run.world.town.gates.is_empty(), "the gate goes with it")


## Walks a townsperson from one point to another; returns [arrived, used a gate, climbed, ticks].
func _walk_folk(run: RunState, from: Vector2, to: Vector2) -> Array:
	var w := run.world
	var u := _walker(Unit.Team.FOLK, from)
	var out := [false, false, false, 0]
	for t in 3000:
		if w.walk_toward(u, to, 4.0):
			out[0] = true
			break
		var i := w.pathing.index_of(u.pos)
		out[1] = out[1] or w.town.is_gate(i)
		out[2] = out[2] or w.pathing.climb(i)
		out[3] = t
	return out


func test_folk_use_a_nearby_gate_or_climb() -> void:
	var run := _run()
	run.stake_road([Vector2(-150, 0), Vector2(-230, 0)])
	check(run.stake_wall(_ring(184.0)), "staked a ring")
	_raise_all(run)
	var near := _walk_folk(run, Vector2(-120, 30), Vector2(-260, 30))
	check(near[0] and near[1] and not near[2], "beside a gate, they walk through it")
	var far := _walk_folk(run, Vector2(120, 0), Vector2(260, 0))
	check(far[0] and far[2], "far from a gate, they climb over")
	var bare := _run()
	var open := _walk_folk(bare, Vector2(120, 0), Vector2(260, 0))
	check(far[3] > open[3], "climbing is slower (%d vs %d ticks)" % [far[3], open[3]])


func test_raiders_go_round_a_short_palisade() -> void:
	var run := _run()
	var w := run.world
	check(run.stake_wall([Vector2(300, -40), Vector2(300, 40)]), "a short palisade")
	_raise_all(run)
	var e := _walker(Unit.Team.ENEMY, Vector2(400, 0))
	for t in 1500:
		e.cooldown_left -= w.dt
		if w.walk_toward(e, Vector2(200, 0), 4.0):
			break
	check(e.pos.distance_to(Vector2(200, 0)) < 10.0, "the raider got past")
	for i in w.town.walls[0]["cells"]:
		check_eq(w.pathing.wall_hp[i], w.town.max_wall_hp(i), "it went round without a blow")


func test_raiders_batter_through_a_long_palisade() -> void:
	var run := _run()
	var w := run.world
	run.stake_road([Vector2.ZERO, Vector2(0, 260)])
	check(run.stake_wall(_ring(184.0)), "staked a ring")
	_raise_all(run)
	var e := _walker(Unit.Team.ENEMY, Vector2(-300, 0))
	var arrived := false
	for t in 4000:
		e.cooldown_left -= w.dt
		if w.walk_toward(e, Vector2.ZERO, 40.0):
			arrived = true
			break
	check(arrived, "the raider gets in")
	check(w.town.wall_counts()["standing"] < w.town.wall_counts()["staked"], "by breaking the palisade")
	check(int(run._round_entry["breaches"]) > 0, "the breach is recorded")
	w.town.patch_walls()
	check(w.town.next_wall([]) >= 0, "a broken square waits for craftspeople")


func test_craftspeople_raise_staked_palisades() -> void:
	var run := _run()
	check(run.stake_wall([Vector2(150, -100), Vector2(150, 100)]), "staked a palisade")
	run.world.folk_ai.add_folk("craftsperson")
	var wood := int(run.stock["wood"])
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	run.world.dens.clear()
	for i in int(20.0 / run.world.dt):
		run.step()
	check(run.world.town.wall_counts()["standing"] > 0, "some palisade stands")
	check(int(run.stock["wood"]) < wood, "it cost wood")
	check(not run._round_entry["walling"].is_empty(), "the wood is recorded")


func test_buildings_leave_palisade_ground_clear() -> void:
	var run := _run()
	var w := run.world
	check(run.stake_wall(_ring(110.0)), "staked a ring through the plots")
	while run.build("hut"):
		pass
	for b in w.buildings:
		for i in w.town.plots[b["plot"]]["cells"]:
			check(w.town.wall_staked[i] == 0, "no building on the palisade")


func test_record_has_palisades() -> void:
	var run := _run()
	run.stake_wall([Vector2(150, -100), Vector2(150, 100)])
	run.begin_round()
	var record := run.to_record()
	check(int(record["format"]) >= 9, "record format 9 or later")
	var first: Dictionary = record["rounds"][0]
	check(first["actions"].any(func(a: Dictionary) -> bool: return a["kind"] == "wall"), "the palisade is recorded")


func test_bot_can_stake_a_palisade_ring() -> void:
	var run := _run()
	var bot := AutoPlayer.new()
	bot.wall_gates = 4
	bot.wall_round = 1
	bot.build(run)
	check(not run.world.town.walls.is_empty(), "the bot staked a palisade")
	check(run.world.town.gates.size() >= 4, "with gates")
