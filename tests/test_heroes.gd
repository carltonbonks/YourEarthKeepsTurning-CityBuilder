extends TestCase
## Slice 3: hero energy, lodgings, whims and loot.


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


func _hero_with_trait(run: RunState, trait_id: String) -> Unit:
	var hero := run.heroes[0]
	hero.trait_id = trait_id
	return hero


## Steps the world (no dawn pauses) for some seconds of game time.
func _advance(run: RunState, seconds: float) -> void:
	for i in int(seconds / run.world.dt):
		run.step()


func test_heroes_sleep_rough_without_lodging() -> void:
	var run := _run()
	run.world.hero_ai.assign_lodgings()
	for hero in run.heroes:
		check_eq(hero.lodging, -1, "no lodging means a spot by the hearth")


func test_heroes_pick_their_favourite_lodging() -> void:
	var run := _run()
	var longhouse := _raise(run, "longhouse")
	var tavern := _raise(run, "tavern")
	var shrine := _raise(run, "shrine")
	run.heroes[0].trait_id = "greedy"
	run.heroes[1].trait_id = "cautious"
	run.world.hero_ai.assign_lodgings()
	check_eq(run.heroes[0].lodging, tavern, "greedy hero sleeps in the mead hall")
	check_eq(run.heroes[1].lodging, shrine, "cautious hero sleeps in the shrine")
	check(run.world.hero_ai.is_preferred(run.heroes[0], tavern), "the mead hall is a greedy hero's favourite")
	check(not run.world.hero_ai.is_preferred(run.heroes[0], longhouse), "the longhouse is not")


func test_full_lodging_overflows() -> void:
	var run := _run()
	var shrine := _raise(run, "shrine")
	var longhouse := _raise(run, "longhouse")
	for i in 2:
		run._add_hero(run._make_hero())
	for hero in run.heroes:
		hero.trait_id = "cautious"
	run.world.hero_ai.assign_lodgings()
	var in_shrine := run.heroes.filter(func(h: Unit) -> bool: return h.lodging == shrine).size()
	var in_longhouse := run.heroes.filter(func(h: Unit) -> bool: return h.lodging == longhouse).size()
	check_eq(in_shrine, 2, "shrine holds 2")
	check_eq(in_longhouse, 2, "the rest go to the longhouse")


func test_any_lodging_brings_hero_cards() -> void:
	var run := _run()
	_raise(run, "tavern")
	run.begin_round()
	var seen := 0
	for i in 8:
		for card in run.pick_offer:
			if card["kind"] == "hero":
				seen += 1
		run._offer_picks()
	check(seen > 0, "a mead hall alone lets heroes appear at dawn")


func test_lodging_draws_heroes_who_like_it() -> void:
	var run := _run()
	_raise(run, "tavern")
	var greedy := 0
	for i in 200:
		if run._make_hero(true).trait_id == "greedy":
			greedy += 1
	# 4 traits: greedy and brave both favour the mead hall, weight 3 each vs 1 for the others.
	check(greedy > 50, "a mead hall draws greedy heroes more often (%d of 200)" % greedy)


func test_energy_drains_by_day_and_rest_restores_it() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	_advance(run, 10.0)
	var hero := run.heroes[0]
	check(hero.energy < 100.0, "energy drains while awake")
	hero.energy = 10.0
	_advance(run, 15.0)
	check(hero.resting or hero.pos.distance_to(run.world.hero_ai.bed_pos(hero)) > 8.0, "a tired hero heads to bed")


func test_rest_rate_depends_on_lodging() -> void:
	var run := _run()
	var w := run.world
	var hero := _hero_with_trait(run, "greedy")
	var tavern := _raise(run, "tavern")
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	hero.lodging = -1
	hero.pos = w.hero_ai.bed_pos(hero)
	hero.resting = true
	hero.energy = 0.0
	w.hero_ai.rest_tick(hero)
	var rough := hero.energy
	hero.lodging = tavern
	hero.pos = w.hero_ai.bed_pos(hero)
	hero.resting = true
	hero.energy = 0.0
	w.hero_ai.rest_tick(hero)
	check(hero.energy > rough * 2.0, "a mead hall bed rests far faster than the bare ground (%.2f vs %.2f)" % [hero.energy, rough])


func test_sleepers_wake_for_nearby_enemies_only() -> void:
	var run := _run()
	var w := run.world
	var hero := _hero_with_trait(run, "greedy")
	var tavern := _raise(run, "tavern")
	run.begin_round()
	run.choose_pick(-1)
	w.enemies.clear()
	hero.lodging = tavern
	hero.pos = w.hero_ai.bed_pos(hero)
	hero.resting = true
	hero.energy = 50.0
	var far := w.enemy_ai.make_enemy("raider", hero.pos + Vector2(150, 0), 0.0)
	w.enemies.append(far)
	w.hero_ai.rest_tick(hero)
	check(hero.resting, "a deep sleeper in the mead hall ignores a raider 150 away")
	far.pos = hero.pos + Vector2(60, 0)
	w.hero_ai.rest_tick(hero)
	check(not hero.resting, "but wakes when it comes close")


func test_exhausted_heroes_hit_softer() -> void:
	var run := _run()
	var w := run.world
	var hero := run.heroes[0]
	var a := w.enemy_ai.make_enemy("cave_bear", Vector2(300, 0), 0.0)
	var b := w.enemy_ai.make_enemy("cave_bear", Vector2(300, 0), 0.0)
	hero.attack = 10.0
	hero.energy = 100.0
	w.hit(hero, a)
	hero.energy = 0.0
	w.hit(hero, b)
	check(a.max_hp - a.hp > b.max_hp - b.hp, "exhausted hit is weaker")


func test_whims_follow_traits_and_lodgings() -> void:
	var run := _run()
	for hero in run.heroes:
		hero.trait_id = "greedy"
	var carouse := 0
	for i in 30:
		run.round_number = i + 1
		run.world.hero_ai.roll_whims()
		for hero in run.heroes:
			check(hero.whim in run.content.whims, "whim is a known id")
			if hero.whim == "carouse":
				carouse += 1
	check_eq(carouse, 0, "no carousing without a mead hall")
	_raise(run, "tavern")
	for i in 30:
		run.round_number = i + 1
		run.world.hero_ai.roll_whims()
		for hero in run.heroes:
			if hero.whim == "carouse":
				carouse += 1
	check(carouse > 0, "greedy heroes carouse once there is a mead hall")


func test_hero_wears_better_loot_and_keeps_the_rest_to_sell() -> void:
	var run := _run()
	var hero := _hero_with_trait(run, "brave")
	var before := hero.attack
	run.world.hero_ai.give_item(hero, Loot.make("flint_blade", 2))
	check_eq(hero.items["weapon"]["tier"], 2, "wears the blade")
	check(hero.attack > before, "the blade adds damage")
	run.world.hero_ai.give_item(hero, Loot.make("flint_blade", 1))
	check_eq(hero.items["weapon"]["tier"], 2, "keeps the better blade on")
	check_eq(hero.spares.size(), 1, "the worse blade is kept to sell")


func test_selling_loot_pays_hero_and_settlement() -> void:
	var run := _run()
	var hero := run.heroes[0]
	hero.spares.append(Loot.make("fur_cloak", 2, ["sturdy"]))
	hero.gold = 0
	var shells: int = run.stock["shells"]
	run._heroes_sell_finds()
	var value := Loot.value(run.content, Loot.make("fur_cloak", 2, ["sturdy"]))
	var cut := roundi(value * float(run.content.items["sell_tax"]))
	check_eq(run.stock["shells"], shells + cut, "the settlement keeps a cut")
	check(hero.spares.is_empty(), "spares sold")
	check_eq(run._round_entry["sales"].size(), 1, "sale recorded")


func test_no_traders_sell_gear_between_rounds() -> void:
	var run := _run()
	var hero := _hero_with_trait(run, "brave")
	hero.gold = 200
	run._heroes_sell_finds()
	check(not hero.items.has("weapon"), "gear only comes from the market's stalls now")
	check_eq(hero.gold, 200, "nothing bought")


func test_dropped_items_are_valid_and_reproducible() -> void:
	var content := Content.load_default()
	var a := SeededRng.new(7)
	var b := SeededRng.new(7)
	for i in 50:
		var item := Loot.roll(content, a, 1 + i % 10)
		check_eq(item, Loot.roll(content, b, 1 + i % 10), "same seed, same item")
		check(content.items["bases"].has(item["base"]), "known base")
		check(int(item["tier"]) >= 1 and int(item["tier"]) <= 3, "tier in range")


func test_record_has_hero_items_whims_and_loot() -> void:
	var record := bot_record(4821)
	check(int(record["format"]) >= 4, "record format 4 or later")
	var whims := 0
	for rd: Dictionary in record["rounds"]:
		check(rd.has("loot") and rd.has("sales") and rd.has("hero_spending"), "round %d has loot fields" % rd["round"])
		whims += rd["whims"].size()
	check(whims > 0, "whims recorded")
	for h: Dictionary in record["heroes"]:
		check(h.has("items") and h.has("energy") and h.has("lodging"), "hero snapshot has items, energy and lodging")
