extends Control
## Vertical-slice screen: decision panel on the left, the battle in the middle,
## heroes and the town's story underneath. UI is built in code for now
## (placeholder layout); all rules live in sim/.

const SPEEDS := [1, 2, 4, 8]

var content: Content
var run: RunState
var battle: Battle
var speed := 2
var _tick_acc := 0.0
## How much of the story is already on screen. Battle lines are shown live and
## then repeated in run.story when the battle finishes, so those get skipped.
var _shown_story := 0
var _battle_story_shown := 0
var _skip_lines := 0

var _status: RichTextLabel
var _decide_box: VBoxContainer
var _wave_box: VBoxContainer
var _recruit_btn: Button
var _market_btn: Button
var _repair_btn: Button
var _start_btn: Button
var _battle_box: VBoxContainer
var _relic_label: RichTextLabel
var _arena: ArenaView
var _heroes_label: RichTextLabel
var _story_label: RichTextLabel
var _overlay: PanelContainer
var _overlay_box: VBoxContainer
var _seed_edit: LineEdit


func _ready() -> void:
	content = Content.load_default()
	_build_ui()
	_new_run(_initial_seed())


func _process(delta: float) -> void:
	if battle == null:
		return
	_tick_acc += delta * speed
	while _tick_acc >= battle.dt and not battle.over:
		_tick_acc -= battle.dt
		battle.step()
	_refresh_live()
	if battle.over:
		var finished := battle
		battle = null
		_arena.battle = null
		_skip_lines = finished.story.size()
		run.finish_battle(finished)
		_after_battle()


# --- Flow ------------------------------------------------------------------

func _new_run(seed_value: int) -> void:
	run = RunState.new(content, seed_value)
	battle = null
	_arena.run = run
	_arena.battle = null
	_shown_story = 0
	_story_label.clear()
	_overlay.hide()
	_seed_edit.text = str(seed_value)
	_refresh()


func _start_wave() -> void:
	if run.phase != RunState.Phase.DECIDE:
		return
	battle = run.start_battle()
	_arena.battle = battle
	_tick_acc = 0.0
	_battle_story_shown = 0
	_refresh()


func _skip_battle() -> void:
	if battle != null:
		battle.run_to_end()


func _after_battle() -> void:
	_refresh()
	match run.phase:
		RunState.Phase.RELIC:
			_show_relic_pick()
		RunState.Phase.WON, RunState.Phase.LOST:
			_show_end()


func _pick_relic(relic_id: String) -> void:
	run.choose_relic(relic_id)
	_overlay.hide()
	_refresh()


# --- Refresh ---------------------------------------------------------------

func _refresh() -> void:
	var deciding := run.phase == RunState.Phase.DECIDE
	_decide_box.visible = deciding
	_battle_box.visible = run.phase == RunState.Phase.BATTLE
	_refresh_status()
	_refresh_wave()
	_recruit_btn.text = "Recruit a hero (%dg)  [%d/%d]" % [run.recruit_cost(), run.heroes.size(), content.int_num("max_heroes")]
	_recruit_btn.disabled = not run.can_recruit()
	_market_btn.text = "Build a market (%dg)  [%d/%d]  +%dg/round" % [content.int_num("market_cost"), run.markets,
		content.int_num("max_markets"), int(content.num("market_income") + run.mod("market_income"))]
	_market_btn.disabled = not run.can_build_market()
	_repair_btn.text = "Repair keep (%dg)  +%d HP" % [content.int_num("repair_cost"), content.int_num("repair_amount")]
	_repair_btn.disabled = not run.can_repair()
	_start_btn.text = "Start wave %d" % run.round_number
	var relic_text := "[b]Relics[/b]\n"
	if run.relics.is_empty():
		relic_text += "[color=#888]none yet[/color]"
	for id in run.relics:
		relic_text += "[hint=%s]%s[/hint]\n" % [content.relics[id]["text"], content.relics[id]["name"]]
	_relic_label.text = relic_text
	_refresh_live()


func _refresh_status() -> void:
	var keep_hp := battle.keep_hp if battle != null else run.keep_hp
	_status.text = "[b]Round %d / %d[/b]\nGold: [color=#ffd24a]%d[/color]  (free %d, +%d next round)\nKeep: %d / %d HP\nSeed: %d" % [
		run.round_number, content.int_num("rounds_to_win"), run.gold, run.free_gold(), run.income(),
		maxi(0, int(keep_hp)), int(run.keep_max_hp()), run.run_seed]


func _refresh_wave() -> void:
	for child in _wave_box.get_children():
		child.queue_free()
	var counts := run.wave_counts()
	var ids := counts.keys()
	ids.sort()
	for id: String in ids:
		var e: Dictionary = content.enemies[id]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s x%d" % [e["name"], counts[id]]
		label.tooltip_text = "HP %d, damage %d, range %d%s" % [e["hp"], e["attack"], e["range"],
			"\nHangs back and makes every enemy hit harder while alive." if e.has("war_chant") else ""]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var amount := int(run.bounties.get(id, 0))
		var step := content.int_num("bounty_step")
		var minus := Button.new()
		minus.text = " - "
		minus.disabled = amount <= 0
		minus.pressed.connect(func() -> void: run.set_bounty(id, amount - step); _refresh())
		row.add_child(minus)
		var bounty := Label.new()
		bounty.text = "%dg" % amount
		bounty.custom_minimum_size.x = 36
		bounty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bounty.add_theme_color_override("font_color", Color("#ffd24a") if amount > 0 else Color("#888"))
		row.add_child(bounty)
		var plus := Button.new()
		plus.text = " + "
		plus.pressed.connect(func() -> void: run.set_bounty(id, amount + step); _refresh())
		row.add_child(plus)
		_wave_box.add_child(row)


## Parts that change every frame during a battle.
func _refresh_live() -> void:
	if battle != null:
		_refresh_status()
	var text := ""
	var heroes: Array[Unit] = battle.heroes if battle != null else run.heroes
	for hero in heroes:
		var c: Dictionary = content.hero_classes[hero.type_id]
		var name_color: String = c["color"] if hero.alive else "#666666"
		text += "[color=%s][b]%s[/b][/color] %s %s  Lv%d  HP %d/%d  %dg  gear W%d A%d  kills %d%s\n" % [
			name_color, hero.display_name, content.traits[hero.trait_id]["name"], c["name"], hero.level,
			int(hero.hp), int(hero.max_hp), hero.gold, hero.weapon_tier, hero.armor_tier, hero.kills,
			"" if hero.alive else "  [color=#e05050]fallen[/color]"]
	for hero in run.fallen:
		if battle == null or not battle.heroes.has(hero):
			text += "[color=#666666]%s (fallen)[/color]\n" % hero.display_name
	_heroes_label.text = text
	_append_story()
	if battle != null:
		while _battle_story_shown < battle.story.size():
			_story_label.append_text("  " + battle.story[_battle_story_shown] + "\n")
			_battle_story_shown += 1


func _append_story() -> void:
	if battle != null:
		return
	while _shown_story < run.story.size():
		var line := run.story[_shown_story]
		_shown_story += 1
		if _skip_lines > 0:
			_skip_lines -= 1
			continue
		var bold := line.begins_with("Round ") or line.begins_with("The keep") or line.begins_with("The town")
		_story_label.append_text(("[b]%s[/b]" if bold else "%s") % line + "\n")


# --- Overlays --------------------------------------------------------------

func _show_relic_pick() -> void:
	_clear_overlay()
	_overlay_title("Wave %d survived! Choose a relic" % run.round_number)
	for id in run.relic_offer:
		var r: Dictionary = content.relics[id]
		var btn := Button.new()
		btn.text = "%s\n%s" % [r["name"], r["text"]]
		btn.custom_minimum_size = Vector2(420, 60)
		btn.pressed.connect(_pick_relic.bind(id))
		_overlay_box.add_child(btn)
	var skip := Button.new()
	skip.text = "Skip"
	skip.pressed.connect(_pick_relic.bind(""))
	_overlay_box.add_child(skip)
	_overlay.show()


func _show_end() -> void:
	_clear_overlay()
	var won := run.phase == RunState.Phase.WON
	_overlay_title("Victory! The town endures." if won else "The keep has fallen in round %d." % run.round_number)
	var summary := Label.new()
	summary.text = "Seed %d  ·  heroes lost: %d  ·  relics: %s" % [run.run_seed, run.fallen.size(),
		", ".join(run.relics.map(func(id: String) -> String: return content.relics[id]["name"])) if not run.relics.is_empty() else "none"]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.custom_minimum_size.x = 420
	_overlay_box.add_child(summary)
	var again := Button.new()
	again.text = "New run (new seed)"
	again.pressed.connect(func() -> void: _new_run(_random_seed()))
	_overlay_box.add_child(again)
	var replay := Button.new()
	replay.text = "Replay seed %d" % run.run_seed
	replay.pressed.connect(func() -> void: _new_run(run.run_seed))
	_overlay_box.add_child(replay)
	_overlay.show()


func _clear_overlay() -> void:
	for child in _overlay_box.get_children():
		child.queue_free()


func _overlay_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_box.add_child(title)


# --- Seeds -----------------------------------------------------------------

## Uses ?seed=1234 from the page address in the browser build, else a random seed.
func _initial_seed() -> int:
	if OS.has_feature("web"):
		var from_url: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('seed')")
		if from_url is String and (from_url as String).is_valid_int():
			return int(from_url)
	return _random_seed()


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

	_status = _rich(left, 96)

	_decide_box = VBoxContainer.new()
	left.add_child(_decide_box)
	_heading(_decide_box, "Next wave: post bounties (paid per kill)")
	var hint := Label.new()
	hint.text = "Bounties steer heroes. Greedy heroes chase them; unpaid heroes stay near the keep."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#9aa"))
	_decide_box.add_child(hint)
	_wave_box = VBoxContainer.new()
	_decide_box.add_child(_wave_box)
	_heading(_decide_box, "Town")
	_recruit_btn = _button(_decide_box, "", func() -> void: run.recruit(); _refresh())
	_market_btn = _button(_decide_box, "", func() -> void: run.build_market(); _refresh())
	_repair_btn = _button(_decide_box, "", func() -> void: run.repair_keep(); _refresh())
	_decide_box.add_child(HSeparator.new())
	_start_btn = _button(_decide_box, "", _start_wave)
	_start_btn.custom_minimum_size.y = 44

	_battle_box = VBoxContainer.new()
	left.add_child(_battle_box)
	_heading(_battle_box, "Battle speed")
	var speeds := HBoxContainer.new()
	_battle_box.add_child(speeds)
	var group := ButtonGroup.new()
	for s: int in SPEEDS:
		var b := Button.new()
		b.text = "%dx" % s
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = s == speed
		b.pressed.connect(func() -> void: speed = s)
		speeds.add_child(b)
	_button(_battle_box, "Skip to end of wave", _skip_battle)

	left.add_child(HSeparator.new())
	_relic_label = _rich(left, 0)
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

	# Right: arena above, heroes + story below.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	_arena = ArenaView.new()
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.size_flags_stretch_ratio = 2.2
	right.add_child(_arena)
	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(bottom)
	_heroes_label = _rich(bottom, 0)
	_heroes_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heroes_label.add_theme_font_size_override("normal_font_size", 13)
	_heroes_label.add_theme_font_size_override("bold_font_size", 13)
	_story_label = _rich(bottom, 0)
	_story_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_story_label.scroll_following = true
	_story_label.add_theme_font_size_override("normal_font_size", 13)
	_story_label.add_theme_font_size_override("bold_font_size", 13)

	# Overlay for relic picks and the end screen: dims the screen, panel in the middle.
	_overlay = PanelContainer.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.6)
	_overlay.add_theme_stylebox_override("panel", dim)
	add_child(_overlay)
	var center := CenterContainer.new()
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color("#23262d")
	box_style.border_color = Color("#e8d9a8")
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", box_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 10)
	margin.add_child(_overlay_box)
	_overlay.hide()


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#e8d9a8"))
	parent.add_child(l)


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _rich(parent: Control, min_height: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.custom_minimum_size.y = min_height
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL if min_height == 0 else Control.SIZE_FILL
	parent.add_child(r)
	return r
