class_name CreditsPanel
extends RefCounted
## The Credits screen (from the title screen): who made what the game uses, built from the licence lines in
## art/manifest.json and audio/manifest.json, so a new sprite or sound is credited the moment its row is added.
## CC-BY work must name its author here (tests/test_sound.gd checks every sound has a licence line).

const ART := "res://art/manifest.json"
const AUDIO := "res://audio/manifest.json"


## Fills `box`; `on_back` closes it.
static func fill(box: VBoxContainer, on_back: Callable) -> void:
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Credits"
	title.add_theme_font_size_override("font_size", UiKit.HEADING)
	title.add_theme_color_override("font_color", UiKit.HEADING_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	UiKit.button(head, "Back", on_back).custom_minimum_size = Vector2(96, 40)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	_section(list, "Sound", sound_lines())
	_section(list, "Art", art_lines())
	_section(list, "Engine", ["Godot Engine, MIT licence (godotengine.org/license)"])


## Each sound source once, with the moments it plays for: "Kenney (kenney.nl), RPG Audio, CC0 1.0: cards dealt, card taken".
static func sound_lines() -> Array[String]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDIO))
	var rows: Dictionary = (parsed as Dictionary).get("sounds", {}) if parsed is Dictionary else {}
	var by_source := {}
	for key: String in rows:
		for line: String in rows[key].get("licence", []):
			if not by_source.has(line):
				by_source[line] = []
			by_source[line].append(str(rows[key].get("name", key)))
	var out: Array[String] = []
	for line: String in by_source:
		out.append("%s: %s" % [line, ", ".join(by_source[line])])
	return out


## Each art source once, with how many pictures come from it.
static func art_lines() -> Array[String]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ART))
	var rows: Dictionary = (parsed as Dictionary).get("sprites", {}) if parsed is Dictionary else {}
	var counts := {}
	for id: String in rows:
		var line := str(rows[id].get("licence", "")).get_slice(" (", 0)
		counts[line] = int(counts.get(line, 0)) + 1
	var out: Array[String] = []
	for line: String in counts:
		out.append("%s: %d %s" % [line, counts[line], "picture" if counts[line] == 1 else "pictures"])
	return out


static func _section(list: VBoxContainer, heading: String, lines: Array[String]) -> void:
	UiKit.note(list, heading.to_upper(), UiKit.BODY, UiKit.DIM)
	for line in lines:
		UiKit.note(list, line, UiKit.BODY).custom_minimum_size.x = 680
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	list.add_child(gap)
