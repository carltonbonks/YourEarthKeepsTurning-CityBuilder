extends TestCase
## Gatherers plan their trips: none they can't finish before dusk, and they spread over goods and nodes.


## A run on its first morning with no monsters about and only the given nodes on the map
## (each {"id", "pos", "amount"}); returns the run.
func _setup(node_list: Array) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	w.enemies.clear()
	w.nodes.clear()
	for n: Dictionary in node_list:
		w._add_node(n["id"], n["pos"])
		if n.has("amount"):
			w.nodes[-1]["amount"] = n["amount"]
	return run


func _tribesperson(run: RunState) -> Unit:
	for u in run.world.folk:
		if u.type_id == "tribesperson":
			u.pos = Vector2.ZERO
			u.task = ""
			return u
	return run.world.folk_ai.add_folk("tribesperson")


func test_no_trip_that_cannot_finish_before_dusk() -> void:
	var run := _setup([{"id": "berries", "pos": Vector2(500, 0)}])
	run.stock["food"] = 0
	var w := run.world
	var u := _tribesperson(run)
	w.folk_ai.begin_step()
	check_eq(w.folk_ai.plan_trip(u), 0, "in the morning the far berries are worth the walk")
	# 500 away at speed 55 is ~10s of walking; with 8s of daylight left it can't be done.
	w.time = w.content.num("day_seconds") - w.content.num("dusk_seconds") - 8.0
	check_eq(w.folk_ai.plan_trip(u), -1, "late in the day nobody sets off for them")


func test_late_in_the_day_a_nearer_trip_still_goes() -> void:
	var run := _setup([{"id": "berries", "pos": Vector2(500, 0)}, {"id": "brush", "pos": Vector2(150, 0)}])
	run.stock["food"] = 0
	var w := run.world
	var u := _tribesperson(run)
	w.time = w.content.num("day_seconds") - w.content.num("dusk_seconds") - 8.0
	w.folk_ai.begin_step()
	check_eq(w.folk_ai.plan_trip(u), 1, "the brush nearby can still be fetched before dusk")


func test_gatherers_do_not_all_crowd_one_small_node() -> void:
	var run := _setup([{"id": "berries", "pos": Vector2(200, 0), "amount": 2}, {"id": "berries", "pos": Vector2(0, 300)}])
	run.stock["food"] = 0
	var w := run.world
	var a := _tribesperson(run)
	var b := w.folk_ai.add_folk("tribesperson")
	b.pos = Vector2.ZERO
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(a)
	check_eq(a.task_index, 0, "the first goes to the nearer thicket")
	w.folk_ai._choose_work(b)
	check_eq(b.task_index, 1, "it only has one load left, so the second goes to the other")


func test_gatherers_spread_over_what_the_town_is_short_of() -> void:
	var run := _setup([{"id": "berries", "pos": Vector2(200, 0), "amount": 60}, {"id": "grove", "pos": Vector2(0, 220), "amount": 60}])
	var w := run.world
	var crew: Array[Unit] = []
	for i in 12:
		var u := w.folk_ai.add_folk("tribesperson")
		u.pos = Vector2.ZERO
		crew.append(u)
	var wants := run.resource_wants()
	run.stock["food"] = int(wants["food"]) - 10  # Each good is ten short: five loads apiece.
	run.stock["wood"] = int(wants["wood"]) - 10
	w.folk_ai.begin_step()
	var picks := {}
	for u in crew:
		w.folk_ai._choose_work(u)
		picks[u.task_index] = int(picks.get(u.task_index, 0)) + 1
	check(int(picks.get(0, 0)) >= 4 and int(picks.get(1, 0)) >= 4,
		"the crew splits over both shortages instead of all chasing one (%s)" % picks)


func test_gathering_is_recorded() -> void:
	var run := _setup([{"id": "berries", "pos": Vector2(60, 0)}])
	run.stock["food"] = 0
	var w := run.world
	var u := _tribesperson(run)
	for i in 200:
		w.folk_ai.begin_step()
		w.folk_ai.folk_tick(u)
	check(int(run.record.entry["gathered"].get("food", 0)) > 0, "food brought in shows in the round's record")
