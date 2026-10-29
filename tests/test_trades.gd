extends TestCase
## The southern caravan's trade cards (sim/caravan.gd, data/trades.json): deals drawn by rarity once the
## Bronze moot stands, each taken once a round for its goods, people, a smith's work or a relic.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	return run


## Raises the market and the moot on the spot, with room for newcomers, and lays out the round's deals.
func _bronze(run: RunState) -> void:
	run.stock["wood"] = 999
	run.stock["stone"] = 999
	run.stock["shells"] = 999
	for i in 8:
		run.build("hut")
	for b in run.world.buildings:
		b["work_left"] = 0.0
	for i in maxi(0, 12 - run.population()):
		run.world.folk_ai.add_folk("tribesperson")
	for type in ["market", "bronze_moot"]:
		check(run.build(type), "can order a %s" % type)
		run.world.buildings.back()["work_left"] = 0.0
		run.on_building_done(type)
	run.caravan.lay_out()


## Puts one known deal on offer and returns its index.
func _offer(run: RunState, id: String) -> int:
	run.caravan.offers.append({"deal": id, "need": run.caravan.need(id), "taken": false})
	return run.caravan.offers.size() - 1


func test_no_deals_before_the_moot() -> void:
	var run := _run()
	run.caravan.lay_out()
	check(run.caravan.offers.is_empty(), "no caravan in the stone age")


func test_the_caravan_lays_out_deals_of_its_age() -> void:
	var run := _run()
	_bronze(run)
	check_eq(run.age, "bronze", "the moot brings the bronze age")
	check_eq(run.caravan.offers.size(), int(run.content.trades["offers"]), "a few deals each round")
	var seen := {}
	for o: Dictionary in run.caravan.offers:
		check(not seen.has(o["deal"]), "no deal twice in one round")
		seen[o["deal"]] = true
		check(run.content.age_reached(run.age, run.caravan.deal(o["deal"]).get("age", "")), "%s belongs to the age" % o["deal"])


func test_rarer_deals_come_up_less_often() -> void:
	var counts := {"white": 0, "orange": 0}
	var run := _run()
	_bronze(run)
	for r in 60:
		run.round_number = r + 1
		run.caravan.lay_out()
		for o: Dictionary in run.caravan.offers:
			var rarity := run.content.rarity_of("deal", o["deal"])
			if counts.has(rarity):
				counts[rarity] += 1
	check(counts["white"] > counts["orange"] * 2, "white deals far outnumber mythic ones (%s)" % str(counts))
	check(counts["orange"] > 0, "but mythic deals do come up")


func test_a_deal_pays_and_brings_once() -> void:
	var run := _run()
	_bronze(run)
	run.round_number = 1
	var i := _offer(run, "tin_bundle")
	var shells := int(run.stock["shells"])
	var tin := int(run.stock["tin"])
	check(run.caravan.take(i), "tin bought")
	check_eq(int(run.stock["shells"]), shells - 30, "paid in shells")
	check_eq(int(run.stock["tin"]), tin + 4, "the bundle arrives")
	check(not run.caravan.take(i), "each deal only once a round")
	check_eq(run.caravan.blocker(i), "Taken", "the card says so")
	check_eq(int(run.record.entry["trades"]["tin"]), 4, "the round counts the tin bought")
	check_eq(run.record.entry["deals"][0]["deal"], "tin_bundle", "and the deal taken")


func test_deals_grow_a_little_each_round() -> void:
	var run := _run()
	_bronze(run)
	run.round_number = 1
	var early := int(run.caravan.gets("timber_load")["wood"])
	run.round_number = 11
	check(int(run.caravan.gets("timber_load")["wood"]) > early, "later rounds bring bigger lots")


func test_a_barter_needs_its_goods_and_the_scales_sweeten_it() -> void:
	var run := _run()
	_bronze(run)
	run.round_number = 1
	run.stock["hides"] = 2
	var i := _offer(run, "tin_for_furs")
	check(not run.caravan.can_take(i), "no barter without the hides")
	run.stock["hides"] = 20
	check(run.caravan.need("tin_for_furs") != "", "held twice over, the town wants to barter them")
	var plain := int(run.caravan.gets("tin_for_furs")["tin"])
	run.relics.append("hagglers_scales")
	check(int(run.caravan.gets("tin_for_furs")["tin"]) > plain, "Haggler's scales: barters bring more")
	check_eq(int(run.caravan.gets("tin_bundle")["tin"]), 4, "but not bulk buys")
	check(run.caravan.take(i), "bartered")
	check_eq(int(run.stock["hides"]), 14, "the hides go south")


func test_people_need_room() -> void:
	var run := _run()
	_bronze(run)
	var i := _offer(run, "sellswords")
	for n in maxi(0, run.housing() - run.population()):
		run.world.folk_ai.add_folk("tribesperson")
	check(not run.caravan.can_take(i), "no room for the sellswords")
	check(run.caravan.blocker(i).begins_with("No room"), "the card says why")
	run.world.folk.pop_back()
	run.world.folk.pop_back()
	var warriors := run.count_role("warrior")
	check(run.caravan.take(i), "hired")
	check_eq(run.count_role("warrior"), warriors + 2, "two warriors join")


func test_the_smith_raises_every_heros_weapon() -> void:
	var run := _run()
	_bronze(run)
	var hero: Unit = run.living_heroes()[0]
	hero.items["weapon"] = Loot.make("flint_blade", 1)
	run.world.hero_ai.apply_hero_stats(hero)
	var attack := hero.attack
	check(run.caravan.take(_offer(run, "travelling_smith")), "the smith works")
	check_eq(int(hero.items["weapon"]["tier"]), 2, "one tier better")
	check(hero.attack > attack, "and hits harder")


func test_the_relic_dealer_sells_a_relic() -> void:
	var run := _run()
	_bronze(run)
	var before := run.relics.size()
	check(run.caravan.take(_offer(run, "relic_dealer")), "bought")
	check_eq(run.relics.size(), before + 1, "a relic is gained")
	check(not run.content.has_tag("relic", run.relics.back(), "pact"), "an ordinary relic, never a pact")


func test_traders_and_the_seal_lay_out_more() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions(["traders", "hunters"])
	_bronze(run)
	var base := int(run.content.trades["offers"])
	check_eq(run.caravan.offers.size(), base + 1, "Traders: one more deal")
	run.relics.append("caravan_seal")
	run.caravan.lay_out()
	check_eq(run.caravan.offers.size(), base + 2, "the Caravan seal adds another")


func test_medieval_deals_wait_for_the_age() -> void:
	var run := _run()
	_bronze(run)
	for r in 30:
		run.round_number = r + 1
		run.caravan.lay_out()
		for o: Dictionary in run.caravan.offers:
			check(not o["deal"] in ["iron_bars", "steel_billets"], "no iron or steel in the bronze age")


func test_metal_is_wanted_while_tools_are_unbought() -> void:
	var run := _run()
	_bronze(run)
	run.stock["bronze"] = 0
	check(run.caravan.need("bronze_ingots") != "", "ingots wanted while a bronze tool set is unbought")
	run.tools.assign(["bronze_picks", "bronze_chisels", "bronze_spears"])
	check_eq(run.caravan.need("bronze_ingots"), "", "not once every set is bought")
