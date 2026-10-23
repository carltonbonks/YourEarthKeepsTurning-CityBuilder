extends TestCase
## Incentive and hero-shaping buildings (Yusuf's pick 2026-10-22): the gibbet post, barrow warden's hut,
## trophy hall, training yard, kennel, duelling ring, seer's tent and brewhouse, and blueprint rarity.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	return run


## Orders a building and finishes it on the spot.
func _raise(run: RunState, type: String) -> int:
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	run.stock["shells"] = 99
	check(run.build(type), "can order a %s" % type)
	var i := run.world.buildings.size() - 1
	run.world.buildings[i]["work_left"] = 0.0
	run.on_building_done(type)
	run.world.market.refresh_prizes()
	return i


func _enemy(run: RunState, type: String) -> Unit:
	var e := Unit.new()
	e.team = Unit.Team.ENEMY
	e.type_id = type
	return e


func test_gibbet_pays_for_human_raiders() -> void:
	var run := _run()
	check_eq(run.world.market.prize_for("raider"), 0, "no prize before")
	_raise(run, "gibbet_post")
	check_eq(run.world.market.prize_for("raider"), 2, "2 shells a raider")
	check_eq(run.world.market.prize_for("wolf"), 0, "not for wolves")


func test_warden_adds_xp_for_undead() -> void:
	var run := _run()
	_raise(run, "warden_hut")
	check_eq(run.world.market.prize_xp("barrow_wight"), 0.5, "half again the XP from undead")
	check_eq(run.world.market.prize_xp("wolf"), 0.0, "none from wolves")
	var hero := run.heroes[0]
	var wolf := _enemy(run, "wolf")
	wolf.hp = 1.0
	var xp := hero.xp
	run.world.damage(hero, wolf, 99.0)
	var wolf_xp := hero.xp - xp
	var wight := _enemy(run, "barrow_wight")
	wight.hp = 1.0
	xp = hero.xp
	run.world.damage(hero, wight, 99.0)
	var expected := float(run.content.enemies["barrow_wight"]["xp"]) / float(run.content.enemies["wolf"]["xp"]) * wolf_xp * 1.5
	check(absf(hero.xp - xp - expected) < 0.01, "a wight gives half again its XP (%s, wanted %s)" % [hero.xp - xp, expected])


func test_trophy_hall_pays_for_trophies_and_draws_trophy_hunts() -> void:
	var run := _run()
	_raise(run, "trophy_hall")
	check_eq(run.world.market.prize_for("cave_bear"), 6, "6 shells a cave bear")
	check_eq(run.world.market.prize_for("wolf"), 0, "a wolf is no trophy")
	check_eq(run.mod("trophy_whims"), 2.0, "trophy whims three times as often")


func test_training_yard_drills_idle_heroes() -> void:
	var run := _run()
	_raise(run, "training_yard")
	var hero := run.heroes[0]
	run.world.enemies = [] as Array[Unit]
	run.world.dens = [] as Array[Dictionary]
	var before := hero.xp
	for i in int(20.0 / run.world.dt):
		run.world.hero_ai.hero_tick(hero)
	check(hero.xp > before, "the hero gains XP drilling (%s -> %s)" % [before, hero.xp])
	check(hero.intent.begins_with("drilling"), "and says so (%s)" % hero.intent)


func test_kennel_gives_hounds_that_eat() -> void:
	var run := _run()
	var food := run.food_needed_today()
	_raise(run, "kennel")
	var attack := {}
	for h in run.heroes:
		attack[h] = h.attack
	run.world.hero_ai.kennel_dawn()
	check_eq(run.world.hero_ai.hounds(), mini(2, run.living_heroes().size()), "up to 2 heroes get a hound")
	for h in run.heroes:
		check_eq(h.attack, attack[h] + (3.0 if h.hound else 0.0), "+3 attack with a hound")
	check_eq(run.food_needed_today(), food + run.world.hero_ai.hounds(), "each hound eats 1 food")


func test_hounds_bolt_when_their_hero_falls_back() -> void:
	var run := _run()
	_raise(run, "kennel")
	run.world.hero_ai.kennel_dawn()
	var hero: Unit = run.heroes.filter(func(h: Unit) -> bool: return h.hound)[0]
	hero.hp = 1.0
	run.world.hero_ai.hero_tick(hero)
	check(not hero.hound, "the hound runs off")


func test_duelling_ring_spars_bold_heroes() -> void:
	var run := _run()
	while run.heroes.size() < 2:
		run.people.add_hero(run.people.make_hero())
	run.heroes[0].trait_id = "brave"
	run.heroes[1].trait_id = "greedy"
	for h in run.heroes.slice(2):
		h.trait_id = "cautious"
	_raise(run, "duel_ring")
	var xp := [run.heroes[0].xp, run.heroes[1].xp]
	run.world.hero_ai.duels_dawn()
	check_eq(run.heroes[0].xp, xp[0] + 8.0, "both duellists learn")
	check_eq(run.heroes[1].xp, xp[1] + 8.0, "both duellists learn")
	check(run.heroes[0].hp < run.heroes[0].max_hp or run.heroes[1].hp < run.heroes[1].max_hp, "the loser is hurt")


func test_seer_shows_one_more_dawn_card() -> void:
	var run := _run()
	check_eq(run.mod("pick_bonus"), 0.0, "no bonus before")
	_raise(run, "seer_tent")
	check_eq(run.mod("pick_bonus"), 1.0, "one more dawn card")


func test_brewhouse_bands_sooner_and_eats() -> void:
	var run := _run()
	var food := run.food_needed_today()
	var tiers: Array = run.content.townsfolk["tribesperson"]["band_tiers"]
	var size := int(tiers[0]["size"])
	check_eq(run.world.folk_ai.band_level("tribesperson", "forager", size - 1), 0, "no band one short")
	_raise(run, "brewhouse")
	check_eq(run.world.folk_ai.band_level("tribesperson", "forager", size - 1), 1, "a band one short with ale")
	check_eq(run.food_needed_today(), food + 2, "brewing eats 2 food")


func test_rarer_blueprints_come_up_less() -> void:
	var c := Content.load_default()
	check_eq(c.rarity_of("building", "knapper"), "white", "no rarity is white")
	check_eq(c.rarity_of("building", "seer_tent"), "orange", "the seer is mythic")
	check(c.rarity_weight("orange") < c.rarity_weight("yellow") and c.rarity_weight("yellow") < c.rarity_weight("blue") \
		and c.rarity_weight("blue") < c.rarity_weight("white"), "rarer is offered less often")
	for id: String in c.rarity["order"]:
		check(c.rarity["tiers"].has(id), "%s has a tier" % id)
	for type: String in c.buildings:
		check(c.rarity["tiers"].has(c.rarity_of("building", type)), "%s has a known rarity" % type)


func test_bots_use_the_new_buildings() -> void:
	# Which blueprints come up depends on the draws, so look over two runs.
	var built := {}
	for seed_value in [1000, 1003]:
		for rd: Dictionary in bot_record(seed_value, "balanced")["rounds"]:
			for a: Dictionary in rd["actions"]:
				if a.get("kind", "") == "build":
					built[a.get("building", "")] = true
	var used := ["training_yard", "kennel", "trophy_hall", "gibbet_post", "seer_tent", "duel_ring", "warden_hut", "brewhouse"].filter(func(t: String) -> bool: return built.has(t))
	check(not used.is_empty(), "the balanced bot raises some of the new buildings (%s)" % [built.keys()])


func test_rule_breakers_change_rules_while_they_stand() -> void:
	var run := _run()
	check(not run.has_effect("levy"), "no levy before")
	_raise(run, "levy_hall")
	check(run.has_effect("levy"), "tribespeople take up spears on the warned night")
	_raise(run, "beacon_tower")
	check(run.has_effect("one_side") and run.mod("wave_mult") > 0.0, "the attack comes from one side, larger")


func test_the_oath_stone_strengthens_heroes_at_once() -> void:
	var run := _run()
	var hero := run.heroes[0]
	var attack := hero.attack
	var hp := hero.max_hp
	_raise(run, "oath_stone")
	check_eq(hero.attack, attack + 3.0, "hits 3 harder")
	check_eq(hero.max_hp, hp + 15.0, "15 more health")
	check_eq(run.mod("xp_mult"), -0.5, "learns half as fast")
