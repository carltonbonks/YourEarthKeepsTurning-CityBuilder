extends TestCase
## Raider routes and quick defences (Yusuf, 2026-10-27): the warned attack's route preview (World.raider_routes,
## Pathing.route_preview), spotting raiders (EnemyAI.spot_tick), the alarm and barricades folk throw up in the
## gaps (FolkAI.raise_alarm, Town.barricade_plots / raise_barricade / clear_barricades, World._batter).


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.world.enemies.clear()
	run.stock["wood"] = 20
	_clear(run)
	return run


## Takes the seeded boulders and oaks away.
func _clear(run: RunState) -> void:
	var town := run.world.town
	for n in town.plots.size():
		if town.plots[n]["obstacle"] != "":
			town.plots[n]["obstacle"] = ""
			town._set_plot_solid(n, false)


func _boulder(run: RunState, n: int) -> void:
	run.world.town.plots[n]["obstacle"] = "boulder"
	run.world.town._set_plot_solid(n, true)


## The plot of an open ring nearest angle a.
func _plot_facing(run: RunState, ring: int, a: float) -> int:
	var town := run.world.town
	var best := -1
	for k in town.plots.size():
		if int(town.plots[k]["ring"]) != ring:
			continue
		if best < 0 or absf(angle_difference(a, (town.plots[k]["pos"] as Vector2).angle())) \
				< absf(angle_difference(a, (town.plots[best]["pos"] as Vector2).angle())):
			best = k
	return best


## A gap facing east in the outer open ring: boulders on both sides of it.
func _east_gap(run: RunState) -> int:
	var town := run.world.town
	var k := _plot_facing(run, run.rings_open - 1, 0.0)
	for n: int in town.ring_neighbours(k):
		_boulder(run, n)
	return k


func _raider(run: RunState, at: Vector2) -> Unit:
	var e := run.world.enemy_ai.make_enemy("raider", at, 0.0)
	e.spawned = true
	run.world.enemies.append(e)
	return e


func _worker(run: RunState, at: Vector2) -> Unit:
	var u: Unit = run.world.folk.filter(func(f: Unit) -> bool: return f.type_id == "craftsperson")[0]
	u.pos = at
	u.task = ""
	return u


func test_the_route_is_straight_over_open_ground() -> void:
	var run := _run()
	var w := run.world
	w.wave_sides.assign([0.0])
	var routes := w.raider_routes()
	check_eq(routes.size(), 1, "one route per warned side")
	var route: PackedVector2Array = routes[0]
	check(route[0].x > 700.0 and absf(route[0].y) < 1.0, "it starts at the map's edge on the warned side")
	check(route[route.size() - 1].length() < 1.0, "and ends at the hearth")
	run.dispose()


func test_the_route_bends_through_a_gap_in_a_walled_ring() -> void:
	var run := _run()
	var w := run.world
	var town := w.town
	var gap := _plot_facing(run, 1, PI / 2.0)
	for k in town.plots.size():
		if int(town.plots[k]["ring"]) == 1 and k != gap:
			_boulder(run, k)
	w.wave_sides.assign([0.0])
	var route: PackedVector2Array = w.raider_routes()[0]
	check(route.size() > 2, "the line has corners now (%d points)" % route.size())
	var nearest := INF
	for n in route.size() - 1:
		nearest = minf(nearest, Geometry2D.get_closest_point_to_segment(town.plots[gap]["pos"], route[n], route[n + 1]).distance_to(town.plots[gap]["pos"]))
	check(nearest < 25.0, "and it goes in through the one gap (passes %.0f from it)" % nearest)
	# The cache follows the town: wall the gap and the route changes.
	var before := route
	_boulder(run, gap)
	check(w.raider_routes()[0] != before, "a change to the town redraws the line")
	run.dispose()


func test_a_spotted_raider_raises_the_alarm_and_folk_barricade_the_gap() -> void:
	var run := _run()
	var w := run.world
	var gap := _east_gap(run)
	var site: Vector2 = w.town.plots[gap]["pos"]
	var folk := _worker(run, site + Vector2(-20.0, 0.0))
	var e := _raider(run, Vector2(site.length() + 70.0, 0.0))
	w.enemy_ai.spot_tick()
	check(e.spotted, "a townsperson within reach spots the raider")
	check(not w.barricades.is_empty(), "the alarm sends folk to barricade that side")
	if w.barricades.is_empty():
		run.dispose()
		return
	check_eq(int(w.barricades[0]["plot"]), gap, "the true gap facing the raider first")
	check_eq(int(run.stock["wood"]), 20 - w.barricades.size(), "each paid for from stock")
	check_eq(folk.barricade, 0, "the nearest free hands run to raise it")
	check_eq(w.spots.size(), 1, "the map can show who spotted it")
	# Move the raider off so the worker doesn't flee, then let the worker raise it.
	e.pos = Vector2(700.0, 0.0)
	for i in 400:
		w.folk_ai.folk_tick(folk)
		if w.barricades[0]["built"]:
			break
	check(w.barricades[0]["built"], "the barricade goes up")
	check_eq(folk.barricade, -1, "and the worker goes back to its day")
	var walled := 0
	for i in w.town.plots[gap]["cells"]:
		if w.pathing.wall_hp[i] > 0.0:
			walled += 1
	check(walled > 0, "its squares are walled like a gate's (%d)" % walled)
	# The same way doesn't raise a second alarm.
	var planned := w.barricades.size()
	var again := _raider(run, Vector2(site.length() + 90.0, 10.0))
	folk.pos = site
	w.enemy_ai.spot_tick()
	check(again.spotted, "the second raider is spotted too")
	check_eq(w.barricades.size(), planned, "but the alarm from that way was already raised")
	run.dispose()


func test_no_wood_no_barricades() -> void:
	var run := _run()
	var w := run.world
	var gap := _east_gap(run)
	run.stock["wood"] = 0
	_worker(run, w.town.plots[gap]["pos"])
	var e := _raider(run, Vector2((w.town.plots[gap]["pos"] as Vector2).length() + 100.0, 0.0))
	w.enemy_ai.spot_tick()
	check(e.spotted, "spotted")
	check(w.barricades.is_empty(), "nothing to build with")
	run.dispose()


func test_den_wanderers_raise_no_alarm() -> void:
	var run := _run()
	var w := run.world
	var gap := _east_gap(run)
	_worker(run, w.town.plots[gap]["pos"])
	var e := _raider(run, Vector2((w.town.plots[gap]["pos"] as Vector2).length() + 60.0, 0.0))
	e.den_index = 0
	w.enemy_ai.spot_tick()
	check(not e.spotted and w.barricades.is_empty(), "a den's wanderer isn't coming for the town")
	run.dispose()


func test_greenwood_cover_hides_raiders_until_closer() -> void:
	var run := _run()
	var w := run.world
	var at := Vector2.from_angle(0.0) * 350.0
	var watcher := _worker(run, at - Vector2(100.0, 0.0))
	var reach := float(run.content.town["barricades"]["spot_range"])
	check(reach * w.earth.sight_at(at) >= 100.0 or w.earth.sight_at(at) < 1.0, "test set-up: a plain plate sees 100 off")
	var e := _raider(run, at)
	w.enemy_ai.spot_tick()
	check_eq(e.spotted, 100.0 <= reach * w.earth.sight_at(at), "spotting reach follows the plate's sight (%s)" % w.earth.kind_at(at))
	watcher.pos = at - Vector2(reach * 0.5, 0.0)
	w.enemy_ai.spot_tick()
	check(e.spotted, "close enough, any plate's raider is seen")
	run.dispose()


func test_raiders_break_a_barricade_without_a_breach_and_dawn_clears_them() -> void:
	var run := _run()
	var w := run.world
	var gap := _east_gap(run)
	_worker(run, w.town.plots[gap]["pos"])
	var e := _raider(run, Vector2((w.town.plots[gap]["pos"] as Vector2).length() + 100.0, 0.0))
	w.enemy_ai.spot_tick()
	w.town.raise_barricade(0)
	var square: int = w.barricade_square.keys()[0]
	var breaches := int(run.record.entry.get("breaches", 0))
	for i in 20:
		e.cooldown_left = 0.0
		w._batter(e, square)
	check_eq(w.pathing.wall_hp[square], 0.0, "raiders batter a square open")
	check(w.barricades[0]["broken"], "the barricade counts as broken")
	check_eq(int(run.record.entry.get("breaches", 0)), breaches, "a barricade isn't a gate: no breach")
	# A second, never raised, is refunded at dawn.
	w.barricades.append({"plot": _plot_facing(run, 0, PI), "pos": Vector2.ZERO, "work_left": 2.0, "built": false, "broken": false, "cost": {"wood": 1}})
	var wood := int(run.stock["wood"])
	var unraised := w.barricades.filter(func(b: Dictionary) -> bool: return not b["built"]).size()
	w.town.clear_barricades()
	check(w.barricades.is_empty() and w.barricade_square.is_empty() and w.alarm_ways.is_empty(), "dawn clears them all")
	check_eq(int(run.stock["wood"]), wood + unraised, "the unraised ones' wood comes back")
	for i in w.town.plots[gap]["cells"]:
		check_eq(w.pathing.wall_hp[i], 0.0, "no wall left at dawn")
		break
	run.dispose()
