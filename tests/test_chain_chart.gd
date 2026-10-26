extends TestCase
## docs/CHAINS.md is drawn from the data (ChainChart), so it can't drift from the game.


func test_the_chain_chart_matches_the_data() -> void:
	var on_disk := FileAccess.get_file_as_string("res://docs/CHAINS.md")
	check(on_disk == ChainChart.markdown(Content.load_default()),
		"docs/CHAINS.md is out of date: run ~/godot/godot --headless --path . -s res://tools/chains.gd")


func test_every_craft_is_on_the_chart() -> void:
	var chart := ChainChart.markdown(Content.load_default())
	var c := Content.load_default()
	for id: String in c.crafts:
		check(chart.contains("craft_" + id + "{{"), "%s is drawn" % id)
		for type: String in c.crafts[id]["opens"]:
			check(chart.contains("craft_%s -.-> %s" % [id, type]), "%s opens %s on the chart" % [id, type])
