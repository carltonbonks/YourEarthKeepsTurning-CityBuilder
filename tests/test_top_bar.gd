extends TestCase
## The top bar's chips shorten when the bar is wider than the screen (TopBar.compact).


func test_chips_drop_their_trailing_words() -> void:
	check_eq(TopBar.compact("[color=#e09060]Food 0[/color]  runs out at dawn", "food"), "[color=#e09060]Food 0[/color]", "food keeps its number")
	check_eq(TopBar.compact("[b]Round 5 / 14[/b]  Stone age", "round"), "[b]Round 5 / 14[/b]", "round drops the age")
	check_eq(TopBar.compact("[color=#a]Wood 1[/color]  [color=#b]Stone 2[/color]  " + UiKit.tint("+4 more", UiKit.DIM), "goods"),
		"[color=#a]Wood 1[/color]  [color=#b]Stone 2[/color]", "goods keep every good and drop the count of more")
	check_eq(TopBar.compact("Relics 4", "relics"), "Relics 4", "a short chip stays as it is")
