extends TestCase
## The war camp: raiders catch-up holds back camp in the wilds instead of vanishing (EnemyAI.make_camp), and march
## with the next round's attack unless heroes break the camp first (mercy as a loan); glory for an uneased attack.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func _weaken(run: RunState) -> void:
	for hero in run.heroes:
		hero.alive = false
	for u in run.world.folk:
		u.alive = false


## Plans round `r` for a town with no fighters and makes the camp from what was held back.
func _eased_camp(run: RunState, r := 8) -> int:
	run.round_number = r
	run.waves.plan(r)
	return run.world.enemy_ai.make_camp(run.held_back)


func test_dens_at_the_start_are_never_a_camp() -> void:
	var w := _run().world
	check_eq(w.dens.size(), w.content.int_num("den_count"), "only the usual dens")
	check(w.dens.all(func(d: Dictionary) -> bool: return not d.get("camp", false)), "no camp before anything is held back")
	check_eq(w.camp_index(), -1, "no camp")


func test_held_back_raiders_make_a_camp_by_a_node() -> void:
	var run := _run()
	_weaken(run)
	var joined := _eased_camp(run)
	var w := run.world
	check(run.wave_eased > 0, "the wave was eased")
	check_eq(run.held_back.size(), run.wave_eased, "every held-back raider is listed")
	check(joined > 0, "held-back raiders camp")
	var ci := w.camp_index()
	check(ci >= 0, "a camp stands")
	check_eq(w.enemy_ai.camp_raiders().size(), joined, "they live at the camp")
	var pos: Vector2 = w.dens[ci]["pos"]
	check(pos.length() >= w.content.num("camp_min_distance") - 0.1, "out past the town")
	var held := w.nodes.filter(func(n: Dictionary) -> bool: return w.held_by_camp(n))
	check(not held.is_empty(), "it holds a node")
	for n: Dictionary in held:
		check(not w.node_safe(n), "townsfolk won't gather a held node")
	var free := w.nodes.filter(func(n: Dictionary) -> bool: return not w.held_by_camp(n) and not n["wild"])
	check(free.all(func(n: Dictionary) -> bool: return w.node_safe(n)), "other nodes are unaffected")


func test_a_strong_town_never_gets_a_camp() -> void:
	var run := _run()
	for i in 40:
		run.world.folk_ai.add_folk("warrior")
	check_eq(_eased_camp(run, 3), 0, "nothing held back, nobody camps")
	check_eq(run.world.camp_index(), -1, "no camp")


func test_later_raiders_join_the_same_camp_up_to_the_cap() -> void:
	var run := _run()
	_weaken(run)
	_eased_camp(run, 8)
	var w := run.world
	var first: Vector2 = w.dens[w.camp_index()]["pos"]
	_eased_camp(run, 12)
	check_eq(w.dens.size(), w.content.int_num("den_count") + 1, "still one camp")
	check_eq(w.dens[w.camp_index()]["pos"], first, "it stays where it was")
	check(w.enemy_ai.camp_raiders().size() <= w.content.int_num("camp_max_raiders"), "never more than the cap")


func test_battering_rams_never_camp() -> void:
	var run := _run()
	var siege: Array[String] = []
	for id: String in run.content.enemies:
		if run.content.has_tag("enemy", id, "siege"):
			siege.append(id)
	check(not siege.is_empty(), "some raider is a siege engine")
	check_eq(run.world.enemy_ai.make_camp(siege), 0, "rams stay away")


func test_breaking_the_camp_frees_the_land_and_pays_no_plunder() -> void:
	var run := _run()
	_weaken(run)
	_eased_camp(run)
	var w := run.world
	var hero := run.people.make_hero()
	run.people.add_hero(hero)
	var shells := int(run.stock["shells"])
	var finds := hero.items.size() + hero.spares.size()
	for e in w.enemy_ai.camp_raiders():
		w.damage(hero, e, e.hp + 1.0)
	check_eq(int(run.stock["shells"]), shells, "weakness no longer pays: no plunder")
	check(hero.items.size() + hero.spares.size() > finds, "the hero who ended it finds an item")
	check_eq(w.camp_index(), -1, "the camp is gone")
	check_eq(int(run.record.entry.get("camps_cleared", 0)), 1, "logged")
	w._cleanup()
	check_eq(w.dens.size(), w.content.int_num("den_count"), "the camp is taken off the map")
	check(w.nodes.all(func(n: Dictionary) -> bool: return not w.held_by_camp(n)), "no node is held any more")


func test_campers_march_with_the_next_rounds_attack_not_this_ones() -> void:
	var run := _run()
	_weaken(run)
	var joined := _eased_camp(run, 8)
	var w := run.world
	check(joined > 0, "a camp formed")
	check(run.waves.camp_due().is_empty(), "raiders held back this round aren't due yet")
	w.roll_wave_sides()
	w.enemy_ai.spawn_wave()
	check_eq(w.enemy_ai.camp_raiders().size(), joined, "this round they stay in camp")
	# Next round the loan comes due.
	run.round_number = 9
	run.next_wave = []
	check_eq(run.waves.camp_due().size(), joined, "every camper is due")
	check_eq(run.waves.attack().size(), joined, "the attack counts them")
	var campers := w.enemy_ai.camp_raiders()
	w.enemy_ai.spawn_wave()
	check(w.enemy_ai.camp_raiders().is_empty(), "they left the camp")
	check(campers.all(func(e: Unit) -> bool: return e.den_index < 0 and e.target == null), "they march on the hearth with the attack")
	check_eq(w.camp_index(), -1, "an empty camp is gone")
	check_eq(int(run.record.entry.get("camp_marched", 0)), joined, "logged")


func test_heroes_who_break_the_camp_first_cancel_the_loan() -> void:
	var run := _run()
	_weaken(run)
	_eased_camp(run, 8)
	var w := run.world
	run.round_number = 9
	run.next_wave = []
	for e in w.enemy_ai.camp_raiders():
		w.damage(null, e, e.hp + 1.0)
	check(run.waves.camp_due().is_empty(), "nobody left to march")
	w.roll_wave_sides()
	w.enemy_ai.spawn_wave()
	check(w.enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index < 0).is_empty(), "nobody marches")


func test_glory_adds_a_relic_card_when_the_attack_was_not_eased() -> void:
	var run := _run()
	for i in 40:
		run.world.folk_ai.add_folk("warrior")
	run.round_number = 3
	run.waves.plan(3)
	check(not run.outmatched, "a strong town isn't outmatched")
	var offer := run._roll_relic_offer()
	check(run.glory, "glory")
	var base := run.content.int_num("relic_choices") + run.content.int_num("glory_relic_choices")
	check_eq(offer.size() - (1 if not run.spoils.is_empty() else 0), base, "one more relic to choose from")


func test_no_glory_for_an_eased_attack_even_under_the_black_banner() -> void:
	var run := _run()
	_weaken(run)
	run.relics.append("black_banner")
	run.round_number = 8
	run.waves.plan(8)
	check_eq(run.wave_eased, 0, "the banner turns catch-up off")
	check(run.outmatched, "but the town was still outmatched")
	var offer := run._roll_relic_offer()
	check(not run.glory, "no glory")
	check_eq(offer.size() - (1 if not run.spoils.is_empty() else 0), run.content.int_num("relic_choices"), "the usual offer")


func test_campers_stay_through_the_end_of_a_round() -> void:
	var run := _run()
	_weaken(run)
	_eased_camp(run)
	var n := run.world.enemy_ai.camp_raiders().size()
	run.world._finish_round()
	check_eq(run.world.enemy_ai.camp_raiders().size(), n, "the camp outlasts the round")


func test_hover_explains_the_camp_and_the_land_it_holds() -> void:
	var run := _run()
	_weaken(run)
	_eased_camp(run)
	var w := run.world
	var tip := Tooltips.den(run, w.dens[w.camp_index()])
	check_eq(tip["title"], "War camp", "the camp has its own card")
	check(" ".join(tip["lines"]).contains("march"), "it says the camp marches with the next attack")
	var held: Dictionary = w.nodes.filter(func(n: Dictionary) -> bool: return w.held_by_camp(n))[0]
	check(" ".join(Tooltips.node(run, held)["lines"]).contains("war camp"), "a held node says why nobody gathers it")
