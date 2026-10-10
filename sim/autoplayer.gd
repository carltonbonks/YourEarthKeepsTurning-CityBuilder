class_name AutoPlayer
extends RefCounted
## A simple scripted player for headless balance runs and tests.
## It stands in for a human making decisions so we can simulate many runs fast.

## "balanced": huts as needed, a longhouse early, then watch posts; picks by need.
## "workers": never takes heroes or builds the longhouse; picks townsfolk only.
## "heroes": rushes the longhouse and takes every hero card it can afford.
var style := "balanced"


func play_run(run: RunState) -> void:
	while not run.is_over():
		match run.phase:
			RunState.Phase.BUILD:
				build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")


func build(run: RunState) -> void:
	if style != "workers" and (run.round_number >= 2 or style == "heroes"):
		run.build("longhouse")
	if style == "heroes" and run.round_number >= 2:
		run.build("tavern")
	if style != "workers" and run.round_number >= (3 if style == "heroes" else 4):
		run.build("shrine")
	if run.housing() - run.population() <= 2:
		run.build("hut")
	if run.round_number >= 3:
		run.build("drying_rack")
	if run.round_number >= 2:
		run.build("watch_post")


func pick(run: RunState) -> int:
	var best := -1
	var best_score := -INF
	for i in run.pick_offer.size():
		if not run.can_take_pick(i):
			continue
		var card := run.pick_offer[i]
		var score := 0.0
		match card["role"]:
			"hero":
				score = 5.0 if style != "workers" else -100.0
				if style == "heroes":
					score = 50.0
			"tribesperson":
				score = 4.0 - run.count_role("tribesperson") * 0.6
			"warrior":
				score = 3.0 - run.count_role("warrior") * 0.8
			"craftsperson":
				var pending := run.world.buildings.any(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0)
				score = (4.0 if pending else 1.0) - run.count_role("craftsperson") * 1.5
		if score > best_score:
			best_score = score
			best = i
	return best
