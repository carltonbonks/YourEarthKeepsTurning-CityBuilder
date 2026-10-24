class_name TitleScreen
extends Control
## The title screen the game opens on: New run, Play a seed, How to play, Run history, Settings and Quit
## (desktop only). Behind the menu, rings of earth turn slowly round a campfire. There is no Continue
## (no mid-run saves for now, Yusuf 2026-10-24). Choices go back to the screen as signals.

## seed_value is -1 for a random seed.
signal start_pressed(seed_value: int)
signal how_to_play_pressed
signal history_pressed
signal settings_pressed

const GROUND := Color("#14120f")
const EMBER := Color("#e39a4a")
const MUTED := Color("#b5ab9a")
## Rings of plates: radius, width, plate length in radians, turning speed (radians per second).
const RINGS := [
	[170.0, 30.0, 0.55, 0.026],
	[240.0, 36.0, 0.5, -0.02],
	[320.0, 42.0, 0.46, 0.015],
	[405.0, 46.0, 0.42, -0.011],
]

var _turn := 0.0
var _seed_edit: LineEdit


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.position = Vector2(96, 80)
	column.custom_minimum_size.x = 420
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var kicker := Label.new()
	kicker.text = "A HANDS-OFF FRONTIER ROGUELITE"
	kicker.add_theme_font_size_override("font_size", 13)
	kicker.add_theme_color_override("font_color", EMBER)
	column.add_child(kicker)
	var title := Label.new()
	title.text = "Your Earth\nKeeps Turning"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("#ece5d8"))
	title.add_theme_constant_override("line_spacing", -6)
	column.add_child(title)
	var tagline := UiKit.note(column, "Raise a people from campfire to stone keep. You shape the town; they choose their own fights.", 16, MUTED)
	tagline.custom_minimum_size.x = 420
	var gap := Control.new()
	gap.custom_minimum_size.y = 24
	column.add_child(gap)

	_menu_button(column, "New run", func() -> void: start_pressed.emit(-1), true)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	column.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Play a seed"
	seed_label.add_theme_color_override("font_color", MUTED)
	seed_label.custom_minimum_size.x = 96
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "e.g. 4821"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.custom_minimum_size.y = 40
	_seed_edit.text_submitted.connect(func(_t: String) -> void: _start_seed())
	seed_row.add_child(_seed_edit)
	var go := UiKit.button(seed_row, "Start", _start_seed)
	go.custom_minimum_size = Vector2(72, 40)
	_menu_button(column, "How to play", func() -> void: how_to_play_pressed.emit())
	_menu_button(column, "Run history", func() -> void: history_pressed.emit())
	_menu_button(column, "Settings", func() -> void: settings_pressed.emit())
	if not OS.has_feature("web"):
		_menu_button(column, "Quit", func() -> void: get_tree().quit())

	var footer := Label.new()
	footer.text = "v%s · playtest build" % str(ProjectSettings.get_setting("application/config/version", ""))
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color("#8f8676"))
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.position = Vector2(96, -44)
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(footer)


func _menu_button(parent: Control, text: String, on_press: Callable, main := false) -> Button:
	var b := UiKit.button(parent, text, on_press)
	if main:
		UiKit.primary(b, 18)
	else:
		UiKit.secondary(b, 17)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(420, 46)
	return b


func _start_seed() -> void:
	start_pressed.emit(int(_seed_edit.text) if _seed_edit.text.strip_edges().is_valid_int() else -1)


func _process(delta: float) -> void:
	if visible:
		_turn += delta
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), GROUND)
	var c := Vector2(size.x - 280.0, size.y * 0.5)
	# The fire's glow, then the still ground round the hearth, then the turning rings of plates.
	for i in 12:
		var f := 1.0 - i / 12.0
		draw_circle(c, 40.0 + 200.0 * (1.0 - f), Color(0.77, 0.42, 0.16, 0.05 * f))
	draw_circle(c, 9.0, Color("#f6c27a"))
	draw_arc(c, 60.0, 0.0, TAU, 48, Color("#5a4a36"), 2.0)
	draw_arc(c, 96.0, 0.0, TAU, 64, Color("#4d4132"), 2.0)
	var shades := [Color("#3f372c"), Color("#342e25"), Color("#2a251f"), Color("#211d18")]
	for r in RINGS.size():
		var ring: Array = RINGS[r]
		var radius: float = ring[0]
		var plate: float = ring[2]
		var start: float = _turn * float(ring[3])
		var a := 0.0
		while a < TAU - 0.01:
			var length := minf(plate * (0.7 + 0.3 * sin(a * 3.0 + r)), TAU - a)
			draw_arc(c, radius, start + a, start + a + length - 0.04, 24, shades[r], ring[1])
			a += length
