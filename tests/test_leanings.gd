extends TestCase
## Tribespeople come with a leaning on their dawn card, and it tilts which trips they pick.


func _run() -> RunState:
	return RunState.new(Content.load_default(), 4821)


## Every dawn pool across many dawns, as the folk cards dealt.
func _folk_cards_dealt(run: RunState, dawns: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in dawns:
		run.round_number = i + 1
		run.people.offer_picks()
		for card in run.pick_offer:
			if card["kind"] == "folk":
				out.append(card)
	return out


func test_tribesperson_cards_come_with_a_leaning() -> void:
	var run := _run()
	run.begin_round()
	var seen := {}
	for card in _folk_cards_dealt(run, 40):
		if card["role"] == "tribesperson":
			check(card.has("leaning"), "every tribesperson card has a leaning")
			seen[card.get("leaning", "")] = true
		else:
			check(not card.has("leaning"), "%s cards have none" % card["role"])
	check(seen.has("forager") and seen.has("woodcutter") and seen.has("quarrier") and seen.has("brushcutter"),
		"all the stone-age leanings turn up (%s)" % seen.keys())
	check(not seen.has("prospector"), "no prospectors before the bronze age")


func test_two_tribesperson_cards_in_one_offer_lean_differently() -> void:
	var run := _run()
	run.begin_round()
	for i in 40:
		run.round_number = i + 1
		run.people.offer_picks()
		var leanings := run.pick_offer.filter(func(c: Dictionary) -> bool: return c.has("leaning")).map(
			func(c: Dictionary) -> String: return c["leaning"])
		check(leanings.size() <= 2, "at most two tribespeople a dawn")
		if leanings.size() == 2:
			check(leanings[0] != leanings[1], "the two lean toward different goods")


func test_prospectors_from_the_bronze_age() -> void:
	var run := _run()
	run.begin_round()
	run.age = "bronze"
	check(run.people.leanings_open("tribesperson").has("prospector"), "bronze towns can be dealt prospectors")


func test_taking_a_leaning_card_gives_the_newcomer_that_leaning() -> void:
	var run := _run()
	run.begin_round()
	run.pick_offer = [{"kind": "folk", "role": "tribesperson", "cost": 0, "leaning": "woodcutter"},
		{"kind": "folk", "role": "warrior", "cost": 0}]
	run.choose_pick(0)
	var newcomer: Unit = run.world.folk[-1]
	check_eq(newcomer.leaning, "woodcutter", "the newcomer leans toward wood")
	check_eq(run.folk_name("tribesperson", newcomer.leaning), "Woodcutter", "and is called a woodcutter")
	var pick: Dictionary = run.record.entry["picks"][-1]
	check_eq(pick["leaning"], "woodcutter", "the record says which leaning was taken")
	check_eq(pick["offered_leanings"], ["woodcutter", ""], "and which were offered")


## Berries and a grove the same distance away, with the town short of food a bit more than of wood.
func _setup_trip() -> RunState:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	w.enemies.clear()
	w.nodes.clear()
	w._add_node("berries", Vector2(200, 0))
	w._add_node("grove", Vector2(0, 200))
	return run


## Food 60% short, wood 50% short, against what the town wants now.
func _short(run: RunState) -> void:
	var wants := run.resource_wants()
	run.stock["food"] = roundi(wants["food"] * 0.4)
	run.stock["wood"] = roundi(wants["wood"] * 0.5)


func test_leaning_tilts_the_trip() -> void:
	var run := _setup_trip()
	var w := run.world
	var plain := w.folk_ai.add_folk("tribesperson")
	plain.pos = Vector2.ZERO
	var cutter := w.folk_ai.add_folk("tribesperson", "woodcutter")
	cutter.pos = Vector2.ZERO
	_short(run)
	w.folk_ai.begin_step()
	check_eq(w.folk_ai.plan_trip(plain), 0, "a plain tribesperson goes for the food the town is shorter of")
	check_eq(w.folk_ai.plan_trip(cutter), 1, "a woodcutter would rather fetch wood")


func test_leaning_does_not_send_them_for_goods_nobody_needs() -> void:
	var run := _setup_trip()
	var w := run.world
	var cutter := w.folk_ai.add_folk("tribesperson", "woodcutter")
	cutter.pos = Vector2.ZERO
	_short(run)
	run.stock["wood"] = 999
	w.folk_ai.begin_step()
	check_eq(w.folk_ai.plan_trip(cutter), 0, "with wood piled high, the woodcutter fetches food")


func test_leaned_gathering_is_recorded() -> void:
	var run := _setup_trip()
	var w := run.world
	var cutter := w.folk_ai.add_folk("tribesperson", "woodcutter")
	cutter.pos = Vector2.ZERO
	_short(run)
	for i in 300:
		w.folk_ai.begin_step()
		w.folk_ai.folk_tick(cutter)
	check(int(run.record.entry["gathered_leaned"].get("wood", 0)) > 0, "wood a woodcutter brought in shows in the record")
	run.record.end_round()
	check_eq(int(run.record.rounds[-1]["leanings_end"].get("woodcutter", 0)), 1, "the round's end counts the town's leanings")
