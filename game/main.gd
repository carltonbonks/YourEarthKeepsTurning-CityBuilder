extends Control
## The game screen: a thin bar of key numbers on top, the map filling the middle, and the heroes and
## the story's last lines underneath. Decisions are cards: the building hand over the map while
## building, the dawn and relic picks in the middle. Detail lives in hover cards, not on screen.
## UI is built in code for now (placeholder layout); all rules live in sim/.
##
## This file runs the flow (new run, ticking the sim, pausing for decisions, pause and speed, the Esc
## menu) and lays out the screen. The parts live in their own files: TopBar, BuildHandView (the
## building cards), ThreatCard (the attack and Begin round), Alerts, HeroStrip, StoryLog, Overlays
## (picks, relics, end screen, menu, Run history, dev tuning) and ArenaView (the map).

## How often the live panels are rebuilt while the sim runs (the map redraws every frame).
const LIVE_REFRESH_SECONDS := 0.1

var content: Content
var run: RunState
var speed := 2
## The speed Space returns to after a pause.
var _play_speed := 2
var _tick_acc := 0.0
var _live_acc := 0.0
var _menu_open := false
## Id of this run's file in Run history.
var _run_id := ""

var _top: TopBar
var _hand_view: BuildHandView
var _threat: ThreatCard
var _alerts: Alerts
var _arena: ArenaView
var _clock_label: RichTextLabel
var _heroes: HeroStrip
var _story: StoryLog
var _overlays: Overlays


func _ready() -> void:
	content = Content.load_default()
	_build_ui()
	_new_run(_initial_seed())


func _process(delta: float) -> void:
	if run.phase != RunState.Phase.SIM or _overlays.visible:
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
	if key.keycode == KEY_ESCAPE:
		_close_menu() if _menu_open else _open_menu()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_SPACE and not _overlays.visible:
		_set_speed(_play_speed if speed == 0 else 0)
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
	_overlays.hide()
	_refresh()


func _begin_round() -> void:
	if run.phase != RunState.Phase.BUILD:
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
	RunHistory.save(_run_id, run)
	_refresh()
	_overlays.show_for_phase()


func _take_pick(index: int) -> void:
	run.choose_pick(index)
	_overlays.hide()
	_refresh()


func _pick_relic(relic_id: String) -> void:
	run.choose_relic(relic_id)
	RunHistory.save(_run_id, run)
	_overlays.hide()
	_refresh()


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


## The menu, the log or a dev panel closed: back to whatever the run is waiting on.
func _close_menu() -> void:
	_menu_open = false
	_refresh()
	_overlays.show_for_phase()


# --- Refresh ---------------------------------------------------------------

func _refresh() -> void:
	_hand_view.visible = run.phase == RunState.Phase.BUILD
	if _hand_view.visible:
		_hand_view.refresh()
	_refresh_live()


## Parts that change while the sim runs.
func _refresh_live() -> void:
	_top.refresh()
	_clock_label.text = StatusText.clock(run)
	_threat.refresh()
	_alerts.refresh()
	_heroes.refresh()
	_story.refresh()


# --- Seeds -----------------------------------------------------------------

## Uses ?seed=1234 from the page address in the browser build, else a random seed.
func _initial_seed() -> int:
	if OS.has_feature("web"):
		var from_url: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('seed')")
		if from_url is String and (from_url as String).is_valid_int():
			return int(from_url)
	return _random_seed()


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
	root.add_child(map_box)
	_arena = ArenaView.new()
	_arena.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arena.clip_contents = true
	map_box.add_child(_arena)
	var corner := VBoxContainer.new()
	corner.position = Vector2(10, 8)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation", 6)
	map_box.add_child(corner)
	_clock_label = RichTextLabel.new()
	_clock_label.bbcode_enabled = true
	_clock_label.fit_content = true
	_clock_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_clock_label.scroll_active = false
	_clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock_label.add_theme_font_size_override("normal_font_size", 15)
	_clock_label.add_theme_font_size_override("bold_font_size", 15)
	corner.add_child(_clock_label)
	_alerts = Alerts.new()
	corner.add_child(_alerts)
	_threat = ThreatCard.new()
	_threat.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_threat.position = Vector2(-ThreatCard.WIDTH - 10, 8)
	_threat.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_threat.begin_pressed.connect(_begin_round)
	map_box.add_child(_threat)
	_hand_view = BuildHandView.new()
	_hand_view.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hand_view.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hand_view.changed.connect(_refresh)
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
	bottom.add_child(_story)

	# Overlay for picks, relics, the end screen and the menu: dims the screen, panel in the middle.
	_overlays = Overlays.new()
	_overlays.pick_taken.connect(_take_pick)
	_overlays.relic_picked.connect(_pick_relic)
	_overlays.new_run_requested.connect(_restart)
	_overlays.seed_run_requested.connect(_new_run)
	_overlays.closed.connect(_close_menu)
	add_child(_overlays)
