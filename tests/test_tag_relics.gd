extends TestCase
## Relics keyed on tags (data/relics.json foe_damage, foe_spoils, gear_bonus, node_yield): each acts on whatever
## carries its tag, whichever enemy, item or node that is.


func _run() -> RunState:
	return RunState.new(Content.load_default(), 4821)


func _enemy(run: RunState, type: String, at := Vector2(500, 0)) -> Unit:
	var e := run.world.enemy_ai.make_enemy(type, at, 0.0)
	e.max_hp = 10000.0
	e.hp = 10000.0
	run.world.enemies.append(e)
	return e


## Damage one bare-handed hero blow does to this enemy, before its armour.
func _blow(run: RunState, type: String) -> float:
	var hero := run.heroes[0]
	var e := _enemy(run, type)
	run.world.hit(hero, e)
	return (10000.0 - e.hp) / run.world.enemy_ai.armour_left(e)


func test_foe_damage_strikes_only_its_tag_harder() -> void:
	var run := _run()
	var hero := run.heroes[0]
	hero.items = {}
	run.world.hero_ai.apply_hero_stats(hero)
	run._gain_relic("blood_mark")
	check(_blow(run, "wolf") >= hero.attack * 0.85 * 1.4 - 0.01, "a beast takes 40% more")
	check(_blow(run, "raider") <= hero.attack * 1.15 + 0.01, "a raider takes no more")
	run.dispose()


func test_foe_damage_adds_up_across_relics() -> void:
	var run := _run()
	run._gain_relic("barrow_kings_lamp")
	run._gain_relic("bone_ward")
	check_eq(run.tag_mod("foe_damage", ["undead", "sentient"]), 1.5, "Barrow-king's lamp and Bone ward both count")
	check_eq(run.tag_mod("foe_damage", ["beast"]), 0.0, "neither reaches beasts")
	run.dispose()


func test_foe_spoils_from_tagged_kills() -> void:
	var run := _run()
	# What a wolf's carcass gives anyway, before the knife.
	var food := int(run.stock["food"])
	var hides := int(run.stock.get("hides", 0))
	run.world.damage(null, _enemy(run, "wolf"), 99999.0)
	var plain_food := int(run.stock["food"]) - food
	var plain_hides := int(run.stock.get("hides", 0)) - hides
	run._gain_relic("blood_mark")
	food = int(run.stock["food"])
	hides = int(run.stock.get("hides", 0))
	run.world.damage(null, _enemy(run, "wolf"), 99999.0)
	check_eq(int(run.stock["food"]) - food, plain_food + 2, "a beast gives 2 food more")
	check_eq(int(run.stock["hides"]) - hides, plain_hides + 1, "and a hide more")
	food = int(run.stock["food"])
	run.world.damage(null, _enemy(run, "raider"), 99999.0)
	check_eq(int(run.stock["food"]), food, "a raider gives nothing")
	run.dispose()


func test_gear_bonus_strengthens_tagged_gear_and_heroes_favour_it() -> void:
	var run := _run()
	var c := run.content
	var spear := Loot.make("bone_spear", 2)
	var blade := Loot.make("flint_blade", 2)
	var likes := {"attack": 1.0}
	var spear_before := Loot.score(c, spear, likes, run.gear_bonus())
	run._gain_relic("barrow_kings_lamp")
	check_eq(Loot.stat(c, spear, "attack", run.gear_bonus()), Loot.stat(c, spear, "attack") + 2.0, "+1 a tier on bone")
	check_eq(Loot.stat(c, blade, "attack", run.gear_bonus()), Loot.stat(c, blade, "attack"), "nothing on stone")
	check(Loot.score(c, spear, likes, run.gear_bonus()) > spear_before, "heroes rate bone gear higher")
	var hero := run.heroes[0]
	hero.items = {"weapon": spear}
	run.world.hero_ai.apply_hero_stats(hero)
	var with_rite := hero.attack
	run.relics.erase("barrow_kings_lamp")
	run.world.hero_ai.apply_hero_stats(hero)
	check_eq(with_rite, hero.attack + 2.0, "a hero with a bone spear hits harder")
	run.dispose()


func test_node_yield_brings_more_from_tagged_ground() -> void:
	var run := _run()
	var folk := run.world.folk_ai
	var unit := folk.add_folk("tribesperson")
	unit.leaning = ""
	var rocks := folk.carry_of(unit, "stone", "rocks")
	var grove := folk.carry_of(unit, "wood", "grove")
	run._gain_relic("cairn_wardens_cord")
	check_eq(folk.carry_of(unit, "stone", "rocks"), int(rocks * 1.4), "40% more from rocks")
	check_eq(folk.carry_of(unit, "wood", "grove"), grove, "groves are not stony")
	run.dispose()


func test_tooltips_name_tags_and_the_relics_acting_on_them() -> void:
	var run := _run()
	var c := run.content
	check(Tooltips.gear_line(c, "weapon", Loot.make("bone_spear", 1)).ends_with("[bone]"), "gear shows its tags")
	run._gain_relic("blood_mark")
	var notes := " ".join(PackedStringArray(Tooltips.tag_notes(run, "enemy", "wolf")))
	check(notes.contains("Hunter's blood-mark"), "a wolf's beast tag names the owned relic")
	run.dispose()


func test_affinity_reaches_foes_gear_nodes_and_plates() -> void:
	var run := _run()
	var c := run.content
	run._gain_relic("cairn_wardens_cord")
	check_eq(Loot.stat(c, Loot.make("flint_blade", 2), "attack", run.gear_bonus()), Loot.stat(c, Loot.make("flint_blade", 2), "attack") + 2.0, "stone gear +1 a tier")
	check(run.tag_mod("node_yield", c.tags_of("node", "flint_pit")) > 0.0, "stony nodes yield more")
	check(not run.tag_sums("plate_knobs", ["stone"]).is_empty(), "the Stonefield's numbers change")
	run.dispose()


func test_wet_affinity_reaches_bog_iron() -> void:
	var run := _run()
	run._gain_relic("bog_drowners_stake")
	check_eq(run.tag_mod("node_yield", run.content.tags_of("node", "iron_bog")), 1.0, "twice as much bog iron")
	run.dispose()


func test_node_regrow_relic_regrows_tagged_nodes_at_dawn() -> void:
	var run := _run()
	var w := run.world
	var berries := -1
	var rocks := -1
	for i in w.nodes.size():
		if w.nodes[i]["type"] == "berries" and berries < 0:
			berries = i
		if w.nodes[i]["type"] == "rocks" and rocks < 0:
			rocks = i
	check(berries >= 0 and rocks >= 0, "the map has berries and rocks")
	check_eq(w.relic_regrowth(w.nodes[berries]), 0, "nothing without the veil")
	run._gain_relic("thorn_witchs_veil")
	w.nodes[berries]["amount"] = 0
	check(w.relic_regrowth(w.nodes[berries]) >= 1, "berries regrow with it")
	check_eq(w.relic_regrowth(w.nodes[rocks]), 0, "rocks don't")
	w._tend_nodes()
	check(int(w.nodes[berries]["amount"]) >= 1, "and do so at dawn")
	run.dispose()


func test_foe_xp_gives_heroes_more_from_tagged_foes() -> void:
	var run := _run()
	var hero := run.heroes[0]
	var xp := hero.xp
	run.world.damage(hero, _enemy(run, "raider"), 99999.0)
	var plain := hero.xp - xp
	run._gain_relic("bloodied_banner")
	xp = hero.xp
	run.world.damage(hero, _enemy(run, "raider"), 99999.0)
	check(hero.xp - xp > plain + 0.01, "more XP from a human")
	xp = hero.xp
	run.world.damage(hero, _enemy(run, "wolf"), 99999.0)
	var wolf_xp := hero.xp - xp
	run.relics.erase("bloodied_banner")
	xp = hero.xp
	run.world.damage(hero, _enemy(run, "wolf"), 99999.0)
	check(is_equal_approx(hero.xp - xp, wolf_xp), "no more from a beast")
	run.dispose()


func test_foe_glory_lasts_after_a_trophy_falls() -> void:
	var run := _run()
	var hero := run.heroes[0]
	run._gain_relic("trophy_kings_crown")
	var attack := hero.attack
	var hearth := run.hearth_max_hp()
	run.world.damage(null, _enemy(run, "wolf"), 99999.0)
	check_eq(hero.attack, attack, "a wolf is no trophy")
	run.world.damage(null, _enemy(run, "cave_bear"), 99999.0)
	check_eq(hero.attack, attack + 1.0, "a cave bear makes every hero hit harder")
	check_eq(run.hearth_max_hp(), hearth + 5.0, "and the hearth stronger")
	run.world.hero_ai.apply_hero_stats(hero)
	check_eq(hero.attack, attack + 1.0, "for good")
	run.dispose()


func test_mark_bonus_reaches_marked_townsfolk() -> void:
	var run := _run()
	var folk := run.world.folk_ai
	var swift := folk.add_folk("tribesperson")
	swift.mark = "swift"
	var plain := folk.add_folk("tribesperson")
	plain.mark = ""
	check_eq(folk.unit_mod(swift, "carry"), 0.0, "no bonus yet")
	run._gain_relic("swiftfoot_anklet")
	check_eq(folk.unit_mod(swift, "carry"), 1.0, "a swift townsperson carries 1 more")
	check_eq(folk.unit_mod(plain, "carry"), 0.0, "an unmarked one doesn't")
	run.dispose()


func test_whetstone_spreads_marks_at_dawn() -> void:
	var run := _run()
	var folk := run.world.folk_ai
	for u in run.world.folk:
		u.mark = ""
	var teacher := folk.add_folk("tribesperson")
	teacher.mark = "hardy"
	for i in 4:
		folk.add_folk("tribesperson").mark = ""
	folk.spread_marks()
	check_eq(run.world.folk.filter(func(u: Unit) -> bool: return u.mark == "hardy").size(), 1, "nothing without the whetstone")
	run._gain_relic("elders_whetstone")
	folk.spread_marks()
	check_eq(run.world.folk.filter(func(u: Unit) -> bool: return u.mark == "hardy").size(), 3, "two learn it in a dawn")
	run.dispose()


func test_glory_hounds_banner_pays_bold_heroes_on_the_ring() -> void:
	var run := _run()
	var w := run.world
	var hero := run.heroes[0]
	hero.trait_id = "brave"
	run._gain_relic("glory_hounds_banner")
	var ring := Vector2.ZERO
	for r in range(200, 800, 10):
		if w.earth.kind_at(Vector2(r, 0)) != "":
			ring = Vector2(r, 0)
			break
	check(ring != Vector2.ZERO, "the turning ring is on the map")
	var gold := hero.gold
	w.damage(hero, _enemy(run, "raider", Vector2(790, 0)), 99999.0)
	var off_ring := hero.gold - gold
	gold = hero.gold
	w.damage(hero, _enemy(run, "raider", ring), 99999.0)
	check(hero.gold - gold > off_ring, "a bold hero earns more on the ring (%d vs %d)" % [hero.gold - gold, off_ring])
	run.dispose()
