class_name ChainChart
extends RefCounted
## Draws docs/CHAINS.md, the map of what opens what in the blueprint draft, from the data itself: crafts and the
## buildings they open (data/crafts.json), what each building requires and which buildings age the town up
## (data/buildings.json), and the upgrades the draft can offer for each building (data/upgrades.json).
## tools/chains.gd writes it; tests/test_chain_chart.gd fails when the file and the data disagree, so the chart
## never drifts from the game.


static func markdown(c: Content) -> String:
	var lines: Array[String] = []
	lines.append("# Build chains")
	lines.append("")
	lines.append("What opens what in the blueprint draft. Generated from data/crafts.json, data/buildings.json and data/upgrades.json")
	lines.append("by `tools/chains.gd`; don't edit it by hand. Change the data, then run")
	lines.append("`~/godot/godot --headless --path . -s res://tools/chains.gd` (tests/test_chain_chart.gd fails until you do).")
	lines.append("")
	lines.append("Solid arrows: drafting or raising the first brings or allows the second. Dotted: a craft opens a building, which")
	lines.append("the draft offers only once the town has that craft (a founding tradition's buildings are never held back).")
	lines.append("")
	lines.append("```mermaid")
	lines.append("flowchart LR")
	var shown := {}
	var crafts := c.crafts.keys()
	crafts.sort()
	for id: String in crafts:
		var craft: Dictionary = c.crafts[id]
		lines.append("  craft_%s{{%s}}" % [id, craft["name"]])
		lines.append("  %s --> craft_%s" % [_node(c, "market", shown), id])
		lines.append("  craft_%s --> %s" % [id, _node(c, craft["workshop"], shown)])
		lines.append("  craft_%s --> %s" % [id, _node(c, craft["stall"], shown)])
		for type: String in craft.get("opens", []):
			lines.append("  craft_%s -.-> %s" % [id, _node(c, type, shown)])
	var types := c.buildings.keys()
	types.sort()
	for type: String in types:
		var def: Dictionary = c.buildings[type]
		var needs: String = def.get("requires", "")
		# A craft's stall requires the market, which the craft already shows.
		if needs != "" and not (needs == "market" and _in_craft(c, type)):
			lines.append("  %s --> %s" % [_node(c, needs, shown), _node(c, type, shown)])
		if def.has("ages_up"):
			lines.append("  %s ==> age_%s((%s))" % [_node(c, type, shown), def["ages_up"], c.age_name(def["ages_up"])])
	lines.append("```")
	lines.append("")
	lines.append("## Upgrades by building")
	lines.append("")
	lines.append("One draft offer a round builds on what the town has: an upgrade for a building that stands, a building a craft opened,")
	lines.append("or another craft once the market is in.")
	lines.append("")
	lines.append("| Building | Upgrades |")
	lines.append("| --- | --- |")
	var by_building := {}
	var ids := c.upgrades.keys()
	ids.sort()
	for id: String in ids:
		var up: Dictionary = c.upgrades[id]
		if not by_building.has(up["building"]):
			by_building[up["building"]] = []
		by_building[up["building"]].append("%s (%s)" % [up["name"], up.get("rarity", "white")])
	var with_ups := by_building.keys()
	with_ups.sort_custom(func(a: String, b: String) -> bool: return c.buildings[a]["name"] < c.buildings[b]["name"])
	for type: String in with_ups:
		lines.append("| %s | %s |" % [c.buildings[type]["name"], ", ".join(PackedStringArray(by_building[type]))])
	lines.append("")
	return "\n".join(PackedStringArray(lines))


## A building's node, named the first time it shows: id[Name].
static func _node(c: Content, type: String, shown: Dictionary) -> String:
	if shown.has(type):
		return type
	shown[type] = true
	return "%s[%s]" % [type, c.buildings[type]["name"]]


static func _in_craft(c: Content, type: String) -> bool:
	for id: String in c.crafts:
		if c.crafts[id]["workshop"] == type or c.crafts[id]["stall"] == type:
			return true
	return false
