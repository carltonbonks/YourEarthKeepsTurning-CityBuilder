extends TestCase
## Smoke test for the game screen: builds the real UI and plays a seeded run
## through it with the bot, refreshing every panel and overlay on the way, so a
## broken UI script shows up as a script error (tools/test.sh fails on those).
## Skips Run history saving so tests never write runs to disk.


func test_screen_shows_every_phase_of_a_run() -> void:
	# Built outside the scene tree (the test runner has no frames), so _ready is called by hand.
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var bot := AutoPlayer.new()
	bot.style = "bronze"
	var seen := {}
	var steps := 0
	while not run.is_over() and steps < 400:
		steps += 1
		seen[run.phase] = true
		screen.call("_refresh")
		var overlays: Overlays = screen.get("_overlays")
		overlays.show_for_phase()
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				screen.call("_refresh")
				run.begin_round()
			RunState.Phase.PICK:
				check(overlays.visible, "the dawn pick shows")
				run.choose_pick(bot.pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				check(overlays.visible, "the relic pick shows")
				run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
	check(run.is_over(), "the bot finishes the run through the screen")
	check(seen.has(RunState.Phase.BUILD) and seen.has(RunState.Phase.PICK) and seen.has(RunState.Phase.RELIC), "every decision phase was shown")
	var overlays: Overlays = screen.get("_overlays")
	overlays.show_for_phase()
	check(overlays.visible, "the end screen shows")
	overlays.show_history()
	overlays.show_tuning()
	check(StatusText.status(run).begins_with("[b]Round"), "the status line is filled in")
	check(StatusText.heroes(run) != "" or run.heroes.is_empty(), "heroes are listed")
	run.dispose()
	screen.free()
