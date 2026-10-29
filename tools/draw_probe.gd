extends SceneTree
## Measures how long the map takes to draw as the town grows, with the rendered art and with the placeholder shapes
## (the frame-rate budget in docs/ART_SPEC.md). A bot plays to round `round`; the town is then padded with extra
## townsfolk as in tools/perf_probe.gd, raiders come in, and the day plays a little so people spread out. Then the
## game is paused and ArenaView's own drawing time (draw_usec) is averaged over `frames` frames at the tilted view's
## usual zoom. Needs a display: xvfb-run ~/godot/godot --path . -s res://tools/draw_probe.gd
## [-- people=60,175,400 seed=4821 round=8 style=balanced frames=90 zoom=1.6]

func _init() -> void:
	var args := {"people": "60,175,400", "seed": "4821", "round": "8", "style": "balanced", "frames": "90", "zoom": "1.6"}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	var main: Control = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.settings.persist = false
	main.settings.tips = false
	main.settings.intro_seen = true
	print("people  art  avg ms  worst ms")
	for size_text: String in args["people"].split(","):
		var size := int(size_text)
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
		if run.is_over():
			print("%6d  the bot lost before round %s; try another seed" % [size, args["round"]])
			continue
		bot.build(run)
		run.begin_round()
		while run.phase == RunState.Phase.PICK:
			run.choose_pick(bot.pick(run))
		var roles := ["tribesperson", "tribesperson", "craftsperson", "warrior"]
		var i := 0
		while run.population() < size:
			run.world.folk_ai.add_folk(roles[i % roles.size()])
			i += 1
		var w := run.world
		for r in size / 3:
			var at := Vector2.from_angle(TAU * r / maxf(1.0, size / 3.0)) * run.content.num("world_radius")
			w.enemies.append(w.enemy_ai.make_enemy("raider", at, w.time))
		for step in 150:
			if run.phase != RunState.Phase.SIM:
				break
			run.step()
		main._set_speed(0)
		var arena: ArenaView = main._arena
		arena.zoom = float(args["zoom"])
		arena.pan = Vector2.ZERO
		for art: bool in [true, false]:
			arena.art = art
			var total := 0
			var worst := 0
			for f in int(args["frames"]):
				await process_frame
				total += arena.draw_usec
				worst = maxi(worst, arena.draw_usec)
			print("%6d  %-3s %7.2f %9.2f" % [run.population(), "on" if art else "off", total / 1000.0 / float(args["frames"]), worst / 1000.0])
	quit()
