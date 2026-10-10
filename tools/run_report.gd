extends SceneTree
## Stats from run records: runs you played (copied or downloaded from Run history)
## and/or simulated ones from balance_run.gd.
## Usage: godot --headless --path . -s res://tools/run_report.gd -- in=runs.jsonl [in=more.json]
## Each input may be one run (JSON object), a JSON array of runs, or one run per line.

func _init() -> void:
	var runs: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("in="):
			runs.append_array(load_runs(arg.trim_prefix("in=")))
	if runs.is_empty():
		print("No runs found. Pass in=<file>.")
		quit(1)
		return
	print("\n".join(RunStats.report(runs)))
	quit()


static func load_runs(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) == OK:
		if json.data is Dictionary:
			return [json.data]
		if json.data is Array:
			return json.data
	var runs := []
	for line in text.split("\n", false):
		var one: Variant = JSON.parse_string(line)
		if one is Dictionary:
			runs.append(one)
	return runs
