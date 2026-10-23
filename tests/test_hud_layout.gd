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
