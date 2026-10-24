extends TestCase
## The town reads the attack's way in (HeroAI._meets_attack, FolkAI._on_attack_way; watch posts in test_gate.gd).


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.world.enemies.clear()
	run.world.wave_sides.assign([0.0])
	return run


func _hero(run: RunState, trait_id: String) -> Unit:
	var hero := run.people.make_hero()
	hero.trait_id = trait_id
	run.people.add_hero(hero)
	hero.pos = Vector2.ZERO
	hero.energy = 100.0
	return hero


## World time at dusk of day `day` (0-based) of the round.
func _dusk(run: RunState, day: int) -> float:
	var c := run.content
	return run.world.day_length() * day + c.num("day_seconds") - c.num("dusk_seconds") + 0.5


func test_bold_heroes_meet_the_attack_on_the_plate_it_crosses() -> void:
	var run := _run()
	var w := run.world
	var bold := _hero(run, "brave")
	var careful := _hero(run, "cautious")
	w.time = _dusk(run, 2)
	for i in 30:
		w.hero_ai.hero_tick(bold)
		w.hero_ai.hero_tick(careful)
	var crossed := String(w.earth.kind_def(w.earth.crossing(0.0))["name"]).to_lower()
	check_eq(bold.intent, "waiting for the attack on the %s" % crossed, "a bold hero names the plate the attack crosses")
	check(bold.pos.x > 20.0 and absf(bold.pos.angle()) < 0.3, "and walks out along the way it comes in")
	check_eq(careful.intent, "guarding the camp", "a cautious hero stays by the hearth")
	run.dispose()


func test_bold_heroes_stay_home_on_quiet_dusks() -> void:
	var run := _run()
	var w := run.world
	var bold := _hero(run, "brave")
	w.time = _dusk(run, 0)
	w.hero_ai.hero_tick(bold)
	check(not bold.intent.begins_with("waiting for the attack"), "no attack tonight, so the bold hero stays home (%s)" % bold.intent)
	run.dispose()


func test_gatherers_keep_off_the_attack_way_on_its_day() -> void:
	var run := _run()
	var w := run.world
	var r := 320.0
	for node in w.nodes:
		if node["gives"] == "wood":
			node["amount"] = 0
	w.nodes.append({"type": "grove", "gives": "wood", "pos": Vector2.from_angle(0.1) * r, "amount": 10, "max": 24,
		"heroes_only": false, "wild": false, "age": ""})
	var on_way := w.nodes.size() - 1
	w.nodes.append({"type": "grove", "gives": "wood", "pos": Vector2.from_angle(PI / 2.0) * (r + 30.0), "amount": 10, "max": 24,
		"heroes_only": false, "wild": false, "age": ""})
	var aside := w.nodes.size() - 1
	run.stock["wood"] = 0
	var folk: Unit = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "tribesperson")[0]
	folk.leaning = ""
	folk.pos = Vector2.ZERO
	w.time = 0.0
	check_eq(w.folk_ai.plan_trip(folk), on_way, "on a quiet day the nearer grove wins")
	w.time = w.day_length() * 2.0
	check_eq(w.folk_ai.plan_trip(folk), aside, "on the attack's day the grove on its way is passed over")
	run.dispose()
