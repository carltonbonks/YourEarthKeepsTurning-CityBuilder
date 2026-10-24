extends SceneTree
## Saves a picture of the game screen after a bot has played some rounds, to check how the map looks.
## Needs a display (not --headless); in a container: xvfb-run ~/godot/godot --path . -s res://tools/snapshot.gd -- seed=4821 round=5 style=market out=/tmp/map.png
## mid=1 stops partway through the round's first day instead of at the build phase; zoom= zooms the map;
## gates=2 has the bot order up to 2 gates; flat=1 shows the flat top-down map instead of the tilted one;
## pick=1 shows the round's first dawn pick instead; night=1 plays the round's first day into its night
## so the camera has closed in on the town (NightCamera); preview=<building id> blinks where that building would go,
## as hovering its card does; relic=1 stops at that round's relic pick and shows it; impact=1 shows Who did what
## (with relic=1, that round's; otherwise the whole run's). steps= is how many steps mid=1 plays; goods carried in
## meanwhile show as one "+N" popup. venture=<id> (with pick=1) deals that venture as the first dawn card, and
## venture_taken=1 takes it and shows who never came home. give=<relic id> hands the town that relic first;
## wave=1 (with night=1) plays on into the round's attack night until the hearth or a watch post shoots.
## lodge=1 raises a Geomancer's lodge at the start, so dawn picks show the geomancy spell cards.
## pedlars=1 shows the round's pedlar choice (round= a pedlar round, e.g. 3). master=<trait id> (with pick=1)
## deals a Promote card for a craftsperson with that craft trait as the first dawn card.
## ageup=1 plays on from that round until the town reaches a new age and shows the celebration (style=bronze or
## medieval gets there); levelup=1 levels up the first hero so the halo shows.
## deals=<id,id,...> lays out those caravan trade cards (data/trades.json) in the build hand.
## rolled=1 (with pick=1) deals rolled townsfolk cards: a magic warrior, a powerful forager and a mythic tribesperson;
## rolled=2 a magic family, a mythic venture and a powerful hero.
## size=<W>x<H> sets the window size (default 1600x1000), to check the screen layout at other sizes.

func _init() -> void:
	var args := {"seed": "4821", "round": "4", "style": "market", "out": "user://snapshot.png", "mid": "0", "zoom": "1.2", "gates": "-1", "flat": "0", "pick": "0", "night": "0", "preview": "", "relic": "0", "impact": "0", "steps": "150", "venture": "", "venture_taken": "0", "give": "", "wave": "0", "lodge": "0", "pedlars": "0", "master": "", "ageup": "0", "levelup": "0", "deals": "", "rolled": "0", "size": "1600x1000"}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var wh: PackedStringArray = args["size"].split("x")
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	var main: Control = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._new_run(int(args["seed"]))
	var run: RunState = main.run
	if args["give"] != "":
		run.relics.append(args["give"])
		run.relic_acquired_round[args["give"]] = run.round_number
	if args["lodge"] == "1" and run.world.add_building("geomancer"):
		run.world.buildings[-1]["work_left"] = 0.0
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
		if args["wave"] == "1":
			var tower_shot := func() -> bool: return run.world.shots.any(func(x: Dictionary) -> bool: return x.get("tower", false))
			while run.phase == RunState.Phase.PICK or run.phase == RunState.Phase.SIM:
				if run.phase == RunState.Phase.PICK:
					run.choose_pick(bot.pick(run))
				run.step()
				if run.world.is_wave_night() and tower_shot.call():
					main._set_speed(0)  # Hold the shot in the air for the picture.
					break
	main._overlays.hide()
	if args["pedlars"] == "1" and run.awaiting_pedlar():
		main._refresh()
		main._overlays.show_for_phase()
	if args["pick"] == "1" and run.phase == RunState.Phase.BUILD:
		bot.build(run)
		run.begin_round()
		if args["venture"] != "":
			run.pick_offer[0] = {"kind": "venture", "role": "venture", "cost": 0, "venture": args["venture"]}
		if args["master"] != "":
			var crafter: Unit = run.world.folk[0]
			crafter.made["knapper"] = 9
			run.pick_offer[0] = {"kind": "promote", "role": "craftsperson", "cost": 15, "unit": crafter, "workshop": "knapper",
				"trait": args["master"], "name": run.people.unused_name()}
		if args["rolled"] == "1":
			run.pick_offer = [{"kind": "folk", "role": "warrior", "cost": 0, "roll": "blue", "mark": "swift"},
				{"kind": "folk", "role": "tribesperson", "cost": 0, "leaning": "forager", "roll": "yellow", "mark": "nimble",
					"boons": ["born_leader", "twins"]},
				{"kind": "folk", "role": "tribesperson", "cost": 0, "leaning": "woodcutter", "roll": "orange", "boons": ["many_mother"]}]
		if args["rolled"] == "2":
			run.pick_offer = [{"kind": "family", "role": "family", "cost": 0, "roles": ["tribesperson", "warrior"], "roll": "blue",
				"boons": ["big_family"]},
				{"kind": "venture", "role": "venture", "cost": 0, "venture": run.content.ventures.keys()[0], "roll": "orange",
					"boons": ["cursed_road"]}]
			var hero := run.people.make_hero(true)
			var card := {"kind": "hero", "role": "hero", "cost": 25, "hero": hero, "roll": "yellow", "boons": ["war_tested", "houndmaster"]}
			run.people._shape_hero(card, SeededRng.new(1))
			run.pick_offer.append(card)
		main._overlays.show_for_phase()
		if args["venture_taken"] == "1":
			main._take_pick(0)
	if args["deals"] != "" and run.phase == RunState.Phase.BUILD:
		run.caravan.offers.clear()
		for id in args["deals"].split(","):
			run.caravan.offers.append({"deal": id, "need": run.caravan.need(id), "taken": false})
	main._refresh()
	main._arena.celebrations.update(run, Time.get_ticks_msec())
	if args["ageup"] == "1":
		var start_age := run.age
		while not run.is_over() and run.age == start_age:
			match run.phase:
				RunState.Phase.BUILD:
					bot.build(run)
					run.begin_round()
				RunState.Phase.PICK:
					run.choose_pick(bot.pick(run))
				RunState.Phase.SIM:
					run.step()
				RunState.Phase.RELIC:
					run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
		# A few steps on, so the new ground has been drawn once and glows.
		for i in 10:
			run.step()
		main._refresh()
	if args["levelup"] == "1" and not run.living_heroes().is_empty():
		var hero: Unit = run.living_heroes()[0]
		hero.xp = run.content.num("xp_per_level") * hero.level
		run.people.level_up(hero)
	main._arena.celebrations.update(run, Time.get_ticks_msec())
	if args["deals"] != "":
		# Scroll the hand to its end so the Trading section shows.
		await process_frame
		for scroll in main.find_children("*", "ScrollContainer", true, false):
			if (scroll as ScrollContainer).get_parent() is BuildHandView:
				scroll.scroll_horizontal = 100000
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
