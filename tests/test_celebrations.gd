extends TestCase
## Big moments marked: a new age lays its ground round the hearth for good, and the view (game/celebrations.gd)
## shows a title card, the raised building and the new resources, and a halo on heroes levelling up.


func _run() -> RunState:
	return RunState.new(Content.load_default(), 4821)


## Orders a building and finishes it on the spot.
func _raise(run: RunState, type: String) -> void:
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	run.stock["shells"] = maxi(int(run.stock["shells"]), 300)
	run.stock["bronze"] = 99
	check(run.build(type), "can order a %s" % type)
	run.world.buildings[run.world.buildings.size() - 1]["work_left"] = 0.0
	run.on_building_done(type)


func _age_up(run: RunState) -> void:
	run.stock["wood"] = 99
	for i in 6:
		run.build("hut")
	for b in run.world.buildings:
		b["work_left"] = 0.0
	while run.population() < 12:
		run.world.folk_ai.add_folk("tribesperson")
	_raise(run, "market")
	_raise(run, "bronze_moot")


## Open squares round the hearth out to the age's radius, and how many of them are at least `kind`.
func _hearth_ground(run: RunState, kind: int) -> Array[int]:
	var p := run.world.pathing
	var open := 0
	var laid := 0
	for i in p.cells_in_circle(Vector2.ZERO, float(run.content.ages["hearth_ground_radius"])):
		if not p.is_solid(i):
			open += 1
			if p.ground[i] >= kind:
				laid += 1
	return [open, laid]


func test_each_age_lays_its_ground_round_the_hearth() -> void:
	var run := _run()
	var before := _hearth_ground(run, Pathing.PATH)
	check(before[0] > 20, "there are open squares round the hearth")
	check(before[1] < before[0], "the stone age starts on bare ground")
	_age_up(run)
	var bronze := _hearth_ground(run, Pathing.PATH)
	check_eq(bronze[1], bronze[0], "the bronze age lays a dirt path all round the hearth")
	# Nobody walks there for days: laid ground never fades back.
	for i in 6:
		run.world.pathing.wear_trails()
	check_eq(_hearth_ground(run, Pathing.PATH)[1], bronze[0], "the laid path does not fade")
	_raise(run, "bronzesmith")
	while run.population() < 20:
		run.world.folk_ai.add_folk("tribesperson")
	_raise(run, "stone_keep")
	check_eq(run.age, "medieval", "the keep brings the medieval age")
	var stone := run.world.pathing.kind_ids.find("stone_path")
	var medieval := _hearth_ground(run, stone)
	check_eq(medieval[1], medieval[0], "the medieval age lays stone round the hearth")
	run.dispose()


func test_laying_ground_keeps_better_roads() -> void:
	var run := _run()
	var p := run.world.pathing
	var cobbles := p.kind_ids.find("cobbled_road")
	var square := -1
	for i in p.cells_in_circle(Vector2.ZERO, 50.0):
		if not p.is_solid(i):
			square = i
			break
	p.set_ground(square, cobbles)
	_age_up(run)
	check_eq(int(p.ground[square]), cobbles, "a cobbled road is not dug up for a dirt path")
	run.dispose()


func test_age_up_card_names_the_building_and_new_resources() -> void:
	var run := _run()
	var c := Celebrations.new()
	c.update(run, 0.0)
	c.update(run, 16.0)
	check(c.age_up.is_empty(), "nothing to celebrate at the start")
	_age_up(run)
	c.update(run, 100.0)
	check(not c.age_up.is_empty(), "raising the moot starts the celebration")
	check_eq(str(c.age_up["title"]), "The Bronze age begins", "the title names the age")
	var bi: int = c.age_up["building"]
	check(bi >= 0 and run.world.buildings[bi]["type"] == "bronze_moot", "the moot is the building highlighted")
	var nodes: Array = c.age_up["nodes"]
	check(not nodes.is_empty(), "the bronze age's resources are highlighted")
	for i: int in nodes:
		check_eq(str(run.world.nodes[i]["age"]), "bronze", "only nodes the new age brought")
	check(" ".join(c.age_up["lines"]).contains("Copper seam"), "the card says what is new on the map: %s" % [c.age_up["lines"]])
	c.update(run, 100.0 + Celebrations.HIGHLIGHT_MS)
	check(c.age_up.is_empty(), "the celebration ends")
	run.dispose()


func test_a_new_run_is_not_celebrated() -> void:
	var run := _run()
	_age_up(run)
	var c := Celebrations.new()
	c.update(run, 0.0)
	c.update(run, 16.0)
	check(c.age_up.is_empty(), "an age the town already had when first seen is not celebrated")
	run.dispose()


func test_hero_level_ups_get_a_halo() -> void:
	var run := _run()
	var hero := run.people.make_hero()
	run.people.add_hero(hero)
	var c := Celebrations.new()
	c.update(run, 0.0)
	check_eq(c.halo_share(hero, 0.0), 0.0, "no halo before a level-up")
	hero.xp = run.content.num("xp_per_level") * hero.level
	run.people.level_up(hero)
	c.update(run, 50.0)
	check(c.halo_share(hero, 50.0) > 0.9, "levelling up lights a halo")
	check_eq(int(c.halos[hero.id]["level"]), hero.level, "the halo shows the new level")
	c.update(run, 50.0 + Celebrations.HALO_MS)
	check_eq(c.halo_share(hero, 50.0 + Celebrations.HALO_MS), 0.0, "the halo fades")
	run.dispose()
