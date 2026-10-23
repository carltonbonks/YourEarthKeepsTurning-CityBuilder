class_name StoryLog
extends HBoxContainer
## The story's last few lines under the map, with a button for the whole log (Overlays.show_log)
## and, in tiny text under it, which build is running (build_label). On a narrow window, where long
## lines wrap, it shows fewer lines rather than cutting the newest off.

signal open_pressed
## The Who did what button (Overlays.show_impact).
signal impact_pressed

const LINES := 3
## Written by CI just before the web export (see .github/workflows/ci.yml); absent in local runs.
const BUILD_INFO := "res://build_info.txt"

var run: RunState:
	set(value):
		run = value
		_shown = -1
var _text: RichTextLabel
var _shown := -1


func _init() -> void:
	add_theme_constant_override("separation", 6)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.y = 68
	_text.add_theme_font_size_override("normal_font_size", 12)
	_text.add_theme_font_size_override("bold_font_size", 12)
	_text.resized.connect(func() -> void: _shown = -1)
	add_child(_text)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 2)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(side)
	var open := Button.new()
	open.text = "Log"
	open.tooltip_text = "Everything that has happened this run"
	UiKit.secondary(open, 13)
	open.pressed.connect(func() -> void: open_pressed.emit())
	side.add_child(open)
	var impact := Button.new()
	impact.text = "Impact"
	impact.tooltip_text = "Who did what: damage dealt and taken, kills and work, for each hero, kind of townsfolk and the hearth"
	UiKit.secondary(impact, 13)
	impact.pressed.connect(func() -> void: impact_pressed.emit())
	side.add_child(impact)
	var version := UiKit.note(side, build_label(), 9)
	version.autowrap_mode = TextServer.AUTOWRAP_OFF
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.tooltip_text = "The build you're playing"
	version.mouse_filter = Control.MOUSE_FILTER_PASS


func refresh() -> void:
	if run.story.size() == _shown:
		return
	_shown = run.story.size()
	var from := maxi(0, _shown - LINES)
	while true:
		var lines := PackedStringArray()
		for line in run.story.slice(from):
			lines.append(as_bbcode(line))
		_text.text = "\n".join(lines)
		if from >= _shown - 1 or _text.size.y <= 0.0 or _text.get_content_height() <= _text.size.y:
			break
		from += 1


## Which build is running, such as "PR #41 · 1a2b3c4", or "dev build" when run outside CI.
static func build_label(path := BUILD_INFO) -> String:
	if not FileAccess.file_exists(path):
		return "dev build"
	var label := FileAccess.get_file_as_string(path).strip_edges()
	return label if label != "" else "dev build"


## One story line, in bold when it marks a turn of the run (a new round, the attack, the end).
static func as_bbcode(line: String) -> String:
	var bold := line.begins_with("Round ") or line.begins_with("The hearth") or line.begins_with("Night 3") or line.begins_with("No one")
	return ("[b]%s[/b]" if bold else "%s") % line
