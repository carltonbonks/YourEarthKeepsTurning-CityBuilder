extends TestCase
## The shifting earth as a dial (sim/earth.gd, data/plates.json): rings click a whole plate round the still town
## between rounds, the near plates' kinds shape the ground the attack crosses, the town can feed the earth to turn
## the near ring, and seams fill with pressure, warn when full and wake at the next turn.


func _run(seed_value := 4821, content: Content = null) -> RunState:
	return RunState.new(content if content != null else Content.load_default(), seed_value)


## A point on a near plate of `kind`, mid-ring and well inside the plate ({} -> Vector2.INF if none).
func _point_of_kind(earth: Earth, kind: String) -> Vector2:
	var ring: Dictionary = earth.rings[0]
	var seams: Array = ring["seams"]
	for k in seams.size():
		if ring["plate_kinds"][k] == kind:
			var mid := float(seams[k]) + fposmod(float(seams[(k + 1) % seams.size()]) - float(seams[k]), TAU) / 2.0
			return Vector2.from_angle(mid) * (float(ring["r0"]) + float(ring["r1"])) / 2.0
	return Vector2.INF


## Makes seam k of ring ri a full seam of `kind`, so it wakes at the next turn.
func _make_full(earth: Earth, ri: int, k: int, kind: String) -> void:
	earth.rings[ri]["kinds"][k] = kind
	earth.rings[ri]["pressure"][k] = int(earth.def["pressure"]["full"])


## A point in ring ri beside seam k, on its diving side (dive = true) or the other, `off` units along the ring from it.
func _beside(earth: Earth, ri: int, k: int, dive: bool, off := 50.0) -> Vector2:
	var ring: Dictionary = earth.rings[ri]
	var r := (float(ring["r0"]) + float(ring["r1"])) / 2.0
	var side := -1.0 if int(ring["divers"][k]) == 0 else 1.0
	if not dive:
		side = -side
	return Vector2.from_angle(float(ring["seams"][k]) + side * off / r) * r


func _grove(w: World, p: Vector2) -> Dictionary:
	w.nodes.append({"type": "grove", "gives": "wood", "pos": p, "amount": 10, "max": 24,
		"heroes_only": false, "wild": false, "age": ""})
	return w.nodes[-1]


func test_rings_click_a_whole_plate_round_a_still_town() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var still: Array = w.nodes.filter(func(n: Dictionary) -> bool: return earth.ring_at(n["pos"]) < 0)
	var still_at: Array = still.map(func(n: Dictionary) -> Vector2: return n["pos"])
	var near := _grove(w, _point_of_kind(earth, "fen"))
	var near_at: Vector2 = near["pos"]
	var plots_before: Array = w.town.plots.map(func(p: Dictionary) -> Vector2: return p["pos"])
	var seams_before: Array = earth.rings[0]["seams"].duplicate()
	earth.shift()
	check(not still.is_empty(), "some nodes sit on the still ground near the town")
	for i in still.size():
		check_eq(still[i]["pos"], still_at[i], "nodes inside the first plate ring never move")
	var step := TAU / float(run.content.plates["rings"][0]["plates"])
	check(is_equal_approx(angle_difference(near_at.angle(), Vector2(near["pos"]).angle()), step), "a near-ring node turned a whole plate")
	for k in seams_before.size():
		check(is_equal_approx(angle_difference(float(seams_before[k]), float(earth.rings[0]["seams"][k])), step), "every seam turned with it")
	check_eq(w.town.plots.map(func(p: Dictionary) -> Vector2: return p["pos"]), plots_before, "the town's plots stay put")
	check_eq(earth.shifts, 1, "one shift counted")
	run.dispose()


func test_the_middle_ring_clicks_every_other_turn_and_the_far_ring_the_other_way() -> void:
	var run := _run()
	var earth := run.world.earth
	var rd: Array = run.content.plates["rings"]
	check_eq(earth.turn_of(1, 0, 1), 0.0, "the middle ring waits on the first turn")
	check(is_equal_approx(earth.turn_of(1, 0, 2), TAU / float(rd[1]["plates"]) * float(rd[1]["dir"])), "and clicks on the second")
	check(signf(earth.turn_of(2, 0, 1)) != signf(earth.turn_of(0, 0, 1)), "the far ring turns the other way from the near")
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
	check(run.story.any(func(line: String) -> bool: return line.begins_with("The earth turns")), "the story tells of it")
	run.dispose()


func test_rings_keep_their_shape() -> void:
	var run := _run(9001)
	var earth := run.world.earth
	var widths := func() -> Array:
		var out := []
		for ring in earth.rings:
			var s: Array = ring["seams"]
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
	check(run.world.earth.rings[1]["plate_kinds"].all(func(k: String) -> bool: return k == ""), "the middle ring has none")
	run.dispose()


func test_the_attack_crosses_the_near_plate_in_its_way() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var a := float(w.wave_sides[0])
	check_eq(earth.crossing(a), earth.kind_at(Vector2.from_angle(a) * 350.0), "the plate between its den and the town")
	var next := earth.crossing(a, 1)
	check(next != earth.crossing(a), "one more click puts a different plate in its way")
	earth.feed()
	check_eq(earth.crossing(a), next, "feeding the earth turns that plate into the way")
	check(" ".join(EarthReport.ways(run)).contains(String(earth.kind_def(next)["name"])), "and the threat card names it")
	run.dispose()


func test_feeding_the_earth_costs_stone_once_a_round_and_more_each_time() -> void:
	var run := _run()
	run.choose_traditions([])
	var earth := run.world.earth
	run.stock["stone"] = 100
	var fd: Dictionary = run.content.plates["feed"]
	var seams: Array = earth.rings[0]["seams"].duplicate()
	var middle: Array = earth.rings[1]["seams"].duplicate()
	check(run.can_feed_earth(), "on offer while building")
	check(run.feed_earth(), "fed")
	check_eq(int(run.stock["stone"]), 100 - int(fd["cost"]), "for its stone")
	check(not is_equal_approx(float(seams[0]), float(earth.rings[0]["seams"][0])), "the near ring turned")
	check_eq(earth.rings[1]["seams"], middle, "and only the near ring")
	check(not run.can_feed_earth(), "once a round")
	check_eq(run.record.entry["actions"][-1]["kind"], "feed_earth", "recorded")
	run.round_number += 1
	check_eq(int(earth.feed_cost()["stone"]), int(fd["cost"]) + int(fd["step"]), "the next feeding asks more")
	run.world.add_building("geomancer")
	run.world.buildings[-1]["work_left"] = 0.0
	check_eq(int(earth.feed_cost()["stone"]), roundi((int(fd["cost"]) + int(fd["step"])) * float(fd["geomancer_share"])), "a geomancer halves it")
	run.dispose()


func test_stillstone_leaves_nothing_to_feed() -> void:
	var run := _run()
	run.choose_traditions([])
	run.stock["stone"] = 100
	run.relics.append("stillstone")
	check(not run.can_feed_earth(), "a held ring can't be fed round")
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


func test_pressure_fills_a_few_seams_each_turn() -> void:
	var run := _run()
	var earth := run.world.earth
	var total := func() -> int:
		var n := 0
		for s: Dictionary in earth.seams():
			n += int(s["pressure"])
		return n
	earth.shift()
	check_eq(total.call(), int(run.content.plates["pressure"]["per_turn"]), "per_turn marks after the first turn")
	var woke := 0
	for n in 12:
		earth.shift()
		woke += int(earth.last["wakes"])
	check(woke >= 4, "full seams woke over a run (%d)" % woke)
	run.dispose()


func test_a_full_trench_cracks_what_it_will_swallow_then_swallows_it() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	_make_full(earth, 1, 0, "subduct")
	var doomed := _grove(w, _beside(earth, 1, 0, true))
	var spared := _grove(w, _beside(earth, 1, 0, false))
	check(earth.doomed(doomed["pos"]), "the diving side cracks")
	check(not earth.doomed(spared["pos"]), "the other side doesn't")
	check(" ".join(EarthReport.lines(run)).contains("full"), "the report says a seam is full")
	earth.shift()
	check_eq(doomed["type"], "embers", "the grove on the diving side went under")
	check_eq(doomed["gives"], "fuel", "embers burn as fuel")
	check(not w.regrows(doomed), "embers never grow back")
	check_eq(spared["type"], "grove", "the other side is spared")
	check_eq(int(earth.rings[1]["pressure"][0]), 0, "the seam emptied")
	check_eq(earth.woke["kind"], "subduct", "the shift reports the seam that woke")
	var ev: Array = earth.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "sank" and e["type"] == "grove")
	check(not ev.is_empty() and ev[0]["great"] and ev[0]["worked"], "reported as a waking seam's, and as one the town worked")
	run.dispose()


func test_a_full_trench_takes_a_den_and_its_wanderers() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var far := earth.rings.size() - 1
	_make_full(earth, far, 0, "subduct")
	var p := _beside(earth, far, 0, true)
	w.dens.insert(0, {"type": "wolf_den", "spawns": "wolf", "pos": p, "respawn_left": 0.0})
	var doomed_wolf := w.enemy_ai.make_enemy("wolf", p, 0.0)
	doomed_wolf.den_index = 0
	var other_wolf := w.enemy_ai.make_enemy("wolf", w.dens[1]["pos"], 0.0)
	other_wolf.den_index = 1
	w.enemies.append_array([doomed_wolf, other_wolf])
	var dens_before := w.dens.size()
	earth.shift()
	check_eq(w.dens.size(), dens_before - 1, "the den went under")
	check(not doomed_wolf.alive, "its wolf went with it")
	check(other_wolf.alive, "another den's wolf lives")
	check_eq(other_wolf.den_index, 0, "and still belongs to its own den")
	check_eq(int(earth.last["dens_swallowed"]), 1, "the shift reports the den")
	check(w.nodes.any(func(n: Dictionary) -> bool: return n["type"] == "sunk_hoard"), "its hoard waits for a hero")
	run.dispose()


func test_a_full_trench_takes_the_war_camp_raiders_spoils_and_all() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var far := earth.rings.size() - 1
	_make_full(earth, far, 0, "subduct")
	var p := _beside(earth, far, 0, true)
	w.dens.append({"type": "war_camp", "spawns": "wolf", "pos": p, "respawn_left": 0.0, "camp": true, "joined": 1})
	var camper := w.enemy_ai.make_enemy("wolf", p, 0.0)
	camper.spawned = true
	camper.den_index = w.dens.size() - 1
	w.enemies.append(camper)
	check(earth.doomed(p), "the camp's ground cracks before it goes")
	var shells: int = run.stock["shells"]
	earth.shift()
	check_eq(w.camp_index(), -1, "the war camp went under")
	check(not camper.alive, "its raiders went with it")
	check(bool(earth.last.get("camp_swallowed", false)), "the shift reports the camp")
	check_eq(int(run.stock["shells"]), shells, "nobody won the camp's spoils")
	run.dispose()


func test_a_full_colliding_seam_raises_a_ridge_with_a_rich_vein() -> void:
	var content := Content.load_default()
	content.plates["pressure"]["per_turn"] = 0
	var run := _run(4821, content)
	var w := run.world
	var earth := w.earth
	_make_full(earth, 1, 0, "collide")
	earth.shift()
	var ring: Dictionary = earth.rings[1]
	check_eq(int(ring["ridges"][0]), int(content.plates["ridge_turns"]), "a ridge stands for a few turns")
	var a := float(ring["seams"][0])
	var mid := (float(ring["r0"]) + float(ring["r1"])) / 2.0
	check(w.pathing.is_solid(w.pathing.index_of(Vector2.from_angle(a) * (float(ring["r0"]) + 20.0))), "nobody walks over the ridge")
	check(not w.pathing.is_solid(w.pathing.index_of(Vector2.from_angle(a) * mid)), "its pass in the middle is open")
	for node in w.nodes:
		check(not w.pathing.is_solid(w.pathing.index_of(node["pos"])) or earth.ring_at(node["pos"]) < 0, "no node is left on a ridge")
	var rich: Array = earth.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "raised" and e["great"])
	check_eq(rich.size(), 1, "one rich vein")
	var node: Dictionary = w.nodes.filter(func(n: Dictionary) -> bool: return n["pos"] == rich[0]["pos"])[0]
	check_eq(node["type"], "obsidian", "of the age's upthrust stone")
	check(int(node["amount"]) > int(content.world["nodes"]["obsidian"]["amount"]), "holding more than an ordinary outcrop")
	check(earth.events.any(func(e: Dictionary) -> bool: return e["kind"] == "find" and e["type"] == "starstone"), "starstone came up beside it")
	check(" ".join(EarthReport.lines(run)).contains("Starstone"), "and the report says so")
	for n in int(content.plates["ridge_turns"]):
		earth.shift()
	check_eq(int(ring["ridges"][0]), 0, "then it wears away")
	check(earth.ridge_cells().is_empty(), "and the ground is open again")
	run.dispose()


func test_a_full_rift_grows_a_valley_of_its_plates_kind() -> void:
	var run := _run()
	var earth := run.world.earth
	_make_full(earth, 0, 0, "rift")
	earth.shift()
	var grew: Array = earth.events.filter(func(e: Dictionary) -> bool: return e["kind"] == "grew" and e["great"])
	check_eq(grew.size(), int(run.content.plates["wake"]["rift_nodes"]), "a valley of fresh patches")
	for e: Dictionary in grew:
		check_eq(earth.ring_at(e["pos"]), 0, "in the near ring")
		var kind := earth.kind_at(e["pos"])
		check(earth.kind_def(kind)["grows"].has(e["type"]), "of what its plate grows")
	run.dispose()


func test_gatherers_strip_cracking_ground_first() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	_make_full(earth, 0, 0, "subduct")
	var r := (float(earth.rings[0]["r0"]) + float(earth.rings[0]["r1"])) / 2.0
	var doomed := _grove(w, _beside(earth, 0, 0, true, 40.0))
	var safe := _grove(w, _beside(earth, 0, 0, false, 40.0))
	check(earth.doomed(doomed["pos"]) and not earth.doomed(safe["pos"]), "one cracks, one doesn't")
	var folk: Unit = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "tribesperson")[0]
	folk.pos = (Vector2(doomed["pos"]) + Vector2(safe["pos"])) / 2.0 * (r - 60.0) / r
	folk.leaning = ""
	w.time = 0.0
	for node in w.nodes:
		if node != doomed and node != safe and node["gives"] == "wood":
			node["amount"] = 0
	run.stock["wood"] = 0
	var pick := w.folk_ai.plan_trip(folk)
	check_eq(pick, w.nodes.find(doomed), "the gatherer goes to the cracking grove")
	run.dispose()


func test_heroes_dig_out_a_find_on_cracking_ground_first() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	if run.heroes.is_empty():
		run.dispose()
		return
	var hero: Unit = run.heroes[0]
	var far := earth.rings.size() - 1
	_make_full(earth, far, 0, "subduct")
	var doomed_at := _beside(earth, far, 0, true, 45.0)
	var near_at := _beside(earth, far, 0, false, 25.0)
	hero.pos = _beside(earth, far, 0, true, 0.0)
	earth._add("sunk_hoard", near_at, 1.0)
	var near_i := w.nodes.size() - 1
	earth._add("sunk_hoard", doomed_at, 1.0)
	var doomed_i := w.nodes.size() - 1
	check(not earth.doomed(w.nodes[near_i]["pos"]), "the nearer one is safe")
	check_eq(w.hero_ai.find_for(hero, 2.0), doomed_i, "the hero races for the one about to sink")
	run.dispose()


func test_trails_ride_their_plate() -> void:
	var run := _run()
	var w := run.world
	var p := w.pathing
	var at := _point_of_kind(w.earth, "fen")
	p.set_ground(p.index_of(at), Pathing.TRAIL)
	var turn := w.earth.next_turn(at)
	w.earth.shift()
	check_eq(p.ground[p.index_of(at.rotated(turn))], Pathing.TRAIL, "the trail square moved with its plate")
	run.dispose()


func test_swallowed_paving_is_paid_back() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	_make_full(earth, 0, 0, "subduct")
	var laid := 0
	for i in w.pathing.ground.size():
		if earth.doomed(w.pathing.center(i)):
			w.pathing.set_ground(i, Pathing.FIRST_ROAD)
			laid += 1
	var stone := int(run.stock["stone"])
	earth.shift()
	check(laid > 0, "road laid where the earth will swallow")
	check(int(earth.last["roads_refunded"]) > 0, "the swallowed paving is counted")
	check(int(run.stock["stone"]) > stone, "and its stone comes back")
	run.dispose()


func test_the_same_seed_shifts_the_same_way() -> void:
	var a := _run(777)
	var b := _run(777)
	for n in 6:
		a.world.earth.shift()
		b.world.earth.shift()
	check_eq(a.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]),
		b.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]), "nodes end up in the same places")
	check_eq(a.world.earth.last, b.world.earth.last, "the shifts did the same things")
	check_eq(a.world.earth.seams(), b.world.earth.seams(), "and filled the same seams")
	a.dispose()
	b.dispose()


func test_a_still_earth_when_turned_off() -> void:
	var content := Content.load_default()
	content.plates["enabled"] = false
	var run := RunState.new(content, 4821)
	var before: Array = run.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"])
	run.world.earth.shift()
	check_eq(run.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]), before, "nothing moves")
	check(run.world.earth.seams().is_empty(), "and no seam is shown")
	check(not run.can_feed_earth(), "and there is nothing to feed")
	run.dispose()


func test_record_has_each_shift_and_the_ground_crossed() -> void:
	var rec := bot_record()
	var rounds: Array = rec["rounds"]
	check(not rounds[0].has("shift"), "no shift before round 1")
	check(rounds[0].has("crossing"), "round 1 notes the ground its attack crossed")
	if rounds.size() > 1:
		var shift: Dictionary = rounds[1].get("shift", {})
		for key in ["shift", "swallowed", "dens_swallowed", "ridges", "raised", "grown", "roads_refunded", "wakes", "held"]:
			check(shift.has(key), "round 2's shift has %s" % key)
		check_eq(int(shift.get("shift", 0)), 1, "it was the first shift")


func test_hover_text_names_the_seam_and_its_pressure() -> void:
	var run := _run()
	var earth := run.world.earth
	_make_full(earth, 0, 1, "subduct")
	var entry: Dictionary = earth.seams()[1]
	var seam := Tooltips.seam(run, entry)
	check("seam" in String(seam["title"]).to_lower(), "a seam names its kind")
	check(seam["lines"].any(func(line: String) -> bool: return line.begins_with("Pressure 3 of 3")), "and its pressure")
	check(not seam["warnings"].is_empty(), "a full one warns that it wakes")
	var plate := Tooltips.plate(run, "fen")
	check(plate["title"].begins_with("Fen"), "a near plate names its kind")
	run.dispose()


func test_the_attack_comes_by_a_den_and_turns_with_it() -> void:
	var run := _run()
	var w := run.world
	w.roll_wave_sides()
	check_eq(w.wave_sides.size(), 1, "one side early on")
	var den_type: String = w.wave_side_dens[0]
	check(den_type != "", "the warband comes by a den's way")
	var den: Dictionary = w.dens.filter(func(d: Dictionary) -> bool: return d["type"] == den_type)[0]
	check(absf(angle_difference(w.wave_sides[0], Vector2(den["pos"]).angle())) < 0.001, "from where the den stands")
	w.earth.shift()
	w.roll_wave_sides()
	var moved: Dictionary = w.dens.filter(func(d: Dictionary) -> bool: return d["type"] == w.wave_side_dens[0])[0]
	check(absf(angle_difference(w.wave_sides[0], Vector2(moved["pos"]).angle())) < 0.001, "and after a turn, from where the earth carried it")
	var ways := EarthReport.ways(run)
	check("den" in ways[0] or "mound" in ways[0], "the threat card names the den")
	check(ways[0].contains("across the"), "and the ground it crosses")
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
	check_eq(w.wave_side_dens, ["", ""] as Array[String], "with every den swallowed, open country")
	check(absf(angle_difference(w.wave_sides[0], w.wave_sides[1])) >= apart - 0.001, "still apart")
	check(" ".join(EarthReport.ways(run)).contains("open country"), "and the threat card says so")
	run.dispose()


func test_the_earth_report_says_what_the_turn_did() -> void:
	var run := _run()
	var earth := run.world.earth
	check_eq(EarthReport.headline(run), "", "nothing to report before the first turn")
	var said := false
	for n in 13:
		earth.shift()
		var head := EarthReport.headline(run)
		check(head.begins_with("The earth turned"), "a headline every turn")
		var lines := EarthReport.lines(run)
		check(lines.size() <= EarthReport.MAX_LINES, "a few lines at most")
		if not lines.is_empty():
			said = true
	check(said, "something to say in a run's turns")
	run.dispose()


func _with_lodge(run: RunState) -> void:
	run.world.add_building("geomancer")
	run.world.buildings[-1]["work_left"] = 0.0


func _spell_cards(run: RunState) -> Array:
	return run.pick_offer.filter(func(c: Dictionary) -> bool: return c["kind"] == "spell")


func test_a_free_geomancer_offers_spells_at_dawn() -> void:
	var run := _run()
	run.people.offer_picks()
	check(_spell_cards(run).is_empty(), "no spell cards without a geomancer")
	_with_lodge(run)
	run.people.offer_picks()
	var cards := _spell_cards(run)
	check_eq(cards.size(), run.content.plates["spells"].size(), "one card per spell once the lodge stands")
	check(run.pick_offer.size() > cards.size(), "beside the newcomers")
	var at := run.pick_offer.find(cards.filter(func(c: Dictionary) -> bool: return c["spell"] == "ridge")[0])
	check(run.can_take_pick(at), "a spell card can be taken even with no room")
	run.choose_pick(at)
	check_eq(run.spell, {"id": "ridge", "nights_left": 2}, "the geomancer works on the ridge")
	check_eq(run.record.entry["picks"][-1]["taken"], "spell:ridge", "the pick is recorded")
	run.people.offer_picks()
	check(_spell_cards(run).is_empty(), "no spell cards while one is under way")
	run.cast_spell("wake")
	check_eq(run.spell["id"], "ridge", "and no second spell")
	run.dispose()


func test_a_spell_happens_when_its_nights_run_out() -> void:
	var run := _run()
	_with_lodge(run)
	run.cast_spell("sink_den")
	var dens := run.world.dens.size()
	run._work_spell()
	run._work_spell()
	check_eq(run.world.dens.size(), dens, "not yet after two nights")
	check_eq(int(run.spell["nights_left"]), 1, "one night left")
	run._work_spell()
	check(run.spell.is_empty(), "the geomancer is free again")
	check_eq(run.world.dens.size(), dens - 1, "a den sank on the third dawn")
	check_eq(run.world.earth.changes, 1, "the map is told the land changed")
	var spells: Array = run.record.entry["spells"]
	check_eq(spells[0]["cast"], "sink_den", "the cast is recorded")
	check_eq(spells[-1]["finished"], "sink_den", "and so is the finish")
	check_eq(int(spells[-1]["did"]["dens_swallowed"]), 1, "with what it did")
	run.dispose()


func test_holding_the_near_ring_keeps_it_still_for_one_turn() -> void:
	var run := _run()
	var earth := run.world.earth
	earth.finish_spell("hold", SeededRng.new(1))
	var near: Array = earth.rings[0]["seams"].duplicate()
	var far: Array = earth.rings[2]["seams"].duplicate()
	earth.shift()
	check_eq(earth.rings[0]["seams"], near, "the near ring held still")
	check(earth.rings[2]["seams"] != far, "the far ring still turned")
	check(bool(earth.last["held"]), "the shift says so")
	earth.shift()
	check(earth.rings[0]["seams"] != near, "then it turns again")
	run.dispose()


func test_waking_a_seam_takes_the_fullest_one_now() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	earth.rings[1]["kinds"][2] = "subduct"
	earth.rings[1]["pressure"][2] = 2
	earth.rings[0]["pressure"][1] = 1
	var grove := _grove(w, _beside(earth, 1, 2, true))
	var report := earth.last.duplicate(true)
	var line := earth.finish_spell("wake", SeededRng.new(1))
	check(line.contains("swallows"), "the story says what woke")
	check_eq(grove["type"], "embers", "the fullest seam swallowed its lip")
	check_eq(int(earth.rings[1]["pressure"][2]), 0, "and emptied")
	check_eq(int(earth.rings[0]["pressure"][1]), 1, "the others keep theirs")
	check_eq(earth.last, report, "the last turn's report is left alone")
	run.dispose()


func test_sinking_a_den_takes_the_attacks_den_and_leaves_its_hoard() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var shift_report := earth.last.duplicate(true)
	var type: String = w.wave_side_dens[0] if not w.wave_side_dens.is_empty() and w.wave_side_dens[0] != "" else ""
	earth.finish_spell("sink_den", SeededRng.new(1))
	if type != "":
		check(not w.dens.any(func(d: Dictionary) -> bool: return d["type"] == type and not d.get("camp", false)), "the attack's den is gone")
	check(w.nodes.any(func(n: Dictionary) -> bool: return n["type"] == "sunk_hoard"), "its hoard waits for a hero")
	check_eq(earth.last, shift_report, "the last turn's report is left alone")
	run.dispose()


func test_a_raised_ridge_blocks_the_way_sprouts_and_wears_away() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	w.wave_sides = [0.0]
	var nodes := w.nodes.size()
	var sd: Dictionary = run.content.plates["spells"]["ridge"]
	var mid := w.pathing.index_of(Vector2(float(sd["r"]), 0.0))
	check(not w.pathing.is_solid(mid), "open ground before")
	earth.finish_spell("ridge", SeededRng.new(1))
	check(w.pathing.is_solid(mid), "the ridge stands across the attack's way")
	check(earth.is_ridge(mid), "and the map draws it as a ridge")
	check_eq(w.nodes.size(), nodes + sd["sprouts"].size(), "stone and timber sprout by it")
	for n in w.nodes.slice(nodes):
		check(Vector2(n["pos"]).length() < float(sd["r"]), "on the town's side")
	for i in int(sd["lasts"]) - 1:
		earth.shift()
		check_eq(earth.raised_ridges.size(), 1, "it lasts a few turns")
		var a := float(earth.raised_ridges[0]["a"])
		check(w.pathing.is_solid(w.pathing.index_of(Vector2.from_angle(a) * float(sd["r"]))), "riding the near ring")
	earth.shift()
	check(earth.raised_ridges.is_empty(), "then wears away")
	run.dispose()


func test_a_sunk_den_leaves_a_hoard_and_a_bold_hero_digs_it_out() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	earth.last = {"swallowed": {}, "dens_swallowed": 0}
	var at: Vector2 = w.dens[0]["pos"]
	earth._swallow_den(0)
	var hoard: Array = w.nodes.filter(func(n: Dictionary) -> bool: return n["type"] == "sunk_hoard" and not n.get("gone", false))
	check_eq(hoard.size(), 1, "the den left a hoard")
	check_eq(hoard[0]["pos"], at, "where it went under")
	check(not w.folk.any(func(u: Unit) -> bool: return u.task_index == w.nodes.find(hoard[0])), "townsfolk never gather it")
	var hero: Unit = run.heroes[0] if not run.heroes.is_empty() else null
	if hero == null:
		run.dispose()
		return
	var greedy_wilds := 1.0
	check(w.hero_ai.find_for(hero, greedy_wilds) == w.nodes.find(hoard[0]), "a keen hero finds it")
	var before := hero.items.size() + hero.spares.size()
	w.hero_ai.dig_find(hero, w.nodes.find(hoard[0]))
	check(hoard[0]["gone"], "dug out and gone")
	check_eq(hero.items.size() + hero.spares.size(), before + 1, "the hero gained an item")
	run.dispose()


func test_earth_finds_give_earthborn_gear_a_tier_up() -> void:
	var content := Content.load_default()
	var rng := SeededRng.new(7)
	for n in 20:
		var item := Loot.earth_find(content, rng, 1, "neolithic")
		check(item["affixes"].has("earthborn"), "always earthborn")
		check(int(item["tier"]) >= 2, "a tier above a round-1 drop")
	for n in 200:
		check(not Loot.roll(content, rng, 9, "neolithic")["affixes"].has("earthborn"), "never an ordinary drop")
