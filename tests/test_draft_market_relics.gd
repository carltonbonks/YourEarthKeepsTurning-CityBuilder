extends TestCase
## Relics for the blueprint draft, rolled cards and the market (Yusuf, 2026-11-20, relic slice 2): roll_odds,
## building_mult on costs, rerolls, extra drafts, ring clearing, crafted gear's tier and traits, stall room, stall
## prices and the town's cut of heroes' sales.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func test_roll_odds_by_card_kind() -> void:
	var run := _run()
	check_eq(run.roll_odds("folk"), 1.0, "no relic, plain odds")
	run._gain_relic("augurs_bones")
	check_eq(run.roll_odds("folk"), 2.0, "townsfolk cards twice as likely")
	check_eq(run.roll_odds("hero"), 2.0, "hero cards too")
	check_eq(run.roll_odds("blueprint"), 1.0, "blueprints untouched")
	var rng := SeededRng.stream(1, "odds")
	var plain := 0
	var lucky := 0
	for i in 4000:
		if CardRoll.roll_rarity(run.content, rng, 14) != "white":
			plain += 1
		if CardRoll.roll_rarity(run.content, rng, 14, run.roll_odds("folk")) != "white":
			lucky += 1
	check(lucky > plain * 1.6, "rolls come rarer (%d vs %d of 4000)" % [lucky, plain])
	run.dispose()


func test_building_mult_scales_a_cost() -> void:
	var run := _run()
	var post: Dictionary = run.building_cost("watch_post")
	var gate: Dictionary = run.building_cost("gate")
	run._gain_relic("wardens_seal")
	for r: String in post:
		check_eq(int(run.building_cost("watch_post")[r]), roundi(int(post[r]) * 0.5), "watch posts half the %s" % r)
	check_eq(int(run.building_cost("gate")["wood"]), roundi(int(gate["wood"]) * 0.5), "gates half")
	check_eq(run.building_cost("hut"), {"wood": 8}, "huts untouched")
	run.dispose()


func test_masons_mark_keeps_copies_at_the_first_price() -> void:
	var run := _run()
	run.world.add_building("knapper")
	var dearer: Dictionary = run.building_cost("knapper")
	run._gain_relic("masons_mark")
	var plain: Dictionary = run.building_cost("knapper")
	check(int(plain["wood"]) < int(dearer["wood"]), "a second knapper is no dearer than the first")
	check_eq(int(plain["wood"]), int(run.content.buildings["knapper"]["cost"]["wood"]), "the first one's price")
	run.dispose()


func test_builders_debt_drafts_more_but_builds_dearer() -> void:
	var run := _run()
	var hut := int(run.building_cost("hut")["wood"])
	run._gain_relic("builders_debt")
	check_eq(int(run.building_cost("hut")["wood"]), ceili(hut * 1.25), "everything costs a quarter more")
	run.round_number = 2
	var before := run.hand.picks
	run.hand.deal()
	check_eq(run.hand.picks - before, run.content.int_num("blueprint_picks") + 1, "one more draft a round")
	run.dispose()


func test_diviners_sticks_rerolls_twice_the_first_free() -> void:
	var run := _run()
	run.choose_traditions([])
	run._gain_relic("diviners_sticks")
	run.stock["shells"] = 100
	run.hand.picks = maxi(1, run.hand.picks)
	run.gentle = false
	check_eq(run.hand.redraw_cost(), 0, "the first reroll is free")
	check(run.hand.redraw(), "first reroll")
	check_eq(int(run.stock["shells"]), 100, "it cost nothing")
	check_eq(run.hand.redraw_cost(), run.content.int_num("build_redraw_cost"), "the second costs shells")
	check(run.hand.redraw(), "second reroll")
	check(not run.hand.can_redraw(), "no third")
	run.dispose()


func test_surveyors_stakes_halve_a_ring() -> void:
	var run := _run()
	var cost := run.ring_cost()
	check(not cost.is_empty(), "a ring is closed at the start")
	run._gain_relic("surveyors_stakes")
	for r: String in cost:
		check_eq(int(run.ring_cost()[r]), ceili(int(cost[r]) * 0.5), "half the %s" % r)
	run.dispose()


func test_crafted_gear_a_tier_better_up_to_the_top() -> void:
	var run := _run()
	var id := ""
	for r: String in run.content.market["recipes"]:
		if run.content.market["recipes"][r].has("item"):
			id = r
			break
	var tier := run.craft_tier(id)
	run._gain_relic("smiths_quench")
	check_eq(run.craft_tier(id), mini(tier + 1, maxi(tier, int(run.content.items["drops"]["max_tier"]))), "a tier better")
	run.round_number = 99
	check(run.craft_tier(id) <= maxi(int(run.content.market["recipes"][id].get("max_tier", 1)), int(run.content.items["drops"]["max_tier"])),
		"never past the best tier")
	run.dispose()


func test_stalls_hold_more_and_heroes_pay_more() -> void:
	var run := _run()
	var room := run.world.market.stall_capacity()
	var id := ""
	for r: String in run.content.market["recipes"]:
		if run.content.market["recipes"][r].has("stall"):
			id = r
			break
	var price := run.price_of({"recipe": id, "tier": 2})
	run._gain_relic("stallkeepers_awning")
	run._gain_relic("hagglers_tongue")
	check_eq(run.world.market.stall_capacity(), room + 2, "two more on each stall")
	check_eq(run.price_of({"recipe": id, "tier": 2}), roundi(price * 1.25), "a quarter dearer")
	run.dispose()


func test_fences_purse_takes_a_bigger_cut() -> void:
	var cuts := []
	for with_purse in [false, true]:
		var run := _run()
		if with_purse:
			run._gain_relic("fences_purse")
		var hero := run.heroes[0]
		hero.spares = [Loot.make(run.content.items["bases"].keys()[0], 2, [])]
		var shells := int(run.stock["shells"])
		run.people.heroes_sell_finds()
		cuts.append(int(run.stock["shells"]) - shells)
		run.dispose()
	check(cuts[1] > cuts[0], "the town's cut grows (%d vs %d)" % [cuts[1], cuts[0]])
