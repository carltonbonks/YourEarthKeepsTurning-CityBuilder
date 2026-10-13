class_name Tooltips
extends RefCounted
## Hover text for things on the map and in the build list. Read-only: it only
## looks at the run, so it can be swapped or restyled without touching the sim.
## Each tip is {"title": String, "lines": Array[String], "tags": Array, "warnings": Array[String]}.


static func _tip(title: String) -> Dictionary:
	return {"title": title, "lines": [] as Array[String], "tags": [], "warnings": [] as Array[String]}


static func hero(run: RunState, u: Unit) -> Dictionary:
	var c := run.content
	var t := _tip(u.display_name)
	t["lines"].append("%s %s, level %d" % [c.traits[u.trait_id]["name"], c.hero_classes[u.type_id]["name"].to_lower(), u.level])
	t["lines"].append("Health %d/%d, attack %s" % [roundi(u.hp), roundi(u.max_hp), _num(u.attack)])
	t["lines"].append("Energy %d, mood %d, %d shells, %d kills" % [roundi(u.energy), roundi(u.mood), u.gold, u.kills])
	for slot: String in ["weapon", "armor", "charm"]:
		if u.items.has(slot):
			t["lines"].append("%s: %s" % [slot.capitalize(), Loot.describe(c, u.items[slot])])
	var whim: Dictionary = c.whims.get(u.whim, {})
	if str(whim.get("name", "")) != "":
		t["lines"].append("Today: %s" % whim["name"])
	t["lines"].append("Sleeps in %s%s" % [run.world.hero_ai.bed_name(run.world.hero_ai.bed_index(u)),
		" (their favourite)" if run.world.hero_ai.is_preferred(u, run.world.hero_ai.bed_index(u)) else ""])
	if u.intent != "":
		t["lines"].append("Now: %s" % u.intent)
	if u.mood <= c.num("mood_grumble_at"):
		t["warnings"].append("Unhappy: leaves town at mood %d or below." % c.int_num("mood_leave_at"))
	return t


static func folk(run: RunState, u: Unit) -> Dictionary:
	var c := run.content
	var def: Dictionary = c.townsfolk[u.type_id]
	var t := _tip(def["name"])
	t["lines"].append(def["text"])
	t["lines"].append("Health %d/%d, attack %s" % [roundi(u.hp), roundi(u.max_hp), _num(u.attack)])
	if u.master_of != "":
		t["lines"].append("Master of the %s" % c.buildings[u.master_of]["name"].to_lower())
	if u.carry_amount > 0:
		t["lines"].append("Carrying %d %s" % [u.carry_amount, u.carrying])
	if u.intent != "":
		t["lines"].append("Now: %s" % u.intent)
	return t


## A creature type, with or without a live unit (dens show the type they spawn).
static func enemy(run: RunState, type_id: String, u: Unit = null) -> Dictionary:
	var c := run.content
	var def: Dictionary = c.enemies[type_id]
	var t := _tip(def["name"])
	if u != null:
		t["lines"].append("Health %d/%d, attack %s" % [roundi(u.hp), roundi(u.max_hp), _num(u.attack)])
		if u.den_index >= 0:
			t["lines"].append("Wanders near its den")
	else:
		t["lines"].append("Health %d, attack %s" % [int(def["hp"]), _num(float(def["attack"]))])
	if def.has("shield"):
		t["lines"].append("Shrugs off %d%% of each blow unless it is metal" % roundi(float(def["shield"]) * 100.0))
	if def.has("mail"):
		t["lines"].append("Mail: shrugs off %d%% of each blow unless it is steel" % roundi(float(def["mail"]) * 100.0))
	if def.has("war_chant"):
		t["lines"].append("Hangs back and makes every enemy hit %d%% harder while it lives" % roundi(float(def["war_chant"]) * 100.0))
	var yields: Dictionary = def.get("yields", {})
	if not yields.is_empty():
		t["lines"].append("Carcass gives %s" % _goods(yields))
	t["tags"] = tag_notes(run, "enemy", type_id)
	return t


## Each tag of an entity (see Content.TAG_KINDS) with what it does here,
## e.g. "beast: the hunting lodge pays 3 shells per kill". Tags no rule reads show by name.
static func tag_notes(run: RunState, kind: String, id: String) -> Array[String]:
	var c := run.content
	var out: Array[String] = []
	for tag: String in c.tags_of(kind, id):
		var notes := PackedStringArray()
		if str(c.tags.get(tag, "")) != "":
			notes.append(c.tags[tag])
		for b: String in c.buildings:
			var prize: Dictionary = c.buildings[b].get("prize", {})
			if prize.get("tag", "") == tag:
				var built := run.world.count_buildings(b) > 0
				notes.append("the %s pays %d shells per kill%s" % [c.buildings[b]["name"].to_lower(), int(prize["shells"]), "" if built else " (not built)"])
		out.append(tag if notes.is_empty() else "%s: %s" % [tag, "; ".join(notes)])
	return out


static func building(run: RunState, index: int) -> Dictionary:
	var c := run.content
	var b: Dictionary = run.world.buildings[index]
	var def: Dictionary = c.buildings[b["type"]]
	var t := _tip(def["name"])
	t["lines"].append(def["text"])
	var work_left := float(b["work_left"])
	if work_left > 0.0:
		t["lines"].append("Being built: %d%% done" % roundi(100.0 * (1.0 - work_left / float(def["work"]))))
	if def.has("lodging"):
		var used := 0
		for h in run.living_heroes():
			if run.world.hero_ai.bed_index(h) == index:
				used += 1
		t["lines"].append("Beds: %d of %d taken" % [used, int(def["lodging"]["beds"])])
	if def.has("stall"):
		var kind: String = def["stall"]["sells"]
		var names := PackedStringArray()
		for g: Dictionary in b["goods"]:
			names.append(c.recipe_name(g["recipe"]))
		t["lines"].append("On sale: %s" % (", ".join(names) if not names.is_empty() else "nothing"))
		t["lines"].append("Price: %s" % str(run.prices.get(kind, "fair")).capitalize())
	if def.has("workshop") and b["craft"] != "":
		t["lines"].append("Making: %s" % c.recipe_name(b["craft"]))
	if def.has("gate_hp") and work_left <= 0.0:
		var whole := run.world.town.gate_health(index)
		t["lines"].append("Health %d%%. Mended to full each dawn." % roundi(100.0 * whole) if whole > 0.0 else "Broken through! Mended at dawn.")
	t["warnings"] = warnings(run, b["type"])
	return t


## Problems with a building type the player can fix by ordering something else.
static func warnings(run: RunState, type: String) -> Array[String]:
	var c := run.content
	var def: Dictionary = c.buildings[type]
	var out: Array[String] = []
	if def.has("stall"):
		var makers := suppliers(c, def["stall"]["sells"])
		if not makers.is_empty() and not makers.any(func(m: String) -> bool: return run.world.count_buildings(m, false) > 0):
			out.append("Nothing supplies this stall: build a %s." % " or ".join(PackedStringArray(makers.map(
				func(m: String) -> String: return c.buildings[m]["name"].to_lower()))))
	if def.has("workshop"):
		var sells := PackedStringArray()
		for id in c.recipes_for(type):
			var kind: String = c.market["recipes"][id].get("stall", "")
			if kind != "" and not sells.has(kind):
				sells.append(kind)
		if not sells.is_empty() and not Array(sells).any(func(k: String) -> bool: return _has_stall(run, k)):
			out.append("No stall sells what this makes: build a %s." % " or ".join(PackedStringArray(Array(sells).map(
				func(k: String) -> String: return _stall_name(c, k).to_lower()))))
	return out


## Workshop types whose recipes go to a kind of stall, e.g. "hides" -> [hide_rack].
static func suppliers(c: Content, kind: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in c.market["recipes"]:
		var r: Dictionary = c.market["recipes"][id]
		if r.get("stall", "") == kind and not out.has(r["workshop"]):
			out.append(r["workshop"])
	return out


static func _has_stall(run: RunState, kind: String) -> bool:
	for type: String in run.content.buildings:
		if run.content.buildings[type].get("stall", {}).get("sells", "") == kind and run.world.count_buildings(type, false) > 0:
			return true
	return false


static func _stall_name(c: Content, kind: String) -> String:
	for type: String in c.buildings:
		if c.buildings[type].get("stall", {}).get("sells", "") == kind:
			return c.buildings[type]["name"]
	return kind


static func node(run: RunState, n: Dictionary) -> Dictionary:
	var c := run.content
	var def: Dictionary = c.world["nodes"][n["type"]]
	var t := _tip(def["name"])
	t["lines"].append("%d of %d %s left" % [int(n["amount"]), int(n["max"]), n["gives"]])
	if n["heroes_only"] or n["wild"]:
		var buyer: String = def.get("buyer", "")
		var sold := " and sell it to the %s for %d shells each" % [c.buildings[buyer]["name"].to_lower(), int(def["price"])] if buyer != "" else ""
		t["lines"].append("Heroes fetch it%s" % sold)
	if n["wild"]:
		t["lines"].append("Townsfolk only go once no monster is near")
	elif not n["heroes_only"]:
		t["lines"].append("Townsfolk gather it")
	return t


static func den(run: RunState, d: Dictionary) -> Dictionary:
	var c := run.content
	var t := enemy(run, d["spawns"])
	var spawn_name: String = t["title"]
	t["title"] = c.world["dens"][d["type"]]["name"]
	t["lines"].insert(0, "Sends out %s. Hero territory: heroes hunt here for loot and XP." % spawn_name.to_lower())
	return t


static func obstacle(run: RunState, id: String) -> Dictionary:
	var def: Dictionary = run.content.town["obstacles"][id]
	var t := _tip(def["name"])
	t["lines"].append(def["text"])
	return t


## A square of ground: a trail, a worn path, a road or a thicket.
static func ground(run: RunState, square: int) -> Dictionary:
	var c := run.content
	var w := run.world
	var g := w.pathing.ground[square]
	var t: Dictionary
	if g >= Pathing.FIRST_ROAD:
		var def := w.town.road_def(g)
		t = _tip(def["name"])
		t["lines"].append(def["text"])
	elif g == Pathing.PATH or g == Pathing.TRAIL:
		var def: Dictionary = c.town["path" if g == Pathing.PATH else "trail"]
		t = _tip(def["name"])
		t["lines"].append(def["text"])
		if g == Pathing.PATH and g < w.town.best_road():
			if w.town.can_pave():
				t["lines"].append("Stone-layers will pave it into a %s if it stays busy." % w.town.road_def(w.town.best_road())["name"].to_lower())
			else:
				t["lines"].append("A %s would pave it." % w.town.paver_name())
	else:
		t = _tip(c.town["thickets"]["name"])
		t["lines"].append(c.town["thickets"]["text"])
	return t


static func hearth(run: RunState) -> Dictionary:
	var t := _tip("Hearth")
	t["lines"].append("Health %d/%d. If it falls, the run is lost." % [roundi(run.world.hearth_hp), roundi(run.hearth_max_hp())])
	t["lines"].append("Fuel %d: a cold night hurts everyone and sours heroes' mood." % int(run.stock["fuel"]))
	return t


static func as_text(tip: Dictionary) -> String:
	var parts: Array[String] = [tip["title"]]
	parts.append_array(tip["lines"])
	if not tip["tags"].is_empty():
		parts.append("Tags: " + ", ".join(PackedStringArray(tip["tags"])))
	parts.append_array(tip["warnings"])
	return "\n".join(PackedStringArray(parts))


static func _goods(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in d:
		parts.append("%d %s" % [int(d[k]), k])
	return ", ".join(parts)


static func _num(x: float) -> String:
	return str(roundi(x)) if is_equal_approx(x, roundf(x)) else "%.1f" % x
