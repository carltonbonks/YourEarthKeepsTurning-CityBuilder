class_name TopBar
extends HBoxContainer
## The thin bar along the top: round and age, hearth, people, food and fuel (as days and nights
## left), the goods building cards cost, and relics. Each chip shows its full story on hover
## (StatusText.chip_tip). On the right: pause and speed, and the menu.

signal speed_changed(speed: int)
signal skip_pressed
signal menu_pressed

const SPEEDS := [0, 1, 2, 4, 8]

var run: RunState
var _chips := {}
var _speed_buttons := {}


func _init(dev_mode: bool) -> void:
	add_theme_constant_override("separation", 6)
	for id: String in StatusText.CHIPS:
		var chip := TipChip.new()
		chip.tip = func() -> Dictionary: return StatusText.chip_tip(run, id) if run != null else {}
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.scroll_active = false
		label.add_theme_font_size_override("normal_font_size", 13)
		label.add_theme_font_size_override("bold_font_size", 13)
		chip.add_child(label)
		add_child(chip)
		_chips[id] = label
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)
	var group := ButtonGroup.new()
	for s: int in SPEEDS:
		var b := Button.new()
		b.text = "II" if s == 0 else "%dx" % s
		b.tooltip_text = "Pause (Space)" if s == 0 else "Play at %dx speed (Space pauses)" % s
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: speed_changed.emit(s))
		add_child(b)
		_speed_buttons[s] = b
	if dev_mode:
		var skip := Button.new()
		skip.text = ">>|"
		skip.tooltip_text = "Skip to the next decision (dev)"
		skip.focus_mode = Control.FOCUS_NONE
		skip.pressed.connect(func() -> void: skip_pressed.emit())
		add_child(skip)
	var menu := Button.new()
	menu.text = "Menu"
	menu.tooltip_text = "Seed, new run, Run history (Esc)"
	menu.focus_mode = Control.FOCUS_NONE
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	add_child(menu)


func refresh() -> void:
	for id: String in _chips:
		(_chips[id] as RichTextLabel).text = StatusText.chip(run, id)


## Lights the button for the current speed (0 is paused).
func show_speed(speed: int) -> void:
	if _speed_buttons.has(speed):
		(_speed_buttons[speed] as Button).set_pressed_no_signal(true)
