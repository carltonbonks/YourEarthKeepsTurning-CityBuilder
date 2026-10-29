extends TestCase
## Light over the map (game/lighting.gd): night falls at dusk and lifts at dawn, the sun warms the day,
## and the hearth's and watch posts' shots burn when the town owns a fire relic.


func _round_run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	return run


func test_night_falls_at_dusk_and_lifts_at_dawn() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	check_eq(Lighting.darkness(run), 0.0, "the build phase is in daylight")
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	var day := run.content.num("day_seconds")
	var dusk := run.content.num("dusk_seconds")
	w.time = 1.0
	check_eq(Lighting.darkness(run), 0.0, "the round's first morning follows the build phase, so it is already light")
	w.time = day / 2.0
	check_eq(Lighting.darkness(run), 0.0, "noon is light")
	w.time = day - dusk / 2.0
	check(Lighting.darkness(run) > 0.0 and Lighting.darkness(run) < Lighting.NIGHT, "dusk is half dark")
	w.time = day + 1.0
	check_eq(Lighting.darkness(run), Lighting.NIGHT, "night is dark")
	w.time = w.day_length() + Lighting.DAWN_SECONDS / 2.0
	check(Lighting.darkness(run) > 0.0 and Lighting.darkness(run) < Lighting.NIGHT, "a later dawn lifts the night slowly")
	run.dispose()


func test_the_sun_warms_the_day_and_sets_at_night() -> void:
	var run := _round_run()
	var w := run.world
	var day := run.content.num("day_seconds")
	w.time = day / 2.0
	var noon := Lighting.sun(run)
	check(noon.r > 0.0, "the noon sun adds light")
	w.time = day * 0.1
	var morning := Lighting.sun(run)
	check(morning.r / morning.b > noon.r / noon.b, "morning light is warmer than noon")
	w.time = day + 1.0
	check_eq(Lighting.sun(run).r, 0.0, "no sun at night")
	run.dispose()


func test_fire_relics_set_tower_shots_alight() -> void:
	var run := _round_run()
	var w := run.world
	check(not Lighting.fire_shots(run), "no fire relic, no burning shots")
	run.relics.append("fire_arrows")
	check(Lighting.fire_shots(run), "Fire arrows carries the fire tag")
	var raider := w.enemy_ai.make_enemy("raider", Vector2(30, 0), 0.0)
	raider.hp = 999.0
	w.enemies.append(raider)
	w.hearth_cooldown_left = 0.0
	w.enemy_ai.towers_tick()
	check(not w.shots.is_empty() and w.shots[-1].get("tower", false), "the hearth's shot is marked as a tower's")
	run.dispose()
