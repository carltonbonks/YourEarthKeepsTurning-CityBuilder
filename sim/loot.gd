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


## One stat of an item: the base's stat times its tier, plus every affix. bonus is the owned relics' gear_bonus
## (RunState.gear_bonus(), {tag: {stat: per tier}}): gear whose base carries one of those tags gains it per tier.
static func stat(content: Content, item: Dictionary, key: String, bonus := {}) -> float:
	var total := float(content.items["bases"][item["base"]].get(key, 0.0)) * int(item["tier"])
	for a: String in item["affixes"]:
		total += float(content.items["affixes"][a].get(key, 0.0))
	for tag: String in bonus:
		if content.has_tag("item", item["base"], tag):
			total += float(bonus[tag].get(key, 0.0)) * int(item["tier"])
	return total


## Sum of one stat across everything a hero has equipped.
static func total(content: Content, hero: Unit, key: String, bonus := {}) -> float:
	var sum := 0.0
	for s: String in hero.items:
		sum += stat(content, hero.items[s], key, bonus)
	return sum


## Extra damage a hero's gear does against this victim: each item's bane (attack per tier) against a tag it carries.
static func bane(content: Content, hero: Unit, victim: Unit) -> float:
	var extra := 0.0
	for s: String in hero.items:
		var item: Dictionary = hero.items[s]
		var b: Dictionary = content.items["bases"][item["base"]].get("bane", {})
		if not b.is_empty() and content.unit_has_tag(victim, b["tag"]):
			extra += float(b["attack"]) * int(item["tier"])
	return extra


static func value(content: Content, item: Dictionary) -> int:
	return int(content.items["value_per_tier"]) * int(item["tier"]) \
		+ int(content.items["value_per_affix"]) * item["affixes"].size()


## An item's rarity (data/rarity.json): by how many affixes it has, raised by any affix with a rarity of its own.
static func rarity(content: Content, item: Dictionary) -> String:
	var by: Array = content.items["rarity_by_affixes"]
	var best: String = by[mini(item["affixes"].size(), by.size() - 1)]
	var own_base: String = content.items["bases"][item["base"]].get("rarity", "white")
	if content.rarity["order"].find(own_base) > content.rarity["order"].find(best):
		best = own_base
	var order: Array = content.rarity["order"]
	for a: String in item["affixes"]:
		var own: String = content.items["affixes"][a].get("rarity", "white")
		if order.find(own) > order.find(best):
			best = own
	return best


## e.g. "keen flint blade (t2)".
static func describe(content: Content, item: Dictionary) -> String:
	var words := PackedStringArray()
	for a: String in item["affixes"]:
		words.append(content.items["affixes"][a]["name"].to_lower())
	words.append(content.items["bases"][item["base"]]["name"])
	return "%s (t%d)" % [" ".join(words), int(item["tier"])]


## How much a hero with these tastes wants an item (see "likes" in data/heroes.json). bonus as in stat(), so
## heroes come to favour gear the town's relics strengthen.
static func score(content: Content, item: Dictionary, likes: Dictionary, bonus := {}) -> float:
	var s := 0.0
	for key: String in STATS:
		s += stat(content, item, key, bonus) * float(likes.get(key, 0.0))
	return s


## A random dropped item. Tier grows with the round; its rarity (rolled first) sets its affixes or makes it a unique.
## Bases from a later age only drop once the town has reached it. slot ("" for any) limits the bases;
## min_affixes tops the affixes up (a pedlar's wares).
static func roll(content: Content, rng: SeededRng, round_number: int, age := "", slot := "", min_affixes := 0) -> Dictionary:
	var drops: Dictionary = content.items["drops"]
	var tier := clampi(1 + (round_number - 1) / int(drops["tier_every_rounds"]) + (1 if rng.randf() < 0.25 else 0),
		1, int(drops["max_tier"]))
	# A rarity first (odds climb with the round): white, blue and yellow set how many affixes, mythic is a named unique.
	var by: Array = content.items["rarity_by_affixes"]
	var rarities := by.duplicate()
	var uniques := _bases(content, tier, age, slot, true)
	if round_number >= int(drops["mythic_from_round"]) and not uniques.is_empty():
		rarities.append(content.rarest())
	var rarity: String = rng.pick_by(rarities, func(r: String) -> float: return content.rarity_odds(r, round_number))
	if rarity == content.rarest() and not by.has(rarity):
		return make(rng.pick(uniques), tier)
	var affix_ids: Array = content.items["affixes"].keys()
	affix_ids.sort()
	var affixes := []
	while affixes.size() < mini(maxi(by.find(rarity), min_affixes), affix_ids.size()):
		var extra: String = rng.pick(affix_ids)
		if not affixes.has(extra):
			affixes.append(extra)
	return make(rng.pick(_bases(content, tier, age, slot, false)), tier, affixes)


## A mythic item for a legend: a named unique of the town's age (any slot when none fits slot). {} if there is none.
static func mythic(content: Content, rng: SeededRng, round_number: int, age := "", slot := "") -> Dictionary:
	var drops: Dictionary = content.items["drops"]
	var tier := clampi(1 + (round_number - 1) / int(drops["tier_every_rounds"]), 1, int(drops["max_tier"]))
	var uniques := _bases(content, tier, age, slot, true)
	if uniques.is_empty():
		uniques = _bases(content, tier, age, "", true)
	return {} if uniques.is_empty() else make(rng.pick(uniques), tier)


## The bases that can drop at this tier, age and slot, sorted: the ordinary ones, or only the mythic uniques.
static func _bases(content: Content, tier: int, age: String, slot: String, uniques: bool) -> Array:
	var bases: Array = content.items["bases"].keys().filter(func(id: String) -> bool:
		var b: Dictionary = content.items["bases"][id]
		return int(b.get("min_tier", 1)) <= tier \
			and (age == "" or content.age_reached(age, b.get("age", ""))) \
			and (age != "" or not b.has("age")) \
			and (slot == "" or b["slot"] == slot) \
			and (b.get("rarity", "white") == content.rarest()) == uniques)
	bases.sort()
	return bases
