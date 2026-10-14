class_name Overlays
extends PanelContainer
## The dimmed pop-ups over the screen: the dawn pick, the relic pick, the end of
## a run, Run history and the dev tuning panel. Choices go back to the screen
## as signals; nothing here changes the run directly.

signal pick_taken(index: int)
signal relic_picked(relic_id: String)
## replay = true restarts on the same seed, false on a new one.
signal new_run_requested(replay: bool)
## The tuning panel closed: the screen refreshes and shows the right overlay again.
signal tuning_closed

var run: RunState
var _box: VBoxContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.45)
	add_theme_stylebox_override("panel", dim)
	var center := CenterContainer.new()
	add_child(center)
	var panel := PanelContainer.new()
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color("#23262d")
	box_style.border_color = UiKit.HEADING_COLOR
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", box_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	margin.add_child(_box)
	hide()


## Shows whatever the run is waiting on (a pick, a relic, the end), or hides.
func show_for_phase() -> void:
	match run.phase:
		RunState.Phase.PICK:
			show_pick()
		RunState.Phase.RELIC:
			show_relic_pick()
		RunState.Phase.WON, RunState.Phase.LOST:
			show_end()
		_:
			hide()


func show_pick() -> void:
	var content := run.content
	_clear()
	var day := run.world.day_index() + 1
	_title("Dawn of day %d: who joins the settlement?" % day)
	_night_summary()
	var room := run.population() < run.housing()
	var sub := Label.new()
	sub.text = "Shells: %d   Room: %d / %d%s" % [run.stock["shells"], run.population(), run.housing(),
		"" if room else "\nNo room for anyone new. Build huts at the start of the next round."]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color("#c8c8c8") if room else Color("#e0a050"))
	_box.add_child(sub)
	if run.hunger_turned_away != "":
		var away := Label.new()
		var role: String = content.townsfolk[run.hunger_turned_away]["name"].to_lower()
		away.text = "Word has spread that a %s left hungry: no %s will join today." % [role, role]
		away.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		away.add_theme_color_override("font_color", Color("#e0a050"))
		_box.add_child(away)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	for i in run.pick_offer.size():
		var card := run.pick_offer[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(230, 170)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		if card["kind"] == "promote":
			btn.text = _promote_text(card)
		elif card["kind"] == "hero":
			var hero: Unit = card["hero"]
			var c: Dictionary = content.hero_classes[hero.type_id]
			var likes: Array = content.traits[hero.trait_id].get("lodging", [])
			btn.text = "HERO: %s\n%s %s\nHP %d, damage %d%s\nLikes to sleep in: %s\nCosts %d shells. Eats %s a day." % [hero.display_name,
				content.traits[hero.trait_id]["name"], c["name"], int(hero.max_hp), int(hero.attack),
				", ranged" if hero.attack_range > 60 else "",
				" or ".join(likes.map(func(id: String) -> String: return content.buildings[id]["name"].to_lower())), card["cost"], _food_each()]
			btn.tooltip_text = _trait_hint(hero.trait_id)
		else:
			var def: Dictionary = content.townsfolk[card["role"]]
			btn.text = "%s\n\n%s\nFree. Eats %s a day." % [def["name"], def["text"], _food_each()]
		btn.disabled = not run.can_take_pick(i)
		btn.pressed.connect(func() -> void: pick_taken.emit(i))
		row.add_child(btn)
	var skip := Button.new()
	skip.text = "Nobody today"
	skip.pressed.connect(func() -> void: pick_taken.emit(-1))
	_box.add_child(skip)
	show()


func _food_each() -> String:
	var n := run.content.num("food_per_person_per_day")
	return "%s food" % (str(int(n)) if n == floorf(n) else str(n))


func _promote_text(card: Dictionary) -> String:
	var content := run.content
	var u: Unit = card["unit"]
	if card["role"] == "warrior":
		var hero: Unit = card["hero"]
		return "PROMOTE a veteran warrior\n(%d kills, here since round %d)\nbecomes %s, %s %s, level %d\nNeeds a bed like any hero.\nCosts %d shells" % [
			u.kills, u.joined_round, hero.display_name, content.traits[hero.trait_id]["name"],
			content.hero_classes[hero.type_id]["name"], hero.level, card["cost"]]
	var t: Dictionary = content.promotions["craftsperson"]["traits"][card["trait"]]
	return "PROMOTE a craftsperson\n(%d goods made at the %s)\nbecomes %s, master of the %s\n%s: %s\nCosts %d shells" % [
		int(u.made[card["workshop"]]), content.buildings[card["workshop"]]["name"].to_lower(), card["name"],
		content.buildings[card["workshop"]]["name"].to_lower(), t["name"], t["text"], card["cost"]]


func _trait_hint(trait_id: String) -> String:
	var t: Dictionary = run.content.traits[trait_id]
	var wilds := "hunts far out at the dens by day" if float(t["wilds"]) > 0.6 else ("stays near the camp" if float(t["wilds"]) < 0.2 else "ventures out sometimes")
	return "%s: %s, retreats at %d%% health, goes to rest when energy falls to %d." % [t["name"], wilds,
		roundi(float(t["retreat_at"]) * 100.0), int(t.get("tired_at", 25))]


## One line on what happened last night, above the dawn and relic picks.
func _night_summary() -> void:
	var n := run.last_night
	if n.is_empty():
		return
	var deaths: Array = n["deaths"]
	var left: Array = n.get("left", [])
	var text := "Night %d: raiders %d, enemies killed %d, hearth damage %d. " % [
		n["night"], n["raiders"], n["kills"], n["hearth_damage"]]
	var lost := PackedStringArray()
	for name: String in deaths:
		lost.append("%s (killed)" % name)
	var unhappy: Array = n.get("heroes_left", [])
	for name: String in left:
		lost.append("%s (%s)" % [name, "left unhappy" if unhappy.has(name) else "left hungry"])
	text += "Lost: %s." % ", ".join(lost) if not lost.is_empty() else "Nobody was lost."
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = 600
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#e0a050") if not lost.is_empty() else Color("#a8c8a0"))
	_box.add_child(label)


func show_relic_pick() -> void:
	var content := run.content
	_clear()
	_title("Round %d survived! Choose a relic" % run.round_number)
	_night_summary()
	for id in run.relic_offer:
		var r: Dictionary = content.relics[id]
		var btn := Button.new()
		btn.text = "%s\n%s" % [r["name"], r["text"]]
		btn.custom_minimum_size = Vector2(420, 60)
		btn.pressed.connect(func() -> void: relic_picked.emit(id))
		_box.add_child(btn)
	var skip := Button.new()
	skip.text = "Skip"
	skip.pressed.connect(func() -> void: relic_picked.emit(""))
	_box.add_child(skip)
	show()


func show_end() -> void:
	var content := run.content
	_clear()
	var won := run.phase == RunState.Phase.WON
	_title("Victory! The people endure." if won else "The fire goes out in round %d." % run.round_number)
	var summary := Label.new()
	summary.text = "Seed %d  ·  heroes lost: %d  ·  townsfolk lost: %d  ·  relics: %s" % [run.run_seed, run.fallen.size(), run.fallen_folk,
		", ".join(run.relics.map(func(id: String) -> String: return content.relics[id]["name"])) if not run.relics.is_empty() else "none"]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.custom_minimum_size.x = 420
	_box.add_child(summary)
	UiKit.button(_box, "New run (new seed)", func() -> void: new_run_requested.emit(false))
	UiKit.button(_box, "Replay seed %d" % run.run_seed, func() -> void: new_run_requested.emit(true))
	UiKit.button(_box, "Run history", show_history)
	show()


## Lists saved runs with stats, and lets you copy or download them to share.
func show_history() -> void:
	var was_end_screen := run.is_over()
	_clear()
	_title("Run history")
	var runs := RunHistory.load_all()
	var stats := Label.new()
	stats.text = "No runs saved yet. Runs are saved at every dawn and after each round." if runs.is_empty() \
		else "\n".join(RunStats.report(runs).slice(0, 6))
	stats.add_theme_font_size_override("font_size", 13)
	_box.add_child(stats)
	var hint := Label.new()
	hint.text = "To share runs, download them as one file and attach it to a chat message."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiKit.HINT_COLOR)
	_box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
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
	_box.add_child(buttons)
	if not runs.is_empty():
		var copy_all := Button.new()
		copy_all.text = "Copy all runs"
		copy_all.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(JSON.stringify(runs.map(RunHistory.compact)))
			copy_all.text = "Copied!")
		buttons.add_child(copy_all)
		if OS.has_feature("web"):
			var download_all := Button.new()
			download_all.text = "Download all runs (one file)"
			download_all.tooltip_text = "Saves every run as one file. Attach that file to a chat message to share it."
			download_all.pressed.connect(func() -> void:
				JavaScriptBridge.download_buffer(JSON.stringify(runs.map(RunHistory.compact)).to_utf8_buffer(),
					"runs-%s.json" % Time.get_date_string_from_system(), "application/json"))
			buttons.add_child(download_all)
	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func() -> void:
		if was_end_screen:
			show_end()
		elif run.phase == RunState.Phase.RELIC:
			show_relic_pick()
		else:
			hide())
	buttons.add_child(close)
	show()


## Dev panel: change recipe prices and work times and the price levels live.
## Changes last until the page reloads; "Copy values" puts them on the clipboard to send.
func show_tuning() -> void:
	var content := run.content
	_clear()
	_title("Tune the market (dev)")
	var grid := GridContainer.new()
	grid.columns = 3
	_box.add_child(grid)
	for header: String in ["Recipe", "Price per tier", "Work (seconds)"]:
		var l := Label.new()
		l.text = header
		l.add_theme_color_override("font_color", UiKit.HEADING_COLOR)
		grid.add_child(l)
	var ids: Array = content.market["recipes"].keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = content.market["recipes"][id]
		var l := Label.new()
		l.text = content.recipe_name(id)
		grid.add_child(l)
		for key: String in ["price", "work"]:
			# Smelting recipes fill the stock instead of a stall, so they have no price.
			if not r.has(key):
				grid.add_child(Control.new())
				continue
			var spin := SpinBox.new()
			spin.min_value = 1
			spin.max_value = 200
			spin.value = float(r[key])
			spin.value_changed.connect(func(v: float) -> void: r[key] = v)
			grid.add_child(spin)
	for level: String in ["cheap", "fair", "dear"]:
		var l := Label.new()
		l.text = "%s price x" % level.capitalize()
		grid.add_child(l)
		var spin := SpinBox.new()
		spin.min_value = 0.1
		spin.max_value = 5.0
		spin.step = 0.1
		spin.value = float(content.market["price_levels"][level])
		spin.value_changed.connect(func(v: float) -> void: content.market["price_levels"][level] = v)
		grid.add_child(spin)
		grid.add_child(Control.new())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(buttons)
	var copy := Button.new()
	copy.text = "Copy values"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(JSON.stringify({"price_levels": content.market["price_levels"], "recipes": content.market["recipes"]}))
		copy.text = "Copied!")
	buttons.add_child(copy)
	UiKit.button(buttons, "Back", func() -> void: tuning_closed.emit())
	show()


func _clear() -> void:
	for child in _box.get_children():
		child.queue_free()


func _title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
