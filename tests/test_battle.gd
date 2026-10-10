extends TestCase


func _run_with_one_hero(trait_id: String) -> RunState:
	var run := RunState.new(Content.load_default(), 5)
	run.heroes.resize(1)
	run.heroes[0].trait_id = trait_id
	run.heroes[0].type_id = "warrior"
	return run


func test_greedy_hero_chases_bounty_over_closer_enemy() -> void:
	var run := _run_with_one_hero("greedy")
	run.next_wave = ["goblin", "wolf"] as Array[String]
	run.set_bounty("wolf", 20)
	var battle := run.start_battle()
	var hero := battle.heroes[0]
	var goblin := battle.enemies[0]
	var wolf := battle.enemies[1]
	for e in battle.enemies:
		e.spawned = true
	goblin.pos = hero.pos + Vector2(100, 0)
	wolf.pos = hero.pos + Vector2(300, 0)
	battle.step()
	check(hero.target == wolf, "greedy hero should go for the bountied wolf")


func test_dutiful_hero_ignores_far_bounty_to_defend_keep() -> void:
	var run := _run_with_one_hero("dutiful")
	run.next_wave = ["goblin", "wolf"] as Array[String]
	run.set_bounty("wolf", 20)
	var battle := run.start_battle()
	var hero := battle.heroes[0]
	for e in battle.enemies:
		e.spawned = true
	battle.enemies[0].pos = battle.keep_pos + Vector2(60, 60)
	battle.enemies[1].pos = Vector2(900, 100)
	battle.step()
	check(hero.target == battle.enemies[0], "dutiful hero should defend the keep")


func test_hurt_hero_retreats() -> void:
	var run := _run_with_one_hero("cautious")
	run.next_wave = ["goblin"] as Array[String]
	var battle := run.start_battle()
	var hero := battle.heroes[0]
	hero.hp = hero.max_hp * 0.2
	battle.step()
	check(hero.retreating, "cautious hero at 20% HP should retreat")


func test_battle_always_ends() -> void:
	var run := RunState.new(Content.load_default(), 9)
	var battle := run.start_battle()
	battle.run_to_end()
	check(battle.over, "battle should end")
