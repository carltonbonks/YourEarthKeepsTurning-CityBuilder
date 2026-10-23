class_name BuildHandView
extends PanelContainer
## The round's building cards (run.hand) as a heads-up hand along the bottom of the map, split into
## sections with plain dividers so it's clear where each card comes from: Core (homes and food, always
## on offer), Your blueprints (buildings and rows drafted this run), Upgrades (the ageing-up card and
## tool sets, once there are any) and Trading (the caravan's trade cards, once it comes). While a draft is
## left, the blueprint offers (each says what it adds to the dawn picks), the offer to clear the next ring
## once the town is nearly full, and the reroll sit apart in
## the DraftPopup window over the map. A card the town needs says why on a gold strip at the top
## ("Food runs out in 2 days"); a card the town can't take says why on a red strip at the bottom
## ("Need 3 more wood"). Costs show red where the town is short. Shown only while building.
## Every choice goes through run.hand; `changed` asks the screen to refresh. Hovering a building
## card sends `previewing` with its type (and "" on leaving), so the map can blink the plot it would take.
## The Begin round button sits at the hand's right end, outside the scrolling cards, so it is always in
## the same place and never covered.

signal changed
signal previewing(type: String)
signal begin_pressed

const RECOMMEND_COLOR := UiKit.RECOMMEND_COLOR
const CARD_SIZE := Vector2(150, 132)
const BASIC_SIZE := Vector2(118, 132)
const ROW_SIZE := Vector2(176, 132)
const ROW_BORDER := Color("#9ec27a")
const RING_BORDER := Color("#c9a27a")
## Each section's colour: its heading, its edge and a faint tint behind its cards.
const CORE_COLOR := Color("#c8ccd4")
const BLUEPRINT_COLOR := Color("#ffd28a")
const UPGRADE_COLOR := Color("#8fb8e8")
const TRADE_COLOR := Color("#c0a060")

var run: RunState
## The window the blueprint offers go in; main.gd places it over the map.
var draft: DraftPopup
var _row: HBoxContainer
var _begin: Button
## The round whose draft was last shown, so a hidden draft stays hidden until the next round's.
var _draft_round := -1


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.88)
	style.border_color = UiKit.HEADING_COLOR
	style.border_width_top = 1
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	add_child(line)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = CARD_SIZE.y + 50
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 14)
	scroll.add_child(_row)
	_begin = UiKit.primary(UiKit.button(line, "", func() -> void: begin_pressed.emit()), 18)
	_begin.custom_minimum_size = Vector2(150, 72)
	_begin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_begin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func refresh() -> void:
	previewing.emit("")
	_begin.text = "Begin round %d" % run.round_number
	for child in _row.get_children():
		child.queue_free()
	_draft_cards()
	var core := _section("Core", "Always on offer", CORE_COLOR)
	for type: String in run.hand.basics():
		core.add_child(_card(type, run.hand.need(type), "basic"))
	var mine := _section("Your blueprints", "Drafted this run", BLUEPRINT_COLOR)
	for type: String in run.hand.blueprints:
		if run.world.count_buildings(type, false) < run.building_max(type):
			mine.add_child(_card(type, run.hand.need(type), "blueprint"))
	for id: String in run.hand.row_blueprints:
		mine.add_child(_row_card(id, run.hand.row_need(id), false))
	if mine.get_child_count() == 0:
		var empty := UiKit.note(mine, "None yet.\nDraft one from\nthe offers above.", 12)
		empty.custom_minimum_size.x = 120
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var upgrades := _section("Upgrades", "Ageing up and tool sets", UPGRADE_COLOR)
	if not run.hand.milestone.is_empty():
		upgrades.add_child(_card(run.hand.milestone["building"], "", "age"))
	_tool_cards(upgrades)
	_drop_if_empty(upgrades)
	var trading := _section("Trading", "The caravan's deals, once each this round", TRADE_COLOR)
	_caravan_cards(trading)
	_drop_if_empty(trading)


## A labelled block of cards with a coloured edge and tint, so where one kind of card ends and the
## next begins is plain at a glance. Returns the row to put its cards in.
func _section(title: String, hint: String, color: Color) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.08)
	style.border_color = color
	style.border_width_left = 4
	style.border_width_top = 2
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	_row.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := RichTextLabel.new()
	head.bbcode_enabled = true
	head.fit_content = true
	head.scroll_active = false
	head.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_font_size_override("normal_font_size", 12)
	head.add_theme_font_size_override("bold_font_size", 14)
	head.text = "[b][color=#%s]%s[/color][/b]  [color=#%s]%s[/color]" % [color.to_html(false), title.to_upper(), UiKit.HINT_COLOR.to_html(false), hint]
	box.add_child(head)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	box.add_child(cards)
	return cards


func _drop_if_empty(cards: HBoxContainer) -> void:
	if cards.get_child_count() == 0:
		var panel := cards.get_parent().get_parent()
		_row.remove_child(panel)
		panel.queue_free()


## The draft goes in its own window over the map, so the run's weightiest build choice stands apart
## from the cards the town orders from. A new round's draft opens unfolded; within a round the window
## stays as the player left it.
func _draft_cards() -> void:
	if draft == null:
		return
	# Taken out at once, not at the end of the frame, so the window shrinks to the new offers.
	for child in draft.cards.get_children():
		draft.cards.remove_child(child)
		child.queue_free()
	if run.hand.picks <= 0 or (run.hand.cards.is_empty() and run.hand.rows.is_empty() and not run.hand.ring_offer() and run.hand.upgrade_offers.is_empty()):
		draft.visible = false
		return
	draft.set_title("Draft %d blueprints" % run.hand.picks if run.hand.picks > 1 else "Draft a blueprint", pool_line(run))
	for card: Dictionary in run.hand.cards:
		draft.cards.add_child(_card(card["building"], card["need"], "draft"))
	for card: Dictionary in run.hand.rows:
		draft.cards.add_child(_row_card(card["row"], card["need"], true))
	if run.hand.ring_offer():
		draft.cards.add_child(_ring_card())
	for card: Dictionary in run.hand.upgrade_offers:
		draft.cards.add_child(_upgrade_card(card["upgrade"]))
	var redraw := UiKit.secondary(Button.new(), 13)
	redraw.text = "Reroll\n%d shells" % run.hand.redraw_cost() if run.hand.redraws == 0 else "Rerolled\nthis round"
	redraw.custom_minimum_size = Vector2(86, CARD_SIZE.y)
	redraw.disabled = not run.hand.can_redraw()
	redraw.tooltip_text = "Once a round: swap these offers for a fresh draw."
	redraw.pressed.connect(_act.bind(run.hand.redraw))
	draft.cards.add_child(redraw)
	if _draft_round != run.round_number:
		_draft_round = run.round_number
		draft.set_collapsed(false)
	draft.open()


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
	if int(def.get("effects", {}).get("pick_bonus", 0)) > 0:
		return "Dawn: %d more card to pick from" % int(def["effects"]["pick_bonus"])
	if def.has("hounds"):
		return "Dawn: hounds for %d heroes" % int(def["hounds"]["heroes"])
	if def.has("duels"):
		return "Dawn: bold heroes spar"
	if def.has("workshop") and not content.recipes_for(type).is_empty():
		return "Dawn: its crafters can become masters"
	return ""


## What drafting a row gives, from what the town already has: "You have Knapper. Adds Arms stall."
## The draft title's hover: which blueprints this run can offer at all.
static func pool_line(r: RunState) -> String:
	var all := 0
	for type: String in r.content.buildings:
		var def: Dictionary = r.content.buildings[type]
		if not def.get("basic", false) and not def.has("ages_up"):
			all += 1
	var pool := r.hand.pool()
	var names: Array[String] = []
	for type in pool:
		names.append(r.content.buildings[type]["name"])
	return "This run's blueprints: %d of %d buildings can come up in the draft. Another run deals a different set.\n%s" \
		% [pool.size(), all, ", ".join(names)]


static func row_offer_line(r: RunState, id: String) -> String:
	var names := func(types: Array) -> String:
		return " and ".join(PackedStringArray(types.map(func(t: String) -> String: return r.content.buildings[t]["name"])))
	var have := r.hand.row_have(id)
	var adds := r.hand.row_adds(id)
	if adds.is_empty():
		return "You have both."
	return "You have %s. Adds %s." % [names.call([have]), names.call(adds)]


## The rows drafting this building would open ("" if none): "Opens a row: Blade row".
static func row_hint(r: RunState, type: String) -> String:
	var ids := r.hand.rows_opened_by(type)
	if ids.is_empty():
		return ""
	return "Opens a row: " + ", ".join(PackedStringArray(ids.map(func(id: String) -> String: return r.content.combos[id]["name"])))


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
		"runners":
			return "%d heroes could send for supplies" % run.living_heroes().size()
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
	var hint := row_hint(run, type) if kind == "draft" else ""
	var footer := (dawn if dawn != "" else hint) if kind == "draft" else ("You have %d" % owned if owned > 0 else "")
	var rarity := run.content.rarity_of("building", type)
	var btn := UiKit.card(top, def["name"], UiKit.cost_text(run.stock, def["cost"]), def["text"],
		footer, BASIC_SIZE if kind == "basic" else CARD_SIZE, border, why != "",
		UiKit.HEADING_COLOR if kind == "age" else (Color.WHITE if rarity == "white" else run.content.rarity_color(rarity)))
	btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [def["text"], def["work"]]
	if rarity != "white":
		btn.tooltip_text = "%s blueprint (rarer ones come up less often).\n" % run.content.rarity_tier(rarity)["name"] + btn.tooltip_text
	if dawn != "":
		btn.tooltip_text += "\n" + dawn + "."
	if kind == "draft":
		btn.tooltip_text = "Draft it: you can order it, paying its cost, for the rest of the run.\n" + btn.tooltip_text
		if hint != "":
			btn.tooltip_text += "\n%s: a later draft can add its partner, side by side for a bonus." % hint
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


## An upgrade offer: changes a building the town has for the rest of the run, instead of a new blueprint.
func _upgrade_card(id: String) -> Button:
	var up: Dictionary = run.content.upgrades[id]
	var rarity: String = up.get("rarity", "white")
	var building: String = run.content.buildings[up["building"]]["name"]
	var btn := UiKit.card("Upgrade your %s" % building.to_lower(), up["name"], "", up["text"], "Instead of a new blueprint",
		CARD_SIZE, UiKit.HEADING_COLOR, false, Color.WHITE if rarity == "white" else run.content.rarity_color(rarity))
	btn.tooltip_text = "Draft it: every %s, built or still to come, is changed for the rest of the run.\n%s" % [building.to_lower(), up["text"]]
	if rarity != "white":
		btn.tooltip_text = "%s upgrade (rarer ones come up less often).\n" % run.content.rarity_tier(rarity)["name"] + btn.tooltip_text
	btn.disabled = not run.hand.can_draft_upgrade(id)
	btn.pressed.connect(_act.bind(run.hand.draft_upgrade.bind(id)))
	return btn


## A row card: two buildings ordered together, side by side, for less, and the bonus they make together.
func _row_card(id: String, need: String, drafting: bool) -> Button:
	var content := run.content
	var row: Dictionary = content.combos[id]
	var a: String = content.buildings[row["building"]]["name"]
	var b: String = content.buildings[row["partner"]]["name"]
	var why := recommendation(row["building"] if run.hand.need(row["building"]) == need else row["partner"], need)
	var cost := run.row_cost(id)
	var body := "%s + %s, side by side. %s" % [a, b, row["text"]]
	if drafting:
		body = "%s %s" % [row_offer_line(run, id), row["text"]]
	var btn := UiKit.card(why if why != "" else ("Draft a row" if drafting else "Your row"), row["name"], UiKit.cost_text(run.stock, cost),
		body, "", ROW_SIZE, RECOMMEND_COLOR if why != "" else ROW_BORDER,
		why != "", ROW_BORDER)
	btn.tooltip_text = "%s and %s go up together in one cluster, a fifth cheaper than ordering both.\n%s\nOnly buildings ordered as a row make this bonus." % [
		a, b, row["text"]]
	if drafting:
		btn.tooltip_text = "Draft it: you can order this row for the rest of the run. %s\n" % row_offer_line(run, id) + btn.tooltip_text
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


## The offer to clear the next ring of plots, in place of a building, once the open rings are nearly full.
func _ring_card() -> Button:
	var cost := run.ring_cost()
	var full := roundi(run.world.town.fullness() * 100.0)
	var btn := UiKit.card("Room to grow: %d%% full" % full, "Clear a new ring", UiKit.cost_text(run.stock, cost),
		"Opens the next ring of plots round the town for good. A bigger town has a longer edge to hold.",
		"Ring %d of %d" % [run.rings_open + 1, run.content.town["rings"].size()], CARD_SIZE, RECOMMEND_COLOR, true, RING_BORDER)
	btn.tooltip_text = "Takes this draft instead of a new building: pay to clear the next ring, and buildings can stand there from now on.\nAgeing up also opens a ring, for free."
	btn.disabled = not run.hand.can_clear_ring()
	UiKit.fade_if_disabled(btn, UiKit.shortfall(run.stock, cost))
	btn.pressed.connect(_act.bind(run.hand.clear_ring))
	return btn


## Tool sets, from the bronze age: a lasting upgrade for one townsfolk group, once each. They cost
## goods and shells, like any card.
func _tool_cards(parent: HBoxContainer) -> void:
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
		parent.add_child(btn)


## The southern caravan's trade cards (run.caravan): each deal once a round, its border and name in its rarity's
## colour, a gold strip when the town wants it, a red one when it can't be taken.
func _caravan_cards(parent: HBoxContainer) -> void:
	for i in run.caravan.offers.size():
		parent.add_child(_deal_card(i))


func _deal_card(index: int) -> Button:
	var content := run.content
	var offer: Dictionary = run.caravan.offers[index]
	var id: String = offer["deal"]
	var def := run.caravan.deal(id)
	var rarity := content.rarity_of("deal", id)
	var colour := content.rarity_color(rarity)
	var top: String = offer["need"] if offer["need"] != "" else "Caravan · %s" % content.rarity_tier(rarity)["name"]
	# Spelled out as a trade: what you hand over, then what you get back.
	var terms := "[color=#9da2ab]You pay[/color] %s\n[color=#9da2ab]You get[/color] [color=#a8d890]%s[/color]" % [
		UiKit.cost_text(run.stock, def["give"]), deal_brings(run, id)]
	var btn := UiKit.card(top, def["name"], terms, def["text"],
		"", CARD_SIZE, colour, offer["need"] != "", Color.WHITE if rarity == "white" else colour)
	var pays := ", ".join(PackedStringArray(def["give"].keys().map(func(g: String) -> String: return "%d %s" % [def["give"][g], g])))
	btn.tooltip_text = "%s deal from the %s (rarer deals come up less often).\n%s\nYou pay: %s.\nYou get: %s.\nOnce this round." % [
		content.rarity_tier(rarity)["name"], content.trades["name"].to_lower(), def["text"], pays, deal_brings(run, id)]
	btn.disabled = not run.caravan.can_take(index)
	var blocked := run.caravan.blocker(index)
	UiKit.fade_if_disabled(btn, blocked if blocked != "" else UiKit.shortfall(run.stock, def["give"]))
	btn.pressed.connect(_act.bind(run.caravan.take.bind(index)))
	return btn


## What a deal brings, in words: "+4 tin", "2 warriors join", "every hero's weapon +1 tier", "a relic".
static func deal_brings(r: RunState, id: String) -> String:
	var def := r.caravan.deal(id)
	var parts: PackedStringArray = []
	var got := r.caravan.gets(id)
	for good: String in got:
		parts.append("+%d %s" % [got[good], good])
	for role: String in def.get("folk", {}):
		var n := int(def["folk"][role])
		parts.append("%d %s%s join" % [n, r.content.townsfolk[role]["name"].to_lower(), "s" if n > 1 else ""])
	if int(def.get("smith", 0)) > 0:
		parts.append("hero weapons +%d tier%s" % [def["smith"], "s" if int(def["smith"]) > 1 else ""])
	if int(def.get("relic", 0)) > 0:
		parts.append("a relic")
	return ", ".join(parts)


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
