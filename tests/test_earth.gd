extends TestCase
## The earth as this round's weather (sim/earth.gd, data/plates.json): one ring of plates just past the still town
## clicks a whole plate round between rounds, and the plate kind the attack crosses shapes the round.


func _run(seed_value := 4821, content: Content = null) -> RunState:
	return RunState.new(content if content != null else Content.load_default(), seed_value)


## A point on a near plate of `kind`, mid-ring and well inside the plate (Vector2.INF if none).
func _point_of_kind(earth: Earth, kind: String) -> Vector2:
	var ring: Dictionary = earth.rings[0]
	var seams: Array = ring["seams"]
	for k in seams.size():
		if ring["plate_kinds"][k] == kind:
			var mid := float(seams[k]) + fposmod(float(seams[(k + 1) % seams.size()]) - float(seams[k]), TAU) / 2.0
			return Vector2.from_angle(mid) * (float(ring["r0"]) + float(ring["r1"])) / 2.0
	return Vector2.INF


func _grove(w: World, p: Vector2) -> Dictionary:
	w.nodes.append({"type": "grove", "gives": "wood", "pos": p, "amount": 10, "max": 24,
		"heroes_only": false, "wild": false, "age": ""})
	return w.nodes[-1]


func test_only_the_near_ring_turns_a_whole_plate_round_a_still_town() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	check_eq(earth.rings.size(), 1, "one ring of plates")
	var still: Array = w.nodes.filter(func(n: Dictionary) -> bool: return earth.ring_at(n["pos"]) < 0)
	var still_at: Array = still.map(func(n: Dictionary) -> Vector2: return n["pos"])
	var dens_at: Array = w.dens.map(func(d: Dictionary) -> Vector2: return d["pos"])
	var near := _grove(w, _point_of_kind(earth, "fen"))
	var near_at: Vector2 = near["pos"]
	var plots_before: Array = w.town.plots.map(func(p: Dictionary) -> Vector2: return p["pos"])
	var seams_before: Array = earth.rings[0]["seams"].duplicate()
	earth.shift()
	check(not still.is_empty(), "some nodes sit off the ring")
	for i in still.size():
		check_eq(still[i]["pos"], still_at[i], "nodes off the ring never move")
	check_eq(w.dens.map(func(d: Dictionary) -> Vector2: return d["pos"]), dens_at, "dens stay where they are")
	var step := TAU / float(run.content.plates["rings"][0]["plates"])
	check(is_equal_approx(angle_difference(near_at.angle(), Vector2(near["pos"]).angle()), step), "a node on the ring turned a whole plate")
	for k in seams_before.size():
		check(is_equal_approx(angle_difference(float(seams_before[k]), float(earth.rings[0]["seams"][k])), step), "every plate edge turned with it")
	check_eq(w.town.plots.map(func(p: Dictionary) -> Vector2: return p["pos"]), plots_before, "the town's plots stay put")
	check_eq(earth.shifts, 1, "one shift counted")
	run.dispose()


func test_a_new_round_turns_the_earth_once() -> void:
	var run := _run()
	var bot := AutoPlayer.new()
	while run.round_number < 3 and not run.is_over():
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(bot.pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic("")
	check_eq(run.world.earth.shifts, 2, "a shift as rounds 2 and 3 began, none in round 1")
	check(run.story.any(func(line: String) -> bool: return line.begins_with("The earth turns. This round the attack crosses the")),
		"the story says what ground the attack crosses now")
	run.dispose()


func test_the_ring_keeps_its_shape() -> void:
	var run := _run(9001)
	var earth := run.world.earth
	var widths := func() -> Array:
		var s: Array = earth.rings[0]["seams"]
		var out := []
		for k in s.size():
			out.append(snappedf(fposmod(float(s[(k + 1) % s.size()]) - float(s[k]), TAU), 0.0001))
		return out
	var before: Array = widths.call()
	for n in 13:
		earth.shift()
	check_eq(widths.call(), before, "plates turn as one: none grows or shrinks")
	run.dispose()


func test_the_near_plates_are_dealt_one_of_each_kind() -> void:
	var run := _run()
	var kinds: Array = run.world.earth.rings[0]["plate_kinds"].duplicate()
	kinds.sort()
	var want: Array = run.content.plates["near_kinds"].keys()
	want.sort()
	check_eq(kinds, want, "one plate of each kind")
	run.dispose()


func test_each_turn_puts_a_different_plate_in_the_attacks_way() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var a := float(w.wave_sides[0])
	var first := earth.crossing(a)
	check_eq(first, earth.kind_at(Vector2.from_angle(a) * 350.0), "the plate between its den and the town")
	earth.shift()
	check(earth.crossing(a) != first, "after a turn the attack crosses other ground")
	check(" ".join(EarthReport.ways(run)).contains(String(earth.kind_def(earth.crossing(a))["name"])), "and the threat card names it")
	run.dispose()


func test_stillstone_holds_the_ring_and_the_lodestone_wheel_turns_it_two_plates() -> void:
	var run := _run()
	var earth := run.world.earth
	var step := float(earth.rings[0]["step"])
	run.relics.append("stillstone")
	check_eq(earth.turn_of(0, 1), 0.0, "Stillstone: the ring stays put")
	run.relics.clear()
	run.relics.append("lodestone_wheel")
	check(is_equal_approx(earth.turn_of(0, 1), step * 2.0), "the Lodestone Wheel: two plates at a turn")
	run.dispose()


func test_fen_slows_everyone_and_stonefield_speeds_raiders() -> void:
	var run := _run()
	var earth := run.world.earth
	var fen := _point_of_kind(earth, "fen")
	var stone := _point_of_kind(earth, "stonefield")
	var kinds: Dictionary = run.content.plates["near_kinds"]
	check(is_equal_approx(earth.walk_factor(fen, false), float(kinds["fen"]["walk"])), "townsfolk wade the Fen")
	check(is_equal_approx(earth.walk_factor(fen, true), float(kinds["fen"]["walk"])), "raiders too")
	check(is_equal_approx(earth.walk_factor(stone, true), float(kinds["stonefield"]["raider_walk"])), "raiders march fast on the Stonefield")
	check_eq(earth.walk_factor(stone, false), 1.0, "townsfolk don't")
	check_eq(earth.walk_factor(Vector2(100, 0), true), 1.0, "nothing changes on the still ground")
	run.dispose()


func _raider(w: World, at: Vector2) -> Unit:
	var e := w.enemy_ai.make_enemy("wolf", at, 0.0)
	w.enemies.append(e)
	w._enemy_grid_ok = false
	return e


func test_greenwood_hides_raiders_and_stonefield_shows_them() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	w.enemies = [] as Array[Unit]
	var wood := _point_of_kind(earth, "greenwood")
	var from := wood.normalized() * (wood.length() - 100.0)
	var hidden := _raider(w, wood)
	check(w.enemy_ai.sighted(from, 120.0) == null, "in the Greenwood, 100 off is too far for a 120 reach")
	check(w.enemy_ai.sighted(from, 200.0) == hidden, "seen once close enough")
	w.enemies = [] as Array[Unit]
	var stone := _point_of_kind(earth, "stonefield")
	var from2 := stone.normalized() * (stone.length() - 140.0)
	var open := _raider(w, stone)
	check(w.enemy_ai.sighted(from2, 120.0) == open, "on the Stonefield, seen from further than the reach")
	run.dispose()


func test_a_raider_who_falls_on_the_barrow_gets_up_once() -> void:
	var content := Content.load_default()
	content.plates["near_kinds"]["barrow"]["rise_chance"] = 1.0
	content.plates["near_kinds"]["barrow"]["grave_goods"] = 1.0
	var run := _run(4821, content)
	var w := run.world
	var at := _point_of_kind(w.earth, "barrow")
	var e := _raider(w, at)
	w.damage(null, e, 9999.0)
	check(e.alive, "it gets up again")
	check(is_equal_approx(e.hp, e.max_hp * float(content.plates["near_kinds"]["barrow"]["rise_hp"])), "at half its health")
	if run.heroes.is_empty():
		w.damage(null, e, 9999.0)
		check(not e.alive, "and stays down the second time")
		run.dispose()
		return
	var hero: Unit = run.heroes[0]
	var items := hero.items.size() + hero.spares.size()
	w.damage(hero, e, 9999.0)
	check(not e.alive, "and stays down the second time")
	check(hero.items.size() + hero.spares.size() > items, "the hero who felled it dug up grave goods")
	run.dispose()


func test_greenwood_plants_regrow_each_dawn() -> void:
	var run := _run()
	var w := run.world
	var wood := _grove(w, _point_of_kind(w.earth, "greenwood"))
	var fen := _grove(w, _point_of_kind(w.earth, "fen"))
	w.earth.dawn()
	check(int(wood["amount"]) > 10, "a grove on the Greenwood grew back")
	check_eq(int(fen["amount"]), 10, "one on the Fen didn't")
	run.dispose()


func test_trails_ride_their_plate() -> void:
	var run := _run()
	var w := run.world
	var p := w.pathing
	var at := _point_of_kind(w.earth, "fen")
	p.set_ground(p.index_of(at), Pathing.TRAIL)
	var turn := w.earth.turn_of(0, 1)
	w.earth.shift()
	check_eq(p.ground[p.index_of(at.rotated(turn))], Pathing.TRAIL, "the trail square moved with its plate")
	run.dispose()


func test_the_same_seed_shifts_the_same_way() -> void:
	var a := _run(777)
	var b := _run(777)
	for n in 6:
		a.world.earth.shift()
		b.world.earth.shift()
	check_eq(a.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]),
		b.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]), "nodes end up in the same places")
	check_eq(a.world.earth.rings[0]["seams"], b.world.earth.rings[0]["seams"], "and so do the plates")
	a.dispose()
	b.dispose()


func test_a_still_earth_when_turned_off() -> void:
	var content := Content.load_default()
	content.plates["enabled"] = false
	var run := RunState.new(content, 4821)
	var before: Array = run.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"])
	run.world.earth.shift()
	check_eq(run.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]), before, "nothing moves")
	check_eq(run.world.earth.crossing(0.0), "", "and the attack crosses no plate")
	run.dispose()


func test_record_has_each_shift_and_the_ground_crossed() -> void:
	var rec := bot_record()
	var rounds: Array = rec["rounds"]
	check(not rounds[0].has("shift"), "no shift before round 1")
	check(rounds[0].has("crossing"), "round 1 notes the ground its attack crossed")
	if rounds.size() > 1:
		var shift: Dictionary = rounds[1].get("shift", {})
		check_eq(shift.keys(), ["shift", "roads_refunded"], "round 2's shift says only which it was and any paving paid back")
		check_eq(int(shift.get("shift", 0)), 1, "it was the first shift")


func test_a_plates_hover_says_what_it_gives_and_takes() -> void:
	var run := _run()
	var plate := Tooltips.plate(run, "fen")
	check(plate["title"].begins_with("Fen"), "a near plate names its kind")
	check(plate["lines"].any(func(l: String) -> bool: return l.begins_with("Gives:")), "what it gives")
	check(plate["lines"].any(func(l: String) -> bool: return l.begins_with("Takes:")), "and what it takes")
	run.dispose()


func test_the_attack_comes_by_a_den_across_one_plate() -> void:
	var run := _run()
	var w := run.world
	w.roll_wave_sides()
	check_eq(w.wave_sides.size(), 1, "one side early on")
	var den_type: String = w.wave_side_dens[0]
	check(den_type != "", "the warband comes by a den's way")
	var den: Dictionary = w.dens.filter(func(d: Dictionary) -> bool: return d["type"] == den_type)[0]
	check(absf(angle_difference(w.wave_sides[0], Vector2(den["pos"]).angle())) < 0.001, "from where the den stands")
	var ways := EarthReport.ways(run)
	check_eq(ways.size(), 1, "one line for the one way in")
	check(ways[0].contains("across the"), "naming the ground it crosses")
	run.dispose()


func test_two_sides_stay_apart_and_open_country_once_the_dens_are_gone() -> void:
	var run := _run()
	var w := run.world
	run.round_number = run.content.int_num("wave_two_sides_from_round")
	w.roll_wave_sides()
	check_eq(w.wave_sides.size(), 2, "two sides later on")
	var apart := deg_to_rad(run.content.num("wave_sides_apart"))
	check(absf(angle_difference(w.wave_sides[0], w.wave_sides[1])) >= apart - 0.001, "far enough apart")
	w.dens.clear()
	w.roll_wave_sides()
	check_eq(w.wave_side_dens, ["", ""] as Array[String], "with every den cleared, open country")
	check(absf(angle_difference(w.wave_sides[0], w.wave_sides[1])) >= apart - 0.001, "still apart")
	check(" ".join(EarthReport.ways(run)).contains("open country"), "and the threat card says so")
	run.dispose()
