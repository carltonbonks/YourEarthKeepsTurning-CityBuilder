extends SceneTree
## Measures how long one simulation step takes as the town grows (see docs/PERFORMANCE.md).
## A bot plays to round `round`; the town is then padded with extra townsfolk (half tribespeople,
## a quarter each craftspeople and warriors), and one raider per three people comes in from the edges.
## Prints ms per step over the next day and night, for each size in `people`.
## Usage: godot --headless --path . -s res://tools/perf_probe.gd [-- people=20,60,175,400,850 seed=4821 round=8 style=balanced]

func _init() -> void:
	var sizes := [20, 60, 175, 400]
	var seed_value := 4821
	var to_round := 8
	var style := "balanced"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("people="):
			sizes = Array(arg.trim_prefix("people=").split(",")).map(func(s: String) -> int: return int(s))
		elif arg.begins_with("seed="):
			seed_value = int(arg.trim_prefix("seed="))
		elif arg.begins_with("round="):
			to_round = int(arg.trim_prefix("round="))
		elif arg.begins_with("style="):
			style = arg.trim_prefix("style=")
	var content := Content.load_default()
	print("people  steps  avg ms  worst ms  at step")
	for size: int in sizes:
		var run := RunState.new(content, seed_value)
		var bot := AutoPlayer.new()
		bot.style = style
		while not run.is_over() and not (run.round_number >= to_round and run.phase == RunState.Phase.BUILD):
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
			print("%6d  the bot lost before round %d; try another seed" % [size, to_round])
			continue
		bot.build(run)
		run.begin_round()
		var roles := ["tribesperson", "tribesperson", "craftsperson", "warrior"]
		var i := 0
		while run.population() < size:
			run.world.folk_ai.add_folk(roles[i % roles.size()])
			i += 1
		var w := run.world
		for r in size / 3:
			var at := Vector2.from_angle(TAU * r / maxf(1.0, size / 3.0)) * content.num("world_radius")
			w.enemies.append(w.enemy_ai.make_enemy("raider", at, w.time + r * 0.2))
		var steps := 0
		var total := 0
		var worst := 0
		var worst_at := 0
		var day_steps := int(w.day_length() / w.dt)
		while steps < day_steps and not run.is_over():
			if run.phase == RunState.Phase.PICK:
				for res: String in run.stock:
					run.stock[res] = maxi(int(run.stock[res]), 200)
				run.choose_pick(-1)
				continue
			if run.phase != RunState.Phase.SIM:
				break
			var t0 := Time.get_ticks_usec()
			run.step()
			var us := Time.get_ticks_usec() - t0
			total += us
			if us > worst:
				worst = us
				worst_at = steps
			steps += 1
		print("%6d %6d %7.1f %9.1f %8d" % [size, steps, total / 1000.0 / maxf(1, steps), worst / 1000.0, worst_at])
		run.dispose()
	quit()
