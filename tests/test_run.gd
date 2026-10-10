extends TestCase


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func test_new_run_has_heroes_gold_and_a_wave() -> void:
	var run := _run()
	check_eq(run.heroes.size(), 3, "starting heroes")
	check_eq(run.gold, 60, "starting gold")
	check(not run.next_wave.is_empty(), "first wave should have enemies")


func test_same_seed_and_choices_replay_identically() -> void:
	var a := _run(77)
	var b := _run(77)
	AutoPlayer.new().play_run(a)
	AutoPlayer.new().play_run(b)
	check_eq(a.round_number, b.round_number, "round reached")
	check_eq(a.story, b.story, "story of the run")


func test_waves_grow() -> void:
	var run := _run()
	check(run.generate_wave(8).size() > run.generate_wave(1).size(), "round 8 wave should be bigger than round 1")


func test_last_round_has_boss() -> void:
	var run := _run()
	check(run.generate_wave(run.content.int_num("rounds_to_win")).has("warlord"), "final wave should include the warlord")


func test_bounty_reserves_gold_and_refuses_overspend() -> void:
	var run := _run()
	run.next_wave = ["goblin", "goblin"] as Array[String]
	check(run.set_bounty("goblin", 10), "should afford 2 x 10g")
	check_eq(run.free_gold(), 40, "free gold after reserving 20")
	run.gold = 15
	check(not run.set_bounty("goblin", 10), "can't reserve 20 with 15 gold")


func test_unclaimed_bounty_is_refunded() -> void:
	var run := _run()
	run.next_wave = ["goblin"] as Array[String]
	run.set_bounty("goblin", 10)
	var battle := run.start_battle()
	check_eq(run.gold, 50, "bounty held during battle")
	battle.run_to_end()
	var paid := battle.bounty_paid
	run.finish_battle(battle)
	check_eq(run.gold, 60 - paid, "town only pays for claimed bounties")


func test_relic_changes_stats() -> void:
	var run := _run()
	var before := run.heroes[0].attack
	run.relics.append("war_banner")
	run.relic_acquired_round["war_banner"] = 1
	run.start_battle()
	check_eq(run.heroes[0].attack, before + 2.0, "war banner adds 2 attack")


func test_relic_pick_advances_round_and_pays_income() -> void:
	var run := _run()
	var battle := run.start_battle()
	battle.run_to_end()
	run.finish_battle(battle)
	check_eq(run.phase, RunState.Phase.RELIC, "relic pick after a won wave")
	check_eq(run.relic_offer.size(), 3, "three relics offered")
	var gold := run.gold
	run.choose_relic(run.relic_offer[0])
	check_eq(run.round_number, 2, "round advanced")
	check(run.gold >= gold + 25, "income paid")


func test_market_raises_income() -> void:
	var run := _run()
	var before := run.income()
	check(run.build_market(), "can build a market at the start")
	check_eq(run.income(), before + 10, "market adds 10 income")
