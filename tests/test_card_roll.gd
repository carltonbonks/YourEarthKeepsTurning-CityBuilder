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
				check(card["kind"] != "promote", "promotions don't roll")
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


# --- Slice 2: hero, spell, family, venture and trade cards --------------------------------

func test_every_dawn_card_kind_can_roll() -> void:
	var c := Content.load_default()
	var rng := SeededRng.new(9)
	var kinds := {"hero": {"weapon": true}, "spell": {"spell": "ridge", "nights": 2}, "family": {}, "venture": {}, "trade": {"give": true, "get": true}}
	for kind: String in kinds:
		var seen := {}
		for i in 6000:
			var card := {}
			CardRoll.roll_card(c, rng, card, kind, kinds[kind], 14)
			if card.has("roll"):
				seen[card["roll"]] = true
				for id: String in card["boons"]:
					check(CardRoll.fits_card(c.card_mods[id], kind, kinds[kind]), "%s fits a %s card" % [id, kind])
				if card["roll"] == "orange":
					check_eq(card["boons"].size(), 1, "orange is one")
				elif card["roll"] == "yellow":
					check(card["boons"].size() >= 2, "yellow is a powerful one and a blue one")
		check(seen.has("blue") and seen.has("yellow") and seen.has("orange"), "%s cards roll every rarity (%s)" % [kind, seen.keys()])


func test_modifiers_only_fit_cards_that_can_use_them() -> void:
	var c := Content.load_default()
	check(not CardRoll.fits_card(c.card_mods["well_armed"], "hero", {"weapon": false}), "no better weapon without a weapon")
	check(not CardRoll.fits_card(c.card_mods["hastened"], "spell", {"spell": "wake", "nights": 1}), "a one-night spell can't be sooner")
	check(not CardRoll.fits_card(c.card_mods["deep_working"], "spell", {"spell": "sink_den", "nights": 3}), "only a ridge lasts longer")
	check(not CardRoll.fits_card(c.card_mods["bulk"], "trade", {"give": true, "get": false}), "no bulk on a service")
	check(not CardRoll.fits_card(c.card_mods["exile"], "family", {}), "exiles are given, never dealt")


func test_a_rolled_hero_card_shows_the_hero_as_they_arrive() -> void:
	var run := _run()
	var hero := run.people.make_hero(true)
	var level := hero.level
	var card := {"kind": "hero", "role": "hero", "cost": 25, "hero": hero, "roll": "yellow", "boons": ["war_tested", "cheap_hire"]}
	run.people._shape_hero(card, SeededRng.new(1))
	check_eq(hero.level, level + 2, "two levels up")
	check_eq(card["cost"], 15, "10 shells cheaper")
	var dog := run.people.make_hero(true)
	var dog_card := {"kind": "hero", "role": "hero", "cost": 25, "hero": dog, "roll": "blue", "boons": ["houndmaster"]}
	run.people._shape_hero(dog_card, SeededRng.new(1))
	check(dog.hound, "arrives with a hound")


func test_a_hastened_spell_is_done_a_night_sooner_and_an_echo_rests_the_geomancer() -> void:
	var run := _run()
	run.world.add_building("geomancer")
	run.world.buildings[-1]["work_left"] = 0.0
	run.cast_spell("ridge", {"roll": "blue", "boons": ["hastened"]})
	check_eq(int(run.spell["nights_left"]), 1, "one night instead of two")
	run.spell = {}
	run.cast_spell("wake", {"roll": "orange", "boons": ["echoing"]})
	run._work_spell()
	check(run.spell.is_empty(), "done")
	check_eq(run.record.entry["card_mods_fired"], {"echoing": 1}, "it echoed")
	check(not run.can_cast(), "the geomancer is spent")
	run.round_number += 3
	check(run.can_cast(), "and casts again after two rounds")


func test_a_rolled_family_brings_more_and_marks() -> void:
	var run := _run()
	run.stock["wood"] = 0
	var card := {"kind": "family", "role": "family", "cost": 0, "roles": ["tribesperson", "warrior"], "roll": "yellow",
		"boons": ["gifted_kin", "big_family", "dowry"]}
	check_eq(run.people.card_people(card), 3, "one more")
	var before := run.world.folk.size()
	check_eq(run.people.settle_family(card), 3, "three arrive")
	var arrived := run.world.folk.slice(before)
	check(arrived.all(func(u: Unit) -> bool: return u.mark != ""), "every one with a mark")
	check_eq(int(run.stock["wood"]), 10, "and a dowry")
	var exiles := {"kind": "family", "role": "family", "cost": 0, "roles": ["tribesperson"], "roll": "orange", "boons": ["exiles"]}
	before = run.world.folk.size()
	run.people.settle_family(exiles)
	check_eq(run.world.folk.size() - before, 4, "exiles: three more")
	check(run.world.folk.slice(before).all(func(u: Unit) -> bool: return u.boons.has("exile")), "who all eat more")


func test_rolled_ventures_bring_more_or_lose_everyone() -> void:
	var run := _run()
	var id: String = run.content.ventures.keys()[0]
	var plain := run.people.venture_terms(id)
	var rich := run.people.venture_terms(id, {"roll": "blue", "boons": ["rich_find"]})
	var good: String = plain["goods"].keys()[0]
	check(int(rich["goods"][good]) > int(plain["goods"][good]), "a rich find brings more")
	var cursed := run.people.venture_terms(id, {"roll": "orange", "boons": ["cursed_road"]})
	check_eq(cursed["lose"], [cursed["send"], cursed["send"]], "nobody comes home from a cursed road")
	check(int(cursed["goods"][good]) >= 3 * int(plain["goods"][good]) - 1, "but it brings three times as much")


func test_rolled_trade_deals_change_price_and_goods() -> void:
	var run := _run()
	var c := run.caravan
	check_eq(c.gives("timber_load", {"roll": "blue", "boons": ["bargain"]}), {"shells": 32}, "a fifth off 40")
	check_eq(int(c.gets("timber_load", {"roll": "blue", "boons": ["bulk"]})["wood"]), int(c.gets("timber_load")["wood"] * 1.5),
		"half again the wood")
	check_eq(c.gives("timber_load", {"roll": "orange", "boons": ["cursed_gold"]}), {"shells": 0}, "cursed gold is free")
	check_eq(c.folk_count("timber_load", {"roll": "yellow", "boons": ["escorted", "bulk"]}), 1, "an escort stays on")


func test_a_smugglers_hoard_grows_the_attack_and_cursed_gold_turns_a_hero() -> void:
	var run := _run()
	run.caravan.offers = [{"deal": "timber_load", "need": "", "taken": false, "roll": "orange", "boons": ["smugglers_hoard"]},
		{"deal": "dressed_stone", "need": "", "taken": false, "roll": "orange", "boons": ["cursed_gold"]}]
	run.stock["shells"] = 100
	run.phase = RunState.Phase.BUILD
	var wave := run.next_wave.size()
	check(wave > 0, "an attack is planned")
	check(run.caravan.take(0), "take the hoard")
	check(run.next_wave.size() > wave, "the attack grew (%d -> %d)" % [wave, run.next_wave.size()])
	for h in run.living_heroes():
		h.trait_id = "brave"
	check(run.caravan.take(1), "take the cursed gold")
	check(run.living_heroes().any(func(h: Unit) -> bool: return h.trait_id == "greedy"), "a hero turned greedy")
	check_eq(run.record.entry["deals"][0]["mods"], ["smugglers_hoard"], "the record keeps the deal's modifiers")


func test_a_lingering_deal_waits_one_round() -> void:
	var run := _run()
	run.world.add_building(run.content.trades["needs"])
	run.world.buildings[-1]["work_left"] = 0.0
	run.caravan.offers = [{"deal": "timber_load", "need": "", "taken": false, "roll": "blue", "boons": ["lingering"]}]
	run.round_number += 1
	run.caravan.lay_out()
	check(run.caravan.offers.any(func(o: Dictionary) -> bool: return o["deal"] == "timber_load" and o.get("lingered", false)),
		"still on offer")
	check_eq(run.caravan.offers.filter(func(o: Dictionary) -> bool: return o["deal"] == "timber_load").size(), 1, "once")
	run.round_number += 1
	run.caravan.lay_out()
	check(not run.caravan.offers.any(func(o: Dictionary) -> bool: return o["deal"] == "timber_load" and o.get("lingered", false)),
		"only for one round")


# Slice 3: blueprint and upgrade offers roll, and a drafted roll changes the building for the run.

func test_building_modifiers_only_fit_buildings_that_have_what_they_change() -> void:
	var c := Content.load_default()
	var b := c.buildings
	check(CardRoll.fits_building(c.card_mods["thrifty"], b["watch_post"]), "any building can be thrifty")
	check(CardRoll.fits_building(c.card_mods["roomy"], b["longhouse"]), "a longhouse can be roomy")
	check(not CardRoll.fits_building(c.card_mods["roomy"], b["watch_post"]), "a watch post can't")
	check(CardRoll.fits_building(c.card_mods["wrathful"], b["watch_post"]), "a watch post can be wrathful")
	check(not CardRoll.fits_building(c.card_mods["wrathful"], b["gate"]), "a gate has no attack")
	check(not CardRoll.fits_building(c.card_mods["twin_built"], b["longhouse"]), "only one longhouse, so no twin")
	check(not CardRoll.fits_building(c.card_mods["bloodwood"], b["watch_post"]), "bloodwood needs room, benches or harvest")
	var rng := SeededRng.new(9)
	var seen := {}
	for i in 3000:
		var card := {"building": "knapper"}
		CardRoll.roll_building(c, rng, card, "blueprint", "knapper", 14)
		seen[CardRoll.roll_of(card)] = true
		for id: String in card.get("boons", []):
			check(CardRoll.fits_building(c.card_mods[id], b["knapper"]), "%s fits a knapper" % id)
			check(c.card_mods[id]["cards"].has("blueprint"), "%s comes on blueprints" % id)
	check(seen.has("blue") and seen.has("yellow") and seen.has("orange"), "every rarity turns up (%s)" % seen.keys())


func test_a_drafted_roll_changes_the_building_for_the_run() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var b := run.content.buildings
	CardRoll.apply_to_building(run, "watch_post", {"roll": "yellow", "boons": ["thrifty", "sturdy", "hearthstone"]})
	check_eq(b["watch_post"]["cost"], {"wood": 7, "stone": 2}, "15% off, never below 1")
	check(is_equal_approx(float(b["watch_post"]["tower_hp"]), 84.0), "40% sturdier")
	check(is_equal_approx(float(b["watch_post"]["hearth_hp"]), 15.0), "hearthstone is granted")
	check(not b["watch_post"].has("gate_hp"), "sturdy adds no gate to a post")
	CardRoll.apply_to_building(run, "shrine", {"roll": "orange", "boons": ["wellspring"]})
	check_eq(b["shrine"]["cost"], {"wood": 0, "stone": 0}, "a wellspring costs nothing")
	check(is_equal_approx(float(b["shrine"]["effects"]["near_wake"]), 3.0), "and draws the earth's waking")
	CardRoll.apply_to_building(run, "longhouse", {"roll": "blue", "boons": ["roomy"]})
	check_eq(int(b["longhouse"]["lodging"]["beds"]), 4, "a bed more")
	check_eq(int(b["longhouse"]["housing"]), 3, "and room for one more")
	check_eq(int(Content.load_default().buildings["longhouse"]["lodging"]["beds"]), 3, "only this run changes")


func test_drafting_a_rolled_blueprint_keeps_its_roll() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var card: Dictionary = run.hand.cards[0]
	var type: String = card["building"]
	var cost: Dictionary = run.content.buildings[type]["cost"].duplicate()
	card["roll"] = "blue"
	card["boons"] = ["thrifty"]
	check(run.hand.draft(type), "drafted")
	check_eq(run.hand.rolled[type]["boons"], ["thrifty"], "the hand keeps the roll")
	for r: String in cost:
		check(int(run.content.buildings[type]["cost"][r]) <= int(cost[r]), "%s costs less %s" % [type, r])
	var entry: Dictionary = run.record.entry["blueprints"][-1]
	check_eq(entry["roll"], "blue", "the record keeps the roll")
	check_eq(entry["mods"], ["thrifty"], "and its modifiers")


func test_twin_built_raises_a_free_one() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.hand.cards = [{"building": "watch_post", "need": "", "roll": "yellow", "boons": ["twin_built", "thrifty"]}]
	var wood := int(run.stock["wood"])
	check(run.hand.draft("watch_post"), "drafted")
	check_eq(run.world.count_buildings("watch_post", false), 1, "one goes up at once")
	check_eq(int(run.stock["wood"]), wood, "for free")


func test_a_rolled_upgrade_changes_its_building_too() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.world.add_building("hut")
	run.hand.upgrade_offers = [{"upgrade": "sturdy_huts", "roll": "blue", "boons": ["snug"]}]
	var fuel := float(run.content.buildings["hut"]["fuel"])
	check(run.hand.draft_upgrade("sturdy_huts"), "taken")
	check(is_equal_approx(float(run.content.buildings["hut"]["fuel"]), fuel * 0.5), "huts burn half the fuel")
	check_eq(int(run.content.buildings["hut"]["housing"]), 4, "and the upgrade itself still applies")
	var action: Dictionary = run.record.entry["actions"].filter(func(a: Dictionary) -> bool: return a["kind"] == "upgrade")[0]
	check_eq(action["mods"], ["snug"], "the record keeps the upgrade's modifiers")


func test_draft_offers_roll_and_the_record_keeps_their_rolls() -> void:
	var rolled := 0
	for s in 40:
		var run := RunState.new(Content.load_default(), 100 + s)
		for c in run.hand.cards:
			if c.has("roll"):
				rolled += 1
				check(c["boons"].size() >= 1, "a rolled offer has modifiers")
		check_eq(run.hand.rolls().size(), run.hand.labels().size(), "a roll for every offer")
	check(rolled > 0, "some offers roll over 40 runs (%d)" % rolled)


func test_wrathful_towers_draw_every_raider() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	CardRoll.apply_to_building(run, "watch_post", {"roll": "orange", "boons": ["wrathful"]})
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	check(run.build("watch_post"), "a watch post")
	var post := run.world.buildings.size() - 1
	run.world.buildings[post]["work_left"] = 0.0
	run.world.enemies.clear()
	var knight := run.world.enemy_ai.make_enemy("hollow_knight", Vector2.ZERO, 0.0)
	knight.hp = 999.0
	run.world.enemies.append(knight)
	run.world.buildings[post]["cooldown_left"] = 0.0
	knight.pos = Vector2(run.world.buildings[post]["pos"]) + Vector2(60, 0)
	run.world.enemy_ai.towers_tick()
	check_eq(knight.target_tower, post, "even a hollow knight turns on a wrathful tower")
	check(is_equal_approx(float(run.content.buildings["watch_post"]["attack"]),
		3.0 * float(Content.load_default().buildings["watch_post"]["attack"])), "and it hits three times as hard")
