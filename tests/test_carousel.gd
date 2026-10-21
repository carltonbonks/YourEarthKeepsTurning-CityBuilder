extends TestCase
## Every few rounds a pedlar lays out items and the heroes pick one each, the weakest first.


func _run(heroes: int) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	while run.living_heroes().size() < heroes:
		run.people.add_hero(run.people.make_hero())
	return run


func test_no_pedlar_off_round() -> void:
	var run := _run(2)
	run.round_number = 1
	run.people.pedlar_carousel()
	check(run.people.last_carousel.is_empty(), "round 1 brings no pedlar")


func test_every_hero_picks_one_weakest_first() -> void:
	var run := _run(3)
	run.round_number = run.content.int_num("carousel_every")
	var heroes := run.living_heroes()
	heroes[0].level = 4
	heroes[1].level = 1
	heroes[2].level = 2
	run.people.pedlar_carousel()
	var picks: Array = run.record.entry["carousel"]
	check_eq(picks.size(), 3, "each hero takes one")
	check_eq(picks[0]["hero"], heroes[1].display_name, "the lowest level picks first")
	check_eq(picks[2]["hero"], heroes[0].display_name, "the strongest picks last")
	check_eq(int(run.record.entry["carousel_left"]), run.content.int_num("carousel_extra"), "the spare ware is left")


func test_a_hero_takes_the_upgrade_they_like() -> void:
	var run := _run(1)
	run.round_number = run.content.int_num("carousel_every")
	var hero: Unit = run.living_heroes()[0]
	var likes: Dictionary = run.content.traits[hero.trait_id].get("likes", {})
	var wares: Array[Dictionary] = []
	for base: String in run.content.items["bases"]:
		wares.append(Loot.make(base, 2))
	var pick := run.people._carousel_choice(hero, wares)
	var best_gain := -INF
	for w in wares:
		var current: Dictionary = hero.items.get(Loot.slot(run.content, w), {})
		var gain := Loot.score(run.content, w, likes) - (Loot.score(run.content, current, likes) if not current.is_empty() else 0.0)
		best_gain = maxf(best_gain, gain)
	var cur: Dictionary = hero.items.get(Loot.slot(run.content, wares[pick]), {})
	var got := Loot.score(run.content, wares[pick], likes) - (Loot.score(run.content, cur, likes) if not cur.is_empty() else 0.0)
	check(is_equal_approx(got, best_gain), "the hero takes the ware that improves most on what they wear")


func test_carousel_shows_on_the_relic_screen_data() -> void:
	var run := _run(2)
	run.round_number = run.content.int_num("carousel_every")
	run.people.pedlar_carousel()
	check_eq(run.people.last_carousel.size(), 2, "the relic screen has both picks to show")
