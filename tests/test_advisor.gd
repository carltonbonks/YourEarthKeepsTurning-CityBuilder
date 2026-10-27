extends TestCase
## The Elder (game/advisor.gd): speaks only while the player chooses, only when a card on screen would help,
## and Not now quiets a problem for the round, then for the run.


## A run past its founding and first draft, in the build phase, with plenty of everything but food.
func _building(seed_value := 4821) -> RunState:
	var run := RunState.new(Content.load_default(), seed_value)
	run.choose_traditions([])
	run.hand.picks = 0
	for good in ["wood", "stone", "shells", "fuel"]:
		run.stock[good] = 999
	run.stock["food"] = 999
	return run


func _ids(run: RunState, level := "urgent") -> Array:
	return Advisor.concerns(run, level).map(func(c: Dictionary) -> String: return c["id"])


func _dawn(run: RunState, cards: Array) -> void:
	run.pick_offer.clear()
	for c: Dictionary in cards:
		var card := {"kind": "folk", "cost": 0}
		card.merge(c)
		run.pick_offer.append(card)
	run.phase = RunState.Phase.PICK


func test_short_food_points_at_a_food_building_in_the_hand() -> void:
	var run := _building()
	check(not _ids(run).has("food"), "a stocked town hears nothing about food")
	run.stock["food"] = 0
	var all := Advisor.concerns(run)
	check(_ids(run).has("food"), "food running out tonight is raised")
	var food: Dictionary = all.filter(func(c: Dictionary) -> bool: return c["id"] == "food")[0]
	check_eq(food["fix"]["kind"], "build", "in the build phase the fix is a card in the hand")
	check(run.hand.feeds(food["fix"]["type"]), "and that building brings food")
	check(run.hand.can_order(food["fix"]["type"]), "and the town can order it now")
	check(str(food["fix_text"]).contains(str(run.content.buildings[food["fix"]["type"]]["name"]).to_lower()), "the line names the card")
	run.dispose()


func test_nothing_to_do_about_it_means_no_word() -> void:
	var run := _building()
	run.stock["food"] = 0
	run.stock["wood"] = 0
	run.stock["stone"] = 0
	check(not _ids(run).has("food"), "a problem the hand can't answer stays a plain alert")
	check(Alerts.active(run).any(func(a: Dictionary) -> bool: return a["id"] == "food"), "the alert still flags it")
	run.dispose()


func test_quiet_while_drafting_off_or_in_a_first_runs_first_round() -> void:
	var run := _building()
	run.stock["food"] = 0
	check(_ids(run).has("food"), "speaks in the build phase")
	check(_ids(run, "off").is_empty(), "the Off setting silences it")
	run.hand.picks = 1
	run.hand.deal()
	if run.hand.has_offers() and run.hand.picks > 0:
		check(_ids(run).is_empty(), "silent while a blueprint draft waits")
	run.hand.picks = 0
	run.gentle = true
	check(_ids(run).is_empty(), "silent through a first run's first round")
	run.round_number = 2
	check(_ids(run).has("food"), "and speaks from round 2")
	run.dispose()


func test_chatty_speaks_sooner() -> void:
	var run := _building()
	var net := run.food_needed_today() - run.food_grown_daily()
	check(net > 0, "the town eats more than it grows")
	run.stock["food"] = int(ceil(net * 1.5))
	check(not _ids(run).has("food"), "a day and a half of food is fine on Urgent only")
	check(_ids(run, "chatty").has("food"), "but Chatty mentions it")
	run.dispose()


func test_at_dawn_it_points_at_the_newcomer_who_helps() -> void:
	var run := _building()
	for u in run.world.folk.filter(func(f: Unit) -> bool: return f.type_id == "craftsperson"):
		run.world.folk.erase(u)
	check(run.build("hut"), "a building waits to be raised")
	check(not _ids(run).has("builders"), "nothing in the hand raises buildings")
	_dawn(run, [{"role": "tribesperson"}, {"role": "craftsperson"}])
	var builders: Array = Advisor.concerns(run).filter(func(c: Dictionary) -> bool: return c["id"] == "builders")
	check_eq(builders.size(), 1, "at dawn the missing builders are raised")
	check_eq(builders[0]["fix"], {"kind": "pick", "index": 1, "name": "craftsperson"}, "pointing at the craftsperson")
	run.dispose()


func test_a_leaning_that_brings_the_good_is_preferred() -> void:
	var run := _building()
	run.stock["food"] = 0
	_dawn(run, [{"role": "tribesperson", "leaning": "woodcutter"}, {"role": "warrior"}, {"role": "tribesperson", "leaning": "forager"}])
	var food: Array = Advisor.concerns(run).filter(func(c: Dictionary) -> bool: return c["id"] == "food")
	check_eq(food[0]["fix"]["index"], 2, "the forager over the woodcutter")
	_dawn(run, [{"role": "tribesperson", "leaning": "woodcutter"}, {"role": "warrior"}])
	check(not _ids(run).has("food"), "a woodcutter is no answer to hunger")
	run.dispose()


func test_a_failing_hearth_points_at_defences() -> void:
	var run := _building()
	run.world.hearth_hp = run.hearth_max_hp() * 0.2
	run.hand.blueprints.append("watch_post")
	var hearth: Array = Advisor.concerns(run).filter(func(c: Dictionary) -> bool: return c["id"] == "hearth")
	check_eq(hearth.size(), 1, "a battered hearth is raised")
	check(run.content.buildings[hearth[0]["fix"]["type"]].has("attack"), "pointing at something that shoots")
	_dawn(run, [{"role": "tribesperson"}, {"role": "warrior"}])
	hearth = Advisor.concerns(run).filter(func(c: Dictionary) -> bool: return c["id"] == "hearth")
	check_eq(hearth[0]["fix"]["index"], 1, "at dawn, the warrior")
	run.dispose()


func test_not_now_quiets_it_for_the_round_then_for_the_run() -> void:
	var run := _building()
	run.stock["food"] = 0
	var settings := GameSettings.new()
	settings.persist = false
	var adv := Advisor.new()
	adv.settings = settings
	adv.run = run
	adv.check(false)
	check_eq(adv.speaking_id(), "food", "the Elder speaks up about food")
	adv.check(true)
	check_eq(adv.speaking_id(), "", "and hides while blocked (a highlight, a menu)")
	adv.check(false)
	adv._wave_off()
	adv.check(false)
	check_eq(adv.speaking_id(), "", "Not now quiets it this round")
	run.round_number += 1
	adv.check(false)
	check_eq(adv.speaking_id(), "food", "it comes back next round")
	adv._wave_off()
	run.round_number += 1
	adv.check(false)
	check_eq(adv.speaking_id(), "", "waved off twice, it is never raised again this run")
	settings.advisor = "off"
	adv.reset()
	adv.check(false)
	check_eq(adv.speaking_id(), "", "the Off setting keeps it silent")
	adv.free()
	run.dispose()


func test_alerts_keep_quiet_about_what_the_elder_says() -> void:
	var run := _building()
	run.stock["food"] = 0
	var alerts := Alerts.new()
	alerts.run = run
	alerts.quiet = "food"
	alerts.refresh()
	check(not alerts._labels.has("food"), "no alert for what the Elder is saying")
	alerts.quiet = ""
	alerts.refresh()
	check(not alerts._labels.has("food"), "nor after a Not now")
	alerts.free()
	run.dispose()
