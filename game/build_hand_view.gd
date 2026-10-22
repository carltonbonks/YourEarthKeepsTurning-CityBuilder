class_name BuildHandView
extends PanelContainer
## The round's building cards (run.hand) as a heads-up hand along the bottom of the map, like the
## dawn pick: basics (homes and food, always on offer), the town's blueprints and drafted rows, the ageing-up
## card, tool sets and the caravan in later ages, then, while a draft is left, the blueprint offers
## (each says what it adds to the dawn picks) and the reroll. A card the town needs says why on a gold strip at
## the top ("Food runs out in 2 days"); a card the town can't take says why on a red strip at the
## bottom ("Need 3 more wood"). Costs show red where the town is short. Shown only while building.
## Every choice goes through run.hand; `changed` asks the screen to refresh. Hovering a building
## card sends `previewing` with its type (and "" on leaving), so the map can blink the plot it would take.

signal changed
signal previewing(type: String)

const RECOMMEND_COLOR := UiKit.RECOMMEND_COLOR
const CARD_SIZE := Vector2(150, 132)
const BASIC_SIZE := Vector2(118, 132)
const ROW_SIZE := Vector2(176, 132)
const ROW_BORDER := Color("#9ec27a")
## Height of the buyout button under each caravan card; the card shrinks to make room.
const BUYOUT_HEIGHT := 28.0

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
	previewing.emit("")
	for child in _row.get_children():
		child.queue_free()
	_draft_cards()
	for type: String in run.hand.basics():
		_row.add_child(_card(type, run.hand.need(type), "basic"))
	_row.add_child(VSeparator.new())
	for type: String in run.hand.blueprints:
		if run.world.count_buildings(type, false) < run.building_max(type):
			_row.add_child(_card(type, run.hand.need(type), "blueprint"))
	for id: String in run.hand.row_blueprints:
		_row.add_child(_row_card(id, run.hand.row_need(id), false))
	if not run.hand.milestone.is_empty():
		_row.add_child(_card(run.hand.milestone["building"], "", "age"))
	_age_cards()


## The draft comes first, so the run's weightiest build choice is never scrolled out of sight.
func _draft_cards() -> void:
	if run.hand.picks <= 0 or (run.hand.cards.is_empty() and run.hand.rows.is_empty()):
		return
	var head := UiKit.note(_row, "Draft %d\nKept for\nthe whole run" % run.hand.picks if run.hand.picks > 1 \
		else "Draft one\nKept for\nthe whole run", 13)
	head.custom_minimum_size.x = 92
	head.add_theme_color_override("font_color", UiKit.HEADING_COLOR)
	for card: Dictionary in run.hand.cards:
		_row.add_child(_card(card["building"], card["need"], "draft"))
	for card: Dictionary in run.hand.rows:
		_row.add_child(_row_card(card["row"], card["need"], true))
	var redraw := UiKit.secondary(Button.new(), 13)
	redraw.text = "Reroll\n%d shells" % run.hand.redraw_cost() if run.hand.redraws == 0 else "Rerolled\nthis round"
	redraw.custom_minimum_size = Vector2(86, CARD_SIZE.y)
	redraw.disabled = not run.hand.can_redraw()
	redraw.tooltip_text = "Once a round: swap these offers for a fresh draw."
	redraw.pressed.connect(_act.bind(run.hand.redraw))
	_row.add_child(redraw)
	_row.add_child(VSeparator.new())


## What a building adds to the dawn picks once it stands ("" if nothing): heroes it lodges or draws,
## craftspeople it can make masters, the geomancer's spells.
static func dawn_line(r: RunState, type: String) -> String:
	var content := r.content
	var def: Dictionary = content.buildings[type]
	for id: String in content.hero_classes:
		if content.hero_classes[id].get("needs", "") == type:
			return "Dawn: %ss can arrive" % content.hero_classes[id]["name"].to_lower()
	if def.has("lodging"):
		return "Dawn: heroes can arrive" if r.world.hero_ai.count_lodgings() == 0 else "Dawn: beds for %d more heroes" % int(def["lodging"]["beds"])
	if def.get("spells", false):
		return "Dawn: spell cards"
	if def.has("workshop") and not content.recipes_for(type).is_empty():
		return "Dawn: its crafters can become masters"
	return ""


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
		"heroes":
			return "No hero lodging yet"
		"ageing":
			return "Needed to age up"
		"age":
			return "New in the %s" % content.age_name(content.buildings[type].get("age", run.age)).to_lower()
	return ""


func _card(type: String, need: String, kind: String) -> Button:
	var def: Dictionary = run.content.buildings[type]
	var owned := run.world.count_buildings(type, false)
	var why := recommendation(type, need)
	var top: String = why if why != "" else {"basic": "Always on offer", "age": "Ageing up", "blueprint": "Your blueprint"}.get(kind, "New building")
	var border := RECOMMEND_COLOR if why != "" else (UiKit.HEADING_COLOR if kind == "age" else UiKit.CARD_BORDER)
	var dawn := dawn_line(run, type)
	var footer := dawn if kind == "draft" else ("You have %d" % owned if owned > 0 else "")
	var btn := UiKit.card(top, def["name"], UiKit.cost_text(run.stock, def["cost"]), def["text"],
		footer, BASIC_SIZE if kind == "basic" else CARD_SIZE, border, why != "",
		UiKit.HEADING_COLOR if kind == "age" else Color.WHITE)
	btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [def["text"], def["work"]]
	if dawn != "":
		btn.tooltip_text += "\n" + dawn + "."
	if kind == "draft":
		btn.tooltip_text = "Draft it: you can order it, paying its cost, for the rest of the run.\n" + btn.tooltip_text
		btn.disabled = not run.hand.can_draft(type)
		btn.pressed.connect(_act.bind(run.hand.draft.bind(type)))
		btn.mouse_entered.connect(func() -> void: previewing.emit(type))
		btn.mouse_exited.connect(func() -> void: previewing.emit(""))
		return btn
	var combos := Tooltips.combo_lines(run, type)
	if not combos.is_empty():
		btn.tooltip_text += "\n" + "\n".join(PackedStringArray(combos))
	var blocked := build_blocker(run, type)
	if blocked != "":
		btn.tooltip_text += "\n" + blocked
	var problems := Tooltips.warnings(run, type)
	if not problems.is_empty():
		btn.tooltip_text += "\n" + "\n".join(PackedStringArray(problems))
	btn.disabled = not run.hand.can_order(type)
	UiKit.fade_if_disabled(btn, _why_not(blocked, def["cost"]))
	btn.pressed.connect(_act.bind(run.hand.order.bind(type)))
	btn.mouse_entered.connect(func() -> void: previewing.emit(type))
	btn.mouse_exited.connect(func() -> void: previewing.emit(""))
	return btn


## A row card: two buildings ordered together, side by side, for less, and the bonus they make together.
func _row_card(id: String, need: String, drafting: bool) -> Button:
	var content := run.content
	var row: Dictionary = content.combos[id]
	var a: String = content.buildings[row["building"]]["name"]
	var b: String = content.buildings[row["partner"]]["name"]
	var why := recommendation(row["building"] if run.hand.need(row["building"]) == need else row["partner"], need)
	var cost := run.row_cost(id)
	var btn := UiKit.card(why if why != "" else ("Draft a row" if drafting else "Your row"), row["name"], UiKit.cost_text(run.stock, cost),
		"%s + %s, side by side. %s" % [a, b, row["text"]], "", ROW_SIZE, RECOMMEND_COLOR if why != "" else ROW_BORDER,
		why != "", ROW_BORDER)
	btn.tooltip_text = "%s and %s go up together in one cluster, a fifth cheaper than ordering both.\n%s\nOnly buildings ordered as a row make this bonus." % [
		a, b, row["text"]]
	if drafting:
		btn.tooltip_text = "Draft it: you can order this row, and each of its buildings on its own, for the rest of the run.\n" + btn.tooltip_text
		btn.disabled = not run.hand.can_draft_row(id)
		btn.pressed.connect(_act.bind(run.hand.draft_row.bind(id)))
		return btn
	btn.disabled = not run.hand.can_order_row(id)
	var short := UiKit.shortfall(run.stock, cost)
	UiKit.fade_if_disabled(btn, short if short != "" else "No room for both")
	btn.pressed.connect(_act.bind(run.hand.order_row.bind(id)))
	btn.mouse_entered.connect(func() -> void: previewing.emit(row["building"]))
	btn.mouse_exited.connect(func() -> void: previewing.emit(""))
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
			UiKit.cost_text(run.stock, def["cost"]), def["text"], "", CARD_SIZE, Color("#8fa0b8"))
		btn.tooltip_text = "%s\nOnce only. Every ingot spent here is one the smiths can't turn into hero gear.\nYou have %d bronze%s." % [
			def["text"], run.stock["bronze"], ", %d iron, %d steel" % [run.stock["iron"], run.stock["steel"]] if content.age_reached(run.age, "medieval") else ""]
		btn.disabled = not run.can_buy_tools(id)
		UiKit.fade_if_disabled(btn, UiKit.shortfall(run.stock, def["cost"]))
		btn.pressed.connect(_act.bind(run.buy_tools.bind(id)))
		_row.add_child(btn)
	var trader: Dictionary = content.ages["trader"]
	for good: String in run.trader_stock:
		if int(run.trader_stock[good]) <= 0:
			continue
		# One card buys one; the buyout under it takes as many as the shells pay for.
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		var btn := UiKit.card("Caravan · %d left" % run.trader_stock[good], "1 %s" % good,
			UiKit.cost_text(run.stock, {"shells": run.trader_price(good)}), "", "", Vector2(BASIC_SIZE.x, BASIC_SIZE.y - BUYOUT_HEIGHT - 4), Color("#c0a060"))
		btn.tooltip_text = "%s\n%s\n%d left this round." % [trader["name"], trader["text"], run.trader_stock[good]]
		btn.disabled = not run.can_trade(good)
		UiKit.fade_if_disabled(btn, UiKit.shortfall(run.stock, {"shells": run.trader_price(good)}))
		btn.pressed.connect(_act.bind(run.trade.bind(good)))
		col.add_child(btn)
		var n := run.buyout_count(good)
		var all := UiKit.secondary(Button.new(), 12)
		all.text = "Buy %d · %d shells" % [n, n * run.trader_price(good)] if n > 0 else "Buyout"
		all.custom_minimum_size = Vector2(BASIC_SIZE.x, BUYOUT_HEIGHT)
		all.disabled = n == 0
		all.tooltip_text = "Buy as many %s as your shells pay for, up to all the caravan has left." % good
		all.pressed.connect(_act.bind(run.buyout.bind(good)))
		col.add_child(all)
		_row.add_child(col)


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


## The one thing in the way, for the red strip on a card the town can't order: what it lacks
## (a building, the age, people) before what it can't pay.
func _why_not(blocked: String, cost: Dictionary) -> String:
	if blocked != "":
		return blocked.get_slice(".", 0)
	var short := UiKit.shortfall(run.stock, cost)
	return short if short != "" else "Can't order more"


func _act(choice: Callable) -> void:
	choice.call()
	changed.emit()
