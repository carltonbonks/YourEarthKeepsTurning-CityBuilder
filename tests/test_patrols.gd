extends TestCase
## Warriors' patrol: it walks round the outside of the town proper (leaving far-out fields and huts past an empty
## ring outside), and once enough warriors patrol they walk it in pairs, then small squads, spread round the town.


## A run on its first night (no shadowing) with no monsters, no townsfolk and no obstacles on the plots.
func _setup() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	w.enemies.clear()
	w.folk.clear()
	for plot in w.town.plots:
		plot["obstacle"] = ""
	w.time = w.content.num("day_seconds") - 1.0
	return run


## Puts a stand-in building on the plot of this ring that holds the angle, and returns the plot.
func _put(run: RunState, ring: int, angle: float) -> int:
	var w := run.world
	for k in w.town.plots.size():
		var plot: Dictionary = w.town.plots[k]
		if int(plot["ring"]) == ring and absf(angle_difference(angle, (plot["pos"] as Vector2).angle())) \
				<= (float(plot["a1"]) - float(plot["a0"])) / 2.0:
			plot["building"] = w.buildings.size()
			w.buildings.append({"type": "field", "plot": k, "pos": plot["pos"]})
			return k
	check(false, "a plot on ring %d at angle %.2f" % [ring, angle])
	return -1


## Where the patrol runs just past this ring: the middle of the open gap outside it.
func _past(run: RunState, ring: int) -> float:
	var town := run.world.content.town
	return float(town["rings"][ring]["radius"]) + float(town["ring_depth"]) / 2.0 \
			+ float(run.world.content.townsfolk["warrior"]["patrol_margin"])


func _warriors(run: RunState, count: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for n in count:
		var u := run.world.folk_ai.add_folk("warrior")
		u.pos = Vector2.ZERO
		out.append(u)
	return out


func test_patrol_hugs_the_town_edge() -> void:
	var run := _setup()
	var town := run.world.town
	check_eq(town.patrol_radius(0.0), _past(run, 0), "an empty town is patrolled just past the first ring")
	_put(run, 1, 0.0)
	check_eq(town.patrol_radius(0.0), _past(run, 1), "a building on the second ring pushes the patrol out round it")
	check_eq(town.patrol_radius(PI), _past(run, 0), "the far side keeps the short patrol")
	_put(run, 3, PI / 2.0)
	check_eq(town.patrol_radius(PI / 2.0), _past(run, 0), "a field out past an empty ring is left outside the patrol")
	_put(run, 1, PI / 2.0)
	_put(run, 2, PI / 2.0)
	check_eq(town.patrol_radius(PI / 2.0), _past(run, 3), "once the rings between fill, it counts")


func test_patrol_never_runs_through_buildings() -> void:
	var run := _setup()
	var w := run.world
	for ring in 3:
		for n in 6:
			w.add_building("field")
	for n in 64:
		var angle := TAU * n / 64.0
		var at := Vector2.from_angle(angle) * w.town.patrol_radius(angle)
		check(not w.pathing.is_solid(w.pathing.index_of(at)), "the patrol at %.2f is on open ground" % angle)


func test_warriors_pair_up_then_form_squads() -> void:
	var run := _setup()
	var w := run.world
	var few := _warriors(run, 3)
	w.folk_ai.begin_step()
	check_eq(w.folk_ai.patrol_group_size(), 1, "a few warriors patrol alone")
	w.folk_ai.folk_tick(few[0])
	check_eq(few[0].intent, "patrolling", "alone")
	_warriors(run, 1)
	w.folk_ai.begin_step()
	check_eq(w.folk_ai.patrol_group_size(), 2, "four patrol in pairs")
	w.folk_ai.folk_tick(few[0])
	check_eq(few[0].intent, "patrolling in a pair", "the intent says so")
	_warriors(run, 6)
	w.folk_ai.begin_step()
	check_eq(w.folk_ai.patrol_group_size(), 4, "ten patrol in squads of four")


func test_partners_walk_together_and_groups_spread_out() -> void:
	var run := _setup()
	var w := run.world
	var all := _warriors(run, 4)
	for u in all:
		u.pos = Vector2(_past(run, 0), 0.0).rotated(PI / 3.0)
	w.folk_ai.begin_step()
	for u in all:
		for n in 120:
			w.folk_ai.folk_tick(u)
	check(all[0].pos.distance_to(all[1].pos) < 30.0, "a pair walks a few paces apart")
	check(all[0].pos.distance_to(all[2].pos) > 120.0, "the other pair patrols the far side")
