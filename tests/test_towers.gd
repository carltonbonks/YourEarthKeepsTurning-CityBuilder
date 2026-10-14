extends TestCase
## Towers can be broken: a sentient raider shot by a watch post (or the keep) turns on it; a broken
## tower stops shooting until every tower is mended at dawn.


func _run_with_post() -> Array:
	var run := RunState.new(Content.load_default(), 4821)
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	check(run.build("watch_post"), "can order a watch post")
	var i := run.world.buildings.size() - 1
	run.world.buildings[i]["work_left"] = 0.0
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	run.world.folk.clear()
	return [run, i]


## Lets the post fire once at an enemy standing in its range.
func _shoot(run: RunState, post: int, enemy: Unit) -> void:
	run.world.buildings[post]["cooldown_left"] = 0.0
	enemy.pos = Vector2(run.world.buildings[post]["pos"]) + Vector2(60, 0)
	run.world.enemy_ai.towers_tick()


func test_sentient_raiders_turn_on_the_tower_that_shot_them() -> void:
	var setup := _run_with_post()
	var run: RunState = setup[0]
	var post: int = setup[1]
	var raider := run.world.enemy_ai.make_enemy("raider", Vector2.ZERO, 0.0)
	raider.hp = 999.0
	run.world.enemies.append(raider)
	_shoot(run, post, raider)
	check_eq(raider.target_tower, post, "the raider goes for the watch post")
	var start := float(run.world.buildings[post]["hp"])
	for k in 400:
		run.world.enemy_ai.enemy_tick(raider)
		run.world.time += run.world.dt
		raider.grudge_until = run.world.time + 5.0
		if float(run.world.buildings[post]["hp"]) <= 0.0:
			break
	check(float(run.world.buildings[post]["hp"]) < start, "it hits the tower")
	check_eq(float(run.world.buildings[post]["hp"]), 0.0, "and breaks it in the end")
	check(not run.world.enemy_ai.tower_standing(post), "a broken tower doesn't count as standing")
	var other := run.world.enemy_ai.make_enemy("raider", Vector2.ZERO, 0.0)
	run.world.enemies.append(other)
	var before := other.hp
	_shoot(run, post, other)
	check_eq(other.hp, before, "a broken tower doesn't shoot")
	run.world.enemy_ai.mend_towers()
	check_eq(float(run.world.buildings[post]["hp"]), float(run.content.buildings["watch_post"]["tower_hp"]), "mended to full at dawn")


func test_mindless_raiders_ignore_towers() -> void:
	var setup := _run_with_post()
	var run: RunState = setup[0]
	var post: int = setup[1]
	var knight := run.world.enemy_ai.make_enemy("hollow_knight", Vector2.ZERO, 0.0)
	knight.hp = 999.0
	run.world.enemies.append(knight)
	_shoot(run, post, knight)
	check_eq(knight.target_tower, -1, "a hollow knight (not sentient) keeps on toward the hearth")
	var ram := run.world.enemy_ai.make_enemy("battering_ram", Vector2.ZERO, 0.0)
	ram.hp = 999.0
	run.world.enemies.append(ram)
	_shoot(run, post, ram)
	check_eq(ram.target_tower, -1, "battering rams only want gates and the hearth")


func test_a_blow_from_a_person_takes_back_the_grudge() -> void:
	var setup := _run_with_post()
	var run: RunState = setup[0]
	var post: int = setup[1]
	var raider := run.world.enemy_ai.make_enemy("raider", Vector2.ZERO, 0.0)
	raider.hp = 999.0
	run.world.enemies.append(raider)
	_shoot(run, post, raider)
	var warrior := run.world.folk_ai.add_folk("warrior")
	run.world.damage(warrior, raider, 1.0)
	check_eq(raider.target_tower, -1, "the raider leaves the tower")
	check(raider.target == warrior, "and turns on the warrior who hit it")
