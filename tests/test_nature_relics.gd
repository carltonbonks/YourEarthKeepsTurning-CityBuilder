extends TestCase
## Relics keyed on a hero's class and trait, and on kinds of building (Yusuf, 2026-11-20, relic slice 1): hero_stats,
## hero_nature, hero_xp, whim_weight, building_add and building_mult; plus plate relics offered only when crossed
## and relics that wait for an age.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


## A hero of a class and trait, with stats worked out.
func _hero(run: RunState, type: String, trait_id: String) -> Unit:
	var hero := run.people.make_hero()
	hero.type_id = type
	hero.trait_id = trait_id
	run.people.add_hero(hero)
	run.world.hero_ai.apply_hero_stats(hero)
	return hero


func test_hero_stats_key_on_class_and_trait() -> void:
	var run := _run()
	var stalker := _hero(run, "stalker", "cautious")
	var hunter := _hero(run, "hunter", "cautious")
	var speed := stalker.speed
	var attack := stalker.attack
	var reach := hunter.attack_range
	run._gain_relic("stalkers_shroud")
	run._gain_relic("hunters_fetish")
	check_eq(stalker.speed, speed + 15.0, "stalkers move faster")
	check_eq(stalker.attack, attack + 2.0, "stalkers hit harder")
	check_eq(hunter.attack_range, reach + 40.0, "hunters shoot farther")
	check_eq(hunter.speed, float(run.content.hero_classes["hunter"]["speed"]) + Loot.total(run.content, hunter, "speed", run.gear_bonus()),
		"the shroud leaves hunters alone")
	run.dispose()


func test_a_pact_can_take_as_well_as_give() -> void:
	var run := _run()
	var bold := _hero(run, "champion", "brave")
	var meek := _hero(run, "champion", "cautious")
	var a := bold.attack
	var b := meek.attack
	run._gain_relic("warlords_oath")
	check_eq(bold.attack, a + 4.0, "brave heroes hit harder")
	check_eq(meek.attack, b - 2.0, "cautious heroes hit softer")
	run.dispose()


func test_hero_nature_shifts_the_trait_for_that_trait_only() -> void:
	var run := _run()
	var brave := _hero(run, "champion", "brave")
	var greedy := _hero(run, "champion", "greedy")
	var ai := run.world.hero_ai
	var base := float(run.content.traits["brave"]["retreat_at"])
	check(ai.trait_of(brave) == run.content.traits["brave"], "no relic, the plain trait")
	run._gain_relic("berserkers_paint")
	check_eq(float(ai.trait_of(brave)["retreat_at"]), maxf(0.0, base - 0.25), "brave heroes fall back later")
	check_eq(float(ai.trait_of(greedy)["retreat_at"]), float(run.content.traits["greedy"]["retreat_at"]), "greedy ones don't")
	check_eq(float(run.content.traits["brave"]["retreat_at"]), base, "the trait's data is untouched")
	run._gain_relic("oathkeepers_ring")
	var dutiful := _hero(run, "champion", "dutiful")
	check_eq(float(ai.trait_of(dutiful)["wilds"]), 0.0, "never below 0")
	run.dispose()


func test_whim_weight_rules_whims_in_and_out() -> void:
	var run := _run()
	var dutiful := _hero(run, "champion", "dutiful")
	run._gain_relic("oathkeepers_ring")
	for night in 12:
		run.world.time = night * run.world.day_length()
		run.world.hero_ai.roll_whims()
		check(dutiful.whim != "hunt" and dutiful.whim != "trophy", "a dutiful hero never goes hunting (night %d)" % night)
	run.dispose()


func test_hero_xp_keys_on_the_killers_trait() -> void:
	var run := _run()
	var cautious := _hero(run, "hunter", "cautious")
	var brave := _hero(run, "hunter", "brave")
	run._gain_relic("hares_foot")
	for hero in [cautious, brave]:
		var e := run.world.enemy_ai.make_enemy("wolf", Vector2(500, 0), 0.0)
		run.world.enemies.append(e)
		hero.xp = 0.0
		run.world.damage(hero, e, 9999.0)
	check(cautious.xp > brave.xp * 1.5, "cautious heroes learn more from a kill (%.1f vs %.1f)" % [cautious.xp, brave.xp])
	run.dispose()


func test_building_relics_change_every_building_of_the_kind() -> void:
	var run := _run()
	var beds := {}
	for type: String in run.content.buildings:
		if run.content.has_tag("building", type, "lodging"):
			beds[type] = [int(run.content.buildings[type]["lodging"]["beds"]), float(run.content.buildings[type]["lodging"]["rest"])]
	check(beds.size() >= 3, "several lodgings carry the tag")
	run._gain_relic("thatchers_knot")
	for type: String in beds:
		var lodging: Dictionary = run.content.buildings[type]["lodging"]
		check_eq(int(lodging["beds"]), int(beds[type][0]) + 1, "%s has a bed more" % type)
		check_eq(float(lodging["rest"]), float(beds[type][1]) * 1.35, "%s rests faster" % type)
	var food := int(run.content.buildings["garden"]["daily"]["food"])
	run._gain_relic("seed_mothers_basket")
	check_eq(int(run.content.buildings["garden"]["daily"]["food"]), food + 1, "gardens grow more")
	check(not run.content.buildings["market"].has("daily"), "the market grows nothing")
	run.dispose()


func test_building_relics_belong_to_one_run() -> void:
	var game := Content.load_default()
	var a := RunState.new(game, 1)
	var huts := int(a.content.buildings["hut"]["housing"])
	a._gain_relic("tyrants_lash")
	check_eq(int(a.content.buildings["hut"]["housing"]), huts - 1, "the pact's cost lands")
	check(float(a.content.buildings["knapper"]["craft_speed"]) >= 1.0, "workshops work faster")
	var b := RunState.new(game, 2)
	check_eq(int(b.content.buildings["hut"]["housing"]), huts, "another run's huts are untouched")
	a.dispose()
	b.dispose()


func test_housing_follows_the_relic() -> void:
	var run := _run()
	var before := run.housing()
	var huts := run.world.count_buildings("hut")
	run._gain_relic("hearthstone")
	check_eq(run.housing(), before + huts, "every standing hut houses one more")
	run.dispose()


func test_plate_relics_come_only_when_an_attack_can_cross_their_kind() -> void:
	var run := _run()
	var crossed := run.world.earth.tags_crossed()
	check(not crossed.is_empty(), "the dens' ways cross something")
	for id: String in run.content.relics:
		var plates: Dictionary = run.content.relics[id]["effects"].get("plate_knobs", {})
		if plates.is_empty():
			continue
		var can := plates.keys().any(func(tag: String) -> bool: return tag in crossed)
		check_eq(run.relic_can_come(id), can, "%s is offered only if its ground is crossed" % id)
	# With every den cleared, an attack may come from any side, so every kind counts.
	for den in run.world.dens:
		den["cleared"] = true
	check_eq(run.world.earth.tags_crossed().size(), run.content.plates["near_kinds"].size(), "every kind once the dens fall")
	run.dispose()


func test_bronze_relics_wait_for_bronze() -> void:
	var run := _run()
	check(not run.relic_can_come("caravan_seal"), "no caravan seal before the caravan")
	check(not run.relic_can_come("smith_gods_hammer"), "no ore relic in the stone age")
	run.age = "bronze"
	check(run.relic_can_come("caravan_seal"), "offered once the town is bronze")
	run.dispose()
