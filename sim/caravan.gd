class_name Caravan
extends RefCounted
## The southern caravan's trade cards (`run.caravan`). Once its building stands, every build phase lays out a few
## deals drawn by rarity (data/rarity.json), leaning toward what the town wants: bulk lots, barters, services and
## the odd mythic find. The player takes any deal they can pay for, each once a round. Deals and their numbers are
## in data/trades.json; relics and traditions add deals (trade_deals), make rarer ones likelier (trade_rarity) and
## sweeten barters (barter_bonus).

var run: RunState
## This round's deals, each {"deal": id from data/trades.json, "need": why the town wants it ("" if nothing), "taken": bool}.
var offers: Array[Dictionary] = []


func _init(run_state: RunState) -> void:
	run = run_state


func is_here() -> bool:
	return run.world.count_buildings(run.content.trades["needs"]) > 0


## Lays out this round's deals (called as the build phase begins); none until the caravan's building stands.
func lay_out() -> void:
	offers = []
	if not is_here():
		return
	var trades: Dictionary = run.content.trades
	var count := int(trades["offers"]) + int(run.mod("trade_deals"))
	var rng := SeededRng.stream(run.run_seed, "trade_deals", run.round_number)
	var weights := {}
	var ids: Array = trades["deals"].keys()
	ids.sort()
	for id: String in ids:
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
		offers.append({"deal": id, "need": need(id), "taken": false})
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


## Goods a deal brings now: its get, grown a little each round, plus barter_bonus on barters.
func gets(id: String) -> Dictionary:
	var def := deal(id)
	var grow := 1.0 + float(run.content.trades["growth_per_round"]) * (run.round_number - 1)
	if run.content.has_tag("deal", id, "barter"):
		grow += run.mod("barter_bonus")
	var out := {}
	for good: String in def.get("get", {}):
		out[good] = int(floor(float(def["get"][good]) * grow))
	return out


## People a deal brings (0 if none).
func folk_count(id: String) -> int:
	var n := 0
	for role: String in deal(id).get("folk", {}):
		n += int(deal(id)["folk"][role])
	return n


## Why a deal can't be taken now ("" when it can): not the build phase, taken already, no room or nobody to serve.
func blocker(index: int) -> String:
	if run.phase != RunState.Phase.BUILD or index < 0 or index >= offers.size():
		return "Not now"
	if offers[index]["taken"]:
		return "Taken"
	var id: String = offers[index]["deal"]
	var def := deal(id)
	if folk_count(id) > 0 and run.population() + folk_count(id) > run.housing():
		return "No room: build homes"
	if int(def.get("smith", 0)) > 0 and not run.living_heroes().any(func(h: Unit) -> bool: return h.items.has("weapon")):
		return "No hero has a weapon"
	if int(def.get("relic", 0)) > 0 and run._relic_pool(false).is_empty():
		return "No relics left"
	return ""


func can_take(index: int) -> bool:
	return blocker(index) == "" and run.can_afford(deal(offers[index]["deal"])["give"])


## Takes a deal: pays its goods and brings what it brings. Returns false if it can't be taken.
func take(index: int) -> bool:
	if not can_take(index):
		return false
	var id: String = offers[index]["deal"]
	var def := deal(id)
	for good: String in def["give"]:
		run.stock[good] = int(run.stock[good]) - int(def["give"][good])
	var got := gets(id)
	for good: String in got:
		run.stock[good] = int(run.stock[good]) + int(got[good])
		run.record.note_count("trades", int(got[good]), good)
	var roles: Array = def.get("folk", {}).keys()
	roles.sort()
	for role: String in roles:
		for i in int(def["folk"][role]):
			run.world.folk_ai.add_folk(role)
	var entry := {"deal": id, "rarity": run.content.rarity_of("deal", id)}
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


## The deal ids laid out this round, for the record.
func labels() -> Array:
	return offers.map(func(o: Dictionary) -> String: return o["deal"])
