extends TestCase
## The pedlar's camp: the player invites one pedlar on pedlar rounds; heroes walk out to trade, some guard it.


func _run(heroes: int) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	while run.living_heroes().size() < heroes:
		run.people.add_hero(run.people.make_hero())
	return run


## Back into the build phase of a pedlar round.
func _pedlar_round(run: RunState) -> void:
	run.round_number = int(run.content.pedlars["every"])
	run._enter_build()


func _open(run: RunState, id: String, distance: float) -> PedlarCamp:
	run.world.pedlar.open({"id": id, "pos": Vector2(distance, 0)})
	return run.world.pedlar


func test_no_pedlar_off_round() -> void:
	var run := _run(2)
	check(run.pedlar_offer.is_empty(), "round 1 offers no pedlar")
	check(not run.awaiting_pedlar(), "nothing to choose")


func test_pedlar_round_offers_a_choice() -> void:
	var run := _run(2)
	_pedlar_round(run)
	check_eq(run.pedlar_offer.size(), int(run.content.pedlars["offer"]), "three pedlars offered")
	check(run.awaiting_pedlar(), "the build phase waits for the choice")
	var id: String = run.pedlar_offer[0]["id"]
	run.choose_pedlar(id)
	check(not run.awaiting_pedlar(), "chosen")
	check_eq(run.pedlar, id, "the invited pedlar")
	run.begin_round()
	check(run.world.pedlar.is_open(), "the pedlar camps from the first dawn")
	check_eq(run.world.pedlar.camp["wares"].size(), int(run.content.pedlars["pedlars"][id]["wares"]), "its wares are laid out")


func test_starting_without_choosing_invites_nobody() -> void:
	var run := _run(2)
	_pedlar_round(run)
	run.begin_round()
	check(not run.world.pedlar.is_open(), "no camp")
	check_eq(run.record.entry["actions"].back()["pedlar"], "", "the record says none was invited")


func test_wares_are_of_the_pedlars_kind() -> void:
	var run := _run(1)
	var camp := _open(run, "armourer", 430)
	for item: Dictionary in camp.camp["wares"]:
		check_eq(Loot.slot(run.content, item), "armor", "the armourer sells armour")
	camp.close()
	camp = _open(run, "charm_seller", 430)
	for item: Dictionary in camp.camp["wares"]:
		check(item["affixes"].size() >= 1, "every charm has a trait")


func test_dutiful_and_greedy_heroes_guard() -> void:
	var run := _run(3)
	var heroes := run.living_heroes()
	heroes[0].trait_id = "brave"
	heroes[1].trait_id = "dutiful"
	heroes[2].trait_id = "greedy"
	var camp := _open(run, "tinker", 290)
	check(not camp.is_guard(heroes[0]), "a brave hero won't stand guard for coin")
	check(camp.is_guard(heroes[1]) and camp.is_guard(heroes[2]), "the dutiful and the greedy take the job")
	check_eq(run.world.hero_ai.bed_pos(heroes[1]), camp.guard_spot(heroes[1]), "a guard sleeps at the camp")


func test_bolder_heroes_walk_further() -> void:
	var run := _run(2)
	var heroes := run.living_heroes()
	heroes[0].trait_id = "greedy"
	heroes[1].trait_id = "dutiful"
	for h in heroes:
		h.spares.append(Loot.make("flint_blade", 1))
	var far := float(run.content.pedlars["camps"]["far"])
	var camp := _open(run, "blade_trader", far)
	camp.camp["guards"] = []
	check(camp.wants_visit(heroes[0], float(run.content.traits["greedy"]["wilds"])), "a greedy hero goes far to trade")
	check(not camp.wants_visit(heroes[1], float(run.content.traits["dutiful"]["wilds"])), "a dutiful one won't go that far")
	var who := camp.who_would_go(Vector2(far, 0))
	check(heroes[0].display_name in who["go"] and heroes[1].display_name not in who["go"], "the card says who would go")


func test_trading_sells_loot_whole_and_buys_an_upgrade() -> void:
	var run := _run(1)
	var hero: Unit = run.living_heroes()[0]
	hero.items = {}
	hero.gold = 0
	hero.spares = [Loot.make("flint_blade", 2)]
	var camp := _open(run, "tinker", 290)
	var cheapest := INF
	for item: Dictionary in camp.camp["wares"]:
		cheapest = minf(cheapest, camp.price(item))
	var value := Loot.value(run.content, Loot.make("flint_blade", 2))
	hero.gold = int(cheapest) * 2
	var before := hero.gold
	var wares: int = camp.camp["wares"].size()
	camp.trade(hero)
	check(hero.spares.is_empty(), "the loot is sold")
	check_eq(camp.camp["record"]["sold_value"], value, "the pedlar pays full value, no cut")
	check_eq(camp.camp["wares"].size(), wares - 1, "the hero buys a ware")
	check_eq(hero.gold, before + value - int(camp.camp["record"]["bought"][0]["price"]), "and pays for it")
	check(not camp.wants_visit(hero, 1.0), "once a day")


func test_guards_are_paid_in_wares_when_it_packs_up() -> void:
	var run := _run(2)
	var heroes := run.living_heroes()
	heroes[0].trait_id = "dutiful"
	heroes[1].trait_id = "cautious"
	var camp := _open(run, "tinker", 290)
	var wares: int = camp.camp["wares"].size()
	camp.pack_up()
	check(not camp.is_open(), "the pedlar has gone")
	check_eq(camp.camp["record"]["paid"].size(), 1, "the one guard is paid")
	check_eq(camp.camp["record"]["left"], wares - 1, "the rest leave with the pedlar")


func test_raiders_can_overrun_the_camp() -> void:
	var run := _run(1)
	var camp := _open(run, "blade_trader", 580)
	var e := run.world.enemy_ai.make_enemy("wolf", camp.camp["pos"] + Vector2(5, 0), 0.0)
	e.spawned = true
	check(camp.draws(e), "a wolf close by goes for the camp")
	camp.camp["hp"] = e.attack
	e.cooldown_left = 0.0
	camp.raid(e)
	check(not camp.is_open(), "it falls")
	check(camp.camp["record"]["fell"], "the record says so")
	check(camp.camp["wares"].is_empty(), "the pedlar flees with the wares")


func test_the_camp_is_gone_by_the_attack() -> void:
	var run := _run(3)
	_pedlar_round(run)
	run.choose_pedlar(run.pedlar_offer[0]["id"])
	run.begin_round()
	while run.phase != RunState.Phase.RELIC and not run.is_over():
		if run.phase == RunState.Phase.PICK:
			run.choose_pick(-1)
		else:
			run.run_until_pause()
		if run.world.is_wave_night():
			check(not run.world.pedlar.is_open(), "the pedlar leaves before the attack")
	check(run.record.entry.has("pedlar"), "the round's record has the camp")


func test_bots_trade_with_pedlars() -> void:
	var rec := bot_record(4821, "balanced")
	var visits := 0
	var invited := 0
	for rd: Dictionary in rec["rounds"]:
		if rd.has("pedlar"):
			invited += 1
			visits += int(rd["pedlar"]["visits"])
	check(invited > 0, "the bot invites pedlars")
	check(visits > 0, "heroes walk out to trade")
