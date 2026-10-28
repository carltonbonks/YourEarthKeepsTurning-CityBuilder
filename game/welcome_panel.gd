class_name WelcomePanel
extends RefCounted
## "How a round works": the one screen before the traditions pick of every run (Yusuf, 2026-10-24), also
## opened from How to play on the title screen and the menu. Its words are in data/tips.json.

const EMBER := Color("#e39a4a")
const BODY := Color("#c7bdab")


## Fills `box` with the screen. `go_text` names the button that moves on, which calls `on_go`.
static func fill(box: VBoxContainer, content: Content, settings: GameSettings, go_text: String, on_go: Callable) -> void:
	var w: Dictionary = content.tips["welcome"]
	var title := Label.new()
	title.text = w["title"]
	title.add_theme_font_size_override("font_size", UiKit.HEADING)
	title.add_theme_color_override("font_color", UiKit.HEADING_COLOR)
	box.add_child(title)
	UiKit.note(box, w["intro"], UiKit.STRONG, UiKit.HINT_COLOR).custom_minimum_size.x = 900

	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 14)
	box.add_child(steps)
	for step: Dictionary in w["steps"]:
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#1c1915")
		style.border_color = Color("#3a332a")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(16)
		panel.add_theme_stylebox_override("panel", style)
		panel.custom_minimum_size.x = 290
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		steps.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		panel.add_child(col)
		UiKit.note(col, str(step["when"]).to_upper(), UiKit.CAPTION, UiKit.DIM)
		var heading := Label.new()
		heading.text = step["name"]
		heading.add_theme_font_size_override("font_size", UiKit.HEADING)
		col.add_child(heading)
		UiKit.note(col, step["text"], UiKit.BODY, BODY).custom_minimum_size.x = 250

	var rounds := content.int_num("rounds_to_win")
	# One line under the other, each wrapping across the full width: side by side, a long line squeezed the other.
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	box.add_child(lines)
	UiKit.note(lines, str(w["rounds_line"]) % rounds, UiKit.BODY, Color("#ece5d8"))
	UiKit.note(lines, w["earth_line"], UiKit.BODY, UiKit.HINT_COLOR)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	box.add_child(strip)
	for i in rounds:
		var bar := ColorRect.new()
		bar.color = EMBER if i == 0 else Color("#3a332a")
		bar.custom_minimum_size.y = 8
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		strip.add_child(bar)
	var ends := HBoxContainer.new()
	box.add_child(ends)
	for text: String in ["Round 1", w["ages_line"], "Round %d" % rounds]:
		var l := UiKit.note(ends, text, UiKit.CAPTION, UiKit.HINT_COLOR)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if text == w["ages_line"] \
			else (HORIZONTAL_ALIGNMENT_LEFT if text == "Round 1" else HORIZONTAL_ALIGNMENT_RIGHT)

	var closing := UiKit.note(box, w["closing"], UiKit.TITLE, Color("#d9cbb3"))
	closing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(HSeparator.new())

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	box.add_child(foot)
	var keys := UiKit.note(foot, "%s pause  ·  %s menu  ·  %s tilt the map  ·  point at anything for details" % [
		GameSettings.key_name(settings.keys["pause"]), GameSettings.key_name(settings.keys["menu"]),
		GameSettings.key_name(settings.keys["tilt_map"])], 13, UiKit.HINT_COLOR)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tips := CheckBox.new()
	tips.text = "Tips as I play"
	tips.button_pressed = settings.tips
	tips.focus_mode = Control.FOCUS_NONE
	tips.toggled.connect(func(on: bool) -> void:
		settings.tips = on
		settings.save())
	foot.add_child(tips)
	var go := UiKit.primary(UiKit.button(foot, go_text, on_go))
	go.custom_minimum_size.y = 44
