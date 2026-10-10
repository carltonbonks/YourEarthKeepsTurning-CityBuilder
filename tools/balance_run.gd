extends SceneTree
## Headless balance report: plays many seeded runs with a scripted player.
## Usage: godot --headless --path . -s res://tools/balance_run.gd [-- runs=100 style=bounty]

func _init() -> void:
	var runs := 100
	var style := "bounty"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			runs = int(arg.trim_prefix("runs="))
		elif arg.begins_with("style="):
			style = arg.trim_prefix("style=")
	var content := Content.load_default()
	var wins := 0
	var rounds_total := 0
	var deaths_total := 0
	var lost_on := {}
	for s in runs:
		var run := RunState.new(content, 1000 + s)
		var bot := AutoPlayer.new()
		bot.bounty_style = style
		bot.play_run(run)
		if run.phase == RunState.Phase.WON:
			wins += 1
		else:
			lost_on[run.round_number] = int(lost_on.get(run.round_number, 0)) + 1
		rounds_total += run.round_number
		deaths_total += run.fallen.size()
	print("Style: %s, %d runs (seeds 1000-%d)" % [style, runs, 999 + runs])
	print("Win rate: %d%%" % roundi(100.0 * wins / runs))
	print("Average round reached: %.1f" % (float(rounds_total) / runs))
	print("Average heroes lost per run: %.1f" % (float(deaths_total) / runs))
	var keys := lost_on.keys()
	keys.sort()
	for r in keys:
		print("  lost in round %d: %d runs" % [r, lost_on[r]])
	quit()
