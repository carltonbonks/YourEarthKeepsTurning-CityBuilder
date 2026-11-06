extends TestCase
## Townsfolk at work (Yusuf, 2026-10-26): each townsperson's time by kind, the dawn card's word (Stretched, Busy,
## Slack), the Reeve's hut that shows the rest and tilts the dawn picks, and the round record's "folk_time".


func _setup() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	w.enemies.clear()
	w.folk.clear()
	return run


func _standing(run: RunState, type: String) -> void:
	check(run.world.add_building(type), "the %s has a plot" % type)
	run.world.buildings[-1]["work_left"] = 0.0


func test_a_gatherers_day_counts_as_work_and_idle_as_idle() -> void:
	var run := _setup()
	var w := run.world
	var gatherer := w.folk_ai.add_folk("tribesperson")
	var idler := w.folk_ai.add_folk("tribesperson")
	w.folk_ai.begin_step()
	gatherer.task = "gather"
	gatherer.task_index = 0
	idler.task = "idle"
	idler.task_timer = 99.0
	w.folk_ai._note_time(gatherer)
	w.folk_ai._note_time(idler)
	check(float(gatherer.time.get("work", 0.0)) > 0.0, "a gathering step is the tribesperson's own work")
	check(float(idler.time.get("idle", 0.0)) > 0.0, "a step waiting at home is idle")
	var row: Dictionary = w.folk_ai.role_time["tribesperson"]
	check(is_equal_approx(float(row["work"]), w.dt) and is_equal_approx(float(row["idle"]), w.dt), "the role adds up its people")


func test_roles_read_the_same_task_differently() -> void:
	var run := _setup()
	var w := run.world
	var crafter := w.folk_ai.add_folk("craftsperson")
	crafter.task = "gather"
	w.folk_ai._note_time(crafter)
	check(float(crafter.time.get("fallback", 0.0)) > 0.0, "a craftsperson gathering is falling back, not their own work")


func test_workers_count_by_day_only_and_warriors_at_night_too() -> void:
	var run := _setup()
	var w := run.world
	w.time = run.content.num("day_seconds") + 1.0
	var worker := w.folk_ai.add_folk("tribesperson")
	worker.task = "idle"
	var warrior := w.folk_ai.add_folk("warrior")
	warrior.activity = "fight"
	w.folk_ai._note_time(worker)
	w.folk_ai._note_time(warrior)
	check(worker.time.is_empty(), "a tribesperson asleep at night is not counted")
	check(float(warrior.time.get("work", 0.0)) > 0.0, "a warrior fighting at night is at work")


func test_a_step_of_play_tallies_everyone() -> void:
	var run := _setup()
	var w := run.world
	for i in 3:
		w.folk_ai.add_folk("tribesperson")
	w.folk_ai.add_folk("warrior")
	for i in 20:
		w.step()
	var total := 0.0
	for role: String in w.folk_ai.role_time:
		for kind: String in w.folk_ai.role_time[role]:
			total += float(w.folk_ai.role_time[role][kind])
	check(total > 0.0, "playing on counts time")
	check(w.folk_ai.role_time.has("warrior"), "the warrior's patrol is counted")


func test_the_word_reads_the_idle_share() -> void:
	var run := _setup()
	var ai := run.world.folk_ai
	ai.role_time = {"craftsperson": {"work": 50.0, "idle": 50.0}, "tribesperson": {"work": 99.0, "idle": 1.0},
		"warrior": {"fallback": 70.0, "work": 30.0}}
	check_eq(run.people.busy_word("craftsperson"), "slack", "half the day idle is Slack")
	check_eq(run.people.busy_word("tribesperson"), "stretched", "hardly idle is Stretched")
	check_eq(run.people.busy_word("warrior"), "stretched", "warriors fighting a third of the time are Stretched")
	ai.role_time = {"tribesperson": {"work": 85.0, "idle": 15.0}}
	check_eq(run.people.busy_word("tribesperson"), "busy", "some idle time is Busy")


func test_too_little_this_round_falls_back_to_last_round() -> void:
	var run := _setup()
	run.world.folk_ai.role_time = {"craftsperson": {"idle": 1.0}}
	check_eq(run.people.busy_word("craftsperson"), "", "a second of time says nothing yet")
	run.record.rounds.append({"round": 0, "folk_time": {"craftsperson": {"work": 100, "idle": 5}}})
	check_eq(run.people.busy_of("craftsperson")["from"], "last", "last round's record stands in")
	check_eq(run.people.busy_word("craftsperson"), "stretched", "and gives the word")


func test_the_reeves_hut_tilts_the_dawn_toward_stretched_roles() -> void:
	var run := _setup()
	run.world.folk_ai.role_time = {"craftsperson": {"work": 50.0, "idle": 50.0}, "tribesperson": {"work": 99.0, "idle": 1.0}}
	var crafter := {"kind": "folk", "role": "craftsperson"}
	var tribe := {"kind": "folk", "role": "tribesperson"}
	check_eq(run.people.reeve_tilt(crafter), 1.0, "no tilt without the hut")
	_standing(run, "reeves_hut")
	check(run.people.reeve_tilt(crafter) < 1.0, "a Slack role comes up less often")
	check(run.people.reeve_tilt(tribe) > 1.0, "a Stretched role comes up more often")
	check_eq(run.people.reeve_tilt({"kind": "hero", "role": "hero"}), 1.0, "heroes are not tilted")


func test_the_word_is_free_and_the_rest_needs_the_hut() -> void:
	var run := _setup()
	run.world.folk_ai.role_time = {"craftsperson": {"work": 50.0, "idle": 50.0}}
	var u := run.world.folk_ai.add_folk("craftsperson")
	u.time = {"work": 10.0, "idle": 2.0}
	run.world.folk_ai.role_tasks = {"craftsperson": {"build": 20.0, "idle": 60.0, "walk:build": 20.0}}
	var lines := FolkAtWork.card_lines(run, "craftsperson")
	check(lines[0].begins_with("Slack"), "the card's hover says the word and why")
	check(lines[1].begins_with("Mostly idle (60%)"), "and the biggest task, free")
	check(FolkAtWork.card_bar(run, "craftsperson", 160.0) != null, "the card's task bar is free")
	check(lines[-1].contains("Reeve's hut"), "and points to the hut for the rest")
	check_eq(FolkAtWork.unit_line(run, u), "", "no day on the map hover without the hut")
	_standing(run, "reeves_hut")
	lines = FolkAtWork.card_lines(run, "craftsperson")
	check(lines[-1].begins_with("Their round:"), "with the hut the hover splits the round")
	check(lines[-1].contains("raising buildings 40% (20% walking)"), "by task, with the walking to it")
	check(FolkAtWork.unit_line(run, u).begins_with("This round:"), "and the map hover shows their day")


func test_the_tally_names_each_task_and_its_goods() -> void:
	var run := _setup()
	var w := run.world
	var gatherer := w.folk_ai.add_folk("tribesperson")
	w.folk_ai.begin_step()
	var wood := -1
	for i in w.nodes.size():
		if w.nodes[i]["gives"] == "wood":
			wood = i
			break
	gatherer.task = "gather"
	gatherer.task_index = wood
	gatherer.noted_pos = gatherer.pos
	w.folk_ai._note_time(gatherer)
	check(float(gatherer.tasks.get("fetch:wood", 0.0)) > 0.0, "gathering at a grove counts as gathering wood")
	gatherer.pos += Vector2(5, 0)
	w.folk_ai._note_time(gatherer)
	check(float(gatherer.tasks.get("walk:fetch:wood", 0.0)) > 0.0, "on the move to it, it counts as walking for wood")
	check(w.folk_ai.role_tasks["tribesperson"].has("walk:fetch:wood"), "the role adds it up too")
	var list := FolkAtWork.purposes(gatherer.tasks)
	check_eq(list.size(), 1, "the walking folds into what it was for")
	check(float(list[0]["walk"]) > 0.0 and float(list[0]["doing"]) > 0.0, "split into walking and doing")


func test_fallback_work_counts_as_spare() -> void:
	var run := _setup()
	run.world.folk_ai.role_time = {"craftsperson": {"work": 30.0, "fallback": 65.0, "idle": 5.0}}
	check_eq(run.people.busy_word("craftsperson"), "slack", "a craftsperson mostly hauling wood is not busy at their trade")
	run.world.folk_ai.role_tasks = {"craftsperson": {"fetch:wood": 20.0, "walk:fetch:wood": 45.0, "build": 30.0, "idle": 5.0}}
	var why := FolkAtWork.why_line(run, "craftsperson", run.people.busy_of("craftsperson")["tasks"])
	check(why.begins_with("Mostly gathering wood (65%): no building or bench needed them"), "the card says why: " + why)


func test_the_record_keeps_each_roles_time() -> void:
	var record := bot_record(4821, "balanced")
	var rd: Dictionary = record["rounds"][2]
	check(rd.has("folk_time"), "each round records folk_time")
	check(float(rd["folk_time"].get("tribesperson", {}).get("work", 0)) > 0.0, "tribespeople worked")
	check(rd.has("folk_tasks"), "and folk_tasks")
	check(rd["folk_tasks"].get("tribesperson", {}).keys().any(func(k: String) -> bool: return k.contains("fetch:")),
		"tribespeople gathered named goods")
