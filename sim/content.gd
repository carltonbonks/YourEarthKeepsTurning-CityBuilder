class_name Content
extends RefCounted
## All tunable game content, loaded from the JSON files in data/.
##
## Nothing in sim/ hardcodes balance numbers: they come from here, so changing
## a number in data/ changes the game without touching code.

const DATA_DIR := "res://data"
## Kinds of entity that can carry "tags" in their data, for tags_of() and has_tag().
const TAG_KINDS := ["enemy", "hero", "trait", "townsfolk", "building", "item", "relic"]

var balance: Dictionary
var hero_classes: Dictionary
var traits: Dictionary
var hero_names: Array
var whims: Dictionary
var items: Dictionary
var enemies: Dictionary
var relics: Dictionary
var townsfolk: Dictionary
var buildings: Dictionary
var world: Dictionary
var market: Dictionary  ## data/recipes.json: recipes, provisions and market numbers.
var ages: Dictionary  ## data/ages.json: the tech ages in order, tool sets and the trader.
var promotions: Dictionary  ## data/promotions.json: when townsfolk can be promoted and into what.
var town: Dictionary  ## data/town.json: town rings and plots, obstacles, ground, trails and roads.
var tags: Dictionary  ## data/tags.json: what each tag that a rule reads means, for tooltips.


static func load_default() -> Content:
	var c := Content.new()
	c.balance = _strip(_read("balance.json"))
	var heroes := _read("heroes.json")
	c.hero_classes = heroes["classes"]
	c.traits = heroes["traits"]
	c.hero_names = heroes["names"]
	c.whims = heroes["whims"]
	c.items = _strip(_read("items.json"))
	c.enemies = _strip(_read("enemies.json"))
	c.relics = _strip(_read("relics.json"))
	c.townsfolk = _strip(_read("townsfolk.json"))
	c.buildings = _strip(_read("buildings.json"))
	c.world = _strip(_read("world.json"))
	c.market = _strip(_read("recipes.json"))
	c.ages = _strip(_read("ages.json"))
	c.promotions = _strip(_read("promotions.json"))
	c.town = _strip(_read("town.json"))
	c.tags = _strip(_read("tags.json"))
	return c


func num(key: String) -> float:
	return float(balance[key])


func int_num(key: String) -> int:
	return int(balance[key])


## The tags an entity carries in its data: its "tags" list. kind is one of TAG_KINDS, e.g.
## tags_of("enemy", "wolf") -> ["animal", "sentient", "beast"]. Unknown ids carry none.
func tags_of(kind: String, id: String) -> Array:
	var table := tag_table(kind)
	return table.get(id, {}).get("tags", [])


## True if an entity's data carries a tag. Rules read tags only through this (or unit_has_tag),
## and every tag a rule reads is explained in data/tags.json (tests/test_tags.gd checks it).
func has_tag(kind: String, id: String, tag: String) -> bool:
	return tag in tags_of(kind, id)


## Everything a unit is: an enemy's type tags; a hero's class and trait tags; a townsperson's role tags.
func unit_tags(unit: Unit) -> Array:
	if unit.is_enemy():
		return tags_of("enemy", unit.type_id)
	if unit.is_hero():
		return tags_of("hero", unit.type_id) + tags_of("trait", unit.trait_id)
	return tags_of("townsfolk", unit.type_id)


func unit_has_tag(unit: Unit, tag: String) -> bool:
	return tag in unit_tags(unit)


## The data table for a tag kind (see TAG_KINDS), keyed by id.
func tag_table(kind: String) -> Dictionary:
	match kind:
		"enemy":
			return enemies
		"hero":
			return hero_classes
		"trait":
			return traits
		"townsfolk":
			return townsfolk
		"building":
			return buildings
		"item":
			return items["bases"]
		"relic":
			return relics
	assert(false, "Unknown tag kind %s (see Content.TAG_KINDS)" % kind)
	return {}


## True once a town in age `current` has reached age `needed` ("" needs nothing).
func age_reached(current: String, needed: String) -> bool:
	if needed == "":
		return true
	return ages["order"].find(current) >= ages["order"].find(needed)


func age_name(id: String) -> String:
	return ages["ages"][id]["name"]


## Recipe ids a workshop type can make, sorted.
func recipes_for(workshop: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in market["recipes"]:
		if market["recipes"][id]["workshop"] == workshop:
			out.append(id)
	out.sort()
	return out


## What a recipe is called, e.g. "flint blade" or "smoked meat".
func recipe_name(id: String) -> String:
	var r: Dictionary = market["recipes"][id]
	if r.has("item"):
		return items["bases"][r["item"]]["name"]
	if r.has("makes"):
		return "%s ingot" % id if id == "bronze" else id
	return market["provisions"][r["provision"]]["name"]


## Building type ids that heroes can sleep in, sorted.
func lodging_types() -> Array[String]:
	var out: Array[String] = []
	for id: String in buildings:
		if buildings[id].has("lodging"):
			out.append(id)
	out.sort()
	return out


static func _read(file: String) -> Dictionary:
	var path := DATA_DIR.path_join(file)
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	assert(parsed is Dictionary, "Could not parse %s" % path)
	return parsed


## Drops "_note" style comment keys.
static func _strip(d: Dictionary) -> Dictionary:
	var out := {}
	for key: String in d:
		if not key.begins_with("_"):
			out[key] = d[key]
	return out
