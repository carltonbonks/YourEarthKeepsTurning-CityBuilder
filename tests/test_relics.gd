extends TestCase
## Relics that change rules rather than numbers (data/relics.json): pacts, picks, the horde, heroes,
## enemies, the earth and the economy. Each test gives the run one relic and checks its rule fires.


func _run(seed_value := 4821) -> RunState:
	return RunState.new(Content.load_default(), seed_value)


func _give(run: RunState, id: String) -> void:
	run._gain_relic(id)


func _enemy(run: RunState, type: String, at := Vector2(500, 0)) -> Unit:
	var e := run.world.enemy_ai.make_enemy(type, at, 0.0)
	run.world.enemies.append(e)
	return e


## Plays the run to the next decision, skipping dawn cards.
func _to_relic(run: RunState) -> void:
	run.begin_round()
	while run.phase != RunState.Phase.RELIC and not run.is_over():
		if run.phase == RunState.Phase.PICK:
			run.choose_pick(-1)
		run.run_until_pause()


func _night(w: World) -> void:
	w.time = w.day_length() - w.content.num("night_seconds") * 0.5


func _wave_night(w: World) -> void:
	w.time = (w.content.int_num("days_per_round") - 1) * w.day_length() + w.day_length() - w.content.num("night_seconds") * 0.5


# --- Data ---------------------------------------------------------------------

func test_every_effect_key_is_read_by_a_rule() -> void:
	var c := Content.load_default()
	var code := ""
	for file in DirAccess.get_files_at("res://sim"):
		if file.ends_with(".gd"):
			code += FileAccess.get_file_as_string("res://sim".path_join(file))
	for id: String in c.relics:
		var r: Dictionary = c.relics[id]
		check(r.has("name") and r.has("text") and r.has("effects"), "%s has a name, text and effects" % id)
		for key: String in r["effects"]:
			check(code.contains("\"%s\"" % key), "%s's effect %s is read somewhere in sim/" % [id, key])


func test_there_are_enough_pacts_for_every_pact_round() -> void:
	var c := Content.load_default()
	var pacts := c.relics.keys().filter(func(id: String) -> bool: return c.has_tag("relic", id, "pact"))
	check(pacts.size() >= c.balance["pact_rounds"].size() * c.int_num("relic_choices") - 2, "enough pacts to fill the pact rounds")


# --- Pacts and offers ----------------------------------------------------------

func test_pact_rounds_offer_pacts_and_other_rounds_never_do() -> void:
	var run := _run()
	var c := run.content
	for r in range(1, 14):
		run.round_number = r
		var offer := run._roll_relic_offer().filter(func(id: String) -> bool: return not c.has_tag("relic", id, "spoils"))
		var pacts := offer.filter(func(id: String) -> bool: return c.has_tag("relic", id, "pact")).size()
		if run.is_pact_round():
			check_eq(pacts, offer.size(), "round %d offers only pacts" % r)
		else:
			check_eq(pacts, 0, "round %d offers no pacts" % r)
		for id in offer:
			check(int(c.relics[id].get("from_round", 0)) <= r, "%s is not offered before its round" % id)
	run.dispose()


func test_broken_crown_gives_two_relics_and_shrinks_offers() -> void:
	var run := _run()
	_to_relic(run)
	run.relic_offer = ["broken_crown"]
	run.choose_relic("broken_crown")
	check_eq(run.relics.size(), 3, "the crown and two gifts")
	check(run.relics.slice(1).all(func(id: String) -> bool: return not run.content.has_tag("relic", id, "pact")), "gifts are not pacts")
	run.round_number = 2
	var relics := run._roll_relic_offer().filter(func(id: String) -> bool: return not run.content.has_tag("relic", id, "spoils"))
	check_eq(relics.size(), run.content.int_num("relic_choices") - 1, "one card fewer")
	run.dispose()


func test_chieftains_torc_more_blueprint_offers_fewer_dawn_cards() -> void:
	var run := _run()
	var hand := run.hand.size()
	_give(run, "chieftains_torc")
	check(not run.hand.can_redraw(), "no reroll")
	check_eq(run.hand.size(), hand + 1, "one more blueprint offer")
	run.begin_round()
	run.run_until_pause()
	check_eq(run.phase, RunState.Phase.PICK, "a dawn pick")
	check(run.pick_offer.size() < run.content.int_num("pick_choices"), "fewer dawn cards than usual")
	run.dispose()


func test_twin_fires_two_picks_and_double_fuel() -> void:
	var run := _run()
	var fuel := run.fuel_needed_tonight()
	_give(run, "twin_fires")
	check(run.fuel_needed_tonight() >= fuel * 2 - 1, "twice the fuel")
	run.begin_round()
	run.run_until_pause()
	var before := run.world.folk.size() + run.heroes.size()
	var folk_card := run.pick_offer.find(run.pick_offer.filter(func(c: Dictionary) -> bool: return c["kind"] == "folk")[0])
	run.choose_pick(folk_card)
	check_eq(run.phase, RunState.Phase.PICK, "a second pick at the same dawn")
	var second := run.pick_offer.find(run.pick_offer.filter(func(c: Dictionary) -> bool: return c["kind"] == "folk")[0])
	run.choose_pick(second)
	check_eq(run.phase, RunState.Phase.SIM, "then the day goes on")
	check_eq(run.world.folk.size() + run.heroes.size(), before + 2, "two newcomers")
	run.dispose()


func test_tithe_bowl_stops_income_and_taxes_hero_kills() -> void:
	var run := _run()
	_give(run, "tithe_bowl")
	check_eq(run.income(), 0, "traders leave nothing")
	var shells := int(run.stock["shells"])
	var hero := run.heroes[0]
	hero.gold = 0
	for i in 5:
		run.world.damage(hero, _enemy(run, "cave_bear"), 9999.0)
	check(int(run.stock["shells"]) > shells, "the town takes a share")
	check(hero.gold > 0, "the hero keeps the rest")
	run.dispose()


func test_black_banner_no_catch_up_and_kill_shells() -> void:
	var run := _run()
	_give(run, "black_banner")
	for hero in run.heroes:
		hero.alive = false
	for u in run.world.folk:
		u.alive = false
	run.round_number = 8
	run.waves.plan(8)
	check_eq(run.wave_eased, 0, "the wave never holds back")
	var shells := int(run.stock["shells"])
	run.world.damage(null, _enemy(run, "raider"), 9999.0)
	check_eq(int(run.stock["shells"]), shells + 2, "a kill pays the town")
	run.dispose()


func test_hollow_drum_no_probes_bigger_wave() -> void:
	var run := _run()
	var plain := run.waves.generate(6).size()
	_give(run, "hollow_drum")
	check(run.waves.generate(6).size() > plain, "a larger wave")
	var count := run.world.enemies.size()
	run.round_number = 6
	run.world.enemy_ai.spawn_probe()
	check_eq(run.world.enemies.size(), count, "no probe")
	run.dispose()


func test_lodestone_wheel_turns_the_near_ring_two_plates() -> void:
	var run := _run()
	var earth := run.world.earth
	var seam := float(earth.rings[0]["seams"][0])
	_give(run, "lodestone_wheel")
	_to_relic(run)
	run.choose_relic("")
	check_eq(earth.shifts, 1, "one shift after the first round")
	check(is_equal_approx(absf(angle_difference(seam, float(earth.rings[0]["seams"][0]))), absf(float(earth.rings[0]["step"])) * 2.0), "two plates round")
	run.dispose()


# --- Townsfolk and the horde ----------------------------------------------------

func test_horde_drum_grows_with_fighters() -> void:
	var run := _run()
	var w := run.world
	_give(run, "horde_drum")
	for i in 6:
		w.folk_ai.add_folk("warrior")
	w.folk_ai.begin_step()
	var warrior: Unit = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior")[0]
	var fighters := w.folk_ai.fighters
	check_eq(w.folk_ai.relic_damage(warrior, 6.0), 6.0 + (fighters - 1) / 3, "+1 per 3 other warriors")
	var worker: Unit = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "tribesperson")[0]
	check_eq(w.folk_ai.relic_damage(worker, 2.0), 2.0, "workers are not part of the horde")
	run.dispose()


func test_turncoat_joins_as_a_warrior() -> void:
	var run := _run()
	var w := run.world
	_give(run, "turncoats_torc")
	run.content.relics["turncoats_torc"]["effects"]["turncoat_chance"] = 1.0
	var warriors := w.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").size()
	w.damage(null, _enemy(run, "raider"), 9999.0)
	w.damage(null, _enemy(run, "wolf"), 9999.0)
	w._join_folk()
	check_eq(w.folk.filter(func(u: Unit) -> bool: return u.type_id == "warrior").size(), warriors + 1, "the human turns, the wolf doesn't")
	w.damage(null, _enemy(run, "raider"), 9999.0)
	w.damage(null, _enemy(run, "raider"), 9999.0)
	w._join_folk()
	check_eq(w.turncoats_tonight, 2, "at most two a night")
	run.dispose()


func test_bone_flute_raises_the_fallen_until_dawn() -> void:
	var run := _run()
	var w := run.world
	_give(run, "bone_flute")
	var folk := w.folk.size()
	w.damage(null, _enemy(run, "raider"), 9999.0)
	w._join_folk()
	check_eq(w.folk.size(), folk, "nobody rises by day")
	_night(w)
	for i in 4:
		w.damage(null, _enemy(run, "raider"), 9999.0)
	w._join_folk()
	check_eq(w.folk.size(), folk + 3, "three rise at night")
	var risen: Unit = w.folk[-1]
	check(risen.risen, "marked as risen")
	w.damage(_enemy(run, "raider"), risen, 9999.0)
	w._cleanup()
	check_eq(run.fallen_folk, 0, "a fallen skeleton is no loss")
	w._lay_risen()
	check_eq(w.folk.size(), folk, "the rest crumble at dawn")
	run.dispose()


func test_levy_horn_tribespeople_fight_on_the_wave_night() -> void:
	var run := _run()
	var w := run.world
	_give(run, "levy_horn")
	var worker: Unit = w.folk.filter(func(u: Unit) -> bool: return u.type_id == "tribesperson")[0]
	check(not w.folk_ai.levied(worker), "not levied by day")
	_wave_night(w)
	check(w.is_wave_night(), "the warned night")
	check(w.folk_ai.levied(worker), "levied on the warned night")
	check_eq(w.folk_ai.relic_damage(worker, worker.attack), float(w.content.townsfolk["warrior"]["attack"]), "hits like a warrior")
	run.dispose()


func test_hearth_mothers_doll_every_third_brings_a_twin() -> void:
	var run := _run()
	_give(run, "hearth_mothers_doll")
	run.content.balance["base_housing"] = 50
	var folk := run.world.folk.size()
	for i in 3:
		run.pick_offer = [{"kind": "folk", "role": "tribesperson", "cost": 0}]
		run.picks_left = 1
		run.phase = RunState.Phase.PICK
		run.choose_pick(0)
	check_eq(run.world.folk.size(), folk + 4, "three cards, four people")
	run.dispose()


func test_the_doll_says_which_card_brings_its_twin_and_stacks_with_twins() -> void:
	var run := _run()
	check(not run.doll_twin_next() and run.doll_picks_to_twin() == 0, "nothing without the Doll")
	_give(run, "hearth_mothers_doll")
	run.content.balance["base_housing"] = 50
	check_eq(run.doll_picks_to_twin(), 3, "three cards to go")
	for i in 2:
		check(not run.doll_twin_next(), "card %d brings no twin" % (i + 1))
		run.pick_offer = [{"kind": "folk", "role": "tribesperson", "cost": 0}]
		run.picks_left = 1
		run.phase = RunState.Phase.PICK
		run.choose_pick(0)
	check(run.doll_twin_next() and run.doll_picks_to_twin() == 1, "the third card will")
	var folk := run.world.folk.size()
	run.pick_offer = [{"kind": "folk", "role": "tribesperson", "cost": 0, "roll": "yellow", "boons": ["twins"]}]
	run.picks_left = 1
	run.phase = RunState.Phase.PICK
	run.choose_pick(0)
	check_eq(run.world.folk.size(), folk + 3, "a Twins card on the Doll's turn: one, its twin and the Doll's twin")
	check_eq(run.doll_picks_to_twin(), 3, "and the count starts again")
	run.dispose()


func test_carrion_kiln_burns_enemies_inside_the_settlement() -> void:
	var run := _run()
	_give(run, "carrion_kiln")
	var fuel := int(run.stock["fuel"])
	run.world.damage(null, _enemy(run, "raider", Vector2(500, 0)), 9999.0)
	check_eq(int(run.stock["fuel"]), fuel, "nothing from out in the wilds")
	run.world.damage(null, _enemy(run, "raider", Vector2(80, 0)), 9999.0)
	check_eq(int(run.stock["fuel"]), fuel + 1, "fuel from inside")
	run.dispose()


# --- Heroes -----------------------------------------------------------------------

func test_lone_wolf_only_with_few_heroes() -> void:
	var run := _run()
	_give(run, "lone_wolf_pelt")
	var hero := run.heroes[0]
	run.heroes[1].pos = Vector2(400, 400)
	check_eq(run.world.hero_ai.relic_damage_mult(hero), 2.0, "double with two heroes")
	run.people.add_hero(run.people.make_hero())
	check_eq(run.world.hero_ai.relic_damage_mult(hero), 1.0, "normal with three")
	run.dispose()


func test_chosen_brand_favours_the_highest_level() -> void:
	var run := _run()
	_give(run, "chosen_brand")
	run.heroes[0].level = 3
	check_eq(run.world.hero_ai.chosen_xp(run.heroes[0]), 2.0, "the chosen")
	check_eq(run.world.hero_ai.chosen_xp(run.heroes[1]), -0.5, "the rest")
	run.dispose()


func test_mourning_bell_shares_xp_without_grief() -> void:
	var run := _run()
	_give(run, "mourning_bell")
	var fallen := run.heroes[0]
	fallen.level = 2
	fallen.xp = 5.0
	var other := run.heroes[1]
	run.world.damage(_enemy(run, "raider"), fallen, 9999.0)
	check_eq(other.xp, 5.0 + run.content.num("xp_per_level"), "the other hero gets all the fallen's XP")
	var mood := other.mood
	run.people.update_moods()
	check(other.mood >= mood - 5.0 - 0.01, "no grief")
	run.dispose()


func test_trophy_belt_every_ten_kills() -> void:
	var run := _run()
	_give(run, "trophy_belt")
	var hero := run.heroes[0]
	var attack := hero.attack
	for i in 10:
		run.world.damage(hero, _enemy(run, "wolf"), 9999.0)
	check_eq(hero.attack - attack, 1.0, "+1 at ten kills (no level-up mid-round)")
	run.dispose()


func test_witchs_thread_lifts_the_curse() -> void:
	var run := _run()
	var hero := run.heroes[0]
	hero.items["charm"] = Loot.make("amber_amulet", 1, ["cursed"])
	run.world.hero_ai.apply_hero_stats(hero)
	var cursed_hp := hero.max_hp
	_give(run, "witchs_thread")
	check_eq(hero.max_hp, cursed_hp + 10.0, "the HP penalty is gone")
	run.dispose()


func test_blood_brother_needs_a_hero_close_by() -> void:
	var run := _run()
	_give(run, "blood_brother_knot")
	var a := run.heroes[0]
	var b := run.heroes[1]
	a.pos = Vector2(300, 0)
	b.pos = Vector2(-300, 0)
	check_eq(run.world.hero_ai.relic_damage_mult(a), 1.0, "alone")
	b.pos = Vector2(330, 0)
	check(is_equal_approx(run.world.hero_ai.relic_damage_mult(a), 1.3), "side by side")
	run.dispose()


func test_owl_eyes_night_and_day() -> void:
	var run := _run()
	_give(run, "owl_eyes")
	var hero := run.heroes[0]
	check(is_equal_approx(run.world.hero_ai.relic_damage_mult(hero), 0.75), "weaker by day")
	_night(run.world)
	check(is_equal_approx(run.world.hero_ai.relic_damage_mult(hero), 1.5), "stronger at night")
	run.dispose()


# --- Enemies and defence -----------------------------------------------------------

func test_wolf_mothers_skull_beasts_leave_townsfolk_alone() -> void:
	var run := _run()
	var w := run.world
	_give(run, "wolf_mothers_skull")
	for hero in run.heroes:
		hero.pos = Vector2(-700, 0)
	var worker := w.folk[0]
	worker.pos = Vector2(400, 0)
	var wolf := _enemy(run, "wolf", Vector2(420, 0))
	wolf.spawned = true
	w._friend_grid.rebuild(w.folk + run.heroes)
	w._friend_grid_ok = true
	w.enemy_ai.enemy_tick(wolf)
	check(wolf.target == null, "the wolf ignores the worker")
	var raider := _enemy(run, "raider", Vector2(420, 0))
	raider.spawned = true
	w.enemy_ai.enemy_tick(raider)
	check(raider.target == worker, "a raider doesn't")
	w._friend_grid_ok = false
	run.dispose()


func test_grave_salt_doubles_damage_to_undead() -> void:
	var run := _run()
	_give(run, "grave_salt")
	var hero := run.heroes[0]
	hero.items = {}
	run.world.hero_ai.apply_hero_stats(hero)
	var wight := _enemy(run, "barrow_wight")
	wight.max_hp = 10000.0
	wight.hp = 10000.0
	run.world.hit(hero, wight)
	check(10000.0 - wight.hp >= hero.attack * 0.85 * 2.0 * run.world.enemy_ai.armour_left(wight) - 0.01, "double damage")
	run.dispose()


func test_ram_thorn_stakes_hurt_siege() -> void:
	var run := _run()
	_give(run, "ram_thorn_stakes")
	var ram := _enemy(run, "battering_ram", Vector2(10, 0))
	var hp := ram.hp
	run.world.enemy_ai.thorns(ram)
	check_eq(ram.hp, hp - 10.0, "the stakes bite")
	run.dispose()


func test_beacon_pyre_one_side() -> void:
	var run := _run()
	_give(run, "beacon_pyre")
	run.round_number = 9
	run.world.roll_wave_sides()
	check_eq(run.world.wave_sides.size(), 1, "one side only")
	run.dispose()


# --- The earth -----------------------------------------------------------------------

func test_stillstone_holds_the_near_ring() -> void:
	var run := _run()
	var earth := run.world.earth
	check(earth.turn_of(0, 1) != 0.0, "the near ring turns")
	_give(run, "stillstone")
	check_eq(earth.turn_of(0, 1), 0.0, "and then it doesn't")
	run.dispose()


# --- Economy ----------------------------------------------------------------------------

func test_moneylender_pays_interest() -> void:
	var run := _run()
	_give(run, "moneylenders_knot")
	_to_relic(run)
	run.stock["shells"] = 100
	run.choose_relic("")
	check_eq(int(run.stock["shells"]), 100 + run.income() + 11, "income, then 10% of what is held, capped")
	run.dispose()


func test_ancestor_bones_after_a_round_without_deaths() -> void:
	var run := _run()
	_give(run, "ancestor_bones")
	var base := run.hearth_max_hp()
	_to_relic(run)
	if run.world.deaths.is_empty():
		check_eq(run.hearth_max_hp(), base + 6.0, "the hearth grows")
	else:
		check_eq(run.hearth_max_hp(), base, "not after a round with deaths")
	run.dispose()
