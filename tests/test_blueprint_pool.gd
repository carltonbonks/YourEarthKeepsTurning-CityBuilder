extends TestCase
## Each run drafts from its own pool of blueprints (BuildHand.pool, blueprint_pool_share in data/balance.json).


func _run(seed_value := 4821, traditions: Array[String] = []) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	run.choose_traditions(traditions)
	return run


func _draftable_count(run: RunState) -> int:
	var all := 0
	for type: String in run.content.buildings:
		var def: Dictionary = run.content.buildings[type]
		if not def.get("basic", false) and not def.has("ages_up"):
			all += 1
	return all


func test_a_run_has_some_of_the_blueprints() -> void:
	var run := _run()
	var pool := run.hand.pool()
	check(pool.size() < _draftable_count(run), "not every blueprint is in the pool")
	check(pool.size() > _draftable_count(run) / 2, "but more than half are")
	for type in ["longhouse", "watch_post", "gate"]:
		check(pool.has(type), "staple %s is always in" % type)
	for type in ["market", "bronzesmith"]:
		check(pool.has(type), "what an age-up requires (%s) is always in" % type)


func test_the_pool_follows_the_seed() -> void:
	check_eq(_run(4821).hand.pool(), _run(4821).hand.pool(), "the same seed deals the same pool")
	check(_run(4821).hand.pool() != _run(1001).hand.pool(), "another seed deals another pool")


func test_traditions_buildings_are_always_in() -> void:
	for seed_value in [4821, 1001, 61823]:
		var pool := _run(seed_value, ["hunters", "smiths"] as Array[String]).hand.pool()
		for type in ["hunting_lodge", "hide_rack", "drying_rack", "smoke_hut", "knapper", "bone_carver", "smelter"]:
			check(pool.has(type), "%s comes with its tradition (seed %d)" % [type, seed_value])


func test_pooled_buildings_bring_what_they_require() -> void:
	for seed_value in [4821, 1001, 61823, 7, 99]:
		var run := _run(seed_value)
		for type in run.hand.pool():
			var needs: String = run.content.buildings[type].get("requires", "")
			check(needs == "" or run.hand.pool().has(needs), "%s brings %s (seed %d)" % [type, needs, seed_value])


func test_offers_come_only_from_the_pool() -> void:
	var run := _run()
	var outside := ""
	for type: String in run.content.buildings:
		var def: Dictionary = run.content.buildings[type]
		if not def.get("basic", false) and not def.has("ages_up") and not run.hand.in_pool(type):
			outside = type
			break
	check(outside != "", "something is left out")
	check(not run.hand.draftable(outside), "a building outside the pool is never offered")
	for i in 6:
		run.hand.redraws = 0
		run.hand._fill(SeededRng.stream(i, "probe"))
		for c: Dictionary in run.hand.cards:
			check(run.hand.in_pool(c["building"]), "offer %s is in the pool" % c["building"])


func test_a_row_needs_the_building_it_adds_in_the_pool() -> void:
	var run := _run()
	for id: String in run.content.combos:
		var row: Dictionary = run.content.combos[id]
		for pair in [[row["building"], row["partner"]], [row["partner"], row["building"]]]:
			if run.content.buildings[pair[0]].get("basic", false) or run.hand.in_pool(pair[1]) \
					or run.content.buildings[pair[1]].get("basic", false):
				continue
			run.hand.blueprints = [pair[0]] as Array[String]
			check(not run.hand._row_draftable(id), "%s is not offered: %s is not in this run's pool" % [id, pair[1]])
			return
	check(true, "every row's buildings happen to be in the pool")


func test_the_record_and_the_hover_name_the_pool() -> void:
	var run := _run()
	check_eq(run.to_record()["pool"], run.hand.pool(), "the record keeps the pool")
	var line := BuildHandView.pool_line(run)
	check(line.contains("%d of %d" % [run.hand.pool().size(), _draftable_count(run)]), "the hover counts it: " + line)
	check(line.contains("Longhouse"), "and names its buildings")
