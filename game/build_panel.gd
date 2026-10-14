class_name BuildPanel
extends VBoxContainer
## The build-phase panel on the left: bronze tool sets and the caravan, how the town's paths are
## wearing in, the warned attack with both sides' power levels, and the Begin round button. The
## building cards themselves are a heads-up hand over the map (BuildHandView).
## Every choice goes through RunState; `changed` asks the screen to refresh.

signal changed
signal begin_pressed

var run: RunState
var _road_box: VBoxContainer
var _build_list: VBoxContainer
var _wave_label: RichTextLabel
var _begin_btn: Button


func _init() -> void:
	UiKit.heading(self, "Build")
	UiKit.note(self, "Order buildings from the cards along the bottom of the map. Each finds its own plot and craftspeople raise it during the days. Unused cards are gone at the end of the round.")
	_build_list = VBoxContainer.new()
	add_child(_build_list)
	add_child(HSeparator.new())
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
	var pending := run.world.buildings.filter(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0).size()
	if pending > 0 and run.count_role("craftsperson") == 0:
		UiKit.note(_build_list, "Nobody can raise buildings yet: pick a craftsperson at dawn.", 0, Color("#e0a050"))
	_refresh_bronze()
	var counts := run.waves.counts()
	var ids := counts.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s x%d" % [content.enemies[id]["name"], counts[id]])
	var town := roundi(float(Power.town(run.world)["total"]))
	var attack := roundi(Power.wave(content, run.next_wave))
	var text := "[b]Night %d attack[/b] from the [color=#ff7060]%s[/color]:\n%s\n[b]Power:[/b] your town %d vs the attack %d" % [
		content.int_num("days_per_round"), " and ".join(run.world.side_names()), ", ".join(parts), town, attack]
	if run.wave_eased > 0:
		text += "\n[color=#ffd28a]The warband holds back %d raider%s: your town looks too weak to be worth them all.[/color]" % [
			run.wave_eased, "" if run.wave_eased == 1 else "s"]
	_wave_label.text = text
	_begin_btn.text = "Begin round %d" % run.round_number


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
static func build_blocker(r: RunState, type: String) -> String:
	var content := r.content
	var def: Dictionary = content.buildings[type]
	var out := PackedStringArray()
	var needs: String = def.get("requires", "")
	if needs != "" and r.world.count_buildings(needs, false) == 0:
		out.append("Needs a %s first." % content.buildings[needs]["name"].to_lower())
	if not content.age_reached(r.age, def.get("age", "")):
		out.append("Needs the %s (raise the %s)." % [content.age_name(def["age"]).to_lower(), content.age_builder_name(def["age"])])
	if r.population() < int(def.get("min_people", 0)):
		out.append("Needs %d people (you have %d)." % [def["min_people"], r.population()])
	if def.has("ages_up") and content.age_reached(r.age, def["ages_up"]):
		out.append("Already raised.")
	if def.has("gate_hp") and out.is_empty() and r.world.town.choose_plot(type) < 0:
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
