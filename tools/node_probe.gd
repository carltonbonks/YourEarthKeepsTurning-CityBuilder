extends SceneTree
## Prints how full each kind of resource node is at the start of each round, with the town's stock and people,
## averaged over seeded bot runs. Usage: godot --headless --path . -s res://tools/node_probe.gd [-- runs=20 style=balanced]

func _init() -> void:
	var runs := 20
	var style := "balanced"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			runs = int(arg.trim_prefix("runs="))
		elif arg.begins_with("style="):
			style = arg.trim_prefix("style=")
	var content := Content.load_default()
	var rows := {}  # round -> {key -> [sum, n]}
	var kinds := ["brush", "berries", "grove", "rocks", "flint_pit", "copper_seam", "iron_bog"]
	var goods := ["fuel", "food", "wood", "stone"]
	for s in runs:
		var run := RunState.new(content, 1000 + s)
		var bot := AutoPlayer.new()
		bot.style = style
		var seen := -1
		while not run.is_over():
			match run.phase:
				RunState.Phase.BUILD:
					if run.round_number != seen:
						seen = run.round_number
						var row: Dictionary = rows.get(seen, {})
						for k: String in kinds:
							var amt := 0
							var mx := 0
							for node: Dictionary in run.world.nodes:
								if node["type"] == k and run.world.node_active(node):
									amt += int(node["amount"])
									mx += int(node["max"])
							if mx > 0:
								_add(row, k, 100.0 * amt / mx)
						for g: String in goods:
							_add(row, g, float(run.stock.get(g, 0)))
						_add(row, "people", float(run.world.folk.filter(func(u: Unit) -> bool: return u.alive).size()))
						rows[seen] = row
					bot.build(run)
					run.begin_round()
				RunState.Phase.PICK:
					run.choose_pick(bot.pick(run))
				RunState.Phase.SIM:
					run.run_until_pause()
				RunState.Phase.RELIC:
					run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
		run.dispose()
	var head := "round runs"
	for k: String in kinds:
		head += " %8s" % k.left(8)
	for g: String in goods + ["people"]:
		head += " %6s" % g
	print("Node fullness %% at round start, then stock (style %s, %d runs)" % [style, runs])
	print(head)
	var keys := rows.keys()
	keys.sort()
	for r: int in keys:
		var row: Dictionary = rows[r]
		var line := "%5d %4d" % [r, int(row["people"][1])]
		for k: String in kinds:
			line += (" %8.0f" % (row[k][0] / row[k][1])) if row.has(k) else "        -"
		for g: String in goods + ["people"]:
			line += " %6.1f" % (row[g][0] / row[g][1])
		print(line)
	quit()


func _add(row: Dictionary, key: String, v: float) -> void:
	var p: Array = row.get(key, [0.0, 0])
	p[0] += v
	p[1] += 1
	row[key] = p
