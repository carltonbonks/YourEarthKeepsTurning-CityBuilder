extends SceneTree
## Quick look at the market economy in one bot run.
## Usage: godot --headless --path . -s res://tools/market_probe.gd [-- seed=4821 style=market]

func _init() -> void:
	var seed_value := 4821
	var style := "market"
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
		var spent := 0
		for sale: Dictionary in rd.get("market", []):
			spent += int(sale["price"])
		print("  built: %s  folk: %s" % [JSON.stringify(rd["actions"].map(func(a: Dictionary) -> String: return a.get("building", a.get("kind", "")))), JSON.stringify(rd["townsfolk_start"])])
		print("Round %d: crafted %s, sold %d goods for %d shells, prizes %d, obsidian %d, yields %s" % [rd["round"],
			JSON.stringify(rd.get("crafted", {})), rd.get("market", []).size(), spent, rd.get("prizes", 0),
			rd.get("obsidian", 0), JSON.stringify(rd.get("yields", {}))])
	for h: Dictionary in record["heroes"]:
		print("  %s %s %s lv%d gold %d items %s pack %s" % [h["name"], h["trait"], h["class"], h["level"], h["gold"],
			JSON.stringify(h["items"].map(func(i: Dictionary) -> String: return "%s t%d" % [i["base"], i["tier"]])), JSON.stringify(h["pack"])])
	print("Stock: %s" % JSON.stringify(record["stock"]))
	run.dispose()
	quit()
