class_name BuildHandView
extends PanelContainer
## The round's building cards (run.hand) as a heads-up hand along the bottom of the map, like the
## dawn pick: basics (homes and food, always on offer), the dealt cards, the ageing-up card, tool sets
## and the caravan in later ages, and the redraw. A card the town needs says why at the top ("Recommended: ..."). Shown only while building.
## Every choice goes through run.hand; `changed` asks the screen to refresh.

signal changed

const RECOMMEND_COLOR := UiKit.RECOMMEND_COLOR
const CARD_SIZE := Vector2(150, 132)
const BASIC_SIZE := Vector2(118, 132)

var run: RunState
var _row: HBoxContainer


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.88)
	style.border_color = UiKit.HEADING_COLOR
	style.border_width_top = 1
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = CARD_SIZE.y + 14
	add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	scroll.add_child(_row)


func refresh() -> void:
	for child in _row.get_children():
		child.queue_free()
	for type: String in run.hand.basics():
		_row.add_child(_card(type, run.hand.need(type), "basic"))
	_row.add_child(VSeparator.new())
	for card: Dictionary in run.hand.cards:
		_row.add_child(_card(card["building"], card["need"], "card"))
	if not run.hand.milestone.is_empty():
		_row.add_child(_card(run.hand.milestone["building"], "", "age"))
	_age_cards()
	if run.hand.cards.is_empty() and run.hand.milestone.is_empty():
		var none := UiKit.note(_row, "No cards left this round.", 12)
		none.custom_minimum_size.x = 120
	var redraw := Button.new()
	redraw.text = "Redraw\nunused\n(%d shells)%s" % [run.hand.redraw_cost(), "" if run.hand.redraws == 0 else "\nused"]
	redraw.custom_minimum_size = Vector2(86, CARD_SIZE.y)
	redraw.focus_mode = Control.FOCUS_NONE
	redraw.disabled = not run.hand.can_redraw()
	redraw.tooltip_text = "Once a round: the cards you haven't used are swapped for a fresh deal."
	redraw.pressed.connect(_act.bind(run.hand.redraw))
	_row.add_child(redraw)


## Why the town wants this building, with the numbers ("" if nothing in particular).
func recommendation(type: String, need: String) -> String:
	var content := run.content
	match need:
		"housing":
			var spare := run.housing() - run.population()
			return "Room for %d more" % spare if spare > 0 else "Every bed is full"
		"food":
			var per_day := maxi(1, run.food_needed_today() - run.food_grown_daily())
			var days := int(float(run.stock["food"]) / per_day)
			return "Food runs out in %d day%s" % [days, "" if days == 1 else "s"] if days > 0 else "Food runs out today"
		"beds":
			var short := -run.hand.free_beds()
			return "%d hero%s without a bed" % [short, "" if short == 1 else "es"] if short > 0 else "Hero beds are full"
		"supply":
			return "A stall has nothing to sell"
		"regrow":
			var tag: String = content.buildings[type]["tends"]["tag"]
			return "The wild plants are %d%% picked over" % roundi(100.0 * (1.0 - run.world.nodes_fullness(tag)))
		"fuel":
			var nights := int(float(run.stock["fuel"]) / maxi(1, run.fuel_needed_tonight()))
			return "Fuel for %d night%s" % [nights, "" if nights == 1 else "s"] if nights > 0 else "Fuel runs out tonight"
		"stall":
			return "Your workshop needs a stall"
		"age":
			return "New in the %s" % content.age_name(content.buildings[type].get("age", run.age)).to_lower()
	return ""


func _card(type: String, need: String, kind: String) -> Button:
	var def: Dictionary = run.content.buildings[type]
	var owned := run.world.count_buildings(type, false)
	var why := recommendation(type, need)
	var top := ("Recommended: " + why) if why != "" else ("Always on offer" if kind == "basic" else ("Ageing up" if kind == "age" else ""))
	var border := RECOMMEND_COLOR if why != "" else (UiKit.HEADING_COLOR if kind == "age" else UiKit.CARD_BORDER)
	var btn := UiKit.card(top, ("RAISE: " if kind == "age" else "") + def["name"], _cost_text(def["cost"]), def["text"],
		"You have %d" % owned if owned > 0 else "", BASIC_SIZE if kind == "basic" else CARD_SIZE, border, why != "",
		UiKit.HEADING_COLOR if kind == "age" else Color.WHITE)
	btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [def["text"], def["work"]]
	var blocked := build_blocker(run, type)
	if blocked != "":
		btn.tooltip_text += "\n" + blocked
	var problems := Tooltips.warnings(run, type)
	if not problems.is_empty():
		btn.tooltip_text += "\n" + "\n".join(PackedStringArray(problems))
	btn.disabled = not run.hand.can_order(type)
	UiKit.fade_if_disabled(btn)
	btn.pressed.connect(_act.bind(run.hand.order.bind(type)))
	return btn


## Later-age cards beside the buildings: tool sets (a lasting upgrade for one townsfolk group, once
## each) and whatever the southern caravan has left. They cost goods and shells, like any card.
func _age_cards() -> void:
	var content := run.content
	if not content.age_reached(run.age, "bronze"):
		return
	var ids: Array = content.ages["tools"].keys()
	for id: String in ids:
		var def: Dictionary = content.ages["tools"][id]
		if run.tools.has(id) or not content.age_reached(run.age, def.get("age", "")):
			continue
		var btn := UiKit.card("Tool set for %ss" % content.townsfolk[def["role"]]["name"].to_lower(), def["name"],
			_cost_text(def["cost"]), def["text"], "", CARD_SIZE, Color("#8fa0b8"))
		btn.tooltip_text = "%s\nOnce only. Every ingot spent here is one the smiths can't turn into hero gear.\nYou have %d bronze%s." % [
			def["text"], run.stock["bronze"], ", %d iron, %d steel" % [run.stock["iron"], run.stock["steel"]] if content.age_reached(run.age, "medieval") else ""]
		btn.disabled = not run.can_buy_tools(id)
		UiKit.fade_if_disabled(btn)
		btn.pressed.connect(_act.bind(run.buy_tools.bind(id)))
		_row.add_child(btn)
	var trader: Dictionary = content.ages["trader"]
	for good: String in run.trader_stock:
		if int(run.trader_stock[good]) <= 0:
			continue
		var btn := UiKit.card(trader["name"], "1 %s" % good, "%d shells" % run.trader_price(good), "",
			"%d left this round" % run.trader_stock[good], BASIC_SIZE, Color("#c0a060"))
		btn.tooltip_text = trader["text"]
		btn.disabled = not run.can_trade(good)
		UiKit.fade_if_disabled(btn)
		btn.pressed.connect(_act.bind(run.trade.bind(good)))
		_row.add_child(btn)


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


static func _cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for r: String in cost:
		parts.append("%d %s" % [cost[r], r])
	return ", ".join(parts)


func _act(choice: Callable) -> void:
	choice.call()
	changed.emit()
