extends TestCase
## Crafts, the deepening offer, building again and the replenishing upgrades (Yusuf, 2026-10-26; sim/build_hand.gd).


func _run(seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	run.choose_traditions([])
	return run


func _crafts(run: RunState) -> Array:
	return run.hand.crafts.map(func(c: Dictionary) -> String: return c["craft"])


## Deals the round's draft again with these drafts left.
func _redeal(run: RunState, picks := 1) -> void:
	run.hand.picks = picks
	run.hand._fill(SeededRng.stream(run.run_seed, "test", run.round_number))


func test_the_market_comes_as_a_choice_of_first_craft() -> void:
	var run := _run()
	check_eq(run.hand.crafts.size(), run.content.int_num("market_crafts"), "the draft offers crafts to start the market with")
	for c in run.hand.crafts:
		check(run.hand.craft_adds(c["craft"]).has("market"), "%s brings the market" % c["craft"])
		check_eq(c["need"], "ageing", "the market is needed to age up")
	for c in run.hand.cards:
		check(not run.hand.is_piece(c["building"]), "%s: no stall, workshop or market on its own card" % c["building"])
	check_eq(run.hand.cards.size() + run.hand.crafts.size() + run.hand.upgrade_offers.size(), run.hand.size(), "a full draft")


func test_drafting_a_craft_adds_the_market_workshop_and_stall() -> void:
	var run := _run()
	var id: String = _crafts(run)[0]
	var craft: Dictionary = run.content.crafts[id]
	check(run.hand.draft_craft(id), "drafted")
	for type: String in ["market", craft["workshop"], craft["stall"]]:
		check(run.hand.offers(type), "%s joins the blueprints" % type)
	check(run.hand.crafts_taken.has(id), "the craft is kept")
	check(run.to_record()["crafts"].has(id), "the record keeps it")
	# A second craft brings only its own pieces.
	var other := ""
	for c: String in run.content.crafts:
		if c != id:
			other = c
	check_eq(run.hand.craft_adds(other), [run.content.crafts[other]["workshop"], run.content.crafts[other]["stall"]] as Array[String],
		"a later craft adds just its workshop and stall")


func test_pieces_never_come_alone_and_offers_never_repeat() -> void:
	for seed_value in [3, 17, 4821, 9001]:
		var run := _run(seed_value)
		run.hand.draft_craft(_crafts(run)[0])
		for r in 6:
			run.round_number += 1
			_redeal(run)
			var seen: Array[String] = []
			for c in run.hand.cards:
				check(not run.hand.is_piece(c["building"]), "%s is never a single offer" % c["building"])
				seen.append(c["building"])
			for c in run.hand.crafts:
				for type in run.hand.craft_adds(c["craft"]):
					seen.append(type)
			for type in seen:
				check_eq(seen.count(type), 1, "seed %d: %s is offered once a draft" % [seed_value, type])


func test_a_craft_opens_buildings_only_it_brings() -> void:
	var run := _run()
	var opens: Array = run.content.crafts["hides"]["opens"]
	for type: String in opens:
		check(not run.hand.draftable(type), "%s waits for its craft" % type)
	run.hand.crafts = [{"craft": "hides", "need": ""}]
	run.hand.picks = 1
	check(run.hand.draft_craft("hides"), "drafted")
	for type: String in opens:
		check(run.hand.opened(type), "%s is open once the town has the hides craft" % type)


func test_a_tradition_never_holds_its_buildings_back() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions(["hunters"])
	check(run.hand.opened("hunting_lodge"), "the hunters' lodge comes up without the hides craft")


func test_one_offer_builds_on_what_the_town_has() -> void:
	var run := _run()
	run.hand.draft_craft("arms" if _crafts(run).has("arms") else _crafts(run)[0])
	var taken: String = run.hand.crafts_taken[0]
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	run.hand.order(run.content.crafts[taken]["workshop"])
	for i in 4:
		run.round_number += 1
		_redeal(run)
		var deep := run.hand.cards.filter(func(c: Dictionary) -> bool: return c.has("deep")).size() \
			+ run.hand.crafts.filter(func(c: Dictionary) -> bool: return c.has("deep")).size() \
			+ run.hand.upgrade_offers.filter(func(c: Dictionary) -> bool: return c.has("deep")).size()
		check_eq(deep, 1, "round %d: one deepening offer" % run.round_number)
		check_eq(run.hand.cards.size() + run.hand.crafts.size() + run.hand.upgrade_offers.size(), run.hand.size(), "a full draft")
		for c in run.hand.cards:
			if c.has("deep"):
				check(run.hand.opener(c["building"]) == taken, "a deep building was opened by the town's craft")
		for c in run.hand.crafts:
			check(c.has("deep"), "once the market is in, a craft is only ever the deepening offer")


func test_everyday_buildings_cost_more_for_each_copy() -> void:
	var run := _run()
	run.stock["wood"] = 200
	run.stock["stone"] = 200
	var base: Dictionary = run.content.buildings["forester"]["cost"]
	check_eq(int(run.building_cost("forester")["wood"]), int(base["wood"]), "the first costs its price")
	check(run.world.add_building("forester"), "one stands")
	check_eq(int(run.building_cost("forester")["wood"]), ceili(base["wood"] * 1.5), "the second costs half again")
	check(run.world.add_building("forester"), "two stand")
	check_eq(int(run.building_cost("forester")["wood"]), ceili(base["wood"] * 2.0), "the third twice")
	check(run.world.add_building("tavern"), "a tavern stands")
	check_eq(int(run.building_cost("tavern")["wood"]), int(run.content.buildings["tavern"]["cost"]["wood"]), "a one-of-a-kind building has no copy cost")
	check_eq(run.building_max("tavern"), 1, "and stays one only")


func test_replenishing_upgrades_make_land_regrow() -> void:
	var run := _run()
	check(run.world.tending("stone_yard").is_empty(), "the stone-layers' yard tends nothing at first")
	check(run.world.tending("hunting_lodge").is_empty(), "nor does the hunting lodge")
	check_eq(run.hand.need("stone_yard") == "regrow", false, "so it is never recommended to regrow rocks")
	run.take_upgrade("deep_quarry")
	check(not run.world.tending("stone_yard").is_empty(), "Deep quarry makes the yard tend rocks")
	run.take_upgrade("game_warden")
	check(not run.world.tending("hunting_lodge").is_empty(), "Game warden makes the lodge tend plants")
	var share := float(run.content.buildings["forester"]["tends"]["share"])
	run.take_upgrade("coppicing")
	check_eq(float(run.content.buildings["forester"]["tends"]["share"]), share * 2.0, "Coppicing doubles the forester's regrowth")


func test_deep_quarry_regrows_rocks_by_the_yard() -> void:
	var run := _run()
	run.take_upgrade("deep_quarry")
	var rock: Dictionary = {}
	for node in run.world.nodes:
		if run.content.has_tag("node", node["type"], "stone") and not node.get("heroes_only", false):
			rock = node
			break
	check(not rock.is_empty(), "a rock to tend")
	var before := run.world.node_regrowth(rock)
	run.world.buildings.append({"type": "stone_yard", "plot": -1, "pos": rock["pos"], "work_left": 0.0, "cooldown_left": 0.0,
		"hp": 0.0, "goods": [], "craft": "", "craft_left": 0.0, "craft_tier": 1, "made": 0})
	check(run.world.node_regrowth(rock) > before, "a rock by the yard regrows faster")


func test_practised_crafters_work_twice_as_fast() -> void:
	var run := _run()
	run.take_upgrade("practised_knappers")
	check_eq(float(run.content.buildings["knapper"]["craft_speed"]), 1.0, "the knapper's craft speed is doubled")
