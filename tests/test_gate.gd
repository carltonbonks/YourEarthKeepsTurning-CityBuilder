extends TestCase
## Gates: a building that goes beside buildings of a ring (best in a gap) where the busiest path runs (Town, Pathing, World.walk_toward).


func _run(seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	for r: String in ["wood", "stone", "shells"]:
		run.stock[r] = 999
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
	w.wave_sides.assign([PI])  # Warned from the west, where the gate is.
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


func test_watch_posts_spread_out() -> void:
	var run := _run()
	var w := run.world
	var spread := float(run.content.buildings["watch_post"]["spread"])
	for i in 4:
		check(run.build("watch_post"), "watch post %d can be ordered" % (i + 1))
	var posts := w.buildings.filter(func(b: Dictionary) -> bool: return b["type"] == "watch_post")
	for i in posts.size():
		for j in range(i + 1, posts.size()):
			check((posts[i]["pos"] as Vector2).distance_to(posts[j]["pos"]) >= spread * 0.75,
				"watch posts %d and %d stand apart" % [i, j])


func test_watch_posts_may_crowd_a_gate() -> void:
	var run := _run()
	var w := run.world
	var k := _west_plot(run)
	_fill(run, k, false)
	w.wave_sides.assign([PI])
	var b := _gate(run)
	var near := 0
	for i in 2:
		check(run.build("watch_post"), "a watch post can be ordered")
		if (w.buildings[-1]["pos"] as Vector2).distance_to(w.buildings[b]["pos"]) < float(run.content.town["gate"]["guard_within"]):
			near += 1
	check_eq(near, 2, "both posts guard the gate, close together")
