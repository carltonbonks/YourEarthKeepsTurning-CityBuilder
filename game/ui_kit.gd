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
	return b


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


## A card button like the building hand's: a small top line (gold and highlighted when `gold`), a big
## name, the cost, a short blurb, and a small footer. Detail belongs in the card's tooltip_text.
static func card(top: String, title: String, cost: String, blurb: String, footer: String, card_size: Vector2,
		border: Color, gold := false, title_color := Color.WHITE) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = card_size
	btn.clip_text = true
	# Space pauses the game, so a card clicked a moment ago must not take it.
	btn.focus_mode = Control.FOCUS_NONE
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	btn.add_child(box)
	card_frame(btn, border, 2 if gold else 1)
	var head := card_label(box, top, 11)
	head.add_theme_color_override("font_color", RECOMMEND_COLOR if gold else HINT_COLOR)
	# Every card keeps room for two lines here, so names line up along a row.
	head.custom_minimum_size.y = 34
	if gold:
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(0.45, 0.33, 0.1, 0.55)
		hl.set_corner_radius_all(3)
		hl.set_content_margin_all(2)
		head.add_theme_stylebox_override("normal", hl)
	card_label(box, title, 15).add_theme_color_override("font_color", title_color)
	if cost != "":
		card_label(box, cost, 12)
	var text := card_label(box, blurb, 10)
	text.add_theme_color_override("font_color", Color("#b8bcc4"))
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if footer != "":
		card_label(box, footer, 10).add_theme_color_override("font_color", HINT_COLOR)
	return btn


## A card's border and face; brighter on hover, faded when disabled.
static func card_frame(btn: Button, border: Color, width := 1) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#2a2e36") if state != "hover" else Color("#353a44")
		if state == "focus":
			sb.draw_center = false
		sb.border_color = border if state != "disabled" else Color(border, 0.4)
		sb.set_border_width_all(width)
		sb.set_corner_radius_all(5)
		btn.add_theme_stylebox_override(state, sb)


static func card_label(parent: Control, text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Fades a disabled card's face so it reads as out of reach.
static func fade_if_disabled(btn: Button) -> void:
	if btn.disabled and btn.get_child_count() > 0:
		(btn.get_child(0) as Control).modulate = Color(1, 1, 1, 0.5)


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
