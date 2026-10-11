class_name UiKit
extends RefCounted
## Small builders for the placeholder UI, shared by the screen's panels.

const HINT_COLOR := Color("#9aa")
const HEADING_COLOR := Color("#e8d9a8")


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
