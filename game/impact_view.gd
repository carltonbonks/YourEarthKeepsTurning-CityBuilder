class_name ImpactView
extends RefCounted
## Who did what (the round record's "impact", see RunRecord.note_impact): heroes, each kind of townsfolk and the
## defences, with the damage they dealt and took, kills, losses and the work they did. Built into the overlay panel
## by Overlays.show_impact; `headline` is the one line over the relic pick. Read-only.

const GROUPS := ["heroes", "folk", "defences"]
const GROUP_TITLES := {"heroes": "Heroes", "folk": "Townsfolk", "defences": "Hearth and towers"}
const DEALT_COLOR := Color("#e0a050")
const TAKEN_COLOR := Color("#d07070")


## The round to show as "this round": the one being played, or the last finished one while building
## (or once the run is over). {} before any round has started.
static func shown_round(run: RunState) -> Dictionary:
	var rec := run.record
	if run.phase == RunState.Phase.BUILD or rec.entry.is_empty():
		if rec.rounds.is_empty():
			return {}
		var last: Dictionary = rec.rounds[-1]
		return {"round": int(last["round"]), "impact": last.get("impact", {})}
	return {"round": int(rec.entry["round"]), "impact": RunRecord.rounded_impact(rec.entry.get("impact", {}))}


## Every round's impact added up.
static func whole_run(run: RunState) -> Dictionary:
	var all: Array = run.record.rounds.map(func(r: Dictionary) -> Dictionary: return r.get("impact", {}))
	if not run.record.entry.is_empty():
		all.append(RunRecord.rounded_impact(run.record.entry.get("impact", {})))
	var out := {}
	for impact: Dictionary in all:
		for group: String in impact:
			var g: Dictionary = out.get_or_add(group, {})
			for who: String in impact[group]:
				var row: Dictionary = g.get_or_add(who, {})
				var add: Dictionary = impact[group][who]
				for stat: String in add:
					if add[stat] is Dictionary:
						var goods: Dictionary = row.get_or_add(stat, {})
						for good: String in add[stat]:
							goods[good] = int(goods.get(good, 0)) + int(add[stat][good])
					elif add[stat] is String:
						row[stat] = add[stat]
					else:
						row[stat] = int(row.get(stat, 0)) + int(add[stat])
	return out


## Plain name for a row: a hero's name and class, a townsfolk role (with how many there are now), a defence.
static func row_name(run: RunState, group: String, who: String, row: Dictionary) -> String:
	var content := run.content
	match group:
		"heroes":
			var cls: String = content.hero_classes.get(row.get("class", ""), {}).get("name", "")
			var fate := ""
			if run.fallen.any(func(h: Unit) -> bool: return h.display_name == who):
				fate = ", fell"
			elif run.departed.any(func(h: Unit) -> bool: return h.display_name == who):
				fate = ", left"
			return "%s (%s%s)" % [who, cls.to_lower(), fate] if cls != "" else who
		"folk":
			if who == "risen":
				return "Risen bones"
			var role: String = content.townsfolk.get(who, {}).get("name", who.capitalize())
			return "%s (%d)" % [role, int(run.record.folk_counts().get(who, 0))]
	if who == "hearth":
		return "Hearth"
	if who == "relic":
		return "Relics"
	return content.buildings.get(who, {}).get("name", who.capitalize())


## The work a row did, in a few words ("brought 120 wood, 40 stone · made 3 · raised 2 buildings").
static func work_text(row: Dictionary) -> String:
	var parts := PackedStringArray()
	var goods: Dictionary = row.get("goods", {})
	if not goods.is_empty():
		var keys := goods.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return int(goods[a]) > int(goods[b]))
		var each := PackedStringArray()
		for good: String in keys:
			each.append("%d %s" % [goods[good], good])
		parts.append("brought " + ", ".join(each))
	if int(row.get("made", 0)) > 0:
		parts.append("made %d" % row["made"])
	if int(row.get("raised", 0)) > 0:
		parts.append("raised %d building%s" % [row["raised"], "" if int(row["raised"]) == 1 else "s"])
	if int(row.get("paved", 0)) > 0:
		parts.append("paved %d" % row["paved"])
	if int(row.get("patched", 0)) > 0:
		parts.append("mended hearth %d" % row["patched"])
	if int(row.get("helped", 0)) > 0:
		parts.append("lent a hand %ds" % row["helped"])
	if int(row.get("supplied", 0)) > 0:
		parts.append("supply runs %d" % row["supplied"])
	if int(row.get("drilled", 0)) > 0:
		parts.append("drilled for %d XP" % row["drilled"])
	return " · ".join(parts)


## Sum of one stat over every row of every group.
static func total(impact: Dictionary, stat: String) -> int:
	var sum := 0
	for group: String in impact:
		for who: String in impact[group]:
			sum += int(impact[group][who].get(stat, 0))
	return sum


## One line for the relic pick: who hit hardest, what the townsfolk brought in, what the hearth took.
static func headline(run: RunState, impact: Dictionary) -> String:
	var parts := PackedStringArray()
	var dealt := total(impact, "dealt")
	var best := ""
	var best_dealt := 0
	for group: String in ["heroes", "folk", "defences"]:
		for who: String in impact.get(group, {}):
			var row: Dictionary = impact[group][who]
			if int(row.get("dealt", 0)) > best_dealt:
				best_dealt = int(row["dealt"])
				best = row_name(run, group, who, row).get_slice(" (", 0)
	if best != "" and dealt > 0:
		parts.append("Hardest hitter: %s, %d%% of all damage" % [best, roundi(100.0 * best_dealt / dealt)])
	var brought := 0
	for who: String in impact.get("folk", {}):
		for good: String in impact["folk"][who].get("goods", {}):
			brought += int(impact["folk"][who]["goods"][good])
	if brought > 0:
		parts.append("townsfolk brought in %d goods" % brought)
	var hearth_taken := int(impact.get("defences", {}).get("hearth", {}).get("taken", 0))
	parts.append("the hearth took %d damage" % hearth_taken)
	var text := "; ".join(parts) + "."
	return text.substr(0, 1).to_upper() + text.substr(1)


## Rows of one group, in the order shown: most damage dealt first, then most work.
static func sorted_rows(impact: Dictionary, group: String) -> Array:
	var rows: Dictionary = impact.get(group, {})
	var keys: Array = rows.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var da := int(rows[a].get("dealt", 0))
		var db := int(rows[b].get("dealt", 0))
		if da != db:
			return da > db
		return a < b)
	return keys


## Builds the tables into `parent`.
static func build(parent: Control, run: RunState, impact: Dictionary) -> void:
	if impact.is_empty():
		UiKit.note(parent, "Nothing to show yet: this fills in as the round plays.", 13)
		return
	var dealt_all := maxi(1, total(impact, "dealt"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for group: String in GROUPS:
		var keys := sorted_rows(impact, group)
		if keys.is_empty():
			continue
		UiKit.heading(box, GROUP_TITLES[group])
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 2)
		box.add_child(grid)
		for title: String in ["", "Dealt", "Taken", "Kills", "Lost", "Work"]:
			UiKit.note(grid, title, 11)
		for who: String in keys:
			var row: Dictionary = impact[group][who]
			_cell(grid, row_name(run, group, who, row), 13, Color.WHITE, 220)
			var dealt := int(row.get("dealt", 0))
			_cell(grid, "%d  (%d%%)" % [dealt, roundi(100.0 * dealt / dealt_all)] if dealt > 0 else "-", 13, DEALT_COLOR, 90)
			_cell(grid, str(row.get("taken", 0)) if int(row.get("taken", 0)) > 0 else "-", 13, TAKEN_COLOR, 50)
			_cell(grid, str(row.get("kills", 0)) if int(row.get("kills", 0)) > 0 else "-", 13, Color.WHITE, 36)
			_cell(grid, str(row.get("lost", 0)) if int(row.get("lost", 0)) > 0 else "-", 13, TAKEN_COLOR, 30)
			var work := _cell(grid, work_text(row), 12, UiKit.HINT_COLOR, 300)
			work.autowrap_mode = TextServer.AUTOWRAP_WORD


static func _cell(grid: GridContainer, text: String, font_size: int, color: Color, width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = width
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	grid.add_child(label)
	return label
