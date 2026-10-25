extends TestCase
## The panels over the map keep out of each other's way (HudLayout): the edge columns take the room the
## draft window and the hand leave, and fold what doesn't fit into hover cards rather than overlap.


func test_a_column_takes_the_tallest_free_stretch_beside_the_draft() -> void:
	var m := HudLayout.MARGIN
	var free := HudLayout.free_span(0, 300, 8, 400, [] as Array[Rect2])
	check_eq(free, Vector2(8, 400), "nothing in the way: the whole edge")
	var draft := Rect2(200, 8, 600, 200)
	free = HudLayout.free_span(0, 300, 8, 400, [draft] as Array[Rect2])
	check_eq(free, Vector2(208 + m, 400), "a draft window over the column's top pushes it below the window")
	free = HudLayout.free_span(900, 1200, 8, 400, [draft] as Array[Rect2])
	check_eq(free, Vector2(8, 400), "a window off to the side leaves the column alone")
	var low := Rect2(200, 300, 600, 60)
	free = HudLayout.free_span(0, 300, 8, 400, [low] as Array[Rect2])
	check_eq(free, Vector2(8, 300 - m), "a window dragged low leaves the taller stretch above it")
	var all := Rect2(0, 0, 1000, 500)
	free = HudLayout.free_span(0, 300, 8, 400, [all] as Array[Rect2])
	check(free.y - free.x <= 0.0, "a window over the whole column leaves no room")


func test_the_attack_card_folds_its_extras_into_the_hover_when_short_of_room() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.wave_eased = 3
	var card := ThreatCard.new()
	card.run = run
	card.refresh()
	# Outside the scene tree sizes aren't re-measured, so this checks what folds, not the sums
	# (the screenshots in tools/snapshot.gd size=1280x720 show those).
	check_eq(card.fit(INF), 0, "with room, nothing is folded")
	check(card.fit(0.0) > 0, "with no room, the extras fold")
	var lines: Array = card.call("_tip_with_folded")["lines"]
	check(lines.any(func(l: String) -> bool: return "holds back 3 raiders" in l), "the folded warband banner is in the hover card")
	check_eq(card.fit(INF), 0, "with room again, they come back")
	card.free()
	run.dispose()


func test_alerts_that_dont_fit_wait_their_turn() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.stock["fuel"] = 0
	run.stock["food"] = 0
	var alerts := Alerts.new()
	alerts.run = run
	alerts.refresh()
	var shown := alerts.get_children().size()
	check(shown >= 2, "a starving, freezing town has alerts (%d)" % shown)
	check_eq(alerts.fit(INF), 0, "with room, every alert shows")
	check_eq(alerts.fit(1.0), shown, "with no room, all of them wait")
	var one := (alerts.get_child(0) as Label).get_combined_minimum_size().y
	check_eq(alerts.fit(one), shown - 1, "room for one shows the first and the rest wait")
	alerts.free()
	run.dispose()


func test_a_crowded_hand_shrinks_to_fit_instead_of_scrolling() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	for id: String in ["tin_bundle", "sellswords", "relic_dealer"]:
		run.caravan.offers.append({"deal": id, "need": "", "taken": false})
	screen.call("_refresh")
	var hand: BuildHandView = screen.get("_hand_view")
	check(hand.find_children("*", "ScrollContainer", true, false).is_empty(), "the hand has no scroll bar")
	var shelf: Control = hand.get("_shelf")
	shelf.size.x = 4000.0
	hand.call("_fit")
	check_eq(hand.row_scale(), 1.0, "with room, the cards keep their size")
	shelf.size.x = 500.0
	hand.call("_fit")
	check(hand.row_scale() < 1.0 and hand.row_scale() >= BuildHandView.MIN_SCALE, "a narrow strip shrinks the row (%.2f)" % hand.row_scale())
	check(shelf.custom_minimum_size.y < BuildHandView.ROW_HEIGHT, "and the strip gets shorter with it")
	run.dispose()
	screen.free()


func test_a_big_roster_narrows_the_hero_portraits() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	while run.living_heroes().size() < 6:
		run.people.add_hero(run.people.make_hero())
	var strip := HeroStrip.new()
	strip.run = run
	strip.size.x = 700.0
	strip.refresh()
	var parts: Array = strip.get("_parts")
	check_eq(parts.size(), run.living_heroes().size(), "every hero has a portrait")
	var total := 0.0
	for p: Array in parts:
		total += (p[5] as Control).custom_minimum_size.x
	check(total <= 700.0, "the portraits share the strip's width (%.0f)" % total)
	check((parts[0][5] as Control).custom_minimum_size.x < HeroStrip.CHIP_WIDTH, "each one is narrower than at full size")
	strip.free()
	run.dispose()


func test_a_hero_portrait_shows_health_lost_in_red_above_what_is_left() -> void:
	var holder := HBoxContainer.new()
	var bar := HeroStrip.health_bar(holder)
	HeroStrip.set_health(bar, 0.25)
	var fill := bar.get_child(0) as ColorRect
	check_eq(bar.color, HeroStrip.LOST_COLOR, "the bar behind is the red of health lost")
	check(is_equal_approx(fill.anchor_top, 0.75), "a quarter left fills the bottom quarter (%.2f)" % fill.anchor_top)
	check_eq(fill.color, HeroStrip.LOW_HEALTH_COLOR, "low health turns amber")
	check(bar.custom_minimum_size.y > bar.custom_minimum_size.x, "the bar stands upright")
	holder.free()
