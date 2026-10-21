extends TestCase
## Holding a building card keeps it for the next round's hand.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	return run


func test_a_held_card_comes_back_next_round() -> void:
	var run := _run()
	var type: String = run.hand.cards[0]["building"]
	check(run.hand.hold(type), "a card in hand can be held")
	check_eq(run.hand.held, type, "it is held")
	run.round_number += 1
	run.hand.deal()
	check(run.hand.cards.any(func(c: Dictionary) -> bool: return c["building"] == type), "it is in the next hand")
	check_eq(run.hand.held, "", "and no longer held")


func test_holding_again_lets_go() -> void:
	var run := _run()
	var type: String = run.hand.cards[0]["building"]
	run.hand.hold(type)
	run.hand.hold(type)
	check_eq(run.hand.held, "", "holding twice lets the card go")


func test_one_card_at_a_time() -> void:
	var run := _run()
	var a: String = run.hand.cards[0]["building"]
	var b: String = run.hand.cards[1]["building"]
	run.hand.hold(a)
	run.hand.hold(b)
	check_eq(run.hand.held, b, "holding another card swaps the hold")


func test_ordering_a_held_card_clears_the_hold() -> void:
	var run := _run()
	run.stock["wood"] = 999
	run.stock["stone"] = 999
	run.stock["shells"] = 999
	var type := ""
	for c: Dictionary in run.hand.cards:
		if run.hand.can_order(c["building"]):
			type = c["building"]
			break
	if type == "":
		return
	run.hand.hold(type)
	check(run.hand.order(type), "the held card can still be ordered")
	check_eq(run.hand.held, "", "and is no longer held")


func test_redraw_keeps_the_held_card() -> void:
	var run := _run()
	run.stock["shells"] = 999
	var type: String = run.hand.cards[0]["building"]
	run.hand.hold(type)
	run.hand.redraw()
	check(run.hand.cards.any(func(c: Dictionary) -> bool: return c["building"] == type), "a redraw keeps the held card")


func test_cards_not_in_hand_cannot_be_held() -> void:
	var run := _run()
	check(not run.hand.hold("stone_keep"), "only a card in hand can be held")
