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


func test_a_venture_party_walks_out_and_comes_home_short_of_who_was_lost() -> void:
	var run := _dawn([])
	for i in 8:
		run.world.folk_ai.add_folk("tribesperson")
	var venture: String = run.content.ventures.keys()[0]
	run.pick_offer = [{"kind": "venture", "role": "venture", "cost": 0, "venture": venture},
		{"kind": "folk", "role": "tribesperson", "cost": 0}]
	var view := ArenaView.new()
	view.run = run
	view.size = Vector2(1264, 585)
	var plan := DawnMuster.layout(2, CardView.SHAPE[CardView.Size.LARGE], view.size, 150.0)
	var m := DawnMuster.new()
	m.start(run, view, plan, 1000.0)
	var party: Array = m.groups[0]["members"].duplicate()
	var sent: int = party.size() + m.groups[0]["stand_ins"].size()
	m.come_home(0, 2, 3000.0)
	check(m.homecoming() and not m.choosing(), "the party sets off and the choosing is over")
	check(party.all(func(u: Unit) -> bool: return m.hides(u)), "the party's own people are drawn as the party meanwhile")
	var ours := m.stand_ins.filter(func(st: Dictionary) -> bool: return int(st["group"]) == 0)
	check_eq(ours.size(), sent, "everyone sent walks out")
	check_eq(ours.filter(func(st: Dictionary) -> bool: return st.get("lost", false)).size(), 2, "and two will not come back")
	var st: Dictionary = ours[0]
	check(m.stand_in_place(st, 3000.0 + DawnMuster.HOME_OUT_MS).length() > Vector2(st["spot"]).length() + 1.0,
		"out of the town, away from the hearth")
	var lost: Dictionary = ours.filter(func(s: Dictionary) -> bool: return s.get("lost", false))[0]
	check_eq(m.stand_in_fade(lost, 3000.0 + DawnMuster.HOME_OUT_MS + DawnMuster.HOME_AWAY_MS), 0.0, "the lost never come back")
	var back := 3000.0 + DawnMuster.HOME_OUT_MS + DawnMuster.HOME_AWAY_MS + DawnMuster.HOME_BACK_MS
	check(m.home_back(back), "the rest come home")
	check_eq(m.stand_in_place(st, back), st["spot"], "to their places")
	var newcomer: Dictionary = m.stand_ins.filter(func(s: Dictionary) -> bool: return int(s["group"]) == 1)[0]
	check(m.stand_in_fade(newcomer, back) < 0.01, "the other groups have gone back to work")
	m.finish(-1, back + 500.0)
	check(not m.homecoming() and not m.hides(party[0]), "Carry on sends the party back to work as themselves")
	m.update(view, back + 500.0 + DawnMuster.LEAVE_MS)
	check(not m.active(), "and the scene ends")
	view.free()
	run.dispose()


func test_the_caravan_camps_outside_the_town_by_its_moot() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	check(not CaravanCamp.here(run), "no wagons before the caravan comes")
	run.stock["wood"] = 999
	run.stock["stone"] = 999
	run.stock["shells"] = 999
	for i in 8:
		run.build("hut")
	for b in run.world.buildings:
		b["work_left"] = 0.0
	for i in maxi(0, 12 - run.population()):
		run.world.folk_ai.add_folk("tribesperson")
	for type in ["market", "bronze_moot"]:
		check(run.build(type), "can order a %s" % type)
		run.world.buildings.back()["work_left"] = 0.0
		run.on_building_done(type)
	check(CaravanCamp.here(run), "the wagons come with the moot")
	var moot: Vector2 = run.world.buildings.back()["pos"]
	var at := CaravanCamp.spot(run)
	check(at.length() > moot.length(), "outside the moot")
	check(signf(at.x) == signf(moot.x) or absf(moot.x) < 1.0, "on its side of the town")
	check(at.y < 0.0, "on the far half, clear of the build hand")
	check(at.length() >= run.world.town.patrol_radius(at.angle()), "past the town's edge")
	run.caravan.lay_out()
	var camp := CaravanCamp.new()
	camp.traded(run, 0, 100.0)
	check_eq(camp.risings.size(), 1, "a deal taken rises from the wagons")
	check(str(camp.risings[0]["text"]) != "", "saying what it brings")
	run.dispose()


func test_the_founders_stand_round_the_campfire_by_their_traditions_paths() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var ids: Array = ["stoneworkers", "smiths", "hunters"]
	var groups := DawnMuster.tradition_groups(run, ids)
	check_eq(groups.size(), 4, "one group per tradition and one for the Random card")
	for g: Dictionary in groups.slice(0, 3):
		check_eq(g["stand_ins"].size(), 3, "three founders stand by each tradition")
	check(groups[0]["stand_ins"].all(func(s: Dictionary) -> bool: return s["id"] == "warrior"), "a warband tradition's founders are warriors")
	check_eq(groups[1]["kit"], "guild", "a guilds tradition's craftspeople carry the guild kit")
	check(groups[2]["stand_ins"][0]["hero"], "a heroes tradition's banner is held by a hero")
	var stranger: Dictionary = groups[3]["stand_ins"][0]
	check(groups[3]["stand_ins"].size() == 1 and stranger.has("tint"), "the Random card is one hooded stranger")
	run.dispose()


func test_a_footer_can_be_kept_small_when_the_buttons_go_up_top() -> void:
	var shape: Vector2 = CardView.SHAPE[CardView.Size.MEDIUM]
	var plan := DawnMuster.layout(4, shape, Vector2(1264, 405), 80.0, 8.0)
	check(not plan.is_empty(), "four medium cards fit over the map above the build hand")
	check(float(plan["hearth_y"]) < 405.0, "with the hearth on the map")


func test_the_elder_presents_relics_and_charters_at_the_shrine() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	var relics: Array = run.content.relics.keys().slice(0, 3)
	var groups := DawnMuster.shrine_groups(relics, "relic")
	check_eq(groups.size(), 3, "one stone per card")
	check(groups.all(func(g: Dictionary) -> bool: return g["stand_ins"].is_empty() and g["members"].is_empty()),
		"nobody stands by the stones")
	check_eq(groups[1]["relic"], relics[1], "each stone carries its card's relic")
	check_eq(DawnMuster.shrine_groups(["heroes"], "path")[0]["path"], "heroes", "or its charter's path")
	var view := ArenaView.new()
	view.run = run
	view.size = Vector2(1264, 585)
	var plan := DawnMuster.layout(3, CardView.SHAPE[CardView.Size.LARGE], view.size, 150.0)
	var m := DawnMuster.new()
	m.start(run, view, plan, 1000.0, groups)
	var elders: Array = m.stand_ins.filter(func(st: Dictionary) -> bool: return st.get("elder", false))
	check_eq(elders.size(), 1, "the Elder stands at the shrine")
	check_eq(m.stand_in_anim(elders[0], 1500.0)[0], "raise", "presenting the cards")
	m.finish(2, 3000.0)
	check_eq(m.stand_in_anim(elders[0], 3100.0)[0], "cheer", "and cheers when one is taken")
	view.free()
	run.dispose()
