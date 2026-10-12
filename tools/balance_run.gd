extends SceneTree
## Headless balance report: plays many seeded runs with a scripted player.
## Usage: godot --headless --path . -s res://tools/balance_run.gd [-- runs=50 style=balanced out=runs.jsonl label=pr5 gates=2 gate_round=3]
## out= also writes every run's record (same format as the game's Run history) for run_report.gd
## and tools/export_csv.py. label= names the build being tested (it becomes the runs' game_version).

func _init() -> void:
	var runs := 100
	var style := "balanced"
	var out_path := ""
	var label := "dev"
	var gates := -1  # -1 keeps the bot's default
	var gate_round := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			runs = int(arg.trim_prefix("runs="))
		elif arg.begins_with("style="):
			style = arg.trim_prefix("style=")
		elif arg.begins_with("out="):
			out_path = arg.trim_prefix("out=")
		elif arg.begins_with("label="):
			label = arg.trim_prefix("label=")
		elif arg.begins_with("gates="):
			gates = int(arg.trim_prefix("gates="))
		elif arg.begins_with("gate_round="):
			gate_round = int(arg.trim_prefix("gate_round="))
	var out_file: FileAccess = FileAccess.open(out_path, FileAccess.WRITE) if out_path != "" else null
	var content := Content.load_default()
	var wins := 0
	var rounds_total := 0
	var deaths_total := 0
	var folk_lost := 0
	var lost_on := {}
	for s in runs:
		var run := RunState.new(content, 1000 + s)
		var bot := AutoPlayer.new()
		bot.style = style
		if gates >= 0:
			bot.gates = gates
		if gate_round >= 0:
			bot.gate_round = gate_round
		bot.play_run(run)
		if out_file != null:
			var record := run.to_record()
			record.erase("story")
			record["player"] = "bot:" + style
			record["id"] = "%s-%s-%d" % [label, style, run.run_seed]
			record["game_version"] = label
			out_file.store_line(JSON.stringify(record))
		if run.phase == RunState.Phase.WON:
			wins += 1
		else:
			lost_on[run.round_number] = int(lost_on.get(run.round_number, 0)) + 1
		rounds_total += run.round_number
		deaths_total += run.fallen.size()
		folk_lost += run.fallen_folk
	print("Style: %s, %d runs (seeds 1000-%d)" % [style, runs, 999 + runs])
	print("Win rate: %d%%" % roundi(100.0 * wins / runs))
	print("Average round reached: %.1f" % (float(rounds_total) / runs))
	print("Average heroes lost per run: %.1f" % (float(deaths_total) / runs))
	print("Average townsfolk killed per run: %.1f" % (float(folk_lost) / runs))
	var keys := lost_on.keys()
	keys.sort()
	for r in keys:
		print("  lost in round %d: %d runs" % [r, lost_on[r]])
	quit()
