extends TestCase
## Ventures: dawn cards that send tribespeople out for goods; some never come back.


## A run at its first dawn with this many tribespeople and ventures dealt every dawn.
func _run(tribe: int) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.content.balance["venture_chance"] = 1.0
	run.begin_round()
	while run.count_role("tribesperson") < tribe:
		run.world.folk_ai.add_folk("tribesperson")
	return run


func _venture(run: RunState) -> Dictionary:
	for card in run.pick_offer:
		if card["kind"] == "venture":
			return card
	return {}


func test_a_town_with_tribespeople_to_spare_is_dealt_a_venture() -> void:
	var run := _run(12)
	run.people.offer_picks()
	var card := _venture(run)
	check(not card.is_empty(), "a venture is among the dawn cards")
	check_eq(run.pick_offer.size(), run.content.int_num("pick_choices"), "in place of a newcomer, not on top")
	check(run.pick_offer.filter(func(c: Dictionary) -> bool: return c["kind"] == "venture").size() == 1, "only one")


func test_no_venture_when_the_town_cannot_spare_the_people() -> void:
	var run := _run(0)
	for i in 20:
		run.round_number = i + 1
		run.people.offer_picks()
		check(_venture(run).is_empty(), "too few tribespeople to send anyone (round %d)" % run.round_number)


func test_later_ventures_wait_for_their_age() -> void:
	var run := _run(20)
	var seen := {}
	for i in 40:
		run.round_number = i + 1
		run.people.offer_picks()
		seen[_venture(run).get("venture", "")] = true
	check(not seen.has("tin_trek") and not seen.has("margraves_levy"), "no bronze or medieval ventures in the stone age")
	check(seen.has("warthog_cull"), "the warthog cull turns up (%s)" % seen.keys())


func test_taking_a_venture_loses_some_and_brings_goods() -> void:
	var run := _run(12)
	run.people.offer_picks()
	var index := run.pick_offer.find(_venture(run))
	run.pick_offer[index] = {"kind": "venture", "role": "venture", "cost": 0, "venture": "warthog_cull"}
	var terms := run.people.venture_terms("warthog_cull")
	var tribe := run.count_role("tribesperson")
	var food := int(run.stock["food"])
	run.choose_pick(index)
	var lost := tribe - run.count_role("tribesperson")
	check(lost >= int(terms["lose"][0]) and lost <= int(terms["lose"][1]), "lost %d, within %s" % [lost, terms["lose"]])
	check_eq(int(run.stock["food"]), food + int(terms["goods"]["food"]), "the meat comes home")
	var entry: Dictionary = run.record.entry["picks"][-1]
	check_eq(entry["taken"], "venture:warthog_cull", "the record names the venture")
	check_eq(int(entry["venture_lost"]), lost, "and how many never came home")


func test_a_venture_needs_no_room() -> void:
	var run := _run(12)
	run.pick_offer = [{"kind": "venture", "role": "venture", "cost": 0, "venture": "timber_float"}]
	run.phase = RunState.Phase.PICK
	while run.population() <= run.housing():
		run.world.folk_ai.add_folk("warrior")
	check(run.can_take_pick(0), "nobody new moves in, so a full town can still send people out")


func test_goods_grow_with_the_rounds() -> void:
	var run := _run(12)
	var early: int = run.people.venture_terms("timber_float")["goods"]["wood"]
	run.round_number = 10
	var late: int = run.people.venture_terms("timber_float")["goods"]["wood"]
	check(late > early, "round 10 brings more than round 1 (%d vs %d)" % [late, early])


func test_pathfinders_cord_makes_ventures_safer_and_richer() -> void:
	var run := _run(12)
	var before := run.people.venture_terms("far_cliffs")
	run._gain_relic("pathfinders_cord")
	var after := run.people.venture_terms("far_cliffs")
	check_eq(after["lose"], [int(before["lose"][0]) - 1, int(before["lose"][1]) - 1], "one fewer lost")
	check(int(after["goods"]["stone"]) > int(before["goods"]["stone"]), "more stone")
	var calm := run.people.venture_terms("timber_float")
	check_eq(int(calm["lose"][0]), 0, "never fewer than none")
