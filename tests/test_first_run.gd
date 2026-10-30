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


func test_the_game_opens_on_the_title_screen_and_a_first_run_on_the_tour() -> void:
	var screen := _screen()
	var settings: GameSettings = screen.get("settings")
	settings.intro_seen = false
	var title: TitleScreen = screen.get("_title_screen")
	var overlays: Overlays = screen.get("_overlays")
	var tour: IntroTour = screen.get("_tour")
	var arena: ArenaView = screen.get("_arena")
	check(title.visible, "the game opens on the title screen")
	check(not tour.playing(), "the run behind the title screen plays no tour")
	(title as TitleScreen).start_pressed.emit(4821)
	check(not title.visible, "New run leaves the title screen")
	var run: RunState = screen.get("run")
	check_eq(run.run_seed, 4821, "Play a seed starts that seed")
	check(tour.playing() and not overlays.visible, "a first run opens on the tour, with no pop-up over it")
	check(arena.run != run and arena.run == tour.prologue, "the tour films its own prologue, not the run")
	check(run.gentle, "a first run starts gently")
	check(not (screen.get("_top") as Control).visible, "the top bar is out of the way during the tour")
	tour.finish()
	check(settings.intro_seen, "the tour marks the first run seen")
	check(arena.run == run, "the map shows the run again")
	check(overlays.visible and _has_text(overlays, "Found the town"), "after the tour comes the traditions pick, not the round screen")
	check(run.awaiting_traditions() and run.round_number == 1, "the run waits where it started")
	screen.call("_restart", true)
	run = screen.get("run")
	check(tour.playing() and not run.gentle, "a later run opens on the tour too, without the gentle start")
	check(not overlays.visible and not overlays.welcome_pending, "with no round screen over or after it")
	tour.finish()
	check(overlays.visible and _has_text(overlays, "Found the town"), "and goes on to the traditions pick")
	settings.tour = false
	screen.call("_restart", true)
	run = screen.get("run")
	check(not tour.playing() and not run.gentle, "with the tour turned off, a later run has no tour")
	check(overlays.visible and overlays.welcome_pending, "and opens on how a round works")
	check(_has_text(overlays, "You rule. You don't command."), "the round screen shows its words")
	screen.call("_show_title")
	check(title.visible and not overlays.visible, "the menu's Title screen goes back to it")
	overlays.show_welcome(false, true)
	check(_has_text(overlays, "Play the first-run intro again"), "How to play on the title screen can replay the intro")
	overlays.intro_requested.emit()
	check(tour.playing() and not settings.intro_seen and (screen.get("run") as RunState).gentle, "which starts a run on the tour")
	tour.finish()
	run = screen.get("run")
	run.dispose()
	screen.free()


func test_the_tour_films_a_real_prologue_and_leaves_the_run_alone() -> void:
	var content := Content.load_default()
	var before := RunState.new(content, 4821)
	var prologue := IntroTour.make_prologue(content, 4821)
	check_eq(prologue.phase, RunState.Phase.SIM, "the prologue is playing its first day")
	check(prologue.world.time >= IntroTour.PRE_ROLL_SECONDS - 0.5, "it starts a little into the day, people already out")
	IntroTour.advance(prologue, 50.0)
	check(prologue.phase == RunState.Phase.SIM or prologue.phase == RunState.Phase.PICK, "it plays on by itself, taking each dawn's newcomer")
	check(IntroTour.pick_hero(prologue) != null, "the hero shot has a hero to follow")
	check(IntroTour.pick_den(prologue) != Vector2.ZERO, "the den shot has a den on the attack's way")
	var after := RunState.new(content, 4821)
	check_eq(after.stock, before.stock, "a run of the same seed starts the same after a prologue")
	check(not after.traditions_settled, "and still waits on its tradition")
	for shot: Dictionary in content.tips["tour"]:
		check(["hearth", "town", "hero", "den", "map"].has(shot["shot"]) and str(shot["text"]) != "", "tour shot %s has a place and a caption" % shot["shot"])
	var total := 0.0
	for shot: Dictionary in content.tips["tour"]:
		total += float(shot["seconds"])
	check(total <= 30.0, "the tour is short (%.0f s)" % total)
	for r in [before, prologue, after]:
		r.dispose()


func test_highlights_come_once_each_at_their_moment_and_close_when_done() -> void:
	var screen := _screen()
	screen.call("_new_run", 4821, false)
	var run: RunState = screen.get("run")
	var tips: FirstTips = screen.get("_tips")
	var settings: GameSettings = screen.get("settings")
	var overlays: Overlays = screen.get("_overlays")
	overlays.welcome_pending = false
	overlays.show_for_phase()
	# Headless, nothing has a size: give every target a place on screen.
	tips.target_rect = func(_name: String) -> Rect2: return Rect2(100, 100, 200, 80)
	check_eq(FirstTips.due(run), ["first_tradition"] as Array[String], "the tradition pick has its highlight")
	screen.call("_refresh_live")
	check_eq(tips.shown_id(), "first_tradition", "it shows")
	check(not tips.framed().is_empty(), "framing the pick")
	# The pick moves (laid out, fitted to the window, resized): the frame follows it on the next frame.
	tips.target_rect = func(_name: String) -> Rect2: return Rect2(300, 200, 600, 320)
	tips._process(0.0)
	check_eq(tips.framed(), [Rect2(300, 200, 600, 320).grow(FirstTips.PAD)] as Array[Rect2], "the frame follows its target's rect")
	run.choose_traditions(["stoneworkers"])
	check_eq(FirstTips.due(run), ["first_draft"] as Array[String], "then the draft")
	screen.call("_refresh_live")
	check(settings.tips_seen.has("first_tradition"), "choosing the tradition closed its highlight for good")
	check_eq(tips.shown_id(), "first_draft", "the draft's highlight follows")
	if not run.hand.cards.is_empty():
		run.hand.draft(run.hand.cards[0]["building"])
	else:
		run.hand.draft_craft(run.hand.crafts[0]["craft"])
	check_eq(FirstTips.due(run), ["first_build"] as Array[String], "with the draft taken, build a hut")
	screen.call("_refresh_live")
	check_eq(tips.shown_id(), "first_build", "the build highlight shows")
	check(run.hand.order("hut"), "a hut can be ordered")
	check_eq(FirstTips.due(run), ["first_begin"] as Array[String], "once something is built, Begin round")
	screen.call("_refresh_live")
	check(settings.tips_seen.has("first_build") and tips.shown_id() == "first_begin", "building closed the build highlight")
	run.begin_round()
	check(FirstTips.due(run).has("first_dawn"), "the first dawn has its highlight")
	check_eq(FirstTips.targets(run.content.tips["tips"]["first_dawn"]), ["panel", "food"] as Array[String], "it frames the pick and the food")
	screen.set("_menu_open", true)
	screen.call("_refresh_live")
	check(not tips.visible, "a highlight waits while the menu is open")
	check(not settings.tips_seen.has("first_dawn"), "and isn't marked seen for it")
	screen.set("_menu_open", false)
	tips.target_rect = func(_name: String) -> Rect2: return Rect2()
	screen.call("_refresh_live")
	check(not tips.visible, "a highlight whose target isn't on screen waits")
	settings.tips = false
	screen.call("_refresh_live")
	check(not tips.visible, "tips switched off never show")
	for id: String in run.content.tips["tips"]:
		for t in FirstTips.targets(run.content.tips["tips"][id]):
			check(["panel", "core", "begin", "upgrades", "threat", "food"].has(t), "%s frames something the screen knows (%s)" % [id, t])
	run.dispose()
	screen.free()


func test_the_note_never_covers_what_it_frames() -> void:
	var screen := Rect2(0, 0, 1280, 720)
	var note := Vector2(330, 150)
	# The build hand's Core section along the bottom: no room below, so the note goes above it.
	var core: Array[Rect2] = [Rect2(8, 446, 308, 192)]
	var at := FirstTips.note_spot(screen, core, note)
	check(not Rect2(at, note).intersects(core[0]), "the note sits clear of the hand")
	check(at.y + note.y <= core[0].position.y, "above it")
	# A tall pop-up filling most of the screen: the note still finds a free side.
	var big: Array[Rect2] = [Rect2(380, 40, 560, 640)]
	at = FirstTips.note_spot(screen, big, note)
	check(not Rect2(at, note).intersects(big[0]), "the note sits beside a tall pop-up")
	check(screen.encloses(Rect2(at, note)), "and on screen")


func test_the_dimming_leaves_the_framed_parts_clear() -> void:
	var screen := Rect2(0, 0, 100, 100)
	var holes: Array[Rect2] = [Rect2(20, 20, 30, 30), Rect2(60, 0, 10, 10)]
	var cells := FirstTips.dim_cells(screen, holes)
	var area := 0.0
	for c in cells:
		area += c.get_area()
		for h in holes:
			check(not c.intersects(h), "no dim cell over a hole")
	check(is_equal_approx(area, 10000.0 - 900.0 - 100.0), "everything else is dimmed (%.0f)" % area)


func test_a_tradition_brings_its_blueprint_in_place_of_a_draft() -> void:
	var content := Content.load_default()
	for id: String in content.traditions:
		var key: String = content.traditions[id].get("blueprint", "")
		check(key != "", "%s brings a blueprint" % id)
		check(content.buildings.has(key) or (key.begins_with("craft:") and content.crafts.has(key.trim_prefix("craft:"))), "%s's blueprint %s exists" % [id, key])
	var run := RunState.new(content, 4821)
	var picks := run.hand.picks
	run.choose_traditions(["stoneworkers"])
	check(run.hand.blueprints.has("watch_post"), "Stoneworkers start with the watch post")
	check_eq(run.hand.picks, picks - 1, "in place of one of round 1's drafts")
	check(not run.hand.cards.any(func(c: Dictionary) -> bool: return c["building"] == "watch_post"), "and the draft doesn't offer it again")
	check(run.record.entry["actions"].any(func(a: Dictionary) -> bool: return a["kind"] == "tradition_blueprint" and a.get("building") == "watch_post"), "the record says so")
	run.dispose()
	run = RunState.new(content, 4821)
	run.choose_traditions(["smiths"])
	check(run.hand.crafts_taken.has("arms"), "Smiths start with the arms craft")
	for type in ["market", "knapper", "arms_stall"]:
		check(run.hand.blueprints.has(type), "which brings the %s" % type)
	run.dispose()
	run = RunState.new(content, 4821)
	run.choose_traditions([])
	check_eq(run.hand.picks, picks, "no tradition keeps both drafts")
	run.dispose()


func test_a_gentle_first_run_starts_with_a_few_tribespeople() -> void:
	var content := Content.load_default()
	var run := RunState.new(content, 4821)
	run.gentle = true
	run.choose_traditions([])
	check(not run.hand.can_redraw(), "the first draft has no reroll")
	AutoPlayer.new().build(run)
	run.begin_round()
	check_eq(run.pick_offer.size(), content.int_num("gentle_first_dawn"), "the first dawn offers a few cards")
	check(run.pick_offer.all(func(c: Dictionary) -> bool: return c["kind"] == "folk" and c["role"] == "tribesperson"), "all tribespeople")
	run.choose_pick(0)
	run.run_until_pause()
	check(run.phase != RunState.Phase.PICK or run.pick_offer.any(func(c: Dictionary) -> bool: return c["role"] != "tribesperson") \
		or run.pick_offer.size() > content.int_num("gentle_first_dawn"), "the second dawn deals as usual")
	check(StatusText.bar_goods(run).size() >= 2 and not StatusText.chip_shown(run, "relics"), "round 1 keeps the bar short: no relics chip")
	run.dispose()
	run = RunState.new(content, 4821)
	run.choose_traditions([])
	run.round_number = 2
	check(StatusText.bar_goods(run).has("shells") and StatusText.chip_shown(run, "relics"), "from round 2 the bar shows shells and relics")
	run.dispose()


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
