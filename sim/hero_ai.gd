class_name HeroAI
extends RefCounted
## Hero behaviour in the World: energy, beds, whims, picking fights, gear and shopping.
##
## Heroes run on energy. It drains while they are up and about (faster in the
## wilds) and comes back while they rest in a lodging. They go to bed when tired
## and at dusk, and get up once rested. A sleeper only wakes when an enemy comes
## within the lodging's wake radius, so where heroes sleep shapes the defence.
## By day heroes with shells shop at the market's stalls, and keen hunters fetch
## goods from the wilds (obsidian, cassiterite) to sell to the settlement.
## Holds no state of its own: everything lives on `w` (the World).

var w: World


func _init(world: World) -> void:
	w = world


func hero_tick(hero: Unit) -> void:
	var t: Dictionary = w.content.traits[hero.trait_id]
	hero.cooldown_left -= w.dt
	var retreat_at := clampf(float(t["retreat_at"]) + w.run.mod("retreat_shift"), 0.0, 0.95)
	if hero.carry_amount > 0 and hero.pos.length() <= w.content.num("settlement_radius"):
		sell_shards(hero)
	_call_for_supplies(hero, t, retreat_at)
	if not hero.retreating and hero.hp_fraction() < retreat_at + 0.1:
		_use_provision(hero, "heal")
	if not hero.retreating and hero.hp_fraction() < retreat_at:
		hero.retreating = true
		hero.resting = false
		hero.target = null
		if w.wave_spawned:
			w.wave_stats["retreats"] = int(w.wave_stats["retreats"]) + 1
		w.run.tell("%s is badly hurt and falls back to the hearth." % hero.display_name)
	# A hurt hero who has sent for a poultice waits for it where they are, unless something is coming for them.
	if hero.retreating and runner_coming(hero) and w.nearest_enemy(hero.pos, w.content.num("supply_wait_safe")) == null:
		hero.intent = "waiting for a runner with a poultice"
		return
	if hero.retreating:
		hero.intent = "retreating to heal"
		if w.go_heal(hero, 1.0 + w.run.mod("hearth_heal_mult")):
			if hero.hp_fraction() >= World.HEAL_UNTIL:
				hero.retreating = false
		return
	if hero.resting:
		rest_tick(hero)
		return
	var drain := w.content.num("energy_drain_wilds") if hero.pos.length() > w.content.num("settlement_radius") else w.content.num("energy_drain")
	drain *= maxf(0.2, 1.0 - Loot.total(w.content, hero, "energy", w.run.gear_bonus()))
	if _lone():
		drain *= 1.0 - w.run.mod("lone_tire")
	var was_awake := hero.energy > 0.0
	hero.energy = maxf(0.0, hero.energy - drain * w.dt)
	if hero.energy <= float(t.get("tired_at", 25)) and hero.pos.length() > w.content.num("settlement_radius"):
		_use_provision(hero, "energy")
	if was_awake and hero.energy <= 0.0:
		w.run.tell("%s is exhausted and fights weakly until they rest." % hero.display_name)

	var whim: Dictionary = w.content.whims.get(hero.whim, {})
	var wilds := float(whim.get("wilds", t["wilds"]))
	# By day the keen ones hunt far out; at dusk and night everyone stays near home.
	if w.pedlar.is_guard(hero):
		_guard_tick(hero, t)
		return
	var reach := w.content.num("settlement_radius") + 160.0
	if not w.is_dusk():
		reach = maxf(reach, wilds * (w.content.num("den_max_distance") + 120.0))
	hero.target = _choose_target(hero, t, reach, whim.get("trophy", false))
	# By day a hero with shells stops at the stalls, unless a fight is close.
	var fight_close := hero.target != null and hero.target.pos.distance_to(hero.pos) < 140.0
	if not w.is_night() and not fight_close and hero.gold > 0 and _shop_tick(hero, t, whim):
		return
	var bed := bed_index(hero)
	var why_bed := _wants_bed(hero, t)
	if why_bed != "":
		# On the way to bed a hero only fights what is close or chasing them.
		if hero.target != null and (hero.target.pos.distance_to(hero.pos) <= wake_radius(bed) or hero.target.target == hero):
			w.fight(hero, hero.target)
			return
		hero.target = null
		hero.intent = "%s, heading to %s" % [why_bed, bed_name(bed)]
		if w.walk_toward(hero, bed_pos(hero), 8.0):
			hero.resting = true
			_on_lie_down(hero, bed)
		return
	if hero.target != null:
		w.fight(hero, hero.target)
		return
	if runner_coming(hero):
		hero.intent = "waiting for a runner with %s" % ("a poultice" if hero.supply_call == "heal" else "food")
		return
	if not w.is_dusk() and w.pedlar.wants_visit(hero, wilds):
		hero.intent = "off to trade with the %s" % w.pedlar.def(w.pedlar.camp["id"])["name"].to_lower()
		if w.walk_toward(hero, w.pedlar.camp["pos"], PedlarCamp.CAMP_RADIUS + 6.0):
			w.pedlar.trade(hero)
		return
	if not w.is_dusk() and float(t["greed"]) + wilds >= w.content.num("find_appetite"):
		var find := find_for(hero, wilds)
		if find >= 0:
			hero.intent = "digging out the %s" % w.content.world["nodes"][w.nodes[find]["type"]]["name"].to_lower()
			if w.walk_toward(hero, w.nodes[find]["pos"], 10.0):
				dig_find(hero, find)
			return
	if not w.is_dusk() and wilds > 0.5 and not w.dens.is_empty():
		var outcrop := outcrop_for(hero)
		if outcrop >= 0:
			hero.intent = "prising %s from the %s" % [w.nodes[outcrop]["gives"], w.content.world["nodes"][w.nodes[outcrop]["type"]]["name"].to_lower()]
			if w.walk_toward(hero, w.nodes[outcrop]["pos"], 10.0):
				take_shards(hero, outcrop)
			return
		var den: Dictionary = w.dens[hero.id % w.dens.size()]
		hero.intent = "stalking the %s" % w.content.world["dens"][den["type"]]["name"].to_lower()
		w.walk_toward(hero, den["pos"] * 0.85, 10.0)
		return
	var index := w.run.heroes.find(hero)
	if w.is_dusk():
		hero.intent = "guarding the camp"
		w.walk_toward(hero, Vector2.from_angle(index * 1.7 + 0.4) * (w.content.num("settlement_radius") * 0.6), 4.0)
		return
	# A quiet day for a hero who doesn't roam: drill by the hearth for a trickle of XP.
	hero.intent = "drilling by the hearth"
	if w.walk_toward(hero, Vector2.from_angle(index * 1.7 + 0.4) * w.content.num("drill_radius"), 4.0):
		var xp := w.content.num("drill_xp_per_second") * w.dt
		hero.xp += xp
		var key := w.run.record.impact_key(hero)
		if not key.is_empty():
			w.run.record.note_impact(key[0], key[1], "drilled", xp)


## A hero guarding the pedlar's camp: fights anything near it, sleeps beside it, trades there once a day,
## and otherwise stands watch.
func _guard_tick(hero: Unit, t: Dictionary) -> void:
	var camp_pos: Vector2 = w.pedlar.camp["pos"]
	var foe := w.nearest_enemy(camp_pos, float(w.content.pedlars["guard_radius"]))
	if foe != null:
		hero.target = foe
		hero.intent = "defending the pedlar's camp"
		w.fight(hero, foe)
		return
	hero.target = null
	var why_bed := _wants_bed(hero, t)
	if why_bed != "":
		hero.intent = "%s, bedding down at the pedlar's camp" % why_bed
		if w.walk_toward(hero, bed_pos(hero), 8.0):
			hero.resting = true
		return
	hero.intent = "guarding the pedlar's camp"
	if w.walk_toward(hero, w.pedlar.guard_spot(hero), 6.0) and hero.pedlar_visit != w.night_key():
		w.pedlar.trade(hero)


## Why a hero wants to be in bed right now ("" if they don't).
func _wants_bed(hero: Unit, t: Dictionary) -> String:
	# Everyone knows the warned attack is coming, so heroes stay up for it unless worn out.
	if w.is_dusk() and w.day_index() < w.content.int_num("days_per_round") - 1:
		return "night is falling"
	# A hero who has sent for food keeps going while a runner is on the way, unless worn right out.
	if hero.energy <= float(t.get("tired_at", 25)) and not (hero.energy > 0.0 and runner_coming(hero)):
		return "tired"
	if _carousing(hero):
		return "off to drink"
	if w.time_of_day() < w.content.num("day_seconds") * float(w.content.whims.get(hero.whim, {}).get("lie_in", 0.0)):
		return "sleeping in"
	return ""


func rest_tick(hero: Unit) -> void:
	var bed := bed_index(hero)
	if hero.pos.distance_to(bed_pos(hero)) > 20.0:
		# The bed moved (a new lodging opened): walk over and lie down again.
		hero.resting = false
		return
	var danger := w.nearest_enemy(hero.pos, wake_radius(bed))
	if danger != null:
		hero.resting = false
		if w.is_night() and hero.woke_night != w.night_key():
			hero.woke_night = w.night_key()
			w.run.tell("%s wakes in %s to fight a %s." % [hero.display_name, bed_name(bed), danger.display_name.to_lower()])
		return
	var def := lodging_def(bed)
	var rate := w.content.num("energy_rest") * (float(def["rest"]) if not def.is_empty() else w.content.num("energy_rest_rough"))
	if is_preferred(hero, bed):
		rate *= w.content.num("energy_home_bonus")
	hero.energy = minf(w.content.num("hero_energy_max"), hero.energy + rate * w.dt)
	hero.hp = minf(hero.max_hp, hero.hp + (float(def.get("heal", 0.0)) + Loot.total(w.content, hero, "rest_heal", w.run.gear_bonus())) * w.dt)
	if _carousing(hero):
		hero.intent = "drinking in %s" % bed_name(bed)
	elif w.pedlar.is_guard(hero):
		hero.intent = "asleep at the pedlar's camp" if w.is_night() else "resting at the pedlar's camp"
	else:
		hero.intent = "asleep in %s" % bed_name(bed) if w.is_night() else "resting in %s" % bed_name(bed)
	if w.is_night():
		# Sleeping by the fire only rankles once the town has beds that others get.
		if bed < 0:
			hero.slept = "rough" if count_lodgings() > 0 else ""
		else:
			hero.slept = "favourite" if is_preferred(hero, bed) else "other"
	if w.is_night() and bed >= 0 and hero.paid_night != w.night_key():
		hero.paid_night = w.night_key()
		_pay_town(hero, int(def.get("night_price", 0)), "tavern")
	if _wants_bed(hero, w.content.traits[hero.trait_id]) == "" and hero.energy >= w.content.num("energy_wake_at"):
		hero.resting = false


func _on_lie_down(hero: Unit, bed: int) -> void:
	if _carousing(hero) and hero.caroused != w.night_key():
		hero.caroused = w.night_key()
		var spent := _pay_town(hero, int(w.content.whims["carouse"].get("spend", 0)), "carousing")
		w.run.tell("%s settles in at %s and drinks %d shells' worth." % [hero.display_name, bed_name(bed), spent])


## Takes up to `amount` shells from a hero into the settlement's stock. Returns what was paid.
func _pay_town(hero: Unit, amount: int, reason: String) -> int:
	var paid := mini(amount, hero.gold)
	if paid <= 0:
		return 0
	hero.gold -= paid
	w.run.stock["shells"] = int(w.run.stock["shells"]) + paid
	w.run.record.note_hero_spending(reason, paid)
	return paid


func _carousing(hero: Unit) -> bool:
	if hero.whim != "carouse" or w.first_built("tavern") < 0 or w.pedlar.is_guard(hero):
		return false
	return w.is_night() or w.time_of_day() >= w.content.num("day_seconds") * float(w.content.whims["carouse"].get("from", 0.5))


## Gives each living hero a bed: their favourite lodging with a free bed, then
## any free bed, else a spot by the hearth.
func assign_lodgings() -> void:
	var used := {}
	for hero in w.run.living_heroes():
		hero.lodging = -1
		var choices: Array = w.content.traits[hero.trait_id].get("lodging", []).duplicate()
		for id in w.content.lodging_types():
			if not choices.has(id):
				choices.append(id)
		for type: String in choices:
			var i := _free_bed(type, used)
			if i >= 0:
				hero.lodging = i
				used[i] = int(used.get(i, 0)) + 1
				break


func _free_bed(type: String, used: Dictionary) -> int:
	for i in w.buildings.size():
		var b := w.buildings[i]
		if b["type"] == type and float(b["work_left"]) <= 0.0 \
				and int(used.get(i, 0)) < int(w.content.buildings[type]["lodging"]["beds"]):
			return i
	return -1


func count_lodgings() -> int:
	var n := 0
	for type in w.content.lodging_types():
		n += w.count_buildings(type)
	return n


## Where a hero sleeps tonight: a building index, or -1 for the hearth.
func bed_index(hero: Unit) -> int:
	if w.pedlar.is_guard(hero):
		return -1
	if _carousing(hero):
		return w.first_built("tavern")
	return hero.lodging


func bed_pos(hero: Unit) -> Vector2:
	if w.pedlar.is_guard(hero):
		return w.pedlar.guard_spot(hero)
	var bed := bed_index(hero)
	if bed >= 0:
		return w.buildings[bed]["pos"]
	return Vector2.from_angle(w.run.heroes.find(hero) * 1.7 + 0.4) * (World.HEARTH_RADIUS + 16.0)


func lodging_def(bed: int) -> Dictionary:
	return w.content.buildings[w.buildings[bed]["type"]]["lodging"] if bed >= 0 else {}


func bed_name(bed: int) -> String:
	return "the %s" % w.content.buildings[w.buildings[bed]["type"]]["name"].to_lower() if bed >= 0 else "the open by the hearth"


func wake_radius(bed: int) -> float:
	return float(lodging_def(bed)["wake_radius"]) if bed >= 0 else w.content.num("rough_wake_radius")


func is_preferred(hero: Unit, bed: int) -> bool:
	return bed >= 0 and w.buildings[bed]["type"] in w.content.traits[hero.trait_id].get("lodging", [])


## Each hero's whim for the day, rolled at dawn from their trait's weights.
func roll_whims() -> void:
	var rng := SeededRng.stream(w.run.run_seed, "whims", w.night_key())
	var notes := PackedStringArray()
	for hero in w.run.living_heroes():
		var weights: Dictionary = w.content.traits[hero.trait_id].get("whims", {}).duplicate()
		for id: String in weights.keys():
			var needs: String = w.content.whims[id].get("needs", "")
			if needs != "" and w.count_buildings(needs) == 0:
				weights[id] = 0.0
		hero.whim = rng.weighted(weights)
		if hero.whim == "":
			hero.whim = "none"
		w.run.record.note_whim(hero)
		if hero.whim != "none":
			notes.append("%s is %s" % [hero.display_name, w.content.whims[hero.whim]["name"]])
	if not notes.is_empty():
		w.run.tell("Today %s." % ", ".join(notes))


## Scores every reachable enemy from this hero's point of view and picks the best.
## Brave and greedy heroes value wanderers (glory and loot); dutiful ones value
## threats to the camp; cautious ones avoid enemies that could kill them fast.
## A hero after a trophy also values big, tough monsters.
func _choose_target(hero: Unit, t: Dictionary, reach: float, trophy := false) -> Unit:
	var best: Unit = null
	var best_score := -INF
	var reason := ""
	for enemy in w.enemies:
		if not enemy.alive or not enemy.spawned:
			continue
		var from_home := enemy.pos.length()
		if from_home > reach and enemy.target != hero:
			continue
		var distance := hero.pos.distance_to(enemy.pos)
		var threat_to_camp := 1.0 - clampf(from_home / w.content.num("world_radius"), 0.0, 1.0)
		var danger := enemy.attack / maxf(hero.hp, 1.0) * 10.0
		var glory := float(t["wilds"]) * (4.0 if enemy.den_index >= 0 else 1.0) * (0.5 + float(t["greed"]) * 0.5)
		# Prizes posted by buildings (the hunting lodge) draw greedy heroes most.
		glory += w.market.prize_for(enemy.type_id) * float(t["greed"]) * 0.5
		if trophy:
			glory += enemy.max_hp / 12.0
		var duty := float(t["duty"]) * threat_to_camp * 8.0
		var score := 10.0 - distance / 60.0 + glory + duty - float(t["caution"]) * danger * 2.0
		if enemy == hero.target:
			score += World.TARGET_STICKINESS
		if score > best_score:
			best_score = score
			best = enemy
			reason = "hunting for glory" if glory >= duty and enemy.den_index >= 0 else ("defending the camp" if duty >= 3.0 else "fighting")
	if best != null:
		hero.intent = "%s (%s)" % [reason, best.display_name]
	return best


func apply_hero_stats(hero: Unit) -> void:
	var c: Dictionary = w.content.hero_classes[hero.type_id]
	var old_max := hero.max_hp
	hero.max_hp = maxf(1.0, float(c["hp"]) + (hero.level - 1) * w.content.num("level_hp") \
		+ Loot.total(w.content, hero, "hp", w.run.gear_bonus()) + w.run.mod("hero_hp"))
	hero.attack = float(c["attack"]) + (hero.level - 1) * w.content.num("level_attack") \
		+ Loot.total(w.content, hero, "attack", w.run.gear_bonus()) + w.run.mod("hero_attack")
	# Trophy Belt: damage for every so many kills. Witch's Thread: cursed gear's HP penalty is lifted.
	if w.run.has_effect("trophy_every"):
		hero.attack += w.run.mod("trophy_damage") * (hero.kills / int(w.run.mod("trophy_every")))
	if w.run.has_effect("curse_lift"):
		for s: String in hero.items:
			if hero.items[s]["affixes"].has("cursed"):
				hero.max_hp -= float(w.content.items["affixes"]["cursed"].get("hp", 0.0))
	hero.attack_range = float(c["range"])
	hero.cooldown = float(c["cooldown"])
	hero.speed = float(c["speed"]) + Loot.total(w.content, hero, "speed", w.run.gear_bonus())
	if old_max > 1.0 and hero.max_hp > old_max:
		hero.hp += hero.max_hp - old_max
	hero.hp = minf(hero.hp, hero.max_hp)


## A hero picks up an item: wears it if they like it better than what they have
## (by their personality), otherwise carries it to sell.
func give_item(hero: Unit, item: Dictionary) -> void:
	var slot := Loot.slot(w.content, item)
	var likes: Dictionary = w.content.traits[hero.trait_id].get("likes", {})
	var current: Dictionary = hero.items.get(slot, {})
	var equip := current.is_empty() or Loot.score(w.content, item, likes, w.run.gear_bonus()) > Loot.score(w.content, current, likes, w.run.gear_bonus())
	if equip:
		if not current.is_empty():
			hero.spares.append(current)
		hero.items[slot] = item
		apply_hero_stats(hero)
		w.run.tell("%s finds a %s and takes it up." % [hero.display_name, Loot.describe(w.content, item)])
	else:
		hero.spares.append(item)
		w.run.tell("%s finds a %s and keeps it to sell." % [hero.display_name, Loot.describe(w.content, item)])
	w.run.record.note_loot(hero, item, equip)
	_trim_spares(hero)


## Heroes carry only a few spare items; the least valuable is dropped.
func _trim_spares(hero: Unit) -> void:
	if hero.spares.size() > int(w.content.items["spare_limit"]):
		hero.spares.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Loot.value(w.content, a) > Loot.value(w.content, b))
		hero.spares.pop_back()


func maybe_drop(hero: Unit, victim: Unit) -> void:
	var drops: Dictionary = w.content.items["drops"]
	var chance := float(drops["boss"]) if victim.is_boss else float(drops["den"] if victim.den_index >= 0 else drops["wave"])
	if w.rng.randf() < chance:
		var item := Loot.roll(w.content, w.rng, w.run.round_number, w.run.age)
		if w.run.has_effect("cursed_drops") and not item["affixes"].has("cursed") and w.rng.randf() < w.run.mod("cursed_drops"):
			item["affixes"].append("cursed")
			w.run.relic_fired("cursed_drops")
		give_item(hero, item)


# --- Relics on heroes ----------------------------------------------------------

## Lone Wolf's Pelt: the town has few enough heroes for it to work.
func _lone() -> bool:
	return w.run.has_effect("lone_heroes") and w.run.living_heroes().size() <= int(w.run.mod("lone_heroes"))


## How much harder a hero hits from relics that depend on the moment: few heroes (Lone Wolf's Pelt),
## another hero close by (Blood-brother Knot), night or day (Owl Eyes).
func relic_damage_mult(hero: Unit) -> float:
	var mult := 1.0
	if _lone():
		mult *= 1.0 + w.run.mod("lone_damage")
	if w.run.has_effect("kin_damage"):
		var radius := w.run.mod("kin_radius")
		for other in w.run.heroes:
			if other != hero and other.alive and other.pos.distance_to(hero.pos) <= radius:
				mult *= 1.0 + w.run.mod("kin_damage")
				break
	mult *= 1.0 + w.run.mod("night_damage" if w.is_night() else "day_damage")
	return maxf(0.1, mult)


## Chosen One's Brand: extra XP share for the town's highest-level hero (most XP, then the longest here, breaks ties),
## less for the rest.
func chosen_xp(hero: Unit) -> float:
	if not w.run.has_effect("chosen_xp"):
		return 0.0
	var chosen: Unit = null
	for h in w.run.heroes:
		if h.alive and (chosen == null or h.level > chosen.level or (h.level == chosen.level and h.xp > chosen.xp)):
			chosen = h
	return w.run.mod("chosen_xp") if chosen == hero else w.run.mod("others_xp")


## Trophy Belt: a hero who reaches another milestone of kills grows stronger at once.
func count_trophy(hero: Unit) -> void:
	var every := int(w.run.mod("trophy_every"))
	if every > 0 and hero.kills % every == 0:
		apply_hero_stats(hero)
		w.run.relic_fired("trophy_every")
		w.run.tell("%s adds a trophy to their belt (%d kills)." % [hero.display_name, hero.kills])


## Mourning Bell: a fallen hero's XP, all of it, is shared among the living heroes.
func mourn(fallen: Unit) -> void:
	var share := w.run.mod("mourning_share")
	if share <= 0.0:
		return
	var living := w.run.heroes.filter(func(h: Unit) -> bool: return h.alive and h != fallen)
	if living.is_empty():
		return
	var total := fallen.xp
	for lv in range(1, fallen.level):
		total += w.content.num("xp_per_level") * lv
	for h: Unit in living:
		h.xp += total * share / living.size()
	w.run.relic_fired("mourning_share")
	w.run.tell("The bell tolls for %s; what they learned passes to the others." % fallen.display_name)


## How much a hero wants a good on a stall (0 or less: not at all).
func _want(hero: Unit, t: Dictionary, good: Dictionary) -> float:
	var r: Dictionary = w.content.market["recipes"][good["recipe"]]
	if good.has("item"):
		var item: Dictionary = good["item"]
		var likes: Dictionary = t.get("likes", {})
		var slot := Loot.slot(w.content, item)
		var current: Dictionary = hero.items.get(slot, {})
		var gain := Loot.score(w.content, item, likes, w.run.gear_bonus()) - (Loot.score(w.content, current, likes, w.run.gear_bonus()) if not current.is_empty() else 0.0)
		return gain * (1.25 if slot == t.get("prefers", "") else 1.0)
	var have := hero.pack.count(good["recipe"])
	if have >= int(w.content.market["pack_limit"]):
		return 0.0
	var p: Dictionary = w.content.market["provisions"][r["provision"]]
	# Cautious heroes stock up on poultices; keen hunters on food for the trail.
	var keen := float(t["caution"]) if p.has("heal") else float(t["wilds"])
	return (2.0 + 3.0 * keen) / (1.0 + have)


## The good a hero would buy right now: {stall, index, price}, or {} if nothing tempts them.
func best_buy(hero: Unit, t: Dictionary) -> Dictionary:
	var best := {}
	var best_want := 0.0
	for i in w.buildings.size():
		var b := w.buildings[i]
		var kind: String = w.content.buildings[b["type"]].get("stall", {}).get("sells", "")
		if kind == "" or float(b["work_left"]) > 0.0 or b["goods"].is_empty():
			continue
		if w.run.price_markup(kind) > float(t.get("max_markup", 1.5)) + 0.001:
			continue
		for j in b["goods"].size():
			var good: Dictionary = b["goods"][j]
			var price := w.run.price_of(good)
			# Hoarders only buy when they have plenty left over.
			if hero.gold < price * float(t.get("hoard", 1.0)):
				continue
			var want := _want(hero, t, good)
			if want > best_want:
				best_want = want
				best = {"stall": i, "index": j, "price": price}
	return best


## A hero in town with shells to spend walks to a stall with something they want.
## Returns true while they are shopping.
func _shop_tick(hero: Unit, t: Dictionary, whim: Dictionary) -> bool:
	var in_town := hero.pos.length() <= w.content.num("settlement_radius") + 60.0
	if not in_town and hero.shop_stall < 0 and not whim.get("shop_anywhere", false):
		return false
	var pick := best_buy(hero, t)
	if pick.is_empty():
		hero.shop_stall = -1
		return false
	var stall: Dictionary = w.buildings[pick["stall"]]
	hero.shop_stall = pick["stall"]
	hero.intent = "shopping at the %s" % w.content.buildings[stall["type"]]["name"].to_lower()
	if w.walk_toward(hero, stall["pos"], 12.0):
		_buy(hero, pick)
		hero.shop_stall = -1
	return true


func _buy(hero: Unit, pick: Dictionary) -> void:
	var stall: Dictionary = w.buildings[pick["stall"]]
	var good: Dictionary = stall["goods"][pick["index"]]
	var price: int = pick["price"]
	stall["goods"].remove_at(pick["index"])
	hero.gold -= price
	w.run.stock["shells"] = int(w.run.stock["shells"]) + price
	hero.mood_events["bought"] = 1
	w.run.record.note_hero_spending("market", price)
	w.run.record.note_market_sale(hero, good, price)
	var where: String = w.content.buildings[stall["type"]]["name"].to_lower()
	if good.has("item"):
		var item: Dictionary = good["item"]
		var slot := Loot.slot(w.content, item)
		if hero.items.has(slot):
			hero.spares.append(hero.items[slot])
			_trim_spares(hero)
		hero.items[slot] = item
		apply_hero_stats(hero)
		w.run.tell("%s buys a %s at the %s for %d shells." % [hero.display_name, Loot.describe(w.content, item), where, price])
	else:
		hero.pack.append(good["recipe"])
		w.run.tell("%s buys %s at the %s for %d shells." % [hero.display_name, w.content.recipe_name(good["recipe"]), where, price])


## Uses one provision from the pack that has `effect` ("energy" or "heal"). True if one was used.
func _use_provision(hero: Unit, effect: String) -> bool:
	for k in hero.pack.size():
		var id := hero.pack[k]
		var p: Dictionary = w.content.market["provisions"][w.content.market["recipes"][id]["provision"]]
		if not p.has(effect):
			continue
		hero.pack.remove_at(k)
		if effect == "energy":
			hero.energy = minf(w.content.num("hero_energy_max"), hero.energy + float(p["energy"]))
			w.run.tell("%s eats %s and keeps going." % [hero.display_name, p["name"]])
		else:
			hero.hp = minf(hero.max_hp, hero.hp + float(p["heal"]))
			w.run.tell("%s presses a %s to their wounds." % [hero.display_name, p["name"]])
		return true
	return false


## Out in the wilds with no provision left for what they are about to need, a hero who can pay sends for one: food
## once their energy nears feeling tired, a poultice once their health nears falling back. A courier building's runner
## brings it from the stall (FolkAI._dispatch_runners). Heroes who hoard only send when they have plenty to spare.
func _call_for_supplies(hero: Unit, t: Dictionary, retreat_at: float) -> void:
	hero.supply_call = ""
	if hero.runner != null and not runner_coming(hero):
		hero.runner = null
	var hut := w.folk_ai.courier_hut()
	if hut < 0 or w.is_dusk() or w.pedlar.is_guard(hero) or hero.pos.length() <= w.content.num("settlement_radius"):
		return
	var need := ""
	if hero.hp_fraction() < retreat_at + w.content.num("supply_heal_margin") and not _has_provision(hero, "heal"):
		need = "heal"
	elif hero.energy <= float(t.get("tired_at", 25)) + w.content.num("supply_energy_margin") and not _has_provision(hero, "energy"):
		need = "energy"
	if need == "":
		return
	var pick := w.market.provision_on_stall(need)
	if pick.is_empty():
		return
	var kind: String = w.content.buildings[w.buildings[pick["stall"]]["type"]]["stall"]["sells"]
	if w.run.price_markup(kind) > float(t.get("max_markup", 1.5)) + 0.001:
		return
	if hero.gold < (int(pick["price"]) + w.folk_ai.runner_fee(hut)) * float(t.get("hoard", 1.0)):
		return
	hero.supply_call = need


## A runner is on its way to this hero.
func runner_coming(hero: Unit) -> bool:
	return hero.runner != null and hero.runner.alive and hero.runner.errand_for == hero


func _has_provision(hero: Unit, effect: String) -> bool:
	for id in hero.pack:
		if w.content.market["provisions"][w.content.market["recipes"][id]["provision"]].has(effect):
			return true
	return false


## A runner has handed over a provision: the hero uses it at once, and one patched up enough stops falling back.
func on_supplied(hero: Unit, effect: String) -> void:
	_use_provision(hero, effect)
	if effect == "heal" and hero.retreating:
		var retreat_at := float(w.content.traits[hero.trait_id]["retreat_at"]) + w.run.mod("retreat_shift")
		if hero.hp_fraction() >= retreat_at + 0.1:
			hero.retreating = false
			w.run.tell("%s is patched up and turns back to the hunt." % hero.display_name)


## The nearest earth find (a sunk den's hoard, starstone by a ridge) within this hero's reach, or -1.
## Reach grows with how keen they are on the wilds, as for hunting.
func find_for(hero: Unit, wilds: float) -> int:
	var reach := wilds * (w.content.num("den_max_distance") + w.content.num("find_reach"))
	var best := -1
	var best_d := INF
	for i in w.nodes.size():
		var node := w.nodes[i]
		if node.get("gone", false) or int(node["amount"]) <= 0 or not w.content.world["nodes"][node["type"]].get("find", false):
			continue
		if Vector2(node["pos"]).length() > reach:
			continue
		var d := hero.pos.distance_to(node["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


## A hero digs out an earth find: an item a tier above an ordinary drop, earthborn. The find is gone.
func dig_find(hero: Unit, index: int) -> void:
	var node := w.nodes[index]
	node["amount"] = 0
	node["gone"] = true
	var rng := SeededRng.stream(w.run.run_seed, "earth_find", index)
	var item := Loot.earth_find(w.content, rng, w.run.round_number, w.run.age)
	w.run.tell("%s digs %s out of the %s." % [hero.display_name, "something old and strange", w.content.world["nodes"][node["type"]]["name"].to_lower()])
	w.run.record.note_count("finds_dug", 1, node["type"])
	give_item(hero, item)


## A node out in the wilds near a hero worth fetching from (obsidian, cassiterite), or -1.
## Only once the building that buys it stands.
func outcrop_for(hero: Unit) -> int:
	if hero.carry_amount > 0:
		return -1
	var best := -1
	var best_d := 300.0
	for i in w.nodes.size():
		var node := w.nodes[i]
		if not (node.get("heroes_only", false) or node.get("wild", false)) or int(node["amount"]) <= 0 or not w.node_active(node):
			continue
		var def: Dictionary = w.content.world["nodes"][node["type"]]
		if w.count_buildings(def.get("buyer", "")) == 0 or int(w.run.stock[node["gives"]]) >= int(def.get("buy_until", 99)):
			continue
		var d := hero.pos.distance_to(node["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


func take_shards(hero: Unit, index: int) -> void:
	var node := w.nodes[index]
	var take := mini(int(node["amount"]), int(w.content.market["hero_carry"]))
	node["amount"] = int(node["amount"]) - take
	hero.carrying = node["gives"]
	hero.carry_amount = take


## A hero back in town sells what they carry from the wilds to the settlement, which pays what it can.
func sell_shards(hero: Unit) -> void:
	var n := hero.carry_amount
	var price := 0
	for id: String in w.content.world["nodes"]:
		if w.content.world["nodes"][id]["gives"] == hero.carrying:
			price = int(w.content.world["nodes"][id].get("price", 0))
	var pay := mini(n * price, int(w.run.stock["shells"]))
	w.bring_in(hero.carrying, n)
	w.run.stock["shells"] = int(w.run.stock["shells"]) - pay
	hero.gold += pay
	hero.carry_amount = 0
	w.run.record.note_economy(hero.carrying, n)
	w.run.record.impact_key(hero)
	w.run.record.note_impact("heroes", hero.display_name, "goods", n, hero.carrying)
	w.run.tell("%s brings back %d %s and sells it for %d shells." % [hero.display_name, n, hero.carrying, pay])
