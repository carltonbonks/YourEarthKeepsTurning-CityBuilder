extends TestCase


func _played(seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	AutoPlayer.new().play_run(run)
	return run


func test_record_has_one_entry_per_round_played() -> void:
	var run := _played()
	var record := run.to_record()
	check_eq(record["rounds"].size(), run.round_number, "one round entry per round")
	check(record["result"] in ["won", "lost"], "finished run has a result")
	check_eq(record["format"], RunState.RECORD_FORMAT, "format version stored")


func test_record_captures_choices_and_battle() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.build_market()
	run.set_bounty(run.next_wave[0], 5)
	var battle := run.start_battle()
	battle.run_to_end()
	run.finish_battle(battle)
	var r1: Dictionary = run.to_record()["rounds"][0]
	check_eq(r1["actions"][0]["kind"], "market", "market build recorded")
	check_eq(r1["bounties"][run.next_wave[0]], 5, "bounty recorded")
	check(r1.has("battle"), "battle summary recorded")
	check_eq(r1["relic_offer"].size(), 3, "relic offer recorded")


func test_unfinished_run_includes_current_round() -> void:
	var run := RunState.new(Content.load_default(), 5)
	var record := run.to_record()
	check_eq(record["result"], "in_progress", "result")
	check_eq(record["rounds"].size(), 1, "current round included")


func test_record_survives_json_and_feeds_stats() -> void:
	var runs := []
	for s in 3:
		runs.append(JSON.parse_string(JSON.stringify(_played(200 + s).to_record())))
	var lines := RunStats.report(runs)
	check(lines[0].begins_with("Runs: 3"), "report counts runs: %s" % lines[0])
