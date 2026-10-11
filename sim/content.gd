class_name Content
extends RefCounted
## All tunable game content, loaded from the JSON files in data/.
##
## Nothing in sim/ hardcodes balance numbers: they come from here, so changing
## a number in data/ changes the game without touching code.

const DATA_DIR := "res://data"

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
	return c


func num(key: String) -> float:
	return float(balance[key])


func int_num(key: String) -> int:
	return int(balance[key])


## True if an enemy type carries a tag (see "tags" in data/enemies.json).
func enemy_has_tag(type_id: String, tag: String) -> bool:
	return tag in enemies[type_id].get("tags", [])


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
