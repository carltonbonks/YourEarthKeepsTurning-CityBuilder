extends TestCase
## The medieval age: the Stone keep, iron and steel, families, townhouses and fields, the guildhall and
## knights, the chapel, mail, battering rams, hollow knights and the 14-round run.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


## Orders a building and finishes it on the spot.
func _raise(run: RunState, type: String) -> int:
	run.stock["wood"] = 199
	run.stock["stone"] = 199
	run.stock["shells"] = maxi(int(run.stock["shells"]), 199)
	run.stock["bronze"] = maxi(int(run.stock["bronze"]), 20)
	check(run.build(type), "can order a %s" % type)
	var i := run.world.buildings.size() - 1
	run.world.buildings[i]["work_left"] = 0.0
	run.on_building_done(type)
	run.world.town.on_built(i)
	return i


func _crowd(run: RunState, n: int) -> void:
	run.stock["wood"] = 199
	for i in 8:
		run.build("hut")
	for b in run.world.buildings:
		b["work_left"] = 0.0
	while run.population() < n:
		run.world.folk_ai.add_folk("tribesperson")


## Takes the town to the bronze age, then raises the Stone keep.
func _medieval(run: RunState) -> void:
	_crowd(run, 16)
	_raise(run, "market")
	_raise(run, "bronze_moot")
	_raise(run, "bronzesmith")
	_raise(run, "stone_keep")


func _start_day(run: RunState) -> void:
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	run.world.dens.clear()


func _advance(run: RunState, seconds: float) -> void:
	for i in int(seconds / run.world.dt):
		run.step()


func test_the_keep_needs_bronze_people_and_a_bronzesmith() -> void:
	var run := _run()
	check(not run.can_build("stone_keep"), "no keep in the stone age")
	_crowd(run, 16)
	_raise(run, "market")
	_raise(run, "bronze_moot")
	run.stock["bronze"] = 20
	check(not run.can_build("stone_keep"), "the keep needs a bronzesmith first")
	_raise(run, "bronzesmith")
	check(run.can_build("stone_keep"), "with a bronzesmith and 16 people the keep can be ordered")
	check(not run.can_build("blacksmith"), "no blacksmith before the keep")
	var hearth_before := run.hearth_max_hp()
	_raise(run, "stone_keep")
	check_eq(run.age, "medieval", "raising the keep brings the medieval age")
	check_eq(run.hearth_max_hp(), hearth_before + 60.0, "the keep strengthens the hearth")
	check(run.can_build("blacksmith"), "the blacksmith can be ordered in the medieval age")
	check_eq(int(run.to_record()["age_rounds"]["medieval"]), 1, "the round the keep rose is recorded")
	check(run.story.back().contains("bog iron"), "the story says what the age brings")


func test_keep_shoots_and_counts_toward_town_power() -> void:
	var run := _run()
	var before := float(Power.town(run.world)["defences"])
	_medieval(run)
	check(float(Power.town(run.world)["defences"]) > before, "the keep's crossbows and walls add to the defences")


func test_fifth_ring_and_more_watch_posts_open_with_the_keep() -> void:
	var run := _run()
	var outer := run.world.town.plots.filter(func(p: Dictionary) -> bool: return p["age"] == "medieval")
	check(not outer.is_empty(), "the map has a medieval ring")
	check(not run.world.town.ring_open(outer[0]), "it is closed before the keep")
	check_eq(run.building_max("watch_post"), 4, "4 watch posts before the medieval age")
	_medieval(run)
	check(run.world.town.ring_open(outer[0]), "the keep opens the fifth ring")
	check_eq(run.building_max("watch_post"), 6, "6 watch posts in the medieval age")


func test_bog_iron_only_counts_in_the_medieval_age() -> void:
	var run := _run()
	var bogs := run.world.nodes.filter(func(n: Dictionary) -> bool: return n["gives"] == "bog_iron")
	check(not bogs.is_empty(), "bog-iron pools are on the map")
	check(not run.world.node_active(bogs[0]), "dormant before the keep")
	_medieval(run)
	check(run.world.node_active(bogs[0]), "open once the keep stands")


func test_charcoal_iron_and_steel_chain() -> void:
	var run := _run()
	_medieval(run)
	var burner := _raise(run, "charcoal_burner")
	var bloomery := _raise(run, "bloomery")
	var smith := _raise(run, "blacksmith")
	run.stock["wood"] = 60
	run.stock["bog_iron"] = 8
	run.stock["charcoal"] = 4
	run.stock["iron"] = 1
	run.stock["fuel"] = 99
	run.stock["food"] = 99
	for i in 3:
		run.world.folk_ai.add_folk("craftsperson")
	_start_day(run)
	_advance(run, 28.0)
	check(int(run.world.buildings[burner]["made"]) > 0, "the burner turned wood into charcoal")
	check(int(run.world.buildings[bloomery]["made"]) > 0, "the bloomery made iron")
	check(int(run.world.buildings[smith]["made"]) > 0, "the blacksmith worked the iron")


func test_iron_tools_and_steel_warriors() -> void:
	var run := _run()
	_medieval(run)
	check(not run.can_buy_tools("mail_and_halberds"), "no iron, no mail")
	run.stock["iron"] = 10
	run.stock["steel"] = 10
	var warrior: Unit = run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior")[0]
	var attack := warrior.attack
	check(run.buy_tools("mail_and_halberds"), "mail and halberds bought")
	check(warrior.attack > attack, "warriors hit harder")
	check(run.has_tools_with("warrior", "steel"), "warriors strike with steel")


func test_mail_turns_all_but_steel() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	var man := run.world.enemy_ai.make_enemy("man_at_arms", Vector2(100, 0), 0.0)
	run.world.enemies.append(man)
	var hero := run.heroes[0]
	hero.energy = 100.0
	var hits := {}
	for base: String in ["flint_blade", "bronze_sword", "steel_longsword"]:
		hero.items = {"weapon": Loot.make(base, 4)}
		run.world.hero_ai.apply_hero_stats(hero)
		man.hp = 1000.0
		run.world.hit(hero, man)
		hits[base] = (1000.0 - man.hp) / hero.attack
	check(float(hits["flint_blade"]) < 0.6, "mail soaks half a stone blow")
	check(float(hits["bronze_sword"]) < 0.6, "and half a bronze one")
	check(float(hits["steel_longsword"]) > 0.84, "steel cuts through")


func test_reliquary_bites_the_undead() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	var hero := run.heroes[0]
	hero.energy = 100.0
	hero.items = {"charm": Loot.make("reliquary", 3)}
	run.world.hero_ai.apply_hero_stats(hero)
	var wight := run.world.enemy_ai.make_enemy("barrow_wight", Vector2(100, 0), 0.0)
	var raider := run.world.enemy_ai.make_enemy("raider", Vector2(100, 0), 0.0)
	wight.hp = 1000.0
	raider.hp = 1000.0
	run.world.hit(hero, wight)
	run.world.hit(hero, raider)
	check(1000.0 - wight.hp > hero.attack * 1.15, "the undead take extra damage")
	check(1000.0 - raider.hp <= hero.attack * 1.15 + 0.01, "the living don't")


func test_chapel_pays_for_the_undead() -> void:
	var run := _run()
	_medieval(run)
	_raise(run, "chapel")
	run.world.market.refresh_prizes()
	check_eq(run.world.market.prize_for("hollow_knight"), 4, "the chapel posts a prize on the undead")
	check_eq(run.world.market.prize_for("raider"), 0, "and none on the living")


func test_families_arrive_together_in_the_medieval_age() -> void:
	var run := _run()
	for r in 12:
		run.round_number = r + 1
		run.people.offer_picks()
		check(not run.pick_offer.any(func(c: Dictionary) -> bool: return c["kind"] == "family"), "no families before the keep")
	run = _run()
	_medieval(run)
	_raise(run, "townhouse")
	_raise(run, "townhouse")
	var seen := false
	for attempt in 40:
		run.pick_offer = []
		run.people.offer_picks()
		var i := run.pick_offer.find_custom(func(c: Dictionary) -> bool: return c["kind"] == "family")
		if i >= 0:
			seen = true
			var before := run.world.folk.size()
			check(run.can_take_pick(i), "a family can be taken when the houses have room")
			run.choose_pick(i)
			check_eq(run.world.folk.size(), before + run.content.balance["family_roles"].size(), "the whole family joins")
			break
		run.phase = RunState.Phase.BUILD
		run.round_number += 1
	check(seen, "family cards turn up in the medieval age")


func test_family_needs_room_for_everyone() -> void:
	var run := _run()
	_medieval(run)
	while run.population() < run.housing() - 1:
		run.world.folk_ai.add_folk("tribesperson")
	run.phase = RunState.Phase.PICK
	run.pick_offer = [{"kind": "family", "role": "family", "cost": 0, "roles": ["tribesperson", "tribesperson", "craftsperson"]}]
	check(not run.can_take_pick(0), "a family of 3 doesn't fit in 1 free bed")


func test_fields_need_hands_and_ploughs_double_them() -> void:
	var run := _run()
	_medieval(run)
	var gardens := run.food_grown_daily()
	_raise(run, "field")
	while run.count_role("tribesperson") > 0:
		run.world.folk.erase(run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "tribesperson")[0])
	check_eq(run.food_grown_daily(), gardens, "an unworked field grows nothing")
	run.world.folk_ai.add_folk("tribesperson")
	run.world.folk_ai.add_folk("tribesperson")
	check_eq(run.food_grown_daily(), gardens + 4, "two tribespeople work a field for 4 food")
	run.stock["iron"] = 10
	check(run.buy_tools("iron_ploughs"), "iron ploughs bought")
	check_eq(run.food_grown_daily(), gardens + 8, "iron ploughs double the field")


func test_knights_need_the_guildhall() -> void:
	var run := _run()
	for i in 30:
		check(run.people.make_hero().type_id != "knight", "no knights without a guildhall")
	_medieval(run)
	_raise(run, "guildhall")
	var knights := 0
	for i in 40:
		var h := run.people.make_hero()
		if h.type_id == "knight":
			knights += 1
	check(knights > 0, "knights answer once the guildhall stands")
	check_eq(run.people.hero_card_cost("knight"), 45, "a knight's card costs more")


func test_champion_can_be_knighted() -> void:
	var run := _run()
	_medieval(run)
	_raise(run, "guildhall")
	var hero := run.people.make_hero()
	hero.type_id = "champion"
	hero.level = 5
	run.people.add_hero(hero)
	run.stock["shells"] = 200
	run.begin_round()
	var card := -1
	for i in run.pick_offer.size():
		if run.pick_offer[i]["kind"] == "promote" and run.pick_offer[i]["role"] == "champion":
			card = i
	check(card >= 0, "a level-5 champion is offered for knighting")
	if card < 0:
		return
	run.choose_pick(card)
	check_eq(hero.type_id, "knight", "the champion is now a knight")
	check(run.heroes.has(hero), "still the same hero")


func test_proud_knights_hate_sleeping_rough() -> void:
	var run := _run()
	var knight := run.people.make_hero()
	knight.type_id = "knight"
	var plain := run.people.make_hero()
	plain.type_id = "hunter"
	plain.trait_id = knight.trait_id
	run.heroes.append(knight)
	run.heroes.append(plain)
	knight.mood = 80.0
	plain.mood = 80.0
	knight.slept = "rough"
	plain.slept = "rough"
	run.people.update_moods()
	check(80.0 - knight.mood > 80.0 - plain.mood, "a knight takes sleeping rough harder")


func test_battering_rams_ignore_people() -> void:
	var run := _run()
	run.begin_round()
	run.choose_pick(-1)
	run.world.enemies.clear()
	var ram := run.world.enemy_ai.make_enemy("battering_ram", Vector2(60, 0), 0.0)
	run.world.enemies.append(ram)
	run.world.enemy_ai.enemy_tick(ram)
	check(ram.target == null, "the ram picks no fight with people")


func test_medieval_threats_come_by_round_not_by_age() -> void:
	var run := _run()
	check(not run.waves.generate(9).has("man_at_arms"), "no men-at-arms before round 10")
	var seen := {}
	for r in range(10, 15):
		for id in run.waves.generate(r):
			seen[id] = true
	for id in ["man_at_arms", "battering_ram", "hollow_knight"]:
		check(seen.has(id), "%s turn up in a stone-age town's late waves too" % id)
	check(run.waves.generate(14).has("black_margrave"), "the Black Margrave leads the last wave")
	check(not run.waves.generate(13).has("black_margrave"), "and only the last")
	var barrow := {"type": "barrow", "spawns": "barrow_wight"}
	check_eq(run.world.enemy_ai.den_spawns(barrow), "barrow_wight", "barrows send wights early on")
	run.round_number = 10
	check_eq(run.world.enemy_ai.den_spawns(barrow), "hollow_knight", "and hollow knights from round 10")


func test_medieval_bot_records_format_13_fields() -> void:
	var record := bot_record(1003, "medieval")
	check(int(record["format"]) >= 13, "record format 13 or later")
	check(record.has("age_rounds"), "record has age_rounds")
	check(record["stock"].has("steel"), "stock lists steel")
	for rd: Dictionary in record["rounds"]:
		check(rd.has("siege_damage"), "round %d has siege_damage" % rd["round"])
