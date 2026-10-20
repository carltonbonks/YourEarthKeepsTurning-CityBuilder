extends TestCase
## Heroes eat a hearty meal at dawn when the store can spare it, and earn more XP that day.


func _run_with_hero() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.people.add_hero(run.people.make_hero())
	return run


func test_a_full_store_feeds_heroes_well() -> void:
	var run := _run_with_hero()
	var hero: Unit = run.heroes[0]
	run.stock["food"] = 100
	var need := run.food_needed_today()
	var heroes := run.living_heroes().size()
	run.daily_upkeep()
	check(hero.well_fed, "with plenty in store the hero eats well")
	check_eq(int(run.stock["food"]), 100 + run.food_grown_daily() - need - heroes * run.content.int_num("hearty_food"),
		"and each hero eats one more food")
	check_eq(int(run.record.entry["hearty_meals"]), heroes, "the record counts the meals")


func test_a_thin_store_keeps_its_reserve() -> void:
	var run := _run_with_hero()
	var hero: Unit = run.heroes[0]
	var need := run.food_needed_today()
	run.stock["food"] = need + need * 2 - run.food_grown_daily()
	run.daily_upkeep()
	check(not hero.well_fed, "no hearty meal when it would dip into the town's two days of food")


func test_going_short_feeds_nobody_well() -> void:
	var run := _run_with_hero()
	var hero: Unit = run.heroes[0]
	hero.well_fed = true
	run.stock["food"] = 0
	run.daily_upkeep()
	check(not hero.well_fed, "a hungry dawn leaves nobody well fed")


func test_well_fed_heroes_learn_faster() -> void:
	var run := _run_with_hero()
	var w := run.world
	var hero: Unit = run.heroes[0]
	var wolf := w.enemy_ai.make_enemy("wolf", hero.pos, 0.0)
	w.damage(hero, wolf, 9999.0)
	var plain := hero.xp
	check(plain > 0.0, "a kill earns XP")
	hero.xp = 0.0
	hero.well_fed = true
	w.damage(hero, w.enemy_ai.make_enemy("wolf", hero.pos, 0.0), 9999.0)
	var base := 1.0 + run.mod("xp_mult")
	check(is_equal_approx(hero.xp, plain * (base + run.content.num("hearty_xp")) / base),
		"a well-fed hero earns more XP (%s vs %s)" % [hero.xp, plain])
