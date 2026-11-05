extends TestCase
## The blueprint draft as a scene in the town (game/draft_stage.gd): where each offer goes, how the cards line up
## over the town, and that the camera goes there and back.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	return run


func test_each_offer_points_where_it_would_go() -> void:
	var run := _run()
	var a := DraftStage.anchor(run, {"building": "hut"})
	var k := run.world.town.choose_plot("hut")
	check_eq(a["plot"], k, "a building's card points at the plot it would place itself on")
	check_eq(a["at"], run.world.town.plots[k]["pos"], "there")
	check_eq(a["ghost"], "hut", "with a ghost of it")
	var craft: String = run.content.crafts.keys()[0]
	var c := DraftStage.anchor(run, {"craft": craft})
	check_eq(c["ghost"], run.content.crafts[craft]["workshop"], "a craft shows its workshop")
	var r := DraftStage.anchor(run, {"ring": true})
	check_eq(r["ring"], float(run.content.town["rings"][run.rings_open]["radius"]), "clearing a ring lights the next ring")
	check(r["ghost"] == "" and r["placed"], "and points at it, with no ghost")
	var up: String = run.content.upgrades.keys()[0]
	var u := DraftStage.anchor(run, {"upgrade": up})
	check_eq(u["lit"], run.content.upgrades[up]["building"], "an upgrade lights the building it changes")
	check(not u["placed"] or run.world.count_buildings(u["lit"], false) > 0, "pointing at one only when the town has it")
	check(DraftStage.reach(run, [a, c, r]) >= float(r["ring"]), "the camera takes in the ring to clear")
	run.dispose()


func test_cards_line_up_over_their_places_without_overlapping() -> void:
	var xs := DraftStage.spread([600.0, 610.0, 100.0, 1250.0], 120.0, 1264.0)
	check_eq(xs.size(), 4, "every card gets a place")
	var sorted := xs.duplicate()
	sorted.sort()
	for i in 3:
		check(float(sorted[i + 1]) - float(sorted[i]) >= 120.0 + DraftStage.GAP - 0.01, "cards don't overlap")
	check(float(sorted[0]) - 60.0 >= DraftStage.EDGE - 0.01 and float(sorted[3]) + 60.0 <= 1264.0 - DraftStage.EDGE + 0.01,
		"and stay on the map")
	check(float(xs[2]) < float(xs[0]) and float(xs[0]) < float(xs[1]) and float(xs[1]) < float(xs[3]),
		"in the order of the places they point at")
	check_eq(DraftStage.spread([0.0, 0.0, 0.0], 400.0, 1000.0), [], "too many to fit: none")
	check(DraftStage.card_scale(4, CardView.SHAPE[CardView.Size.MEDIUM], Vector2(1264, 405), 80.0) >= DraftStage.MIN_SCALE,
		"four offers fit over a 1280x720 screen's map above the hand")
	check_eq(DraftStage.card_scale(4, CardView.SHAPE[CardView.Size.MEDIUM], Vector2(700, 300), 80.0), 0.0,
		"a map too small shows the classic pop-up")


func test_the_camera_goes_to_the_town_and_back() -> void:
	var run := _run()
	var view := ArenaView.new()
	view.run = run
	view.size = Vector2(1264, 405)
	view.zoom = 1.2
	var d := DraftStage.new()
	var a := DraftStage.anchor(run, {"building": "hut"})
	d.start(view, [a], 1.6, Vector2(0, 30), 1000.0)
	d.update(view, 1000.0 + DraftStage.GLIDE_MS)
	check(is_equal_approx(view.zoom, 1.6) and view.pan.is_equal_approx(Vector2(0, 30)), "the camera pulls out to the town")
	d.finish(1500.0 + DraftStage.GLIDE_MS)
	d.start(view, [a], 1.6, Vector2(0, 30), 1500.0 + DraftStage.GLIDE_MS)
	check(d.choosing() and is_equal_approx(d.born, 1000.0), "laid out again (a refresh), the scene carries on")
	d.finish(3000.0)
	check(not d.choosing(), "the draft taken, the choosing ends")
	d.update(view, 3000.0 + DraftStage.LEAVE_MS)
	check(not d.active() and is_equal_approx(view.zoom, 1.2), "and the camera is back where it was")
	check(view.screen_at(Vector2(40, 0), view.zoom, view.pan).is_equal_approx(view._to_screen(Vector2(40, 0))),
		"screen_at agrees with the view at its own camera")
	view.free()
	run.dispose()


func test_a_pedlar_points_at_its_camp_spot() -> void:
	var c := DraftStage.camp(Vector2(120, -40))
	check_eq(c["at"], Vector2(120, -40), "the card points at where the camp would stand")
	check(c["ghost"] == "pedlar_camp" and int(c["plot"]) < 0 and c["placed"], "with a ghost of the camp, off the plots")
