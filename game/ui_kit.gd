class_name UiKit
extends RefCounted
## Small builders for the placeholder UI, shared by the screen's panels.

const HINT_COLOR := Color("#9aa")
const HEADING_COLOR := Color("#e8d9a8")
const RECOMMEND_COLOR := Color("#ffd28a")
const CARD_BORDER := Color("#5a606c")


static func heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", HEADING_COLOR)
	parent.add_child(l)


static func button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return secondary(b)


static func rich(parent: Control, min_height: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.custom_minimum_size.y = min_height
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL if min_height == 0 else Control.SIZE_FILL
	parent.add_child(r)
	return r


## A wrapped line of small text, grey unless a colour is given.
static func note(parent: Control, text: String, font_size := 12, color := HINT_COLOR) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## A card button like the building hand's, laid out so what decides the choice stands out: a small
## top line (when `gold`, the reason the town wants it, on a gold strip), a big name, the cost (BBCode,
## see cost_text: red where the town is short), a dim short blurb, and a small footer. Detail belongs
## in the card's tooltip_text. A card that can't be taken says why on its face (block).
static func card(top: String, title: String, cost: String, blurb: String, footer: String, card_size: Vector2,
		border: Color, gold := false, title_color := Color.WHITE) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = card_size
	btn.clip_text = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Space pauses the game, so a card clicked a moment ago must not take it.
	btn.focus_mode = Control.FOCUS_NONE
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 3)
	btn.add_child(box)
	card_frame(btn, border, 2 if gold else 1)
	var head := card_label(box, top, 11)
	head.add_theme_color_override("font_color", Color("#1a1408") if gold else HINT_COLOR)
	# Every card keeps room here, so names line up along a row.
	head.custom_minimum_size.y = 30
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if gold:
		var hl := StyleBoxFlat.new()
		hl.bg_color = RECOMMEND_COLOR
		hl.set_corner_radius_all(3)
		hl.set_content_margin_all(3)
		head.add_theme_stylebox_override("normal", hl)
	card_label(box, title, 17).add_theme_color_override("font_color", title_color)
	if cost != "":
		var price := RichTextLabel.new()
		price.bbcode_enabled = true
		price.fit_content = true
		price.scroll_active = false
		price.autowrap_mode = TextServer.AUTOWRAP_WORD
		price.mouse_filter = Control.MOUSE_FILTER_IGNORE
		price.add_theme_font_size_override("normal_font_size", 13)
		price.add_theme_font_size_override("bold_font_size", 13)
		price.text = cost
		box.add_child(price)
	var text := card_label(box, blurb, 10)
	text.add_theme_color_override("font_color", Color("#9da2ab"))
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if footer != "":
		card_label(box, footer, 10).add_theme_color_override("font_color", HINT_COLOR)
	return btn


## Colours a card by its rarity (data/rarity.json): the border, and the rarity's name on the top line.
## White (base) cards keep their usual look; a recommended (gold) top line keeps its gold.
static func mark_rarity(btn: Button, content: Content, rarity_id: String) -> void:
	if rarity_id == "white":
		return
	var color := content.rarity_color(rarity_id)
	card_frame(btn, color, 2)
	var head := btn.get_child(0).get_child(0) as Label
	head.text = "%s · %s" % [head.text, content.rarity_tier(rarity_id)["name"]]
	if not head.has_theme_stylebox_override("normal"):
		head.add_theme_color_override("font_color", color)


## A dealt card that rolled its own rarity (sim/card_roll.gd): the frame and top line show the roll (mark_rarity),
## a small gem in the top corner shows how often its kind turns up (its own rarity, none for white), and its
## modifiers sit under the name in the roll's colour, one a line.
static func mark_roll(btn: Button, content: Content, roll: String, kind_rarity: String, mods: Array[String]) -> void:
	mark_rarity(btn, content, roll)
	if kind_rarity != "white":
		var gem := ColorRect.new()
		gem.color = content.rarity_color(kind_rarity)
		gem.size = Vector2(7, 7)
		gem.pivot_offset = gem.size * 0.5
		gem.rotation = PI / 4.0
		gem.position = Vector2(btn.custom_minimum_size.x - 14.0, 7.0)
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(gem)
		btn.tooltip_text += "\nThis kind of card is %s: it turns up less often." % content.rarity_tier(kind_rarity)["name"].to_lower()
	if mods.is_empty():
		return
	var box := btn.get_child(0) as VBoxContainer
	var lines := card_label(box, "\n".join(mods), 11)
	lines.add_theme_color_override("font_color", content.rarity_color(roll).lightened(0.25))
	box.move_child(lines, 2)
	btn.custom_minimum_size.y += 15.0 * mods.size()
	btn.tooltip_text += "\n%s card: %s." % [content.rarity_tier(roll)["name"], "; ".join(mods)]


## A card's border and face: lifts and lights up gold under the mouse so it reads as clickable,
## faded when it can't be taken.
static func card_frame(btn: Button, border: Color, width := 1) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"hover": Color("#3a404c"), "pressed": Color("#454c5a"), "disabled": Color("#24272d")}.get(state, Color("#2c3038"))
		if state == "focus":
			sb.draw_center = false
		sb.border_color = HEADING_COLOR if state == "hover" or state == "pressed" else (border if state != "disabled" else Color(border, 0.35))
		sb.set_border_width_all(maxi(width, 2) if state == "hover" else width)
		sb.set_corner_radius_all(6)
		if state == "normal" or state == "hover":
			sb.shadow_color = Color(0, 0, 0, 0.45 if state == "hover" else 0.3)
			sb.shadow_size = 5 if state == "hover" else 2
			sb.shadow_offset = Vector2(0, 3 if state == "hover" else 1)
		btn.add_theme_stylebox_override(state, sb)


static func card_label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Fades a disabled card's face so it reads as out of reach, and when `why` is given says on the card
## what stands in the way ("Need 3 more wood"), on a red strip along its bottom that stays readable.
static func fade_if_disabled(btn: Button, why := "") -> void:
	if not btn.disabled or btn.get_child_count() == 0:
		return
	btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
	(btn.get_child(0) as Control).modulate = Color(1, 1, 1, 0.45)
	if why == "":
		return
	var l := Label.new()
	l.text = why
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color("#ffd8d0"))
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(0.5, 0.14, 0.12, 0.92)
	strip.set_corner_radius_all(3)
	strip.set_content_margin_all(3)
	l.add_theme_stylebox_override("normal", strip)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 5)
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	btn.add_child(l)


## A cost as BBCode for a card: each good in white when the town has enough, red when it is short.
## An empty cost reads "Free".
static func cost_text(stock: Dictionary, cost: Dictionary) -> String:
	if cost.is_empty():
		return "[color=#a8d890]Free[/color]"
	var parts := PackedStringArray()
	for r: String in cost:
		var short := int(stock.get(r, 0)) < int(cost[r])
		parts.append("[color=%s]%d %s[/color]" % ["#ff7a6a" if short else "#f0f0f0", cost[r], r])
	return ", ".join(parts)


## What the town still lacks for a cost ("Need 3 more wood"), or "" when it can pay.
static func shortfall(stock: Dictionary, cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for r: String in cost:
		var gap := int(cost[r]) - int(stock.get(r, 0))
		if gap > 0:
			parts.append("%d more %s" % [gap, r])
	return "Need " + ", ".join(parts) if not parts.is_empty() else ""


## The look of the one button that moves the game on (Begin round, Resume): solid gold, dark text.
static func primary(btn: Button, font_size := 17) -> Button:
	btn.add_theme_font_size_override("font_size", font_size)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"hover": Color("#ffe0a0"), "pressed": Color("#d8a858"), "disabled": Color("#5a5040")}.get(state, RECOMMEND_COLOR)
		if state == "focus":
			sb.draw_center = false
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
		btn.add_theme_stylebox_override(state, sb)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(key, Color("#1a1408"))
	btn.add_theme_color_override("font_disabled_color", Color("#9a9080"))
	return btn


## The look of a second choice (Skip, Nobody today, Redraw): outlined, so it reads as a button but
## doesn't compete with the cards or the main button.
static func secondary(btn: Button, font_size := 14) -> Button:
	btn.add_theme_font_size_override("font_size", font_size)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"hover": Color("#3a404c"), "pressed": Color("#454c5a")}.get(state, Color("#262a31"))
		if state == "focus":
			sb.draw_center = false
		sb.border_color = Color(HEADING_COLOR, 0.3 if state == "disabled" else (1.0 if state == "hover" else 0.6))
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(6)
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", HEADING_COLOR)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(HINT_COLOR, 0.5))
	return btn


## A thin bar: `fraction` of it filled with `color`, the rest dark.
static func bar(parent: Control, fraction: float, color: Color, height := 4.0) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(0.05, 0.05, 0.06)
	back.custom_minimum_size.y = height
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	set_bar(back, fraction)
	return back


static func set_bar(back: ColorRect, fraction: float, color := Color(0, 0, 0, 0)) -> void:
	var fill := back.get_child(0) as ColorRect
	fill.anchor_right = clampf(fraction, 0.0, 1.0)
	fill.anchor_bottom = 1.0
	fill.offset_right = 0.0
	fill.offset_bottom = 0.0
	if color.a > 0.0:
		fill.color = color
