class_name BuildPanel
extends VBoxContainer
## The build-phase panel on the left: the round's building cards (run.hand), bronze tool sets and the
## caravan, stall prices, how the town's paths are wearing in, the warned attack and the Begin round button.
## Every choice goes through RunState; `changed` asks the screen to refresh.

signal changed
signal begin_pressed

const PRICE_LEVELS := ["cheap", "fair", "dear"]

var run: RunState
var _road_box: VBoxContainer
var _build_list: VBoxContainer
var _price_box: VBoxContainer
var _wave_label: RichTextLabel
var _begin_btn: Button


func _init() -> void:
	UiKit.heading(self, "Building cards")
	UiKit.note(self, "Order from this round's cards. Each building finds its own plot and craftspeople raise it during the days. Unused cards are gone at the end of the round.")
	_build_list = VBoxContainer.new()
	add_child(_build_list)
	add_child(HSeparator.new())
	_price_box = VBoxContainer.new()
	add_child(_price_box)
	_road_box = VBoxContainer.new()
	add_child(_road_box)
	_wave_label = UiKit.rich(self, 0)
	_wave_label.fit_content = true
	_begin_btn = UiKit.button(self, "", func() -> void: begin_pressed.emit())
	_begin_btn.custom_minimum_size.y = 44


func refresh() -> void:
	_refresh_paths()
	var content := run.content
	for child in _build_list.get_children():
		child.queue_free()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_build_list.add_child(grid)
	for card: Dictionary in run.hand.cards:
		grid.add_child(_card_button(card, false))
	if run.hand.cards.is_empty():
		UiKit.note(_build_list, "No cards left this round.", 12)
	if not run.hand.milestone.is_empty():
		_build_list.add_child(_card_button(run.hand.milestone, true))
	var redraw := UiKit.button(_build_list, "Redraw unused cards (%d shells)%s" % [run.hand.redraw_cost(),
		"" if run.hand.redraws == 0 else ": used"], _act.bind(run.hand.redraw))
	redraw.disabled = not run.hand.can_redraw()
	redraw.tooltip_text = "Once a round: the cards you haven't used are swapped for a fresh deal."
	var pending := run.world.buildings.filter(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0).size()
	if pending > 0 and run.count_role("craftsperson") == 0:
		UiKit.note(_build_list, "Nobody can raise buildings yet: pick a craftsperson at dawn.", 0, Color("#e0a050"))

	_refresh_bronze()
	_refresh_prices()
	var counts := run.waves.counts()
	var ids := counts.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s x%d" % [content.enemies[id]["name"], counts[id]])
	_wave_label.text = "[b]Night %d attack[/b] from the [color=#ff7060]%s[/color]:\n%s" % [
		content.int_num("days_per_round"), " and ".join(run.world.side_names()), ", ".join(parts)]
	_begin_btn.text = "Begin round %d" % run.round_number


const NEED_TEXT := {
	"housing": "Beds are nearly full",
	"food": "Food is running short",
	"beds": "Heroes need beds",
	"supply": "A stall has nothing to sell",
	"stall": "Your workshop needs a stall",
}


## One building card: name, cost, why the town wants it; the description and warnings on hover.
func _card_button(card: Dictionary, age_up: bool) -> Button:
	var content := run.content
	var type: String = card["building"]
	var def: Dictionary = content.buildings[type]
	var cost := PackedStringArray()
	for r: String in def["cost"]:
		cost.append("%d %s" % [def["cost"][r], r])
	var owned := run.world.count_buildings(type, false)
	var lines := PackedStringArray()
	lines.append(("RAISE: " if age_up else "") + def["name"])
	lines.append(", ".join(cost))
	var why: String = NEED_TEXT.get(card["need"], "")
	if why == "" and owned == 0 and not age_up:
		why = "New"
	elif why == "" and owned > 0:
		why = "You have %d" % owned
	lines.append(why)
	var btn := Button.new()
	btn.text = "\n".join(lines)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 72)
	if card["need"] != "":
		btn.add_theme_color_override("font_color", Color("#ffd28a"))
	btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [def["text"], def["work"]]
	var blocked := _build_blocker(type)
	if blocked != "":
		btn.tooltip_text += "\n" + blocked
	var problems := Tooltips.warnings(run, type)
	if not problems.is_empty():
		btn.tooltip_text += "\n" + "\n".join(PackedStringArray(problems))
	btn.disabled = not run.hand.can_order(type)
	btn.pressed.connect(_act.bind(run.hand.order.bind(type)))
	return btn


## How far the desire paths have worn in, and what has been paved.
func _refresh_paths() -> void:
	for child in _road_box.get_children():
		child.queue_free()
	var town := run.world.town
	var pathing := run.world.pathing
	var parts := PackedStringArray()
	parts.append("%d paces of trail" % pathing.count_ground(Pathing.TRAIL))
	parts.append("%d of worn path" % pathing.count_ground(Pathing.PATH))
	var paved := town.paved_counts()
	for id: String in paved:
		parts.append("%d of %s" % [paved[id], run.content.town["roads"][id]["name"].to_lower()])
	UiKit.note(_road_box, "Paths: " + ", ".join(parts) + ".", 11)
	var gates := town.gate_counts()
	if gates["built"] > 0:
		UiKit.note(_road_box, "Gates: %d." % gates["built"], 11)
	if pathing.count_ground(Pathing.PATH) > 0 and not town.can_pave():
		UiKit.note(_road_box, "Nobody paves the paths yet: build a %s." % town.paver_name(), 11, Color("#ffb060"))


## Runs a choice on the run, then asks the screen to refresh.
func _act(choice: Callable) -> void:
	choice.call()
	changed.emit()


## Why a building can't be ordered yet, beyond its cost ("" if nothing).
func _build_blocker(type: String) -> String:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	var out := PackedStringArray()
	var needs: String = def.get("requires", "")
	if needs != "" and run.world.count_buildings(needs, false) == 0:
		out.append("Needs a %s first." % content.buildings[needs]["name"].to_lower())
	if not content.age_reached(run.age, def.get("age", "")):
		out.append("Needs the %s (raise the %s)." % [content.age_name(def["age"]).to_lower(), content.age_builder_name(def["age"])])
	if run.population() < int(def.get("min_people", 0)):
		out.append("Needs %d people (you have %d)." % [def["min_people"], run.population()])
	if def.has("ages_up") and content.age_reached(run.age, def["ages_up"]):
		out.append("Already raised.")
	if def.has("gate_hp") and out.is_empty() and run.world.town.choose_plot(type) < 0:
		out.append("Needs a free plot beside a building.")
	return " ".join(out)


## Later-age choices while building: tool sets for townsfolk groups and the southern caravan.
func _refresh_bronze() -> void:
	var content := run.content
	if not content.age_reached(run.age, "bronze"):
		return
	UiKit.heading(_build_list, "Tool sets (once each)")
	UiKit.note(_build_list, "Bronze ingots: %d. Every ingot here is one the bronzesmith can't turn into hero gear." % run.stock["bronze"])
	if content.age_reached(run.age, "medieval"):
		UiKit.note(_build_list, "Iron: %d, steel: %d. Every bloom here is one the blacksmith can't forge for heroes." % [run.stock["iron"], run.stock["steel"]])
	for id: String in content.ages["tools"]:
		var def: Dictionary = content.ages["tools"][id]
		if not content.age_reached(run.age, def.get("age", "")):
			continue
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
