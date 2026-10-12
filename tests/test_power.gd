extends TestCase
## Power levels (sim/power.gd): the town and the wave rated on one scale and logged per round.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func test_enemy_power_follows_stats() -> void:
	var c := Content.load_default()
	check(Power.enemy(c, "wolf") > Power.enemy(c, "raider"), "a wolf outranks a raider")
	check(Power.enemy(c, "cave_bear") > Power.enemy(c, "wolf"), "a cave bear outranks a wolf")
	check(Power.enemy(c, "antlered_king") > Power.enemy(c, "cave_bear"), "the boss outranks a bear")


func test_wave_power_adds_up_and_chants_scale_it() -> void:
	var c := Content.load_default()
	check(is_equal_approx(Power.wave(c, ["raider", "raider"]), 2.0 * Power.enemy(c, "raider")), "two raiders = twice one")
	var plain := Power.enemy(c, "raider") + Power.enemy(c, "bone_caller")
	check(Power.wave(c, ["raider", "bone_caller"]) > plain, "a war chant raises the whole wave")


func test_shield_counts_as_extra_hp() -> void:
	var c := Content.load_default()
	var e: Dictionary = c.enemies["bronze_reaver"]
	var bare := Power.rating(float(e["hp"]), float(e["attack"]) / float(e["cooldown"]))
	check(Power.enemy(c, "bronze_reaver") > bare, "a shielded reaver rates above its bare stats")


func test_later_waves_are_stronger() -> void:
	var run := _run()
	var c := run.content
	check(Power.wave(c, run.generate_wave(8)) > Power.wave(c, run.generate_wave(1)) * 3.0, "round 8 wave is far stronger than round 1")


func test_town_power_counts_heroes_fighters_and_defences() -> void:
	var run := _run()
	var before := Power.town(run.world)
	check(before["defences"] > 0.0, "the hearth's fire counts")
	run.world.folk_ai.add_folk("tribesperson")
	check_eq(Power.town(run.world)["fighters"], before["fighters"], "a tribesperson does not fight")
	run.world.folk_ai.add_folk("warrior")
	var with_warrior := Power.town(run.world)
	check(with_warrior["fighters"] > before["fighters"], "a warrior (tag fighter) counts")
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	check(run.build("watch_post"), "can order a watch post")
	check_eq(Power.town(run.world)["defences"], with_warrior["defences"], "an unbuilt tower does not count")
	run.world.buildings[run.world.buildings.size() - 1]["work_left"] = 0.0
	check(Power.town(run.world)["defences"] > with_warrior["defences"], "a raised tower adds to the defences")
	var total: float = Power.town(run.world)["total"]
	var hero: Unit = run.heroes[0]
	hero.level += 2
	run.world.hero_ai.apply_hero_stats(hero)
	check(Power.town(run.world)["total"] > total, "a levelled hero raises the town's power")


func test_round_record_logs_power_when_the_wave_comes() -> void:
	var run := _run()
	run.begin_round()
	while run.phase == RunState.Phase.PICK or run.phase == RunState.Phase.SIM:
		if run.phase == RunState.Phase.PICK:
			run.choose_pick(0)
		else:
			run.run_until_pause()
	var r1: Dictionary = run.to_record()["rounds"][0]
	check(r1.has("power"), "round 1 logs power")
	check(float(r1["power"]["wave"]) > 0.0, "wave power logged")
	check(float(r1["power"]["town"]["total"]) > 0.0, "town power logged")
