class_name DraftPopup
extends PanelContainer
## The round's blueprint draft as a small window over the map, so the run's weightiest build choice
## sits apart from the cards the town orders from. Drag it by its title bar to see the town under it,
## or hide it down to the title bar and show it again. It remembers where it was put for the rest of
## the run. BuildHandView fills `cards` and decides when it shows; this file is only the window.
## On a map too narrow for all the offers it shrinks to fit. `moved` fires whenever it moves, folds or
## changes size, so the panels beside it can make room (HudLayout).

signal moved

const BORDER := Color("#ffd28a")

## The row the offers and the reroll go in.
var cards: HBoxContainer
var _title: Label
var _toggle: Button
var _body: Control
var _placed := false
var _dragging := false


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.13, 0.96)
	style.border_color = BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 10
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	# The title bar is the handle: dragging it moves the window.
	var bar := HBoxContainer.new()
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_bar_input)
	box.add_child(bar)
	bar.add_theme_constant_override("separation", 10)
	_title = UiKit.note(bar, "", 17, UiKit.HEADING_COLOR)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drag := UiKit.note(bar, "drag to move", 11)
	drag.autowrap_mode = TextServer.AUTOWRAP_OFF
	drag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toggle = UiKit.secondary(Button.new(), 13)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.pressed.connect(func() -> void: set_collapsed(_body.visible))
	bar.add_child(_toggle)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	box.add_child(_body)
	UiKit.note(_body, "Pick one: it joins Your blueprints below and stays on offer for the whole run.", 12).autowrap_mode = TextServer.AUTOWRAP_OFF
	cards = HBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	_body.add_child(cards)
	set_collapsed(false)


func set_title(text: String, tip := "") -> void:
	_title.text = text
	_title.tooltip_text = tip
	_title.mouse_filter = Control.MOUSE_FILTER_PASS if tip != "" else Control.MOUSE_FILTER_IGNORE


## Folded down to its title bar (true) or open.
func set_collapsed(folded: bool) -> void:
	_body.visible = not folded
	_toggle.text = "Show offers" if folded else "Hide"
	_toggle.tooltip_text = "Show the draft again." if folded else "Fold the draft away to look at the town. It waits until you pick."
	_fit.call_deferred()


func is_collapsed() -> bool:
	return not _body.visible


## Shows the window; the first time, at the top middle of the map (the town stays in view below it),
## after that where it was left.
func open() -> void:
	visible = true
	# Old cards are freed at the end of the frame, so the size settles a frame later.
	_fit.call_deferred()


func _fit() -> void:
	reset_size()
	var area := get_parent_area_size()
	if area.x > 0.0:
		var s := minf(1.0, (area.x - 16.0) / size.x)
		scale = Vector2(s, s)
	if not _placed and area.x > 0.0:
		_placed = true
		position = Vector2((area.x - shown_size().x) * 0.5, 8.0)
	_keep_inside()


## The window's size on screen, after any shrinking.
func shown_size() -> Vector2:
	return size * scale


## The part of the map the window covers.
func shown_rect() -> Rect2:
	return Rect2(position, shown_size())


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		position += event.relative * scale
		_keep_inside()
		accept_event()


## Never lets the window leave the map, so it can't be lost off screen.
func _keep_inside() -> void:
	var area := get_parent_area_size()
	position.x = clampf(position.x, 0.0, maxf(0.0, area.x - shown_size().x))
	position.y = clampf(position.y, 0.0, maxf(0.0, area.y - shown_size().y))
	moved.emit()
