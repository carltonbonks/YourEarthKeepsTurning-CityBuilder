extends TestCase
## Run paths (data/paths.json): a tradition starts its path, age-ups bring charters, each tier I changes the run;
## and trades guilds: a band at its top tier can be chartered at dawn, keeps to its trade and spares its nodes.


func _run(traditions: Array = [], seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	run.choose_traditions(traditions)
	return run


func test_a_tradition_starts_its_path() -> void:
	var run := _run(["hunters"])
	check_eq(run.path_tier("heroes"), 1, "hunters start on the heroes path")
	check_eq(run.paths.size(), 1, "and only that one")
	check(_run([]).paths.is_empty(), "no tradition, no path")
	for id: String in run.content.traditions:
		check(run.content.paths["paths"].has(run.content.traditions[id].get("path", "")), "%s names a path" % id)
	check_eq(run.to_record()["paths"], {"heroes": 1}, "the record keeps the paths")


func test_path_effects_count_like_relics() -> void:
	var run := _run(["traders"])
	check_eq(run.mod("income"), 10.0, "traders' 5 shells plus the trade path's 5")
	check(run.caravan.is_here(), "the trade path brings the caravan before its building")
	check(not _run(["hunters"]).caravan.is_here(), "without it the caravan waits for the moot")


func test_trade_path_lays_out_deals_from_round_one() -> void:
	var run := _run(["traders"])
	run.caravan.lay_out()
	check(not run.caravan.offers.is_empty(), "deals on offer in round 1")


func _dawn(run: RunState) -> Array[Dictionary]:
	if run.phase == RunState.Phase.BUILD:
		run.begin_round()
	return run.pick_offer


func test_warband_always_deals_a_warrior() -> void:
	for s in 12:
		var run := _run(["stoneworkers"], 300 + s)
		check(_dawn(run).any(func(c: Dictionary) -> bool: return c["role"] == "warrior"), "seed %d: a warrior card at dawn" % (300 + s))
		run.dispose()


func test_warband_warriors_eat_half() -> void:
	var run := _run([])
	for i in 4:
		run.world.folk_ai.add_folk("warrior")
	var plain := run.food_needed_today()
	run.paths["warband"] = 1
	check(run.food_needed_today() < plain, "four warriors eat less on the warband path (%d vs %d)" % [run.food_needed_today(), plain])


func test_warband_patrols_pair_up_sooner() -> void:
	var run := _run([])
	run.begin_round()
	run.choose_pick(-1)
	for u in run.world.folk.filter(func(f: Unit) -> bool: return f.type_id == "warrior"):
		run.world.folk.erase(u)
	for i in 3:
		run.world.folk_ai.add_folk("warrior")
	run.world.folk_ai.begin_step()
	var alone := run.world.folk_ai.patrol_group_size()
	run.paths["warband"] = 1
	check(run.world.folk_ai.patrol_group_size() > alone, "three warriors pair up on the warband path (%d vs %d)" % [
		run.world.folk_ai.patrol_group_size(), alone])


func test_guilds_deal_one_more_card_and_a_tribesperson() -> void:
	for s in 12:
		var plain := _run([], 500 + s)
		var guilds := _run(["woodfolk"], 500 + s)
		var a := _dawn(plain).size()
		var b := _dawn(guilds)
		check_eq(b.size(), a + 1, "seed %d: one more dawn card" % (500 + s))
		check(b.any(func(c: Dictionary) -> bool: return c["role"] == "tribesperson"), "seed %d: a tribesperson among them" % (500 + s))
		plain.dispose()
		guilds.dispose()


func test_guilds_band_every_leaning_sooner_but_not_twice() -> void:
	var run := _run(["woodfolk"])
	var folk := run.world.folk_ai
	check_eq(folk.band_level("tribesperson", "forager", 2), 1, "two foragers band on the Guilds path")
	check_eq(folk.band_level("tribesperson", "woodcutter", 1), 0, "woodfolk's own woodcutters still need two, not one")


func test_heroes_path_deals_a_hero_once_they_have_beds() -> void:
	var run := _run(["hunters"])
	run.build("tavern")
	for b in run.world.buildings:
		b["work_left"] = 0.0
	run.on_building_done("tavern")
	check(_dawn(run).any(func(c: Dictionary) -> bool: return c["kind"] == "hero"), "a hero card at dawn")


func test_path_buildings_come_up_more_often() -> void:
	var plain := 0
	var favoured := 0
	var shaping := ["training_yard", "kennel", "duel_ring", "trophy_hall", "warden_hut", "gibbet_post", "hunting_lodge", "tavern", "shrine"]
	for s in 60:
		var a := _run([], 2000 + s)
		plain += a.hand.cards.filter(func(c: Dictionary) -> bool: return shaping.has(c["building"])).size()
		a.dispose()
		var b := _run([], 2000 + s)
		b.paths["heroes"] = 1
		b.hand.deal()
		favoured += b.hand.cards.filter(func(c: Dictionary) -> bool: return shaping.has(c["building"])).size()
		b.dispose()
	check(favoured > plain, "the heroes path is dealt its buildings more often (%d vs %d in 60 hands)" % [favoured, plain])


func test_an_age_up_brings_a_charter_at_the_next_build() -> void:
	var run := _run(["hunters"])
	run.on_building_done("bronze_moot")
	check_eq(run.charters_due, 1, "one charter owed")
	check(not run.awaiting_charter(), "not this build phase")
	run._roll_charter()
	check(run.awaiting_charter(), "offered once dealt (at the next build)")
	check_eq(run.charter_offer.size(), 3, "three paths offered")
	check_eq(run.charter_offer[0], "heroes", "the town's own path's next tier comes first")
	var pick := run.charter_offer[1]
	run.choose_charter(pick)
	check_eq(run.path_tier(pick), 1, "the charter adds the path")
	check_eq(run.charters_due, 0, "nothing more owed")
	check(not run.awaiting_charter(), "and the screen goes")
	var charter: Array = run.record.entry["actions"].filter(func(a: Dictionary) -> bool: return a["kind"] == "charter")
	check_eq(charter.size(), 1, "the record keeps the charter")
	check_eq(charter[0]["path"], pick, "with the path taken")


func test_a_path_at_its_last_tier_is_not_offered() -> void:
	var run := _run(["hunters"])
	run.paths["heroes"] = run.content.paths["paths"]["heroes"]["tiers"].size()
	run.charters_due = 1
	run._roll_charter()
	check(not run.charter_offer.has("heroes"), "a path held at its last tier isn't offered again")
	run.choose_charter("heroes")
	check_eq(run.path_tier("heroes"), run.content.paths["paths"]["heroes"]["tiers"].size(), "nor raised past it")


func test_every_tier_ii_names_its_cost() -> void:
	var paths: Dictionary = Content.load_default().paths["paths"]
	for id: String in paths:
		check(paths[id]["tiers"].size() >= 2, "%s has a tier II" % id)
		check("Cost:" in str(paths[id]["tiers"][1]["text"]), "%s II says what it costs" % id)


func test_charters_are_seeded() -> void:
	var a := _run([], 77)
	var b := _run([], 77)
	for run in [a, b]:
		run.charters_due = 1
		run._roll_charter()
	check_eq(a.charter_offer, b.charter_offer, "the same seed offers the same charter")


func test_the_bot_takes_charters() -> void:
	var record := TestCase.bot_record(4821, "medieval")
	var charters := 0
	for rd: Dictionary in record["rounds"]:
		charters += rd.get("actions", []).filter(func(a: Dictionary) -> bool: return a["kind"] == "charter").size()
	var ages := (record.get("age_rounds", {}) as Dictionary).size()
	check(charters >= mini(ages, 1), "a charter for each age-up the bot reached before its last build (%d for %d ages)" % [charters, ages])


# --- Trades guilds ---------------------------------------------------------------

func _band_run(leaning: String, n: int) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	for i in n:
		run.world.folk_ai.add_folk("tribesperson", leaning)
	run.world.folk_ai.begin_step()
	return run


func test_a_full_band_is_offered_a_guild() -> void:
	check_eq(_band_run("woodcutter", 3).people.guild_ready(), "", "a band of three isn't ready")
	var run := _band_run("woodcutter", 6)
	check_eq(run.people.guild_ready(), "woodcutter", "a band of six is")
	var card := run.people.guild_card()
	check_eq(card["kind"], "guild", "as a guild card")
	run.guilds["woodcutter"] = 1
	check_eq(run.people.guild_ready(), "", "once chartered it isn't offered again")


func test_the_guild_card_comes_at_dawn_and_charters() -> void:
	var run := _band_run("woodcutter", 6)
	run.run_until_pause()
	while run.phase != RunState.Phase.PICK and not run.is_over():
		if run.phase == RunState.Phase.RELIC:
			run.choose_relic("")
		elif run.phase == RunState.Phase.BUILD:
			run.begin_round()
		else:
			run.run_until_pause()
	var at := -1
	for i in run.pick_offer.size():
		if run.pick_offer[i]["kind"] == "guild":
			at = i
	check(at >= 0, "the next dawn offers the guild")
	check(run.can_take_pick(at), "it needs no bed")
	var people := run.population()
	run.choose_pick(at)
	check(run.guilds.has("woodcutter"), "taking it charters the woodcutters' guild")
	check_eq(run.population(), people, "and brings nobody")
	check_eq(run.to_record()["guilds"].keys(), ["woodcutter"], "the record keeps it")


func test_guild_members_keep_to_their_trade() -> void:
	var run := _band_run("forager", 6)
	var w := run.world
	var forager: Unit = w.folk.filter(func(u: Unit) -> bool: return u.leaning == "forager")[0]
	run.stock["food"] = 999
	run.stock["wood"] = 0
	var before := w.folk_ai.plan_trip(forager)
	check(before >= 0 and w.nodes[before]["gives"] != "food", "with food piled up, a plain forager fetches something else")
	run.guilds["forager"] = 1
	var after := w.folk_ai.plan_trip(forager)
	check(after < 0 or w.nodes[after]["gives"] == "food", "a guild forager only fetches food")


func test_a_tending_guild_regrows_what_it_cuts() -> void:
	var run := _band_run("woodcutter", 6)
	var w := run.world
	run.guilds["woodcutter"] = 1
	var cutter: Unit = w.folk.filter(func(u: Unit) -> bool: return u.leaning == "woodcutter")[0]
	var i := -1
	for k in w.nodes.size():
		if w.nodes[k]["gives"] == "wood" and int(w.nodes[k]["max"]) >= 10:
			i = k
			break
	var node := w.nodes[i]
	node["amount"] = 2
	var took := w.folk_ai._guild_drain(cutter, node, 2)
	check_eq(took, 2, "woodcutters take their whole haul")
	node["amount"] = 0
	check(float(node.get("guild_tend", 0.0)) > 0.0, "and mark the grove to regrow")
	w._tend_nodes()
	check(int(node["amount"]) >= roundi(int(node["max"]) * 0.15), "at dawn it regrows 15%% of its size (%d of %d)" % [node["amount"], node["max"]])
	check(int(run.record.entry.get("guild_tended", {}).get("wood", 0)) > 0, "the record counts it")


func test_a_gentle_guild_drains_slower() -> void:
	var run := _band_run("quarrier", 6)
	var w := run.world
	run.guilds["quarrier"] = 1
	var cutter: Unit = w.folk.filter(func(u: Unit) -> bool: return u.leaning == "quarrier")[0]
	var node := {"gives": "stone", "amount": 100, "max": 100}
	var taken := 0
	for t in 10:
		taken += w.folk_ai._guild_drain(cutter, node, 3)
	check_eq(taken, 21, "ten hauls of 3 stone take 21 from the rock, not 30")
	var plain := run.world.folk_ai.add_folk("tribesperson")
	check_eq(w.folk_ai._guild_drain(plain, node, 3), 3, "someone outside the guild takes the full haul")


# --- Tier IIs (slice 2) --------------------------------------------------------------

func test_heroes_ii_keeps_a_fallen_heros_best_item_for_the_next() -> void:
	var run := _run(["hunters"])
	run.paths["heroes"] = 2
	var fallen := run.people.make_hero()
	fallen.items = {"weapon": Loot.make("obsidian_edge", 3), "armor": Loot.make("hide_armour", 1)}
	run.people.add_hero(fallen)
	fallen.alive = false
	run.people.bury_heroes()
	check_eq(run.heirlooms.size(), 1, "the fallen hero's best item is kept")
	check_eq(run.heirlooms[0]["base"], "obsidian_edge", "the most valuable one")
	var next := run.people.make_hero()
	next.items = {}
	run.people.add_hero(next)
	check_eq(next.items.get("weapon", {}).get("base", ""), "obsidian_edge", "the next hero takes it up")
	check(run.heirlooms.is_empty(), "and it's gone from the hall")
	var plain := _run(["hunters"])
	var lost := plain.people.make_hero()
	lost.items = {"weapon": Loot.make("obsidian_edge", 3)}
	plain.people.add_hero(lost)
	lost.alive = false
	plain.people.bury_heroes()
	check(plain.heirlooms.is_empty(), "without the path nothing is kept")


func test_heroes_ii_deals_fewer_tribespeople() -> void:
	var plain := 0
	var heroes := 0
	for s in 12:
		var a := _run([], 700 + s)
		plain += _dawn(a).filter(func(c: Dictionary) -> bool: return c["role"] == "tribesperson").size()
		a.dispose()
		var b := _run([], 700 + s)
		b.paths["heroes"] = 2
		heroes += _dawn(b).filter(func(c: Dictionary) -> bool: return c["role"] == "tribesperson").size()
		b.dispose()
	check(heroes < plain, "fewer tribesperson cards on Heroes II (%d vs %d in 12 dawns)" % [heroes, plain])


func _wave_night(run: RunState) -> void:
	var w := run.world
	w.time = (run.content.int_num("days_per_round") - 1) * w.day_length() + run.content.num("day_seconds") + 1.0


func test_warband_ii_musters_tribespeople_at_half_strength() -> void:
	var run := _band_run("forager", 1)
	var tribe: Unit = run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "tribesperson")[0]
	_wave_night(run)
	check(not run.world.folk_ai.levied(tribe), "no muster without the path")
	run.paths["warband"] = 2
	check(run.world.folk_ai.levied(tribe), "on Warband II tribespeople take up spears on the warned night")
	var warrior_blow := float(run.content.townsfolk["warrior"]["attack"])
	check_eq(run.world.folk_ai.relic_damage(tribe, tribe.attack), warrior_blow * 0.5, "with half a warrior's blow")
	run.world.time = 1.0
	check(not run.world.folk_ai.levied(tribe), "but not by day")


func test_warband_ii_warriors_stop_shadowing_gatherers() -> void:
	var run := _run([])
	run.begin_round()
	run.choose_pick(-1)
	for i in 4:
		run.world.folk_ai.add_folk("warrior")
	run.world.folk_ai.begin_step()
	run.paths["warband"] = 2
	check_eq(run.world.folk_ai._shadowing(), 0, "no warrior shadows a gatherer on Warband II")


func _to_warned_dusk(run: RunState) -> void:
	var w := run.world
	w.time = (run.content.int_num("days_per_round") - 1) * w.day_length() + run.content.num("day_seconds") \
		- run.content.num("dusk_seconds") - w.dt * 0.5
	w.step()


func test_warband_ii_stakes_the_attacks_way_at_dusk() -> void:
	var plain := _band_run("forager", 4)
	plain.stock["wood"] = 50
	_to_warned_dusk(plain)
	check(plain.world.barricades.is_empty(), "no barricades at dusk without the path")
	var staked := _band_run("forager", 4)
	staked.paths["warband"] = 2
	staked.stock["wood"] = 50
	check(not staked.world.wave_sides.is_empty(), "the round has an attack's way")
	_to_warned_dusk(staked)
	check(not staked.world.barricades.is_empty(), "at the warned dusk the town barricades the way in")
	check(int(staked.record.entry.get("dusk_stakes", 0)) > 0, "the record counts it")


func test_guilds_ii_charters_a_band_of_four() -> void:
	var run := _band_run("woodcutter", 4)
	check_eq(run.people.guild_ready(), "", "a band of four isn't ready on tier I")
	run.paths["guilds"] = 2
	check_eq(run.people.guild_ready(), "woodcutter", "it is on Guilds II")


func test_guilds_ii_deals_hero_cards_less_often() -> void:
	var plain := 0
	var guilds := 0
	for s in 30:
		for tier in [0, 2]:
			var run := _run([], 900 + s)
			if tier > 0:
				run.paths["guilds"] = tier
			run.build("tavern")
			for b in run.world.buildings:
				b["work_left"] = 0.0
			run.on_building_done("tavern")
			var n := _dawn(run).filter(func(c: Dictionary) -> bool: return c["kind"] == "hero").size()
			if tier > 0:
				guilds += n
			else:
				plain += n
			run.dispose()
	check(guilds < plain, "hero cards come up less often on Guilds II (%d vs %d in 30 dawns)" % [guilds, plain])


func test_trade_ii_folk_cards_cost_shells() -> void:
	var run := _run([])
	run.paths["trade"] = 2
	for c in _dawn(run):
		if c["role"] in ["tribesperson", "warrior"]:
			check_eq(int(c["cost"]), 3, "a %s card costs 3 shells" % c["role"])
	run.stock["shells"] = 0
	var at := -1
	for i in run.pick_offer.size():
		if run.pick_offer[i]["role"] == "tribesperson":
			at = i
	check(at >= 0 and not run.can_take_pick(at), "and can't be taken without them")


func test_trade_ii_hires_blades_for_the_round() -> void:
	var run := _run([])
	run.caravan.lay_out()
	check(not run.caravan.offers.any(func(o: Dictionary) -> bool: return o["deal"] == "hired_blades"), "no hired blades without the path")
	run.paths["trade"] = 2
	run.caravan.lay_out()
	var at := -1
	for i in run.caravan.offers.size():
		if run.caravan.offers[i]["deal"] == "hired_blades":
			at = i
	check(at >= 0, "Trade II lays out hired blades")
	check_eq(run.caravan.offers.size(), int(run.content.trades["offers"]) + 1, "on top of the usual deals")
	var people := run.population()
	for i in run.housing() - people:
		run.world.folk_ai.add_folk("tribesperson")
	run.stock["shells"] = 100
	check(run.caravan.take(at), "taken with no free beds")
	check_eq(run.population(), run.housing(), "the blades need no beds")
	var warriors := func() -> int: return run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").size()
	var with_blades: int = warriors.call()
	run.world._finish_round()
	check_eq(warriors.call(), with_blades - 3, "they leave as the round ends")
