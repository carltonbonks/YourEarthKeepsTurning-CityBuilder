extends SceneTree
## Saves a picture of the game screen after a bot has played some rounds, to check how the map looks.
## Needs a display (not --headless); in a container: xvfb-run ~/godot/godot --path . -s res://tools/snapshot.gd -- seed=4821 round=5 style=market out=/tmp/map.png
## mid=1 stops partway through the round's first day instead of at the build phase; zoom= zooms the map;
## gates=2 has the bot order up to 2 gates; flat=1 shows the flat top-down map instead of the tilted one;
## pick=1 shows the round's first dawn pick instead; night=1 plays the round's first day into its night
## so the camera has closed in on the town (NightCamera); preview=<building id> blinks where that building would go,
## as hovering its card does; venture=<id> (with pick=1) deals that venture as the first dawn card, and
## venture_taken=1 takes it and shows who never came home.

func _init() -> void:
	var args := {"seed": "4821", "round": "4", "style": "market", "out": "user://snapshot.png", "mid": "0", "zoom": "1.2", "gates": "-1", "flat": "0", "pick": "0", "night": "0", "preview": "", "venture": "", "venture_taken": "0"}
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
	if int(args["gates"]) >= 0:
		bot.gates = int(args["gates"])
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
	if args["night"] == "1" and run.phase == RunState.Phase.BUILD:
		bot.build(run)
		run.begin_round()
		run.choose_pick(bot.pick(run))
		while not run.world.is_night():
			run.step()
		for i in 60:
			run.step()
	main._overlays.hide()
	if args["pick"] == "1" and run.phase == RunState.Phase.BUILD:
		bot.build(run)
		run.begin_round()
		if args["venture"] != "":
			run.pick_offer[0] = {"kind": "venture", "role": "venture", "cost": 0, "venture": args["venture"]}
		main._overlays.show_for_phase()
		if args["venture_taken"] == "1":
			main._take_pick(0)
	main._refresh()
	if args["preview"] != "":
		main._preview_building(args["preview"])
	main._arena.iso = args["flat"] != "1"
	if args["night"] != "1":
		main._arena.zoom = float(args["zoom"])
	for i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(args["out"])
	print("Saved %s (round %d)" % [args["out"], run.round_number])
	quit()
