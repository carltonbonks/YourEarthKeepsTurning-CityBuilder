extends SceneTree
## Saves a picture of the game screen after a bot has played some rounds, to check how the map looks.
## Needs a display (not --headless); in a container: xvfb-run ~/godot/godot --path . -s res://tools/snapshot.gd -- seed=4821 round=5 style=market out=/tmp/map.png
## mid=1 stops partway through the round's first day instead of at the build phase; zoom= zooms the map;
## stake=1 shows a road being staked (build phase only).

func _init() -> void:
	var args := {"seed": "4821", "round": "4", "style": "market", "out": "user://snapshot.png", "mid": "0", "zoom": "1.2", "stake": "0"}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var main: Control = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._new_run(int(args["seed"]))
	var run: RunState = main.run
	var bot := AutoPlayer.new()
	bot.style = args["style"]
	while not run.is_over() and not (run.round_number >= int(args["round"]) and run.phase == RunState.Phase.BUILD):
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(bot.pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
	if args["mid"] == "1" and run.phase == RunState.Phase.BUILD:
		bot.build(run)
		run.begin_round()
		run.choose_pick(bot.pick(run))
		for i in 150:
			run.step()
	main._overlays.hide()
	main._refresh()
	main._arena.zoom = float(args["zoom"])
	if args["stake"] == "1" and run.phase == RunState.Phase.BUILD:
		main._arena.start_staking()
		main._arena.stake_points = [Vector2.ZERO, Vector2(120, -150), Vector2(170, -300)]
		main._arena._update_preview()
	for i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(args["out"])
	print("Saved %s (round %d)" % [args["out"], run.round_number])
	quit()
