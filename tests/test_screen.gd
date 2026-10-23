extends TestCase
## Smoke test for the game screen: builds the real UI and plays a seeded run
## through it with the bot, refreshing every panel and overlay on the way, so a
## broken UI script shows up as a script error (tools/test.sh fails on those).
## Skips Run history saving so tests never write runs to disk.


func test_screen_shows_every_phase_of_a_run() -> void:
	# Built outside the scene tree (the test runner has no frames), so _ready is called by hand.
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var bot := AutoPlayer.new()
	bot.style = "medieval"
	var seen := {}
	var steps := 0
	while not run.is_over() and steps < 400:
		steps += 1
		seen[run.phase] = true
		screen.call("_refresh")
		var overlays: Overlays = screen.get("_overlays")
		overlays.show_for_phase()
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				screen.call("_refresh")
				run.begin_round()
			RunState.Phase.PICK:
				check(overlays.visible, "the dawn pick shows")
				run.choose_pick(bot.pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				check(overlays.visible, "the relic pick shows")
				run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
	check(run.is_over(), "the bot finishes the run through the screen")
	check(seen.has(RunState.Phase.BUILD) and seen.has(RunState.Phase.PICK) and seen.has(RunState.Phase.RELIC), "every decision phase was shown")
	var overlays: Overlays = screen.get("_overlays")
	overlays.show_for_phase()
	check(overlays.visible, "the end screen shows")
	overlays.show_history()
	overlays.show_tuning()
	for id: String in StatusText.CHIPS:
		check(StatusText.chip(run, id) != "", "the top bar's %s chip is filled in" % id)
		check(not StatusText.chip_tip(run, id).is_empty(), "the %s chip has a hover card" % id)
	check(not ThreatCard.tip(run).is_empty(), "the attack has a hover card")
	overlays.show_menu(true)
	overlays.show_log()
	check(overlays.visible, "the menu and the full log show")
	run.dispose()
	screen.free()


func test_every_kind_of_card_shows() -> void:
	# The medieval cards a seeded bot may never be dealt: family, knighting, a master craftsperson,
	# and every tool set and some caravan deals in the building hand.
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	run.age = "medieval"
	for id: String in ["tin_bundle", "sellswords", "relic_dealer"]:
		run.caravan.offers.append({"deal": id, "need": "", "taken": false})
	screen.call("_refresh")
	var hand: BuildHandView = screen.get("_hand_view")
	var labels := []
	for card in hand.find_children("*", "Label", true, false):
		labels.append((card as Label).text)
	check(labels.has("Iron ploughs and axes"), "a medieval tool set is a card in the hand")
	check(labels.has("Bundle of tin") and labels.has("Relic dealer"), "the caravan's deals are cards in the hand")
	run.begin_round()
	check_eq(run.phase, RunState.Phase.PICK, "the round opens on a dawn pick")
	var champion := run.people.make_hero()
	champion.type_id = "champion"
	var crafter: Unit = run.world.folk[0]
	crafter.made["knapper"] = 9
	run.pick_offer = [
		{"kind": "family", "role": "family", "cost": 0, "roles": ["tribesperson", "tribesperson", "craftsperson"]},
		{"kind": "promote", "role": "champion", "cost": 25, "hero": champion},
		{"kind": "promote", "role": "craftsperson", "cost": 10, "unit": crafter, "workshop": "knapper", "trait": "gifted", "name": "Ada"},
	]
	var overlays: Overlays = screen.get("_overlays")
	overlays.show_pick()
	var texts := []
	for l in overlays.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	check(texts.has("A family"), "the family card shows")
	# Rarer cards add their rarity to the top line ("Knight a champion · Mythic").
	check(texts.any(func(t: String) -> bool: return t.begins_with("Knight a champion")), "the knighting card shows")
	check(texts.any(func(t: String) -> bool: return t.begins_with("Promote a craftsperson")), "the master craftsperson card shows")
	run.dispose()
	screen.free()


func test_the_draft_opens_in_its_own_window_and_the_hand_has_sections() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var bot := AutoPlayer.new()
	while run.phase != RunState.Phase.BUILD or run.hand.picks <= 0 or run.hand.cards.is_empty():
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(bot.pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
	screen.call("_refresh")
	var draft: DraftPopup = screen.get("_draft")
	var hand: BuildHandView = screen.get("_hand_view")
	check(draft.visible and not draft.is_collapsed(), "the round's draft opens in its window")
	var offer: String = run.content.buildings[run.hand.cards[0]["building"]]["name"]
	var in_draft := draft.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	var in_hand := hand.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check(in_draft.has(offer), "the offers are in the window")
	check(not in_hand.has(offer) or run.hand.blueprints.has(run.hand.cards[0]["building"]), "the offers are not in the hand")
	var heads := " ".join(PackedStringArray(hand.find_children("*", "RichTextLabel", true, false).map(func(l: RichTextLabel) -> String: return l.text)))
	check("CORE" in heads and "YOUR BLUEPRINTS" in heads, "the hand is split into labelled sections")
	draft.set_collapsed(true)
	screen.call("_refresh")
	check(draft.is_collapsed(), "a hidden draft stays hidden while the player orders")
	run.hand.draft(run.hand.cards[0]["building"])
	screen.call("_refresh")
	if run.hand.picks <= 0:
		check(not draft.visible, "the window goes once the draft is taken")
	run.begin_round()
	screen.call("_refresh")
	check(not draft.visible, "the window is gone outside the build phase")
	run.dispose()
	screen.free()


func test_night_closes_in_on_the_town_and_keeps_the_speed() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var arena: ArenaView = screen.get("_arena")
	arena.set_anchors_preset(Control.PRESET_TOP_LEFT)
	arena.size = Vector2(1600, 830)
	var bot := AutoPlayer.new()
	bot.build(run)
	run.begin_round()
	run.choose_pick(bot.pick(run))
	arena.zoom = 1.5
	arena.pan = Vector2(200, -100)
	screen.call("_set_speed", 8)
	var tick := func() -> void:
		arena.night.update(arena, 1.0 / 60.0)
	var day := run.content.num("day_seconds")
	while run.world.time_of_day() < day - NightCamera.LEAD_SECONDS - 1.0:
		run.step()
	tick.call()
	check_eq(arena.zoom, 1.5, "by day the camera stays where the player put it")
	check_eq(screen.get("speed"), 8, "by day the game keeps its speed")
	while not run.world.is_night():
		run.step()
	tick.call()
	check(arena.zoom > 1.5 and arena.pan.length() < 1.0, "at nightfall the camera has closed in on the town")
	var town := NightCamera.town_radius(run)
	check(town > float(run.content.town["rings"][0]["radius"]), "the town's reach covers its buildings")
	check(is_equal_approx(arena.zoom, maxf(1.5, arena.zoom_to_fit(town, NightCamera.FILL))), "the town fills most of the view")
	check_eq(screen.get("speed"), 8, "the night keeps the speed the player picked")
	while run.phase == RunState.Phase.SIM:
		run.step()
	for i in 120:
		tick.call()
	check_eq(arena.zoom, 1.5, "after the night the zoom goes back")
	check_eq(arena.pan, Vector2(200, -100), "after the night the camera goes back")
	check_eq(screen.get("speed"), 8, "the speed never changed")
	# The player takes the camera during the next night: it stays where they leave it.
	run.choose_pick(-1)
	while not run.world.is_night():
		run.step()
	tick.call()
	arena.night.release()
	arena.zoom = 3.0
	while run.phase == RunState.Phase.SIM:
		run.step()
	for i in 120:
		tick.call()
	check_eq(arena.zoom, 3.0, "a camera the player moved at night stays put")
	run.dispose()
	screen.free()


func test_a_venture_shows_its_dead_as_red_crosses() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	AutoPlayer.new().build(run)
	run.begin_round()
	while run.count_role("tribesperson") < 12:
		run.world.folk_ai.add_folk("tribesperson")
	run.pick_offer = [{"kind": "venture", "role": "venture", "cost": 0, "venture": "warthog_cull"}]
	var terms := run.people.venture_terms("warthog_cull")
	var overlays: Overlays = screen.get("_overlays")
	overlays.show_pick()
	var on_card: Array = overlays.find_children("*", "VentureFigures", true, false)
	check_eq(on_card.size(), 1, "the venture card shows its people")
	var row: VentureFigures = on_card[0]
	check_eq(row.send, int(terms["send"]), "one figure per person sent")
	check_eq(row.dead, int(terms["lose"][0]), "a bold cross for each sure death")
	check_eq(row.maybe, int(terms["lose"][1]) - int(terms["lose"][0]), "a faint cross for each who may not come back")
	screen.call("_take_pick", 0)
	check(overlays.visible, "taking the venture shows how it went before the day goes on")
	# The cards are freed at the end of the frame, so the outcome's row is the newest one.
	var outcome: VentureFigures = overlays.find_children("*", "VentureFigures", true, false).back()
	check_eq(outcome.send, int(terms["send"]), "the outcome shows the people sent")
	check_eq(outcome.dead, int(run.last_venture["lost"]), "a red cross for each who never came home")
	check_eq(outcome.maybe, 0, "no maybes once it's done")
	overlays.closed.emit()
	check(not overlays.visible, "carrying on lets the day begin")
	run.dispose()
	screen.free()


func test_a_pedlar_round_opens_on_the_pedlar_choice_after_the_relic() -> void:
	# Every round ends on a relic pick, so the pedlar choice must show once the relic is taken
	# (it used to be hidden, and starting the round quietly invited nobody).
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.set("save_runs", false)
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	run.choose_traditions([])
	run.round_number = int(run.content.pedlars["every"]) - 1
	run.phase = RunState.Phase.RELIC
	screen.call("_pick_relic", "")
	var overlays: Overlays = screen.get("_overlays")
	check(run.awaiting_pedlar(), "the new round is a pedlar round")
	check(overlays.visible, "the pedlar choice shows after the relic pick")
	var buttons := overlays.find_children("*", "Button", true, false)
	check(buttons.any(func(b: Button) -> bool: return b.tooltip_text.contains("Would go")), "it shows the pedlar cards")
	run.choose_pedlar(run.pedlar_offer[0]["id"])
	run.begin_round()
	check(Alerts.active(run).any(func(a: Dictionary) -> bool: return String(a["id"]).begins_with("pedlar")),
		"an alert says where the pedlar camped")
	run.dispose()
	screen.free()
