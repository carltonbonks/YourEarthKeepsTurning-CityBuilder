class_name CardView
extends Button
## One card, drawn the same way wherever the player picks something (the card redesign, 2026-10-24): dawn,
## the blueprint draft, the build hand, caravan deals, relics, traditions and pedlars. Every part means one thing:
## - the frame is the card's rolled rarity: heavier each tier, with pips in the band, a slow glow on orange;
## - the band is what kind of card it is: a family colour and icon (FAMILIES), the kind in words, and on large and
##   medium cards a small gem when the kind itself is rare (how often it turns up);
## - the price sits top right, red where the town is short;
## - the gives row is what lands, as icons and numbers;
## - each rolled modifier is a plaque with its name and a few words (`short` in data/card_mods.json, data/marks.json),
##   an orange one split into its gift and its price;
## - the body is two lines at most and the footer is what the card costs to keep.
## Advice sits on a bone ribbon over the band; a blocker on a red strip over the footer (UiKit.fade_if_disabled).
## The rarity colours appear nowhere else on screen. The rest is in the hover panel, built when the mouse rests on
## the card from tooltip_text and the card's modifiers. Small cards (the build hand) show no body or plaques.

enum Size { LARGE, MEDIUM, SMALL }

## Every card of a size has the same shape, so cards read as one set wherever they appear: large and medium are
## 3:4, small (the build hand) squatter so the hand stays low over the map. Text that doesn't fit is in the hover panel.
const SHAPE := {Size.LARGE: Vector2(186, 248), Size.MEDIUM: Vector2(156, 208), Size.SMALL: Vector2(136, 140)}
## What kind of card: the band's colour and icon. Muted, and never one of the four rarity colours.
const FAMILIES := {
	"folk": {"color": "#c39a7a", "icon": "folk"},
	"hero": {"color": "#a58ad8", "icon": "hero"},
	"promote": {"color": "#c39a7a", "icon": "up"},
	"building": {"color": "#8fa3b8", "icon": "house"},
	"earth": {"color": "#6fb59a", "icon": "earth"},
	"trade": {"color": "#c97a9a", "icon": "cart"},
	"venture": {"color": "#c07a66", "icon": "map"},
	"relic": {"color": "#d4ccb8", "icon": "relic"},
	"spoils": {"color": "#9bb07a", "icon": "sack"},
	"tradition": {"color": "#b8a888", "icon": "flag"},
}
const BONE := Color("#e6e1d3")
const FACE := Color("#2a2e36")
const TEXT := Color("#ece8de")
const DIM := Color("#a9aeb7")
const GOOD := Color("#9be08a")
const DANGER := Color("#ff7a6a")
const PLAIN_BORDER := Color("#5a606c")
## Frame width for each roll, rarer heavier.
const FRAME_WIDTH := {"white": 1, "blue": 2, "yellow": 2, "orange": 3}

var content: Content
var card_size := Size.LARGE
var family := "folk"
var roll := "white"
var kind_rarity := "white"
var mods: Array[String] = []
var title_label: Label
var _box: VBoxContainer
var _band: PanelContainer
var _band_row: HBoxContainer
var _head: HBoxContainer
var _price: HBoxContainer
var _gives: HFlowContainer
var _plaques: VBoxContainer
var _body: Label
var _footer: Label
var _selected := false
## How many lines the body may take when there is room (set_body_lines), and whether it has text to show.
var _body_lines := 2
var _body_wanted := false
var _fitting := false


func _init(sz := Size.LARGE, fam := "folk", kind := "", title := "") -> void:
	card_size = sz
	family = fam
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# Space pauses the game, so a card clicked a moment ago must not take it.
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = SHAPE[sz]
	_box = VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 0)
	add_child(_box)
	_box.minimum_size_changed.connect(_fit)
	resized.connect(_fit)
	_band = PanelContainer.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint := family_color()
	var bs := StyleBoxFlat.new()
	bs.bg_color = FACE.lerp(tint, 0.2)
	bs.border_color = Color(tint, 0.45)
	bs.border_width_bottom = 1
	bs.corner_radius_top_left = 5
	bs.corner_radius_top_right = 5
	bs.content_margin_left = 7
	bs.content_margin_right = 7
	bs.content_margin_top = 4
	bs.content_margin_bottom = 4
	_band.add_theme_stylebox_override("panel", bs)
	_box.add_child(_band)
	_band_row = HBoxContainer.new()
	_band_row.add_theme_constant_override("separation", 5)
	_band.add_child(_band_row)
	_band_row.add_child(CardIcon.make(FAMILIES.get(family, FAMILIES["folk"])["icon"], tint, 13.0 if sz == Size.SMALL else 14.0))
	var kl := _label(_band_row, kind.to_upper(), 10, tint)
	kl.autowrap_mode = TextServer.AUTOWRAP_OFF
	kl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kl.clip_text = true
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kl.add_theme_constant_override("outline_size", 0)
	var inner := MarginContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		inner.add_theme_constant_override("margin_" + side, 8 if sz != Size.SMALL else 6)
	inner.add_theme_constant_override("margin_top", 6)
	inner.add_theme_constant_override("margin_bottom", 4)
	_box.add_child(inner)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	inner.add_child(col)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 4)
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_head)
	title_label = _label(_head, title, {Size.LARGE: 17, Size.MEDIUM: 16, Size.SMALL: 14}[sz], TEXT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price = HBoxContainer.new()
	_price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_price.add_theme_constant_override("separation", 3)
	_price.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# Smaller cards are too narrow for the name and the price side by side: the price goes under the name.
	(_head if sz == Size.LARGE else col).add_child(_price)
	_gives = HFlowContainer.new()
	_gives.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gives.add_theme_constant_override("h_separation", 4)
	_gives.add_theme_constant_override("v_separation", 3)
	col.add_child(_gives)
	_plaques = VBoxContainer.new()
	_plaques.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plaques.add_theme_constant_override("separation", 3)
	col.add_child(_plaques)
	_body = _label(col, "", 11, DIM)
	_body.max_lines_visible = 2
	_body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_body.visible = false
	# Pushes the footer to the bottom, so footers line up along a row of cards.
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(spacer)
	var foot := MarginContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		foot.add_theme_constant_override("margin_" + side, 8 if sz != Size.SMALL else 6)
	foot.add_theme_constant_override("margin_bottom", 5)
	_box.add_child(foot)
	_footer = _label(foot, "", 10, Color("#9aa0aa"))
	_footer.visible = false
	_apply_frame()


## A coloured dot before the name (a hero's class colour).
func add_title_dot(tint: Color) -> CardView:
	var dot := CardIcon.make("dot", tint, 12.0)
	_head.add_child(dot)
	_head.move_child(dot, 0)
	return self


## Another icon for the band than the family's own (an outpost's flag, an upgrade's hammer).
func set_band_icon(id: String) -> CardView:
	var old := _band_row.get_child(0) as CardIcon
	old.icon = id
	old.queue_redraw()
	return self


func family_color() -> Color:
	return Color(FAMILIES.get(family, FAMILIES["folk"])["color"])


## The card keeps its shape: when what is on it runs too tall, the body gives up lines, then goes (the hover panel
## has it all). Only a card that still doesn't fit grows. Judged once the card has its width: before that every
## label measures tall.
func _fit() -> void:
	if _fitting or size.x < SHAPE[card_size].x - 0.5:
		return
	_fitting = true
	var lines := _body_lines
	_body.max_lines_visible = lines
	_body.visible = _body_wanted
	while _body.visible and _box.get_combined_minimum_size().y > SHAPE[card_size].y:
		lines -= 1
		if lines <= 0:
			_body.visible = false
		else:
			_body.max_lines_visible = lines
	custom_minimum_size.y = maxf(SHAPE[card_size].y, _box.get_combined_minimum_size().y)
	_fitting = false


func _label(parent: Control, text: String, font_size: int, tint: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## The price, top right: each good's icon and amount, red where the town is short. An empty cost reads "Free".
func set_price(stock: Dictionary, cost: Dictionary) -> CardView:
	for c in _price.get_children():
		c.queue_free()
	if cost.is_empty():
		_chip_label(_price, "Free", DIM)
		return self
	for good: String in cost:
		var short := int(stock.get(good, 0)) < int(cost[good])
		_price.add_child(CardIcon.good(good))
		_chip_label(_price, str(int(cost[good])) + ("" if CardIcon.has_shape(good) else " " + good.replace("_", " ")),
			DANGER if short else TEXT)
	return self


## A price that isn't goods ("free", "never comes back").
func set_price_text(text: String, tint := DIM) -> CardView:
	_chip_label(_price, text, tint)
	return self


func _chip_label(parent: Control, text: String, tint: Color, font_size := 12) -> Label:
	var l := _label(parent, text, font_size, tint)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


## A chip on the gives row: a few words, an optional icon before them.
func add_chip(text: String, icon := "", tint := TEXT, icon_tint := Color(0, 0, 0, 0)) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.28)
	st.set_corner_radius_all(3)
	st.content_margin_left = 4
	st.content_margin_right = 5
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	if icon != "":
		row.add_child(CardIcon.make(icon, icon_tint if icon_tint.a > 0.0 else tint, 12.0))
	if text != "":
		var l := _chip_label(row, text, tint, 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = minf(l.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 1.0,
			SHAPE[card_size].x - 34.0)
	_gives.add_child(chip)
	return chip


## Goods as chips: "+51" with the wood icon. A good with no icon of its own is named. The chip remembers the good
## and the amount (meta "good", "amount") for anyone reading the card.
func add_goods(goods: Dictionary, plus := true, tint := GOOD) -> void:
	for good: String in goods:
		var n := int(goods[good])
		var chip := add_chip(("+" if plus else "") + str(n) + ("" if CardIcon.has_shape(good) else " " + good.replace("_", " ")), "", tint)
		var row := chip.get_child(0)
		var icon := CardIcon.good(good, 12.0)
		row.add_child(icon)
		row.move_child(icon, 0)
		chip.set_meta("good", good)
		chip.set_meta("amount", n)


## A good a card is about, by name with its icon ("food"): what a tribesperson leans toward.
func add_good_label(good: String) -> void:
	var chip := add_chip(good.replace("_", " "), "", TEXT)
	var row := chip.get_child(0)
	var icon := CardIcon.good(good, 12.0)
	row.add_child(icon)
	row.move_child(icon, 0)


## The people a card brings, one figure each (a warrior's carries a spear), "×N" past five.
func add_people(roles: Array) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 1)
	for i in mini(roles.size(), 5):
		row.add_child(CardIcon.make("warrior" if roles[i] == "warrior" else "folk", family_color().lightened(0.15), 15.0))
	if roles.size() > 5:
		_chip_label(row, "×%d" % roles.size(), TEXT, 11)
	_gives.add_child(row)


## Anything else for the gives row (the venture's figures).
func add_control(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gives.add_child(c)


## Two lines at most; the whole text belongs in tooltip_text. Small cards keep it for the hover panel only.
func set_body(text: String, tint := DIM) -> CardView:
	_body.text = text
	_body.add_theme_color_override("font_color", tint)
	_body_wanted = text != "" and card_size != Size.SMALL
	_body.visible = _body_wanted
	_fit()
	return self


## Lets the body run to as many lines as it needs (a relic's text is the whole card).
func set_body_lines(lines: int) -> CardView:
	_body_lines = lines
	_body.max_lines_visible = lines
	_fit()
	return self


func set_footer(text: String) -> CardView:
	_footer.text = text
	_footer.visible = text != ""
	return self


## Why the town wants this card, on a bone ribbon over the band.
func set_advice(text: String) -> CardView:
	if text == "":
		return self
	var l := _label(_box, text, 11, Color("#1a1c22"))
	var st := StyleBoxFlat.new()
	st.bg_color = BONE
	st.corner_radius_top_left = 5
	st.corner_radius_top_right = 5
	st.content_margin_left = 7
	st.content_margin_right = 7
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	l.add_theme_stylebox_override("normal", st)
	_box.move_child(l, 0)
	var bs := _band.get_theme_stylebox("panel") as StyleBoxFlat
	bs.corner_radius_top_left = 0
	bs.corner_radius_top_right = 0
	return self


## A chosen card (a tradition picked): a bone frame.
func set_selected(on: bool) -> CardView:
	_selected = on
	_apply_frame()
	return self


## The roll: the frame and pips in the roll's colour, the kind's gem, and one plaque per modifier.
func set_roll(c: Content, rolled: String, kind_rare: String, mod_ids: Array[String]) -> CardView:
	content = c
	roll = rolled
	kind_rarity = kind_rare
	mods = mod_ids
	_apply_frame()
	var pips: int = c.rarity["order"].find(roll)
	if pips > 0:
		var box := HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		for i in pips:
			var pip := CardIcon.make("diamond", c.rarity_color(roll), 7.0)
			pip.accent = Color(0, 0, 0, 0.0)
			box.add_child(pip)
		_band_row.add_child(box)
	if kind_rarity != "white" and card_size != Size.SMALL:
		# Round, so it never reads as one more pip: pips are this card's roll, the gem how rare its kind is.
		var gem := CardIcon.make("gem", c.rarity_color(kind_rarity), 11.0)
		_band_row.add_child(gem)
	if card_size == Size.SMALL:
		return self
	for id in mods:
		_plaques.add_child(_plaque(id))
	return self


## The rarity names this card's roll and kind would show in the hover panel, for checks.
func roll_line() -> String:
	if content == null:
		return ""
	var parts := PackedStringArray()
	if roll != "white":
		parts.append("%s card" % content.rarity_tier(roll)["name"])
	if kind_rarity != "white":
		parts.append("this kind of card is %s: it turns up less often" % content.rarity_tier(kind_rarity)["name"].to_lower())
	return ", ".join(parts)


## An orange modifier's text reads "gift, but price": [gift, price] (price "" when it has none).
static func split_price(text: String) -> PackedStringArray:
	var at := text.find(", but ")
	if at < 0:
		return PackedStringArray([text, ""])
	return PackedStringArray([text.substr(0, at), text.substr(at + 6)])


func _plaque(id: String) -> Control:
	var m := CardRoll.mod_def(content, id)
	var tint := content.rarity_color(roll)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(tint, 0.13)
	st.border_color = Color(tint, 0.7)
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.content_margin_left = 5
	st.content_margin_right = 5
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 1)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	if content.marks.has(id):
		# A mark shows its own dot, the same one its bearer wears on the map.
		var shape: String = m.get("shape", "circle")
		var dot := CardIcon.make({"circle": "dot", "diamond": "diamond", "square": "square"}.get(shape, "dot"), Color(m["color"]), 9.0)
		dot.accent = Color(0, 0, 0, 0.0)
		row.add_child(dot)
	var name_l := _chip_label(row, m["name"], tint.lightened(0.35), 11)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The few words go beside the name when both fit the card, else on a line of their own under it.
	var short := str(m.get("short", ""))
	var font := name_l.get_theme_font("font")
	var room: float = SHAPE[card_size].x - 32.0
	var both := font.get_string_size(m["name"] + "  " + short, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + (13.0 if content.marks.has(id) else 0.0)
	var short_l := _chip_label(row if both <= room else col, short, TEXT, 11)
	short_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var price := split_price(m["text"])[1] if roll == "orange" else ""
	if price != "":
		st.border_color = Color(tint, 0.9)
		var p := _label(col, price[0].to_upper() + price.substr(1), 10, Color("#f2a39b"))
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color("#e0574a", 0.18)
		ps.border_color = Color("#e0574a", 0.6)
		ps.border_width_top = 1
		ps.content_margin_left = 3
		ps.content_margin_top = 1
		ps.content_margin_bottom = 1
		p.add_theme_stylebox_override("normal", ps)
	return panel


func _apply_frame() -> void:
	var border := PLAIN_BORDER
	var width := 1
	if roll != "white" and content != null:
		border = content.rarity_color(roll)
		width = int(FRAME_WIDTH.get(roll, 2))
	if _selected:
		border = BONE
		width = 3
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"hover": FACE.lightened(0.09), "pressed": FACE.lightened(0.15), "disabled": FACE.darkened(0.2)}.get(state, FACE)
		if state == "focus":
			sb.draw_center = false
		# Hovering lifts the card and brightens its own frame; it never turns another colour.
		sb.border_color = border.lightened(0.35) if state == "hover" or state == "pressed" else (border if state != "disabled" else Color(border, 0.35))
		sb.set_border_width_all(width + (1 if state == "hover" and width < 3 else 0))
		sb.set_corner_radius_all(6)
		if state == "normal" or state == "hover":
			sb.shadow_color = Color(0, 0, 0, 0.45 if state == "hover" else 0.3)
			sb.shadow_size = 6 if state == "hover" else 2
			sb.shadow_offset = Vector2(0, 3 if state == "hover" else 1)
		if roll == "orange" and state != "disabled" and not _selected:
			sb.shadow_color = Color(border, 0.4)
			sb.shadow_size = 7
			sb.shadow_offset = Vector2.ZERO
			if state == "normal":
				_glow(sb)
		add_theme_stylebox_override(state, sb)


## An orange card's glow breathes slowly, so a mythic card catches the eye without a word.
func _glow(sb: StyleBoxFlat) -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(sb, "shadow_size", 11, 1.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sb, "shadow_size", 5, 1.6).set_trans(Tween.TRANS_SINE)


## The hover panel: the card's name, its roll and how often its kind turns up, every modifier in full (an orange
## one's price in red), then the card's own detail (tooltip_text).
func _make_custom_tooltip(for_text: String) -> Object:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_tip_line(box, title_label.text, 14, Color("#f0e6c8"))
	var rl := roll_line()
	if rl != "":
		_tip_line(box, rl[0].to_upper() + rl.substr(1) + ".", 11, Color("#9aa0aa"))
	for id in mods:
		var m := CardRoll.mod_def(content, id)
		var parts := split_price(m["text"]) if roll == "orange" else PackedStringArray([m["text"], ""])
		_tip_line(box, "%s: %s" % [m["name"], parts[0]], 12, content.rarity_color(roll).lightened(0.3))
		if parts[1] != "":
			_tip_line(box, "Price: " + parts[1], 12, Color("#f2a39b"))
	for line in for_text.split("\n"):
		if line.strip_edges() != "":
			_tip_line(box, line, 12, Color("#c8ccc0"))
	return box


func _tip_line(box: VBoxContainer, text: String, font_size: int, tint: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", tint)
	if text.length() > 56:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 340
	box.add_child(l)
