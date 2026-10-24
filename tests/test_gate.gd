extends TestCase
## Gates: a building that goes beside buildings of a ring (best in a gap) where the busiest path runs (Town, Pathing, World.walk_toward).


func _run(seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	for r: String in ["wood", "stone", "shells"]:
		run.stock[r] = 999
	# These tests work in the third ring, so open it as if it had been cleared.
	run.rings_open = 3
	return run


## A plot in the outer stone-age ring facing west, with no obstacle on it or its neighbours.
func _west_plot(run: RunState) -> int:
	var town := run.world.town
	var best := -1
	for k in town.plots.size():
		var plot: Dictionary = town.plots[k]
		if int(plot["ring"]) != 2 or plot["obstacle"] != "":
			continue
		if best < 0 or (plot["pos"] as Vector2).x < (town.plots[best]["pos"] as Vector2).x:
			best = k
	return best


## Fills plots with boulders. close_ring fills the whole of plot k's ring but k; otherwise just its neighbours.
func _fill(run: RunState, k: int, close_ring: bool) -> void:
	var town := run.world.town
	var fill: Array = town.ring_neighbours(k)
	if close_ring:
		fill = range(town.plots.size()).filter(func(n: int) -> bool: return town.plots[n]["ring"] == town.plots[k]["ring"] and n != k)
	for n: int in fill:
		town.plots[n]["obstacle"] = "boulder"
		town._set_plot_solid(n, true)


## Takes the seeded boulders and oaks away.
func _clear(run: RunState) -> void:
	var town := run.world.town
	for n in town.plots.size():
		if town.plots[n]["obstacle"] != "":
			town.plots[n]["obstacle"] = ""
			town._set_plot_solid(n, false)


## Many feet across plot k, so the gap there is the busiest.
func _tread(run: RunState, k: int) -> void:
	for i in run.world.town.plots[k]["cells"]:
		run.world.pathing.traffic[i] += 20.0


## Orders a gate and finishes it at once. Returns its building index.
func _gate(run: RunState) -> int:
	check(run.build("gate"), "a gate can be ordered")
	var b := run.world.buildings.size() - 1
	run.world.buildings[b]["work_left"] = 0.0
	run.world.town.on_built(b)
	return b


func _walker(team: Unit.Team, at: Vector2) -> Unit:
	var u := Unit.new()
	u.team = team
	u.speed = 50.0
	u.attack = 5.0
	u.cooldown = 1.0
	u.pos = at
	return u


func test_a_gate_goes_beside_a_building() -> void:
	var run := _run()
	var k := _west_plot(run)
	var town := run.world.town
	_clear(run)
	check_eq(town.choose_plot("gate"), -1, "nothing built, nowhere for a gate")
	check(not run.can_build("gate"), "so it can't be ordered")
	var side: int = town.ring_neighbours(k)[0]
	town.plots[side]["obstacle"] = "boulder"
	town._set_plot_solid(side, true)
	check(town.ring_neighbours(town.choose_plot("gate")).has(side), "a gate goes beside something standing")


func test_gate_prefers_a_gap_then_the_feet() -> void:
	var run := _run()
	var town := run.world.town
	_clear(run)
	var k := _west_plot(run)
	_fill(run, k, false)
	# A second gap on the far side of the ring, with nobody walking through it.
	var other: int = town.ring_neighbours(town.ring_neighbours(k)[0])[0]
	other = town.ring_neighbours(town.ring_neighbours(other)[0])[0]
	_fill(run, other, false)
	_tread(run, k)
	check_eq(town.choose_plot("gate"), k, "of two gaps, the gate goes where the most feet pass")
	# A plot with a building on one side only, however busy, loses to a true gap.
	var half: int = town.ring_neighbours(town.ring_neighbours(k)[1])[1]
	_tread(run, half)
	_tread(run, half)
	check_eq(town.choose_plot("gate"), k, "a true gap beats a busier half-gap")


func test_folk_walk_through_and_raiders_batter() -> void:
	var run := _run()
	var w := run.world
	var k := _west_plot(run)
	_fill(run, k, true)
	var b := _gate(run)
	check_eq(int(w.buildings[b]["plot"]), k, "the gate fills the only gap")
	check(w.town.gate_health(b) == 1.0, "it stands at full health")
	var outside: Vector2 = (w.town.plots[k]["pos"] as Vector2) * 1.5
	# Townsfolk walk through it.
	var folk := _walker(Unit.Team.FOLK, outside)
	var through := false
	for t in 2000:
		if w.walk_toward(folk, Vector2.ZERO, 40.0):
			through = true
			break
	check(through, "a townsperson walks in through the gate")
	check(w.town.gate_health(b) == 1.0, "without harming it")
	# A raider has to batter it down.
	var e := _walker(Unit.Team.ENEMY, outside)
	var arrived := false
	for t in 4000:
		e.cooldown_left -= w.dt
		if w.walk_toward(e, Vector2.ZERO, 40.0):
			arrived = true
			break
	check(arrived, "the raider gets in")
	check(w.town.gate_health(b) < 1.0, "by battering the gate")
	check_eq(int(w.town.gate_counts()["broken"]), 1, "the gate counts as broken")
	check(int(run.record.entry["breaches"]) > 0, "the breach is recorded")
	w.town.patch_walls()
	check(w.town.gate_health(b) == 1.0, "it is mended at dawn")


func test_raiders_go_round_a_gate_in_an_open_ring() -> void:
	var run := _run()
	var w := run.world
	var k := _west_plot(run)
	_fill(run, k, false)
	var b := _gate(run)
	var outside: Vector2 = (w.town.plots[k]["pos"] as Vector2) * 1.4
	var e := _walker(Unit.Team.ENEMY, outside)
	for t in 3000:
		e.cooldown_left -= w.dt
		if w.walk_toward(e, Vector2.ZERO, 40.0):
			break
	check(e.pos.length() < 50.0, "the raider got in")
	check(w.town.gate_health(b) == 1.0, "round the ends, without a blow")


func test_paving_stays_under_a_gate() -> void:
	var run := _run()
	var w := run.world
	var k := _west_plot(run)
	_fill(run, k, false)
	for i in w.town.plots[k]["cells"]:
		w.pathing.set_ground(i, Pathing.FIRST_ROAD)
	var stone := int(run.stock["stone"])
	_gate(run)
	for i in w.town.plots[k]["cells"]:
		check(w.pathing.is_road(i), "the road runs on through the gate")
	check(int(run.stock["stone"]) <= stone, "nothing is lifted or refunded")


func test_watch_posts_like_gates() -> void:
	var run := _run()
	var w := run.world
	var k := _west_plot(run)
	_fill(run, k, false)
	w.wave_sides.assign([0.0])  # Warned from the east, away from the gate: the gate still wins.
	var b := _gate(run)
	check(run.build("watch_post"), "a watch post can be ordered")
	var post: Dictionary = w.buildings[-1]
	check((post["pos"] as Vector2).distance_to(w.buildings[b]["pos"]) < float(run.content.town["gate"]["guard_within"]),
		"it stands by the gate")


func test_bot_orders_a_gate() -> void:
	var run := _run()
	var k := _west_plot(run)
	_fill(run, k, false)
	run.round_number = 3
	var bot := AutoPlayer.new()
	bot.gates = 1
	bot.gate_round = 3
	run.hand.blueprints = ["gate"] as Array[String]
	bot.build(run)
	check_eq(run.world.count_buildings("gate", false), 1, "the bot ordered a gate")


func test_record_counts_gates() -> void:
	var run := _run()
	var k := _west_plot(run)
	_fill(run, k, false)
	_gate(run)
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	run.world.dens.clear()
	var snapshot: Dictionary = run.record.town_snapshot()
	check_eq(int(snapshot["gates"]["built"]), 1, "the round's town counts the gate")


func _near(run: RunState, a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < float(run.content.town["gate"]["guard_within"])


func test_watch_posts_take_gates_in_turn() -> void:
	var run := _run()
	var w := run.world
	var town := w.town
	var k := _west_plot(run)
	_fill(run, k, false)
	# A second gap on the far side of the ring.
	var east := k
	for n in town.plots.size():
		if int(town.plots[n]["ring"]) == 2 and (town.plots[n]["pos"] as Vector2).x > (town.plots[east]["pos"] as Vector2).x:
			east = n
	_fill(run, east, false)
	var first := _gate(run)
	var second := _gate(run)
	# The attack comes in by the newer gate's side, so the first post leans that way.
	w.wave_sides.assign([(w.buildings[second]["pos"] as Vector2).angle()])
	check(run.build("watch_post"), "a first watch post")
	var p1: Dictionary = w.buildings[-1]
	check(run.build("watch_post"), "a second watch post")
	var p2: Dictionary = w.buildings[-1]
	check(_near(run, p1["pos"], w.buildings[second]["pos"]), "the first post guards the gate the attack comes in by")
	check(_near(run, p2["pos"], w.buildings[first]["pos"]), "the second post goes to the other gate")
	for post: Dictionary in [p1, p2]:
		check(not town.plots[post["plot"]]["lane"], "a post never stands in a lane")


func test_watch_posts_guard_lanes_without_gates() -> void:
	var run := _run()
	var w := run.world
	for i in 4:
		check(run.build("watch_post"), "watch post %d can be ordered" % (i + 1))
	var posts := w.buildings.filter(func(b: Dictionary) -> bool: return b["type"] == "watch_post")
	for i in posts.size():
		check(not w.town.plots[posts[i]["plot"]]["lane"], "watch post %d keeps the lane free" % i)
		for j in range(i + 1, posts.size()):
			check(not _near(run, posts[i]["pos"], posts[j]["pos"]), "watch posts %d and %d guard different spots" % [i, j])


func test_a_second_post_moves_on_from_a_guarded_gate() -> void:
	var run := _run()
	var w := run.world
	var k := _west_plot(run)
	_fill(run, k, false)
	var b := _gate(run)
	run.build("watch_post")
	check(_near(run, w.buildings[-1]["pos"], w.buildings[b]["pos"]), "the first post guards the gate")
	run.build("watch_post")
	check(not _near(run, w.buildings[-1]["pos"], w.buildings[b]["pos"]), "the next one guards somewhere else")
