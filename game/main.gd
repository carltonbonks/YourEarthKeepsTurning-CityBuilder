extends Control
## The game screen: the settlement map in the middle, decisions on the left,
## heroes and the story underneath. UI is built in code for now (placeholder
## layout); all rules live in sim/.
##
## This file runs the flow (new run, ticking the sim, pausing for decisions) and
## lays out the screen. The parts live in their own files: BuildPanel (the
## build-phase choices), Overlays (picks, relics, end screen, Run history, dev
## tuning), StatusText (the live text) and ArenaView (the map).

const SPEEDS := [1, 2, 4, 8]

var content: Content
var run: RunState
var speed := 2
var _tick_acc := 0.0
## How much of run.story is already on screen.
var _shown_story := 0
## Id of this run's file in Run history.
var _run_id := ""

var _status: RichTextLabel
var _build_panel: BuildPanel
var _market_label: RichTextLabel
var _sim_box: VBoxContainer
var _relic_label: RichTextLabel
var _arena: ArenaView
var _clock_label: RichTextLabel
var _heroes_label: RichTextLabel
var _story_label: RichTextLabel
var _overlays: Overlays
var _seed_edit: LineEdit


func _ready() -> void:
	content = Content.load_default()
	_build_ui()
	_new_run(_initial_seed())


func _process(delta: float) -> void:
	if run.phase != RunState.Phase.SIM:
		return
	_tick_acc += delta * speed
	var dt := run.world.dt
	while _tick_acc >= dt and run.phase == RunState.Phase.SIM:
		_tick_acc -= dt
		run.step()
	if run.phase != RunState.Phase.SIM:
		_on_pause()
	else:
		_refresh_live()


# --- Flow ------------------------------------------------------------------

func _new_run(seed_value: int) -> void:
	if run != null:
		run.dispose()
	run = RunState.new(content, seed_value)
	_run_id = RunHistory.new_run_id(seed_value)
	_arena.run = run
	_arena.reset_camera()
	_build_panel.run = run
	_arena.stop_staking()
	_overlays.run = run
	_shown_story = 0
	_story_label.clear()
	_overlays.hide()
	_seed_edit.text = str(seed_value)
	_refresh()


func _begin_round() -> void:
	if run.phase != RunState.Phase.BUILD:
		return
	_arena.stop_staking()
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


func _tuning_closed() -> void:
	_refresh()
	_overlays.show_for_phase()


# --- Refresh ---------------------------------------------------------------

func _refresh() -> void:
	var building := run.phase == RunState.Phase.BUILD
	_build_panel.visible = building
	_sim_box.visible = run.phase == RunState.Phase.SIM
	if building:
		_build_panel.refresh()
	_relic_label.text = StatusText.relics(run)
	_refresh_live()


## Parts that change every frame while the sim runs.
func _refresh_live() -> void:
	_status.text = StatusText.status(run)
	_clock_label.text = StatusText.clock(run)
	_heroes_label.text = StatusText.heroes(run)
	_market_label.text = StatusText.market(run)
	_append_story()


func _append_story() -> void:
	while _shown_story < run.story.size():
		var line := run.story[_shown_story]
		_shown_story += 1
		var bold := line.begins_with("Round ") or line.begins_with("The hearth") or line.begins_with("Night 3") or line.begins_with("No one")
		_story_label.append_text(("[b]%s[/b]" if bold else "%s") % line + "\n")


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

	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# Left: decisions.
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 340
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	left_scroll.add_child(left)

	_status = UiKit.rich(left, 140)
	_status.add_theme_font_size_override("normal_font_size", 13)
	_status.add_theme_font_size_override("bold_font_size", 14)

	_build_panel = BuildPanel.new()
	_build_panel.changed.connect(_refresh)
	_build_panel.begin_pressed.connect(_begin_round)
	left.add_child(_build_panel)

	_sim_box = VBoxContainer.new()
	left.add_child(_sim_box)
	UiKit.heading(_sim_box, "Speed")
	var speeds := HBoxContainer.new()
	_sim_box.add_child(speeds)
	var group := ButtonGroup.new()
	for s: int in SPEEDS:
		var b := Button.new()
		b.text = "%dx" % s
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = s == speed
		b.pressed.connect(func() -> void: speed = s)
		speeds.add_child(b)
	if _dev_mode():
		UiKit.button(_sim_box, "Skip to the next decision (dev)", _skip_ahead)

	left.add_child(HSeparator.new())
	_market_label = UiKit.rich(left, 0)
	_market_label.fit_content = true
	_market_label.add_theme_font_size_override("normal_font_size", 12)
	_market_label.add_theme_font_size_override("bold_font_size", 13)
	left.add_child(HSeparator.new())
	_relic_label = UiKit.rich(left, 0)
	_relic_label.fit_content = true

	left.add_child(HSeparator.new())
	var seed_row := HBoxContainer.new()
	left.add_child(seed_row)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "seed"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_edit)
	var restart := Button.new()
	restart.text = "Restart with seed"
	restart.pressed.connect(func() -> void:
		_new_run(int(_seed_edit.text) if _seed_edit.text.is_valid_int() else _random_seed()))
	seed_row.add_child(restart)
	UiKit.button(left, "Run history", func() -> void: _overlays.show_history())
	if _dev_mode():
		UiKit.button(left, "Tune market (dev)", func() -> void: _overlays.show_tuning())

	# Right: clock line, map, then heroes + story.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	_clock_label = UiKit.rich(right, 26)
	_clock_label.add_theme_font_size_override("normal_font_size", 15)
	_clock_label.add_theme_font_size_override("bold_font_size", 15)
	_arena = ArenaView.new()
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.size_flags_stretch_ratio = 2.6
	_arena.clip_contents = true
	right.add_child(_arena)
	_build_panel.arena = _arena
	_arena.stake_points_changed.connect(func() -> void: _build_panel.refresh_roads())
	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(bottom)
	_heroes_label = UiKit.rich(bottom, 0)
	_heroes_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heroes_label.add_theme_font_size_override("normal_font_size", 13)
	_heroes_label.add_theme_font_size_override("bold_font_size", 13)
	_story_label = UiKit.rich(bottom, 0)
	_story_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_label.scroll_following = true
	_story_label.add_theme_font_size_override("normal_font_size", 13)
	_story_label.add_theme_font_size_override("bold_font_size", 13)

	# Overlay for picks, relics and the end screen: dims the screen, panel in the middle.
	_overlays = Overlays.new()
	_overlays.pick_taken.connect(_take_pick)
	_overlays.relic_picked.connect(_pick_relic)
	_overlays.new_run_requested.connect(_restart)
	_overlays.tuning_closed.connect(_tuning_closed)
	add_child(_overlays)
