extends TestCase
## Runners: with a runners' hut (tag courier) standing, heroes in the wilds who run low on food or poultices send for
## one, and a tribesperson runs it out from the provisions stall for the stall price plus a fee.


## A first morning with no monsters, dens or townsfolk, a market, a provisions stall holding `goods` and (if `hut`)
## a runners' hut, one tribesperson by the hearth and one hero out in the wilds.
func _setup(goods: Array, hut := true) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	w.enemies.clear()
	w.dens.clear()
	w.folk.clear()
	_standing(run, "market")
	var stall := _standing(run, "provisions_stall")
	for recipe: String in goods:
		w.buildings[stall]["goods"].append({"recipe": recipe, "tier": 1})
	if hut:
		_standing(run, "runners_hut")
	var runner := w.folk_ai.add_folk("tribesperson")
	runner.pos = Vector2.ZERO
	runner.task = ""
	for h in run.heroes:
		h.alive = false
	var hero := run.people.make_hero()
	hero.trait_id = "brave"
	run.people.add_hero(hero)
	hero.pos = Vector2(400, 0)
	hero.gold = 30
	hero.pack.clear()
	hero.resting = false
	hero.energy = 100.0
	return run


func _standing(run: RunState, type: String) -> int:
	check(run.world.add_building(type), "the %s has a plot" % type)
	run.world.buildings[-1]["work_left"] = 0.0
	return run.world.buildings.size() - 1


## Steps the townsfolk and heroes without moving the clock (it stays morning unless the test moves it).
func _tick(run: RunState, seconds: float) -> void:
	var w := run.world
	for i in roundi(seconds / w.dt):
		w.folk_ai.begin_step()
		for u in w.folk.duplicate():
			if u.alive:
				w.folk_ai.folk_tick(u)
		for h in run.heroes:
			if h.alive:
				w.hero_ai.hero_tick(h)


func _tired(run: RunState, hero: Unit) -> void:
	hero.energy = float(run.content.traits[hero.trait_id].get("tired_at", 25)) + 5.0


func test_a_runner_brings_food_to_a_tired_hero_who_pays_for_it() -> void:
	var run := _setup(["smoked_meat"])
	var w := run.world
	var hero := run.heroes[-1]
	_tired(run, hero)
	var shells := int(run.stock["shells"])
	_tick(run, 0.2)
	check(w.hero_ai.runner_coming(hero), "a tired hero in the wilds sends for food")
	check_eq(w.folk[0].errand_for, hero, "the tribesperson runs the errand")
	_tick(run, 20.0)
	check_eq(w.supplies_delivered, 1, "the runner reaches the hero")
	var price := w.run.price_of({"recipe": "smoked_meat", "tier": 1})
	var fee := int(run.content.buildings["runners_hut"]["runners"]["fee"])
	check_eq(hero.gold, 30 - price - fee, "the hero pays the stall price and the fee")
	check_eq(int(run.stock["shells"]), shells + price + fee, "into the town's stock")
	check(hero.pack.is_empty(), "and eats it at once")
	check(w.folk[0].errand_for == null, "the runner's errand is done")
	check_eq(w.buildings[w.market.stall_index("provisions")]["goods"].size(), 0, "the food came off the stall")
	check_eq(int(run.record.entry.get("supply_runs", {}).get("smoked_meat", 0)), 1, "the run is recorded")


func test_a_hero_waits_for_the_runner_instead_of_walking_home() -> void:
	var run := _setup(["smoked_meat"])
	var hero := run.heroes[-1]
	hero.energy = float(run.content.traits[hero.trait_id].get("tired_at", 25)) - 1.0
	_tick(run, 0.5)
	check(run.world.hero_ai.runner_coming(hero), "a runner is on the way")
	check(hero.intent.begins_with("waiting for a runner"), "the hero holds where they are (%s)" % hero.intent)
	check(not hero.resting, "rather than heading to bed")


func test_a_wounded_hero_falling_back_is_patched_up_and_turns_back() -> void:
	var run := _setup(["poultice"])
	var hero := run.heroes[-1]
	hero.energy = 100.0
	var retreat_at := float(run.content.traits[hero.trait_id]["retreat_at"])
	hero.hp = hero.max_hp * (retreat_at + 0.05)
	_tick(run, 0.2)
	check_eq(hero.supply_call, "heal", "a hurt hero sends for a poultice")
	hero.hp = hero.max_hp * (retreat_at - 0.05)
	_tick(run, 25.0)
	check_eq(run.world.supplies_delivered, 1, "the runner catches up with them")
	check(hero.hp_fraction() > retreat_at, "the poultice heals them")


func test_no_hut_no_runners() -> void:
	var run := _setup(["smoked_meat"], false)
	var hero := run.heroes[-1]
	_tired(run, hero)
	_tick(run, 1.0)
	check_eq(hero.supply_call, "", "without a runners' hut nobody sends for supplies")
	check(run.world.folk[0].errand_for == null, "and nobody runs")


func test_a_hero_who_cannot_pay_sends_for_nothing() -> void:
	var run := _setup(["smoked_meat"])
	var hero := run.heroes[-1]
	hero.gold = 2
	_tired(run, hero)
	_tick(run, 1.0)
	check_eq(hero.supply_call, "", "the fee and price are more than they have")


func test_a_hero_with_food_in_the_pack_needs_no_runner() -> void:
	var run := _setup(["smoked_meat"])
	var hero := run.heroes[-1]
	hero.pack.append("smoked_meat")
	hero.energy = 100.0
	_tick(run, 0.2)
	check_eq(hero.supply_call, "", "a hero still carrying food sends for nothing")


func test_runners_turn_back_at_dusk_and_return_the_goods() -> void:
	var run := _setup(["smoked_meat"])
	var w := run.world
	var hero := run.heroes[-1]
	hero.pos = Vector2(600, 0)
	_tired(run, hero)
	_tick(run, 4.0)
	var runner := w.folk[0]
	check(not runner.parcel.is_empty(), "the runner has the food from the stall")
	w.time = run.content.num("day_seconds") - run.content.num("dusk_seconds") + 0.5
	_tick(run, 0.2)
	check(runner.errand_for == null, "at dusk the runner gives up")
	check(hero.runner == null, "and the hero knows it")
	check_eq(w.buildings[w.market.stall_index("provisions")]["goods"].size(), 1, "the food goes back on the stall")
	check_eq(w.supplies_delivered, 0, "nothing was delivered")


func test_only_tribespeople_in_town_run() -> void:
	var run := _setup(["smoked_meat"])
	var w := run.world
	w.folk[0].pos = Vector2(500, 0)
	var hero := run.heroes[-1]
	_tired(run, hero)
	_tick(run, 0.2)
	check(not w.hero_ai.runner_coming(hero), "a tribesperson out in the wilds is not sent")
