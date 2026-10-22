extends TestCase
## The "+2 stone" popups over the hearth: the world tallies goods carried in, and the view gathers them into one
## popup every so often instead of one per haul.


func test_hauls_reach_stock_and_the_tally() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	var wood := int(run.stock["wood"])
	w.bring_in("wood", 3)
	check_eq(int(run.stock["wood"]), wood + 3, "goods brought in go into stock")
	check_eq(int(w.brought_in["wood"]), 3, "and into the tally the popups read")
	w.brought_in.clear()
	for i in 600:
		w.step()
		if w.pause != World.Pause.NONE:
			break
	var total := 0
	for good: String in w.brought_in:
		total += int(w.brought_in[good])
	check(total > 0, "townsfolk carry goods home in a day: %s" % w.brought_in)
	run.dispose()


func test_popups_gather_hauls_into_buckets() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var w := run.world
	var pops := PickupPopups.new()
	w.brought_in["stone"] = 5
	pops.update(w, 0.0)
	check(pops.popups.is_empty(), "what the town already had shows nothing")
	w.bring_in("stone", 2)
	w.bring_in("stone", 2)
	w.bring_in("wood", 7)
	pops.update(w, 100.0)
	check(pops.popups.is_empty(), "hauls wait for the bucket to fill")
	pops.update(w, PickupPopups.BUCKET_MS + 1.0)
	check_eq(pops.popups.size(), 1, "one popup per bucket, however many hauls")
	check_eq(pops.popups[0]["lines"], [["+7 wood", "wood"], ["+4 stone", "stone"]], "one line per good, biggest first")
	pops.update(w, PickupPopups.BUCKET_MS * 2.0 + 2.0)
	check_eq(pops.popups.size(), 1, "a quiet bucket adds nothing")
	pops.update(w, PickupPopups.BUCKET_MS + 1.0 + PickupPopups.RISE_MS)
	check(pops.popups.is_empty(), "popups fade away")
	run.dispose()


func test_many_goods_fold_into_more() -> void:
	var lines := PickupPopups.gained({}, {"a": 9, "b": 8, "c": 7, "d": 6, "e": 2, "f": 1, "bog_iron": 0})
	check_eq(lines.size(), PickupPopups.MAX_LINES + 1, "extra goods share a line")
	check_eq(lines[-1], ["+3 more", ""], "summed into +N more")
	check_eq(PickupPopups.gained({}, {"bog_iron": 2})[0][0], "+2 bog iron", "ids read as words")
