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
	run._gain_relic("grave_salt")
	run._gain_relic("bone_ward")
	check_eq(run.tag_mod("foe_damage", ["undead", "sentient"]), 1.5, "Grave Salt and Bone Ward both count")
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
	run._gain_relic("skinning_knife")
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
	run._gain_relic("bone_readers_rite")
	check_eq(Loot.stat(c, spear, "attack", run.gear_bonus()), Loot.stat(c, spear, "attack") + 2.0, "+1 a tier on bone")
	check_eq(Loot.stat(c, blade, "attack", run.gear_bonus()), Loot.stat(c, blade, "attack"), "nothing on stone")
	check(Loot.score(c, spear, likes, run.gear_bonus()) > spear_before, "heroes rate bone gear higher")
	var hero := run.heroes[0]
	hero.items = {"weapon": spear}
	run.world.hero_ai.apply_hero_stats(hero)
	var with_rite := hero.attack
	run.relics.erase("bone_readers_rite")
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
	run._gain_relic("quarry_spirit")
	check_eq(folk.carry_of(unit, "stone", "rocks"), int(rocks * 1.5), "half again from rocks")
	check_eq(folk.carry_of(unit, "wood", "grove"), grove, "groves are not stony")
	run.dispose()


func test_tooltips_name_tags_and_the_relics_acting_on_them() -> void:
	var run := _run()
	var c := run.content
	check(Tooltips.gear_line(c, "weapon", Loot.make("bone_spear", 1)).ends_with("[bone]"), "gear shows its tags")
	run._gain_relic("blood_mark")
	var notes := " ".join(PackedStringArray(Tooltips.tag_notes(run, "enemy", "wolf")))
	check(notes.contains("Hunter's Blood-mark"), "a wolf's beast tag names the owned relic")
	run.dispose()
