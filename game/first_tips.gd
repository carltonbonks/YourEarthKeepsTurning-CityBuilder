class_name FirstTips
extends PanelContainer
## One-time tips: a small parchment note, the first time each thing happens (the first build, dawn,
## night, relic, hero card, turn of the earth, age card), sitting by the part of the screen it is about.
## Each shows once (GameSettings.tips_seen), one at a time; it never pauses the game. Words and places
## are in data/tips.json; `due` says which moments are here, read-only.

const PAPER := Color("#f2e8d6")
const INK := Color("#1c1710")
const WIDTH := 340.0

## Where a tip goes: called with the tip's `at` (hand, threat, top, map) and its size, returns its position.
var anchor := Callable()
var settings: GameSettings
var content: Content
var _shown := ""
var _kicker: Label
var _text: Label


## The tips whose moment is here in this run (seen or not), in data order.
static func due(run: RunState) -> Array[String]:
	var now := {}
	var deciding := run.awaiting_traditions() or run.awaiting_pedlar()
	match run.phase:
		RunState.Phase.BUILD:
			if not deciding:
				now["first_build"] = true
				now["first_attack"] = true
				now["first_earth"] = run.round_number >= 2
				now["first_age"] = not run.hand.milestone.is_empty()
		RunState.Phase.PICK:
			now["first_dawn"] = true
			now["first_hero"] = run.pick_offer.any(func(c: Dictionary) -> bool: return c["kind"] == "hero")
		RunState.Phase.SIM:
			now["first_night"] = run.world.is_night()
		RunState.Phase.RELIC:
			now["first_relic"] = true
	var out: Array[String] = []
	for id: String in run.content.tips["tips"]:
		if now.get(id, false):
			out.append(id)
	return out


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size.x = WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_kicker = UiKit.note(box, "", 11, Color("#8a4a12"))
	_text = UiKit.note(box, "", 15, INK)
	_text.custom_minimum_size.x = WIDTH - 28.0
	var row := HBoxContainer.new()
	box.add_child(row)
	var off := Button.new()
	off.text = "Turn tips off"
	off.flat = true
	off.focus_mode = Control.FOCUS_NONE
	off.add_theme_color_override("font_color", Color("#5a4a36"))
	off.add_theme_color_override("font_hover_color", INK)
	off.add_theme_font_size_override("font_size", 13)
	off.pressed.connect(func() -> void:
		settings.tips = false
		settings.save()
		_close())
	row.add_child(off)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var ok := Button.new()
	ok.text = "Got it"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Vector2(84, 36)
	var dark := StyleBoxFlat.new()
	dark.bg_color = INK
	dark.set_corner_radius_all(5)
	for state: String in ["normal", "hover", "pressed"]:
		ok.add_theme_stylebox_override(state, dark)
	ok.add_theme_color_override("font_color", PAPER)
	ok.add_theme_color_override("font_hover_color", Color.WHITE)
	ok.pressed.connect(func() -> void:
		if not settings.tips_seen.has(_shown):
			settings.tips_seen.append(_shown)
		settings.save()
		_close())
	row.add_child(ok)
	hide()


## Shows the first unseen tip whose moment is here, or keeps the one showing; `blocked` (a menu or the
## title screen is up) hides it for now without marking it seen.
func check(run: RunState, blocked: bool) -> void:
	if blocked or settings == null or not settings.tips:
		hide()
		return
	var now := due(run)
	if _shown != "" and not now.has(_shown):
		_shown = ""  # Its moment passed unread; it comes back next time.
	if _shown == "":
		for id in now:
			if not settings.tips_seen.has(id):
				_shown = id
				break
	if _shown == "":
		hide()
		return
	var tip: Dictionary = content.tips["tips"][_shown]
	var total: int = content.tips["tips"].size()
	_kicker.text = "%s  ·  TIP %d OF %d" % [str(tip["title"]).to_upper(), settings.tips_seen.size() + 1, total]
	_text.text = tip["text"]
	reset_size()
	show()
	if anchor.is_valid():
		position = anchor.call(tip["at"], get_combined_minimum_size())


func shown_id() -> String:
	return _shown if visible else ""


func _close() -> void:
	_shown = ""
	hide()
