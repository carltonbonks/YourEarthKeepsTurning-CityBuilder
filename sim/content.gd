class_name Content
extends RefCounted
## All tunable game content, loaded from the JSON files in data/.
##
## Nothing in sim/ hardcodes balance numbers: they come from here, so changing
## a number in data/ changes the game without touching code.

const DATA_DIR := "res://data"
## Kinds of entity that can carry "tags" in their data, for tags_of() and has_tag().
const TAG_KINDS := ["enemy", "hero", "trait", "townsfolk", "building", "item", "relic", "node", "deal", "mark", "card_mod", "plate"]

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
var plates: Dictionary  ## data/plates.json: the shifting earth past the town (see Earth).
var traditions: Dictionary  ## data/traditions.json: founding traditions picked before round 1.
var paths: Dictionary  ## data/paths.json: run paths (heroes, warband, guilds, trade) and their tiers; charters at age-ups.
var crafts: Dictionary  ## data/crafts.json: a workshop and its stall drafted together, and what each craft opens.
var ventures: Dictionary  ## data/ventures.json: dawn cards that spend tribespeople for goods.
var pedlars: Dictionary  ## data/pedlars.json: the pedlars invited on pedlar rounds and their camp (see PedlarCamp).
var trades: Dictionary  ## data/trades.json: the caravan's trade cards (see Caravan).
var marks: Dictionary  ## data/marks.json: lasting edges single townsfolk earn (warriors drilling beside heroes).
var card_mods: Dictionary  ## data/card_mods.json: the powerful and transmuting modifiers a rolled card can carry.
var upgrades: Dictionary  ## data/upgrades.json: draft offers that change a building the town has, for the run.
var rarity: Dictionary  ## data/rarity.json: the four rarities (white, blue, yellow, orange) anything can carry.
var tips: Dictionary  ## data/tips.json: what a new player is told (the round screen before each run, one-time tips).


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
	c.plates = _strip(_read("plates.json"))
	c.traditions = _strip(_read("traditions.json"))
	c.paths = _strip(_read("paths.json"))
	c.crafts = _strip(_read("crafts.json"))
	c.ventures = _strip(_read("ventures.json"))
	c.pedlars = _strip(_read("pedlars.json"))
	c.rarity = _strip(_read("rarity.json"))
	c.trades = _strip(_read("trades.json"))
	c.upgrades = _strip(_read("upgrades.json"))
	c.marks = _strip(_read("marks.json"))
	c.card_mods = _strip(_read("card_mods.json"))
	c.tips = _strip(_read("tips.json"))
	return c


## A copy for one run: the same data, but buildings of its own, so upgrades taken in this run
## (RunState.take_upgrade) change only this run.
func for_run() -> Content:
	var c := Content.new()
	for p in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			c.set(p["name"], get(p["name"]))
	c.buildings = buildings.duplicate(true)
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


## Everything a unit is: an enemy's type tags; a hero's class and trait tags; a townsperson's role tags, its mark's
## and its card modifiers'.
func unit_tags(unit: Unit) -> Array:
	if unit.is_enemy():
		return tags_of("enemy", unit.type_id)
	if unit.is_hero():
		return tags_of("hero", unit.type_id) + tags_of("trait", unit.trait_id)
	if unit.mark == "" and unit.boons.is_empty():
		return tags_of("townsfolk", unit.type_id)
	var out := tags_of("townsfolk", unit.type_id) + (tags_of("mark", unit.mark) if unit.mark != "" else [])
	for id in unit.boons:
		out += tags_of("card_mod", id)
	return out


func unit_has_tag(unit: Unit, tag: String) -> bool:
	return tag in unit_tags(unit)


## An entity's rarity id from its own data ("white" when it has none). kind is one of TAG_KINDS.
func rarity_of(kind: String, id: String) -> String:
	return tag_table(kind).get(id, {}).get("rarity", "white")


## A rarity's entry in data/rarity.json ({name, color, weight}).
func rarity_tier(rarity_id: String) -> Dictionary:
	return rarity["tiers"].get(rarity_id, rarity["tiers"]["white"])


func rarity_color(rarity_id: String) -> Color:
	return Color(rarity_tier(rarity_id)["color"])


## How often a rarity is offered next to a white one (1.0 = as often).
func rarity_weight(rarity_id: String) -> float:
	return float(rarity_tier(rarity_id)["weight"])


## A rarity's weight in a given round: rarer things turn up more as the run goes on. By the last round each
## rarity has closed rarity_climb (data/balance.json) of its gap to white.
func rarity_odds(rarity_id: String, round_number: int) -> float:
	var w := rarity_weight(rarity_id)
	var t := clampf(float(round_number - 1) / maxf(1.0, num("rounds_to_win") - 1.0), 0.0, 1.0)
	return w + (1.0 - w) * num("rarity_climb") * t


## The rarest rarity (mythic, orange).
func rarest() -> String:
	return rarity["order"][-1]


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
		"node":
			return world["nodes"]
		"deal":
			return trades["deals"]
		"mark":
			return marks
		"card_mod":
			return card_mods
		"plate":
			return plates["near_kinds"]
	assert(false, "Unknown tag kind %s (see Content.TAG_KINDS)" % kind)
	return {}


## True once a town in age `current` has reached age `needed` ("" needs nothing).
func age_reached(current: String, needed: String) -> bool:
	if needed == "":
		return true
	return ages["order"].find(current) >= ages["order"].find(needed)


func age_name(id: String) -> String:
	return ages["ages"][id]["name"]


## The name of the building that brings an age (its "ages_up"), e.g. "Stone keep" for the medieval age.
func age_builder_name(id: String) -> String:
	for b: String in buildings:
		if buildings[b].get("ages_up", "") == id:
			return buildings[b]["name"]
	return age_name(id)


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
		return "%s ingot" % id if id == "bronze" else ("iron bloom" if id == "iron" else id)
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
