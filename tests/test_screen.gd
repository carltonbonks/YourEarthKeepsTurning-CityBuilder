extends TestCase
## Smoke test for the game screen: builds the real UI and plays a seeded run
## through it with the bot, refreshing every panel and overlay on the way, so a
## broken UI script shows up as a script error (tools/test.sh fails on those).
## Skips Run history saving so tests never write runs to disk.


func test_screen_shows_every_phase_of_a_run() -> void:
	# Built outside the scene tree (the test runner has no frames), so _ready is called by hand.
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
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
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
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
	# The kind of card is the band along its top, in capitals (CardView).
	check(texts.has("KNIGHT A CHAMPION"), "the knighting card shows")
	check(texts.has("PROMOTE A CRAFTSPERSON"), "the master craftsperson card shows")
	run.dispose()
	screen.free()


func test_the_draft_is_a_pick_to_answer_before_building() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	run.choose_traditions([])
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
	var overlays: Overlays = screen.get("_overlays")
	var hand: BuildHandView = screen.get("_hand_view")
	check(overlays.visible and overlays.showing_draft, "the round's draft opens as a pick screen")
	var offer: String = run.content.buildings[run.hand.cards[0]["building"]]["name"]
	var on_screen := overlays.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check(on_screen.has(offer), "the offers are on the pick screen")
	var heads := " ".join(PackedStringArray(hand.find_children("*", "RichTextLabel", true, false).map(func(l: RichTextLabel) -> String: return l.text)))
	check("CORE" in heads and "YOUR BLUEPRINTS" in heads, "the hand is split into labelled sections")
	# Nothing gets past it: closing the menu brings it back, and the round can't begin.
	overlays.show_menu(true)
	screen.call("_close_menu")
	check(overlays.visible and overlays.showing_draft, "closing the menu goes back to the draft")
	screen.call("_begin_round")
	check_eq(run.phase, RunState.Phase.BUILD, "the round can't begin before the draft is taken")
	while run.hand.picks > 0 and not run.hand.cards.is_empty():
		run.hand.draft(run.hand.cards[0]["building"])
		screen.call("_refresh")
	check(not overlays.visible, "the pick screen goes once the draft is taken, and building can start")
	screen.call("_begin_round")
	check(run.phase != RunState.Phase.BUILD, "then the round begins")
	run.dispose()
	screen.free()


func test_night_closes_in_on_the_town_and_keeps_the_speed() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
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
	var aim := NightCamera.frame(run)
	check_eq(aim[1], town * NightCamera.LOOSE, "on a quiet night the view keeps a little room round the town")
	check(is_equal_approx(arena.zoom, maxf(1.5, arena.zoom_to_fit(aim[1], NightCamera.FILL))), "the town fills most of the view")
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


func test_the_attack_night_frames_the_way_it_comes_in() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var w := run.world
	w.wave_sides = [0.0]
	w.time = w.day_length() * (run.content.int_num("days_per_round") - 1)
	var aim := NightCamera.frame(run)
	var far := run.content.num("meet_attack_at") + NightCamera.FIGHT_MARGIN
	check(Vector2(aim[0]).x > 0.0 and is_zero_approx(Vector2(aim[0]).y), "the view slides toward the way the attack comes in")
	check(Vector2(aim[0]).x + float(aim[1]) >= far - 0.01, "it reaches out to where heroes meet the attack")
	check(Vector2(aim[0]).x - float(aim[1]) <= -NightCamera.town_radius(run) * NightCamera.LOOSE + 0.01, "and still holds the whole town")
	w.wave_sides = [0.0, PI]
	aim = NightCamera.frame(run)
	check(Vector2(aim[0]).is_zero_approx() and is_equal_approx(aim[1], far), "attacks from two ways widen the view round the hearth")
	w.time = 0.0
	check(is_equal_approx(NightCamera.frame(run)[1], NightCamera.town_radius(run) * NightCamera.LOOSE), "earlier nights frame just the town")
	run.dispose()


func test_a_won_run_celebrates_round_the_hearth_before_the_end_screen() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var arena: ArenaView = screen.get("_arena")
	var overlays: Overlays = screen.get("_overlays")
	arena.set_anchors_preset(Control.PRESET_TOP_LEFT)
	arena.size = Vector2(1600, 830)
	overlays.hide()
	arena.zoom = 1.2
	arena.pan = Vector2(150, 0)
	run.phase = RunState.Phase.WON
	screen.call("_on_pause")
	check(arena.victory_playing(), "winning starts the celebration")
	check(not overlays.visible, "the end screen waits while it plays")
	var start := arena.victory.born
	var hero: Unit = run.living_heroes()[0] if not run.living_heroes().is_empty() else null
	var folk: Unit = run.world.folk[0]
	check(folk.pos.distance_to(arena.victory.place(folk, start)) < 0.01, "everyone starts where they stood")
	var home := arena.victory.place(folk, start + Victory.GATHER_MS)
	check(home.length() >= Victory.FIRST_RING - 0.01 and home.length() < Victory.FIRST_RING + 60.0, "then stands round the hearth")
	check(arena.victory.hop(folk, start + Victory.GATHER_MS * 0.5) == 0.0, "nobody jumps on the way home")
	var hops := range(20).map(func(i: int) -> float: return arena.victory.hop(folk, start + Victory.GATHER_MS + 400.0 + i * 50.0))
	check(hops.max() > 0.5, "once home they jump")
	if hero != null:
		check(arena.victory.place(hero, start + Victory.GATHER_MS).length() < home.length() + 0.01, "heroes stand nearest the fire")
	check(arena.victory.night_left(start + Victory.DAWN_MS) == 0.0, "the night lifts")
	check(not arena.victory.update(arena, start + 100.0), "the end screen does not open at once")
	arena.victory.update(arena, start + Victory.CAMERA_MS)
	check(arena.zoom > 1.2 and arena.pan.is_zero_approx(), "the camera closes in on the hearth")
	check(arena.victory.update(arena, start + Victory.SHOW_MS), "the end screen opens by itself after a while")
	check(not arena.victory.update(arena, start + Victory.SHOW_MS + 100.0), "and only once")
	run.dispose()
	screen.free()


func test_a_click_skips_to_the_end_screen() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var arena: ArenaView = screen.get("_arena")
	var overlays: Overlays = screen.get("_overlays")
	overlays.hide()
	run.phase = RunState.Phase.WON
	screen.call("_on_pause")
	arena.skip_victory()
	check(overlays.visible and not arena.victory_playing(), "skipping opens the end screen")
	check(arena.victory.active(), "the party carries on behind it")
	run.dispose()
	screen.free()


func test_victory_places_everyone_in_rings_round_the_hearth() -> void:
	var spots := Victory.layout(5, 200)
	check_eq(spots.size(), 205, "a place for everyone")
	for i in spots.size():
		for j in range(i + 1, mini(i + 40, spots.size())):
			check(spots[i].distance_to(spots[j]) > Victory.FOLK_SPACING * 0.5, "places don't overlap")
	check(spots[0].length() < spots[204].length(), "heroes first, nearest the fire")
	check(Victory.layout(0, 0).is_empty(), "nobody, no places")


func test_the_earth_turning_pulls_the_camera_out_and_can_be_skipped() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var arena: ArenaView = screen.get("_arena")
	arena.set_anchors_preset(Control.PRESET_TOP_LEFT)
	arena.size = Vector2(1280, 720)
	arena.call("_watch_shift")
	check(not arena.turn_playing(), "showing a run for the first time is not a turn")
	arena.zoom = 3.0
	arena.pan = Vector2(150, 80)
	run.world.earth.shift()
	arena.call("_watch_shift")
	check(arena.turn_playing(), "a turn of the earth starts the beat")
	check_eq(TurnCamera.weight_at(0.0), 0.0, "the beat starts from the player's camera")
	check_eq(TurnCamera.weight_at(TurnCamera.BEAT_MS / 2.0), 1.0, "mid-beat every ring is in view")
	check_eq(TurnCamera.weight_at(TurnCamera.BEAT_MS), 0.0, "the beat ends on the player's camera")
	var rings: Array = run.content.plates["rings"]
	check(arena.zoom_to_fit(float(rings[-1]["r1"]), TurnCamera.FILL) < 3.0, "zoomed in, the widest view is wider than the player's")
	arena.zoom = 0.9
	arena.pan = Vector2.ZERO
	# The pause key calls this while the beat plays (main.gd), so Space skips it.
	arena.skip_turn()
	check(not arena.turn_playing(), "skipping ends the beat")
	check_eq(arena.zoom, 3.0, "skipping gives the zoom back")
	check_eq(arena.pan, Vector2(150, 80), "skipping gives the camera back")
	run.dispose()
	screen.free()


func test_a_venture_shows_its_dead_as_red_crosses() -> void:
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
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


func test_two_picks_a_dawn_keeps_the_pick_open() -> void:
	# Twin Fires and Antler Crown take two newcomers a dawn: after the first, the pick must show again
	# (it used to hide, leaving neither the cards nor the Begin round button).
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.set("save_runs", false)
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	run.choose_traditions([])
	run.call("_gain_relic", "antler_crown")
	AutoPlayer.new().build(run)
	screen.call("_begin_round")
	var overlays: Overlays = screen.get("_overlays")
	check_eq(run.phase, RunState.Phase.PICK, "the round opens on a dawn pick")
	check_eq(run.picks_left, 2, "the crown gives two picks")
	var first := -1
	for i in run.pick_offer.size():
		if run.pick_offer[i]["kind"] == "folk":
			first = i
			break
	check(first >= 0, "a newcomer is on offer")
	screen.call("_take_pick", first)
	check_eq(run.phase, RunState.Phase.PICK, "the dawn waits for the second newcomer")
	check(overlays.visible, "the dawn pick shows again for the second newcomer")
	screen.call("_take_pick", 0)
	check_eq(run.phase, RunState.Phase.SIM, "the day begins after the second pick")
	check(not overlays.visible, "and the pick closes")
	run.dispose()
	screen.free()


func test_a_pedlar_round_opens_on_the_pedlar_choice_after_the_relic() -> void:
	# Every round ends on a relic pick, so the pedlar choice must show once the relic is taken
	# (it used to be hidden, and starting the round quietly invited nobody).
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.set("save_runs", false)
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
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


func test_pick_screens_wait_for_the_earth_to_turn() -> void:
	# Playtest 2026-10-25: the draft and pedlar pop-ups hid the earth turning. They wait until its beat has played
	# or Space skipped it.
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.set("save_runs", false)
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	run.choose_traditions([])
	var arena: ArenaView = screen.get("_arena")
	arena.set_anchors_preset(Control.PRESET_TOP_LEFT)
	arena.size = Vector2(1280, 720)
	arena.call("_watch_shift")
	run.round_number = int(run.content.pedlars["every"]) - 1
	run.phase = RunState.Phase.RELIC
	screen.call("_pick_relic", "")
	var overlays: Overlays = screen.get("_overlays")
	check(run.awaiting_pedlar(), "the new round is a pedlar round")
	check(arena.turn_pending(), "the earth has turned and its beat is still to play")
	check(not overlays.visible, "the pedlar choice waits for the earth")
	screen.call("_refresh")
	check(not overlays.visible, "a refresh doesn't bring up a pick screen meanwhile")
	arena.call("_watch_shift")
	arena.skip_turn()
	screen.call("_process", 0.0)
	check(overlays.visible, "once the beat is skipped the pedlar choice shows")
	run.dispose()
	screen.free()


func test_the_nights_last_kill_slows_time_and_holds_the_pick() -> void:
	check_eq(LastKill.speed_at(0.0, 8.0), LastKill.SLOW_SPEED, "time slows when the last raider falls")
	check_eq(LastKill.speed_at(LastKill.SLOW_UNTIL_MS - 1.0, 4.0), LastKill.SLOW_SPEED, "and stays slow while the kill is held")
	check(LastKill.speed_at(LastKill.BEAT_MS - 100.0, 8.0) > LastKill.SLOW_SPEED, "then eases back")
	check_eq(LastKill.speed_at(LastKill.BEAT_MS, 8.0), 8.0, "to the player's speed")
	check_eq(LastKill.speed_at(500.0, 0.0), 0.0, "a paused game stays paused")
	check_eq(LastKill.weight_at(0.0), 0.0, "the camera starts where the player had it")
	check_eq(LastKill.weight_at(LastKill.BEAT_MS / 2.0), 1.0, "leans in on the kill")
	check_eq(LastKill.weight_at(LastKill.BEAT_MS), 0.0, "and ends where the player had it")

	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	(screen.get("settings") as GameSettings).intro_seen = true  # No first-run tour here.
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	var arena: ArenaView = screen.get("_arena")
	var overlays: Overlays = screen.get("_overlays")
	arena.set_anchors_preset(Control.PRESET_TOP_LEFT)
	arena.size = Vector2(1280, 720)
	var bot := AutoPlayer.new()
	var beats := 0
	var nights_with_raiders := 0
	# Play rounds with the bot, watching every step as main.gd does, until a beat holds a pick.
	while run.round_number <= 3 and run.phase != RunState.Phase.LOST:
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(bot.pick(run))
			RunState.Phase.RELIC:
				run.choose_relic(bot.pick_relic(run))
			RunState.Phase.SIM:
				var was_night := run.world.is_night()
				run.step()
				if run.world.is_night() and not was_night:
					nights_with_raiders += 1
				if arena.last_kill.watch(arena, run.world):
					beats += 1
					check(not run.world.enemies.any(func(e: Unit) -> bool: return e.alive and e.den_index < 0),
						"the beat starts only once no raider is left")
					check(arena.last_kill.headline() != "", "it says what happened")
					if run.phase != RunState.Phase.SIM:
						overlays.hide()
						screen.call("_on_pause")
						check(not overlays.visible, "the pick waits while the last kill is held")
						# The pause key calls this while the beat plays (main.gd), so Space skips it.
						arena.skip_last_kill()
						check(not arena.last_kill_playing(), "skipping ends the beat")
						screen.call("_process", 0.016)
						check(overlays.visible, "then the pick opens")
					arena.last_kill.skip(arena)
	check(beats > 0, "the night's last kill is held at least once in three rounds")
	check(beats <= nights_with_raiders, "at most once a night")
	run.dispose()
	screen.free()

