extends TestCase
## Rolled dawn cards (sim/card_roll.gd): each townsfolk card dealt rolls its own rarity, and a rolled card carries
## modifiers (a mark from data/marks.json, powerful or transmuting ones from data/card_mods.json).


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	return run


func test_roll_odds_climb_from_the_first_round_to_the_last() -> void:
	var c := Content.load_default()
	check_eq(CardRoll.roll_chance(c, "white", 1), 0.0, "white takes what is left")
	check(is_equal_approx(CardRoll.roll_chance(c, "blue", 1), 0.05), "blue starts at 5%")
	check(is_equal_approx(CardRoll.roll_chance(c, "blue", c.int_num("rounds_to_win")), 0.09), "and ends at 9%")
	check(CardRoll.roll_chance(c, "orange", 7) > CardRoll.roll_chance(c, "orange", 1), "orange climbs too")


func test_rolls_come_up_about_as_often_as_the_odds_say() -> void:
	var c := Content.load_default()
	var rng := SeededRng.new(77)
	var counts := {}
	var n := 20000
	for i in n:
		var r := CardRoll.roll_rarity(c, rng, 1)
		counts[r] = int(counts.get(r, 0)) + 1
	var blue := float(counts.get("blue", 0)) / n
	check(blue > 0.04 and blue < 0.06, "about 5% blue in round 1 (%.3f)" % blue)
	var yellow := float(counts.get("yellow", 0)) / n
	check(yellow > 0.005 and yellow < 0.015, "about 1% yellow (%.3f)" % yellow)
	check(int(counts.get("orange", 0)) < n * 0.006, "orange is rare")


func test_rolled_cards_carry_modifiers_that_fit_the_role() -> void:
	var c := Content.load_default()
	var rng := SeededRng.new(5)
	var seen := {}
	for i in 4000:
		var card := {"kind": "folk", "role": "warrior"}
		CardRoll.roll_folk(c, rng, card, 14)
		var roll := CardRoll.roll_of(card)
		seen[roll] = true
		if roll == "blue":
			check(card.has("mark") and not card.has("boons"), "blue is one mark")
		elif roll == "yellow":
			check(card.has("mark") and card["boons"].size() >= 1 and card["boons"].size() <= 2, "yellow is a mark and one or two")
		elif roll == "orange":
			check(not card.has("mark") and card["boons"].size() == 1, "orange is one transmutation")
		if card.has("mark"):
			check(c.marks[card["mark"]].get("roles", ["warrior"]).has("warrior"), "a warrior's mark fits warriors")
		for id: String in card.get("boons", []):
			check(c.card_mods[id].get("roles", ["warrior"]).has("warrior"), "%s fits warriors" % id)
			check(not c.card_mods[id].get("needs_leaning", false), "no band modifier without a leaning")
		if card.has("boons") and card["boons"].size() == 2:
			check(card["boons"][0] != card["boons"][1], "no modifier twice")
	check(seen.has("blue") and seen.has("yellow") and seen.has("orange"), "every rarity turns up (%s)" % seen.keys())


func test_dawn_deals_roll_townsfolk_cards_without_changing_which_cards_are_dealt() -> void:
	var plain := _run()
	var rolled := _run()
	var rolls := 0
	for i in 40:
		plain.round_number = i + 1
		rolled.round_number = i + 1
		plain.people.offer_picks()
		rolled.people.offer_picks()
		check_eq(rolled.pick_offer.map(rolled.people.card_label), plain.pick_offer.map(plain.people.card_label), "same cards")
		for card in rolled.pick_offer:
			if card.has("roll"):
				rolls += 1
				check(card["kind"] == "folk" or card.get("legend", false), "only townsfolk cards and legends roll")
	check(rolls > 0, "some cards rolled over 40 dawns (%d)" % rolls)


func test_a_magic_card_brings_a_townsperson_born_with_its_mark() -> void:
	var run := _run()
	run.pick_offer = [{"kind": "folk", "role": "warrior", "cost": 0, "roll": "blue", "mark": "swift"}]
	var speed := float(run.content.townsfolk["warrior"]["speed"])
	run.choose_pick(0)
	var newcomer: Unit = run.world.folk[-1]
	check_eq(newcomer.mark, "swift", "born swift")
	check(is_equal_approx(newcomer.speed, speed * 1.1), "10% faster")
	check(run.content.unit_has_tag(newcomer, "swift"), "and carries the mark's tag")
	var pick: Dictionary = run.record.entry["picks"][-1]
	check_eq(pick["roll"], "blue", "the record keeps the roll")
	check_eq(pick["mods"], ["swift"], "and the modifiers")
	check_eq(run.record.entry["card_mods_taken"], {"swift": 1}, "and counts it")


func test_a_born_mark_counts_toward_the_one_mark_cap() -> void:
	var run := _run()
	run.pick_offer = [{"kind": "folk", "role": "warrior", "cost": 0, "roll": "blue", "mark": "hardy"}]
	run.choose_pick(0)
	var newcomer: Unit = run.world.folk[-1]
	newcomer.task = ""
	run.world.folk_ai.begin_step()
	check(not run.world.folk_ai._free_pupils.has(newcomer), "a warrior born with a mark doesn't drill for another")


func test_powerful_modifiers_change_the_newcomer() -> void:
	var run := _run()
	run.pick_offer = [{"kind": "folk", "role": "craftsperson", "cost": 0, "roll": "yellow", "mark": "steady_hands",
		"boons": ["master_builder"]}]
	run.choose_pick(0)
	var u: Unit = run.world.folk[-1]
	var base := float(run.content.townsfolk["craftsperson"]["build_rate"]) + run.tool_bonus("craftsperson", "build_rate")
	check(is_equal_approx(run.world.folk_ai.work_rate(u), base * 1.7), "steady hands and master builder: 70% faster")
	check(run.content.unit_has_tag(u, "builder"), "card modifiers' tags are the unit's tags")


func test_twins_bring_two_and_need_two_beds() -> void:
	var run := _run()
	var card := {"kind": "folk", "role": "tribesperson", "cost": 0, "leaning": "forager", "roll": "yellow", "mark": "swift",
		"boons": ["twins"]}
	check_eq(run.people.card_people(card), 2, "two people")
	run.pick_offer = [card]
	var before := run.world.folk.size()
	run.choose_pick(0)
	check_eq(run.world.folk.size(), before + 2, "both arrive")
	check_eq(run.world.folk[-1].leaning, "forager", "the twin shares the leaning")
	check_eq(run.world.folk[-1].mark, "", "but not the mark")


func test_a_born_leader_counts_twice_in_their_band() -> void:
	var run := _run()
	run.pick_offer = [{"kind": "folk", "role": "tribesperson", "cost": 0, "leaning": "forager", "roll": "yellow",
		"mark": "swift", "boons": ["born_leader"]}]
	var before := int(run.world.folk_ai.count_leanings().get("tribesperson/forager", 0))
	run.choose_pick(0)
	check_eq(int(run.world.folk_ai.count_leanings().get("tribesperson/forager", 0)), before + 2, "counts as two")


func test_light_eaters_and_mothers_shift_the_food_need() -> void:
	var run := _run()
	var before := run.food_needed_today()
	var per := run.content.num("food_per_person_per_day")
	var u := run.world.folk_ai.add_folk("tribesperson")
	u.boons.append("many_mother")
	check(run.food_needed_today() >= before + int(floor(2.0 * per)), "she eats for two (%d -> %d)" % [before, run.food_needed_today()])


func test_a_seer_adds_a_dawn_card_and_never_works() -> void:
	var run := _run()
	run.people.offer_picks()
	var usual := run.pick_offer.filter(func(c: Dictionary) -> bool: return c["kind"] != "spell").size()
	var seer := run.world.folk_ai.add_folk("tribesperson")
	seer.boons.append("hollow_seer")
	run.people.offer_picks()
	check_eq(run.pick_offer.filter(func(c: Dictionary) -> bool: return c["kind"] != "spell").size(), usual + 1, "one more card")
	run.choose_pick(-1)
	seer.pos = Vector2(150, 0)
	for i in 60:
		run.world.folk_ai.begin_step()
		run.world.folk_ai.folk_tick(seer)
	check_eq(seer.task, "", "the seer takes no task")
	check(seer.pos.distance_to(seer.home) < seer.pos.distance_to(Vector2(150, 0)) or seer.pos.distance_to(seer.home) < 10.0,
		"and walks home")


func test_the_bloodsworn_burn_out_after_three_rounds() -> void:
	var run := _run()
	var u := run.world.folk_ai.add_folk("warrior")
	u.boons.append("bloodsworn")
	run.world.folk_ai.apply_folk_stats(u)
	check(is_equal_approx(u.attack, (float(run.content.townsfolk["warrior"]["attack"]) + run.mod("warrior_attack")
		+ run.tool_bonus("warrior", "attack")) * 1.6), "60% harder")
	u.joined_round = run.round_number
	run.round_number += 1
	run.people.spend_bloodsworn()
	check(run.world.folk.has(u), "still standing after their second round")
	run.round_number += 1
	run.people.spend_bloodsworn()
	check(not run.world.folk.has(u), "laid to rest after their third")


func test_a_mother_of_many_brings_kin_while_there_is_room() -> void:
	var run := _run()
	var u := run.world.folk_ai.add_folk("tribesperson")
	u.boons.append("many_mother")
	var joined := 0
	for i in 20:
		run.round_number = i + 1
		var before := run.world.folk.size()
		if run.population() >= run.housing():
			break
		run.people._kin_join()
		joined += run.world.folk.size() - before
	check(joined > 0, "kin walked in (%d)" % joined)
	check(run.population() <= run.housing(), "never past the beds")


func test_ember_born_burn_fuel_at_night() -> void:
	var run := _run()
	var before := run.fuel_needed_tonight()
	var u := run.world.folk_ai.add_folk("craftsperson")
	u.boons.append("ember_born")
	check(run.fuel_needed_tonight() >= before + 1, "a fuel more")
