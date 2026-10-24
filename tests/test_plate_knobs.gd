extends TestCase
## Relics and buildings that change the near plate kinds by tag (plate_knobs, Earth.kind_def).


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	for r: String in ["wood", "stone", "shells"]:
		run.stock[r] = 999
	return run


## A point on a near plate of `kind`, mid-ring and well inside the plate (Vector2.INF if none).
func _point_of_kind(earth: Earth, kind: String) -> Vector2:
	var ring: Dictionary = earth.rings[0]
	var seams: Array = ring["seams"]
	for k in seams.size():
		if ring["plate_kinds"][k] == kind:
			var mid := float(seams[k]) + fposmod(float(seams[(k + 1) % seams.size()]) - float(seams[k]), TAU) / 2.0
			return Vector2.from_angle(mid) * (float(ring["r0"]) + float(ring["r1"])) / 2.0
	return Vector2.INF


## Builds `type` and finishes it at once.
func _stand(run: RunState, type: String) -> Dictionary:
	check(run.build(type), "%s can be built" % type)
	var b: Dictionary = run.world.buildings[-1]
	b["work_left"] = 0.0
	run.world.market.refresh_prizes()
	return b


func test_bog_drowners_stake_slows_raiders_on_the_fen_only() -> void:
	var run := _run()
	var earth := run.world.earth
	var fen := _point_of_kind(earth, "fen")
	check(fen != Vector2.INF, "the run has a Fen")
	check(is_equal_approx(earth.walk_factor(fen, true), 0.7), "raiders wade the Fen at 70%")
	run.relics.append("bog_drowners_stake")
	check(is_equal_approx(earth.walk_factor(fen, true), 0.56), "with the stake a fifth slower again")
	check(is_equal_approx(earth.walk_factor(fen, false), 0.7), "your people are not slowed more")
	run.dispose()


func test_barrow_kings_lamp_keeps_the_dead_down_and_doubles_grave_goods() -> void:
	var run := _run()
	var earth := run.world.earth
	run.relics.append("barrow_kings_lamp")
	var kd := earth.kind_def("barrow")
	check_eq(float(kd["rise_chance"]), 0.0, "nobody rises on the Barrow")
	check(is_equal_approx(float(kd["grave_goods"]), 0.24), "grave goods twice as often")
	check_eq(String(kd["name"]), "Barrow", "the kind keeps its own data")
	run.dispose()


func test_thorn_witchs_veil_and_cairn_wardens_cord() -> void:
	var run := _run()
	var earth := run.world.earth
	run.relics.append("thorn_witchs_veil")
	run.relics.append("cairn_wardens_cord")
	check(is_equal_approx(float(earth.kind_def("greenwood")["sight"]), 0.85), "the Greenwood hides raiders less")
	check(is_equal_approx(float(earth.kind_def("greenwood")["regrow"]), 0.2), "and regrows more")
	check(is_equal_approx(float(earth.kind_def("stonefield")["raider_walk"]), 1.0), "raiders lose the Stonefield's speed")
	check(is_equal_approx(float(earth.kind_def("stonefield")["sight"]), 1.4), "towers see farther across it")
	check(is_equal_approx(float(earth.kind_def("fen")["walk"]), 0.7), "other kinds are untouched")
	run.dispose()


func test_a_causeway_speeds_everyone_across_the_fen_once_it_stands() -> void:
	var run := _run()
	var earth := run.world.earth
	var fen := _point_of_kind(earth, "fen")
	check(run.build("causeway"), "a causeway can be ordered")
	run.world.market.refresh_prizes()
	check(is_equal_approx(earth.walk_factor(fen, false), 0.7), "while it is being built nothing changes")
	run.world.buildings[-1]["work_left"] = 0.0
	run.world.market.refresh_prizes()
	check(is_equal_approx(earth.walk_factor(fen, false), 0.9), "once it stands your people cross at 90%")
	check(is_equal_approx(earth.walk_factor(fen, true), 0.9), "and so do raiders")
	run.dispose()


func test_a_lookout_cairn_sees_farther_on_open_and_wooded_plates() -> void:
	var run := _run()
	var earth := run.world.earth
	_stand(run, "lookout_cairn")
	check(is_equal_approx(float(earth.kind_def("stonefield")["sight"]), 1.45), "farther across the Stonefield")
	check(is_equal_approx(float(earth.kind_def("greenwood")["sight"]), 0.8), "and into the Greenwood")
	var wood := _point_of_kind(earth, "greenwood")
	if wood != Vector2.INF:
		check(is_equal_approx(earth.sight_at(wood), 0.8), "the towers' reach follows")
	run.dispose()


func test_a_plates_hover_names_what_changes_it() -> void:
	var run := _run()
	run.relics.append("bog_drowners_stake")
	var lines: Array = Tooltips.plate(run, "fen")["lines"]
	check(lines.any(func(l: String) -> bool: return l.contains("Bog-drowner's Stake")), "the Fen's hover names the stake")
	var other: Array = Tooltips.plate(run, "barrow")["lines"]
	check(not other.any(func(l: String) -> bool: return l.begins_with("Changed by")), "the Barrow's doesn't")
	run.dispose()
