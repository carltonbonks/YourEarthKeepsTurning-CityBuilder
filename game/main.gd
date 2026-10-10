extends Control
## Slice 3 screen: the settlement map in the middle, decisions on the left,
## heroes and the story underneath. UI is built in code for now (placeholder
## layout); all rules live in sim/.

const SPEEDS := [1, 2, 4, 8]
const RESOURCE_COLORS := {"food": "#d98aa8", "fuel": "#e0b050", "wood": "#7fbf6a", "stone": "#b0b4bc", "shells": "#ffd24a"}

var content: Content
var run: RunState
var speed := 2
var _tick_acc := 0.0
## How much of run.story is already on screen.
var _shown_story := 0
## Id of this run's file in Run history.
var _run_id := ""

var _status: RichTextLabel
var _build_box: VBoxContainer
var _build_list: VBoxContainer
var _wave_label: RichTextLabel
var _begin_btn: Button
var _sim_box: VBoxContainer
var _relic_label: RichTextLabel
var _arena: ArenaView
var _clock_label: RichTextLabel
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
	_shown_story = 0
	_story_label.clear()
	_overlay.hide()
	_seed_edit.text = str(seed_value)
	_refresh()


func _build(type: String) -> void:
	run.build(type)
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
	_show_phase_overlay()


func _show_phase_overlay() -> void:
	match run.phase:
		RunState.Phase.PICK:
			_show_pick()
		RunState.Phase.RELIC:
			_show_relic_pick()
		RunState.Phase.WON, RunState.Phase.LOST:
			_show_end()
		_:
			_overlay.hide()


func _take_pick(index: int) -> void:
	run.choose_pick(index)
	_overlay.hide()
	_refresh()


func _pick_relic(relic_id: String) -> void:
	run.choose_relic(relic_id)
	RunHistory.save(_run_id, run)
	_overlay.hide()
	_refresh()


# --- Refresh ---------------------------------------------------------------

func _refresh() -> void:
	var building := run.phase == RunState.Phase.BUILD
	_build_box.visible = building
	_sim_box.visible = run.phase == RunState.Phase.SIM
	if building:
		_refresh_build()
	var relic_text := "[b]Relics[/b]\n"
	if run.relics.is_empty():
		relic_text += "[color=#888]none yet[/color]"
	for id in run.relics:
		relic_text += "[hint=%s]%s[/hint]\n" % [content.relics[id]["text"], content.relics[id]["name"]]
	_relic_label.text = relic_text
	_refresh_live()


func _refresh_build() -> void:
	for child in _build_list.get_children():
		child.queue_free()
	var types := content.buildings.keys()
	for type: String in types:
		var def: Dictionary = content.buildings[type]
		var cost := PackedStringArray()
		for r: String in def["cost"]:
			cost.append("%d %s" % [def["cost"][r], r])
		var owned := run.world.count_buildings(type, false)
		var btn := Button.new()
		btn.text = "%s  (%s)%s" % [def["name"], ", ".join(cost), "  [%d/%d]" % [owned, def["max"]] if def.has("max") else ("  [%d]" % owned if owned > 0 else "")]
		btn.tooltip_text = "%s\nA craftsperson needs about %d seconds to raise it." % [def["text"], def["work"]]
		btn.disabled = not run.can_build(type)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_build.bind(type))
		_build_list.add_child(btn)
		var note := Label.new()
		note.text = def["text"]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD
		note.add_theme_font_size_override("font_size", 11)
		note.add_theme_color_override("font_color", Color("#9aa"))
		_build_list.add_child(note)
	var pending := run.world.buildings.filter(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0).size()
	if pending > 0 and run.count_role("craftsperson") == 0:
		var warn := Label.new()
		warn.text = "Nobody can raise buildings yet: pick a craftsperson at dawn."
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD
		warn.add_theme_color_override("font_color", Color("#e0a050"))
		_build_list.add_child(warn)

	var counts := run.wave_counts()
	var ids := counts.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s x%d" % [content.enemies[id]["name"], counts[id]])
	_wave_label.text = "[b]Night %d attack[/b] from the [color=#ff7060]%s[/color]:\n%s" % [
		content.int_num("days_per_round"), " and ".join(run.world.side_names()), ", ".join(parts)]
	_begin_btn.text = "Begin round %d" % run.round_number


## Parts that change every frame while the sim runs.
func _refresh_live() -> void:
	var w := run.world
	var stock := PackedStringArray()
	for r: String in RunState.RESOURCES:
		stock.append("[color=%s]%s %d[/color]" % [RESOURCE_COLORS[r], r.capitalize(), run.stock[r]])
	var folk := PackedStringArray()
	for role: String in content.townsfolk:
		folk.append("%s %d" % [content.townsfolk[role]["name"], run.count_role(role)])
	_status.text = "[b]Round %d / %d[/b]   Seed %d\nHearth: %d / %d HP\n%s\nPeople %d / %d housing  (%s, heroes %d)\nUpkeep: %d food per day, %d fuel per night" % [
		run.round_number, content.int_num("rounds_to_win"), run.run_seed, maxi(0, int(w.hearth_hp)), int(run.hearth_max_hp()),
		"  ".join(stock), run.population(), run.housing(), ", ".join(folk), run.living_heroes().size(),
		_food_per_day(), run.fuel_needed_tonight()]

	var clock := ""
	if run.phase == RunState.Phase.BUILD:
		clock = "[b]Build[/b]: order buildings, then begin the round."
	else:
		var night := w.is_night()
		var wave_night := w.day_index() == content.int_num("days_per_round") - 1
		clock = "[b]Day %d / %d[/b]  %s%s" % [w.day_index() + 1, content.int_num("days_per_round"),
			"[color=#8fa8ff]Night[/color]" if night else ("[color=#e0a050]Dusk[/color]" if w.is_dusk() else "[color=#ffe08a]Day[/color]"),
			("   [color=#ff7060]Attack tonight from the %s[/color]" % " and ".join(w.side_names())) if wave_night and not w.wave_spawned else ""]
		if w.wave_spawned:
			var left := w.enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index < 0).size()
			clock += "   [color=#ff7060]Attackers left: %d[/color]" % left
		if w.cold_tonight:
			clock += "   [color=#8fd0ff]No fuel: a cold night[/color]"
	_clock_label.text = clock

	var text := ""
	for hero in run.heroes:
		var c: Dictionary = content.hero_classes[hero.type_id]
		var name_color: String = c["color"] if hero.alive else "#666666"
		var energy_color := "#7fd0ff" if hero.energy > 40.0 else ("#e0a050" if hero.energy > 0.0 else "#e05050")
		text += "[color=%s][b]%s[/b][/color] %s %s  Lv%d  HP %d/%d  [color=%s]Energy %d[/color]  %d shells  kills %d%s\n" % [
			name_color, hero.display_name, content.traits[hero.trait_id]["name"], c["name"], hero.level,
			int(hero.hp), int(hero.max_hp), energy_color, int(hero.energy), hero.gold, hero.kills,
			"" if hero.alive else "  [color=#e05050]fallen[/color]"]
		if not hero.alive:
			continue
		var whim: String = content.whims.get(hero.whim, {}).get("name", "")
		var bed := "No bed: sleeps by the hearth" if hero.lodging < 0 else "Sleeps in %s%s" % [w.bed_name(hero.lodging),
			"" if w.is_preferred(hero, hero.lodging) else " (not their favourite)"]
		text += "    [color=#9aa]%s%s[/color]\n" % [bed,
			("  ·  today: " + whim) if whim != "" and run.phase != RunState.Phase.BUILD else ""]
		var gear := PackedStringArray()
		for slot: String in Loot.SLOTS:
			if hero.items.has(slot):
				gear.append(Loot.describe(content, hero.items[slot]))
		if not gear.is_empty() or not hero.spares.is_empty():
			text += "    [color=#c8b88a]%s%s[/color]\n" % [", ".join(gear) if not gear.is_empty() else "no gear",
				"  ·  %d to sell" % hero.spares.size() if not hero.spares.is_empty() else ""]
		if hero.intent != "" and run.phase == RunState.Phase.SIM:
			text += "    [color=#9aa]%s[/color]\n" % hero.intent
	for hero in run.fallen:
		text += "[color=#666666]%s (fallen)[/color]\n" % hero.display_name
	_heroes_label.text = text
	_append_story()


func _food_per_day() -> int:
	return maxi(0, int(ceil(run.population() * content.num("food_per_person_per_day") * (1.0 - 0.25 * run.world.count_buildings("drying_rack")))))


func _append_story() -> void:
	while _shown_story < run.story.size():
		var line := run.story[_shown_story]
		_shown_story += 1
		var bold := line.begins_with("Round ") or line.begins_with("The hearth") or line.begins_with("Night 3") or line.begins_with("No one")
		_story_label.append_text(("[b]%s[/b]" if bold else "%s") % line + "\n")


# --- Overlays --------------------------------------------------------------

func _show_pick() -> void:
	_clear_overlay()
	var day := run.world.day_index() + 1
	_overlay_title("Dawn of day %d: who joins the settlement?" % day)
	_night_summary()
	var room := run.population() < run.housing()
	var sub := Label.new()
	sub.text = "Shells: %d   Room: %d / %d%s" % [run.stock["shells"], run.population(), run.housing(),
		"" if room else "\nNo room for anyone new. Build huts at the start of the next round."]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color("#c8c8c8") if room else Color("#e0a050"))
	_overlay_box.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_overlay_box.add_child(row)
	for i in run.pick_offer.size():
		var card := run.pick_offer[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(230, 170)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		if card["kind"] == "hero":
			var hero: Unit = card["hero"]
			var c: Dictionary = content.hero_classes[hero.type_id]
			var likes: Array = content.traits[hero.trait_id].get("lodging", [])
			btn.text = "HERO: %s\n%s %s\nHP %d, damage %d%s\nLikes to sleep in: %s\nCosts %d shells" % [hero.display_name,
				content.traits[hero.trait_id]["name"], c["name"], int(hero.max_hp), int(hero.attack),
				", ranged" if hero.attack_range > 60 else "",
				" or ".join(likes.map(func(id: String) -> String: return content.buildings[id]["name"].to_lower())), card["cost"]]
			btn.tooltip_text = _trait_hint(hero.trait_id)
		else:
			var def: Dictionary = content.townsfolk[card["role"]]
			btn.text = "%s\n\n%s\nFree. Eats 1 food a day." % [def["name"], def["text"]]
		btn.disabled = not run.can_take_pick(i)
		btn.pressed.connect(_take_pick.bind(i))
		row.add_child(btn)
	var skip := Button.new()
	skip.text = "Nobody today"
	skip.pressed.connect(_take_pick.bind(-1))
	_overlay_box.add_child(skip)
	_overlay.show()


func _trait_hint(trait_id: String) -> String:
	var t: Dictionary = content.traits[trait_id]
	var wilds := "hunts far out at the dens by day" if float(t["wilds"]) > 0.6 else ("stays near the camp" if float(t["wilds"]) < 0.2 else "ventures out sometimes")
	return "%s: %s, retreats at %d%% health, goes to rest when energy falls to %d." % [t["name"], wilds,
		roundi(float(t["retreat_at"]) * 100.0), int(t.get("tired_at", 25))]


## One line on what happened last night, above the dawn and relic picks.
func _night_summary() -> void:
	var n := run.last_night
	if n.is_empty():
		return
	var deaths: Array = n["deaths"]
	var text := "Night %d: raiders %d, enemies killed %d, hearth damage %d. " % [
		n["night"], n["raiders"], n["kills"], n["hearth_damage"]]
	text += "Lost: %s." % ", ".join(deaths) if not deaths.is_empty() else "Nobody was lost."
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = 600
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#e0a050") if not deaths.is_empty() else Color("#a8c8a0"))
	_overlay_box.add_child(label)


func _show_relic_pick() -> void:
	_clear_overlay()
	_overlay_title("Round %d survived! Choose a relic" % run.round_number)
	_night_summary()
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
	_overlay_title("Victory! The people endure." if won else "The fire goes out in round %d." % run.round_number)
	var summary := Label.new()
	summary.text = "Seed %d  ·  heroes lost: %d  ·  townsfolk lost: %d  ·  relics: %s" % [run.run_seed, run.fallen.size(), run.fallen_folk,
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
	var history := Button.new()
	history.text = "Run history"
	history.pressed.connect(_show_history)
	_overlay_box.add_child(history)
	_overlay.show()


## Lists saved runs with stats, and lets you copy or download them to share.
func _show_history() -> void:
	var was_end_screen := run.is_over()
	_clear_overlay()
	_overlay_title("Run history")
	var runs := RunHistory.load_all()
	var stats := Label.new()
	stats.text = "No runs saved yet. Runs are saved at every dawn and after each round." if runs.is_empty() \
		else "\n".join(RunStats.report(runs).slice(0, 6))
	stats.add_theme_font_size_override("font_size", 13)
	_overlay_box.add_child(stats)
	var hint := Label.new()
	hint.text = "Copy a run and paste it in the project chat, with what felt off."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#9aa"))
	_overlay_box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_overlay_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for data in runs:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = RunHistory.one_line(data)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var copy := Button.new()
		copy.text = "Copy"
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(JSON.stringify(RunHistory.compact(data)))
			copy.text = "Copied!")
		row.add_child(copy)
		if OS.has_feature("web"):
			var download := Button.new()
			download.text = "Download"
			download.pressed.connect(func() -> void:
				JavaScriptBridge.download_buffer(JSON.stringify(data, "\t").to_utf8_buffer(),
					"run-%s.json" % data.get("id", "run"), "application/json"))
			row.add_child(download)
		list.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_box.add_child(buttons)
	if not runs.is_empty():
		var copy_all := Button.new()
		copy_all.text = "Copy all runs"
		copy_all.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(JSON.stringify(runs.map(RunHistory.compact)))
			copy_all.text = "Copied!")
		buttons.add_child(copy_all)
	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func() -> void:
		if was_end_screen:
			_show_end()
		elif run.phase == RunState.Phase.RELIC:
			_show_relic_pick()
		else:
			_overlay.hide())
	buttons.add_child(close)
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

	_status = _rich(left, 120)
	_status.add_theme_font_size_override("normal_font_size", 13)
	_status.add_theme_font_size_override("bold_font_size", 14)

	_build_box = VBoxContainer.new()
	left.add_child(_build_box)
	_heading(_build_box, "Order buildings")
	var hint := Label.new()
	hint.text = "Craftspeople raise what you order during the days. Nobody takes orders otherwise."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#9aa"))
	_build_box.add_child(hint)
	_build_list = VBoxContainer.new()
	_build_box.add_child(_build_list)
	_build_box.add_child(HSeparator.new())
	_wave_label = _rich(_build_box, 0)
	_wave_label.fit_content = true
	_begin_btn = _button(_build_box, "", _begin_round)
	_begin_btn.custom_minimum_size.y = 44

	_sim_box = VBoxContainer.new()
	left.add_child(_sim_box)
	_heading(_sim_box, "Speed")
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
		_button(_sim_box, "Skip to the next decision (dev)", _skip_ahead)

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
	_button(left, "Run history", _show_history)

	# Right: clock line, map, then heroes + story.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	_clock_label = _rich(right, 26)
	_clock_label.add_theme_font_size_override("normal_font_size", 15)
	_clock_label.add_theme_font_size_override("bold_font_size", 15)
	_arena = ArenaView.new()
	_arena.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arena.size_flags_stretch_ratio = 2.6
	_arena.clip_contents = true
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

	# Overlay for picks, relics and the end screen: dims the screen, panel in the middle.
	_overlay = PanelContainer.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.45)
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
