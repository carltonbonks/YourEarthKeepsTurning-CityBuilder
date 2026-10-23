extends TestCase
## Opening rings: a run starts with a few rings of plots open; ageing up opens the next for free, and once the
## open rings are nearly full the blueprint draft offers to clear the next one for goods (BuildHand.clear_ring).


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func _rich(run: RunState) -> void:
	for r: String in ["wood", "stone", "shells"]:
		run.stock[r] = 999


func _fill(run: RunState) -> void:
	_rich(run)
	while run.build("hut"):
		pass


func _open_rings(run: RunState) -> Array:
	var out := []
	for plot in run.world.town.plots:
		if run.world.town.ring_open(plot) and not out.has(int(plot["ring"])):
			out.append(int(plot["ring"]))
	return out


func test_a_run_starts_with_its_opening_rings() -> void:
	var run := _run()
	var start := int(run.content.town["start_rings"])
	check_eq(run.rings_open, start, "start_rings are open")
	check_eq(_open_rings(run).size(), start, "only their plots are open")
	for plot in run.world.town.plots:
		if plot["obstacle"] != "":
			check(int(plot["ring"]) < int(run.content.town["obstacle_rings"]), "obstacles sit on the inner rings")


func test_no_ring_offer_while_there_is_room() -> void:
	var run := _run()
	check(run.world.town.fullness() < 0.1, "a new town is nearly empty")
	check(not run.hand.ring_offer(), "no ring is offered")
	check(not run.hand.labels().has("ring"), "nor recorded as offered")


func test_a_full_town_can_clear_the_next_ring() -> void:
	var run := _run()
	_fill(run)
	check(run.world.town.fullness() >= float(run.content.town["clear_when_full"]), "huts filled the open rings")
	check(not run.can_build("hut"), "no room for another hut")
	check(run.hand.ring_offer(), "the draft offers to clear a ring")
	check(run.hand.labels().has("ring"), "the record lists the ring offer")
	var cost := run.ring_cost()
	check(not cost.is_empty(), "clearing costs goods")
	var wood := int(run.stock["wood"])
	var picks := run.hand.picks
	check(run.hand.clear_ring(), "cleared")
	check_eq(run.rings_open, int(run.content.town["start_rings"]) + 1, "one more ring is open")
	check_eq(int(run.stock["wood"]), wood - int(cost.get("wood", 0)), "it paid the ring's cost")
	check_eq(run.hand.picks, picks - 1, "it took a draft")
	check(run.build("hut"), "there is room again")
	var actions: Array = run.record.entry["actions"]
	check(actions.any(func(a: Dictionary) -> bool: return a["kind"] == "clear_ring"), "the clearing is recorded")


func test_clearing_needs_the_goods_and_a_draft() -> void:
	var run := _run()
	_fill(run)
	run.stock["wood"] = 0
	run.stock["stone"] = 0
	check(run.hand.ring_offer(), "still offered")
	check(not run.hand.clear_ring(), "but it can't be paid for")
	_rich(run)
	run.hand.picks = 0
	check(not run.hand.ring_offer(), "not offered with no draft left")
	check(not run.hand.clear_ring(), "nor cleared")


func test_ageing_up_opens_a_ring_for_free() -> void:
	var run := _run()
	var wood := int(run.stock["wood"])
	run.on_building_done("bronze_moot")
	check_eq(run.age, "bronze", "the town aged up")
	check_eq(run.rings_open, int(run.content.town["start_rings"]) + 1, "the next ring opened")
	check(int(run.stock["wood"]) >= wood, "for nothing")


func test_once_every_ring_is_open_none_is_offered() -> void:
	var run := _run()
	while run.ring_closed():
		run.open_ring()
	check_eq(run.rings_open, run.content.town["rings"].size(), "every ring is open")
	check(run.ring_cost().is_empty(), "nothing left to pay for")
	_fill(run)
	check(not run.hand.ring_offer(), "no ring offer")
