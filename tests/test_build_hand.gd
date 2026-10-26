extends TestCase
## Blueprints: each round offers buildings to draft, kept for the whole run (sim/build_hand.gd).


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func _types(run: RunState) -> Array:
	return run.hand.cards.map(func(c: Dictionary) -> String: return c["building"])


func test_offers_are_dealt_without_repeats() -> void:
	var run := _run()
	var types := _types(run)
	check_eq(types.size() + run.hand.crafts.size() + run.hand.upgrade_offers.size(), run.content.int_num("blueprint_offers"), "a full draft is offered")
	for t: String in types:
		check_eq(types.count(t), 1, "%s is offered once" % t)
		check(run.hand.draftable(t), "%s could be drafted now" % t)
		check(not run.content.buildings[t].has("ages_up"), "ageing up is never drafted")
	check_eq(run.hand.picks, run.content.int_num("blueprint_first_picks"), "the first round brings its drafts")


func test_same_seed_same_hand() -> void:
	check_eq(_types(_run(77)), _types(_run(77)), "the offers only depend on the seed")


func test_a_drafted_building_stays_on_offer() -> void:
	var run := _run()
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	var held: String = run.hand.cards[0]["building"]
	check(not run.hand.order(held), "an offer can't be ordered before it is drafted")
	var picks := run.hand.picks
	check(run.hand.draft(held), "drafted")
	check_eq(run.hand.picks, picks - 1, "a draft is used")
	check(not _types(run).has(held), "a blueprint is not offered again")
	var wood := int(run.stock["wood"])
	check(run.hand.order(held), "the blueprint's building is ordered")
	check_eq(run.world.count_buildings(held, false), 1, "the building is placed")
	check(int(run.stock["wood"]) < wood, "its cost is paid")
	check(run.hand.offers(held), "and it stays on offer")
	check(run.to_record()["rounds"][-1]["blueprints"].any(func(b: Dictionary) -> bool: return b["building"] == held), "the record keeps it")


func test_drafts_run_out_and_come_back_next_round() -> void:
	var run := _run()
	while run.hand.picks > 0:
		check(run.hand.draft(run.hand.cards[0]["building"]), "drafted")
	check(run.hand.cards.is_empty(), "no offers once the drafts are used")
	check(not run.hand.can_redraw(), "nothing to reroll")
	run.round_number += 1
	run.hand.deal()
	check_eq(run.hand.picks, run.content.int_num("blueprint_picks"), "a new round brings a draft")
	check(not run.hand.cards.is_empty(), "and fresh offers")


func test_a_new_age_brings_an_extra_draft() -> void:
	var run := _run()
	run.hand.picks = 0
	run.round_number += 1
	run.age = "bronze"
	run.hand.deal()
	check_eq(run.hand.picks, run.content.int_num("blueprint_picks") + run.content.int_num("blueprint_age_picks"), "an extra draft")


func test_the_age_up_need_is_always_offered() -> void:
	for s in [1, 2, 3, 4, 5]:
		var run := _run(s)
		run.round_number = 2
		run.hand.deal()
		check(run.hand.crafts.any(func(c: Dictionary) -> bool: return run.hand.craft_adds(c["craft"]).has("market")),
			"the market, which the moot needs, is offered with a craft (seed %d)" % s)
		check_eq(run.hand.need("market"), "ageing", "and marked as needed to age up")


func test_no_lodging_marks_lodgings() -> void:
	var run := _run()
	check_eq(run.hand.need("tavern"), "heroes", "no lodging yet wants one")
	run.hand.blueprints.append("longhouse")
	check(run.hand.need("tavern") != "heroes", "a drafted lodging is enough")


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


func test_reroll_costs_shells_once_a_round() -> void:
	var run := _run()
	run.stock["shells"] = 100
	check(run.hand.redraw(), "a reroll is allowed")
	check_eq(int(run.stock["shells"]), 100 - run.hand.redraw_cost(), "the reroll is paid in shells")
	check(not run.hand.can_redraw(), "only one reroll a round")
	var record := run.to_record()
	var hands: Array = record["rounds"][-1]["build_hands"]
	check_eq(hands.size(), 2, "the record keeps the first offers and the rerolled ones")
	check(record["rounds"][-1]["actions"].any(func(a: Dictionary) -> bool: return a["kind"] == "redraw"), "the redraw is logged")


func test_basics_are_always_on_offer() -> void:
	var run := _run()
	run.stock["wood"] = 99
	check(run.hand.basics().has("hut"), "huts are always on offer")
	check(not _types(run).has("hut"), "huts are never offered as a draft")
	check(run.hand.order("hut") and run.hand.order("hut"), "two huts can be ordered in one round")
	check_eq(run.world.count_buildings("hut", false), 2, "both huts are placed")


func test_the_bot_drafts_what_it_wanted() -> void:
	var run := _run()
	run.choose_traditions([])
	run.round_number = 2
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	run.hand.deal()
	AutoPlayer.new().build(run)
	check_eq(run.hand.picks, 0, "the bot uses its drafts")
	check(run.hand.blueprints.size() >= 2, "and keeps what it drafted (%s)" % [run.hand.blueprints])
