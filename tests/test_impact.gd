extends TestCase
## Who did what: each round's "impact" tallies damage dealt and taken, kills, losses and work for heroes,
## each kind of townsfolk and the defences (RunRecord.note_impact / note_blow), shown by ImpactView.


func _round_run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	return run


func _impact(run: RunState) -> Dictionary:
	return run.record.entry["impact"]


func test_blows_count_only_the_health_they_took() -> void:
	var run := _round_run()
	var w := run.world
	var warrior := w.folk_ai.add_folk("warrior")
	var raider := w.enemy_ai.make_enemy("raider", Vector2.ZERO, 0.0)
	raider.hp = 10.0
	w.enemies.append(raider)
	w.damage(warrior, raider, 4.0)
	w.damage(warrior, raider, 50.0)
	var row: Dictionary = _impact(run)["folk"]["warrior"]
	check_eq(float(row["dealt"]), 10.0, "overkill doesn't count: 4 then the 6 left")
	check_eq(float(row["kills"]), 1.0, "the kill is the warrior's")
	w.damage(raider, warrior, warrior.hp + 100.0)
	check_eq(float(row["taken"]), float(run.content.townsfolk["warrior"]["hp"]), "taken is at most the health it had")
	check_eq(float(row["lost"]), 1.0, "a townsperson who dies counts as lost")


func test_heroes_and_the_hearth_have_their_own_rows() -> void:
	var run := _round_run()
	var w := run.world
	var hero: Unit = run.people.make_hero()
	var raider := w.enemy_ai.make_enemy("raider", Vector2(30, 0), 0.0)
	raider.hp = 999.0
	w.enemies.append(raider)
	w.damage(hero, raider, 7.0)
	w.damage(raider, hero, 3.0)
	var row: Dictionary = _impact(run)["heroes"][hero.display_name]
	check_eq(float(row["dealt"]), 7.0, "the hero's blow")
	check_eq(float(row["taken"]), 3.0, "the blow the hero took")
	check_eq(row["class"], hero.type_id, "the row knows the hero's class")
	w.hearth_cooldown_left = 0.0
	w.enemy_ai.towers_tick()
	check(float(_impact(run)["defences"]["hearth"]["dealt"]) > 0.0, "the hearth's own shots count for the hearth")


func test_a_bot_round_records_rounded_impact() -> void:
	var record := bot_record(4821, "balanced")
	var any_goods := false
	var any_hero_dealt := false
	for rd: Dictionary in record["rounds"]:
		check(rd.has("impact"), "every round has its impact")
		for group: String in rd["impact"]:
			for who: String in rd["impact"][group]:
				var row: Dictionary = rd["impact"][group][who]
				for stat: String in row:
					if stat != "class" and stat != "goods":
						check(row[stat] is int, "%s is a whole number" % stat)
		for who: String in rd["impact"].get("folk", {}):
			if not rd["impact"]["folk"][who].get("goods", {}).is_empty():
				any_goods = true
		for who: String in rd["impact"].get("heroes", {}):
			if int(rd["impact"]["heroes"][who].get("dealt", 0)) > 0:
				any_hero_dealt = true
	check(any_goods, "townsfolk bring goods home")
	check(any_hero_dealt, "heroes deal damage")


func test_delivered_goods_never_exceed_gathered() -> void:
	var record := bot_record(4821, "balanced")
	for rd: Dictionary in record["rounds"]:
		var brought := {}
		for who: String in rd["impact"].get("folk", {}):
			var goods: Dictionary = rd["impact"]["folk"][who].get("goods", {})
			for good: String in goods:
				brought[good] = int(brought.get(good, 0)) + int(goods[good])
		for good: String in brought:
			# Loads picked up late in the round before can land this round, so allow one round's slack of a few loads.
			check(int(brought[good]) <= int(rd.get("gathered", {}).get(good, 0)) + 40,
				"round %d: %s brought home is about what was gathered" % [rd["round"], good])


func test_whole_run_adds_rounds_up() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.record.rounds = [
		{"round": 1, "impact": {"folk": {"tribesperson": {"dealt": 5, "goods": {"wood": 10}}}}},
		{"round": 2, "impact": {"folk": {"tribesperson": {"dealt": 2, "goods": {"wood": 3, "stone": 4}}},
			"heroes": {"Ash": {"class": "hunter", "kills": 2}}}},
	]
	run.record.entry = {}
	var all := ImpactView.whole_run(run)
	check_eq(all["folk"]["tribesperson"]["dealt"], 7, "damage adds up")
	check_eq(all["folk"]["tribesperson"]["goods"], {"wood": 13, "stone": 4}, "goods add up by kind")
	check_eq(all["heroes"]["Ash"]["class"], "hunter", "class carries over")
	check(ImpactView.headline(run, all).begins_with("Hardest hitter: Tribesperson"), "headline names the hardest hitter")
	check_eq(ImpactView.work_text({"goods": {"wood": 3, "stone": 9}, "made": 2, "raised": 1}),
		"brought 9 stone, 3 wood · made 2 · raised 1 building", "work in a few words")
