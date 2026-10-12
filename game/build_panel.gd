class_name BuildPanel
extends VBoxContainer
## The build-phase panel on the left: roads and palisades to stake out, building orders, bronze
## tool sets and the caravan, stall prices, the warned attack and the Begin round button.
## Every choice goes through RunState; `changed` asks the screen to refresh.

signal changed
signal begin_pressed

const PRICE_LEVELS := ["cheap", "fair", "dear"]

var run: RunState
## The map, which collects road waypoints while staking.
var arena: ArenaView
var _road_box: VBoxContainer
var _build_list: VBoxContainer
var _price_box: VBoxContainer
var _wave_label: RichTextLabel
var _begin_btn: Button


func _init() -> void:
	UiKit.heading(self, "Roads and palisades")
	UiKit.note(self, "Stake out a road by clicking waypoints on the map; it bends round whatever stands in the way. Staking is free, and new buildings leave staked ground clear. Once a stone-layers' yard stands, craftspeople pave it for stone. Everyone walks faster on roads, raiders too.")
	UiKit.note(self, "A palisade runs straight between its waypoints and craftspeople raise it for wood. Raiders go round or batter through; your people climb over slowly. Where a road crosses it there is a gate your people walk through, and watch posts like to stand over gates.")
	_road_box = VBoxContainer.new()
	add_child(_road_box)
	add_child(HSeparator.new())
	UiKit.heading(self, "Order buildings")
	UiKit.note(self, "Craftspeople raise what you order during the days. Each building picks its own plot in the rings round the hearth. Nobody takes orders otherwise.")
	_build_list = VBoxContainer.new()
	add_child(_build_list)
	add_child(HSeparator.new())
	_price_box = VBoxContainer.new()
	add_child(_price_box)
	_wave_label = UiKit.rich(self, 0)
	_wave_label.fit_content = true
	_begin_btn = UiKit.button(self, "", func() -> void: begin_pressed.emit())
	_begin_btn.custom_minimum_size.y = 44


func refresh() -> void:
	refresh_roads()
	var content := run.content
	for child in _build_list.get_children():
		child.queue_free()
	var types := content.buildings.keys()
	for type: String in types:
		var def: Dictionary = content.buildings[type]
		var cost := PackedStringArray()
		for r: String in def["cost"]:
			cost.append("%d %s" % [def["cost"][r], r])
		var owned := run.world.count_buildings(type, false)
		var btn := Button.new()
		btn.text = "%s  (%s)%s" % [def["name"], ", ".join(cost), "  [%d/%d]" % [owned, def["max"]] if def.has("max") else ("  [%d]" % owned if owned > 0 else "")]
		btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [def["text"], def["work"]]
		var blocked := _build_blocker(def)
		if blocked != "":
			btn.tooltip_text += "\n" + blocked
		btn.disabled = not run.can_build(type)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_act.bind(run.build.bind(type)))
		_build_list.add_child(btn)
		UiKit.note(_build_list, def["text"] + (" " + blocked if blocked != "" else ""), 11)
		var problems := Tooltips.warnings(run, type)
		if not problems.is_empty():
			btn.tooltip_text += "\n" + "\n".join(PackedStringArray(problems))
			if owned > 0:
				UiKit.note(_build_list, " ".join(PackedStringArray(problems)), 11, Color("#ffb060"))
	var pending := run.world.buildings.filter(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0).size()
	if pending > 0 and run.count_role("craftsperson") == 0:
		UiKit.note(_build_list, "Nobody can raise buildings yet: pick a craftsperson at dawn.", 0, Color("#e0a050"))

	_refresh_bronze()
	_refresh_prices()
	var counts := run.wave_counts()
	var ids := counts.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s x%d" % [content.enemies[id]["name"], counts[id]])
	_wave_label.text = "[b]Night %d attack[/b] from the [color=#ff7060]%s[/color]:\n%s" % [
		content.int_num("days_per_round"), " and ".join(run.world.side_names()), ", ".join(parts)]
	_begin_btn.text = "Begin round %d" % run.round_number


## The road buttons: stake a road (then finish or cancel it), or pull up the last one.
func refresh_roads() -> void:
	for child in _road_box.get_children():
		child.queue_free()
	var town := run.world.town
	if arena != null and arena.staking:
		var points := arena.stake_points.size()
		var what := "palisade" if arena.staking_wall else "road"
		var finish := UiKit.button(_road_box, "Finish %s (%d waypoints)" % [what, points], _finish_road)
		finish.disabled = not arena.preview_ok()
		UiKit.button(_road_box, "Cancel", func() -> void:
			arena.stop_staking()
			changed.emit())
		if arena.staking_wall:
			UiKit.note(_road_box, "Click the map to add corners, right-click to drop the last one. A road staked across it makes a gate.", 11, Color("#ffd27a"))
		else:
			UiKit.note(_road_box, "Click the map to add waypoints (the hearth is a good start), right-click to drop the last one.", 11, Color("#ffd27a"))
		return
	var stake := UiKit.button(_road_box, "Stake a road", func() -> void:
		if arena != null:
			arena.start_staking(false)
		refresh_roads())
	stake.disabled = arena == null
	var undo := UiKit.button(_road_box, "Pull up the last road's stakes", _act.bind(run.unstake_road))
	undo.disabled = town.roads.is_empty()
	var stake_wall := UiKit.button(_road_box, "Stake a palisade", func() -> void:
		if arena != null:
			arena.start_staking(true)
		refresh_roads())
	stake_wall.disabled = arena == null
	var undo_wall := UiKit.button(_road_box, "Pull up the last palisade", _act.bind(run.unstake_wall))
	undo_wall.disabled = town.walls.is_empty()
	if not town.walls.is_empty():
		var wc := town.wall_counts()
		UiKit.note(_road_box, "Palisade: %d of %d paces standing, %d gates." % [wc["standing"], wc["staked"], wc["gates"]], 11)
	var paved := town.paved_counts()
	var parts := PackedStringArray()
	for id: String in paved:
		parts.append("%d paces of %s" % [paved[id], run.content.town["roads"][id]["name"].to_lower()])
	if not town.roads.is_empty() or not parts.is_empty():
		UiKit.note(_road_box, "Staked: %d paces. Paved: %s." % [town.staked_count(), ", ".join(parts) if not parts.is_empty() else "none yet"], 11)
	if not town.roads.is_empty() and not town.can_pave():
		UiKit.note(_road_box, "Nobody paves roads yet: build a %s." % town.paver_name(), 11, Color("#ffb060"))


func _finish_road() -> void:
	if arena == null:
		return
	if arena.staking_wall:
		run.stake_wall(arena.stake_points)
	else:
		run.stake_road(arena.stake_points)
	arena.stop_staking()
	changed.emit()


## Runs a choice on the run, then asks the screen to refresh.
func _act(choice: Callable) -> void:
	choice.call()
	changed.emit()


## Why a building can't be ordered yet, beyond its cost ("" if nothing).
func _build_blocker(def: Dictionary) -> String:
	var content := run.content
	var out := PackedStringArray()
	var needs: String = def.get("requires", "")
	if needs != "" and run.world.count_buildings(needs, false) == 0:
		out.append("Needs a %s first." % content.buildings[needs]["name"].to_lower())
	if not content.age_reached(run.age, def.get("age", "")):
		out.append("Needs the %s (raise the Bronze moot)." % content.age_name(def["age"]).to_lower())
	if run.population() < int(def.get("min_people", 0)):
		out.append("Needs %d people (you have %d)." % [def["min_people"], run.population()])
	if def.has("ages_up") and content.age_reached(run.age, def["ages_up"]):
		out.append("Already raised.")
	return " ".join(out)


## Bronze-age choices while building: tool sets for townsfolk and the southern caravan.
func _refresh_bronze() -> void:
	var content := run.content
	if not content.age_reached(run.age, "bronze"):
		return
	UiKit.heading(_build_list, "Bronze tool sets (once each)")
	UiKit.note(_build_list, "Bronze ingots: %d. Every ingot here is one the bronzesmith can't turn into hero gear." % run.stock["bronze"])
	for id: String in content.ages["tools"]:
		var def: Dictionary = content.ages["tools"][id]
		var cost := PackedStringArray()
		for r: String in def["cost"]:
			cost.append("%d %s" % [def["cost"][r], r])
		var btn := UiKit.button(_build_list, "%s  (%s)%s" % [def["name"], ", ".join(cost), "  [owned]" if run.tools.has(id) else ""],
			_act.bind(run.buy_tools.bind(id)))
		btn.tooltip_text = def["text"]
		btn.disabled = not run.can_buy_tools(id)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if run.trader_stock.is_empty():
		return
	var trader: Dictionary = content.ages["trader"]
	UiKit.heading(_build_list, trader["name"])
	UiKit.note(_build_list, trader["text"])
	for good: String in run.trader_stock:
		var btn := UiKit.button(_build_list, "Buy 1 %s for %d shells  [%d left]" % [good, run.trader_price(good), run.trader_stock[good]],
			_act.bind(run.trade.bind(good)))
		btn.disabled = not run.can_trade(good)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT


## Cheap / Fair / Dear buttons for each stall kind you have ordered.
func _refresh_prices() -> void:
	var content := run.content
	for child in _price_box.get_children():
		child.queue_free()
	var kinds: Array = run.prices.keys()
	kinds.sort()
	var any := false
	for kind: String in kinds:
		if not run.world.buildings.any(func(b: Dictionary) -> bool:
				return content.buildings[b["type"]].get("stall", {}).get("sells", "") == kind):
			continue
		if not any:
			UiKit.heading(_price_box, "Stall prices this round")
			UiKit.note(_price_box, "Cheap makes heroes stronger now. Dear brings in more shells, but greedy heroes won't pay it.")
			any = true
		var row := HBoxContainer.new()
		_price_box.add_child(row)
		var label := Label.new()
		label.text = content.market["stall_names"][kind]
		label.custom_minimum_size.x = 90
		row.add_child(label)
		var group := ButtonGroup.new()
		for level: String in PRICE_LEVELS:
			var b := Button.new()
			b.text = "%s x%s" % [level.capitalize(), str(content.market["price_levels"][level])]
			b.toggle_mode = true
			b.button_group = group
			b.button_pressed = run.prices[kind] == level
			b.pressed.connect(_act.bind(run.set_price.bind(kind, level)))
			row.add_child(b)
