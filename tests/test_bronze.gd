extends TestCase
## Slice 5: the bronze age, tool sets, the caravan, bronze reavers, promotions and hero mood.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


## Orders a building and finishes it on the spot.
func _raise(run: RunState, type: String) -> int:
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	run.stock["shells"] = maxi(int(run.stock["shells"]), 99)
	check(run.build(type), "can order a %s" % type)
	var i := run.world.buildings.size() - 1
	run.world.buildings[i]["work_left"] = 0.0
	run.on_building_done(type)
	return i


func _crowd(run: RunState, n: int) -> void:
	run.stock["wood"] = 99
	for i in 6:
		run.build("hut")
	for b in run.world.buildings:
		b["work_left"] = 0.0
	while run.population() < n:
		run.world.add_folk("tribesperson")


func _age_up(run: RunState) -> void:
	_crowd(run, 12)
	_raise(run, "market")
	_raise(run, "bronze_moot")


## Starts the first day with no dawn newcomer and no monsters around.
func _start_day(run: RunState) -> void:
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	run.world.dens.clear()


func _advance(run: RunState, seconds: float) -> void:
	for i in int(seconds / run.world.dt):
		run.step()


func test_bronze_buildings_wait_for_the_moot() -> void:
	var run := _run()
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	run.stock["shells"] = 99
	check(not run.can_build("smelter"), "no smelter in the stone age")
	run.build("market")
	check(not run.can_build("bronze_moot"), "the moot needs 12 people")
	_crowd(run, 12)
	check(run.can_build("bronze_moot"), "with a market and 12 people the moot can be ordered")
	check_eq(run.age, "neolithic", "still the stone age while the moot is unbuilt")
	_raise(run, "bronze_moot")
	check_eq(run.age, "bronze", "raising the moot brings the bronze age")
	check(run.can_build("smelter"), "the smelter can be ordered in the bronze age")
	check(not run.can_build("bronze_moot"), "only one moot")
	check_eq(int(run.to_record()["age_up_round"]), 1, "the age-up round is recorded")


func test_copper_seams_only_count_in_the_bronze_age() -> void:
	var run := _run()
	var seams := run.world.nodes.filter(func(n: Dictionary) -> bool: return n["gives"] == "copper")
	check(not seams.is_empty(), "copper seams are on the map")
	check(not run.world.node_active(seams[0]), "copper seams are dormant in the stone age")
	var cass := run.world.nodes.filter(func(n: Dictionary) -> bool: return n["gives"] == "cassiterite")
	check_eq(cass.size(), run.world.dens.size(), "one cassiterite vein per den")
	for n: Dictionary in cass:
		var near := run.world.dens.any(func(d: Dictionary) -> bool: return n["pos"].distance_to(d["pos"]) < 200.0)
		check(near, "cassiterite sits near a den")
	_age_up(run)
	check(run.world.node_active(seams[0]), "copper seams open in the bronze age")


func test_new_nodes_leave_the_stone_age_map_alone() -> void:
	# Stone-age nodes come from the world stream as before; later ages use their own streams.
	var run := _run(1234)
	var stone := run.world.nodes.filter(func(n: Dictionary) -> bool: return n["age"] == "")
	check(stone.size() > 0, "stone-age nodes exist")
	var again := _run(1234).world.nodes.filter(func(n: Dictionary) -> bool: return n["age"] == "")
	for i in stone.size():
		check(stone[i]["pos"].is_equal_approx(again[i]["pos"]), "same seed, same map")


func test_townsfolk_skip_cassiterite_until_the_den_is_quiet() -> void:
	var run := _run()
	_age_up(run)
	var vein := -1
	for i in run.world.nodes.size():
		if run.world.nodes[i]["gives"] == "cassiterite":
			if vein >= 0:
				run.world.nodes[vein]["amount"] = 0  # Only one vein in play for this test.
			vein = i
	var node: Dictionary = run.world.nodes[vein]
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	var wolf := run.world._make_enemy("wolf", node["pos"] + Vector2(40, 0), 0.0)
	wolf.den_index = 0
	run.world.enemies.append(wolf)
	check(not run.world.node_safe(node), "a wolf by the vein makes it unsafe")
	var u := run.world.folk[0]
	check_eq(run.world._nearest_node(u, "cassiterite"), -1, "a tribesperson won't go while the wolf prowls")
	wolf.alive = false
	run.world.enemies.clear()
	check(run.world.node_safe(node), "with the den's wanderers dead the vein is safe")
	check_eq(run.world._nearest_node(u, "cassiterite"), vein, "now townsfolk can fetch cassiterite")


func test_heroes_fetch_cassiterite_once_a_smelter_stands() -> void:
	var run := _run()
	_age_up(run)
	var hero := run.heroes[0]
	var vein := -1
	for i in run.world.nodes.size():
		if run.world.nodes[i]["gives"] == "cassiterite":
			vein = i
	hero.pos = run.world.nodes[vein]["pos"] + Vector2(30, 0)
	check_eq(run.world._outcrop_for(hero), -1, "no smelter: nobody buys cassiterite")
	_raise(run, "smelter")
	check_eq(run.world._outcrop_for(hero), vein, "with a smelter heroes fetch it")
	run.world._take_shards(hero, vein)
	var shells_before := int(run.stock["shells"])
	run.world._sell_shards(hero)
	check(int(run.stock["cassiterite"]) > 0, "the town gets the cassiterite")
	check(int(run.stock["shells"]) < shells_before, "and pays the hero for it")


func test_smelter_makes_tin_then_bronze() -> void:
	var run := _run()
	_age_up(run)
	var smelter := _raise(run, "smelter")
	run.stock["cassiterite"] = 4
	run.stock["copper"] = 4
	run.stock["fuel"] = 50
	run.stock["food"] = 50
	var u := run.world.add_folk("craftsperson")
	_start_day(run)
	_advance(run, 30.0)
	check(int(run.world.buildings[smelter]["made"]) >= 2, "the smelter has worked")
	check(int(run.stock["bronze"]) > 0, "cassiterite became tin and tin became bronze")
	check(int(u.made.get("smelter", 0)) > 0 or run.world.folk.any(func(f: Unit) -> bool: return int(f.made.get("smelter", 0)) > 0),
		"the craftsperson's work is counted")


func test_tool_sets_cost_bronze_and_upgrade_a_group() -> void:
	var run := _run()
	check(not run.can_buy_tools("bronze_spears"), "no tool sets in the stone age")
	_age_up(run)
	var warrior: Unit = run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior")[0]
	var attack := warrior.attack
	check(not run.can_buy_tools("bronze_spears"), "no bronze, no spears")
	run.stock["bronze"] = 10
	check(run.buy_tools("bronze_spears"), "spears bought")
	check(warrior.attack > attack, "warriors hit harder")
	check(run.has_metal_tools("warrior"), "warriors now strike with metal")
	check_eq(int(run.stock["bronze"]), 6, "the ingots are spent")
	check(not run.buy_tools("bronze_spears"), "each set only once")
	var plain := run.world.work_rate(run.world.add_folk("craftsperson"))
	run.buy_tools("bronze_chisels")
	check(run.world.work_rate(run.world.folk.back()) > plain, "chisels speed up craftspeople")


func test_caravan_sells_tin_at_a_markup() -> void:
	var run := _run()
	check(run.trader_stock.is_empty(), "no caravan in the stone age")
	_age_up(run)
	run.begin_round()
	while not run.is_over() and run.phase != RunState.Phase.BUILD:
		match run.phase:
			RunState.Phase.PICK:
				run.choose_pick(-1)
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic("")
	if run.is_over():
		return
	check(run.trader_stock.has("tin") and run.trader_stock.has("cassiterite"), "the caravan brings tin and a little cassiterite")
	check(int(run.trader_stock["cassiterite"]) < int(run.trader_stock["tin"]), "only a little raw ore: it is heavy")
	run.stock["shells"] = 100
	check(run.trade("tin"), "tin bought")
	check_eq(int(run.stock["tin"]), 1, "tin arrives")
	check_eq(int(run.stock["shells"]), 100 - run.trader_price("tin"), "at the caravan's price")
	var local := int(run.content.world["nodes"]["cassiterite"]["price"])
	check(run.trader_price("cassiterite") > local * 2, "the caravan charges far more than heroes do")


func test_bronze_shields_turn_stone_but_not_metal() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	var reaver := run.world._make_enemy("bronze_reaver", Vector2(100, 0), 0.0)
	run.world.enemies.append(reaver)
	var hero := run.heroes[0]
	hero.items = {"weapon": Loot.make("flint_blade", 2)}
	run.world.apply_hero_stats(hero)
	hero.energy = 100.0
	var hp := reaver.hp
	run.world._hit(hero, reaver)
	var stone_hit := hp - reaver.hp
	hero.items = {"weapon": Loot.make("bronze_sword", 2)}
	run.world.apply_hero_stats(hero)
	hp = reaver.hp
	run.world._hit(hero, reaver)
	var bronze_hit := hp - reaver.hp
	check(stone_hit < hero.attack * 1.15 * 0.61, "the shield soaks part of a stone blow")
	check(bronze_hit > hero.attack * 0.84, "a bronze blade cuts through")


func test_reavers_join_waves_from_round_6() -> void:
	var run := _run()
	check(not run.generate_wave(5).has("bronze_reaver"), "no reavers before round 6")
	var seen := false
	for r in range(6, 11):
		seen = seen or run.generate_wave(r).has("bronze_reaver")
	check(seen, "reavers turn up in later waves")


func test_bronze_gear_never_drops_in_the_stone_age() -> void:
	var c := Content.load_default()
	var rng := SeededRng.new(5)
	for i in 300:
		var item := Loot.roll(c, rng, 10, "neolithic")
		check(not c.items["bases"][item["base"]].has("age"), "stone-age drops only")
		if c.items["bases"][item["base"]].has("age"):
			return


func test_veteran_warrior_can_be_promoted_to_a_hero() -> void:
	var run := _run()
	_raise(run, "longhouse")
	var warrior: Unit = run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior")[0]
	warrior.kills = 6
	run.stock["shells"] = 100
	var heroes := run.heroes.size()
	run.begin_round()
	var card := -1
	for i in run.pick_offer.size():
		if run.pick_offer[i]["kind"] == "promote":
			card = i
	check(card >= 0, "a Promote card is offered at dawn")
	check_eq(run.pick_offer.size(), run.content.int_num("pick_choices"), "it takes one of the usual slots")
	var hero: Unit = run.pick_offer[card]["hero"]
	run.choose_pick(card)
	check_eq(run.heroes.size(), heroes + 1, "the warrior is now a hero")
	check(not run.world.folk.has(warrior), "and has left the warriors")
	check_eq(hero.kills, 6, "their kills come with them")
	check_eq(hero.level, int(run.content.promotions["warrior"]["start_level"]), "a veteran starts above level 1")
	check_eq(int(run.stock["shells"]), 100 - int(run.content.promotions["warrior"]["cost"]), "promotion costs shells")
	var promos: Array = run.to_record()["rounds"][0]["promotions"]
	check_eq(promos.size(), 1, "the promotion is recorded")


func test_no_warrior_promotion_without_a_lodging() -> void:
	var run := _run()
	var warrior: Unit = run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior")[0]
	warrior.kills = 20
	run.begin_round()
	check(not run.pick_offer.any(func(c: Dictionary) -> bool: return c["kind"] == "promote"), "a hero needs somewhere to sleep")


func test_skilled_craftsperson_becomes_a_master() -> void:
	var run := _run()
	_raise(run, "market")
	_raise(run, "arms_stall")
	var knapper := _raise(run, "knapper")
	var u := run.world.add_folk("craftsperson")
	u.made["knapper"] = 8
	run.stock["shells"] = 100
	run.begin_round()
	var card := -1
	for i in run.pick_offer.size():
		if run.pick_offer[i]["kind"] == "promote":
			card = i
	check(card >= 0, "a Promote card is offered for the craftsperson")
	run.choose_pick(card)
	check_eq(u.master_of, "knapper", "now master of the knapper")
	check(u.craft_trait != "" and u.display_name != "Craftsperson", "with a name and a craft trait")
	check(run.world._workshop_needing_hands(u) == knapper or run.world._next_recipe(knapper) == "", "a master goes to their own bench")


func test_master_trait_shapes_their_goods() -> void:
	var run := _run()
	_raise(run, "market")
	var stall := _raise(run, "arms_stall")
	var knapper := _raise(run, "knapper")
	var u := run.world.add_folk("craftsperson")
	u.master_of = "knapper"
	u.craft_trait = "gifted"
	run.stock["flint"] = 10
	run.world._start_craft(knapper)
	var base_tier := int(run.world.buildings[knapper]["craft_tier"])
	run.world._finish_craft(knapper, u)
	var good: Dictionary = run.world.buildings[stall]["goods"][0]
	check_eq(int(good["tier"]), base_tier + 1, "a gifted master's gear is a tier better")


func test_heroes_sleeping_rough_grow_unhappy_and_leave() -> void:
	var run := _run()
	_raise(run, "shrine")
	# Fill every bed with other heroes so one is left by the fire.
	while not run.heroes.any(func(h: Unit) -> bool: return h.lodging < 0):
		run._add_hero(run._make_hero())
	var rough: Array = run.heroes.filter(func(h: Unit) -> bool: return h.lodging < 0)
	check(not rough.is_empty(), "someone sleeps rough")
	var hero: Unit = rough[0]
	hero.mood = run.content.num("mood_leave_at") + 3.0
	hero.slept = "rough"
	run._update_moods()
	check(not run.heroes.has(hero), "an unhappy hero leaves")
	check(run.departed.has(hero), "and is remembered as departed")
	check(run.world.night_report["heroes_left"].has(hero.display_name), "the dawn report names them")


func test_happy_heroes_stay_and_mood_rises() -> void:
	var run := _run()
	var hero := run.heroes[0]
	var before := hero.mood
	hero.slept = "favourite"
	hero.mood_events = {"bought": 1}
	run._update_moods()
	check(hero.mood > before, "a good night and a purchase lift mood")
	check(run.heroes.has(hero), "a happy hero stays")
	check(hero.mood_events.is_empty() and hero.slept == "", "the day's events are used up")


func test_no_rough_sleep_penalty_before_any_lodging() -> void:
	# At the campfire start everyone sleeps by the hearth; that is no slight.
	var run := _run()
	run.begin_round()
	for i in 3:
		if run.phase == RunState.Phase.PICK:
			run.choose_pick(-1)
		run.run_until_pause()
	for hero in run.living_heroes():
		check(hero.mood >= run.content.num("mood_start") - 30.0, "%s keeps their spirits by the fire" % hero.display_name)


func test_bronze_bot_records_format_7() -> void:
	var run := _run(1003)
	var bot := AutoPlayer.new()
	bot.style = "bronze"
	bot.play_run(run)
	var record := run.to_record()
	check_eq(int(record["format"]), 7, "record format 7")
	for key in ["age", "age_up_round", "tools", "departed"]:
		check(record.has(key), "record has %s" % key)
	for rd: Dictionary in record["rounds"]:
		for key in ["promotions", "trades", "cassiterite", "heroes_left"]:
			check(rd.has(key), "round %d has %s" % [rd["round"], key])
	for h: Dictionary in record["heroes"]:
		check(h.has("mood"), "hero snapshot has mood")
	run.dispose()
