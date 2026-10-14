class_name BuildHandView
extends PanelContainer
## The round's building cards (run.hand) as a heads-up hand along the bottom of the map, like the
## dawn pick: basics (homes and food, always on offer), the dealt cards, the ageing-up card and the
## redraw. A card the town needs says why at the top ("Recommended: ..."). Shown only while building.
## Every choice goes through run.hand; `changed` asks the screen to refresh.

signal changed

const RECOMMEND_COLOR := Color("#ffd28a")
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
	if run.hand.cards.is_empty() and run.hand.milestone.is_empty():
		var none := UiKit.note(_row, "No cards left this round.", 12)
		none.custom_minimum_size.x = 120
	var redraw := Button.new()
	redraw.text = "Redraw\nunused\n(%d shells)%s" % [run.hand.redraw_cost(), "" if run.hand.redraws == 0 else "\nused"]
	redraw.custom_minimum_size = Vector2(86, CARD_SIZE.y)
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
		"stall":
			return "Your workshop needs a stall"
		"age":
			return "New in the %s" % content.age_name(content.buildings[type].get("age", run.age)).to_lower()
	return ""


func _card(type: String, need: String, kind: String) -> Button:
	var def: Dictionary = run.content.buildings[type]
	var owned := run.world.count_buildings(type, false)
	var btn := Button.new()
	btn.custom_minimum_size = BASIC_SIZE if kind == "basic" else CARD_SIZE
	btn.clip_text = true
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	btn.add_child(box)
	var why := recommendation(type, need)
	_frame(btn, RECOMMEND_COLOR if why != "" else (UiKit.HEADING_COLOR if kind == "age" else Color("#5a606c")))
	var top := _label(box, ("Recommended: " + why) if why != "" else ("Always on offer" if kind == "basic" else ("Ageing up" if kind == "age" else "")), 11)
	top.add_theme_color_override("font_color", RECOMMEND_COLOR if why != "" else UiKit.HINT_COLOR)
	# Every card keeps room for two lines here, so names line up along the hand.
	top.custom_minimum_size.y = 34
	if why != "":
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(0.45, 0.33, 0.1, 0.55)
		hl.set_corner_radius_all(3)
		hl.set_content_margin_all(2)
		top.add_theme_stylebox_override("normal", hl)
	var name := _label(box, ("RAISE: " if kind == "age" else "") + def["name"], 15)
	name.add_theme_color_override("font_color", UiKit.HEADING_COLOR if kind == "age" else Color.WHITE)
	_label(box, _cost_text(def), 12)
	var blurb := _label(box, def["text"], 10)
	blurb.add_theme_color_override("font_color", Color("#b8bcc4"))
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blurb.clip_text = true
	blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if owned > 0:
		_label(box, "You have %d" % owned, 10).add_theme_color_override("font_color", UiKit.HINT_COLOR)
	btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [def["text"], def["work"]]
	var blocked := BuildPanel.build_blocker(run, type)
	if blocked != "":
		btn.tooltip_text += "\n" + blocked
	var problems := Tooltips.warnings(run, type)
	if not problems.is_empty():
		btn.tooltip_text += "\n" + "\n".join(PackedStringArray(problems))
	btn.disabled = not run.hand.can_order(type)
	if btn.disabled:
		box.modulate = Color(1, 1, 1, 0.5)
	btn.pressed.connect(_act.bind(run.hand.order.bind(type)))
	return btn


## A card's border and face: gold when the town needs it, grey otherwise; brighter on hover.
func _frame(btn: Button, border: Color) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#2a2e36") if state != "hover" else Color("#353a44")
		if state == "focus":
			sb.draw_center = false
		sb.border_color = border if state != "disabled" else Color(border, 0.4)
		sb.set_border_width_all(2 if border == RECOMMEND_COLOR else 1)
		sb.set_corner_radius_all(5)
		btn.add_theme_stylebox_override(state, sb)


func _label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func _cost_text(def: Dictionary) -> String:
	var cost := PackedStringArray()
	for r: String in def["cost"]:
		cost.append("%d %s" % [def["cost"][r], r])
	return ", ".join(cost)


func _act(choice: Callable) -> void:
	choice.call()
	changed.emit()
