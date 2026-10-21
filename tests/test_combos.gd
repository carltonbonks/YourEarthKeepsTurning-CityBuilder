extends TestCase
## Buildings in the same cluster of plots help each other (data/combos.json).


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.stock["wood"] = 999
	run.stock["stone"] = 999
	run.stock["shells"] = 999
	return run


## Puts a finished building of this type on plot k.
func _place(run: RunState, type: String, k: int) -> int:
	var w := run.world
	w.buildings.append({"type": type, "plot": k, "pos": w.town.plots[k]["pos"], "work_left": 0.0, "cooldown_left": 0.0,
		"hp": 0.0, "goods": [], "craft": "", "craft_left": 0.0, "craft_tier": 1, "made": 0})
	w.town.occupy(k, w.buildings.size() - 1)
	return w.buildings.size() - 1


## Two free plots side by side in one cluster, and one free plot in another cluster of the same ring.
func _plots(run: RunState) -> Array[int]:
	var town := run.world.town
	for k in town.plots.size():
		var mates := town.cluster_plots(k)
		if town.plots[k]["lane"] or mates.size() < 2 or not town.plot_free(k) or not town.plot_free(mates[1]):
			continue
		for far in town.plots.size():
			if town.plots[far]["ring"] == town.plots[k]["ring"] and not town.plots[far]["lane"] and town.plot_free(far) \
					and not mates.has(far):
				return [k, mates[1], far]
	return []


func test_a_cluster_runs_between_lanes() -> void:
	var run := _run()
	var town := run.world.town
	for k in town.plots.size():
		if town.plots[k]["lane"]:
			continue
		var mates := town.cluster_plots(k)
		check(mates.size() >= 1 and mates.size() <= int(run.content.town["cluster"]) + 1, "a cluster is a few plots (%d)" % mates.size())
		check(mates.all(func(p: int) -> bool: return not town.plots[p]["lane"] and town.plots[p]["ring"] == town.plots[k]["ring"]),
			"all in one ring, no lanes")


func test_knapper_beside_arms_stall_works_faster() -> void:
	var run := _run()
	var p := _plots(run)
	var knapper := _place(run, "knapper", p[0])
	check(run.world.town.combos_of(knapper).is_empty(), "alone, no combo")
	_place(run, "arms_stall", p[1])
	check_eq(run.world.town.combos_of(knapper), ["blade_row"] as Array[String], "beside the arms stall: blade row")
	check_eq(run.world.town.combo_effect(knapper, "craft_speed"), 0.5, "works 50% faster")


func test_partner_in_another_cluster_does_not_count() -> void:
	var run := _run()
	var p := _plots(run)
	var knapper := _place(run, "knapper", p[0])
	_place(run, "arms_stall", p[2])
	check(run.world.town.combos_of(knapper).is_empty(), "a stall in another cluster is no help")


func test_unfinished_partner_does_not_count() -> void:
	var run := _run()
	var p := _plots(run)
	var knapper := _place(run, "knapper", p[0])
	var stall := _place(run, "arms_stall", p[1])
	run.world.buildings[stall]["work_left"] = 5.0
	check(run.world.town.combos_of(knapper).is_empty(), "the stall must be finished")


func test_kitchen_garden_grows_more_food() -> void:
	var run := _run()
	var p := _plots(run)
	_place(run, "garden", p[0])
	var alone := run.food_grown_daily()
	_place(run, "hut", p[1])
	check_eq(run.food_grown_daily(), alone + 1, "a garden beside a hut brings 1 more food")


func test_buildings_lean_toward_combos() -> void:
	var run := _run()
	var p := _plots(run)
	_place(run, "arms_stall", p[0])
	check(run.world.town._completes_combo("knapper", p[1]), "the plot beside the stall would make a combo")
	check(not run.world.town._completes_combo("knapper", p[2]), "a plot in another cluster would not")


func test_combos_are_recorded() -> void:
	var run := _run()
	var p := _plots(run)
	_place(run, "knapper", p[0])
	_place(run, "arms_stall", p[1])
	run.begin_round()
	run.record.end_round()
	check_eq(int(run.record.rounds[-1]["combos_end"].get("blade_row", 0)), 1, "the round's end counts combos")


func test_hover_names_the_combo() -> void:
	var run := _run()
	var p := _plots(run)
	var knapper := _place(run, "knapper", p[0])
	_place(run, "arms_stall", p[1])
	var lines := Tooltips.combo_lines(run, "knapper", knapper)
	check(lines.any(func(l: String) -> bool: return l.begins_with("Combo: Blade row")), "the knapper's hover names its combo (%s)" % [lines])
	check_eq(Tooltips.combo_hint(run, "smoke_hut"), "", "no hint without a partner")
	check_eq(Tooltips.combo_hint(run, "hide_rack"), "", "nor for an unrelated building")
