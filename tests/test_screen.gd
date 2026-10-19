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
	# and every tool set and caravan good in the building hand.
	var screen: Control = load("res://game/main.tscn").instantiate()
	screen.call("_ready")
	screen.call("_new_run", 4821)
	var run: RunState = screen.get("run")
	run.age = "medieval"
	for good: String in run.content.ages["trader"]["goods"]:
		run.trader_stock[good] = 1
	screen.call("_refresh")
	var hand: BuildHandView = screen.get("_hand_view")
	var labels := []
	for card in hand.find_children("*", "Label", true, false):
		labels.append((card as Label).text)
	check(labels.has("Iron ploughs and axes"), "a medieval tool set is a card in the hand")
	check(labels.has("1 tin"), "the caravan's goods are cards in the hand")
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
	check(texts.has("Knight a champion"), "the knighting card shows")
	check(texts.has("Promote a craftsperson"), "the master craftsperson card shows")
	run.dispose()
	screen.free()
