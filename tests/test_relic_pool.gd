extends TestCase
## Each run's relic pool (Yusuf, 2026-11-05): ordinary relics are offered only from a pool dealt from the run's
## seed, leaning toward the founding traditions' paths, with a few mythics; charters bring more of their path's.


func _run(traditions: Array = [], seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	run.choose_traditions(traditions)
	return run


func _tagged(run: RunState, ids: Array, tag: String) -> int:
	return ids.filter(func(id: String) -> bool: return run.content.has_tag("relic", id, tag)).size()


func test_every_path_has_relics_to_lean_on() -> void:
	var run := _run()
	for path: String in run.content.paths["paths"]:
		var tag := run.path_relic_tag(path)
		check(tag != "", "%s names its relic tag" % path)
		check(_tagged(run, run.ordinary_relics(), tag) >= run.content.int_num("relic_pool_charter"), "%s has enough relics for a charter" % path)
	run.dispose()


func test_the_pool_is_ordinary_relics_of_its_size_with_mythics() -> void:
	var run := _run(["hunters"])
	var pool := run.relic_pool()
	check_eq(pool.size(), run.content.int_num("relic_pool_size"), "relic_pool_size relics")
	check(pool.all(func(id: String) -> bool: return not run.content.has_tag("relic", id, "pact") and not run.content.has_tag("relic", id, "spoils")), "no pacts or spoils")
	var mythics := pool.filter(func(id: String) -> bool: return run.content.rarity_of("relic", id) == "orange").size()
	check(mythics >= run.content.int_num("relic_pool_mythics"), "at least the mythics asked for")
	check(pool.size() < run.ordinary_relics().size(), "a pool, not every relic")
	run.dispose()


func test_the_pool_is_seeded_and_differs_between_runs() -> void:
	var a := _run(["hunters"], 11)
	var b := _run(["hunters"], 11)
	var c := _run(["hunters"], 12)
	check_eq(a.relic_pool(), b.relic_pool(), "same seed, same pool")
	check(a.relic_pool() != c.relic_pool(), "another seed deals another pool")
	for r in [a, b, c]:
		r.dispose()


func test_the_pool_leans_toward_the_founding_path() -> void:
	var lean := 0
	var plain := 0
	for s in 6:
		var hunters := _run(["hunters"], 100 + s)
		var none := _run([], 100 + s)
		lean += _tagged(hunters, hunters.relic_pool(), "hero")
		plain += _tagged(none, none.relic_pool(), "hero")
		check(_tagged(hunters, hunters.relic_pool(), "hero") >= roundi(hunters.content.int_num("relic_pool_size") * hunters.content.num("relic_pool_lean_share")),
			"a heroes run holds at least the lean's share of hero relics")
		hunters.dispose()
		none.dispose()
	check(lean > plain, "hunters see more hero relics than a town with no tradition (%d vs %d)" % [lean, plain])


func test_offers_come_from_the_pool() -> void:
	var run := _run(["traders"])
	var pool := run.relic_pool()
	for r in range(2, 13):
		run.round_number = r
		if run.is_pact_round():
			continue
		for id: String in run._roll_relic_offer():
			if not run.content.has_tag("relic", id, "spoils"):
				check(pool.has(id), "round %d offers %s from the pool" % [r, id])
	run.dispose()


func test_a_dry_pool_tops_up_from_every_relic() -> void:
	var run := _run()
	run.round_number = 2
	for id in run.relic_pool():
		run.relics.append(id)
	var offer := run._roll_relic_offer().filter(func(id: String) -> bool: return not run.content.has_tag("relic", id, "spoils"))
	check(offer.size() >= run.content.int_num("relic_choices"), "still a full offer")
	check(offer.all(func(id: String) -> bool: return not run.relic_pool().has(id)), "from outside the pool")
	run.dispose()


func test_a_charter_brings_its_paths_relics_within_reach() -> void:
	var run := _run(["traders"])
	var before := run.relic_pool()
	run.charters_due = 1
	run.charter_offer = ["warband"]
	run.choose_charter("warband")
	var after := run.relic_pool()
	var added := after.filter(func(id: String) -> bool: return not before.has(id))
	check_eq(added.size(), run.content.int_num("relic_pool_charter"), "relic_pool_charter new relics")
	check(added.all(func(id: String) -> bool: return run.content.has_tag("relic", id, "horde")), "all warband relics")
	check(before.all(func(id: String) -> bool: return after.has(id)), "nothing leaves the pool")
	check_eq(run.to_record()["relic_pool"], after, "the record keeps the pool")
	run.dispose()
