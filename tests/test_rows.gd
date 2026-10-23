extends TestCase
## Rows: drafted like blueprints, they order two buildings together, side by side, for less; only they make a combo (data/combos.json).


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	run.stock["wood"] = 999
	run.stock["stone"] = 999
	run.stock["shells"] = 999
	return run


## Gives the town this row as if drafted.
func _deal(run: RunState, id: String) -> void:
	run.hand.row_blueprints = [id] as Array[String]


func _finish(run: RunState) -> void:
	for b in run.world.buildings:
		b["work_left"] = 0.0


func test_a_row_card_builds_both_side_by_side() -> void:
	var run := _run()
	_deal(run, "kitchen_garden")
	var before := run.world.buildings.size()
	var wood := int(run.stock["wood"])
	check(run.hand.order_row("kitchen_garden"), "ordered")
	check_eq(run.world.buildings.size(), before + 2, "two buildings")
	var garden: Dictionary = run.world.buildings[before]
	var hut: Dictionary = run.world.buildings[before + 1]
	check_eq([garden["type"], hut["type"]], ["garden", "hut"], "a garden and a hut")
	check(run.world.town.cluster_plots(garden["plot"]).has(hut["plot"]), "in one cluster")
	var full := int(run.content.buildings["garden"]["cost"]["wood"]) + int(run.content.buildings["hut"]["cost"]["wood"])
	check_eq(wood - int(run.stock["wood"]), int(full * (1.0 - run.content.num("row_discount"))), "a fifth cheaper")
	check(run.hand.can_order_row("kitchen_garden"), "the row stays on offer")


func test_the_row_bonus_comes_once_both_stand() -> void:
	var run := _run()
	_deal(run, "kitchen_garden")
	var alone := run.food_grown_daily()
	run.hand.order_row("kitchen_garden")
	check_eq(run.food_grown_daily(), alone, "nothing while they are being built")
	_finish(run)
	var garden := run.world.buildings.size() - 2
	check_eq(run.world.town.combos_of(garden), ["kitchen_garden"] as Array[String], "the garden is in a row")
	check_eq(run.food_grown_daily(), alone + int(run.content.buildings["garden"]["daily"]["food"]) + 3, "the garden's food and 3 more")


func test_buildings_ordered_alone_make_no_combo() -> void:
	var run := _run()
	run.build("market")
	run.build("knapper")
	run.build("arms_stall")
	_finish(run)
	for i in run.world.buildings.size():
		check(run.world.town.combos_of(i).is_empty(), "no combo without a row card")


func test_a_workshop_row_works_twice_as_fast() -> void:
	var run := _run()
	run.build("market")
	_deal(run, "blade_row")
	check(run.hand.order_row("blade_row"), "the stall's market stands")
	_finish(run)
	var knapper := run.world.buildings.size() - 2
	check_eq(run.world.town.combo_effect(knapper, "craft_speed"), 1.0, "twice as fast")


func test_a_row_needs_its_buildings_allowed() -> void:
	var run := _run()
	check(not run.row_allowed("blade_row"), "no arms stall before a market")
	check(not run.row_allowed("bronze_row"), "nor bronze before the bronze age")
	check(run.row_allowed("kitchen_garden"), "a garden and a hut can go up")


func test_drafts_offer_rows() -> void:
	var run := _run()
	var dealt := 0
	for r in 6:
		run.hand._fill(SeededRng.stream(r, "t"))
		dealt += run.hand.rows.size()
		for c in run.hand.rows:
			check(run.hand._row_draftable(c["row"]), "only rows in reach of the age")
	check(dealt > 0, "rows come up in the draft")
	check(dealt <= 6 * run.content.int_num("row_cards"), "at most row_cards a draft")


func test_drafting_a_row_drafts_its_buildings() -> void:
	var run := _run()
	run.hand.rows = [{"row": "drying_greens", "need": ""}] as Array[Dictionary]
	check(run.hand.draft_row("drying_greens"), "drafted")
	check(run.hand.offers_row("drying_greens"), "the row is on offer for good")
	check(run.hand.blueprints.has("drying_rack"), "its drying rack is a blueprint")
	check(not run.hand.blueprints.has("garden"), "its garden is a basic, not a blueprint")


func test_rows_are_recorded() -> void:
	var run := _run()
	_deal(run, "kitchen_garden")
	run.hand.order_row("kitchen_garden")
	_finish(run)
	run.begin_round()
	run.record.end_round()
	check_eq(int(run.record.rounds[-1]["combos_end"].get("kitchen_garden", 0)), 1, "the round's end counts rows")
	check(run.record.rounds[-1]["actions"].any(func(a: Dictionary) -> bool: return a["kind"] == "row"), "and the order")


func test_hover_names_the_row() -> void:
	var run := _run()
	_deal(run, "kitchen_garden")
	run.hand.order_row("kitchen_garden")
	_finish(run)
	var garden := run.world.buildings.size() - 2
	var lines := Tooltips.combo_lines(run, "garden", garden)
	check(lines.any(func(l: String) -> bool: return l.begins_with("Row: Kitchen garden")), "the garden's hover names its row (%s)" % [lines])


func test_bots_take_row_cards() -> void:
	# Whether a row is drafted at all depends on the draws, so look at a second run if the first had none.
	var rows := 0
	for s in [4821, 61823]:
		for rd: Dictionary in bot_record(s, "balanced")["rounds"]:
			for a: Dictionary in rd["actions"]:
				if a["kind"] == "row":
					rows += 1
		if rows > 0:
			break
	check(rows > 0, "the bot orders rows")
