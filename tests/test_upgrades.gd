extends TestCase
## Upgrade offers (data/upgrades.json): a draft may offer to change a building the town has, for the rest of the run.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.choose_traditions([])
	run.stock["wood"] = 999
	run.stock["stone"] = 999
	return run


func _finish(run: RunState) -> void:
	for b in run.world.buildings:
		b["work_left"] = 0.0


func test_an_upgrade_changes_its_building_for_the_run() -> void:
	var run := _run()
	var before := run.housing()
	run.build("hut")
	_finish(run)
	var one := run.housing() - before
	run.take_upgrade("sturdy_huts")
	check_eq(run.housing() - before, one + 1, "the standing hut holds 1 more")
	run.build("hut")
	_finish(run)
	check_eq(run.housing() - before, 2 * (one + 1), "and so does the next")


func test_upgrades_reach_inside() -> void:
	var run := _run()
	var beds := int(run.content.buildings["longhouse"]["lodging"]["beds"])
	run.take_upgrade("wide_longhouse")
	check_eq(int(run.content.buildings["longhouse"]["lodging"]["beds"]), beds + 2, "a dotted key adds inside lodging")


func test_upgrades_stay_in_their_run() -> void:
	var content := Content.load_default()
	var a := RunState.new(content, 1)
	a.take_upgrade("sturdy_huts")
	var b := RunState.new(content, 2)
	check_eq(int(b.content.buildings["hut"]["housing"]), int(content.buildings["hut"]["housing"]), "another run keeps plain huts")


func test_drafts_offer_upgrades_only_for_what_stands() -> void:
	var run := _run()
	run.hand.picks = 1
	run.hand._fill(SeededRng.stream(1, "t"))
	for c in run.hand.upgrade_offers:
		check(run.world.count_buildings(run.content.upgrades[c["upgrade"]]["building"]) > 0, "only for standing buildings")
	run.build("watch_post")
	_finish(run)
	var seen := false
	for r in 8:
		run.hand._fill(SeededRng.stream(r, "t"))
		check(run.hand.upgrade_offers.size() <= run.content.int_num("upgrade_cards"), "at most upgrade_cards")
		check(run.hand.cards.size() + run.hand.rows.size() <= run.hand.size(), "upgrades come on top of the building offers")
		seen = seen or not run.hand.upgrade_offers.is_empty()
	check(seen, "upgrades come up once something stands")


func test_drafting_an_upgrade_spends_the_draft() -> void:
	var run := _run()
	run.build("watch_post")
	_finish(run)
	run.hand.picks = 1
	run.hand.upgrade_offers = [{"upgrade": "fletchers"}] as Array[Dictionary]
	var attack := float(run.content.buildings["watch_post"]["attack"])
	check(run.hand.draft_upgrade("fletchers"), "drafted")
	check_eq(run.hand.picks, 0, "the draft is spent")
	check_eq(float(run.content.buildings["watch_post"]["attack"]), attack + 2.0, "posts hit harder")
	check(not run.hand.upgradable("fletchers"), "taken once")
	check(run.to_record()["upgrades"].has("fletchers"), "recorded")


func test_every_upgrade_names_a_real_building_and_key() -> void:
	var c := Content.load_default()
	for id: String in c.upgrades:
		var up: Dictionary = c.upgrades[id]
		check(c.buildings.has(up["building"]), "%s upgrades a real building" % id)
		for key: String in up["add"]:
			var at: Variant = c.buildings[up["building"]]
			for part in key.split("."):
				at = at.get(part) if at is Dictionary else null
			check(at != null, "%s: %s.%s exists" % [id, up["building"], key])
