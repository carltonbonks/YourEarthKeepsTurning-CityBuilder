class_name SettingsPanel
extends RefCounted
## The Settings screen (from the title screen and the menu): screen, play and keys, in three columns.
## Every change saves and takes effect at once. Sound joins when the game has sounds.



## Fills `box`; `on_back` closes it, `on_change` runs after any change (the screen applies it).
static func fill(box: VBoxContainer, settings: GameSettings, on_change: Callable, on_back: Callable) -> void:
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", UiKit.HEADING)
	title.add_theme_color_override("font_color", UiKit.HEADING_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	UiKit.button(head, "Back", on_back).custom_minimum_size = Vector2(96, 40)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	box.add_child(cols)
	var changed := func() -> void:
		settings.save()
		on_change.call()

	var screen := _column(cols, "Screen")
	var fs := CheckBox.new()
	fs.button_pressed = settings.fullscreen
	fs.toggled.connect(func(on: bool) -> void:
		settings.fullscreen = on
		changed.call())
	_row(screen, "Fullscreen", fs)
	var scale := OptionButton.new()
	for s: float in GameSettings.UI_SCALES:
		scale.add_item("%d%%" % roundi(s * 100.0))
	scale.select(maxi(0, GameSettings.UI_SCALES.find(_nearest(GameSettings.UI_SCALES, settings.ui_scale))))
	scale.item_selected.connect(func(i: int) -> void:
		settings.ui_scale = GameSettings.UI_SCALES[i]
		changed.call())
	_row(screen, "Interface size", scale)
	var art := CheckBox.new()
	art.button_pressed = settings.art
	art.toggled.connect(func(on: bool) -> void:
		settings.art = on
		changed.call())
	_row(screen, "Rendered art", art)
	UiKit.note(screen, "Interface size makes the cards and text bigger or smaller. Rendered art off draws everything as plain shapes. V tilts the map in play (the flat map is always shapes).", UiKit.CAPTION).custom_minimum_size.x = 260

	var play := _column(cols, "Play")
	var speed := OptionButton.new()
	var speeds: Array = TopBar.SPEEDS.filter(func(s: int) -> bool: return s > 0)
	for s: int in speeds:
		speed.add_item("%d×" % s)
	speed.select(maxi(0, speeds.find(settings.start_speed)))
	speed.item_selected.connect(func(i: int) -> void:
		settings.start_speed = speeds[i]
		changed.call())
	_row(play, "Speed a run starts at", speed)
	var cam := CheckBox.new()
	cam.button_pressed = settings.night_camera
	cam.toggled.connect(func(on: bool) -> void:
		settings.night_camera = on
		changed.call())
	_row(play, "Bring the camera in at night", cam)
	var tour := CheckBox.new()
	tour.button_pressed = settings.tour
	tour.toggled.connect(func(on: bool) -> void:
		settings.tour = on
		changed.call())
	_row(play, "Open each run on the tour", tour)
	var tips := CheckBox.new()
	tips.button_pressed = settings.tips
	tips.toggled.connect(func(on: bool) -> void:
		settings.tips = on
		changed.call())
	_row(play, "First-time tips", tips)
	var again := Button.new()
	again.text = "Show again"
	UiKit.secondary(again)
	again.disabled = settings.tips_seen.is_empty()
	again.pressed.connect(func() -> void:
		settings.tips_seen.clear()
		settings.tips = true
		tips.set_pressed_no_signal(true)
		again.disabled = true
		changed.call())
	_row(play, "Seen all the tips?", again)
	var advisor := OptionButton.new()
	var levels := ["urgent", "chatty", "off"]
	for name: String in ["Urgent only", "Chatty", "Off"]:
		advisor.add_item(name)
	advisor.select(maxi(0, levels.find(settings.advisor)))
	advisor.item_selected.connect(func(i: int) -> void:
		settings.advisor = levels[i]
		changed.call())
	_row(play, "The Elder's warnings", advisor)
	UiKit.note(play, "Sound and music settings arrive with the first sounds.", UiKit.CAPTION).custom_minimum_size.x = 260

	var keys := _column(cols, "Keys")
	var buttons := {}
	for action: String in GameSettings.ACTIONS:
		var b := RebindButton.new()
		b.action = action
		b.settings = settings
		b.on_bound = func() -> void:
			for other: String in buttons:
				(buttons[other] as RebindButton).show_key()
			changed.call()
		b.show_key()
		buttons[action] = b
		_row(keys, GameSettings.ACTIONS[action], b)
	UiKit.note(keys, "Click a key, then press the new one. A key already in use swaps places.", UiKit.CAPTION).custom_minimum_size.x = 260


static func _column(parent: Control, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 280
	col.add_theme_constant_override("separation", 4)
	parent.add_child(col)
	UiKit.note(col, heading.to_upper(), UiKit.BODY, UiKit.DIM)
	return col


static func _row(col: VBoxContainer, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	col.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if control is Button and not control is CheckBox:
		control.custom_minimum_size.x = 96
	row.add_child(control)


static func _nearest(values: Array, v: float) -> float:
	var best: float = values[0]
	for x: float in values:
		if absf(x - v) < absf(best - v):
			best = x
	return best


## A key in the Keys column: click it, then press the new key.
class RebindButton:
	extends Button

	var action := ""
	var settings: GameSettings
	var on_bound := Callable()
	var _listening := false

	func _init() -> void:
		UiKit.secondary(self)
		focus_mode = Control.FOCUS_ALL
		pressed.connect(func() -> void:
			_listening = true
			text = "Press a key"
			grab_focus())

	func show_key() -> void:
		_listening = false
		text = GameSettings.key_name(settings.keys[action])

	func _gui_input(event: InputEvent) -> void:
		var key := event as InputEventKey
		if not _listening or key == null or not key.pressed or key.echo:
			return
		accept_event()
		settings.rebind(action, key.keycode)
		show_key()
		release_focus()
		on_bound.call()
