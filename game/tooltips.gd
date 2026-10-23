class_name Tooltips
extends RefCounted
## Hover text for things on the map and in the build list. Read-only: it only
## looks at the run, so it can be swapped or restyled without touching the sim.
## Each tip is {"title": String, "lines": Array[String], "tags": Array, "warnings": Array[String]};
## "line_colors" (optional) maps a line's index to its colour, e.g. gear in its rarity's colour.


static func new_tip(title: String) -> Dictionary:
	return {"title": title, "lines": [] as Array[String], "tags": [], "warnings": [] as Array[String], "line_colors": {}}


static func hero(run: RunState, u: Unit) -> Dictionary:
	var c := run.content
	var t := new_tip(u.display_name)
	t["lines"].append("%s %s, level %d" % [c.traits[u.trait_id]["name"], c.hero_classes[u.type_id]["name"].to_lower(), u.level])
	t["lines"].append("Health %d/%d, attack %s" % [roundi(u.hp), roundi(u.max_hp), _num(u.attack)])
	t["lines"].append("Energy %d, mood %d, %d shells, %d kills" % [roundi(u.energy), roundi(u.mood), u.gold, u.kills])
	if u.well_fed:
		t["lines"].append("Well fed: +%d%% XP until dawn" % roundi(c.num("hearty_xp") * 100.0))
	for slot: String in ["weapon", "armor", "charm"]:
		if u.items.has(slot):
			t["lines"].append(gear_line(c, slot, u.items[slot]))
			t["line_colors"][t["lines"].size() - 1] = c.rarity_color(Loot.rarity(c, u.items[slot]))
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


## e.g. "Weapon: keen flint blade (t2), Magic"; white gear leaves its rarity unsaid.
static func gear_line(c: Content, slot: String, item: Dictionary) -> String:
	var rarity := Loot.rarity(c, item)
	return "%s: %s%s" % [slot.capitalize(), Loot.describe(c, item), "" if rarity == "white" else ", " + c.rarity_tier(rarity)["name"]]


static func folk(run: RunState, u: Unit) -> Dictionary:
	var c := run.content
	var def: Dictionary = c.townsfolk[u.type_id]
	var t := new_tip(run.folk_name(u.type_id, u.leaning))
	t["lines"].append(def["text"])
	if u.leaning != "":
		t["lines"].append(def["leanings"][u.leaning]["text"])
		t["lines"].append(band_line(run, u.type_id, u.leaning))
	t["lines"].append("Health %d/%d, attack %s" % [roundi(u.hp), roundi(u.max_hp), _num(u.attack)])
	if u.master_of != "":
		t["lines"].append("Master of the %s (%s): %s." % [c.buildings[u.master_of]["name"].to_lower(),
			run.craft_trait(u)["name"].to_lower(), "; ".join(master_effects(c, u.craft_trait, u.master_of)).to_lower()])
	if u.carry_amount > 0:
		t["lines"].append("Carrying %d %s" % [u.carry_amount, u.carrying])
	if u.intent != "":
		t["lines"].append("Now: %s" % u.intent)
	return t


## How the townsfolk sharing a leaning stand as a band: its tier's bonus and what the next tier needs.
## joining counts one more (a dawn card about to be taken).
static func band_line(run: RunState, role: String, leaning: String, joining := false) -> String:
	var def: Dictionary = run.content.townsfolk[role]
	var tiers: Array = def.get("band_tiers", [])
	if tiers.is_empty():
		return ""
	var lean: Dictionary = def["leanings"][leaning]
	var plural := "%ss" % lean["name"].to_lower()
	var size := int(run.world.folk_ai.count_leanings().get(role + "/" + leaning, 0)) + (1 if joining else 0)
	var goods := " or ".join(lean["goods"]).replace("_", " ")
	var folk_ai := run.world.folk_ai
	var now := folk_ai.tier_for(role, leaning, size)
	var next := {}
	for tier: Dictionary in tiers:
		if size < folk_ai.band_size_needed(role, leaning, tier):
			next = tier
			break
	if now.is_empty():
		return "%d %s%s; %d make a band (%s)." % [size, plural, " with this one" if joining else "",
			folk_ai.band_size_needed(role, leaning, next), band_bonus(now, next, goods)]
	var out := "Band of %d %s: %s." % [size, plural, band_bonus({}, now, goods)]
	if not next.is_empty():
		out += " At %d: %s." % [folk_ai.band_size_needed(role, leaning, next), band_bonus(now, next, goods)]
	return out


## What a band tier gives on top of the one below it, in words.
static func band_bonus(below: Dictionary, tier: Dictionary, goods: String) -> String:
	var parts := PackedStringArray()
	var carry := int(tier.get("carry", 0))
	if carry > int(below.get("carry", 0)):
		parts.append("+%d %s a trip" % [carry, goods])
	var faster := float(tier.get("gather_mult", 0))
	if faster > float(below.get("gather_mult", 0)):
		parts.append("gather %d%% faster" % roundi(faster * 100.0))
	return ", ".join(parts) if not parts.is_empty() else "no change"


## A creature type, with or without a live unit (dens show the type they spawn).
static func enemy(run: RunState, type_id: String, u: Unit = null) -> Dictionary:
	var c := run.content
	var def: Dictionary = c.enemies[type_id]
	var t := new_tip(def["name"])
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
	var t := new_tip(def["name"])
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
	if def.has("tower_hp") and float(b["work_left"]) <= 0.0:
		t["lines"].append("Broken: shoots again once mended at dawn" if float(b["hp"]) <= 0.0 else "Health: %d / %d" % [int(b["hp"]), int(def["tower_hp"])])
	if def.has("stall"):
		var names := PackedStringArray()
		for g: Dictionary in b["goods"]:
			names.append("%s (tier %d)" % [c.recipe_name(g["recipe"]), int(g["tier"])])
		t["lines"].append("On sale (%d of %d): %s" % [names.size(), int(c.market["stall_capacity"]),
			", ".join(names) if not names.is_empty() else "nothing"])
	if def.has("workshop") and b["craft"] != "":
		t["lines"].append("Making: %s" % c.recipe_name(b["craft"]))
	elif def.has("workshop") and work_left <= 0.0:
		t["lines"].append("Idle right now")
	t["lines"].append_array(helper_lines(run, b))
	if def.has("gate_hp") and work_left <= 0.0:
		var whole := run.world.town.gate_health(index)
		t["lines"].append("Health %d%%. Mended to full each dawn." % roundi(100.0 * whole) if whole > 0.0 else "Broken through! Mended at dawn.")
	t["lines"].append_array(combo_lines(run, b["type"], index))
	t["warnings"] = warnings(run, b["type"])
	return t


## Who lends a hand at a building when they have nothing worth fetching ("assist" in buildings.json), and the
## extra food today's helpers have earned it.
static func helper_lines(run: RunState, b: Dictionary) -> Array[String]:
	var c := run.content
	var def: Dictionary = c.buildings[b["type"]]
	var assist: Dictionary = def.get("assist", {})
	var out: Array[String] = []
	if assist.is_empty():
		return out
	var who := PackedStringArray()
	var leanings: Dictionary = c.townsfolk["tribesperson"]["leanings"]
	for l: String in assist.get("leanings", []):
		who.append(String(leanings[l]["name"]).to_lower() + "s")
	who.append("tribespeople with no leaning")
	if def.has("workshop"):
		who.append("craftspeople")
	out.append("Helpers with nothing to fetch: %s (%d at a time)" % [", ".join(who), int(assist.get("hands", 1))])
	if assist.has("food") and float(b["work_left"]) <= 0.0:
		out.append("Helped today: +%d food at dawn (most %d)" % [run.world.folk_ai.assisted_food(b), int(assist["food_max"])])
	return out


## The rows (data/combos.json) a building type can be part of, marking the one building `index` is part of now.
## index -1: a building card, so nothing is active yet.
static func combo_lines(run: RunState, type: String, index := -1) -> Array[String]:
	var c := run.content
	var active: Array[String] = run.world.town.combos_of(index) if index >= 0 else ([] as Array[String])
	var out: Array[String] = []
	for id: String in c.combos:
		var row: Dictionary = c.combos[id]
		if active.has(id):
			out.append("Row: %s: %s" % [row["name"], row["text"]])
		elif row["building"] == type or row["partner"] == type:
			out.append("Ordered with a %s as a drafted %s row, it would make a bonus: %s" % [
				c.buildings[row["partner"] if row["building"] == type else row["building"]]["name"].to_lower(), row["name"], row["text"]])
	return out


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
	var t := new_tip(def["name"])
	t["lines"].append("%d of %d %s left" % [int(n["amount"]), int(n["max"]), n["gives"]])
	if n["heroes_only"] or n["wild"]:
		var buyer: String = def.get("buyer", "")
		var sold := " and sell it to the %s for %d shells each" % [c.buildings[buyer]["name"].to_lower(), int(def["price"])] if buyer != "" else ""
		t["lines"].append("Heroes fetch it%s" % sold)
	if run.world.held_by_camp(n):
		t["lines"].append("Held by the war camp: townsfolk won't gather it until heroes clear the camp")
	elif n["wild"]:
		t["lines"].append("Townsfolk only go once no monster is near")
	elif not n["heroes_only"]:
		t["lines"].append("Townsfolk gather it")
	if run.world.regrows(n):
		t["lines"].append("Regrows %d each dawn" % run.world.node_regrowth(n))
	else:
		t["lines"].append("Never grows back")
	t["tags"] = tag_notes(run, "node", n["type"])
	return t


static func den(run: RunState, d: Dictionary) -> Dictionary:
	var c := run.content
	if d.get("camp", false):
		return war_camp(run, d)
	var t := enemy(run, d["spawns"])
	var spawn_name: String = t["title"]
	t["title"] = c.world["dens"][d["type"]]["name"]
	t["lines"].insert(0, "Sends out %s. Hero territory: heroes hunt here for loot and XP." % spawn_name.to_lower())
	return t


## Ridges and raw rift ground (kind "ridge" or "raw", see "texts" in data/plates.json).
static func earth(run: RunState, kind: String) -> Dictionary:
	var text: Dictionary = run.content.plates["texts"][kind]
	var t := new_tip(text["name"])
	t["lines"].append(text["text"])
	return t


## A seam between two earth plates (an Earth.forecast entry): what kind it is and its ridge, not what comes next.
static func seam(run: RunState, entry: Dictionary) -> Dictionary:
	var earth := run.world.earth
	var ring: Dictionary = earth.rings[int(entry["ring"])]
	var kind: String = ring["kinds"][int(entry["seam"])]
	var text: Dictionary = run.content.plates["texts"][kind]
	var t := new_tip("%s (%s ring)" % [text["name"], String(ring["name"]).to_lower()])
	t["lines"].append(text["text"])
	var ridge := int(ring["ridges"][int(entry["seam"])])
	if ridge > 0:
		t["lines"].append("Its ridge stands %d high." % ridge)
	return t


## The war camp: who is in it, what it holds, and what clearing it pays.
static func war_camp(run: RunState, d: Dictionary) -> Dictionary:
	var c := run.content
	var t := new_tip(c.world["dens"][d["type"]]["name"])
	var counts := {}
	for e in run.world.enemy_ai.camp_raiders():
		counts[e.display_name] = int(counts.get(e.display_name, 0)) + 1
	var names := counts.keys()
	names.sort()
	var who: Array[String] = []
	for n: String in names:
		who.append("%s x%d" % [n, counts[n]])
	t["lines"].append("Raiders the warband held back: %s." % ", ".join(who))
	t["lines"].append("They set on anyone who comes close, and townsfolk won't gather near the camp.")
	t["lines"].append("Clear it for %d shells of plunder; the hero who ends it also finds an item." % [
		int(d["joined"]) * c.int_num("camp_spoils_per_raider")])
	return t


## What a master's craft trait does at their workshop, in numbers against an ordinary craftsperson.
## Gear bonuses only count where the workshop makes gear (a smelter makes metal, not gear).
## short: the terse wording a dawn card has room for.
static func master_effects(c: Content, trait_id: String, workshop: String, short := false) -> Array[String]:
	var t: Dictionary = c.promotions["craftsperson"]["traits"][trait_id]
	var out: Array[String] = []
	var rate := float(t.get("craft_rate", 1.0))
	if rate > 1.0:
		out.append(("%sx speed" if short else "Works %sx as fast there") % _num(rate))
	elif rate < 1.0:
		out.append(("%d%% slower" if short else "Works %d%% slower there") % roundi((1.0 - rate) * 100.0))
	var gear: bool = c.market["recipes"].values().any(func(r: Dictionary) -> bool:
		return r["workshop"] == workshop and r.has("item"))
	if not gear:
		out.append("makes no gear, so only speed counts" if short else
			"The %s makes no gear, so only the speed counts" % c.buildings[workshop]["name"].to_lower())
		return out
	var usual := roundi(float(c.market["affix_chance"]) * 100.0)
	var affix := roundi(float(t.get("affix_chance", 0.0)) * 100.0)
	if affix == 0:
		out.append(("gear never has a trait (usual %d%%)" if short else "Their gear never has a trait (usually %d%%)") % usual)
	elif affix != usual:
		out.append(("%d%% of gear has a trait (usual %d%%)" if short else "%d%% of their gear has a trait (usually %d%%)") % [affix, usual])
	var tier := int(t.get("extra_tier", 0))
	if tier > 0:
		out.append(("gear %d tier better" if short else "Their gear comes out %d tier%s better") % ([tier] if short else [tier, "" if tier == 1 else "s"]))
	return out


## The pedlar's camp: what is left to buy, who guards it, who would walk out to it.
static func pedlar_camp(run: RunState) -> Dictionary:
	var c := run.content
	var camp: Dictionary = run.world.pedlar.camp
	var d: Dictionary = c.pedlars["pedlars"][camp["id"]]
	var t := new_tip("%s's camp" % d["name"])
	var wares: Array[String] = []
	for item: Dictionary in camp["wares"]:
		wares.append("%s, %d shells" % [Loot.describe(c, item), run.world.pedlar.price(item)])
	t["lines"].append("Wares: %s." % ("; ".join(wares) if not wares.is_empty() else "sold out"))
	var guards: Array[String] = []
	for h in run.heroes:
		if h.alive and h.id in camp["guards"]:
			guards.append(h.display_name)
	t["lines"].append("Guarded by %s." % " and ".join(guards) if not guards.is_empty() else "Nobody guards it.")
	t["lines"].append("Health %d / %d. Raiders that come near go for it; if it falls the pedlar flees with the wares." % [
		roundi(float(camp["hp"])), int(c.pedlars["hp"])])
	t["lines"].append("Heroes come out by day to sell loot (the pedlar takes no cut) and buy. It leaves at dusk on the last day.")
	return t


static func obstacle(run: RunState, id: String) -> Dictionary:
	var def: Dictionary = run.content.town["obstacles"][id]
	var t := new_tip(def["name"])
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
		t = new_tip(def["name"])
		t["lines"].append(def["text"])
	elif g == Pathing.PATH or g == Pathing.TRAIL:
		var def: Dictionary = c.town["path" if g == Pathing.PATH else "trail"]
		t = new_tip(def["name"])
		t["lines"].append(def["text"])
		if g == Pathing.PATH and g < w.town.best_road():
			if w.town.can_pave():
				t["lines"].append("Stone-layers will pave it into a %s if it stays busy." % w.town.road_def(w.town.best_road())["name"].to_lower())
			else:
				t["lines"].append("A %s would pave it." % w.town.paver_name())
	else:
		t = new_tip(c.town["thickets"]["name"])
		t["lines"].append(c.town["thickets"]["text"])
	return t


static func hearth(run: RunState) -> Dictionary:
	var t := new_tip("Hearth")
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
