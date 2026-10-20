class_name StoryLog
extends HBoxContainer
## The story's last few lines under the map, with a button for the whole log (Overlays.show_log).

signal open_pressed

const LINES := 3

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
	add_child(_text)
	var open := Button.new()
	open.text = "Log"
	open.tooltip_text = "Everything that has happened this run"
	open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiKit.secondary(open, 13)
	open.pressed.connect(func() -> void: open_pressed.emit())
	add_child(open)


func refresh() -> void:
	if run.story.size() == _shown:
		return
	_shown = run.story.size()
	var lines := PackedStringArray()
	for line in run.story.slice(maxi(0, _shown - LINES)):
		lines.append(as_bbcode(line))
	_text.text = "\n".join(lines)


## One story line, in bold when it marks a turn of the run (a new round, the attack, the end).
static func as_bbcode(line: String) -> String:
	var bold := line.begins_with("Round ") or line.begins_with("The hearth") or line.begins_with("Night 3") or line.begins_with("No one")
	return ("[b]%s[/b]" if bold else "%s") % line
