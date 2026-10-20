extends TestCase
## Townsfolk sharing a leaning form a band: bigger loads of their goods at 3, faster gathering at 6.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	return run


func _add(run: RunState, leaning: String, n: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for i in n:
		out.append(run.world.folk_ai.add_folk("tribesperson", leaning))
	run.world.folk_ai.begin_step()
	return out


func test_two_woodcutters_are_no_band() -> void:
	var run := _run()
	var w := run.world
	var cutters := _add(run, "woodcutter", 2)
	var plain := w.folk_ai.carry_of(cutters[0])
	check(w.folk_ai.band_tier(cutters[0]).is_empty(), "two is not a band yet")
	check_eq(w.folk_ai.carry_of(cutters[0], "wood"), plain, "so they carry the usual load of wood")


func test_three_woodcutters_carry_more_wood_only() -> void:
	var run := _run()
	var w := run.world
	var cutters := _add(run, "woodcutter", 3)
	var plain := w.folk_ai.carry_of(cutters[0])
	check_eq(w.folk_ai.carry_of(cutters[0], "wood"), plain + 1, "a band of three brings 1 more wood a trip")
	check_eq(w.folk_ai.carry_of(cutters[0], "food"), plain, "but no more food")
	check_eq(w.folk_ai.gather_time(cutters[0], "wood"), w.folk_ai.gather_time(cutters[0]), "and gathers no faster yet")


func test_six_gather_faster() -> void:
	var run := _run()
	var w := run.world
	var cutters := _add(run, "woodcutter", 6)
	check(w.folk_ai.gather_time(cutters[0], "wood") < w.folk_ai.gather_time(cutters[0]) * 0.7, "a band of six gathers wood faster")
	check_eq(w.folk_ai.carry_of(cutters[0], "wood"), w.folk_ai.carry_of(cutters[0]) + 1, "and still carries 1 more")


func test_other_leanings_and_the_dead_do_not_count() -> void:
	var run := _run()
	var w := run.world
	var cutters := _add(run, "woodcutter", 2)
	_add(run, "forager", 1)
	var third := _add(run, "woodcutter", 1)[0]
	check(not w.folk_ai.band_tier(cutters[0]).is_empty(), "three woodcutters make a band")
	third.alive = false
	w.folk_ai.begin_step()
	check(w.folk_ai.band_tier(cutters[0]).is_empty(), "with one dead, the band breaks")


func test_band_loads_are_recorded() -> void:
	var run := _run()
	var w := run.world
	w.nodes.clear()
	w._add_node("grove", Vector2(0, 150))
	var cutters := _add(run, "woodcutter", 3)
	for u in cutters:
		u.pos = Vector2.ZERO
	run.stock["wood"] = 0
	for i in 400:
		w.folk_ai.begin_step()
		w.folk_ai.folk_tick(cutters[0])
	check(int(run.record.entry["gathered_band"].get("wood", 0)) > 0, "what the band added shows in the record")
	run.record.end_round()
	check_eq(int(run.record.rounds[-1]["bands_end"].get("woodcutter", 0)), 1, "the round's end records the band's tier")


func test_dawn_card_says_when_it_forms_a_band() -> void:
	var run := _run()
	_add(run, "quarrier", 2)
	var line := Tooltips.band_line(run, "tribesperson", "quarrier", true)
	check(line.contains("Band of 3"), "a third quarrier makes a band (%s)" % line)
	check(line.contains("At 6"), "and the line says what six would bring (%s)" % line)
	var none := Tooltips.band_line(run, "tribesperson", "forager", true)
	check(none.contains("3 make a band"), "a first forager is told how many make a band (%s)" % none)
