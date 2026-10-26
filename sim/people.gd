class_name People
extends RefCounted
## Who is in the town and who joins it (`run.people`): the dawn cards, promotions, making and
## adding heroes, hero mood (and heroes walking away), levelling, between-round healing and
## heroes selling their finds. The lists of people themselves live on RunState (`heroes`,
## `fallen`, `departed`) and World (`folk`).

var run: RunState
## True once someone has gone hungry since the last dawn's mood update.
var hungry_today := false
var _hero_rng: SeededRng


func _init(run_state: RunState) -> void:
	run = run_state
	_hero_rng = SeededRng.stream(run.run_seed, "heroes")


# --- Dawn cards --------------------------------------------------------------

## Deals the dawn cards into run.pick_offer and waits for the player's pick.
func offer_picks() -> void:
	var content := run.content
	var world := run.world
	var rng := SeededRng.stream(run.run_seed, "picks", run.round_number * 10 + world.day_index())
	var pool: Array[Dictionary] = []
	var roles := content.townsfolk.keys()
	roles.sort()
	for role: String in roles:
		if role == run.hunger_turned_away:
			continue
		var leanings := leanings_open(role)
		if leanings.is_empty():
			pool.append({"kind": "folk", "role": role, "cost": 0})
		# A leaning the town's traditions favour is always among those dealt (the first one, if several).
		var favoured := run.tradition_leanings().filter(func(l: String) -> bool: return leanings.has(l))
		for i in mini(leanings.size(), int(content.townsfolk[role].get("leaning_cards", 1))):
			var leaning: String = favoured[0] if i == 0 and not favoured.is_empty() else rng.pick(leanings)
			leanings.erase(leaning)
			pool.append({"kind": "folk", "role": role, "cost": 0, "leaning": leaning})
	if world.hero_ai.count_lodgings() > 0:
		var hero := make_hero(true)
		pool.append({"kind": "hero", "role": "hero", "cost": hero_card_cost(hero.type_id), "hero": hero})
	if content.age_reached(run.age, content.balance.get("family_cards_from", "")) and content.balance.has("family_roles") \
			and not content.balance["family_roles"].has(run.hunger_turned_away):
		pool.append({"kind": "family", "role": "family", "cost": 0, "roles": content.balance["family_roles"].duplicate()})
	run.pick_offer = []
	# A first run's first dawn (RunState.gentle) offers a few tribespeople and nothing else.
	if run.gentle and run.round_number == 1 and world.day_index() == 0:
		pool = pool.filter(func(c: Dictionary) -> bool: return c["role"] == "tribesperson")
		var roll_first := SeededRng.stream(run.run_seed, "card_roll", run.round_number * 10)
		while run.pick_offer.size() < content.int_num("gentle_first_dawn") and not pool.is_empty():
			var first: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
			_roll_dawn_card(first, roll_first)
			run.pick_offer.append(first)
		run.picks_left = 1
		run.phase = RunState.Phase.PICK
		return
	_kin_join()
	var promote := _promotion_card(rng)
	var venture := _venture_card()
	# A hollow-eyed seer (data/card_mods.json pick_bonus) adds a card while they live.
	var seers := int(world.folk_ai.folk_sum("pick_bonus"))
	if seers > 0:
		run.record.note_count("card_mods_fired", seers, "hollow_seer")
	var slots := maxi(1, content.int_num("pick_choices") + int(run.mod("pick_bonus")) + seers) - (0 if promote.is_empty() else 1) \
		- (0 if venture.is_empty() else 1)
	# Each card dealt rolls its own rarity (CardRoll), on a stream of its own so the cards dealt stay the same.
	var roll_rng := SeededRng.stream(run.run_seed, "card_roll", run.round_number * 10 + world.day_index())
	# Rarer cards are drawn less often, less so as the run goes on (Content.rarity_odds).
	while run.pick_offer.size() < slots and not pool.is_empty():
		var card: Dictionary = rng.pick_by(pool, func(c: Dictionary) -> float:
			return content.rarity_odds(card_rarity(c), run.round_number) * reeve_tilt(c))
		pool.erase(card)
		_roll_dawn_card(card, roll_rng)
		run.pick_offer.append(card)
	if not promote.is_empty():
		run.pick_offer.append(promote)
	if not venture.is_empty():
		_roll_dawn_card(venture, roll_rng)
		run.pick_offer.append(venture)
	run.picks_left = 1 + int(run.mod("extra_picks"))
	run.phase = RunState.Phase.PICK


# --- Townsfolk at work (Yusuf, 2026-10-26) -----------------------------------------------------------------

## How a role spent its time: {"kinds": {kind: seconds}, "total": seconds, "from": "this" or "last" round, or ""}.
## This round once it has busy_min_seconds counted, else last round's record (always last round's while building).
func busy_of(role: String) -> Dictionary:
	var now: Dictionary = run.world.folk_ai.role_time.get(role, {})
	var total := _sum(now)
	if total >= run.content.num("busy_min_seconds") and run.phase != RunState.Phase.BUILD:
		return {"kinds": now.duplicate(), "total": total, "from": "this"}
	if not run.record.rounds.is_empty():
		var last: Dictionary = run.record.rounds[-1].get("folk_time", {}).get(role, {})
		if _sum(last) >= run.content.num("busy_min_seconds"):
			return {"kinds": last.duplicate(), "total": _sum(last), "from": "last"}
	return {"kinds": {}, "total": 0.0, "from": ""}


static func _sum(kinds: Dictionary) -> float:
	var total := 0.0
	for k: String in kinds:
		total += float(kinds[k])
	return total


## The dawn card word for a role: "stretched" (another would earn their keep), "busy", "slack" (another mostly adds
## upkeep), or "" with nothing counted yet. From busy_words in data/townsfolk.json.
func busy_word(role: String) -> String:
	var rule: Dictionary = run.content.townsfolk.get(role, {}).get("busy_words", {})
	var b := busy_of(role)
	if rule.is_empty() or float(b["total"]) <= 0.0:
		return ""
	var share := busy_share(role, b)
	if rule.has("stretched_below"):
		return "stretched" if share < float(rule["stretched_below"]) else ("slack" if share > float(rule["slack_above"]) else "busy")
	return "stretched" if share > float(rule["stretched_above"]) else ("slack" if share < float(rule["slack_below"]) else "busy")


## The share of a role's counted time in the kinds its busy word reads (idle for workers, fighting and healing for warriors).
func busy_share(role: String, b := {}) -> float:
	if b.is_empty():
		b = busy_of(role)
	if float(b["total"]) <= 0.0:
		return 0.0
	var part := 0.0
	for kind: String in run.content.townsfolk[role].get("busy_words", {}).get("kinds", []):
		part += float(b["kinds"].get(kind, 0.0))
	return part / float(b["total"])


## The standing building that keeps the town's tally ("reckons" in data/buildings.json: the Reeve's hut), its
## numbers or {}. It shows the Your people panel and tilts the dawn picks.
func reckoning() -> Dictionary:
	for b in run.world.buildings:
		var def: Dictionary = run.content.buildings[b["type"]]
		if def.has("reckons") and float(b["work_left"]) <= 0.0:
			return def["reckons"]
	return {}


## With a Reeve's hut, a townsfolk card's draw weight: Stretched roles come up more often, Slack ones less.
func reeve_tilt(card: Dictionary) -> float:
	if card["kind"] != "folk":
		return 1.0
	var tilt := float(reckoning().get("dawn_tilt", 0.0))
	if tilt <= 0.0:
		return 1.0
	match busy_word(card["role"]):
		"stretched":
			return 1.0 + tilt
		"slack":
			return 1.0 / (1.0 + tilt)
	return 1.0


## Rolls a dawn card's own rarity and modifiers (CardRoll); a hero card's take hold of its hero at once, so the
## card shows the hero as they will arrive. Promotions don't roll.
func _roll_dawn_card(card: Dictionary, rng: SeededRng) -> void:
	var content := run.content
	match card["kind"]:
		"folk":
			CardRoll.roll_folk(content, rng, card, run.round_number)
		"hero":
			var hero: Unit = card["hero"]
			CardRoll.roll_card(content, rng, card, "hero", {"weapon": hero.items.has("weapon")}, run.round_number)
			_shape_hero(card, rng)
		"family", "venture":
			CardRoll.roll_card(content, rng, card, card["kind"], {}, run.round_number)


## A rolled hero card's modifiers: levels, a hound, a better weapon, a price; the orange roll is a legend, a few levels
## up and carrying a mythic item, costing more.
func _shape_hero(card: Dictionary, rng: SeededRng) -> void:
	var content := run.content
	if not card.has("roll"):
		return
	var hero: Unit = card["hero"]
	hero.level += int(CardRoll.card_sum(content, card, "levels"))
	if CardRoll.card_sum(content, card, "hound") > 0.0:
		hero.hound = true
	if hero.items.has("weapon"):
		hero.items["weapon"]["tier"] = int(hero.items["weapon"]["tier"]) + int(CardRoll.card_sum(content, card, "weapon_tiers"))
	card["cost"] = maxi(0, int(card["cost"]) + int(CardRoll.card_sum(content, card, "cost_shells")))
	if CardRoll.card_has(content, card, "legend"):
		var item := Loot.mythic(content, rng, run.round_number, run.age, str(content.traits[hero.trait_id].get("prefers", "")))
		if not item.is_empty():
			hero.items[Loot.slot(content, item)] = item
		hero.level += content.int_num("legend_levels")
		card["legend"] = true
		card["cost"] = int(card["cost"]) + content.int_num("legend_cost")
	run.world.hero_ai.apply_hero_stats(hero)
	hero.hp = hero.max_hp


## The leanings a role's dawn cards can come with in the town's age, sorted.
func leanings_open(role: String) -> Array[String]:
	var out: Array[String] = []
	var all: Dictionary = run.content.townsfolk[role].get("leanings", {})
	for id: String in all:
		if run.content.age_reached(run.age, str(all[id].get("age", ""))):
			out.append(id)
	out.sort()
	return out


## What a hero card of this class costs (a class may set its own card_cost).
func hero_card_cost(class_id: String) -> int:
	return int(run.content.hero_classes[class_id].get("card_cost", run.content.int_num("hero_card_cost")))


## How many people a dawn card brings into town (0 for a promotion or a venture).
func card_people(card: Dictionary) -> int:
	match card["kind"]:
		"promote", "venture":
			return 0
		"family":
			return card["roles"].size() + CardRoll.extra_people(run.content, card)
	return 1 + CardRoll.extra_people(run.content, card)


## A dawn card's rarity (data/rarity.json), from the data of whatever it offers.
func card_rarity(card: Dictionary) -> String:
	var content := run.content
	match card["kind"]:
		"hero":
			return content.rarity_of("hero", card["hero"].type_id)
		"promote":
			return str(content.promotions[card["role"]].get("rarity", "white"))
		"venture":
			return str(content.ventures[card["venture"]].get("rarity", "white"))
		"family":
			return str(content.balance.get("family_rarity", "white"))
	return content.rarity_of("townsfolk", card["role"])


func card_label(card: Dictionary) -> String:
	if card["kind"] == "promote":
		return "promote:" + card["role"]
	if card["kind"] == "venture":
		return "venture:" + card["venture"]
	if card["kind"] == "family":
		return "family"
	return "hero:" + card["hero"].type_id if card["kind"] == "hero" else card["role"]


# --- Rolled townsfolk (data/card_mods.json) -----------------------------------

## A family card's people move in, with what its roll brings: more of them, marks, goods, a modifier on everyone.
## Returns how many arrived.
func settle_family(card: Dictionary) -> int:
	var content := run.content
	var roles: Array = card["roles"].duplicate()
	var extra := CardRoll.card_goods(content, card, "extra_folk")
	var keys := extra.keys()
	keys.sort()
	for role: String in keys:
		for i in int(extra[role]):
			roles.append(role)
	var marks := int(CardRoll.card_sum(content, card, "mark_members"))
	var boon := ""
	for id: String in card.get("boons", []):
		boon = str(content.card_mods[id].get("member_boon", boon))
	var rng := SeededRng.stream(run.run_seed, "family_marks", run.round_number * 10 + run.world.day_index())
	for role: String in roles:
		var u := run.world.folk_ai.add_folk(role)
		if marks > 0:
			u.mark = CardRoll._pick_mark(content, rng, role)
			marks -= 1
		if boon != "":
			u.boons.append(boon)
		if u.mark != "" or boon != "":
			run.world.folk_ai.apply_folk_stats(u)
			u.hp = u.max_hp
	var goods := CardRoll.card_goods(content, card, "goods")
	for good: String in goods:
		run.stock[good] = int(run.stock.get(good, 0)) + int(goods[good])
	return roles.size()

## A mother of many (kin_chance) may bring a plain tribesperson in free at dawn, while there is room.
func _kin_join() -> void:
	var rng := SeededRng.stream(run.run_seed, "kin", run.round_number * 10 + run.world.day_index())
	for unit in run.world.folk.duplicate():
		var chance := run.world.folk_ai.unit_mod(unit, "kin_chance")
		if chance <= 0.0 or not unit.alive or run.population() >= run.housing() or rng.randf() >= chance:
			continue
		run.world.folk_ai.add_folk("tribesperson")
		run.record.note_count("card_mods_fired", 1, "many_mother")
		run.tell("Kin of the mother of many walk in from the wilds: a tribesperson joins.")


## The bloodsworn (doom_rounds) burn out at the end of their last round.
func spend_bloodsworn() -> void:
	for unit in run.world.folk.duplicate():
		var rounds := int(run.world.folk_ai.unit_mod(unit, "doom_rounds"))
		if rounds > 0 and run.round_number - unit.joined_round + 1 >= rounds:
			run.world.folk.erase(unit)
			run.record.note_count("card_mods_fired", 1, "bloodsworn")
			run.tell("A bloodsworn %s has given all they had and is laid to rest." % run.content.townsfolk[unit.type_id]["name"].to_lower())


# --- Ventures ---------------------------------------------------------------

## Now and then a venture card: send tribespeople out for goods, some never come back (data/ventures.json).
## {} when none comes up this dawn or the town can't spare enough tribespeople.
func _venture_card() -> Dictionary:
	var content := run.content
	var rng := SeededRng.stream(run.run_seed, "venture", run.round_number * 10 + run.world.day_index())
	if content.ventures.is_empty() or rng.randf() >= content.num("venture_chance"):
		return {}
	var spare := run.count_role("tribesperson") - content.int_num("venture_keep_home")
	var open: Array = content.ventures.keys().filter(func(id: String) -> bool:
		return content.age_reached(run.age, str(content.ventures[id].get("age", ""))) and int(content.ventures[id]["send"]) <= spare)
	if open.is_empty():
		return {}
	open.sort()
	var id: String = rng.pick(open)
	return {"kind": "venture", "role": "venture", "cost": 0, "venture": id}


## What a venture risks and brings, with relics counted: send, lose (lowest and highest) and goods.
## A rolled venture card (card) adds its modifiers: more goods, fewer lost, or nobody back (data/card_mods.json).
func venture_terms(id: String, card := {}) -> Dictionary:
	var v: Dictionary = run.content.ventures[id]
	var safety := int(run.mod("venture_safety")) + int(CardRoll.card_sum(run.content, card, "safety"))
	var grow := 1.0 + run.content.num("venture_growth_per_round") * (run.round_number - 1)
	grow *= 1.0 + run.mod("venture_bonus") + CardRoll.card_sum(run.content, card, "gain_mult")
	if CardRoll.card_sum(run.content, card, "lose_all") > 0.0:
		return {"send": int(v["send"]), "lose": [int(v["send"]), int(v["send"])], "goods": _venture_goods(v, grow)}
	return {"send": int(v["send"]), "lose": [maxi(0, int(v["lose"][0]) - safety), maxi(0, int(v["lose"][1]) - safety)],
		"goods": _venture_goods(v, grow)}


func _venture_goods(v: Dictionary, grow: float) -> Dictionary:
	var goods := {}
	for good: String in v["gain"]:
		goods[good] = int(ceil(float(v["gain"][good]) * grow))
	return goods


## Sends the tribespeople out: some never come back (chosen at random), the goods come home.
## Returns {venture, send, lost, goods}.
func go_venturing(card: Dictionary) -> Dictionary:
	var id: String = card["venture"]
	var terms := venture_terms(id, card)
	var rng := SeededRng.stream(run.run_seed, "venture_lost", run.round_number * 10 + run.world.day_index())
	var lost := rng.randi_range(terms["lose"][0], terms["lose"][1])
	var tribe: Array = run.world.folk.filter(func(u: Unit) -> bool: return u.type_id == "tribesperson" and u.alive)
	for i in mini(lost, tribe.size()):
		var gone: Unit = tribe[rng.randi_range(0, tribe.size() - 1)]
		tribe.erase(gone)
		run.world.folk.erase(gone)
	for good: String in terms["goods"]:
		run.stock[good] = int(run.stock.get(good, 0)) + int(terms["goods"][good])
	for effect: String in ["venture_safety", "venture_bonus"]:
		if run.has_effect(effect):
			run.relic_fired(effect)
	var brought := ", ".join(terms["goods"].keys().map(func(g: String) -> String: return "%d %s" % [terms["goods"][g], g.replace("_", " ")]))
	var name: String = run.content.ventures[id]["name"]
	if lost == 0:
		run.tell("%s: all %d tribespeople come home, with %s." % [name, terms["send"], brought])
	else:
		run.tell("%s: %d of %d tribespeople never come home. The rest bring %s." % [name, lost, terms["send"], brought])
	return {"venture": id, "send": terms["send"], "lost": lost, "goods": terms["goods"]}


# --- Promotions -------------------------------------------------------------

## A Promote card for one townsperson who has earned it, or {} if nobody has.
## The outcome (name, class, trait) is rolled now so the card can show it.
func _promotion_card(rng: SeededRng) -> Dictionary:
	var rules := run.content.promotions
	var candidates: Array[Dictionary] = []
	for u in run.world.folk:
		if u.type_id == "warrior" and u.kills >= int(rules["warrior"]["kills"]) and run.world.hero_ai.count_lodgings() > 0:
			candidates.append({"kind": "promote", "role": "warrior", "cost": int(rules["warrior"]["cost"]), "unit": u})
		elif u.type_id == "craftsperson" and u.master_of == "":
			var best := ""
			var shops := u.made.keys()
			shops.sort()
			for shop: String in shops:
				if int(u.made[shop]) >= int(rules["craftsperson"]["made"]) and (best == "" or int(u.made[shop]) > int(u.made[best])):
					best = shop
			if best != "":
				candidates.append({"kind": "promote", "role": "craftsperson", "cost": int(rules["craftsperson"]["cost"]),
					"unit": u, "workshop": best})
	var knight: Dictionary = rules.get("champion", {})
	if not knight.is_empty() and _class_available(knight["becomes"]):
		for hero in run.living_heroes():
			if hero.type_id == "champion" and hero.level >= int(knight["level"]):
				candidates.append({"kind": "promote", "role": "champion", "cost": int(knight["cost"]), "hero": hero})
	if candidates.is_empty():
		return {}
	var card: Dictionary = rng.pick(candidates)
	if card["role"] == "champion":
		return card
	if card["role"] == "warrior":
		var hero := make_hero()
		hero.type_id = rules["warrior"]["becomes"]
		hero.level = int(rules["warrior"]["start_level"])
		run.world.hero_ai.apply_hero_stats(hero)
		hero.hp = hero.max_hp
		card["hero"] = hero
	else:
		var traits: Array = rules["craftsperson"]["traits"].keys()
		traits.sort()
		card["trait"] = rng.pick(traits)
		card["name"] = unused_name()
	return card


func promote(card: Dictionary) -> void:
	if card["role"] == "champion":
		_knight(card)
		return
	var u: Unit = card["unit"]
	var since := "round %d" % u.joined_round if u.joined_round > 1 else "the first fire"
	var entry := {"day": run.world.day_index() + 1, "role": card["role"], "joined_round": u.joined_round}
	if card["role"] == "warrior":
		var hero: Unit = card["hero"]
		hero.kills = u.kills
		run.world.folk.erase(u)
		add_hero(hero)
		run.tell("A warrior who has stood watch since %s and killed %d foes is raised up: %s." % [since, u.kills, run.describe(hero)])
		entry.merge({"name": hero.display_name, "became": hero.type_id, "trait": hero.trait_id, "kills": u.kills})
	else:
		u.display_name = card["name"]
		u.master_of = card["workshop"]
		u.craft_trait = card["trait"]
		var t: Dictionary = run.content.promotions["craftsperson"]["traits"][u.craft_trait]
		run.tell("%s, a craftsperson since %s, becomes master of the %s. %s: %s" % [u.display_name, since,
			run.content.buildings[u.master_of]["name"].to_lower(), t["name"], t["text"]])
		entry.merge({"name": u.display_name, "became": "master_" + u.master_of, "trait": u.craft_trait, "made": int(u.made[u.master_of])})
	run.record.note_list("promotions", entry)


## A champion of high enough level is knighted: same hero, new class.
func _knight(card: Dictionary) -> void:
	var hero: Unit = card["hero"]
	var was := run.describe(hero)
	hero.type_id = run.content.promotions["champion"]["becomes"]
	run.world.hero_ai.apply_hero_stats(hero)
	hero.hp = hero.max_hp
	run.tell("%s kneels in the guildhall and rises a %s." % [was, run.content.hero_classes[hero.type_id]["name"].to_lower()])
	run.record.note_list("promotions", {"day": run.world.day_index() + 1, "role": "champion", "name": hero.display_name,
		"became": hero.type_id, "trait": hero.trait_id, "level": hero.level, "kills": hero.kills})


# --- Heroes -----------------------------------------------------------------

## True if heroes of a class can turn up: a class with "needs" waits for that building.
func _class_available(class_id: String) -> bool:
	var needs: String = run.content.hero_classes[class_id].get("needs", "")
	return needs == "" or run.world.count_buildings(needs) > 0


## A new hero, not yet in the settlement (dawn cards show these).
## For dawn cards, heroes whose favourite lodging stands are likelier to turn up.
func make_hero(drawn_by_lodging := false) -> Unit:
	var content := run.content
	var hero := Unit.new()
	hero.id = run.new_id()
	hero.team = Unit.Team.HERO
	var class_ids := content.hero_classes.keys().filter(_class_available)
	class_ids.sort()
	var trait_ids := content.traits.keys()
	trait_ids.sort()
	hero.type_id = _hero_rng.pick(class_ids)
	if drawn_by_lodging:
		var weights := {}
		for id: String in trait_ids:
			var favourite: Array = content.traits[id].get("lodging", [])
			weights[id] = 1.0 + (content.num("lodging_draw_bonus") if not favourite.is_empty() and run.world.count_buildings(favourite[0]) > 0 else 0.0)
		hero.trait_id = _hero_rng.weighted(weights)
	else:
		hero.trait_id = _hero_rng.pick(trait_ids)
	hero.display_name = unused_name()
	hero.mood = content.num("mood_start")
	run.world.hero_ai.apply_hero_stats(hero)
	hero.hp = hero.max_hp
	return hero


func add_hero(hero: Unit) -> void:
	hero.pos = Vector2.from_angle(run.heroes.size() * 1.7 + 0.4) * 60.0
	run.world.hero_ai.apply_hero_stats(hero)
	run.heroes.append(hero)
	run.world.hero_ai.assign_lodgings()


func bury_heroes() -> void:
	for hero in run.heroes.duplicate():
		if not hero.alive:
			run.heroes.erase(hero)
			run.fallen.append(hero)


func unused_name() -> String:
	var taken := {}
	for h in run.heroes + run.fallen + run.departed:
		taken[h.display_name] = true
	for u in run.world.folk:
		taken[u.display_name] = true
	var free := run.content.hero_names.filter(func(n: String) -> bool: return not taken.has(n))
	if free.is_empty():
		return "Wanderer %d" % run.peek_id()
	return _hero_rng.pick(free)


## Moves each hero's mood by what happened since the last dawn, then lets the
## unhappiest walk away. Called at each dawn and at the end of each round.
func update_moods() -> void:
	var content := run.content
	var report := run.world.night_report
	var comrades := int(report.get("hero_deaths", 0))
	for hero in run.living_heroes():
		var changes := {}
		match hero.slept:
			"favourite":
				changes["slept in their favourite lodging"] = content.num("mood_slept_favourite")
			"other":
				changes["slept somewhere they don't like"] = content.num("mood_slept_other")
			"rough":
				changes["slept rough by the hearth"] = content.num("mood_slept_rough") \
					* (content.num("mood_proud_rough_mult") if content.unit_has_tag(hero, "proud") else 1.0)
		if hero.mood_events.has("bought"):
			changes["bought something they wanted"] = content.num("mood_bought")
		if int(hero.mood_events.get("prize", 0)) > 0:
			changes["won prizes"] = content.num("mood_prize")
		if comrades > 0 and not run.has_effect("mourning_share"):
			changes["lost comrades"] = content.num("mood_comrade_died") * comrades
		if content.unit_has_tag(hero, "proud") and hero.items.values().any(func(item: Dictionary) -> bool:
				return content.items["bases"][item["base"]].get("steel", false)):
			changes["wears steel"] = content.num("mood_proud_steel")
		if hungry_today:
			changes["went hungry"] = content.num("mood_hungry")
		if report.get("cold", false):
			changes["shivered through a cold night"] = content.num("mood_cold")
		var before := hero.mood
		for why: String in changes:
			hero.mood += float(changes[why])
		hero.mood = clampf(hero.mood, 0.0, 100.0)
		hero.slept = ""
		hero.mood_events = {}
		var worst := ""
		for why: String in changes:
			if float(changes[why]) < 0.0 and (worst == "" or float(changes[why]) < float(changes[worst])):
				worst = why
		if hero.mood <= content.num("mood_leave_at"):
			_hero_leaves(hero, worst)
		elif hero.mood <= content.num("mood_grumble_at") and hero.mood < before and worst != "":
			run.tell("%s grumbles: they %s. They may leave if this goes on." % [hero.display_name, worst])
	hungry_today = false


func _hero_leaves(hero: Unit, why: String) -> void:
	run.heroes.erase(hero)
	run.departed.append(hero)
	hero.target = null
	run.world.night_report["left"].append(hero.display_name)
	run.world.night_report["heroes_left"].append(hero.display_name)
	run.record.note_list("heroes_left", {"day": run.world.day_index() + 1, "hero": hero.display_name, "trait": hero.trait_id,
		"mood": roundi(hero.mood), "why": why})
	run.tell("%s has had enough%s and leaves town with their gear." % [run.describe(hero), " (%s)" % why if why != "" else ""])
	run.world.hero_ai.assign_lodgings()


func level_up(hero: Unit) -> void:
	var per_level := run.content.num("xp_per_level")
	while hero.xp >= per_level * hero.level:
		hero.xp -= per_level * hero.level
		hero.level += 1
		run.world.hero_ai.apply_hero_stats(hero)
		run.tell("%s reaches level %d." % [hero.display_name, hero.level])


func heal_between_rounds() -> void:
	var content := run.content
	var full := run.mod("full_heal") > 0.0
	for hero in run.heroes:
		hero.energy = content.num("hero_energy_max")
		hero.resting = false
		var heal := hero.max_hp if full else hero.max_hp * content.num("between_round_heal")
		hero.hp = minf(hero.max_hp, hero.hp + heal)
	for unit in run.world.folk:
		unit.hp = minf(unit.max_hp, unit.hp + unit.max_hp * content.num("between_round_heal"))


## Between rounds heroes sell the loot they carry (the settlement takes a cut).
## Gear and provisions are only bought at the market's stalls, by day (see World).
func heroes_sell_finds() -> void:
	var content := run.content
	var tax_rate := float(content.items["sell_tax"])
	var where := "at the market" if run.world.count_buildings("market") > 0 else "to passing traders"
	for hero in run.heroes:
		if hero.spares.is_empty():
			continue
		var total := 0
		var tax := 0
		for item in hero.spares:
			var v := Loot.value(content, item)
			var cut := roundi(v * tax_rate)
			total += v
			tax += cut
			run.record.note_list("sales", {"hero": hero.display_name, "base": item["base"], "tier": item["tier"],
				"affixes": item["affixes"].duplicate(), "value": v, "town_cut": cut})
		hero.gold += total - tax
		run.stock["shells"] = int(run.stock["shells"]) + tax
		run.tell("%s sells %d found item%s %s for %d shells; the settlement keeps %d." % [hero.display_name,
			hero.spares.size(), "" if hero.spares.size() == 1 else "s", where, total, tax])
		hero.spares.clear()


## Hearty meals at dawn, once everyone has eaten the town's daily need: each hero in turn eats hearty_food more
## while the store would still hold hearty_reserve_days of that need, and is well fed (more XP) until the next dawn.
## need < 0: the town went short, so nobody is well fed.
func serve_hearty_meals(need: int) -> void:
	var content := run.content
	var extra := content.int_num("hearty_food")
	var reserve := need * content.num("hearty_reserve_days")
	for hero in run.heroes:
		hero.well_fed = need >= 0 and hero.alive and int(run.stock["food"]) - extra >= reserve
		if hero.well_fed:
			run.stock["food"] = int(run.stock["food"]) - extra
			run.record.note_count("hearty_meals", 1)
