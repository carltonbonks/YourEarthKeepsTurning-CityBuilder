class_name PedlarCamp
extends RefCounted
## The pedlar's camp in the World (data/pedlars.json). On pedlar rounds the player invites one of a few pedlars
## while building (RunState.choose_pedlar). The pedlar camps out past the town for the round's days and packs up
## at dusk on the last day, before the attack. Heroes walk out on their own to sell the loot they carry and buy
## wares: bolder and greedier heroes go further, and a guarded camp tempts the careful. The pedlar hires a hero
## or two as guards, who stay and sleep by the camp and are paid in wares when it packs up. Raiders and
## wanderers that come near go for the camp; if it falls the pedlar flees with the wares.
## HeroAI asks it where heroes trade and guard; EnemyAI sends raiders at it.

const CAMP_RADIUS := 14.0

var w: World
## This round's camp, empty when no pedlar came: {id, pos, wares (items), hp, guards (hero ids), open, fell,
## record (the round's "pedlar" entry, filled as heroes trade)}.
var camp := {}


func _init(world: World) -> void:
	w = world


func def(id: String) -> Dictionary:
	return w.content.pedlars["pedlars"][id]


func is_pedlar_round(round_number: int) -> bool:
	var every := int(w.content.pedlars["every"])
	return every > 0 and round_number % every == 0


## The pedlars offered this round, each {id, pos}: `offer` of them drawn from the pool, each camping at its
## distance in a direction as far from the dens as a few rolled tries find.
func roll_offer() -> Array[Dictionary]:
	var rng := SeededRng.stream(w.run.run_seed, "pedlar_offer", w.run.round_number)
	var ids: Array = w.content.pedlars["pedlars"].keys()
	ids.sort()
	var offer: Array[Dictionary] = []
	while offer.size() < int(w.content.pedlars["offer"]) and not ids.is_empty():
		var id: String = rng.pick(ids)
		ids.erase(id)
		offer.append({"id": id, "pos": _site(id, rng)})
	offer.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Vector2(a["pos"]).length() < Vector2(b["pos"]).length())
	return offer


func _site(id: String, rng: SeededRng) -> Vector2:
	var dist := float(w.content.pedlars["camps"][def(id)["camp"]])
	var best := Vector2.ZERO
	var best_gap := -1.0
	for i in 8:
		var at := Vector2.from_angle(rng.randf() * TAU) * dist
		var gap := INF
		for den in w.dens:
			gap = minf(gap, at.distance_to(den["pos"]))
		if gap > best_gap:
			best_gap = gap
			best = at
	var cell := w.pathing.open_near(w.pathing.index_of(best))
	return w.pathing.center(cell) if cell >= 0 else best


## The tier a pedlar's wares come at this round (before the 25% chance of one more).
func ware_tier(id: String) -> int:
	var drops: Dictionary = w.content.items["drops"]
	var r := w.run.round_number + int(def(id)["ahead"])
	return clampi(1 + (r - 1) / int(drops["tier_every_rounds"]), 1, int(drops["max_tier"]))


## The invited pedlar arrives at dawn on day 1: lays out its wares and hires guards.
func open(choice: Dictionary) -> void:
	var id: String = choice["id"]
	var d := def(id)
	var rng := SeededRng.stream(w.run.run_seed, "pedlar_wares", w.run.round_number)
	var wares: Array[Dictionary] = []
	for i in int(d["wares"]):
		wares.append(Loot.roll(w.content, rng, w.run.round_number + int(d["ahead"]), w.run.age, d["slot"], int(d["affixes"])))
	camp = {"id": id, "pos": choice["pos"], "wares": wares, "hp": float(w.content.pedlars["hp"]), "guards": [],
		"open": true, "fell": false,
		"record": {"id": id, "distance": roundi(Vector2(choice["pos"]).length()), "wares": wares.size(), "visits": 0,
			"sold": 0, "sold_value": 0, "bought": [], "guards": [], "paid": [], "fell": false, "left": 0}}
	w.run.record.note_value("pedlar", camp["record"])
	w.run.tell("The %s sets up camp %s of the town with %d wares." % [d["name"].to_lower(),
		World.compass(Vector2(choice["pos"]).angle()), wares.size()])
	hire_guards()


func is_open() -> bool:
	return not camp.is_empty() and camp["open"]


func is_guard(hero: Unit) -> bool:
	return is_open() and hero.id in camp["guards"]


## Where a guard stands and sleeps: a spot round the camp.
func guard_spot(hero: Unit) -> Vector2:
	return Vector2(camp["pos"]) + Vector2.from_angle(hero.id * 2.1) * (CAMP_RADIUS + 8.0)


## Each step: the pedlar packs up at dusk on the last day, before the attack.
func tick() -> void:
	if is_open() and w.is_dusk() and w.day_index() == w.content.int_num("days_per_round") - 1:
		pack_up()


## Fills the guard posts: heroes whose duty or greed is high enough take the pedlar's coin, the keenest first.
## Run when the camp opens and at each dawn, so a fallen guard is replaced.
func hire_guards() -> void:
	if not is_open():
		return
	var p := w.content.pedlars
	camp["guards"] = camp["guards"].filter(func(id: int) -> bool: return w.run.heroes.any(
		func(h: Unit) -> bool: return h.id == id and h.alive))
	var keen := func(h: Unit) -> float:
		var t: Dictionary = w.content.traits[h.trait_id]
		return maxf(float(t["duty"]), float(t["greed"]))
	var candidates := w.run.living_heroes().filter(func(h: Unit) -> bool:
		return h.id not in camp["guards"] and keen.call(h) >= float(p["guard_appetite"]))
	candidates.sort_custom(func(a: Unit, b: Unit) -> bool:
		return keen.call(a) > keen.call(b) or (keen.call(a) == keen.call(b) and a.id < b.id))
	for h: Unit in candidates:
		if camp["guards"].size() >= int(p["guards"]):
			break
		camp["guards"].append(h.id)
		h.resting = false
		camp["record"]["guards"].append(h.display_name)
		w.run.tell("%s takes the %s's coin to guard the camp." % [h.display_name, def(camp["id"])["name"].to_lower()])


## How far from the hearth this hero will walk to trade: bolder and greedier heroes go further,
## and a guard standing at the camp makes it feel safe enough to go further still.
func reach(hero: Unit, wilds: float, guarded: bool) -> float:
	var p := w.content.pedlars
	var t: Dictionary = w.content.traits[hero.trait_id]
	var r := float(p["camp_reach_base"]) + (float(t["greed"]) + wilds) * float(p["camp_reach_per"])
	if guarded:
		r += float(p["guarded_reach"])
	return r


## For the pedlar cards: which living heroes would walk out to a camp at this spot on an ordinary day
## (by their trait's love of the wilds), as {go: names, guarded: names who would go only once it is guarded}.
func who_would_go(pos: Vector2) -> Dictionary:
	var go: Array[String] = []
	var guarded: Array[String] = []
	for h in w.run.living_heroes():
		var wilds := float(w.content.traits[h.trait_id]["wilds"])
		if pos.length() <= reach(h, wilds, false):
			go.append(h.display_name)
		elif pos.length() <= reach(h, wilds, true):
			guarded.append(h.display_name)
	return {"go": go, "guarded": guarded}


func _guarded() -> bool:
	for h in w.run.heroes:
		if h.alive and h.id in camp["guards"] and h.pos.distance_to(camp["pos"]) < float(w.content.pedlars["guard_radius"]):
			return true
	return false


## Whether a hero sets off for the camp now: it is open, they haven't traded today, it is within their reach,
## and they have loot to sell or the shells for a ware they want.
func wants_visit(hero: Unit, wilds: float) -> bool:
	if not is_open() or hero.pedlar_visit == w.night_key():
		return false
	if Vector2(camp["pos"]).length() > reach(hero, wilds, _guarded()):
		return false
	return not hero.spares.is_empty() or best_ware(hero) >= 0


func price(item: Dictionary) -> int:
	return maxi(1, roundi(Loot.value(w.content, item) * float(w.content.pedlars["price"])))


## The ware this hero would buy (index into the camp's wares), or -1: the one that most improves on what they
## wear by their likes, if they hold its price x their hoard in shells.
func best_ware(hero: Unit) -> int:
	var t: Dictionary = w.content.traits[hero.trait_id]
	var best := -1
	var best_gain := 0.0
	for i in camp["wares"].size():
		var item: Dictionary = camp["wares"][i]
		if hero.gold < price(item) * float(t.get("hoard", 1.0)):
			continue
		var gain := gain_of(hero, item)
		if gain > best_gain:
			best_gain = gain
			best = i
	return best


## How much better an item is than what the hero wears in its slot, by their likes.
func gain_of(hero: Unit, item: Dictionary) -> float:
	var likes: Dictionary = w.content.traits[hero.trait_id].get("likes", {})
	var current: Dictionary = hero.items.get(Loot.slot(w.content, item), {})
	return Loot.score(w.content, item, likes, w.run.gear_bonus()) - (Loot.score(w.content, current, likes, w.run.gear_bonus()) if not current.is_empty() else 0.0)


## A hero at the camp sells all their spare loot (the pedlar takes no cut) and buys the ware they want most.
func trade(hero: Unit) -> void:
	hero.pedlar_visit = w.night_key()
	var rec: Dictionary = camp["record"]
	rec["visits"] = int(rec["visits"]) + 1
	var name: String = def(camp["id"])["name"].to_lower()
	if not hero.spares.is_empty():
		var total := 0
		for item in hero.spares:
			total += roundi(Loot.value(w.content, item) * float(w.content.pedlars["buys"]))
		rec["sold"] = int(rec["sold"]) + hero.spares.size()
		rec["sold_value"] = int(rec["sold_value"]) + total
		hero.gold += total
		w.run.tell("%s sells %d found item%s to the %s for %d shells." % [hero.display_name, hero.spares.size(),
			"" if hero.spares.size() == 1 else "s", name, total])
		hero.spares.clear()
	var pick := best_ware(hero)
	if pick < 0:
		return
	var item: Dictionary = camp["wares"][pick]
	var cost := price(item)
	camp["wares"].remove_at(pick)
	hero.gold -= cost
	hero.mood_events["bought"] = 1
	rec["bought"].append({"hero": hero.display_name, "base": item["base"], "tier": item["tier"],
		"affixes": item["affixes"].duplicate(), "price": cost})
	w.run.record.note_hero_spending("pedlar", cost)
	w.run.tell("%s buys a %s from the %s for %d shells." % [hero.display_name, Loot.describe(w.content, item), name, cost])
	w.hero_ai.give_item(hero, item)


## Whether a raider goes for the camp: it is open and close enough, and the raider isn't a siege engine.
func draws(enemy: Unit) -> bool:
	return is_open() and not w.content.unit_has_tag(enemy, "siege") \
		and enemy.pos.distance_to(camp["pos"]) <= float(w.content.pedlars["aggro"])


## A raider goes for the camp and strikes it when close.
func raid(enemy: Unit) -> void:
	var at: Vector2 = camp["pos"]
	enemy.intent = "raiding the pedlar's camp"
	if enemy.pos.distance_to(at) > enemy.attack_range + CAMP_RADIUS:
		w.walk_toward(enemy, at)
		return
	if enemy.cooldown_left > 0.0:
		return
	enemy.cooldown_left = enemy.cooldown
	camp["hp"] = float(camp["hp"]) - enemy.attack
	w.shots.append({"from": enemy.pos, "to": at, "ranged": enemy.attack_range > 60, "time": w.time})
	if float(camp["hp"]) <= 0.0:
		_fall()


func _fall() -> void:
	camp["open"] = false
	camp["fell"] = true
	camp["record"]["fell"] = true
	camp["record"]["left"] = 0
	camp["wares"] = []
	camp["guards"] = []
	w.run.tell("Raiders overrun the %s's camp. The pedlar flees with what is left, and the guards go unpaid." % def(camp["id"])["name"].to_lower())


## At dusk on the last day the pedlar packs up: each guard still standing takes a ware as pay
## (the one they want most, else the most valuable), and the rest leave with the pedlar.
func pack_up() -> void:
	camp["open"] = false
	var paid := PackedStringArray()
	for h in w.run.heroes:
		if not h.alive or h.id not in camp["guards"] or camp["wares"].is_empty():
			continue
		var i := pay_choice(h, camp["wares"])
		var item: Dictionary = camp["wares"][i]
		camp["wares"].remove_at(i)
		camp["record"]["paid"].append({"hero": h.display_name, "base": item["base"], "tier": item["tier"],
			"affixes": item["affixes"].duplicate()})
		paid.append(h.display_name)
		w.hero_ai.give_item(h, item)
	camp["guards"] = []
	camp["record"]["left"] = camp["wares"].size()
	var name: String = def(camp["id"])["name"]
	if paid.is_empty():
		w.run.tell("The %s packs up and heads off before nightfall." % name.to_lower())
	else:
		w.run.tell("The %s packs up before nightfall and pays %s in wares." % [name.to_lower(), " and ".join(paid)])


## Which ware a guard takes as pay: the biggest gain over what they wear, else the most valuable.
func pay_choice(hero: Unit, wares: Array) -> int:
	var best := -1
	var best_gain := 0.0
	for i in wares.size():
		var gain := gain_of(hero, wares[i])
		if gain > best_gain:
			best_gain = gain
			best = i
	if best >= 0:
		return best
	best = 0
	for i in wares.size():
		if Loot.value(w.content, wares[i]) > Loot.value(w.content, wares[best]):
			best = i
	return best


## The round is over: the camp is gone either way.
func close() -> void:
	if is_open():
		pack_up()
	camp = {}
