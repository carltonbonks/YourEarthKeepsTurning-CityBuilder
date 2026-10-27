class_name RunState
extends RefCounted
## One run of the game: the settlement, its stock, relics and the round loop.
##
## Round loop: BUILD (order buildings) -> for each day: PICK (choose a newcomer
## at dawn) -> SIM (the day and night play out on their own) -> after the last
## night, which brings the round's warned wave: RELIC (pick 1 of N) -> next BUILD.
## The run ends in WON (survived the last round) or LOST (hearth destroyed or
## everyone gone). No scenes or nodes here, so whole runs can be simulated headless.
##
## Three parts hold the rest: `people` (People: dawn cards, promotions, heroes and their mood),
## `waves` (WavePlanner: what attacks and when) and `record` (RunRecord: the run's history).

enum Phase { BUILD, PICK, SIM, RELIC, WON, LOST }

const RESOURCES := ["food", "fuel", "wood", "stone", "shells", "flint", "hides", "bone", "obsidian",
	"copper", "cassiterite", "tin", "bronze", "bog_iron", "charcoal", "iron", "steel"]

var content: Content
var run_seed: int
var round_number := 1
var phase := Phase.BUILD

var world: World
var people: People
var hand: BuildHand
var caravan: Caravan
var waves: WavePlanner
var record: RunRecord
var stock := {}
var heroes: Array[Unit] = []
var fallen: Array[Unit] = []
var fallen_folk := 0
var relics: Array[String] = []
var relic_acquired_round := {}
var relic_offer: Array[String] = []
## Founding traditions chosen before round 1 (data/traditions.json), and whether that choice is made (or skipped).
var traditions: Array[String] = []
## Upgrades taken this run (data/upgrades.json), in order.
var upgrades: Array[String] = []
var traditions_settled := false
## A gentle start for a player's first run (set by the game before round 1, never by bots): the first dawn offers
## only gentle_first_dawn tribespeople, and round 1's draft has no reroll.
var gentle := false
## Whether the tradition was left to chance (choose_random_tradition), which brought tradition_random_bonus.
var tradition_random := false
## The spoils in this round's relic offer: {id, kind (enemy tag), foes (how many of that kind came)}, or {}.
var spoils := {}
## Max hearth HP the town has earned for good (Ancestor Bones).
var bonus_hearth_hp := 0.0
## Dawn cards still to take this dawn (Twin Fires gives two), and townsfolk cards taken this run (Hearth-mother's Doll).
var picks_left := 1
var folk_cards_taken := 0
## Dawn cards: {kind: "folk"|"hero"|"promote"|"family", role: String, cost: int, hero: Unit (for hero cards),
## roles: Array (for a family), leaning: String (for a folk card whose role has leanings)}.
var pick_offer: Array[Dictionary] = []
## Enemy type ids of this round's wave, in spawn order.
var next_wave: Array[String] = []
## Raiders held back from this round's scheduled wave by catch-up (see WavePlanner.plan).
var wave_eased := 0
## This round's raiders the warband held back, and how many of them joined the war camp.
var held_back: Array[String] = []
var camp_joined := 0
## True when this round's scheduled wave outmatched the town enough for catch-up (see WavePlanner.plan).
var outmatched := false
## True when the town held an attack the warband didn't need to ease: the relic offer has glory_relic_choices more.
var glory := false
## Plain-language story of what happened, newest last.
var story: Array[String] = []
## The last night's report, shown at the next decision (see World.night_report).
var last_night := {}
## Price level per stall kind ("cheap", "fair" or "dear"; see data/recipes.json), set while building.
var prices := {}
## The town's tech age (an id from data/ages.json) and the round it was reached (0 = the start).
var age := ""
var age_up_round := 0
## The round each age after the first was reached: age id -> round.
var age_rounds := {}
## How many rings of plots are open (see Town.ring_open): start_rings in data/town.json, one more per age-up or cleared ring.
var rings_open := 0
## Tool sets bought for townsfolk groups (ids from "tools" in data/ages.json).
var tools: Array[String] = []
## Heroes who left town unhappy.
var departed: Array[Unit] = []
## The role of whoever left hungry this dawn ("" if nobody): none of that role come to the dawn pick.
var hunger_turned_away := ""
## The venture taken at the last dawn pick ({} if none): {venture, send, lost, goods}, so the screen can show who never came home.
var last_venture := {}

## Pedlar rounds (data/pedlars.json): the pedlars offered while building, each {id, pos} (where it would camp),
## the one invited ("" for none), and whether the choice is made (an unmade one invites nobody when the round begins).
var pedlar_offer: Array[Dictionary] = []
var pedlar := ""
var pedlar_settled := true

var _next_id := 1
var _effects_between_rounds := {}


func _init(game_content: Content, seed_value: int) -> void:
	content = game_content.for_run()
	run_seed = seed_value
	people = People.new(self)
	hand = BuildHand.new(self)
	caravan = Caravan.new(self)
	waves = WavePlanner.new(self)
	record = RunRecord.new(self)
	age = content.ages["order"][0]
	for r in RESOURCES:
		stock[r] = int(content.balance["start_stock"].get(r, 0))
	var kinds: Array = content.market["stall_names"].keys()
	kinds.sort()
	for kind: String in kinds:
		prices[kind] = "fair"
	rings_open = int(content.town["start_rings"])
	world = World.new(self)
	var start_people: Dictionary = content.balance["start_people"]
	var roles := start_people.keys()
	roles.sort()
	for role: String in roles:
		for i in int(start_people[role]):
			world.folk_ai.add_folk(role)
	for i in content.int_num("start_heroes"):
		people.add_hero(people.make_hero())
	tell("Round 1. A handful of people gather around a fire at the edge of the world.")
	_enter_build()


# --- Modifiers -------------------------------------------------------------

## Sum of one relic effect across all owned relics (0 if none have it).
func mod(key: String) -> float:
	var total := 0.0
	for id in relics:
		var effects: Dictionary = content.relics[id]["effects"]
		var v: Variant = effects.get(key, 0.0)
		total += float(v) if v is float or v is int else 0.0
	for id in traditions:
		total += float(content.traditions[id].get("effects", {}).get(key, 0.0))
	if world != null:
		total += float(world.building_effects.get(key, 0.0))
	return total


## Relic effects keyed on tags ({tag: ...}), read through tag_mod, tag_sums and gear_bonus.
const TAG_EFFECTS := ["foe_damage", "foe_spoils", "gear_bonus", "node_yield", "plate_knobs"]


## The effects of everything owned that has effects: relics, then traditions.
func _owned_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in relics:
		out.append(content.relics[id]["effects"])
	for id in traditions:
		out.append(content.traditions[id].get("effects", {}))
	return out


## Tag-keyed effects ({tag: number}, e.g. foe_damage {"beast": 0.4}): the sum over owned relics of the
## numbers for every tag in `tags`. So a relic for beasts also covers any new enemy that carries the tag.
func tag_mod(key: String, tags: Array) -> float:
	var total := 0.0
	for effects in _owned_effects():
		var by_tag: Dictionary = effects.get(key, {})
		for tag: String in by_tag:
			if tag in tags:
				total += float(by_tag[tag])
	return total


## Tag-keyed effects whose values are goods or stats ({tag: {key: number}}, e.g. foe_spoils, gear_bonus):
## summed per key over every tag in `tags`. Empty when nothing owned has the effect.
func tag_sums(key: String, tags: Array) -> Dictionary:
	var out := {}
	for effects in _owned_effects():
		var by_tag: Dictionary = effects.get(key, {})
		for tag: String in by_tag:
			if tag in tags:
				for k: String in by_tag[tag]:
					out[k] = float(out.get(k, 0.0)) + float(by_tag[tag][k])
	return out


## gear_bonus from every owned relic, merged: {tag: {stat: per tier}} for Loot.stat.
func gear_bonus() -> Dictionary:
	var out := {}
	for effects in _owned_effects():
		var by_tag: Dictionary = effects.get("gear_bonus", {})
		for tag: String in by_tag:
			var stats: Dictionary = out.get(tag, {})
			for k: String in by_tag[tag]:
				stats[k] = float(stats.get(k, 0.0)) + float(by_tag[tag][k])
			out[tag] = stats
	return out


# --- Founding traditions -----------------------------------------------------

## True while the run waits for its founding traditions: round 1's build phase, before they are chosen or skipped.
func awaiting_traditions() -> bool:
	return not traditions_settled and round_number == 1 and phase == Phase.BUILD


## Founds the town on up to traditions_to_pick traditions (an empty list founds it on none). Their start goods
## arrive, their blueprint is drafted in place of one of round 1's drafts, their effects apply and round 1's
## building hand is dealt again with their buildings favoured.
func choose_traditions(ids: Array) -> void:
	assert(awaiting_traditions())
	traditions_settled = true
	for id: String in ids:
		if content.traditions.has(id) and not traditions.has(id) and traditions.size() < content.int_num("traditions_to_pick"):
			traditions.append(id)
	for id in traditions:
		var start: Dictionary = content.traditions[id].get("start", {})
		for good: String in start:
			stock[good] = int(stock.get(good, 0)) + int(start[good])
		tell("The people keep the ways of the %s." % content.traditions[id]["name"])
		var gift := str(content.traditions[id].get("blueprint", ""))
		if gift != "":
			hand.gift(gift)
			tell("Their ways bring a blueprint: %s." % BuildHand.gift_name(content, gift))
	for u in world.folk:
		world.folk_ai.apply_folk_stats(u)
	for h in heroes:
		world.hero_ai.apply_hero_stats(h)
	hand.deal()


## Founds the town on one tradition drawn from the run's seed, plus tradition_random_bonus goods for leaving it to
## chance (Yusuf, 2026-10-25).
func choose_random_tradition() -> void:
	var ids: Array = content.traditions.keys()
	ids.sort()
	var pick: String = SeededRng.stream(run_seed, "tradition").pick(ids)
	tradition_random = true
	var bonus: Dictionary = content.balance.get("tradition_random_bonus", {})
	for good: String in bonus:
		stock[good] = int(stock.get(good, 0)) + int(bonus[good])
	choose_traditions([pick])


## The leanings the town's traditions favour.
func tradition_leanings() -> Array[String]:
	var out: Array[String] = []
	for id in traditions:
		var leaning := str(content.traditions[id].get("leaning", ""))
		if leaning != "":
			out.append(leaning)
	return out


## Whether one of the town's traditions favours this building's cards.
func tradition_favours(building: String) -> bool:
	return traditions.any(func(id: String) -> bool: return content.traditions[id].get("buildings", []).has(building))


## The hearth's health: the base, relics, and standing buildings that strengthen it (the Stone keep).
func hearth_max_hp() -> float:
	var total := content.num("hearth_max_hp") + mod("hearth_max_hp") + bonus_hearth_hp
	if world == null:
		return total
	for b in world.buildings:
		if float(b["work_left"]) <= 0.0:
			total += float(content.buildings[b["type"]].get("hearth_hp", 0.0))
	return total


## Shells the settlement earns at the start of each round.
func income() -> int:
	return maxi(0, int((content.num("income_shells_per_round") + mod("income")) * (1.0 + mod("income_mult"))))


## Whether this run owns a relic with this effect.
func has_effect(key: String) -> bool:
	return mod(key) != 0.0


## Counts a relic's rule firing in the round record ("relic_effects": effect key -> times). Between rounds
## (interest, the earth's turns) there is no round entry yet, so the count waits for the next one.
func relic_fired(effect: String, times := 1) -> void:
	if record.entry.is_empty():
		_effects_between_rounds[effect] = int(_effects_between_rounds.get(effect, 0)) + times
		return
	record.note_count("relic_effects", times, effect)


func living_heroes() -> Array[Unit]:
	return heroes.filter(func(h: Unit) -> bool: return h.alive)


func population() -> int:
	return world.folk.size() + living_heroes().size()


func housing() -> int:
	var total := content.int_num("base_housing")
	for type: String in content.buildings:
		total += world.count_buildings(type) * int(content.buildings[type].get("housing", 0))
	return total


func count_role(role: String) -> int:
	return world.folk.filter(func(u: Unit) -> bool: return u.type_id == role).size()


# --- Building (start of round) ----------------------------------------------

func can_afford(cost: Dictionary) -> bool:
	for r: String in cost:
		if int(stock.get(r, 0)) < int(cost[r]):
			return false
	return true


func can_build(type: String) -> bool:
	var def: Dictionary = content.buildings[type]
	var needs: String = def.get("requires", "")
	return phase == Phase.BUILD and can_afford(building_cost(type)) \
		and world.count_buildings(type, false) < building_max(type) \
		and (needs == "" or world.count_buildings(needs, false) > 0) \
		and content.age_reached(age, def.get("age", "")) and population() >= int(def.get("min_people", 0)) \
		and world.has_spot(type)


## How many of a building the town may have: its max, raised by max_by_age once the town reaches that age.
func building_max(type: String) -> int:
	var def: Dictionary = content.buildings[type]
	var most := int(def.get("max", 99))
	var by_age: Dictionary = def.get("max_by_age", {})
	for a: String in by_age:
		if content.age_reached(age, a):
			most = maxi(most, int(by_age[a]))
	return most


## What ordering one more of a building costs now: its cost, and for a building with copy_cost (data/buildings.json)
## that share more for every one already built or ordered (Yusuf 2026-10-26: everyday buildings can be built again).
func building_cost(type: String) -> Dictionary:
	var def: Dictionary = content.buildings[type]
	var grow := float(def.get("copy_cost", 0.0)) * world.count_buildings(type, false) if world != null else 0.0
	var cost := {}
	for r: String in def["cost"]:
		cost[r] = ceili(float(def["cost"][r]) * (1.0 + grow))
	return cost


func build(type: String) -> bool:
	var cost := building_cost(type)
	if not can_build(type) or not world.add_building(type):
		return false
	for r: String in cost:
		stock[r] = int(stock[r]) - int(cost[r])
	record.note_action({"kind": "build", "building": type})
	return true


## Takes an upgrade (data/upgrades.json): its numbers are added to its building's data for the rest of the run.
## A rolled offer (BuildHand.draft_upgrade) also notes its roll and modifiers in the action.
func take_upgrade(id: String, offer := {}) -> void:
	var up: Dictionary = content.upgrades[id]
	var def: Dictionary = content.buildings[up["building"]]
	for key: String in up["add"]:
		var parts := key.split(".")
		var at: Dictionary = def
		for i in parts.size() - 1:
			if not at.has(parts[i]):
				at[parts[i]] = {}
			at = at[parts[i]]
		var last := parts[parts.size() - 1]
		at[last] = float(at.get(last, 0.0)) + float(up["add"][key])
	upgrades.append(id)
	var action := {"kind": "upgrade", "upgrade": id}
	if offer.has("roll"):
		action["roll"] = offer["roll"]
		action["mods"] = offer["boons"].duplicate()
	record.note_action(action)
	tell("%s: %s" % [up["name"], up["text"]])


## True while building on a pedlar round until the player invites a pedlar or none (after the traditions).
func awaiting_pedlar() -> bool:
	return phase == Phase.BUILD and not pedlar_settled and not awaiting_traditions()


## Invites one of the offered pedlars to camp this round ("" for none).
func choose_pedlar(id: String) -> void:
	if not awaiting_pedlar():
		return
	pedlar_settled = true
	pedlar = id if pedlar_offer.any(func(o: Dictionary) -> bool: return o["id"] == id) else ""
	record.note_value("pedlar_offer", pedlar_offer.map(func(o: Dictionary) -> String: return o["id"]))
	record.note_action({"kind": "pedlar", "pedlar": pedlar})
	if pedlar != "":
		tell("You send word to the %s." % content.pedlars["pedlars"][pedlar]["name"].to_lower())


## The offered pedlar the player invited ({id, pos}), or {}.
func pedlar_choice() -> Dictionary:
	for o in pedlar_offer:
		if o["id"] == pedlar:
			return o
	return {}


# --- Market prices ----------------------------------------------------------

## Sets a stall kind's price level for the coming round ("cheap", "fair" or "dear").
func set_price(kind: String, level: String) -> void:
	if phase != Phase.BUILD or not prices.has(kind) or not content.market["price_levels"].has(level) or prices[kind] == level:
		return
	prices[kind] = level
	record.note_action({"kind": "price", "stall": kind, "level": level})


func price_markup(kind: String) -> float:
	return float(content.market["price_levels"][prices.get(kind, "fair")])


## What a hero pays for a good: the recipe's price per tier x the stall's level, less relic discounts.
func price_of(good: Dictionary) -> int:
	var r: Dictionary = content.market["recipes"][good["recipe"]]
	var discount := clampf(mod("gear_discount"), 0.0, 0.9) if r.has("item") else 0.0
	return maxi(1, roundi(float(r["price"]) * int(good.get("tier", 1)) * price_markup(r["stall"]) * (1.0 - discount)))


## Tier a workshop makes a recipe at this round.
func craft_tier(recipe_id: String) -> int:
	var r: Dictionary = content.market["recipes"][recipe_id]
	var tier := 1 + (round_number - 1) / int(content.market["tier_every_rounds"])
	return clampi(tier, int(r.get("min_tier", 1)), int(r.get("max_tier", 1)))


## Ends the build phase; the first dawn of the round follows.
func begin_round() -> void:
	assert(phase == Phase.BUILD)
	# Starting round 1 without choosing founds the town on no traditions.
	traditions_settled = true
	if not pedlar_settled:
		choose_pedlar("")
	if world.earth.enabled():
		record.note_value("crossing", world.wave_sides.map(func(a: float) -> String: return world.earth.crossing(a)))
	world.start_round()
	if pedlar != "":
		world.pedlar.open(pedlar_choice())
	people.offer_picks()


func on_building_done(type: String) -> void:
	var def: Dictionary = content.buildings[type]
	if def.has("lodging"):
		world.hero_ai.assign_lodgings()
	if def.has("hearth_hp"):
		world.hearth_hp = minf(hearth_max_hp(), world.hearth_hp + float(def["hearth_hp"]))
	# A building with effects (an oath stone's hero_attack) changes heroes' stats the moment it stands.
	if def.has("effects"):
		world.market.refresh_prizes()
		for hero in living_heroes():
			world.hero_ai.apply_hero_stats(hero)
	# Goods a building brings with it when it stands (the age-up buildings' founding gifts).
	for good: String in def.get("gift", {}):
		stock[good] = int(stock.get(good, 0)) + int(def["gift"][good])
	var next_age: String = def.get("ages_up", "")
	if next_age != "" and not content.age_reached(age, next_age):
		age = next_age
		age_up_round = round_number
		age_rounds[next_age] = round_number
		record.note_value("aged_up", next_age)
		world.town.lay_hearth_ground(next_age)
		open_ring()
		tell("The %s is raised. The %s begins: %s." % [def["name"], content.age_name(age), content.ages["ages"][age].get("begins", "")])


# --- Rings ---------------------------------------------------

## True if a ring of plots is still closed.
func ring_closed() -> bool:
	return rings_open < content.town["rings"].size()


## What clearing the next closed ring costs ({} if none is closed).
func ring_cost() -> Dictionary:
	return content.town["rings"][rings_open].get("clear_cost", {}) if ring_closed() else {}


## Opens the next closed ring (an age-up does it for free; BuildHand.clear_ring when the player pays).
func open_ring() -> void:
	if ring_closed():
		rings_open += 1


# --- Ages: tool sets -----------------------------------------

func can_buy_tools(id: String) -> bool:
	var def: Dictionary = content.ages["tools"][id]
	return phase == Phase.BUILD and not tools.has(id) and content.age_reached(age, def.get("age", "")) and can_afford(def["cost"])


## Buys a tool set: a lasting upgrade for one townsfolk group.
func buy_tools(id: String) -> bool:
	if not can_buy_tools(id):
		return false
	var def: Dictionary = content.ages["tools"][id]
	for r: String in def["cost"]:
		stock[r] = int(stock[r]) - int(def["cost"][r])
	tools.append(id)
	for u in world.folk:
		world.folk_ai.apply_folk_stats(u)
	record.note_action({"kind": "tools", "tools": id})
	tell("%s for the %ss." % [def["name"], content.townsfolk[def["role"]]["name"].to_lower()])
	return true


## Sum of one tool-set bonus for a townsfolk role (0 if none).
func tool_bonus(role: String, key: String) -> float:
	var total := 0.0
	for id in tools:
		var def: Dictionary = content.ages["tools"][id]
		if def["role"] == role:
			total += float(def.get(key, 0.0))
	return total


## True if a group has a tool set with this flag ("metal": pierces shields, "steel": cuts mail).
func has_tools_with(role: String, flag: String) -> bool:
	return tools.any(func(id: String) -> bool:
		return content.ages["tools"][id]["role"] == role and content.ages["tools"][id].get(flag, false))


# --- Dawn picks ------------------------------------------------------------

## A townsperson's name with its leaning, e.g. "Forager" (or the role's name without one).
func folk_name(role: String, leaning: String) -> String:
	if leaning == "":
		return content.townsfolk[role]["name"]
	return content.townsfolk[role]["leanings"][leaning]["name"]


func can_take_pick(index: int) -> bool:
	if phase != Phase.PICK or index < 0 or index >= pick_offer.size():
		return false
	var card := pick_offer[index]
	return (card["kind"] in ["promote", "venture"] or population() + people.card_people(card) <= housing()) and int(stock["shells"]) >= int(card["cost"])


## Takes a dawn card (-1 skips), then lets the day begin.
func choose_pick(index: int) -> void:
	assert(phase == Phase.PICK)
	var taken := ""
	var venture := {}
	last_venture = {}
	var took := can_take_pick(index)
	if took:
		var card := pick_offer[index]
		stock["shells"] = int(stock["shells"]) - int(card["cost"])
		if card["kind"] != "folk":
			CardRoll.note_taken(self, card)
		if card["kind"] == "hero":
			var hero: Unit = card["hero"]
			people.add_hero(hero)
			taken = "hero:" + hero.type_id
			tell("%s arrives and sleeps in %s." % [describe(hero), world.hero_ai.bed_name(hero.lodging)])
		elif card["kind"] == "promote":
			people.promote(card)
			taken = people.card_label(card)
		elif card["kind"] == "venture":
			venture = people.go_venturing(card)
			last_venture = venture
			taken = people.card_label(card)
		elif card["kind"] == "family":
			var arrived := people.settle_family(card)
			taken = "family"
			tell("A family of %d comes to settle." % arrived)
		else:
			var leaning: String = card.get("leaning", "")
			var newcomer := world.folk_ai.add_folk(card["role"], leaning)
			CardRoll.apply_to(self, newcomer, card)
			taken = card["role"]
			if card.has("roll"):
				tell("A %s joins the settlement: %s." % [folk_name(card["role"], leaning).to_lower(),
					"; ".join(CardRoll.lines(content, card)).to_lower()])
			else:
				tell("A %s joins the settlement." % folk_name(card["role"], leaning).to_lower())
			var extra := CardRoll.extra_people(content, card)
			for i in extra:
				world.folk_ai.add_folk(card["role"], leaning)
				tell("Twins: a second %s comes too." % folk_name(card["role"], leaning).to_lower())
			var doll := doll_twin_next()
			folk_cards_taken += 1
			if doll:
				# Hearth-mother's Doll doubles the whole card: a Twins card brings four.
				for i in 1 + extra:
					world.folk_ai.add_folk(card["role"], leaning)
				relic_fired("twin_every")
				tell("Hearth-mother's Doll doubles the %s: %d come in all." % [folk_name(card["role"], leaning).to_lower(), 2 * (1 + extra)])
	var entry := {"day": world.day_index() + 1, "offered": pick_offer.map(people.card_label), "taken": taken}
	var leanings := pick_offer.map(func(c: Dictionary) -> String: return str(c.get("leaning", "")))
	if leanings.any(func(l: String) -> bool: return l != ""):
		entry["offered_leanings"] = leanings
	if took and pick_offer[index].has("leaning"):
		entry["leaning"] = pick_offer[index]["leaning"]
	entry["offered_rarities"] = pick_offer.map(people.card_rarity)
	var rolls := pick_offer.map(CardRoll.roll_of)
	if rolls.any(func(r: String) -> bool: return r != "white"):
		entry["offered_rolls"] = rolls
	if took and pick_offer[index].has("roll"):
		entry["roll"] = pick_offer[index]["roll"]
		entry["mods"] = CardRoll.mods_of(pick_offer[index])
	if took and pick_offer[index].get("legend", false):
		entry["legend"] = true
	if hunger_turned_away != "":
		entry["hunger_turned_away"] = hunger_turned_away
	if not venture.is_empty():
		entry["venture_lost"] = venture["lost"]
		entry["venture_goods"] = venture["goods"]
	record.note_list("picks", entry)
	picks_left -= 1
	# Twin Fires: another newcomer from the cards left, unless the player skipped.
	if took and picks_left > 0 and pick_offer.size() > 1:
		pick_offer.remove_at(index)
		if not pick_offer.is_empty():
			relic_fired("extra_picks")
			return
	pick_offer = []
	hunger_turned_away = ""
	phase = Phase.SIM
	world.resume()
	tell("Day %d dawns." % (world.day_index() + 1))
	world.hero_ai.roll_whims()


## Whether Hearth-mother's Doll doubles the next townsfolk card taken (every 3rd one).
func doll_twin_next() -> bool:
	var every := int(mod("twin_every"))
	return every > 0 and (folk_cards_taken + 1) % every == 0


## Townsfolk cards still to take before the Doll next doubles one (0 without the Doll).
func doll_picks_to_twin() -> int:
	var every := int(mod("twin_every"))
	return every - folk_cards_taken % every if every > 0 else 0


## A master crafter's trait numbers ({} for an ordinary craftsperson).
func craft_trait(unit: Unit) -> Dictionary:
	if unit.craft_trait == "":
		return {}
	return content.promotions["craftsperson"]["traits"][unit.craft_trait]


# --- Simulation ------------------------------------------------------------

func step() -> void:
	if phase != Phase.SIM:
		return
	world.step()
	match world.pause:
		World.Pause.DAWN:
			people.bury_heroes()
			people.update_moods()
			_close_night()
			people.offer_picks()
		World.Pause.ROUND_OVER:
			_finish_round()
		World.Pause.HEARTH_LOST:
			_lose()


## Runs the world until it needs a decision (a dawn pick, a relic, or the end).
func run_until_pause() -> void:
	while phase == Phase.SIM:
		step()


## Food the town eats each dawn: every person, townsfolk and heroes alike, less drying racks and relics.
func food_needed_today() -> int:
	var racks := world.count_buildings("drying_rack")
	var growth := 0.0
	for id in relics:
		growth += float(content.relics[id]["effects"].get("food_growth", 0.0)) * (round_number - int(relic_acquired_round[id]))
	var eaten := 0
	for type: String in content.buildings:
		eaten += world.count_buildings(type) * int(content.buildings[type].get("eats", {}).get("food", 0))
	eaten += world.hero_ai.hounds() * int(world.hero_ai.kennel_def().get("food", 0))
	# Light eaters and those who eat for two (marks and card modifiers: upkeep) shift the town's mouths.
	var mouths := maxf(0.0, population() + world.folk_ai.folk_sum("upkeep"))
	return maxi(0, int(ceil(mouths * content.num("food_per_person_per_day") * (1.0 - 0.25 * racks) - growth))) + eaten


## Food that standing buildings (gardens, fields) bring in each dawn, before anyone eats. A building
## with worked_by only yields while enough of that role are in town to work it, plus their tools' field_mult.
## Townsfolk who lent a hand there the day before add their extra food (FolkAI.assisted_food).
func food_grown_daily() -> int:
	var total := 0
	for type: String in content.buildings:
		var def: Dictionary = content.buildings[type]
		var each := int(def.get("daily", {}).get("food", 0))
		if each <= 0:
			continue
		var count := world.count_buildings(type)
		var worked: Dictionary = def.get("worked_by", {})
		if not worked.is_empty():
			count = mini(count, count_role(worked["role"]) / int(worked["per"]))
			each = roundi(each * (1.0 + tool_bonus(worked["role"], "field_mult")))
		total += count * each
	# What helpers earned at food buildings today.
	for i in world.buildings.size():
		total += world.folk_ai.assisted_food(world.buildings[i])
	return total


## Food eaten at each dawn. If there isn't enough, someone leaves, and none of their role join that dawn.
func daily_upkeep() -> void:
	var grown := food_grown_daily()
	if grown > 0:
		stock["food"] = int(stock["food"]) + grown
		record.note_count("food_grown", grown)
	var need := food_needed_today()
	if int(stock["food"]) >= need:
		stock["food"] = int(stock["food"]) - need
		people.serve_hearty_meals(need)
		return
	people.serve_hearty_meals(-1)
	stock["food"] = 0
	people.hungry_today = true
	if not world.folk.is_empty():
		var leaver: Unit = world.folk[SeededRng.stream(run_seed, "hunger", round_number * 10 + world.day_index()).randi_range(0, world.folk.size() - 1)]
		world.folk.erase(leaver)
		world.night_report["left"].append(leaver.display_name)
		record.note_count("left_hungry", 1)
		tell("Hunger: a %s walks away into the wilds." % leaver.display_name.to_lower())
		if content.balance.get("hunger_turns_folk_away", false):
			hunger_turned_away = leaver.type_id


func fuel_needed_tonight() -> int:
	var need := content.num("fuel_per_night_base") + population() * content.num("fuel_per_person_per_night") \
		+ world.folk_ai.folk_sum("night_fuel")
	for type: String in content.buildings:
		need += world.count_buildings(type) * float(content.buildings[type].get("fuel", 0.0))
	return maxi(0, int(ceil(need * (1.0 + mod("fuel_mult")) - mod("fuel_saving"))))


## Gatherable goods, most needed first (shortest against two days of need).
func needed_resources() -> Array[String]:
	var wants := resource_wants()
	var gaps := {}
	for r: String in wants:
		gaps[r] = (wants[r] - float(stock[r])) / maxf(wants[r], 1.0)
	var out: Array[String] = []
	out.assign(wants.keys())
	out.sort_custom(func(a: String, b: String) -> bool: return gaps[a] > gaps[b] or (gaps[a] == gaps[b] and a < b))
	return out


## Gatherable good -> how much the town wants in store (two days of need, plus what its buildings eat).
func resource_wants() -> Dictionary:
	var wants := {
		"food": population() * content.num("food_per_person_per_day") * 2.0,
		"fuel": fuel_needed_tonight() * 2.0,
		"wood": 12.0,
		"stone": 6.0,
	}
	# Knappers need flint, and the smoke hut eats food and fuel.
	if world.count_buildings("knapper") > 0:
		wants["flint"] = 6.0 * world.count_buildings("knapper")
	if world.count_buildings("smoke_hut") > 0:
		wants["food"] += 4.0
		wants["fuel"] += 2.0
	# The smelter wants copper and cassiterite, and burns fuel.
	if world.count_buildings("smelter") > 0:
		wants["copper"] = 8.0
		wants["cassiterite"] = 4.0
		wants["fuel"] += 3.0
	# The charcoal pit eats wood when fuel runs low.
	if world.count_buildings("charcoal_pit") > 0:
		wants["wood"] += 3.0 * world.count_buildings("charcoal_pit")
	# The charcoal burner eats wood, and the bloomery wants bog iron.
	if world.count_buildings("charcoal_burner") > 0:
		wants["wood"] += 6.0 * world.count_buildings("charcoal_burner")
	if world.count_buildings("bloomery") > 0:
		wants["bog_iron"] = 8.0
	return wants


## Files the night's report in the round record and keeps it for the UI.
func _close_night() -> void:
	var report := world.night_report.duplicate(true)
	report["night"] = world.day_index() + (0 if world.pause == World.Pause.DAWN else 1)
	report["hearth_damage"] = roundi(float(report["hearth_damage"]))
	last_night = report
	record.note_night(report)
	world.reset_night_report()


func _finish_round() -> void:
	world.pedlar.close()
	people.bury_heroes()
	people.update_moods()
	_close_night()
	world.release()
	var stats := world.wave_stats
	record.note_value("battle", {
		"seconds": snappedf(float(stats["seconds"]), 0.1),
		"keep_hp_after": roundi(world.hearth_hp),
		"keep_damage": roundi(float(stats["keep_damage"])),
		"bounty_paid": 0,
		"bounty_refunded": 0,
		"hero_deaths": stats["hero_deaths"].duplicate(),
		"retreats": int(stats["retreats"]),
	})
	record.note_value("deaths", world.deaths.duplicate())
	for hero in heroes:
		people.level_up(hero)
	people.spend_bloodsworn()
	if world.hearth_hp <= 0.0:
		_lose()
		return
	if world.deaths.is_empty() and has_effect("hearth_per_safe_round"):
		bonus_hearth_hp += mod("hearth_per_safe_round")
		world.hearth_hp += mod("hearth_per_safe_round")
		relic_fired("hearth_per_safe_round")
		tell("Nobody died this round: the ancestors' bones lend the hearth strength.")
	if round_number >= content.int_num("rounds_to_win"):
		phase = Phase.WON
		tell("The people endured all %d rounds!" % round_number)
		record.end_round()
		return
	people.heal_between_rounds()
	people.heroes_sell_finds()
	relic_offer = _roll_relic_offer()
	record.note_value("relic_offer", relic_offer.duplicate())
	if not spoils.is_empty():
		var noted := spoils.duplicate()
		noted["taken"] = false
		record.note_value("spoils", noted)
	phase = Phase.RELIC


func _lose() -> void:
	if world.pause == World.Pause.HEARTH_LOST:
		_close_night()
	phase = Phase.LOST
	world.pedlar.close()
	people.bury_heroes()
	world.release()
	if world.hearth_hp <= 0.0:
		tell("The hearth is trampled and goes dark in round %d." % round_number)
	else:
		tell("No one is left to tend the fire in round %d." % round_number)
	record.note_value("deaths", world.deaths.duplicate())
	record.end_round()


## Takes a relic from the offer ("" skips), then starts the next round.
func choose_relic(relic_id: String) -> void:
	assert(phase == Phase.RELIC)
	if relic_id != "" and relic_id == spoils.get("id", ""):
		_take_spoils()
	elif relic_id != "" and relic_id in relic_offer:
		_gain_relic(relic_id)
		tell("Relic taken: %s." % content.relics[relic_id]["name"])
		# Broken Crown, Starfall Idol: more relics at once, drawn from the ordinary ones.
		var gifts := int(content.relics[relic_id]["effects"].get("gain_relics", 0))
		if gifts > 0:
			var rng := SeededRng.stream(run_seed, "relic_gifts", round_number)
			var pool := _relic_pool(false)
			var gifted: Array[String] = []
			for i in gifts:
				if pool.is_empty():
					break
				var gift: String = rng.pick(pool)
				pool.erase(gift)
				_gain_relic(gift)
				gifted.append(gift)
				tell("%s brings %s." % [content.relics[relic_id]["name"], content.relics[gift]["name"]])
			record.note_value("relic_gifts", gifted)
	record.note_value("relic_pick", relic_id)
	if not spoils.is_empty():
		var noted := spoils.duplicate()
		noted["taken"] = relic_id == spoils["id"]
		record.note_value("spoils", noted)
	record.end_round()
	relic_offer = []
	spoils = {}
	round_number += 1
	var earned := income()
	stock["shells"] = int(stock["shells"]) + earned
	tell("Round %d. Traders leave %d shells." % [round_number, earned])
	if has_effect("interest"):
		var interest := mini(int(mod("interest_cap")), int(int(stock["shells"]) * mod("interest")))
		if interest > 0:
			stock["shells"] = int(stock["shells"]) + interest
			relic_fired("interest", interest)
			tell("Shells lent out come back with %d more." % interest)
	world.earth.shift()
	if has_effect("earth_turns"):
		relic_fired("earth_turns")
	_enter_build()
	if not world.earth.last.is_empty():
		record.note_value("shift", world.earth.last.duplicate(true))
		var ground := world.wave_sides.map(func(a: float) -> String: return String(world.earth.kind_def(world.earth.crossing(a)).get("name", "")))
		if not ground.has("") and not has_effect("still_ring"):
			tell("The earth turns. This round the attack crosses the %s." % " and the ".join(ground))


func _enter_build() -> void:
	phase = Phase.BUILD
	next_wave = waves.plan(round_number)
	camp_joined = world.enemy_ai.make_camp(held_back)
	if wave_eased > 0:
		tell("Scouts say the warband holds back %d of its number: your camp looks too weak to be worth them all." % wave_eased)
	if camp_joined > 0:
		tell("%d of them make a war camp out in the wilds. Gatherers can't work near it, and next round they march with the attack unless heroes break the camp first." % camp_joined)
	var due := waves.camp_due().size()
	if due > 0:
		tell("The war camp's %d raider%s march with this round's attack unless heroes break the camp first." % [due, "" if due == 1 else "s"])
	world.roll_wave_sides()
	pedlar = ""
	pedlar_offer = world.pedlar.roll_offer() if world.pedlar.is_pedlar_round(round_number) else ([] as Array[Dictionary])
	pedlar_settled = pedlar_offer.is_empty()
	caravan.lay_out()
	hand.deal()
	record.begin_round()
	for effect: String in _effects_between_rounds:
		relic_fired(effect, int(_effects_between_rounds[effect]))
	_effects_between_rounds = {}


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


## The whole run so far as plain data (see RunRecord.to_record).
func to_record() -> Dictionary:
	return record.to_record()


## Breaks the run <-> world and run <-> part reference loops so a finished run can be freed.
func dispose() -> void:
	world.dispose()
	people.run = null
	hand.run = null
	caravan.run = null
	waves.run = null
	record.run = null


func describe(hero: Unit) -> String:
	return "%s the %s %s" % [hero.display_name, content.traits[hero.trait_id]["name"].to_lower(),
		content.hero_classes[hero.type_id]["name"].to_lower()]


func new_id() -> int:
	_next_id += 1
	return _next_id


## The last id handed out (for placeholder names).
func peek_id() -> int:
	return _next_id


func tell(line: String) -> void:
	story.append(line)


## Owns a relic and applies what happens the moment it is taken (a free hero, a stronger hearth, warriors' stats).
func _gain_relic(relic_id: String) -> void:
	var before_max := hearth_max_hp()
	relics.append(relic_id)
	relic_acquired_round[relic_id] = round_number + 1
	var effects: Dictionary = content.relics[relic_id]["effects"]
	world.hearth_hp = clampf(world.hearth_hp + hearth_max_hp() - before_max, 1.0, hearth_max_hp())
	for i in int(effects.get("free_hero", 0)):
		var hero := people.make_hero()
		people.add_hero(hero)
		tell("%s follows the wanderer's fire to your camp." % describe(hero))
	for u in world.folk:
		world.folk_ai.apply_folk_stats(u)
	for h in heroes:
		world.hero_ai.apply_hero_stats(h)


## Whether this round's relic offer is a pact round (see pact_rounds in data/balance.json).
func is_pact_round() -> bool:
	return content.balance.get("pact_rounds", []).any(func(r: float) -> bool: return int(r) == round_number)


## Relics not yet owned that can be offered now: pacts or the rest, in a fixed order.
func _relic_pool(pacts: bool) -> Array:
	var pool: Array = content.relics.keys().filter(func(id: String) -> bool:
		return not relics.has(id) and content.has_tag("relic", id, "pact") == pacts and not content.has_tag("relic", id, "spoils") \
			and int(content.relics[id].get("from_round", 0)) <= round_number)
	pool.sort()
	return pool


## How likely a relic is to be drawn this round, by its rarity.
func _relic_odds(id: String) -> float:
	return content.rarity_odds(content.rarity_of("relic", id), round_number)


## On pact rounds the offer is pacts, topped up from the rest if too few are left. Rarer relics are drawn less often.
func _roll_relic_offer() -> Array[String]:
	var rng := SeededRng.stream(run_seed, "relics", round_number)
	var choices := maxi(1, content.int_num("relic_choices") + int(mod("relic_choices")))
	glory = not outmatched and content.int_num("glory_relic_choices") > 0
	if glory:
		choices += content.int_num("glory_relic_choices")
		tell("Glory: the warband came at full strength and your people held. One more relic to choose from.")
		record.note_value("glory", true)
	var pool := _relic_pool(is_pact_round())
	var offer: Array[String] = []
	while offer.size() < choices and not pool.is_empty():
		var pick: String = rng.pick_by(pool, _relic_odds)
		pool.erase(pick)
		offer.append(pick)
	if offer.size() < choices and is_pact_round():
		pool = _relic_pool(false)
		while offer.size() < choices and not pool.is_empty():
			var pick: String = rng.pick_by(pool, _relic_odds)
			pool.erase(pick)
			offer.append(pick)
	spoils = _roll_spoils()
	if not spoils.is_empty():
		offer.append(spoils["id"])
	return offer


## The spoils of this round's attack: a kind (an enemy tag some spoils are of) drawn weighted by how many of that
## kind came, then one of its spoils not already kept. {} when nothing in the attack has spoils.
func _roll_spoils() -> Dictionary:
	var rng := SeededRng.stream(run_seed, "spoils", round_number)
	var by_kind := {}
	for id: String in content.relics:
		if content.has_tag("relic", id, "spoils") and not relics.has(id):
			var kind: String = content.relics[id]["spoils_of"]
			if not by_kind.has(kind):
				by_kind[kind] = []
			by_kind[kind].append(id)
	var kinds: Array = by_kind.keys()
	kinds.sort()
	var counts := {}
	var total := 0
	for kind: String in kinds:
		var n := next_wave.filter(func(e: String) -> bool: return content.has_tag("enemy", e, kind)).size()
		if n > 0:
			counts[kind] = n
			total += n
	if total == 0:
		return {}
	var roll := rng.randi_range(1, total)
	for kind: String in counts:
		roll -= int(counts[kind])
		if roll <= 0:
			by_kind[kind].sort()
			return {"id": rng.pick(by_kind[kind]), "kind": kind, "foes": counts[kind]}
	return {}


## What taking this round's spoils brings at once: goods (good -> amount) and folk (role -> how many).
func spoils_now() -> Dictionary:
	var now: Dictionary = content.relics[spoils["id"]].get("take_now", {})
	var goods := {}
	var per_foe: Dictionary = now.get("per_foe", {})
	for good: String in per_foe:
		goods[good] = int(ceil(float(per_foe[good]) * int(spoils["foes"])))
	return {"goods": goods, "folk": now.get("folk", {})}


func _take_spoils() -> void:
	var id: String = spoils["id"]
	var now := spoils_now()
	for good: String in now["goods"]:
		stock[good] = int(stock.get(good, 0)) + int(now["goods"][good])
	for role: String in now["folk"]:
		for i in int(now["folk"][role]):
			world.folk_ai.add_folk(role)
	spoils["goods"] = now["goods"]
	# Spoils with lasting effects are kept like relics; the rest are only what they bring now.
	if not content.relics[id]["effects"].is_empty():
		_gain_relic(id)
	tell("Spoils taken: %s." % content.relics[id]["name"])
