class_name TipChip
extends PanelContainer
## A small panel that shows a hover card built when the mouse rests on it, in the same style as
## the map's tooltips. `tip` returns a Tooltips-style dictionary ({title, lines, tags, warnings});
## `pressed` fires on a click. Used for the top bar, the hero portraits and the threat card, so
## the screen stays short and the detail is there when you point at it.

signal pressed

var tip := Callable()
var _last_tip := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.17, 0.2, 0.92)
	style.border_color = Color("#3c414c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(5)
	add_theme_stylebox_override("panel", style)


## Children never take the mouse, so the whole chip shows the hover card.
func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_ignore_mouse(self)


func _ignore_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(child)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


func _get_tooltip(_at: Vector2) -> String:
	_last_tip = tip.call() if tip.is_valid() else {}
	return "" if _last_tip.is_empty() else Tooltips.as_text(_last_tip)


func _make_custom_tooltip(_for_text: String) -> Object:
	return card_for(_last_tip)


## A hover card for a tip: title, lines, tags, then warnings in orange, like the map's.
static func card_for(t: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	_line(box, t.get("title", ""), 14, Color("#f0e6c8"))
	for line: String in t.get("lines", []):
		_line(box, line, 12, Color("#c8ccc0"))
	if not t.get("tags", []).is_empty():
		_line(box, "Tags", 12, Color("#9fc4e0"))
		for tag: String in t["tags"]:
			_line(box, "- " + tag, 12, Color("#9fc4e0"))
	for warning: String in t.get("warnings", []):
		_line(box, warning, 12, Color("#ffb060"))
	return box


static func _line(box: VBoxContainer, text: String, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	# Long lines wrap at a readable width; short ones keep the card narrow.
	if text.length() > 60:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 380
	box.add_child(l)
