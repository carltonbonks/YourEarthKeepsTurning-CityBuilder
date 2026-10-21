class_name People
extends RefCounted
## Who is in the town and who joins it (`run.people`): the dawn cards, promotions, making and
## adding heroes, hero mood (and heroes walking away), levelling, between-round healing and
## heroes selling their finds. The lists of people themselves live on RunState (`heroes`,
## `fallen`, `departed`) and World (`folk`).

var run: RunState
## True once someone has gone hungry since the last dawn's mood update.
var hungry_today := false
## The last pedlar's carousel, in pick order: {hero, item (described), equipped}; [] when none came this round.
var last_carousel: Array = []
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
	var promote := _promotion_card(rng)
	var venture := _venture_card()
	var slots := maxi(1, content.int_num("pick_choices") + int(run.mod("pick_bonus"))) - (0 if promote.is_empty() else 1) \
		- (0 if venture.is_empty() else 1)
	while run.pick_offer.size() < slots and not pool.is_empty():
		var card: Dictionary = rng.pick(pool)
		pool.erase(card)
		run.pick_offer.append(card)
	if not promote.is_empty():
		run.pick_offer.append(promote)
	if not venture.is_empty():
		run.pick_offer.append(venture)
	run.picks_left = 1 + int(run.mod("extra_picks"))
	run.phase = RunState.Phase.PICK


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
			return card["roles"].size()
	return 1


func card_label(card: Dictionary) -> String:
	if card["kind"] == "promote":
		return "promote:" + card["role"]
	if card["kind"] == "venture":
		return "venture:" + card["venture"]
	if card["kind"] == "family":
		return "family"
	return "hero:" + card["hero"].type_id if card["kind"] == "hero" else card["role"]


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
func venture_terms(id: String) -> Dictionary:
	var v: Dictionary = run.content.ventures[id]
	var safety := int(run.mod("venture_safety"))
	var grow := 1.0 + run.content.num("venture_growth_per_round") * (run.round_number - 1)
	grow *= 1.0 + run.mod("venture_bonus")
	var goods := {}
	for good: String in v["gain"]:
		goods[good] = int(ceil(float(v["gain"][good]) * grow))
	return {"send": int(v["send"]), "lose": [maxi(0, int(v["lose"][0]) - safety), maxi(0, int(v["lose"][1]) - safety)], "goods": goods}


## Sends the tribespeople out: some never come back (chosen at random), the goods come home.
## Returns {lost, goods} for the record.
func go_venturing(card: Dictionary) -> Dictionary:
	var id: String = card["venture"]
	var terms := venture_terms(id)
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
	return {"lost": lost, "goods": terms["goods"]}


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
		run.tell("%s, a craftsperson since %s, becomes master of the %s (%s)." % [u.display_name, since,
			run.content.buildings[u.master_of]["name"].to_lower(), t["name"]])
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


## The pedlar's carousel (TFT): every carousel_every-th round a pedlar lays out one item per living hero and a few more.
## Heroes pick one each, the weakest first (lowest level, then fewest shells): the item that most improves on what
## they wear by their personality, or the most valuable one to sell when none does. Picks are kept on last_carousel.
func pedlar_carousel() -> void:
	var content := run.content
	last_carousel = []
	var every := content.int_num("carousel_every")
	var heroes := run.living_heroes()
	if every <= 0 or run.round_number % every != 0 or heroes.is_empty():
		return
	var rng := SeededRng.stream(run.run_seed, "carousel", run.round_number)
	var wares: Array[Dictionary] = []
	for i in heroes.size() + content.int_num("carousel_extra"):
		wares.append(Loot.roll(content, rng, run.round_number + content.int_num("carousel_rounds_ahead"), run.age))
	heroes.sort_custom(func(a: Unit, b: Unit) -> bool:
		return a.level < b.level or (a.level == b.level and (a.gold < b.gold or (a.gold == b.gold and a.id < b.id))))
	run.tell("A pedlar spreads out %d wares, and the heroes take their pick, %s first." % [wares.size(), heroes[0].display_name])
	var picks: Array = []
	for hero in heroes:
		var best := _carousel_choice(hero, wares)
		var item: Dictionary = wares[best]
		wares.remove_at(best)
		var slot := Loot.slot(content, item)
		run.world.hero_ai.give_item(hero, item)
		var equipped: bool = hero.items.get(slot, {}) == item
		picks.append({"hero": hero.display_name, "level": hero.level, "base": item["base"], "tier": item["tier"],
			"affixes": item["affixes"].duplicate(), "equipped": equipped})
		last_carousel.append({"hero": hero.display_name, "item": Loot.describe(content, item), "equipped": equipped})
	run.record.note_value("carousel", picks)
	run.record.note_value("carousel_left", wares.size())


## Which ware a hero takes: the biggest gain over the item in that slot, by their likes; else the most valuable.
func _carousel_choice(hero: Unit, wares: Array[Dictionary]) -> int:
	var content := run.content
	var likes: Dictionary = content.traits[hero.trait_id].get("likes", {})
	var best := -1
	var best_gain := 0.0
	for i in wares.size():
		var current: Dictionary = hero.items.get(Loot.slot(content, wares[i]), {})
		var gain := Loot.score(content, wares[i], likes) - (Loot.score(content, current, likes) if not current.is_empty() else 0.0)
		if gain > best_gain:
			best_gain = gain
			best = i
	if best >= 0:
		return best
	best = 0
	for i in wares.size():
		if Loot.value(content, wares[i]) > Loot.value(content, wares[best]):
			best = i
	return best


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
