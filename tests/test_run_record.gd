extends TestCase


func test_record_has_one_entry_per_round_played() -> void:
	var record := bot_record()
	check_eq(record["rounds"].size(), int(record["round_reached"]), "one round entry per round")
	check(record["result"] in ["won", "lost"], "finished run has a result")
	check_eq(record["format"], RunState.RECORD_FORMAT, "format version stored")


func test_record_captures_builds_picks_and_wave() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.build("hut")
	run.begin_round()
	while run.phase == RunState.Phase.PICK or run.phase == RunState.Phase.SIM:
		if run.phase == RunState.Phase.PICK:
			run.choose_pick(0)
		else:
			run.run_until_pause()
	var r1: Dictionary = run.to_record()["rounds"][0]
	check_eq(r1["actions"][0]["building"], "hut", "hut order recorded")
	check_eq(r1["picks"].size(), 3, "three dawn picks recorded")
	check_eq(r1["picks"][0]["offered"].size(), 3, "offered cards recorded")
	check(r1.has("battle"), "wave summary recorded")
	check(not r1["wave_sides"].is_empty(), "wave sides recorded")
	check_eq(r1["relic_offer"].size(), 3, "relic offer recorded")


func test_unfinished_run_includes_current_round() -> void:
	var run := RunState.new(Content.load_default(), 5)
	var record := run.to_record()
	check_eq(record["result"], "in_progress", "result")
	check_eq(record["rounds"].size(), 1, "current round included")


func test_record_survives_json_and_feeds_stats() -> void:
	var runs := []
	for r in [bot_record(), bot_record(1001, "market"), bot_record(1003, "bronze")]:
		runs.append(JSON.parse_string(JSON.stringify(r)))
	var lines := RunStats.report(runs)
	check(lines[0].begins_with("Runs: 3"), "report counts runs: %s" % lines[0])
	var history := RunHistory.one_line(runs[0])
	check(history.length() > 0, "history line")
