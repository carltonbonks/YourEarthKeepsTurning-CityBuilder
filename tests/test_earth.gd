extends TestCase
## The shifting earth (sim/earth.gd, data/plates.json): plates turn round the still town between rounds,
## and their seams swallow, raise ridges or open rifts.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


## Shifts the earth until the next shift will do `kind` somewhere; returns that forecast entry ({} if never).
func _shift_until(earth: Earth, kind: String, limit := 30) -> Dictionary:
	for n in limit:
		for entry: Dictionary in earth.forecast():
			if entry["kind"] == kind:
				return entry
		earth.shift()
	return {}


## A point in ring ri that the next shift swallows, or Vector2.INF.
func _doomed_point(earth: Earth, ri: int) -> Vector2:
	var ring: Dictionary = earth.rings[ri]
	for step in 720:
		for r in [0.3, 0.5, 0.7]:
			var p := Vector2.from_angle(TAU * step / 720.0) * lerpf(float(ring["r0"]), float(ring["r1"]), r)
			if earth.doomed(p):
				return p
	return Vector2.INF


func test_plates_turn_round_a_still_town() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var still: Array = w.nodes.filter(func(n: Dictionary) -> bool: return earth.ring_at(n["pos"]) < 0)
	var still_at: Array = still.map(func(n: Dictionary) -> Vector2: return n["pos"])
	var den_at: Vector2 = w.dens[0]["pos"]
	var plots_before: Array = w.town.plots.map(func(p: Dictionary) -> Vector2: return p["pos"])
	earth.shift()
	check(not still.is_empty(), "some nodes sit on the still ground near the town")
	for i in still.size():
		check_eq(still[i]["pos"], still_at[i], "nodes inside the first plate ring never move")
	check(absf(angle_difference(den_at.angle(), Vector2(w.dens[0]["pos"]).angle())) > deg_to_rad(1.0), "the den rode its plate round")
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
	check(run.story.any(func(line: String) -> bool: return line.begins_with("The earth turns")), "the story tells of it")
	run.dispose()


func test_plates_never_shrink_away() -> void:
	for seed_value in [11, 4821, 9001]:
		var run := _run(seed_value)
		var earth := run.world.earth
		var min_width := deg_to_rad(float(run.content.plates["min_plate_degrees"])) - 0.001
		for n in 13:
			earth.shift()
			for ring in earth.rings:
				var seams: Array = ring["seams"]
				var total := 0.0
				for k in seams.size():
					var width := fposmod(float(seams[(k + 1) % seams.size()]) - float(seams[k]), TAU)
					check(width >= min_width, "seed %d: a plate kept at least the narrowest width" % seed_value)
					total += width
				check(is_equal_approx(total, TAU), "seed %d: the plates still go all the way round" % seed_value)
		run.dispose()


func test_subducting_seam_swallows_what_the_forecast_said() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	check(not _shift_until(earth, "subduct").is_empty(), "a seam closes by subducting within a run")
	var doomed := []
	var safe := []
	for node in w.nodes:
		if w.node_active(node) and earth.ring_at(node["pos"]) >= 0:
			(doomed if earth.doomed(node["pos"]) else safe).append([node, node["type"]])
	for ri in earth.rings.size():
		var p := _doomed_point(earth, ri)
		if p != Vector2.INF:
			w.nodes.append({"type": "grove", "gives": "wood", "pos": p, "amount": 24, "max": 24,
				"heroes_only": false, "wild": false, "age": ""})
			doomed.append([w.nodes[-1], "grove"])
			break
	check(not doomed.is_empty(), "something stands where the earth will swallow")
	earth.shift()
	for pair: Array in doomed:
		check_eq(pair[0]["type"], "embers", "a swallowed %s turned to embers" % pair[1])
		check_eq(pair[0]["gives"], "fuel", "embers burn as fuel")
		check(not w.regrows(pair[0]), "embers never grow back")
	for pair: Array in safe:
		check_eq(pair[0]["type"], pair[1], "a node the forecast spared is still there")
	check(int(earth.last["swallowed"].get("grove", 0)) >= 1, "the shift reports what it swallowed")
	run.dispose()


func test_swallowed_den_takes_its_wanderers() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var far := earth.rings.size() - 1
	var p := Vector2.INF
	for n in 30:
		p = _doomed_point(earth, far)
		if p != Vector2.INF:
			break
		earth.shift()
	check(p != Vector2.INF, "a far seam swallows something within a run")
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
	run.dispose()


func test_colliding_seam_raises_a_ridge_with_a_pass() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var entry := _shift_until(earth, "collide")
	check(not entry.is_empty(), "a seam collides within a run")
	earth.shift()
	var ring: Dictionary = earth.rings[int(entry["ring"])]
	var k := int(entry["seam"])
	check(int(ring["ridges"][k]) >= 1, "the colliding seam has a ridge")
	check(not earth.ridge_cells().is_empty(), "the ridge is on the ground")
	var a := float(ring["seams"][k])
	var mid := (float(ring["r0"]) + float(ring["r1"])) / 2.0
	check(w.pathing.is_solid(w.pathing.index_of(Vector2.from_angle(a) * (float(ring["r0"]) + 20.0))), "nobody walks over the ridge")
	check(not w.pathing.is_solid(w.pathing.index_of(Vector2.from_angle(a) * mid)), "its pass in the middle is open")
	for node in w.nodes:
		check(not w.pathing.is_solid(w.pathing.index_of(node["pos"])) or earth.ring_at(node["pos"]) < 0, "no node is left on a ridge")
	check(w.pathing.connected(Vector2.from_angle(a - 0.05) * (float(ring["r0"]) + 20.0),
		Vector2.from_angle(a + 0.05) * (float(ring["r0"]) + 20.0)), "the far side is still reachable")
	run.dispose()


func test_tall_ridges_raise_upthrust_stone() -> void:
	var run := _run()
	var earth := run.world.earth
	var raised := 0
	for n in 13:
		earth.shift()
		raised += int(earth.last["raised"].get("obsidian", 0))
	check(raised >= 1, "a ridge broke open obsidian in a neolithic run")
	check(raised <= int(run.content.plates["upthrust_cap"]) * 3, "but not without limit")
	run.dispose()


func test_rifts_open_raw_ground_and_grow_fresh_plants() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	var grew := 0
	var saw_raw := false
	for n in 13:
		var before := w.nodes.size()
		earth.shift()
		grew += w.nodes.size() - before - earth.last["raised"].values().reduce(func(x: int, y: int) -> int: return x + y, 0)
		for strip in earth.raw:
			var ring: Dictionary = earth.rings[int(strip["ring"])]
			var mid_angle := float(strip["a0"]) + fposmod(float(strip["a1"]) - float(strip["a0"]), TAU) / 2.0
			var p := Vector2.from_angle(mid_angle) * (float(ring["r0"]) + float(ring["r1"])) / 2.0
			if earth.raw_at(p) and w.pathing.ground[w.pathing.index_of(p)] in [Pathing.THICKET, Pathing.TRAIL, Pathing.PATH]:
				saw_raw = true
	check(saw_raw, "rifts leave raw, slow ground")
	check(grew >= 1, "fresh plants took root in a rift")
	run.dispose()


func test_trails_ride_their_plate() -> void:
	var run := _run()
	var w := run.world
	var p := w.pathing
	var ring: Dictionary = w.earth.rings[0]
	var r := (float(ring["r0"]) + float(ring["r1"])) / 2.0
	# A plate's middle, well away from any seam.
	var seams: Array = ring["seams"]
	var mid := float(seams[0]) + fposmod(float(seams[1]) - float(seams[0]), TAU) / 2.0
	var at := Vector2.from_angle(mid) * r
	p.set_ground(p.index_of(at), Pathing.TRAIL)
	var turn := w.earth.next_turn(at)
	w.earth.shift()
	check_eq(p.ground[p.index_of(at.rotated(turn))], Pathing.TRAIL, "the trail square moved with its plate")
	run.dispose()


func test_swallowed_paving_is_paid_back() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	check(not _shift_until(earth, "subduct").is_empty(), "a seam subducts")
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
	for n in 5:
		a.world.earth.shift()
		b.world.earth.shift()
	check_eq(a.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]),
		b.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]), "nodes end up in the same places")
	check_eq(a.world.earth.last, b.world.earth.last, "the shifts did the same things")
	a.dispose()
	b.dispose()


func test_a_still_earth_when_turned_off() -> void:
	var content := Content.load_default()
	content.plates["enabled"] = false
	var run := RunState.new(content, 4821)
	var before: Array = run.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"])
	run.world.earth.shift()
	check_eq(run.world.nodes.map(func(n: Dictionary) -> Vector2: return n["pos"]), before, "nothing moves")
	check(run.world.earth.forecast().is_empty(), "and nothing is forecast")
	run.dispose()


func test_record_has_each_shift() -> void:
	var rec := bot_record()
	var rounds: Array = rec["rounds"]
	check(not rounds[0].has("shift"), "no shift before round 1")
	if rounds.size() > 1:
		var shift: Dictionary = rounds[1].get("shift", {})
		for key in ["shift", "swallowed", "dens_swallowed", "ridges", "raised", "rifts", "grown", "roads_refunded"]:
			check(shift.has(key), "round 2's shift has %s" % key)
		check_eq(int(shift.get("shift", 0)), 1, "it was the first shift")


func test_hover_text_warns_of_the_next_shift() -> void:
	var run := _run()
	var w := run.world
	var earth := w.earth
	check(not _shift_until(earth, "subduct").is_empty(), "a seam subducts")
	var p := Vector2.INF
	for ri in earth.rings.size():
		p = _doomed_point(earth, ri)
		if p != Vector2.INF:
			break
	w.nodes.append({"type": "grove", "gives": "wood", "pos": p, "amount": 24, "max": 24, "heroes_only": false, "wild": false, "age": ""})
	var tip := Tooltips.node(run, w.nodes[-1])
	check(tip["warnings"].any(func(line: String) -> bool: return "swallows" in line), "a doomed grove warns of it")
	var entry: Dictionary = earth.forecast()[0]
	var seam := Tooltips.seam(run, entry)
	check(seam["lines"].any(func(line: String) -> bool: return line.begins_with("Next shift")), "a seam says what the next shift does")
	run.dispose()
