class_name UiKit
extends RefCounted
## Small builders for the placeholder UI, shared by the screen's panels. Cards are CardView.

## The text language (docs/TEXT_STYLE.md). Each colour means one thing; text that doesn't carry the meaning is
## INK or DIM. The four rarity colours belong to card frames (CardView) and appear nowhere else.
const INK := Color("#ece8de")
const DIM := Color("#a9aeb7")
## Good for the town, gained.
const GOOD := Color("#a8d890")
## Loss, danger, can't.
const DANGER := Color("#ff7a6a")
## A problem this round the player can fix (alerts, the Elder).
const EMBER := Color("#e0a050")
## A moment: tier 3 and 4 banners only.
const GOLD := Color("#ffd870")
## Advice and the one button that moves the game on.
const BONE := Color("#e6e1d3")
## Night on the clock: a time of day, not a state.
const NIGHT := Color("#8fa8ff")
const HINT_COLOR := DIM
const HEADING_COLOR := INK
const RECOMMEND_COLOR := BONE

## The six text sizes (cards keep their own, CardView.SHAPE), plus the run's banner.
const CAPTION := 11
const BODY := 13
const STRONG := 15
const TITLE := 18
const HEADING := 24
## Tier 3 moments (the last kill, a new age).
const BANNER := 32
## Tier 4: victory, the fire going out.
const BANNER_RUN := 44


## A colour as a BBCode tag's value ("#ff7a6a").
static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Text in a colour, as BBCode.
static func tint(text: String, c: Color) -> String:
	return "[color=%s]%s[/color]" % [hex(c), text]


## One story line as BBCode in its emphasis tier (RunState.AMBIENT .. RUN): routine dim, notices plain, problems in
## red, moments and the run's end in bold gold. A round's opening line stays bold so the log reads in rounds.
static func story_line(line: String, tier: int) -> String:
	match tier:
		RunState.AMBIENT:
			return tint(line, DIM)
		RunState.PROBLEM:
			return tint(line, DANGER.lerp(INK, 0.35))
		RunState.MOMENT, RunState.RUN:
			return "[b]%s[/b]" % tint(line, GOLD)
	return "[b]%s[/b]" % line if line.begins_with("Round ") else line


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
static func note(parent: Control, text: String, font_size := BODY, color := HINT_COLOR) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
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
	l.add_theme_font_size_override("font_size", CAPTION)
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
		return tint("Free", GOOD)
	var parts := PackedStringArray()
	for r: String in cost:
		var short := int(stock.get(r, 0)) < int(cost[r])
		parts.append(tint("%d %s" % [cost[r], r], DANGER if short else INK))
	return ", ".join(parts)


## What the town still lacks for a cost ("Need 3 more wood"), or "" when it can pay.
static func shortfall(stock: Dictionary, cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for r: String in cost:
		var gap := int(cost[r]) - int(stock.get(r, 0))
		if gap > 0:
			parts.append("%d more %s" % [gap, r])
	return "Need " + ", ".join(parts) if not parts.is_empty() else ""


## The look of the one button that moves the game on (Begin round, Resume): solid bone, dark text.
static func primary(btn: Button, font_size := TITLE) -> Button:
	btn.add_theme_font_size_override("font_size", font_size)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.focus_mode = Control.FOCUS_NONE
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"hover": Color("#f7f4ec"), "pressed": Color("#c9c3b2"), "disabled": Color("#55524a")}.get(state, RECOMMEND_COLOR)
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
static func secondary(btn: Button, font_size := STRONG) -> Button:
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
