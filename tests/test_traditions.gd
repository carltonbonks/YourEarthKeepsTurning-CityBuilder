extends TestCase
## Founding traditions picked before round 1 tilt the building hand, the dawn's tribespeople, bands and a few rules.


func _run() -> RunState:
	return RunState.new(Content.load_default(), 4821)


func test_a_new_run_waits_for_its_traditions() -> void:
	var run := _run()
	check(run.awaiting_traditions(), "round 1 starts by asking for traditions")
	run.choose_traditions(["hunters"])
	check(not run.awaiting_traditions(), "and stops asking once chosen")
	check_eq(run.traditions, ["hunters"] as Array[String], "it is kept")


func test_only_one_known_tradition() -> void:
	var run := _run()
	run.choose_traditions(["nonsense", "hunters", "traders"])
	check_eq(run.traditions, ["hunters"] as Array[String], "one known tradition (Yusuf, 2026-10-25)")


func test_random_tradition_brings_a_bonus() -> void:
	var run := _run()
	var before := run.stock.duplicate()
	run.choose_random_tradition()
	check(not run.awaiting_traditions(), "leaving it to chance founds the town")
	check_eq(run.traditions.size(), 1, "on one tradition")
	check(run.tradition_random, "and remembers it was chance")
	var start: Dictionary = run.content.traditions[run.traditions[0]].get("start", {})
	for good: String in ["food", "stone", "fuel"]:
		check_eq(int(run.stock[good]), int(before[good]) + 5 + int(start.get(good, 0)), "+5 %s on top of its start goods" % good)
	check_eq(run.to_record()["tradition_random"], true, "the record says so")
	var again := _run()
	again.choose_random_tradition()
	check_eq(again.traditions, run.traditions, "the same seed draws the same tradition")
	var drawn := {}
	for s in 30:
		var r := RunState.new(Content.load_default(), 100 + s)
		r.choose_random_tradition()
		drawn[r.traditions[0]] = true
		r.dispose()
	check(drawn.size() >= 4, "different seeds draw different traditions (%d of 6)" % drawn.size())


func test_starting_the_round_skips_them() -> void:
	var run := _run()
	run.begin_round()
	check(not run.awaiting_traditions(), "beginning round 1 founds the town on none")
	check(run.traditions.is_empty(), "with no traditions")


func test_start_goods_and_effects() -> void:
	var run := _run()
	var shells := int(run.stock["shells"])
	run.choose_traditions(["traders"])
	check_eq(int(run.stock["shells"]), shells + 15, "traders bring shells")
	check_eq(run.mod("income"), 5.0, "traders' effect counts like a relic's")
	check(not run.tradition_random, "a chosen tradition is not chance")
	var wood_run := _run()
	var wood := int(wood_run.stock["wood"])
	wood_run.choose_traditions(["woodfolk"])
	check_eq(int(wood_run.stock["wood"]), wood + 10, "woodfolk bring wood")


func test_hunters_make_heroes_hit_harder() -> void:
	var run := _run()
	var before := run.heroes[0].attack if not run.heroes.is_empty() else 0.0
	run.choose_traditions(["hunters"])
	if not run.heroes.is_empty():
		check_eq(run.heroes[0].attack, before + 1.0, "starting heroes hit 1 harder")


func test_tradition_buildings_come_up_more_often() -> void:
	var plain := 0
	var favoured := 0
	for s in 40:
		var a := RunState.new(Content.load_default(), 2000 + s)
		a.choose_traditions([])
		plain += a.hand.cards.filter(func(c: Dictionary) -> bool: return c["building"] == "hunting_lodge").size()
		a.dispose()
		var b := RunState.new(Content.load_default(), 2000 + s)
		b.choose_traditions(["hunters"])
		favoured += b.hand.cards.filter(func(c: Dictionary) -> bool: return c["building"] == "hunting_lodge").size()
		b.dispose()
	check(favoured > plain, "hunters are dealt hunting lodges more often (%d vs %d in 40 hands)" % [favoured, plain])


func _woodcutter_cards(traditions: Array) -> int:
	var run := _run()
	run.choose_traditions(traditions)
	run.begin_round()
	var n := 0
	for i in 40:
		run.round_number = i + 1
		run.people.offer_picks()
		n += run.pick_offer.filter(func(c: Dictionary) -> bool: return c.get("leaning", "") == "woodcutter").size()
	run.dispose()
	return n


func test_tradition_leaning_comes_more_often_and_bands_sooner() -> void:
	var plain := _woodcutter_cards([])
	var favoured := _woodcutter_cards(["woodfolk"])
	check(favoured > plain, "woodfolk are offered woodcutters more often (%d vs %d in 40 dawns)" % [favoured, plain])
	var run := _run()
	run.choose_traditions(["woodfolk"])
	var w := run.world
	check_eq(w.folk_ai.band_level("tribesperson", "woodcutter", 2), 1, "two woodcutters band for woodfolk")
	check_eq(w.folk_ai.band_level("tribesperson", "forager", 2), 0, "but two foragers do not")
	check_eq(w.folk_ai.band_level("tribesperson", "woodcutter", 5), 2, "and five gather faster")


func test_record_keeps_the_traditions() -> void:
	var run := _run()
	run.choose_traditions(["smiths"])
	check_eq(run.to_record()["traditions"], ["smiths"], "the record names it")
