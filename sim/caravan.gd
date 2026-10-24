class_name Caravan
extends RefCounted
## The southern caravan's trade cards (`run.caravan`). Once its building stands, every build phase lays out a few
## deals drawn by rarity (data/rarity.json), leaning toward what the town wants: bulk lots, barters, services and
## the odd mythic find. The player takes any deal they can pay for, each once a round. Deals and their numbers are
## in data/trades.json; relics and traditions add deals (trade_deals), make rarer ones likelier (trade_rarity) and
## sweeten barters (barter_bonus).

var run: RunState
## This round's deals, each {"deal": id from data/trades.json, "need": why the town wants it ("" if nothing), "taken": bool},
## plus "roll" and "boons" when the card rolled modifiers (sim/card_roll.gd).
var offers: Array[Dictionary] = []


func _init(run_state: RunState) -> void:
	run = run_state


func is_here() -> bool:
	return run.world.count_buildings(run.content.trades["needs"]) > 0


## Lays out this round's deals (called as the build phase begins); none until the caravan's building stands.
func lay_out() -> void:
	# A lingering deal not taken last round waits for this one (once).
	var waiting := offers.filter(func(o: Dictionary) -> bool:
		return not o["taken"] and CardRoll.card_has(run.content, o, "linger") and not o.get("lingered", false))
	offers = []
	if not is_here():
		return
	for o: Dictionary in waiting:
		o["lingered"] = true
		o["need"] = need(o["deal"])
		offers.append(o)
	var trades: Dictionary = run.content.trades
	var count := int(trades["offers"]) + int(run.mod("trade_deals"))
	var rng := SeededRng.stream(run.run_seed, "trade_deals", run.round_number)
	# Each deal laid out rolls its own rarity and modifiers (CardRoll), on a stream of its own.
	var roll_rng := SeededRng.stream(run.run_seed, "trade_roll", run.round_number)
	var weights := {}
	var ids: Array = trades["deals"].keys()
	ids.sort()
	for id: String in ids:
		if offers.any(func(o: Dictionary) -> bool: return o["deal"] == id):
			continue
		if not run.content.age_reached(run.age, trades["deals"][id].get("age", "")):
			continue
		var rarity := run.content.rarity_of("deal", id)
		var weight := run.content.rarity_weight(rarity)
		if rarity != "white":
			weight *= 1.0 + run.mod("trade_rarity")
		if need(id) != "":
			weight *= float(trades["need_weight"])
		weights[id] = weight
	while offers.size() < count and not weights.is_empty():
		var id := rng.weighted(weights)
		weights.erase(id)
		var offer := {"deal": id, "need": need(id), "taken": false}
		var def := deal(id)
		CardRoll.roll_card(run.content, roll_rng, offer, "trade", {"give": not def["give"].is_empty(), "get": not def.get("get", {}).is_empty()},
			run.round_number, run.content.num("trade_roll_mult"))
		offers.append(offer)
	if not offers.is_empty():
		run.tell("The %s lays out %d deals." % [trades["name"].to_lower(), offers.size()])


func deal(id: String) -> Dictionary:
	return run.content.trades["deals"][id]


## Why the town wants a deal ("" if nothing in particular): a good it is short of, metal while a tool set of its
## age is unbought, or a barter it holds the goods for twice over.
func need(id: String) -> String:
	var def := deal(id)
	var wants := run.resource_wants()
	for good: String in def.get("get", {}):
		if wants.has(good) and float(run.stock[good]) < float(wants[good]):
			return "Short of %s" % good
	if run.content.has_tag("deal", id, "metal") and _tools_left():
		return "Metal for tools"
	if run.content.has_tag("deal", id, "barter"):
		var spare: bool = not def["give"].is_empty()
		for good: String in def["give"]:
			if good == "shells" or int(run.stock[good]) < int(def["give"][good]) * 2:
				spare = false
		if spare:
			return "Spare %s" % ", ".join(def["give"].keys())
	return ""


func _tools_left() -> bool:
	for id: String in run.content.ages["tools"]:
		if run.content.ages["tools"][id].get("age", "") == run.age and not run.tools.has(id):
			return true
	return false


## Goods a deal brings now: its get, grown a little each round, plus barter_bonus on barters; a rolled offer adds its
## get_mult and the goods thrown in.
func gets(id: String, offer := {}) -> Dictionary:
	var def := deal(id)
	var grow := 1.0 + float(run.content.trades["growth_per_round"]) * (run.round_number - 1)
	if run.content.has_tag("deal", id, "barter"):
		grow += run.mod("barter_bonus")
	grow *= 1.0 + CardRoll.card_sum(run.content, offer, "get_mult")
	var out := {}
	for good: String in def.get("get", {}):
		out[good] = int(floor(float(def["get"][good]) * grow))
	var extra := CardRoll.card_goods(run.content, offer, "goods")
	for good: String in extra:
		out[good] = int(out.get(good, 0)) + int(extra[good])
	return out


## What a deal costs now: its give, less a rolled offer's price_mult (a bargain, cursed gold).
func gives(id: String, offer := {}) -> Dictionary:
	var mult := maxf(0.0, 1.0 + CardRoll.card_sum(run.content, offer, "price_mult"))
	var out := {}
	for good: String in deal(id)["give"]:
		out[good] = int(ceil(float(deal(id)["give"][good]) * mult))
	return out


## People a deal brings, its escort included (role -> how many).
func folk_of(id: String, offer := {}) -> Dictionary:
	var out: Dictionary = deal(id).get("folk", {}).duplicate()
	var extra := CardRoll.card_goods(run.content, offer, "extra_folk")
	for role: String in extra:
		out[role] = int(out.get(role, 0)) + int(extra[role])
	return out


## People a deal brings (0 if none).
func folk_count(id: String, offer := {}) -> int:
	var n := 0
	for k: int in folk_of(id, offer).values():
		n += k
	return n


## Why a deal can't be taken now ("" when it can): not the build phase, taken already, no room or nobody to serve.
func blocker(index: int) -> String:
	if run.phase != RunState.Phase.BUILD or index < 0 or index >= offers.size():
		return "Not now"
	if offers[index]["taken"]:
		return "Taken"
	var id: String = offers[index]["deal"]
	var def := deal(id)
	if folk_count(id, offers[index]) > 0 and run.population() + folk_count(id, offers[index]) > run.housing():
		return "No room: build homes"
	if int(def.get("smith", 0)) > 0 and not run.living_heroes().any(func(h: Unit) -> bool: return h.items.has("weapon")):
		return "No hero has a weapon"
	if int(def.get("relic", 0)) > 0 and run._relic_pool(false).is_empty():
		return "No relics left"
	return ""


func can_take(index: int) -> bool:
	return blocker(index) == "" and run.can_afford(gives(offers[index]["deal"], offers[index]))


## Takes a deal: pays its goods and brings what it brings. Returns false if it can't be taken.
func take(index: int) -> bool:
	if not can_take(index):
		return false
	var offer := offers[index]
	var id: String = offer["deal"]
	var def := deal(id)
	var paid := gives(id, offer)
	for good: String in paid:
		run.stock[good] = int(run.stock[good]) - int(paid[good])
	var got := gets(id, offer)
	for good: String in got:
		run.stock[good] = int(run.stock.get(good, 0)) + int(got[good])
		run.record.note_count("trades", int(got[good]), good)
	var folk := folk_of(id, offer)
	var roles: Array = folk.keys()
	roles.sort()
	for role: String in roles:
		for i in int(folk[role]):
			run.world.folk_ai.add_folk(role)
	var entry := {"deal": id, "rarity": run.content.rarity_of("deal", id)}
	if offer.has("roll"):
		entry["roll"] = offer["roll"]
		entry["mods"] = CardRoll.mods_of(offer)
		CardRoll.note_taken(run, offer)
		_transmute(offer)
	if int(def.get("smith", 0)) > 0:
		var reforged := 0
		for hero in run.living_heroes():
			if hero.items.has("weapon"):
				hero.items["weapon"]["tier"] = int(hero.items["weapon"]["tier"]) + int(def["smith"])
				run.world.hero_ai.apply_hero_stats(hero)
				reforged += 1
		entry["reforged"] = reforged
	if int(def.get("relic", 0)) > 0:
		var rng := SeededRng.stream(run.run_seed, "trade_relic", run.round_number)
		var relic: String = rng.pick(run._relic_pool(false))
		run._gain_relic(relic)
		entry["relic"] = relic
		run.tell("The relic dealer's bundle holds %s." % run.content.relics[relic]["name"])
	offers[index]["taken"] = true
	if not got.is_empty():
		entry["got"] = got
	run.record.note_list("deals", entry)
	run.record.note_action({"kind": "deal", "deal": id})
	run.tell("Trade: %s." % def["name"])
	return true


## An orange deal's price: this round's attack grows (Smuggler's hoard), or a hero turns greedy (Cursed gold).
func _transmute(offer: Dictionary) -> void:
	var content := run.content
	var share := CardRoll.card_sum(content, offer, "wave_share")
	if share > 0.0 and not run.next_wave.is_empty():
		var rng := SeededRng.stream(run.run_seed, "hoard_wave", run.round_number)
		var more := maxi(1, int(ceil(run.next_wave.size() * share)))
		for i in more:
			run.next_wave.append(rng.pick(run.next_wave))
		run.record.note_count("card_mods_fired", 1, "smugglers_hoard")
		run.tell("Word of the smuggled hoard spreads: %d more raiders join this round's attack." % more)
	if CardRoll.card_sum(content, offer, "curse_hero") > 0.0:
		var heroes := run.living_heroes().filter(func(h: Unit) -> bool: return h.trait_id != "greedy")
		if not heroes.is_empty():
			var rng := SeededRng.stream(run.run_seed, "cursed_gold", run.round_number)
			var hero: Unit = rng.pick(heroes)
			hero.trait_id = "greedy"
			run.world.hero_ai.apply_hero_stats(hero)
			run.record.note_count("card_mods_fired", 1, "cursed_gold")
			run.tell("The cursed gold gets into %s's head: they are greedy now." % hero.display_name)


## The deal ids laid out this round, for the record.
func labels() -> Array:
	return offers.map(func(o: Dictionary) -> String: return o["deal"])
