class_name BuildHandView
extends PanelContainer
## The round's building cards (run.hand) as a heads-up hand along the bottom of the map, split into
## sections with plain dividers so it's clear where each card comes from: Core (homes and food, always
## on offer), Your blueprints (buildings and rows drafted this run), Upgrades (the ageing-up card and
## tool sets, once there are any) and Trading (the caravan's trade cards, once it comes). While a draft is
## left, the blueprint offers (each says what it adds to the dawn picks), the offer to clear the next ring
## once the town is nearly full, and the reroll are a pick screen the player must answer before building,
## like the dawn pick: Overlays.show_draft lays it out and `fill_draft` makes its cards. Every card is a CardView. A card the town needs says why on a bone ribbon at the top
## ("Food runs out in 2 days"); a card the town can't take says why on a red strip at the bottom
## ("Need 3 more wood"). Costs show red where the town is short. Shown only while building.
## Every choice goes through run.hand; `changed` asks the screen to refresh. Hovering a building
## card sends `previewing` with its type (and "" on leaving), so the map can blink the plot it would take.
## The Begin round button sits at the hand's right end, so it is always in the same place and never
## covered. The hand never scrolls: when the cards are wider than the screen, the section hints go and
## the whole row shrinks to fit (`_fit`), and the strip gets shorter with it.

signal changed
signal previewing(type: String)
signal begin_pressed

## The height the hand keeps for its small cards (their fixed shape, CardView), so the strip doesn't jump as cards change.
const HAND_HEIGHT: float = CardView.SHAPE[CardView.Size.SMALL].y
## The row's height at full size: the cards plus each section's heading and edges.
const ROW_HEIGHT := HAND_HEIGHT + 40.0
## The row shrinks no further than this; past it the last cards are cut off at the screen's edge.
const MIN_SCALE := 0.55
## The sections share one plain look: the cards' own bands say what kind each is, and the rarity colours stay
## for the cards' frames.
const SECTION_COLOR := Color("#d8d4c8")

var run: RunState
var _row: HBoxContainer
## Holds the row and clips it; the row is scaled to its width.
var _shelf: Control
## Each section's hint ("Always on offer"), hidden first when the cards don't fit.
var _hints: Array[Label] = []
var _begin: Button


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
	# A plain Control, not a container: the strip keeps its own height instead of taking the cards' (a new
	# card measures itself tall for a frame before its width is known, CardView), and the row can be scaled.
	_shelf = Control.new()
	_shelf.clip_contents = true
	_shelf.custom_minimum_size.y = ROW_HEIGHT
	_shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shelf.resized.connect(_fit)
	line.add_child(_shelf)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 14)
	_row.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	_shelf.add_child(_row)
	_begin = UiKit.primary(UiKit.button(line, "", func() -> void: begin_pressed.emit()), 18)
	_begin.custom_minimum_size = Vector2(150, 72)
	_begin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_begin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func refresh() -> void:
	previewing.emit("")
	_begin.text = "Begin round %d" % run.round_number
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_hints.clear()
	var core := _section("Core", "Always on offer")
	for type: String in run.hand.basics():
		core.add_child(_card(type, run.hand.need(type), "basic"))
	var mine := _section("Your blueprints", "Drafted this run")
	for type: String in run.hand.blueprints:
		if run.world.count_buildings(type, false) < run.building_max(type):
			mine.add_child(_card(type, run.hand.need(type), "blueprint"))
	for id: String in run.hand.row_blueprints:
		mine.add_child(_row_card(id, run.hand.row_need(id), false))
	if mine.get_child_count() == 0:
		var empty := UiKit.note(mine, "None yet.", 12)
		empty.custom_minimum_size.x = 120
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var upgrades := _section("Upgrades", "Ageing up and tool sets")
	if not run.hand.milestone.is_empty():
		upgrades.add_child(_card(run.hand.milestone["building"], "", "age"))
	_tool_cards(upgrades)
	_drop_if_empty(upgrades)
	var trading := _section("Trading", "The caravan's deals, once each this round")
	_caravan_cards(trading)
	_drop_if_empty(trading)
	_fit.call_deferred()


## A labelled block of cards with a plain edge, so where one kind of card ends and the next begins is plain
## at a glance. Returns the row to put its cards in.
func _section(title: String, hint: String) -> HBoxContainer:
	var color := SECTION_COLOR
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.04)
	style.border_color = Color(color, 0.35)
	style.border_width_left = 3
	style.border_width_top = 1
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
	head.text = "[b][color=#%s]%s[/color][/b]" % [color.to_html(false), title.to_upper()]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	top.add_child(head)
	var hint_label := UiKit.note(top, hint, 12)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hints.append(hint_label)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 6)
	box.add_child(cards)
	return cards


## Shrinks the row to the strip's width: the section hints go first, then the whole row scales down
## (to MIN_SCALE at most), and the strip's height follows, giving the map back the room.
func _fit() -> void:
	var avail := _shelf.size.x
	if avail <= 0.0:
		return
	_hints.assign(_hints.filter(func(h: Label) -> bool: return is_instance_valid(h) and not h.is_queued_for_deletion()))
	for hint in _hints:
		hint.visible = true
	var width := _row.get_combined_minimum_size().x
	if width > avail:
		for hint in _hints:
			hint.visible = false
		width = _row.get_combined_minimum_size().x
	var s := clampf(avail / maxf(1.0, width), MIN_SCALE, 1.0)
	_row.scale = Vector2(s, s)
	_row.position = Vector2.ZERO
	_row.size = Vector2(width, ROW_HEIGHT)
	_shelf.custom_minimum_size.y = ceilf(ROW_HEIGHT * s)


## How much the row is shrunk to fit (1 at full size).
func row_scale() -> float:
	return _row.scale.x


func _drop_if_empty(cards: HBoxContainer) -> void:
	if cards.get_child_count() == 0:
		var panel := cards.get_parent().get_parent()
		_row.remove_child(panel)
		panel.queue_free()


## Whether the round's draft still waits on the player: a draft left and at least one offer they can take.
## While it does, the build waits behind the draft screen.
func draft_pending() -> bool:
	var h := run.hand
	if run.phase != RunState.Phase.BUILD or h.picks <= 0:
		return false
	return h.cards.any(func(c: Dictionary) -> bool: return h.can_draft(c["building"])) \
		or h.rows.any(func(c: Dictionary) -> bool: return h.can_draft_row(c["row"])) \
		or h.can_clear_ring() \
		or h.upgrade_offers.any(func(c: Dictionary) -> bool: return h.can_draft_upgrade(c["upgrade"]))


func draft_title() -> String:
	return "Draft %d blueprints" % run.hand.picks if run.hand.picks > 1 else "Draft a blueprint"


## The draft's offers and the reroll, into the draft screen's row.
func fill_draft(row: Container) -> void:
	for card: Dictionary in run.hand.cards:
		row.add_child(_card(card["building"], card["need"], "draft", card))
	for card: Dictionary in run.hand.rows:
		row.add_child(_row_card(card["row"], card["need"], true))
	if run.hand.ring_offer():
		row.add_child(_ring_card())
	for card: Dictionary in run.hand.upgrade_offers:
		row.add_child(_upgrade_card(card))
	var redraw := UiKit.secondary(Button.new(), 13)
	redraw.text = "Reroll\n%d shells" % run.hand.redraw_cost() if run.hand.redraws == 0 else "Rerolled\nthis round"
	redraw.custom_minimum_size = Vector2(86, 120)
	redraw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	redraw.disabled = not run.hand.can_redraw()
	redraw.tooltip_text = "Once a round: swap these offers for a fresh draw."
	redraw.pressed.connect(_act.bind(run.hand.redraw))
	row.add_child(redraw)


## What a building adds to the dawn picks once it stands ("" if nothing): heroes it lodges or draws,
## craftspeople it can make masters.
static func dawn_line(r: RunState, type: String) -> String:
	var content := r.content
	var def: Dictionary = content.buildings[type]
	for id: String in content.hero_classes:
		if content.hero_classes[id].get("needs", "") == type:
			return "Dawn: %ss can arrive" % content.hero_classes[id]["name"].to_lower()
	if def.has("lodging"):
		return "Dawn: heroes can arrive" if r.world.hero_ai.count_lodgings() == 0 else "Dawn: beds for %d more heroes" % int(def["lodging"]["beds"])
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


## offer = the draft offer (with its roll); a drafted blueprint shows the roll it was drafted with.
## A draft offer is a medium card on the draft screen; a card in the hand is a small one (its detail is on hover).
func _card(type: String, need: String, kind: String, offer := {}) -> CardView:
	var content := run.content
	var def: Dictionary = content.buildings[type]
	var owned := run.world.count_buildings(type, false)
	var drafting := kind == "draft"
	var tags: Array = content.tags_of("building", type)
	var band: String = {"basic": "Core", "age": "Ageing up", "blueprint": "Blueprint"}.get(kind, "New building")
	var text: String = def["text"]
	if drafting and "rule_breaker" in tags:
		band = "Rule-breaker"
	elif drafting and "outpost" in tags:
		band = "Outpost"
	var btn := CardView.new(CardView.Size.MEDIUM if drafting else CardView.Size.SMALL, "building", band, def["name"])
	if kind == "age":
		btn.set_band_icon("up")
	elif band == "Outpost":
		btn.set_band_icon("flag")
	btn.set_advice(recommendation(type, need))
	btn.set_price(run.stock, def["cost"])
	var dawn := dawn_line(run, type)
	var hint := row_hint(run, type) if drafting else ""
	if drafting:
		# The sun says "at dawn", so the chip keeps only what comes.
		if dawn != "":
			var what := dawn.trim_prefix("Dawn: ")
			btn.add_chip(what[0].to_upper() + what.substr(1), "sun", CardView.BONE)
		if hint != "":
			btn.add_chip(hint.replace("Opens a row: ", "Opens "), "house", CardView.TEXT, btn.family_color())
		if "outpost" in tags:
			btn.add_chip("can be lost", "", CardView.DANGER)
	# The band already says "Rule-breaker" or "Outpost", so the body skips saying it again.
	btn.set_body(text.trim_prefix("Rule-breaker. ").trim_prefix("Outpost. "))
	if not drafting and owned > 0:
		btn.set_footer("You have %d" % owned)
	# The frame shows the offer's own roll (CardRoll); the band's gem how rare this blueprint is.
	var rolled: Dictionary = offer if drafting else run.hand.rolled.get(type, {})
	var roll := CardRoll.roll_of(rolled)
	btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [text, roundi(float(def["work"]))]
	if drafting or kind == "blueprint":
		btn.set_roll(content, roll, content.rarity_of("building", type), CardRoll.mods_of(rolled))
		if roll != "white" and drafting:
			btn.tooltip_text += "\nDrafted, its modifiers change every one you build for the rest of the run."
	if dawn != "":
		btn.tooltip_text += "\n" + dawn + "."
	if drafting:
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
func _upgrade_card(offer: Dictionary) -> CardView:
	var id: String = offer["upgrade"]
	var up: Dictionary = run.content.upgrades[id]
	var building: String = run.content.buildings[up["building"]]["name"]
	var btn := CardView.new(CardView.Size.MEDIUM, "building", "Upgrade", up["name"]).set_band_icon("hammer")
	btn.add_chip("for your " + building.to_lower(), "house", CardView.TEXT, btn.family_color())
	btn.set_body(up["text"]).set_footer("Instead of a new blueprint")
	btn.tooltip_text = "Draft it: every %s, built or still to come, is changed for the rest of the run.\n%s" % [building.to_lower(), up["text"]]
	btn.set_roll(run.content, CardRoll.roll_of(offer), up.get("rarity", "white"), CardRoll.mods_of(offer))
	btn.disabled = not run.hand.can_draft_upgrade(id)
	btn.pressed.connect(_act.bind(run.hand.draft_upgrade.bind(id)))
	return btn


## A row card: two buildings ordered together, side by side, for less, and the bonus they make together.
func _row_card(id: String, need: String, drafting: bool) -> CardView:
	var content := run.content
	var row: Dictionary = content.combos[id]
	var a: String = content.buildings[row["building"]]["name"]
	var b: String = content.buildings[row["partner"]]["name"]
	var why := recommendation(row["building"] if run.hand.need(row["building"]) == need else row["partner"], need)
	var cost := run.row_cost(id)
	var btn := CardView.new(CardView.Size.MEDIUM if drafting else CardView.Size.SMALL, "building", "Draft a row" if drafting else "Row", row["name"])
	btn.set_advice(why)
	btn.set_price(run.stock, cost)
	btn.add_chip("%s + %s" % [a, b], "house", CardView.TEXT, btn.family_color())
	btn.set_body("%s %s" % [row_offer_line(run, id), row["text"]] if drafting else row["text"])
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
func _ring_card() -> CardView:
	var cost := run.ring_cost()
	var full := roundi(run.world.town.fullness() * 100.0)
	var btn := CardView.new(CardView.Size.MEDIUM, "building", "Clear a ring", "Clear a new ring").set_band_icon("ring")
	btn.set_advice("Room to grow: %d%% full" % full)
	btn.set_price(run.stock, cost)
	btn.set_body("Opens the next ring of plots round the town for good. A bigger town has a longer edge to hold.")
	btn.set_footer("Ring %d of %d" % [run.rings_open + 1, run.content.town["rings"].size()])
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
		var btn := CardView.new(CardView.Size.SMALL, "building", "Tool set", def["name"]).set_band_icon("hammer")
		btn.set_price(run.stock, def["cost"])
		btn.add_chip("for %ss" % content.townsfolk[def["role"]]["name"].to_lower(), "folk", CardView.TEXT, CardView.FAMILIES["folk"]["color"])
		btn.tooltip_text = "%s\nOnce only. Every ingot spent here is one the smiths can't turn into hero gear.\nYou have %d bronze%s." % [
			def["text"], run.stock["bronze"], ", %d iron, %d steel" % [run.stock["iron"], run.stock["steel"]] if content.age_reached(run.age, "medieval") else ""]
		btn.disabled = not run.can_buy_tools(id)
		UiKit.fade_if_disabled(btn, UiKit.shortfall(run.stock, def["cost"]))
		btn.pressed.connect(_act.bind(run.buy_tools.bind(id)))
		parent.add_child(btn)


## The southern caravan's trade cards (run.caravan): each deal once a round, its frame in its roll's colour,
## a bone ribbon when the town wants it, a red one when it can't be taken.
func _caravan_cards(parent: HBoxContainer) -> void:
	for i in run.caravan.offers.size():
		parent.add_child(_deal_card(i))


## A deal reads as a trade: the price you pay top right, what you get on the gives row after an arrow.
func _deal_card(index: int) -> CardView:
	var content := run.content
	var offer: Dictionary = run.caravan.offers[index]
	var id: String = offer["deal"]
	var def := run.caravan.deal(id)
	var give := run.caravan.gives(id, offer)
	var btn := CardView.new(CardView.Size.SMALL, "trade", "Caravan", def["name"])
	btn.set_advice(offer["need"])
	btn.set_price(run.stock, give)
	btn.add_chip("you get", "", CardView.DIM)
	btn.add_goods(run.caravan.gets(id, offer))
	var folk := run.caravan.folk_of(id, offer)
	for role: String in folk:
		var roles: Array = []
		for i in int(folk[role]):
			roles.append(role)
		btn.add_people(roles)
	if int(def.get("smith", 0)) > 0:
		btn.add_chip("weapons +%d tier%s" % [def["smith"], "s" if int(def["smith"]) > 1 else ""], "", CardView.GOOD)
	if int(def.get("relic", 0)) > 0:
		btn.add_chip("a relic", "relic", CardView.GOOD)
	var pays := ", ".join(PackedStringArray(give.keys().map(func(g: String) -> String: return "%d %s" % [give[g], g])))
	btn.tooltip_text = "A deal from the %s.\n%s\nYou pay: %s.\nYou get: %s.\nOnce this round." % [
		content.trades["name"].to_lower(), def["text"], pays if pays != "" else "nothing", deal_brings(run, id, offer)]
	btn.set_roll(content, CardRoll.roll_of(offer), content.rarity_of("deal", id), CardRoll.mods_of(offer))
	btn.disabled = not run.caravan.can_take(index)
	var blocked := run.caravan.blocker(index)
	UiKit.fade_if_disabled(btn, blocked if blocked != "" else UiKit.shortfall(run.stock, give))
	btn.pressed.connect(_act.bind(run.caravan.take.bind(index)))
	return btn


## What a deal brings, in words: "+4 tin", "2 warriors join", "every hero's weapon +1 tier", "a relic".
static func deal_brings(r: RunState, id: String, offer := {}) -> String:
	var def := r.caravan.deal(id)
	var parts: PackedStringArray = []
	var got := r.caravan.gets(id, offer)
	for good: String in got:
		parts.append("+%d %s" % [got[good], good])
	var folk := r.caravan.folk_of(id, offer)
	for role: String in folk:
		var n := int(folk[role])
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
