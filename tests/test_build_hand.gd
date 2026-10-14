extends TestCase
## Building cards: each round deals a hand of buildings to order from (sim/build_hand.gd).


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func _types(run: RunState) -> Array:
	return run.hand.cards.map(func(c: Dictionary) -> String: return c["building"])


func test_hand_is_dealt_without_repeats() -> void:
	var run := _run()
	var types := _types(run)
	check_eq(types.size(), run.content.int_num("build_hand_size"), "a full hand is dealt")
	for t: String in types:
		check_eq(types.count(t), 1, "%s is dealt once" % t)
		check(run.hand.eligible(t), "%s could be ordered now" % t)
		check(not run.content.buildings[t].has("ages_up"), "ageing up is never one of the dealt cards")


func test_same_seed_same_hand() -> void:
	check_eq(_types(_run(77)), _types(_run(77)), "the hand only depends on the seed")


func test_only_cards_in_hand_can_be_ordered() -> void:
	var run := _run()
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	var held: String = run.hand.cards[0]["building"]
	var missing := ""
	for t: String in run.content.buildings:
		if run.hand.eligible(t) and not run.hand.offers(t):
			missing = t
			break
	check(missing != "", "some building is not in hand")
	check(not run.hand.order(missing), "a building with no card can't be ordered")
	var wood := int(run.stock["wood"])
	check(run.hand.order(held), "the card's building is ordered")
	check_eq(run.world.count_buildings(held, false), 1, "the building is placed")
	check(int(run.stock["wood"]) < wood, "its cost is paid")
	check(not run.hand.offers(held), "the card is used up")
	check(not run.hand.order(held), "the same card can't be used twice")


func test_housing_need_marks_huts() -> void:
	var run := _run()
	while run.housing() - run.population() > 2:
		run.world.folk_ai.add_folk("tribesperson")
	check_eq(run.hand.need("hut"), "housing", "huts are wanted when beds run short")
	check_eq(run.hand.need("watch_post"), "", "watch posts are not a housing need")


func test_supply_need_marks_the_workshop() -> void:
	var run := _run()
	run.stock["wood"] = 99
	check(run.build("market") and run.build("hide_stall"), "market and armour stall ordered")
	check_eq(run.hand.need("hide_rack"), "supply", "a stall with nothing to sell wants its workshop")


func test_ageing_up_is_its_own_card() -> void:
	var run := _run()
	check(run.hand.milestone.is_empty(), "no age-up card before its needs are met")
	run.stock["wood"] = 99
	check(run.build("market"), "market ordered")
	while run.population() < int(run.content.buildings["bronze_moot"]["min_people"]):
		run.world.folk_ai.add_folk("tribesperson")
	run.hand.deal()
	check_eq(run.hand.milestone.get("building", ""), "bronze_moot", "the moot is offered once it can be raised")
	check(run.hand.offers("bronze_moot"), "the age-up card counts as in hand")


func test_redraw_costs_shells_once_a_round() -> void:
	var run := _run()
	run.stock["shells"] = 100
	check(run.hand.redraw(), "a redraw is allowed")
	check_eq(int(run.stock["shells"]), 100 - run.hand.redraw_cost(), "the redraw is paid in shells")
	check(not run.hand.can_redraw(), "only one redraw a round")
	var record := run.to_record()
	var hands: Array = record["rounds"][-1]["build_hands"]
	check_eq(hands.size(), 2, "the record keeps the first hand and the redrawn one")
	check(record["rounds"][-1]["actions"].any(func(a: Dictionary) -> bool: return a["kind"] == "redraw"), "the redraw is logged")
