extends TestCase


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


## Plays until the next decision, taking the first pick each dawn.
func _to_round_end(run: RunState) -> void:
	if run.phase == RunState.Phase.BUILD:
		run.begin_round()
	while run.phase == RunState.Phase.PICK or run.phase == RunState.Phase.SIM:
		if run.phase == RunState.Phase.PICK:
			run.choose_pick(0)
		else:
			run.run_until_pause()


func test_new_run_starts_small_around_the_hearth() -> void:
	var run := _run()
	check_eq(run.phase, RunState.Phase.BUILD, "starts in the build phase")
	check_eq(run.heroes.size(), 2, "starting heroes")
	check_eq(run.count_role("tribesperson"), 2, "starting tribespeople")
	check_eq(run.count_role("craftsperson"), 1, "a craftsperson from the start (playtest 2026-10-25)")
	check_eq(run.count_role("warrior"), 1, "starting warriors")
	check_eq(run.world.dens.size(), 2, "dens in the wilds")
	check(not run.next_wave.is_empty(), "first wave should have enemies")
	for den in run.world.dens:
		check(den["pos"].length() > 500.0, "dens sit far out")


func test_same_seed_and_choices_replay_identically() -> void:
	# Replays the run other tests share and compares the whole record, not just the story.
	var a := _run(4821)
	AutoPlayer.new().play_run(a)
	check_eq(JSON.stringify(a.to_record()), JSON.stringify(bot_record(4821)), "same record")
	a.dispose()


func test_round_has_three_dawn_picks_then_a_relic() -> void:
	var run := _run()
	run.begin_round()
	var picks := 0
	while run.phase == RunState.Phase.PICK or run.phase == RunState.Phase.SIM:
		if run.phase == RunState.Phase.PICK:
			picks += 1
			check_eq(run.pick_offer.size(), 3, "three cards each dawn")
			run.choose_pick(-1)
		else:
			run.run_until_pause()
	check_eq(picks, 3, "one pick per day")
	check_eq(run.phase, RunState.Phase.RELIC, "relic pick after the round")


func test_wave_only_on_the_last_night() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	var saw_wave_early := false
	while run.phase == RunState.Phase.SIM:
		run.step()
		if run.world.day_index() < 2 and run.world.wave_spawned:
			saw_wave_early = true
	check(not saw_wave_early, "no wave before night 3")
	run.choose_pick(-1)
	run.run_until_pause()
	run.choose_pick(-1)
	run.run_until_pause()
	check(run.world.wave_spawned, "wave came on night 3")


func test_taking_a_pick_adds_a_person() -> void:
	var run := _run()
	run.begin_round()
	var before := run.population()
	var folk_card := -1
	for i in run.pick_offer.size():
		if run.pick_offer[i]["kind"] == "folk":
			folk_card = i
	run.choose_pick(folk_card)
	check_eq(run.population(), before + 1, "newcomer joined")


func test_no_hero_cards_without_a_longhouse() -> void:
	var run := _run()
	for r in 3:
		_to_round_end(run)
		if run.phase != RunState.Phase.RELIC:
			break
		for card in run.record.entry["picks"]:
			for label: String in card["offered"]:
				check(not label.begins_with("hero:"), "hero card without lodging")
		run.choose_relic("")


func test_longhouse_brings_hero_cards() -> void:
	var run := _run()
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	check(run.build("longhouse"), "can order a longhouse")
	run.world.buildings[0]["work_left"] = 0.0
	run.begin_round()
	var heroes_seen := 0
	for i in 6:
		for card in run.pick_offer:
			if card["kind"] == "hero":
				heroes_seen += 1
				check_eq(card["cost"], maxi(0, run.content.int_num("hero_card_cost") + int(CardRoll.card_sum(run.content, card, "cost_shells")))
					+ (run.content.int_num("legend_cost") if card.get("legend", false) else 0), "hero card costs shells (a legend more)")
		# Each dawn deals from its own seeded stream, so look at a different round's dawn each time.
		run.round_number += 1
		run.people.offer_picks()
	check(heroes_seen > 0, "hero cards appear once the longhouse stands")


func test_hero_card_needs_shells() -> void:
	var run := _run()
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	run.build("longhouse")
	run.world.buildings[0]["work_left"] = 0.0
	run.begin_round()
	run.pick_offer = [{"kind": "hero", "role": "hero", "cost": 30, "hero": run.people.make_hero()}]
	run.stock["shells"] = 10
	check(not run.can_take_pick(0), "can't afford hero with 10 shells")
	run.stock["shells"] = 40
	check(run.can_take_pick(0), "can afford hero with 40 shells")
	var heroes := run.heroes.size()
	run.choose_pick(0)
	check_eq(run.heroes.size(), heroes + 1, "hero joined")
	check_eq(run.stock["shells"], 10, "paid 30 shells")


func test_housing_limits_picks() -> void:
	var run := _run()
	run.begin_round()
	while run.population() < run.housing():
		run.world.folk_ai.add_folk("tribesperson")
	check(not run.can_take_pick(0), "no room means no newcomer")


func test_building_costs_and_gets_raised() -> void:
	var run := _run()
	var wood: int = run.stock["wood"]
	check(run.build("hut"), "can build a hut")
	check_eq(run.stock["wood"], wood - int(run.content.buildings["hut"]["cost"]["wood"]), "hut costs its listed wood")
	check_eq(run.world.count_buildings("hut"), 0, "not raised yet")
	run.world.folk_ai.add_folk("craftsperson")
	run.begin_round()
	run.choose_pick(-1)
	run.run_until_pause()
	check_eq(run.world.count_buildings("hut"), 1, "craftsperson raised the hut on day 1")


func test_hunger_drives_people_away() -> void:
	var run := _run()
	run.stock["food"] = 0
	var before := run.world.folk.size()
	run.begin_round()
	run.choose_pick(-1)
	for i in 10:
		run.step()
	run.stock["food"] = 0
	run.run_until_pause()
	check(run.world.folk.size() < before or run.stock["food"] > 0, "someone leaves when there is no food")


func test_waves_grow() -> void:
	var run := _run()
	check(run.waves.generate(8).size() > run.waves.generate(1).size(), "round 8 wave should be bigger than round 1")


func test_bosses_lead_their_rounds() -> void:
	var run := _run()
	var king_round := int(run.content.enemies["antlered_king"]["boss_round"])
	check(run.waves.generate(king_round).has("antlered_king"), "the Antlered King leads his round's wave")
	check(not run.waves.generate(king_round + 1).has("antlered_king"), "and only that one")
	check(run.waves.generate(run.content.int_num("rounds_to_win")).has("black_margrave"), "the final wave has the Margrave")


func test_relic_changes_stats() -> void:
	var run := _run()
	var before := run.heroes[0].attack
	run.relics.append("war_paint")
	run.relic_acquired_round["war_paint"] = 1
	run.world.hero_ai.apply_hero_stats(run.heroes[0])
	check(run.heroes[0].attack > before, "attack relic raises hero attack")


func test_relic_pick_advances_round_and_pays_income() -> void:
	var run := _run()
	_to_round_end(run)
	check_eq(run.phase, RunState.Phase.RELIC, "relic pick after the round")
	check_eq(run.relic_offer.size(), 3 + (0 if run.spoils.is_empty() else 1) + (1 if run.glory else 0),
		"three relics offered, the attack's spoils, and one for glory")
	var shells: int = run.stock["shells"]
	run.choose_relic(run.relic_offer[0])
	check_eq(run.round_number, 2, "round advanced")
	check(run.stock["shells"] >= shells + 10, "income paid")
	check_eq(run.phase, RunState.Phase.BUILD, "back to building")


func test_small_raids_on_early_nights() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	run.run_until_pause()
	check_eq(run.phase, RunState.Phase.PICK, "second dawn")
	check(int(run.last_night["raiders"]) > 0, "a small raid came on night 1")
	check(int(run.last_night["raiders"]) < run.next_wave.size(), "the raid is smaller than the warned wave")


func test_sentient_enemies_turn_on_attackers() -> void:
	var run := _run()
	var w := run.world
	var raider := w.enemy_ai.make_enemy("raider", Vector2(400, 0), 0.0)
	var spirit := w.enemy_ai.make_enemy("barrow_wight", Vector2(-400, 0), 0.0)
	w.content.enemies["barrow_wight"]["tags"] = ["undead"]
	var hero := run.heroes[0]
	w.damage(hero, raider, 1.0)
	w.damage(hero, spirit, 1.0)
	check(raider.target == hero, "raider (sentient) goes after the hero who hit it")
	check(spirit.target == null, "a creature without the sentient tag does not")


func test_wood_burns_when_fuel_runs_out() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	while not run.world.is_dusk():
		run.step()
	run.stock["fuel"] = 0
	run.stock["wood"] = 50
	while not run.world.is_night():
		run.stock["fuel"] = 0
		run.step()
	check(run.story.any(func(l: String) -> bool: return l.begins_with("Out of fuel")), "wood was burned")
	check(not run.world.cold_tonight, "no cold night while wood lasts")


func test_huts_need_fuel() -> void:
	var run := _run()
	var before := run.fuel_needed_tonight()
	run.stock["wood"] = 99
	run.build("hut")
	run.build("hut")
	for b in run.world.buildings:
		b["work_left"] = 0.0
	check(run.fuel_needed_tonight() > before, "more homes burn more fuel")


func test_nights_are_recorded() -> void:
	var run := _run()
	_to_round_end(run)
	var nights: Array = run.record.entry["nights"]
	check_eq(nights.size(), 3, "one report per night")
	check_eq(nights[2]["night"], 3, "last report is night 3")


func test_hungry_leavers_show_in_the_night_report() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	run.stock["food"] = 0
	run.world.reset_night_report()
	run.daily_upkeep()
	check_eq(run.world.night_report["left"].size(), 1, "someone who walks away hungry is in the report")


func test_heroes_eat_like_everyone() -> void:
	var run := _run()
	var per := run.content.num("food_per_person_per_day")
	check(not run.living_heroes().is_empty(), "the run starts with heroes")
	check_eq(run.food_needed_today(), int(ceil((run.world.folk.size() + run.living_heroes().size()) * per)),
		"townsfolk and heroes each eat")


func test_hunger_turns_the_same_kind_away() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	run.stock["food"] = 0
	run.world.reset_night_report()
	var before := {}
	for u in run.world.folk:
		before[u] = u.type_id
	run.daily_upkeep()
	var left := ""
	for u: Unit in before:
		if not run.world.folk.has(u):
			left = before[u]
	check(left != "", "someone left hungry")
	check_eq(run.hunger_turned_away, left, "word spreads among their kind")
	for i in 5:
		run.people.offer_picks()
		for card in run.pick_offer:
			check(card["kind"] != "folk" or card["role"] != left, "no %s comes the dawn after one left hungry" % left)
	run.choose_pick(-1)
	check_eq(run.record.entry["picks"][-1].get("hunger_turned_away", ""), left, "the pick record says who stayed away")
	run.stock["food"] = 99
	run.daily_upkeep()
	check_eq(run.hunger_turned_away, "", "with food again, they come back")


func test_gardens_bring_food_every_dawn() -> void:
	var run := _run()
	var grows := int(run.content.buildings["garden"]["daily"]["food"])
	check(run.build("garden"), "a garden can be ordered")
	run.world.buildings[-1]["work_left"] = 0.0
	check_eq(run.food_grown_daily(), grows, "a standing garden grows food")
	run.begin_round()
	run.choose_pick(-1)
	run.stock["food"] = 50
	var need := run.food_needed_today()
	run.daily_upkeep()
	var hearty := int(run.record.entry["hearty_meals"]) * run.content.int_num("hearty_food")
	check_eq(run.stock["food"], 50 + grows - need - hearty, "garden food arrives before the town eats (and heroes eat hearty)")
	check_eq(run.record.entry["food_grown"], grows, "food grown is recorded")
