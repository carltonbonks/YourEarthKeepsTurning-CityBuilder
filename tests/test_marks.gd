extends TestCase
## Escorts and marks: a gatherer a warrior keeps watch over walks faster while no foe is near, and warriors who drill
## beside a hero on quiet days earn a lasting mark the hero's class teaches (data/marks.json).


## A run on its first morning with no monsters, no townsfolk and one grove out past the houses.
func _setup() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.begin_round()
	run.choose_pick(-1)
	var w := run.world
	w.enemies.clear()
	w.nodes.clear()
	w.folk.clear()
	w.dens.clear()
	w._add_node("grove", Vector2(200, 0))
	return run


func _folk(run: RunState, role: String) -> Unit:
	var u := run.world.folk_ai.add_folk(role)
	u.pos = Vector2.ZERO
	u.task = ""
	return u


## A warrior shadowing a gatherer at the grove, standing beside it.
func _escort(run: RunState) -> Array[Unit]:
	var warrior := _folk(run, "warrior")
	_folk(run, "warrior")  # the other half patrols
	var gatherer := _folk(run, "tribesperson")
	gatherer.task = "gather"
	gatherer.task_index = 0
	gatherer.pos = Vector2(200, 0)
	warrior.pos = Vector2(180, 0)
	return [warrior, gatherer]


func _hero(run: RunState, class_id: String, trait_id: String) -> Unit:
	var hero := run.people.make_hero()
	hero.type_id = class_id
	hero.trait_id = trait_id
	run.world.hero_ai.apply_hero_stats(hero)
	run.people.add_hero(hero)
	hero.energy = 100.0
	hero.gold = 0
	return hero


## Steps the warrior and the hero together for this many seconds (begin_step first, as World.step does).
func _drill(run: RunState, warrior: Unit, hero: Unit, seconds: float) -> void:
	var w := run.world
	for i in roundi(seconds / w.dt):
		w.time += w.dt
		w.folk_ai.begin_step()
		w.folk_ai.folk_tick(warrior)
		w.hero_ai.hero_tick(hero)


func test_an_escorted_gatherer_walks_faster_while_no_foe_is_near() -> void:
	var run := _setup()
	var w := run.world
	var pair := _escort(run)
	var gatherer := pair[1]
	w.folk_ai.begin_step()
	check(gatherer.escorted, "the gatherer with a warrior beside it is escorted")
	var start := gatherer.pos
	w.walk_toward(gatherer, Vector2(200, 300))
	var escorted_step := gatherer.pos.distance_to(start)
	gatherer.escorted = false
	start = gatherer.pos
	w.walk_toward(gatherer, Vector2(200, 300))
	var plain_step := gatherer.pos.distance_to(start)
	check(escorted_step > plain_step * 1.1, "it walks about 12%% faster (%.2f vs %.2f)" % [escorted_step, plain_step])

	var wolf := w.enemy_ai.make_enemy("wolf", gatherer.pos + Vector2(100, 0), 0.0)
	wolf.spawned = true
	w.enemies.append(wolf)
	w.folk_ai.begin_step()
	check(not gatherer.escorted, "not with a wolf about")
	w.enemies.clear()
	pair[0].pos = Vector2(-100, 0)
	w.folk_ai.begin_step()
	check(not gatherer.escorted, "not when its warrior is far off")
	pair[0].pos = Vector2(180, 0)
	w.time = w.content.num("day_seconds") - 1.0
	w.folk_ai.begin_step()
	check(not gatherer.escorted, "not at dusk")


func test_warriors_drilling_beside_a_hero_earn_its_mark() -> void:
	var run := _setup()
	var w := run.world
	w.nodes.clear()  # nobody out gathering: every warrior is free to drill
	var warrior := _folk(run, "warrior")
	var speed := warrior.speed
	var hero := _hero(run, "stalker", "cautious")
	hero.pos = Vector2(40, 0)
	_drill(run, warrior, hero, 3.0)
	check_eq(warrior.drill_with, hero, "a drilling stalker takes the idle warrior as a partner")
	check(warrior.intent.begins_with("drilling with"), "who goes to drill beside it")
	_drill(run, warrior, hero, w.content.townsfolk["warrior"]["mark_seconds"] + 6.0)
	check_eq(warrior.mark, "swift", "after a day's drilling a stalker's partner is swift")
	check(is_equal_approx(warrior.speed, speed * 1.1), "and walks 10% faster for good")
	check(warrior.drill_with == null, "the drilling is done")
	check(w.content.unit_has_tag(warrior, "swift"), "the mark is a tag on the warrior")
	check_eq(int(run.record.entry["marks_earned"]["swift"]), 1, "the record counts the mark")
	check(Tooltips.folk(run, warrior)["lines"].any(func(l: String) -> bool: return l.begins_with("Swift")),
		"the hover card names it")
	w.folk_ai.apply_folk_stats(warrior)
	check(is_equal_approx(warrior.speed, speed * 1.1), "and it survives stats being worked out again")


func test_hardy_warriors_gain_health_and_dutiful_heroes_teach_faster() -> void:
	var run := _setup()
	var w := run.world
	w.nodes.clear()
	var warrior := _folk(run, "warrior")
	var hp := warrior.max_hp
	var hero := _hero(run, "champion", "dutiful")
	hero.pos = Vector2(40, 0)
	var need: float = w.content.townsfolk["warrior"]["mark_seconds"]
	_drill(run, warrior, hero, need * 0.5 + 8.0)
	check_eq(warrior.mark, "hardy", "a dutiful champion teaches hardiness in half the time")
	check(is_equal_approx(warrior.max_hp, hp * 1.15), "15% more health")
	check(is_equal_approx(warrior.hp, warrior.max_hp), "and the new health comes at once")


func test_shadowing_warriors_and_marked_ones_dont_drill() -> void:
	var run := _setup()
	var w := run.world
	var pair := _escort(run)
	var patroller := w.folk[1]
	patroller.mark = "sharp"
	var hero := _hero(run, "hunter", "cautious")
	hero.pos = Vector2(40, 0)
	_drill(run, pair[0], hero, 3.0)
	check(pair[0].drill_with == null, "a warrior shadowing a gatherer keeps watch instead")
	check(patroller.drill_with == null, "one already marked doesn't drill again")
