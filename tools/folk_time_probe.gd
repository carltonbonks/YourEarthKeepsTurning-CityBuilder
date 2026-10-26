extends SceneTree
## How each townsfolk role spent each round of one bot run (the record's "folk_time") and the dawn word it earned.
## Usage: godot --headless --path . -s res://tools/folk_time_probe.gd [-- seed=4821 style=balanced]

func _init() -> void:
	var seed_value := 4821
	var style := "balanced"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seed="):
			seed_value = int(arg.trim_prefix("seed="))
		elif arg.begins_with("style="):
			style = arg.trim_prefix("style=")
	var run := RunState.new(Content.load_default(), seed_value)
	var bot := AutoPlayer.new()
	bot.style = style
	bot.play_run(run)
	var record := run.to_record()
	print("Result: %s in round %d" % [record["result"], record["round_reached"]])
	for rd: Dictionary in record["rounds"]:
		var line := "Round %2d:" % rd["round"]
		for role: String in ["tribesperson", "craftsperson", "warrior"]:
			var kinds: Dictionary = rd.get("folk_time", {}).get(role, {})
			var total := 0.0
			for k: String in kinds:
				total += float(kinds[k])
			if total <= 0.0:
				continue
			var parts := []
			for k: String in ["work", "fallback", "idle", "down"]:
				parts.append("%s %d%%" % [k, roundi(100.0 * float(kinds.get(k, 0)) / total)])
			line += "  %s x%d [%s]" % [role.left(5), int(rd.get("townsfolk_end", {}).get(role, 0)), ", ".join(parts)]
		print(line)
	quit()
