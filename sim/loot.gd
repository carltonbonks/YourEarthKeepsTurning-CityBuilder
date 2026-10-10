class_name Loot
extends RefCounted
## Items: what they do, what they're worth, and how a hero rates them.
## An item is plain data, {base, tier, affixes}, so it saves and copies easily.
## Bases and affixes live in data/items.json.

const SLOTS := ["weapon", "armor", "charm"]
const STATS := ["attack", "hp", "speed", "energy", "loot", "rest_heal"]


static func make(base: String, tier: int, affixes: Array = []) -> Dictionary:
	return {"base": base, "tier": tier, "affixes": affixes.duplicate()}


static func slot(content: Content, item: Dictionary) -> String:
	return content.items["bases"][item["base"]]["slot"]


## One stat of an item: the base's stat times its tier, plus every affix.
static func stat(content: Content, item: Dictionary, key: String) -> float:
	var total := float(content.items["bases"][item["base"]].get(key, 0.0)) * int(item["tier"])
	for a: String in item["affixes"]:
		total += float(content.items["affixes"][a].get(key, 0.0))
	return total


## Sum of one stat across everything a hero has equipped.
static func total(content: Content, hero: Unit, key: String) -> float:
	var sum := 0.0
	for s: String in hero.items:
		sum += stat(content, hero.items[s], key)
	return sum


static func value(content: Content, item: Dictionary) -> int:
	return int(content.items["value_per_tier"]) * int(item["tier"]) \
		+ int(content.items["value_per_affix"]) * item["affixes"].size()


## e.g. "keen flint blade (t2)".
static func describe(content: Content, item: Dictionary) -> String:
	var words := PackedStringArray()
	for a: String in item["affixes"]:
		words.append(content.items["affixes"][a]["name"].to_lower())
	words.append(content.items["bases"][item["base"]]["name"])
	return "%s (t%d)" % [" ".join(words), int(item["tier"])]


## How much a hero with these tastes wants an item (see "likes" in data/heroes.json).
static func score(content: Content, item: Dictionary, likes: Dictionary) -> float:
	var s := 0.0
	for key: String in STATS:
		s += stat(content, item, key) * float(likes.get(key, 0.0))
	return s


## A random dropped item. Tier grows with the round; some get one or two affixes.
static func roll(content: Content, rng: SeededRng, round_number: int) -> Dictionary:
	var drops: Dictionary = content.items["drops"]
	var tier := clampi(1 + (round_number - 1) / int(drops["tier_every_rounds"]) + (1 if rng.randf() < 0.25 else 0),
		1, int(drops["max_tier"]))
	var bases: Array = content.items["bases"].keys().filter(func(id: String) -> bool:
		return int(content.items["bases"][id].get("min_tier", 1)) <= tier)
	bases.sort()
	var affix_ids: Array = content.items["affixes"].keys()
	affix_ids.sort()
	var affixes := []
	if rng.randf() < float(drops["affix_chance"]):
		affixes.append(rng.pick(affix_ids))
		if rng.randf() < float(drops["second_affix_chance"]):
			var second: String = rng.pick(affix_ids)
			if not affixes.has(second):
				affixes.append(second)
	return make(rng.pick(bases), tier, affixes)
