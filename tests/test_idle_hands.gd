extends TestCase
## Idle hands: leaned gatherers get first dibs on their goods, townsfolk with no trip worth taking lend a hand in
## town, warriors keep watch over far gatherers by day, and heroes who don't roam drill on quiet days.


## A run on its first morning with no monsters, no townsfolk and only the given nodes (each {"id", "pos", "amount"}).
func _setup(node_list: Array) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	w.enemies.clear()
	w.nodes.clear()
	w.folk.clear()
	for n: Dictionary in node_list:
		w._add_node(n["id"], n["pos"])
		if n.has("amount"):
			w.nodes[-1]["amount"] = n["amount"]
	return run


func _folk(run: RunState, role: String, leaning := "") -> Unit:
	var u := run.world.folk_ai.add_folk(role, leaning)
	u.pos = Vector2.ZERO
	u.task = ""
	return u


## Raises a building at once and returns its index.
func _standing(run: RunState, type: String) -> int:
	check(run.world.add_building(type), "the %s has a plot" % type)
	run.world.buildings[-1]["work_left"] = 0.0
	return run.world.buildings.size() - 1


func test_leaned_gatherer_takes_over_a_plain_ones_trip() -> void:
	var run := _setup([{"id": "grove", "pos": Vector2(200, 0), "amount": 2}])
	run.stock["wood"] = 0
	var w := run.world
	var plain := _folk(run, "tribesperson")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(plain)
	check_eq(plain.task, "gather", "the plain tribesperson sets off for the last wood")
	var cutter := _folk(run, "tribesperson", "woodcutter")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(cutter)
	check_eq(cutter.task, "gather", "the woodcutter takes the wood anyway")
	check_eq(plain.task, "", "the plain one is bumped and looks for other work")
	check_eq(int(run.record.entry["trips_bumped"].get("wood", 0)), 1, "the bump is recorded")


func test_a_trip_already_gathered_is_not_bumped() -> void:
	var run := _setup([{"id": "grove", "pos": Vector2(200, 0), "amount": 2}])
	run.stock["wood"] = 0
	var w := run.world
	var plain := _folk(run, "tribesperson")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(plain)
	plain.carry_amount = 2
	plain.carrying = "wood"
	var cutter := _folk(run, "tribesperson", "woodcutter")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(cutter)
	check_eq(plain.task, "gather", "a gatherer already carrying keeps its load")


func test_forager_with_nothing_to_fetch_tends_the_garden() -> void:
	var run := _setup([])
	var w := run.world
	var garden := _standing(run, "garden")
	var forager := _folk(run, "tribesperson", "forager")
	var before := run.food_grown_daily()
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(forager)
	check_eq(forager.task, "assist", "the forager lends a hand")
	check_eq(forager.task_index, garden, "at the garden")
	forager.pos = w.buildings[garden]["pos"]
	for i in roundi(10.0 / w.dt) + 2:
		w.folk_ai.begin_step()
		w.folk_ai.folk_tick(forager)
	check_eq(run.food_grown_daily(), before + 1, "ten seconds of tending earns a food at dawn")
	w.buildings[garden]["assisted"] = 999.0
	check_eq(run.food_grown_daily(), before + 2, "no more than the garden's food_max a day")
	check(not w.folk_ai.can_assist(forager, garden), "a fully tended garden takes no more help today")


func test_leaning_decides_where_to_help() -> void:
	var run := _setup([])
	var w := run.world
	_standing(run, "garden")
	var cutter := _folk(run, "tribesperson", "woodcutter")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(cutter)
	check_eq(cutter.task, "idle", "a woodcutter doesn't tend gardens")
	check(w.add_building("hut"), "a hut is being raised")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(cutter)
	check_eq(cutter.task, "build", "but helps raise a hut")
	var plain := _folk(run, "tribesperson")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(plain)
	check_eq(plain.task, "assist", "a tribesperson with no leaning helps anywhere")


func test_helpers_at_a_workshop_speed_its_craft() -> void:
	var run := _setup([])
	var w := run.world
	var knapper := _standing(run, "knapper")
	var shop: Dictionary = w.buildings[knapper]
	var hand := _folk(run, "craftsperson")
	w.folk_ai.begin_step()
	check(not w.folk_ai.can_assist(hand, knapper), "nothing to help with at an empty bench")
	shop["craft"] = "flint_blade"
	shop["craft_left"] = 100.0
	check(w.folk_ai.can_assist(hand, knapper, true), "a craftsperson helps while something is being made")
	check(not w.folk_ai.can_assist(_folk(run, "tribesperson", "forager"), knapper), "a forager doesn't knap")
	check(w.folk_ai.can_assist(_folk(run, "tribesperson", "quarrier"), knapper), "a quarrier does")
	hand.task = "assist"
	hand.task_index = knapper
	hand.task_timer = 5.0
	hand.pos = shop["pos"]
	w.folk_ai.folk_tick(hand)
	check(float(shop["craft_left"]) < 100.0, "the helper's work counts toward the craft")


func test_warriors_keep_watch_over_far_gatherers_by_day() -> void:
	var run := _setup([{"id": "grove", "pos": Vector2(400, 0)}])
	var w := run.world
	var first := _folk(run, "warrior")
	var second := _folk(run, "warrior")
	var gatherer := _folk(run, "tribesperson")
	gatherer.task = "gather"
	gatherer.task_index = 0
	gatherer.pos = Vector2(400, 0)
	w.folk_ai.begin_step()
	w.folk_ai.folk_tick(first)
	w.folk_ai.folk_tick(second)
	check_eq(first.intent, "keeping watch over the gatherers", "the first warrior shadows the gatherer")
	check(first.pos.x > 0.0, "walking its way")
	check_eq(second.intent, "patrolling", "the other half keeps the patrol")
	w.time = w.content.num("day_seconds") - 1.0
	w.folk_ai.begin_step()
	w.folk_ai.folk_tick(first)
	check_eq(first.intent, "patrolling", "at dusk everyone patrols")


func test_heroes_who_stay_home_drill_on_quiet_days() -> void:
	var run := _setup([])
	var w := run.world
	w.dens.clear()
	var hero := run.people.make_hero()
	hero.trait_id = "dutiful"
	run.people.add_hero(hero)
	hero.energy = 100.0
	hero.gold = 0
	var xp := hero.xp
	for i in roundi(20.0 / w.dt):
		w.hero_ai.hero_tick(hero)
	check_eq(hero.intent, "drilling by the hearth", "a dutiful hero drills when nothing is about")
	check(hero.xp > xp, "and gains a little XP")


## A knapper (with the market and its arms stall) that has something to make, plus plenty of every good.
func _busy_knapper(run: RunState) -> int:
	for good: String in run.stock:
		run.stock[good] = 99
	_standing(run, "market")
	_standing(run, "arms_stall")
	var knapper := _standing(run, "knapper")
	check(run.world.market.next_recipe(knapper) != "", "the knapper has something to make")
	return knapper


func test_craftspeople_share_building_and_benches() -> void:
	var run := _setup([])
	var w := run.world
	var knapper := _busy_knapper(run)
	check(w.add_building("hut"), "a hut has a plot")
	var site := w.buildings.size() - 1
	var a := _folk(run, "craftsperson")
	var b := _folk(run, "craftsperson")
	var c := _folk(run, "craftsperson")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(a)
	w.folk_ai._choose_work(b)
	w.folk_ai._choose_work(c)
	check(a.task == "build" and a.task_index == site, "the first goes to raise the hut")
	check(b.task == "craft" and b.task_index == knapper, "the second works the knapper's bench instead of crowding the site")
	check(c.task == "build" and c.task_index == site, "with the bench taken, the third builds too")


func test_a_crafter_stays_at_a_bench_with_more_to_make() -> void:
	var run := _setup([])
	var w := run.world
	var knapper := _busy_knapper(run)
	check(w.add_building("hut"), "a hut has a plot")
	var builder := _folk(run, "craftsperson")
	builder.task = "build"
	builder.task_index = w.buildings.size() - 1
	var u := _folk(run, "craftsperson")
	u.task = "craft"
	u.task_index = knapper
	u.pos = w.buildings[knapper]["pos"]
	w.folk_ai.begin_step()
	w.market.start_craft(knapper)
	w.buildings[knapper]["craft_left"] = 0.0001
	w.folk_ai._worker_tick(u)
	w.folk_ai._choose_work(u)
	check(u.task == "craft" and u.task_index == knapper, "with the hut already being raised, it takes the next make once it finishes one")


func test_a_master_takes_their_own_bench_first() -> void:
	var run := _setup([])
	var w := run.world
	var knapper := _busy_knapper(run)
	var plain := _folk(run, "craftsperson")
	w.folk_ai.begin_step()
	w.folk_ai._choose_work(plain)
	check(plain.task == "craft" and plain.task_index == knapper, "a plain craftsperson works the free bench")
	var master := _folk(run, "craftsperson")
	master.master_of = "knapper"
	w.folk_ai._choose_work(master)
	check(master.task == "craft" and master.task_index == knapper, "the master takes the bench")
	check_eq(plain.task, "", "the plain one is bumped and looks for other work")


func test_craftspeople_fetch_wood_with_no_work_in_town() -> void:
	var run := _setup([{"id": "grove", "pos": Vector2(150, 0), "amount": 20}])
	run.stock["wood"] = 0
	var u := _folk(run, "craftsperson")
	run.world.folk_ai.begin_step()
	run.world.folk_ai._choose_work(u)
	check_eq(u.task, "gather", "with nothing to build or make, it fetches wood")
