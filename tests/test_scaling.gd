extends TestCase
## The speed-ups for big towns must not change what happens: same answers as the plain scans.


func _scan(units: Array[Unit], from: Vector2, max_distance: float, accept: Callable) -> Unit:
	var best: Unit = null
	var best_d := max_distance
	for u in units:
		if not accept.call(u):
			continue
		var d := from.distance_to(u.pos)
		if d < best_d:
			best_d = d
			best = u
	return best


func test_grid_finds_the_same_nearest_unit_as_a_scan() -> void:
	var rng := SeededRng.new(7)
	var units: Array[Unit] = []
	for i in 400:
		var u := Unit.new()
		u.id = i
		# Some share a spot, so ties must go to the unit earlier in the list, as the scan does.
		u.pos = Vector2(rng.randf_range(-900, 900), rng.randf_range(-900, 900)).snapped(Vector2(40, 40))
		u.alive = i % 5 != 0
		u.spawned = i % 7 != 0
		units.append(u)
	var grid := UnitGrid.new(900.0)
	grid.rebuild(units)
	var mismatches := 0
	for q in 300:
		var from := Vector2(rng.randf_range(-950, 950), rng.randf_range(-950, 950))
		var reach := rng.randf_range(10, 400)
		var home := rng.randf_range(200, 1300)
		var accept := func(u: Unit) -> bool: return u.alive and u.spawned and u.pos.length() <= home
		if grid.nearest(from, reach, home, true) != _scan(units, from, reach, accept):
			mismatches += 1
	check_eq(mismatches, 0, "grid and scan disagree")


func test_big_town_steps_without_errors() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	for i in 150:
		run.world.folk_ai.add_folk(["tribesperson", "craftsperson", "warrior"][i % 3])
	run.choose_pick(-1)
	for i in 300:
		run.step()
	check(run.world.folk.size() > 100, "the big town is still there")
	run.dispose()
