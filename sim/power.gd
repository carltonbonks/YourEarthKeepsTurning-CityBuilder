class_name Power
extends RefCounted
## Power level: one number for how strong a fighter is, so the settlement and a wave can be compared
## on the same scale (like Path of Exile's monster power). Read-only: nothing in the game uses it
## yet beyond the run record; it is there to compare against wave scaling before anything keys on it.
##
## A fighter's power is sqrt(effective HP x damage per second). How long it lasts times how fast it
## kills is what decides a fight; the square root keeps it additive, so two raiders count as twice
## one raider and a side's power is the sum of its fighters.


static func rating(hp: float, dps: float) -> float:
	return sqrt(maxf(hp, 0.0) * maxf(dps, 0.0))


## One enemy type at full strength. A shield and mail count as extra HP against stone blows,
## which is what most of the town hits with.
static func enemy(content: Content, type_id: String) -> float:
	var e: Dictionary = content.enemies[type_id]
	var hp := float(e["hp"]) / maxf(0.05, (1.0 - float(e.get("shield", 0.0))) * (1.0 - float(e.get("mail", 0.0))))
	return rating(hp, float(e["attack"]) / float(e["cooldown"]))


## A list of enemy type ids (a wave or a raid). War chants raise every enemy's damage while the
## chanter lives, so they scale the whole side by sqrt(1 + chants).
static func wave(content: Content, types: Array) -> float:
	var total := 0.0
	var chant := 0.0
	for id: String in types:
		total += enemy(content, id)
		chant += float(content.enemies[id].get("war_chant", 0.0))
	return total * sqrt(1.0 + chant)


## A hero, townsperson or enemy as it stands now (gear, levels, relics, tools), at full health.
static func unit(u: Unit) -> float:
	return rating(u.max_hp, u.attack / maxf(u.cooldown, 0.01))


## The settlement's power, by part: heroes, townsfolk who fight (tag "fighter"), and the
## defences (the hearth and towers, rated as one: the hearth's HP times their combined fire).
static func town(world: World) -> Dictionary:
	var heroes := 0.0
	for hero in world.run.heroes:
		if hero.alive:
			heroes += unit(hero)
	var fighters := 0.0
	for u in world.folk:
		if u.alive and world.content.unit_has_tag(u, "fighter"):
			fighters += unit(u)
	var tower_bonus := world.run.mod("tower_attack")
	var fire := (world.content.num("hearth_attack") + tower_bonus) / world.content.num("hearth_cooldown")
	for b in world.buildings:
		var def: Dictionary = world.content.buildings[b["type"]]
		if def.has("attack") and float(b["work_left"]) <= 0.0:
			fire += (float(def["attack"]) + tower_bonus) / float(def["cooldown"])
	var defences := rating(world.run.hearth_max_hp(), fire)
	return {"heroes": snappedf(heroes, 0.1), "fighters": snappedf(fighters, 0.1),
		"defences": snappedf(defences, 0.1), "total": snappedf(heroes + fighters + defences, 0.1)}
