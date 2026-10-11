extends TestCase
## Slice 4: workshops, stalls, heroes shopping, beast yields, prizes, provisions and obsidian.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


## Orders a building and finishes it on the spot.
func _raise(run: RunState, type: String) -> int:
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	check(run.build(type), "can order a %s" % type)
	var i := run.world.buildings.size() - 1
	run.world.buildings[i]["work_left"] = 0.0
	run.on_building_done(type)
	return i


## Starts the first day with no dawn newcomer and no monsters around.
func _start_day(run: RunState) -> void:
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	run.world.dens.clear()


func _advance(run: RunState, seconds: float) -> void:
	for i in int(seconds / run.world.dt):
		run.step()


## Puts a good straight onto a stall.
func _stock_stall(run: RunState, stall: int, recipe: String, tier := 1) -> void:
	var good := {"recipe": recipe, "tier": tier}
	var r: Dictionary = run.content.market["recipes"][recipe]
	if r.has("item"):
		good["item"] = Loot.make(r["item"], tier)
	run.world.buildings[stall]["goods"].append(good)


func test_stalls_need_a_market() -> void:
	var run := _run()
	run.stock["wood"] = 99
	check(not run.can_build("arms_stall"), "no stall before a market square")
	check(run.build("market"), "market ordered")
	check(run.can_build("arms_stall"), "a stall can follow once the market is ordered")


func test_workshop_makes_goods_for_its_stall() -> void:
	var run := _run()
	_raise(run, "market")
	var stall := _raise(run, "arms_stall")
	_raise(run, "knapper")
	run.world.folk_ai.add_folk("craftsperson")
	run.stock["flint"] = 10
	run.stock["bone"] = 10
	run.stock["wood"] = 20
	_start_day(run)
	_advance(run, 25.0)
	var goods: Array = run.world.buildings[stall]["goods"]
	check(goods.size() > 0, "the knapper's work lands on the arms stall")
	check(int(run.stock["flint"]) < 10 or int(run.stock["bone"]) < 10, "crafting uses up raw goods")
	for g: Dictionary in goods:
		check(g.has("item") and Loot.slot(run.content, g["item"]) == "weapon", "the arms stall holds weapons")
	var crafted: Dictionary = run.to_record()["rounds"][0]["crafted"]
	check(not crafted.is_empty(), "crafting is recorded")


func test_workshop_idles_without_its_stall_or_goods() -> void:
	var run := _run()
	var knapper := _raise(run, "knapper")
	run.stock["flint"] = 10
	check_eq(run.world.market.next_recipe(knapper), "", "no arms stall: nothing to make")
	_raise(run, "market")
	_raise(run, "arms_stall")
	run.stock["flint"] = 0
	run.stock["bone"] = 0
	run.stock["obsidian"] = 0
	check_eq(run.world.market.next_recipe(knapper), "", "no flint or bone: nothing to make")
	run.stock["flint"] = 2
	run.stock["wood"] = 1
	check_eq(run.world.market.next_recipe(knapper), "flint_blade", "flint and wood make a blade")


func test_heroes_buy_gear_they_like_and_pay_the_town() -> void:
	var run := _run()
	_raise(run, "market")
	var stall := _raise(run, "arms_stall")
	_stock_stall(run, stall, "flint_blade")
	_start_day(run)
	var hero := run.heroes[0]
	hero.trait_id = "brave"
	hero.gold = 50
	hero.items.erase("weapon")
	hero.pos = Vector2(40, 0)
	var shells: int = run.stock["shells"]
	var price := run.price_of(run.world.buildings[stall]["goods"][0])
	_advance(run, 8.0)
	check(hero.items.has("weapon"), "the hero bought the blade")
	check(run.world.buildings[stall]["goods"].is_empty(), "the stall sold out")
	check(int(run.stock["shells"]) >= shells + price, "the settlement got the shells")
	var sales: Array = run.to_record()["rounds"][0]["market"]
	check_eq(sales.size(), 1, "the sale is recorded")


func test_prices_follow_the_stall_level() -> void:
	var run := _run()
	var good := {"recipe": "flint_blade", "tier": 2}
	var fair := run.price_of(good)
	run.set_price("arms", "cheap")
	var cheap := run.price_of(good)
	run.set_price("arms", "dear")
	var dear := run.price_of(good)
	check(cheap < fair and fair < dear, "cheap < fair < dear (%d, %d, %d)" % [cheap, fair, dear])
	check_eq(fair, 24, "fair price is the recipe price per tier")
	var actions: Array = run.to_record()["rounds"][0]["actions"]
	check(actions.any(func(a: Dictionary) -> bool: return a["kind"] == "price" and a["level"] == "dear"), "price changes are recorded")


func test_greedy_heroes_skip_dear_stalls() -> void:
	var run := _run()
	_raise(run, "market")
	var stall := _raise(run, "arms_stall")
	_stock_stall(run, stall, "flint_blade")
	run.set_price("arms", "dear")
	var greedy := run.heroes[0]
	greedy.trait_id = "greedy"
	greedy.gold = 500
	var t: Dictionary = run.content.traits["greedy"]
	check(run.world.hero_ai.best_buy(greedy, t).is_empty(), "a greedy hero won't pay Dear prices")
	var brave := run.heroes[1]
	brave.trait_id = "brave"
	brave.gold = 500
	brave.items.erase("weapon")
	check(not run.world.hero_ai.best_buy(brave, run.content.traits["brave"]).is_empty(), "a brave hero will")


func test_beast_kills_yield_hides_and_the_lodge_pays_prizes() -> void:
	var run := _run()
	var w := run.world
	w.reset_night_report()
	var hero := run.heroes[0]
	var wolf := w.enemy_ai.make_enemy("wolf", Vector2(400, 0), 0.0)
	w.damage(hero, wolf, 999.0)
	check_eq(run.stock["hides"], 1, "a dead wolf gives a hide")
	check_eq(run.stock["bone"], 1, "and a bone")
	_raise(run, "hunting_lodge")
	w.market.refresh_prizes()
	run.stock["shells"] = 10
	var gold := hero.gold
	var raider := w.enemy_ai.make_enemy("raider", Vector2(400, 0), 0.0)
	w.damage(hero, raider, 999.0)
	check_eq(run.stock["shells"], 10, "no prize for a raider (not a beast)")
	var wolf2 := w.enemy_ai.make_enemy("wolf", Vector2(400, 0), 0.0)
	gold = hero.gold
	w.damage(hero, wolf2, 999.0)
	check_eq(run.stock["hides"], 3, "the lodge skins an extra hide")
	check_eq(run.stock["shells"], 7, "the lodge pays a 3-shell prize")
	check(hero.gold >= gold + 3, "to the hero")
	check(w.market.prize_for("cave_bear") == 3 and w.market.prize_for("raider") == 0, "prizes key on the beast tag")


func test_provisions_restore_energy_and_heal() -> void:
	var run := _run()
	_start_day(run)
	var w := run.world
	var hero := run.heroes[0]
	hero.pack.append("smoked_meat")
	hero.pack.append("poultice")
	hero.energy = 5.0
	hero.pos = Vector2(400, 0)
	w.hero_ai.hero_tick(hero)
	check(hero.energy > 30.0, "a tired hero in the wilds eats smoked meat")
	check(not hero.pack.has("smoked_meat"), "and it is used up")
	hero.hp = hero.max_hp * 0.2
	var before := hero.hp
	w.hero_ai.hero_tick(hero)
	check(hero.hp > before + 20.0, "a hurt hero uses a poultice")
	check(hero.pack.is_empty(), "pack empty")


func test_heroes_fetch_obsidian_once_a_knapper_stands() -> void:
	var run := _run()
	var w := run.world
	var hero := run.heroes[0]
	var outcrop := -1
	for i in w.nodes.size():
		if w.nodes[i]["type"] == "obsidian":
			outcrop = i
	check(outcrop >= 0, "the map has obsidian outcrops")
	hero.pos = w.nodes[outcrop]["pos"] + Vector2(20, 0)
	check_eq(w.hero_ai.outcrop_for(hero), -1, "nobody bothers without a knapper")
	_raise(run, "knapper")
	check_eq(w.hero_ai.outcrop_for(hero), outcrop, "with a knapper the shards are worth fetching")
	w.hero_ai.take_shards(hero, outcrop)
	check_eq(hero.carry_amount, 3, "a hero carries three shards")
	run.stock["shells"] = 20
	var gold := hero.gold
	w.hero_ai.sell_shards(hero)
	check_eq(run.stock["obsidian"], 3, "the settlement gets the shards")
	check_eq(hero.gold, gold + 6, "and pays 2 shells each")
	check_eq(run.stock["shells"], 14, "out of its own stock")


func test_townsfolk_never_gather_obsidian() -> void:
	var run := _run()
	for node in run.world.nodes:
		if node["type"] == "obsidian":
			check(node["heroes_only"], "obsidian is hero territory")
			check(node["pos"].length() > 400.0, "out in the wilds")


func test_market_bot_run_records_the_economy() -> void:
	var run := _run(1001)
	var bot := AutoPlayer.new()
	bot.style = "market"
	bot.play_run(run)
	var record := run.to_record()
	check_eq(int(record["format"]), RunState.RECORD_FORMAT, "current record format")
	check(record.has("prices"), "prices in the record")
	var crafted := 0
	var sold := 0
	for rd: Dictionary in record["rounds"]:
		check(rd.has("crafted") and rd.has("market") and rd.has("prizes") and rd.has("obsidian") and rd.has("yields"),
			"round %d has market fields" % rd["round"])
		for id: String in rd["crafted"]:
			crafted += int(rd["crafted"][id])
		sold += rd["market"].size()
	check(crafted > 0, "the market bot's workshops made goods")
	check(sold > 0, "heroes bought goods")
	for h: Dictionary in record["heroes"]:
		check(h.has("pack"), "hero snapshot has a pack")
	run.dispose()
