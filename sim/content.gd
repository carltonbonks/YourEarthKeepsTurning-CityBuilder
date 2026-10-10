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
var gear: Dictionary
var enemies: Dictionary
var relics: Dictionary
var townsfolk: Dictionary
var buildings: Dictionary
var world: Dictionary


static func load_default() -> Content:
	var c := Content.new()
	c.balance = _strip(_read("balance.json"))
	var heroes := _read("heroes.json")
	c.hero_classes = heroes["classes"]
	c.traits = heroes["traits"]
	c.hero_names = heroes["names"]
	c.gear = heroes["gear"]
	c.enemies = _strip(_read("enemies.json"))
	c.relics = _strip(_read("relics.json"))
	c.townsfolk = _strip(_read("townsfolk.json"))
	c.buildings = _strip(_read("buildings.json"))
	c.world = _strip(_read("world.json"))
	return c


func num(key: String) -> float:
	return float(balance[key])


func int_num(key: String) -> int:
	return int(balance[key])


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
