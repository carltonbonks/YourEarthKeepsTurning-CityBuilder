extends TestCase
## The dawn muster (game/dawn_muster.gd): the dawn pick as a scene round the hearth. Who stands in each card's group,
## where the cards and groups go on the map, and that the scene only moves people on screen.


## A founded run at its first dawn with the given cards on offer.
func _dawn(cards: Array) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	run.pick_offer.clear()
	for c: Dictionary in cards:
		var card := {"cost": 0}
		card.merge(c)
		run.pick_offer.append(card)
	run.phase = RunState.Phase.PICK
	return run


func test_a_townsfolk_card_shows_its_band_with_the_newcomer_holding_the_banner() -> void:
	var run := _dawn([{"kind": "folk", "role": "tribesperson"}])
	var g: Dictionary = DawnMuster.gather(run)[0]
	check_eq(g["stand_ins"].size(), 1, "one newcomer stands in")
	check_eq(g["stand_ins"][0]["id"], "tribesperson", "of the card's role")
	var have := run.count_role("tribesperson")
	check_eq(g["members"].size() + int(g["more"]), have, "the band shown plus the count beside it is everyone of that role")
	check(g["members"].size() + 1 <= DawnMuster.MAX_FIGURES, "never more figures than a group shows")
	check(g["members"].all(func(u: Unit) -> bool: return u.type_id == "tribesperson"), "only that role stands with it")
	run.dispose()


func test_each_kind_of_card_gets_its_own_group() -> void:
	var run := _dawn([])
	var hero := run.people.make_hero(true)
	var venture: String = run.content.ventures.keys()[0]
	for i in 8:
		run.world.folk_ai.add_folk("tribesperson")
	run.pick_offer = [{"kind": "hero", "role": "hero", "cost": 0, "hero": hero},
		{"kind": "family", "role": "family", "cost": 0, "roles": ["tribesperson", "warrior"]},
		{"kind": "venture", "role": "venture", "cost": 0, "venture": venture},
		{"kind": "folk", "role": "tribesperson", "cost": 0}]
	var groups := DawnMuster.gather(run)
	check_eq(groups.size(), 4, "one group per card, in the cards' order")
	check(groups[0]["stand_ins"][0]["hero"], "a hero card is the hero alone, in their ring")
	check_eq(groups[0]["stand_ins"][0]["id"], hero.type_id, "drawn as their class")
	check_eq(groups[1]["stand_ins"].map(func(s: Dictionary) -> String: return s["id"]), ["tribesperson", "warrior"],
		"a family is its members, all newcomers")
	var terms := run.people.venture_terms(venture, run.pick_offer[2])
	check_eq(groups[2]["kit"], "venture", "a venture's party is packed for the trip")
	check_eq(groups[2]["members"].size() + groups[2]["stand_ins"].size(), int(terms["send"]), "one figure per person sent")
	check_eq(groups[2]["lose"], terms["lose"], "with the losses its card says")
	var seen := {}
	for g: Dictionary in groups:
		for u: Unit in g["members"]:
			check(not seen.has(u.get_instance_id()), "nobody stands in two groups")
			seen[u.get_instance_id()] = true
	run.dispose()


func test_the_cards_stand_in_a_row_that_fits_or_give_way_to_the_pop_up() -> void:
	for n in [3, 4, 5, 6]:
		var shape: Vector2 = CardView.SHAPE[CardView.Size.LARGE if n <= 4 else CardView.Size.MEDIUM]
		var plan := DawnMuster.layout(n, shape, Vector2(1264, 585), 150.0)
		check(not plan.is_empty(), "%d cards fit over a 1280x720 screen's map" % n)
		var xs: Array = plan["xs"]
		var w: float = Vector2(plan["card"]).x
		for i in n - 1:
			check(float(xs[i + 1]) - float(xs[i]) >= w, "cards don't overlap")
		check(float(xs[0]) - w / 2.0 >= 0.0 and float(xs[n - 1]) + w / 2.0 <= 1264.0, "and stay on the map")
		check(float(plan["feet_y"]) > float(plan["card_bottom"]), "the groups stand under their cards")
		check(float(plan["hearth_y"]) < 585.0 - DawnMuster.FOOTER, "and the hearth shows above the skip button")
	check(DawnMuster.layout(4, CardView.SHAPE[CardView.Size.LARGE], Vector2(700, 400), 150.0).is_empty(),
		"a map too small for readable cards shows the classic pop-up")


func test_a_group_stands_behind_its_banner_holder() -> void:
	check_eq(DawnMuster.formation(0, 5, 160.0), Vector2.ZERO, "the holder stands where the pole comes down")
	var spots := {}
	for k in range(1, 9):
		var p := DawnMuster.formation(k, 8, 160.0)
		check(p.y > 0.0, "the rest stand in front, nearer the viewer")
		check(not spots.has(p), "each in a place of its own")
		spots[p] = true


func test_the_scene_moves_people_on_screen_only_and_ends_after_a_pick() -> void:
	var run := _dawn([{"kind": "folk", "role": "tribesperson"}])
	var view := ArenaView.new()
	view.run = run
	view.size = Vector2(1264, 585)
	var plan := DawnMuster.layout(1, CardView.SHAPE[CardView.Size.LARGE], view.size, 150.0)
	var m := DawnMuster.new()
	m.start(run, view, plan, 1000.0)
	var g: Dictionary = m.groups[0]
	check(not g["members"].is_empty(), "the band gathers")
	var u: Unit = g["members"][0]
	var was := u.pos
	check_eq(m.place(u, 1000.0), was, "everyone starts where they are")
	check(m.place(u, 1000.0 + DawnMuster.GATHER_MS).distance_to(was) > 1.0, "and walks to the group")
	check_eq(u.pos, was, "the sim never moves them")
	m.update(view, 1000.0 + DawnMuster.GLIDE_MS)
	check_eq(view.zoom, minf(DawnMuster.ZOOM, ArenaView.MAX_ZOOM), "the camera closes in")
	check(m.choosing(), "the player chooses")
	m.finish(0, 3000.0)
	check(not m.choosing(), "a pick ends the choosing")
	m.update(view, 3000.0 + DawnMuster.LEAVE_MS)
	check(not m.active(), "and the scene once everyone has gone back")
	check(is_equal_approx(view.zoom, 1.2), "with the camera back where it was")
	view.free()
	run.dispose()
