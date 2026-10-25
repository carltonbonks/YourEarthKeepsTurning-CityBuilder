extends Control
## The game screen: a thin bar of key numbers on top, the map filling the middle, and the heroes and
## the story's last lines underneath. Decisions are cards: the building hand over the map while
## building, the dawn and relic picks in the middle. Detail lives in hover cards, not on screen.
## UI is built in code for now (placeholder layout); all rules live in sim/.
##
## This file runs the flow (new run, ticking the sim, pausing for decisions, pause and speed, the Esc
## menu) and lays out the screen. The parts live in their own files: TopBar, BuildHandView (the
## building cards, and the blueprint draft's cards for its pick screen), ThreatCard (the attack), Alerts, HeroStrip, StoryLog, Overlays
## (picks, relics, end screen, menu, Run history, dev tuning) and ArenaView (the map). HudLayout keeps
## the panels over the map out of each other's way. The game opens on the TitleScreen (skipped when the
## page address names a seed), each run opens on how a round works (WelcomePanel) before the traditions,
## and FirstTips points out each thing the first time it happens. GameSettings holds the player's settings.

## How often the live panels are rebuilt while the sim runs (the map redraws every frame).
const LIVE_REFRESH_SECONDS := 0.1

var content: Content
var run: RunState
var settings: GameSettings
var speed := 2
## The speed Space returns to after a pause.
var _play_speed := 2
var _tick_acc := 0.0
var _live_acc := 0.0
var _menu_open := false
## Id of this run's file in Run history.
var _run_id := ""
## Off in tests, so they never write runs to disk.
var save_runs := true

var _top: TopBar
var _hand_view: BuildHandView
var _threat: ThreatCard
var _alerts: Alerts
var _arena: ArenaView
var _map_box: Control
## The clock and alerts in the map's top-left corner.
var _corner: VBoxContainer
var _clock_label: RichTextLabel
var _heroes: HeroStrip
var _story: StoryLog
var _overlays: Overlays
var _title_screen: TitleScreen
var _tips: FirstTips


func _ready() -> void:
	content = Content.load_default()
	settings = GameSettings.load_saved()
	settings.persist = save_runs
	settings.apply(get_window() if is_inside_tree() else null)
	_build_ui()
	var url_seed := _url_seed()
	_new_run(url_seed if url_seed >= 0 else _random_seed())
	# A playtest link with ?seed= goes straight into that run.
	if url_seed < 0:
		_show_title()


func _process(delta: float) -> void:
	if run.phase != RunState.Phase.SIM or _overlays.visible or _title_screen.visible:
		return
	_live_acc += delta
	if speed == 0:
		if _live_acc >= LIVE_REFRESH_SECONDS:
			_live_acc = 0.0
			_refresh_live()
		return
	_tick_acc += delta * speed
	var dt := run.world.dt
	while _tick_acc >= dt and run.phase == RunState.Phase.SIM:
		_tick_acc -= dt
		run.step()
	if run.phase != RunState.Phase.SIM:
		_on_pause()
	elif _live_acc >= LIVE_REFRESH_SECONDS:
		_live_acc = 0.0
		_refresh_live()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if event.is_action_pressed("menu"):
		if _title_screen.visible:
			_overlays.hide()
		else:
			_close_menu() if _menu_open else _open_menu()
		get_viewport().set_input_as_handled()
	elif _title_screen.visible or _overlays.visible:
		return
	elif event.is_action_pressed("pause") and _arena.turn_playing():
		_arena.skip_turn()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_set_speed(_play_speed if speed == 0 else 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("faster") or event.is_action_pressed("slower"):
		var speeds: Array = TopBar.SPEEDS.filter(func(s: int) -> bool: return s > 0)
		var at := speeds.find(_play_speed)
		at = clampi(at + (1 if event.is_action_pressed("faster") else -1), 0, speeds.size() - 1)
		_set_speed(speeds[at])
		get_viewport().set_input_as_handled()


# --- Flow ------------------------------------------------------------------

func _new_run(seed_value: int) -> void:
	if run != null:
		run.dispose()
	run = RunState.new(content, seed_value)
	_run_id = RunHistory.new_run_id(seed_value)
	_arena.run = run
	_arena.reset_camera()
	for part: Variant in [_top, _hand_view, _threat, _alerts, _heroes, _story, _overlays]:
		part.set("run", run)
	_alerts.reset()
	_story.refresh()
	_menu_open = false
	_title_screen.hide()
	_overlays.welcome_pending = true
	_set_speed(settings.start_speed)
	_refresh()
	_overlays.show_for_phase()


func _show_title() -> void:
	_menu_open = false
	_overlays.hide()
	_title_screen.show()
	_tips.hide()


## A setting changed: put it into effect.
func _apply_settings() -> void:
	settings.apply(get_window() if is_inside_tree() else null)
	_arena.night_camera = settings.night_camera


func _found(ids: Array) -> void:
	run.choose_traditions(ids)
	_overlays.hide()
	_refresh()
	_overlays.show_for_phase()


func _found_by_chance() -> void:
	run.choose_random_tradition()
	_overlays.hide()
	_refresh()
	_overlays.show_for_phase()


func _invite_pedlar(id: String) -> void:
	run.choose_pedlar(id)
	_overlays.hide()
	_refresh()


func _begin_round() -> void:
	if run.phase != RunState.Phase.BUILD or _hand_view.draft_pending():
		return
	run.begin_round()
	_tick_acc = 0.0
	_on_pause()


## Runs straight to the next decision (dawn pick or end of round).
func _skip_ahead() -> void:
	if run.phase == RunState.Phase.SIM:
		run.run_until_pause()
		_on_pause()


## The sim stopped for a decision: save the run and show the right overlay.
func _on_pause() -> void:
	_save()
	_refresh()
	_overlays.show_for_phase()


func _take_pick(index: int) -> void:
	run.choose_pick(index)
	_overlays.hide()
	_refresh()
	# A venture holds the day for a moment to show who never came home; carrying on from it shows what
	# the run waits on next.
	if not run.last_venture.is_empty():
		_overlays.show_venture_result()
	else:
		# A second newcomer the same dawn (Twin Fires, Antler Crown) keeps the dawn pick open.
		_overlays.show_for_phase()


func _pick_relic(relic_id: String) -> void:
	run.choose_relic(relic_id)
	_save()
	_refresh()
	# The next round's build phase may open on a choice of its own (a pedlar round).
	_overlays.show_for_phase()


func _save() -> void:
	if save_runs:
		RunHistory.save(_run_id, run)


func _restart(replay: bool) -> void:
	_new_run(run.run_seed if replay else _random_seed())


func _set_speed(s: int) -> void:
	speed = s
	if s > 0:
		_play_speed = s
	_top.show_speed(s)


func _open_menu() -> void:
	_menu_open = true
	_overlays.show_menu(_dev_mode())


## The menu, the log or a dev panel closed: back to whatever the run is waiting on (or the title screen).
func _close_menu() -> void:
	_menu_open = false
	if _title_screen.visible:
		_overlays.hide()
		return
	_refresh()
	_overlays.show_for_phase()


# --- Refresh ---------------------------------------------------------------

func _refresh() -> void:
	_hand_view.visible = run.phase == RunState.Phase.BUILD
	if _hand_view.visible:
		_hand_view.refresh()
		_show_draft()
	else:
		_arena.preview_plot = -1
	_refresh_live()


## The blueprint draft is a pick screen the player must answer before building, like the dawn pick;
## once it is taken the screen goes and the hand is free. Left alone while a menu, the title screen or
## another pick (traditions, pedlar) is up.
func _show_draft() -> void:
	if _menu_open or _title_screen.visible or run.awaiting_traditions() or run.awaiting_pedlar():
		return
	if _hand_view.draft_pending():
		_overlays.show_draft(_hand_view)
	elif _overlays.showing_draft:
		_overlays.hide()


## A building card is hovered: the map blinks the plot it would go on ("" clears it).
func _preview_building(type: String) -> void:
	_arena.preview_plot = run.world.town.choose_plot(type) if type != "" else -1


## Parts that change while the sim runs.
func _refresh_live() -> void:
	_top.refresh()
	_clock_label.text = StatusText.clock(run)
	_threat.refresh()
	_alerts.refresh()
	_heroes.refresh()
	_story.refresh()
	_layout_hud()
	if _tips != null:
		_tips.check(run, _menu_open or _title_screen.visible)


## Where a one-time tip sits: by the part of the screen it is about, kept on screen.
func _tip_position(at: String, tip_size: Vector2) -> Vector2:
	var map := _map_box.get_global_rect()
	var p := Vector2(map.get_center().x - tip_size.x * 0.5, map.position.y + 12.0)
	match at:
		"hand":
			p = Vector2(map.position.x + 24.0, _hand_view.get_global_rect().position.y - tip_size.y - 12.0)
		"threat":
			var card := _threat.get_global_rect()
			p = Vector2(card.position.x - tip_size.x - 12.0, card.position.y)
		"map":
			p = Vector2(map.get_center().x - tip_size.x * 0.5, map.position.y + map.size.y * 0.3)
	var screen := size - tip_size - Vector2(8, 8)
	return Vector2(clampf(p.x, 8.0, maxf(8.0, screen.x)), clampf(p.y, 8.0, maxf(8.0, screen.y)))


## Gives each panel over the map its own room (HudLayout): the hand
## its strip along the bottom, and the corner columns take the tallest free stretch of their edge and
## fold what doesn't fit there.
func _layout_hud() -> void:
	if _hand_view == null:
		return  # Still building the screen.
	var area := _map_box.size
	if area.x <= 0.0 or area.y <= 0.0:
		return
	var m := HudLayout.MARGIN
	var bottom := area.y - m
	if _hand_view.visible:
		bottom -= maxf(_hand_view.size.y, _hand_view.get_combined_minimum_size().y)
	var blocks: Array[Rect2] = []
	var left_x := m + 2.0
	var left := HudLayout.free_span(left_x, left_x + Alerts.WIDTH, m, bottom, blocks)
	_corner.position = Vector2(left_x, left.x)
	var sep := float(_corner.get_theme_constant("separation"))
	_alerts.fit(left.y - left.x - _clock_label.get_combined_minimum_size().y - sep)
	_corner.reset_size()
	var right_x := area.x - ThreatCard.WIDTH - m - 2.0
	var right := HudLayout.free_span(right_x, area.x, m, bottom, blocks)
	_threat.fit(right.y - right.x)
	_threat.position = Vector2(right_x, right.x)
	_threat.reset_size()


# --- Seeds -----------------------------------------------------------------

## ?seed=1234 from the page address in the browser build, else -1.
func _url_seed() -> int:
	if OS.has_feature("web"):
		var from_url: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('seed')")
		if from_url is String and (from_url as String).is_valid_int():
			return int(from_url)
	return -1


## Dev tools show in desktop runs, or in the browser with ?dev=1 in the address.
func _dev_mode() -> bool:
	if not OS.has_feature("web"):
		return true
	var flag: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('dev')")
	return flag is String and flag == "1"


func _random_seed() -> int:
	return randi_range(1000, 99999)


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.12, 0.14)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_top = TopBar.new(_dev_mode())
	_top.speed_changed.connect(_set_speed)
	_top.skip_pressed.connect(_skip_ahead)
	_top.menu_pressed.connect(_open_menu)
	_top.show_speed(speed)
	root.add_child(_top)

	# The map, with the clock and alerts in its top-left corner, the attack in its top-right, and the
	# building cards as a heads-up hand along its bottom edge while building.
	var map_box := Control.new()
	map_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_box.resized.connect(_layout_hud)
	root.add_child(map_box)
	_map_box = map_box
	_arena = ArenaView.new()
	_arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arena.clip_contents = true
	map_box.add_child(_arena)
	_corner = VBoxContainer.new()
	_corner.position = Vector2(10, 8)
	_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_corner.add_theme_constant_override("separation", 6)
	map_box.add_child(_corner)
	_clock_label = RichTextLabel.new()
	_clock_label.bbcode_enabled = true
	_clock_label.fit_content = true
	# Wraps at the alerts' width, so the corner column keeps its width.
	_clock_label.custom_minimum_size.x = Alerts.WIDTH
	_clock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_clock_label.scroll_active = false
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label.add_theme_font_size_override("normal_font_size", 15)
	_clock_label.add_theme_font_size_override("bold_font_size", 15)
	_corner.add_child(_clock_label)
	_alerts = Alerts.new()
	_corner.add_child(_alerts)
	# Placed by _layout_hud.
	_threat = ThreatCard.new()
	map_box.add_child(_threat)
	_hand_view = BuildHandView.new()
	_hand_view.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hand_view.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hand_view.changed.connect(_refresh)
	_hand_view.previewing.connect(_preview_building)
	_hand_view.resized.connect(_layout_hud)
	_hand_view.begin_pressed.connect(_begin_round)
	map_box.add_child(_hand_view)

	# Underneath: the heroes as portraits, and the story's last lines.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)
	_heroes = HeroStrip.new()
	_heroes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heroes.size_flags_stretch_ratio = 1.5
	_heroes.hero_pressed.connect(func(hero: Unit) -> void: _arena.look_at_point(hero.pos))
	bottom.add_child(_heroes)
	_story = StoryLog.new()
	_story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story.open_pressed.connect(func() -> void:
		_menu_open = true
		_overlays.show_log())
	_story.impact_pressed.connect(func() -> void:
		_menu_open = true
		_overlays.show_impact())
	bottom.add_child(_story)

	# Overlay for picks, relics, the end screen and the menu: dims the screen, panel in the middle.
	_overlays = Overlays.new()
	_overlays.pick_taken.connect(_take_pick)
	_overlays.relic_picked.connect(_pick_relic)
	_overlays.traditions_chosen.connect(_found)
	_overlays.random_tradition_chosen.connect(_found_by_chance)
	_overlays.pedlar_chosen.connect(_invite_pedlar)
	_overlays.new_run_requested.connect(_restart)
	_overlays.seed_run_requested.connect(_new_run)
	_overlays.closed.connect(_close_menu)
	_overlays.settings_changed.connect(_apply_settings)
	_overlays.title_requested.connect(_show_title)
	_overlays.settings = settings

	# The title screen covers the game; the menu's screens (Run history, Settings) open over it.
	_title_screen = TitleScreen.new()
	_title_screen.visible = false
	_title_screen.start_pressed.connect(func(seed_value: int) -> void:
		_new_run(seed_value if seed_value >= 0 else _random_seed()))
	_title_screen.how_to_play_pressed.connect(func() -> void: _overlays.show_welcome(false))
	_title_screen.history_pressed.connect(func() -> void: _overlays.show_history())
	_title_screen.settings_pressed.connect(func() -> void: _overlays.show_settings())
	add_child(_title_screen)
	add_child(_overlays)

	# One-time tips sit above everything, picks included.
	_tips = FirstTips.new()
	_tips.settings = settings
	_tips.content = content
	_tips.anchor = _tip_position
	add_child(_tips)
	_arena.night_camera = settings.night_camera
