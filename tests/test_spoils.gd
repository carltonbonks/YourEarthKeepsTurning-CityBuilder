extends TestCase
## After an attack, the relic offer gains the spoils of the kind of enemy it was made of.


func _run(wave: Array[String]) -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.next_wave = wave
	return run


func test_a_raider_attack_offers_human_spoils() -> void:
	var run := _run(["raider", "raider", "raider"] as Array[String])
	var offer := run._roll_relic_offer()
	check_eq(run.spoils.get("kind", ""), "human", "raiders leave human spoils")
	check_eq(int(run.spoils["foes"]), 3, "three of them came")
	check(offer.has(run.spoils["id"]), "the spoils are in the offer")
	check(run.content.has_tag("relic", offer[-1], "spoils"), "as the last card")
	check_eq(offer.filter(func(id: String) -> bool: return run.content.has_tag("relic", id, "spoils")).size(), 1,
		"and the ordinary relics are never spoils")


func test_no_spoils_without_an_attack() -> void:
	var run := _run([] as Array[String])
	var offer := run._roll_relic_offer()
	check(run.spoils.is_empty(), "nothing came, so nothing to take")
	check_eq(offer.size(), run.content.int_num("relic_choices"), "just the relics")


func test_pack_train_scales_with_the_warband() -> void:
	var run := _run(["raider", "raider", "raider", "raider"] as Array[String])
	run.spoils = {"id": "pack_train", "kind": "human", "foes": 4}
	run.relic_offer = ["pack_train"]
	run.phase = RunState.Phase.RELIC
	var shells := int(run.stock["shells"])
	var wood := int(run.stock["wood"])
	run.choose_relic("pack_train")
	check(int(run.stock["shells"]) >= shells + 8, "2 shells a raider (plus the traders' income)")
	check_eq(int(run.stock["wood"]), wood + 2, "half a wood a raider")
	check(not run.relics.has("pack_train"), "goods-only spoils are not kept as a relic")
	check(run.record.rounds[-1]["spoils"]["taken"], "the record says the spoils were taken")


func test_raiders_spears_bring_a_warrior_and_stay() -> void:
	var run := _run(["raider"] as Array[String])
	var warriors := run.count_role("warrior")
	run.spoils = {"id": "raiders_spears", "kind": "human", "foes": 1}
	run.relic_offer = ["raiders_spears"]
	run.phase = RunState.Phase.RELIC
	run.choose_relic("raiders_spears")
	check_eq(run.count_role("warrior"), warriors + 1, "a raider joins as a warrior")
	check(run.relics.has("raiders_spears"), "and the spears are kept as a relic")
	check_eq(run.mod("warrior_attack"), 2.0, "warriors hit harder")


func test_kept_spoils_are_not_offered_again() -> void:
	var run := _run(["battering_ram"] as Array[String])
	run.relics.append("splintered_ram")
	for i in 10:
		run.round_number = i + 1
		run._roll_relic_offer()
		check_eq(run.spoils.get("id", ""), "ram_timbers", "only the timbers are left to take")


func test_skipping_records_spoils_not_taken() -> void:
	var run := _run(["wolf", "wolf"] as Array[String])
	run.relic_offer = run._roll_relic_offer()
	run.phase = RunState.Phase.RELIC
	check_eq(run.spoils["kind"], "beast", "wolves leave beast spoils")
	run.choose_relic("")
	check(not run.record.rounds[-1]["spoils"]["taken"], "skipped spoils are recorded as not taken")
