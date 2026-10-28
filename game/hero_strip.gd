class_name HeroStrip
extends ScrollContainer
## The heroes as a row of small portraits under the map: a short upright health bar (health lost shows
## red), name and level, a mood dot and what they are doing. Gear, bed, today's whim and the rest are in the hover card (Tooltips.hero).
## Clicking a portrait points the map at that hero. Heroes no longer in town share one grey chip.
## A big roster narrows the portraits (to MIN_CHIP_WIDTH) so they all fit without scrolling.

signal hero_pressed(hero: Unit)

const CHIP_WIDTH := 116.0
const MIN_CHIP_WIDTH := 72.0
const BAR_SIZE := Vector2(5, 30)
const HEALTH_COLOR := Color("#7fd07f")
const LOW_HEALTH_COLOR := Color("#e0a050")
const LOST_COLOR := Color("#b03a3a")

var run: RunState
var _row: HBoxContainer
## The heroes the row was built for, so it is only rebuilt when someone joins or leaves.
var _shown: Array = []
## Per portrait: [hero, health bar, mood dot, intent label, name label, the portrait].
var _parts: Array = []


func _init() -> void:
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# A big roster still scrolls (wheel or drag), but no bar eats the strip's height.
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	custom_minimum_size.y = 46
	resized.connect(_fit_chips)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	add_child(_row)


func refresh() -> void:
	var living := run.living_heroes()
	var shown: Array = []
	shown.assign(living)
	shown.append(run.fallen.size() + run.departed.size())
	if shown != _shown:
		_rebuild(living)
		_shown = shown
	var content := run.content
	for parts: Array in _parts:
		var hero: Unit = parts[0]
		set_health(parts[1], hero.hp / maxf(1.0, hero.max_hp))
		var mood := "#a8d890" if hero.mood > content.num("mood_grumble_at") else ("#e0a050" if hero.mood > content.num("mood_leave_at") else "#e05050")
		var doing := hero.intent if hero.intent != "" and run.phase == RunState.Phase.SIM else ("tired" if hero.energy <= 0.0 else "")
		(parts[2] as Label).add_theme_color_override("font_color", Color(mood))
		(parts[3] as Label).text = doing
		(parts[4] as Label).text = "%s  Lv %d" % [hero.display_name, hero.level]


func _rebuild(living: Array[Unit]) -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_parts.clear()
	if living.is_empty() and run.fallen.is_empty() and run.departed.is_empty():
		UiKit.note(_row, "No heroes yet. Build a lodging and they come to the dawn picks.", 12)
		return
	for hero in living:
		var chip := TipChip.new()
		chip.custom_minimum_size.x = CHIP_WIDTH
		chip.tip = func() -> Dictionary: return Tooltips.hero(run, hero) if hero.alive else {}
		chip.pressed.connect(func() -> void: hero_pressed.emit(hero))
		var side := HBoxContainer.new()
		side.add_theme_constant_override("separation", 5)
		chip.add_child(side)
		var hp := health_bar(side)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side.add_child(box)
		var name := Label.new()
		name.add_theme_font_size_override("font_size", 13)
		name.add_theme_color_override("font_color", Color(run.content.hero_classes[hero.type_id]["color"]))
		name.clip_text = true
		box.add_child(name)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		box.add_child(line)
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_font_size_override("font_size", 11)
		line.add_child(dot)
		var doing := Label.new()
		doing.clip_text = true
		doing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		doing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		doing.add_theme_font_size_override("font_size", 11)
		doing.add_theme_color_override("font_color", UiKit.HINT_COLOR)
		line.add_child(doing)
		_row.add_child(chip)
		_parts.append([hero, hp, dot, doing, name, chip])
	var lost := run.fallen.size() + run.departed.size()
	if lost > 0:
		var chip := TipChip.new()
		chip.tip = func() -> Dictionary: return StatusText.lost_heroes_tip(run)
		var l := Label.new()
		l.text = "%d lost" % lost
		l.add_theme_color_override("font_color", LOST_COLOR.lightened(0.25))
		l.add_theme_font_size_override("font_size", 12)
		chip.add_child(l)
		_row.add_child(chip)
	_fit_chips()


## Shares the strip's width between the portraits: full width when there's room, narrower for a big roster.
func _fit_chips() -> void:
	if _parts.is_empty() or size.x <= 0.0:
		return
	var sep := float(_row.get_theme_constant("separation"))
	var lost := 0.0
	if _row.get_child_count() > _parts.size():
		lost = (_row.get_child(-1) as Control).get_combined_minimum_size().x + sep
	var each := floorf((size.x - lost - sep * (_parts.size() - 1)) / _parts.size()) - 1.0
	for parts: Array in _parts:
		(parts[5] as Control).custom_minimum_size.x = clampf(each, MIN_CHIP_WIDTH, CHIP_WIDTH)


## A short upright health bar: the health left fills from the bottom, the health lost shows red above it.
static func health_bar(parent: Control) -> ColorRect:
	var back := ColorRect.new()
	back.color = LOST_COLOR
	back.custom_minimum_size = BAR_SIZE
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.color = HEALTH_COLOR
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	back.add_child(fill)
	return back


## Fills the bar to `share` of its height (amber once health is low).
static func set_health(back: ColorRect, share: float) -> void:
	var fill := back.get_child(0) as ColorRect
	fill.anchor_top = 1.0 - clampf(share, 0.0, 1.0)
	fill.offset_top = 0.0
	fill.offset_bottom = 0.0
	fill.color = LOW_HEALTH_COLOR if share < 0.35 else HEALTH_COLOR
