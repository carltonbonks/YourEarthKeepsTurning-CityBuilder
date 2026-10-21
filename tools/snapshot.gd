extends SceneTree
## Saves a picture of the game screen after a bot has played some rounds, to check how the map looks.
## Needs a display (not --headless); in a container: xvfb-run ~/godot/godot --path . -s res://tools/snapshot.gd -- seed=4821 round=5 style=market out=/tmp/map.png
## mid=1 stops partway through the round's first day instead of at the build phase; zoom= zooms the map;
## gates=2 has the bot order up to 2 gates; flat=1 shows the flat top-down map instead of the tilted one;
## pick=1 shows the round's first dawn pick instead; night=1 plays the round's first day into its night
## so the camera has closed in on the town (NightCamera); preview=<building id> blinks where that building would go,
## as hovering its card does; relic=1 stops at that round's relic pick and shows it; impact=1 shows Who did what
## (with relic=1, that round's; otherwise the whole run's). steps= is how many steps mid=1 plays; goods carried in
## meanwhile show as one "+N" popup.

func _init() -> void:
	var args := {"seed": "4821", "round": "4", "style": "market", "out": "user://snapshot.png", "mid": "0", "zoom": "1.2", "gates": "-1", "flat": "0", "pick": "0", "night": "0", "preview": "", "relic": "0", "impact": "0", "steps": "150"}
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
	var stop_at := RunState.Phase.RELIC if args["relic"] == "1" else RunState.Phase.BUILD
	while not run.is_over() and not (run.round_number >= int(args["round"]) and run.phase == stop_at):
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
		while run.phase == RunState.Phase.PICK:
			run.choose_pick(bot.pick(run))
		main._arena.pickups.update(run.world, Time.get_ticks_msec())
		for i in int(args["steps"]):
			run.step()
		# Show what was carried in meanwhile as one "+N" popup over the hearth.
		main._arena.pickups.update(run.world, Time.get_ticks_msec() + PickupPopups.BUCKET_MS)
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
		main._overlays.show_for_phase()
	main._refresh()
	if args["relic"] == "1" and run.phase == RunState.Phase.RELIC:
		main._overlays.show_for_phase()
	if args["impact"] == "1":
		main._overlays.show_impact(args["relic"] != "1")
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
