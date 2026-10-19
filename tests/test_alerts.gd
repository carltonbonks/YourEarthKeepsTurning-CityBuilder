extends TestCase
## Alerts: which problems the screen flags, and that they clear when the problem does.


func _ids(run: RunState) -> Array:
	return Alerts.active(run).map(func(a: Dictionary) -> String: return a["id"])


func test_running_out_of_fuel_and_food_is_flagged() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.stock["fuel"] = 999
	run.stock["food"] = 999
	check(not _ids(run).has("fuel") and not _ids(run).has("food"), "a stocked town has no fuel or food alert")
	run.stock["fuel"] = 0
	run.stock["food"] = 0
	check(_ids(run).has("fuel"), "no fuel for tonight is flagged")
	check(_ids(run).has("food"), "no food for the next dawn is flagged")
	run.dispose()


func test_buildings_waiting_without_a_craftsperson_are_flagged() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	for u in run.world.folk.filter(func(f: Unit) -> bool: return f.type_id == "craftsperson"):
		run.world.folk.erase(u)
	check(not _ids(run).has("builders"), "nothing ordered, nothing to flag")
	check(run.build("hut"), "can order a hut")
	check(_ids(run).has("builders"), "a building nobody can raise is flagged")
	run.dispose()


func test_an_unhappy_hero_is_flagged() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var hero := run.people.make_hero()
	run.people.add_hero(hero)
	hero.mood = run.content.num("mood_grumble_at")
	check(_ids(run).has("mood:" + hero.display_name), "a grumbling hero is flagged by name")
	hero.mood = 100.0
	check(not _ids(run).has("mood:" + hero.display_name), "the alert clears once they cheer up")
	run.dispose()
