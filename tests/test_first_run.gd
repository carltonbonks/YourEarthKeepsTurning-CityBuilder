extends TestCase
## The title screen, how a round works before every run, the one-time tips and the settings. Settings
## are never written to disk here (persist off).


func _screen() -> Control:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.set("save_runs", false)
	screen.call("_ready")
	var settings: GameSettings = screen.get("settings")
	settings.persist = false
	settings.tips = true
	settings.tips_seen = []
	return screen


func test_the_game_opens_on_the_title_screen_and_a_run_on_how_a_round_works() -> void:
	var screen := _screen()
	var title: TitleScreen = screen.get("_title_screen")
	var overlays: Overlays = screen.get("_overlays")
	check(title.visible, "the game opens on the title screen")
	(title as TitleScreen).start_pressed.emit(4821)
	check(not title.visible, "New run leaves the title screen")
	var run: RunState = screen.get("run")
	check_eq(run.run_seed, 4821, "Play a seed starts that seed")
	check(overlays.visible and overlays.welcome_pending, "a new run opens on how a round works")
	check(_has_text(overlays, "You rule. You don't command."), "the round screen shows its words")
	overlays.welcome_pending = false
	overlays.show_for_phase()
	check(_has_text(overlays, "Found the town"), "after it comes the traditions pick")
	screen.call("_restart", true)
	check(overlays.welcome_pending, "every run opens on it again, not just the first")
	screen.call("_show_title")
	check(title.visible and not overlays.visible, "the menu's Title screen goes back to it")
	run = screen.get("run")
	run.dispose()
	screen.free()


func test_tips_come_once_each_at_their_moment() -> void:
	var screen := _screen()
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var tips: FirstTips = screen.get("_tips")
	var settings: GameSettings = screen.get("settings")
	check(FirstTips.due(run).is_empty(), "no tip while the traditions are being chosen")
	run.choose_traditions([])
	check_eq(FirstTips.due(run), ["first_build", "first_attack"] as Array[String], "the first build brings the build and attack tips")
	screen.call("_refresh")
	check_eq(tips.shown_id(), "first_build", "the build tip shows first")
	settings.tips_seen.append("first_build")
	tips.call("_close")
	screen.call("_refresh")
	check_eq(tips.shown_id(), "first_attack", "then the attack tip")
	settings.tips_seen.append("first_attack")
	tips.call("_close")
	screen.call("_refresh")
	check_eq(tips.shown_id(), "", "a seen tip never comes back")
	AutoPlayer.new().build(run)
	run.begin_round()
	check(FirstTips.due(run).has("first_dawn"), "the first dawn has its tip")
	screen.set("_menu_open", true)
	screen.call("_refresh_live")
	check(not tips.visible, "a tip waits while the menu is open")
	screen.set("_menu_open", false)
	settings.tips = false
	screen.call("_refresh_live")
	check(not tips.visible, "tips switched off never show")
	for id: String in run.content.tips["tips"]:
		check(["hand", "threat", "top", "map"].has(run.content.tips["tips"][id]["at"]), "%s says where it sits" % id)
	run.dispose()
	screen.free()


func test_keys_can_be_moved_and_never_double_up() -> void:
	var settings := GameSettings.new()
	settings.persist = false
	settings.apply_keys()
	settings.rebind("pause", KEY_P)
	check_eq(settings.keys["pause"], KEY_P, "pause moves to P")
	check(InputMap.action_get_events("pause")[0] is InputEventKey and (InputMap.action_get_events("pause")[0] as InputEventKey).keycode == KEY_P, "the input map follows")
	settings.rebind("menu", KEY_P)
	check_eq(settings.keys["menu"], KEY_P, "the menu takes P")
	check_eq(settings.keys["pause"], KEY_ESCAPE, "pause takes the menu's old key rather than sharing P")
	settings.rebind("menu", KEY_ESCAPE)
	settings.rebind("pause", KEY_SPACE)
	check_eq(settings.keys, GameSettings.DEFAULT_KEYS, "back to the defaults")


func test_settings_screen_and_loss_line_show() -> void:
	var screen := _screen()
	screen.call("_new_run", 4821)
	var overlays: Overlays = screen.get("_overlays")
	overlays.show_settings()
	check(_has_text(overlays, "Interface size"), "the settings screen shows")
	overlays.show_welcome(false)
	check(_has_text(overlays, "Back"), "How to play opens the round screen with Back")
	var run: RunState = screen.get("run")
	run.phase = RunState.Phase.LOST
	overlays.show_end()
	check(_has_text(overlays, run.content.tips["welcome"]["lost_line"]), "a lost run says it is one more story lost to time")
	run.dispose()
	screen.free()


func _has_text(node: Node, text: String) -> bool:
	if (node is Label and (node as Label).text == text) or (node is Button and (node as Button).text == text):
		return true
	for child in node.get_children():
		if _has_text(child, text):
			return true
	return false
