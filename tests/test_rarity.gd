extends TestCase
## Four rarities (data/rarity.json) colour items, relics and dawn cards; each reads its own data.


func _content() -> Content:
	return Content.load_default()


func test_item_rarity_follows_its_affixes() -> void:
	var c := _content()
	check_eq(Loot.rarity(c, Loot.make("flint_blade", 1)), "white", "no affix is base")
	check_eq(Loot.rarity(c, Loot.make("flint_blade", 1, ["keen"])), "blue", "one affix is magic")
	check_eq(Loot.rarity(c, Loot.make("flint_blade", 1, ["keen", "sturdy"])), "yellow", "two affixes are powerful")
	check_eq(Loot.rarity(c, Loot.make("flint_blade", 1, ["earthborn"])), "orange", "earthborn finds are mythic")


func test_earth_finds_are_mythic() -> void:
	var c := _content()
	var item := Loot.earth_find(c, SeededRng.stream(7, "find", 1), 6)
	check_eq(Loot.rarity(c, item), "orange", "an earth find is orange")


func test_pacts_are_mythic_and_every_relic_rarity_is_known() -> void:
	var c := _content()
	for id: String in c.relics:
		var r := c.rarity_of("relic", id)
		check(c.rarity["order"].has(r), "%s has a known rarity (%s)" % [id, r])
		if c.has_tag("relic", id, "pact"):
			check_eq(r, "orange", "pact %s is orange" % id)
	check_eq(c.rarity_of("relic", "war_paint"), "white", "a plain number relic is white")


func test_dawn_cards_take_their_rarity_from_their_data() -> void:
	var run := RunState.new(_content(), 4821)
	var people := run.people
	check_eq(people.card_rarity({"kind": "folk", "role": "tribesperson", "leaning": "forager", "cost": 0}), "white", "a tribesperson is white")
	check_eq(people.card_rarity({"kind": "family", "role": "family", "cost": 0, "roles": []}), "blue", "a family is blue")
	check_eq(people.card_rarity({"kind": "promote", "role": "champion", "cost": 0}), "orange", "knighting is orange")
	check_eq(people.card_rarity({"kind": "spell", "role": "spell", "cost": 0, "spell": "sink_den"}), "orange", "sinking a den is orange")
	var hero := people.make_hero(true)
	check_eq(people.card_rarity({"kind": "hero", "role": "hero", "cost": 0, "hero": hero}), run.content.rarity_of("hero", hero.type_id), "a hero card is its class's rarity")


func test_rarer_odds_climb_through_the_run() -> void:
	var c := _content()
	var last := c.int_num("rounds_to_win")
	check_eq(c.rarity_odds("white", 1), 1.0, "white is always full odds")
	check_eq(c.rarity_odds("orange", 1), c.rarity_weight("orange"), "round 1 uses the plain weight")
	check(c.rarity_odds("orange", last) > c.rarity_odds("orange", 1), "mythic odds climb by the last round")
	check(c.rarity_odds("orange", last) < c.rarity_odds("yellow", last), "mythic stays rarer than powerful")


func test_drops_roll_rarity_and_mythics_are_named_uniques() -> void:
	var c := _content()
	var counts := {}
	var early_mythic := 0
	for i in 2000:
		var item := Loot.roll(c, SeededRng.stream(11, "drop", i), 9, "medieval")
		var r := Loot.rarity(c, item)
		counts[r] = int(counts.get(r, 0)) + 1
		if r == "orange":
			check_eq(item["affixes"].size(), 0, "a unique comes as it is")
			check_eq(c.rarity_of("item", item["base"]), "orange", "a mythic drop is a unique base")
		elif c.rarity_of("item", item["base"]) == "orange":
			check(false, "a unique base only drops as mythic")
		if Loot.rarity(c, Loot.roll(c, SeededRng.stream(11, "early", i), 1, "neolithic")) == "orange":
			early_mythic += 1
	check(int(counts.get("white", 0)) > int(counts.get("blue", 0)), "white drops most")
	check(int(counts.get("blue", 0)) > int(counts.get("yellow", 0)), "then blue")
	check(int(counts.get("yellow", 0)) > int(counts.get("orange", 0)), "then yellow")
	check(int(counts.get("orange", 0)) > 0, "mythic uniques do drop (%s)" % counts)
	check_eq(early_mythic, 0, "no mythic drops before mythic_from_round")


func test_uniques_respect_the_age() -> void:
	var c := _content()
	for i in 300:
		var item := Loot.mythic(c, SeededRng.stream(3, "m", i), 9, "neolithic")
		check(not c.items["bases"][item["base"]].has("age"), "no bronze or medieval unique in the stone age")


func test_a_legend_hero_card_comes_levelled_with_a_mythic_item() -> void:
	var run := RunState.new(_content(), 4821)
	run.begin_round()
	run.round_number = 12
	var hero := run.people.make_hero(true)
	# A legend is the orange roll of a hero card (sim/card_roll.gd).
	var card := {"kind": "hero", "role": "hero", "cost": 10, "hero": hero, "roll": "orange", "boons": ["legend"]}
	run.people._shape_hero(card, SeededRng.stream(5, "legend", 0))
	check(card.get("legend", false), "the orange hero roll is a legend")
	check_eq(hero.level, 1 + run.content.int_num("legend_levels"), "a legend is a few levels up")
	check_eq(int(card["cost"]), 10 + run.content.int_num("legend_cost"), "and costs more")
	check(hero.items.values().any(func(it: Dictionary) -> bool: return Loot.rarity(run.content, it) == "orange"), "and carries a mythic item")
	check_eq(CardRoll.roll_of(card), "orange", "its card is orange")


func test_relic_offers_draw_rarer_relics_less_often() -> void:
	var counts := {}
	for s in 300:
		var run := RunState.new(_content(), 1000 + s)
		run.round_number = 6
		for id in run._roll_relic_offer():
			var r := run.content.rarity_of("relic", id)
			counts[r] = int(counts.get(r, 0)) + 1
	check(int(counts.get("white", 0)) > int(counts.get("orange", 0)), "white relics come up more than mythic ones (%s)" % counts)
	check(int(counts.get("orange", 0)) > 0, "mythic relics do come up by round 6")
