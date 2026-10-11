class_name StatusText
extends RefCounted
## The screen's live text (BBCode), built from the run: the status block, the
## clock line, the heroes list, the market and the relics. Read-only, like
## Tooltips, so wording and layout can change without touching the sim.

const RESOURCE_COLORS := {"food": "#d98aa8", "fuel": "#e0b050", "wood": "#7fbf6a", "stone": "#b0b4bc", "shells": "#ffd24a",
	"flint": "#8fa0b8", "hides": "#c09060", "bone": "#e0d8c0", "obsidian": "#b08ad8",
	"copper": "#d08850", "cassiterite": "#9a9090", "tin": "#c8d0d8", "bronze": "#e0a860"}
## Shown in the stock line from the start; later goods appear once you have some.
const STONE_AGE_RESOURCES := ["food", "fuel", "wood", "stone", "shells", "flint", "hides", "bone", "obsidian"]


## Round, seed, age, hearth, stock, people and upkeep, then the fire line.
static func status(run: RunState) -> String:
	var content := run.content
	var w := run.world
	var stock := PackedStringArray()
	for r: String in RunState.RESOURCES:
		if not STONE_AGE_RESOURCES.has(r) and int(run.stock[r]) == 0 and not content.age_reached(run.age, "bronze"):
			continue
		stock.append("[color=%s]%s %d[/color]" % [RESOURCE_COLORS[r], r.capitalize(), run.stock[r]])
	var folk := PackedStringArray()
	for role: String in content.townsfolk:
		folk.append("%s %d" % [content.townsfolk[role]["name"], run.count_role(role)])
	var text := "[b]Round %d / %d[/b]   Seed %d   %s\nHearth: %d / %d HP\n%s\nPeople %d / %d housing  (%s, heroes %d)\nUpkeep: %d food per day, %d fuel per night" % [
		run.round_number, content.int_num("rounds_to_win"), run.run_seed, content.age_name(run.age), maxi(0, int(w.hearth_hp)), int(run.hearth_max_hp()),
		"  ".join(stock), run.population(), run.housing(), ", ".join(folk), run.living_heroes().size(),
		food_per_day(run), run.fuel_needed_tonight()]
	return text + "\n" + fuel_line(run)


## Fuel in reserve against the nightly burn: one block per night it will last (up to 8).
static func fuel_line(run: RunState) -> String:
	var burn := run.fuel_needed_tonight()
	var fuel: int = run.stock["fuel"]
	if burn <= 0:
		return "Fire: burns nothing tonight"
	var nights := float(fuel) / burn
	var color := "#e05050" if nights < 1.0 else ("#e0a050" if nights < 2.0 else "#e0b050")
	var blocks := mini(8, int(nights))
	var bar := "█".repeat(blocks) + "░".repeat(8 - blocks)
	var spare_wood := "" if nights >= 1.0 or not run.content.balance.get("wood_burns_as_fuel", false) else ", then wood"
	return "Fire: [color=%s]%s[/color] %d fuel, burns %d a night, lasts %s%s" % [color, bar, fuel, burn,
		"%d nights" % int(nights) if nights >= 1.0 else "less than a night", spare_wood]


static func food_per_day(run: RunState) -> int:
	return maxi(0, int(ceil(run.population() * run.content.num("food_per_person_per_day") * (1.0 - 0.25 * run.world.count_buildings("drying_rack")))))


## The line above the map: build phase, or day/night, the warned attack and a cold night.
static func clock(run: RunState) -> String:
	var content := run.content
	var w := run.world
	if run.phase == RunState.Phase.BUILD:
		return "[b]Build[/b]: order buildings, then begin the round."
	var night := w.is_night()
	var wave_night := w.day_index() == content.int_num("days_per_round") - 1
	var text := "[b]Day %d / %d[/b]  %s%s" % [w.day_index() + 1, content.int_num("days_per_round"),
		"[color=#8fa8ff]Night[/color]" if night else ("[color=#e0a050]Dusk[/color]" if w.is_dusk() else "[color=#ffe08a]Day[/color]"),
		("   [color=#ff7060]Attack tonight from the %s[/color]" % " and ".join(w.side_names())) if wave_night and not w.wave_spawned else ""]
	if w.wave_spawned:
		var left := w.enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index < 0).size()
		text += "   [color=#ff7060]Attackers left: %d[/color]" % left
	if w.cold_tonight:
		text += "   [color=#8fd0ff]No fuel: a cold night[/color]"
	return text


## Every hero with stats, bed, whim, gear and intent; the fallen and departed; townsfolk of note.
static func heroes(run: RunState) -> String:
	var content := run.content
	var w := run.world
	var text := ""
	for hero in run.heroes:
		var c: Dictionary = content.hero_classes[hero.type_id]
		var name_color: String = c["color"] if hero.alive else "#666666"
		var energy_color := "#7fd0ff" if hero.energy > 40.0 else ("#e0a050" if hero.energy > 0.0 else "#e05050")
		var mood_color := "#a8d890" if hero.mood > content.num("mood_grumble_at") else ("#e0a050" if hero.mood > content.num("mood_leave_at") else "#e05050")
		text += "[color=%s][b]%s[/b][/color] %s %s  Lv%d  HP %d/%d  [color=%s]Energy %d[/color]  [color=%s]Mood %d[/color]  %d shells  kills %d%s\n" % [
			name_color, hero.display_name, content.traits[hero.trait_id]["name"], c["name"], hero.level,
			int(hero.hp), int(hero.max_hp), energy_color, int(hero.energy), mood_color, int(hero.mood), hero.gold, hero.kills,
			"" if hero.alive else "  [color=#e05050]fallen[/color]"]
		if not hero.alive:
			continue
		var whim: String = content.whims.get(hero.whim, {}).get("name", "")
		var bed := "No bed: sleeps by the hearth" if hero.lodging < 0 else "Sleeps in %s%s" % [w.hero_ai.bed_name(hero.lodging),
			"" if w.hero_ai.is_preferred(hero, hero.lodging) else " (not their favourite)"]
		text += "    [color=#9aa]%s%s[/color]\n" % [bed,
			("  ·  today: " + whim) if whim != "" and run.phase != RunState.Phase.BUILD else ""]
		var gear := PackedStringArray()
		for slot: String in Loot.SLOTS:
			if hero.items.has(slot):
				gear.append(Loot.describe(content, hero.items[slot]))
		var pack := PackedStringArray()
		for id in hero.pack:
			pack.append(content.recipe_name(id))
		if not gear.is_empty() or not hero.spares.is_empty() or not pack.is_empty():
			text += "    [color=#c8b88a]%s%s%s[/color]\n" % [", ".join(gear) if not gear.is_empty() else "no gear",
				"  ·  %d to sell" % hero.spares.size() if not hero.spares.is_empty() else "",
				"  ·  pack: " + ", ".join(pack) if not pack.is_empty() else ""]
		if hero.intent != "" and run.phase == RunState.Phase.SIM:
			text += "    [color=#9aa]%s[/color]\n" % hero.intent
	for hero in run.fallen:
		text += "[color=#666666]%s (fallen)[/color]\n" % hero.display_name
	for hero in run.departed:
		text += "[color=#666666]%s (left, unhappy)[/color]\n" % hero.display_name
	var named := PackedStringArray()
	for u in w.folk:
		if u.master_of != "":
			named.append("%s, %s master of the %s (made %d)" % [u.display_name, run.craft_trait(u)["name"].to_lower(),
				content.buildings[u.master_of]["name"].to_lower(), int(u.made.get(u.master_of, 0))])
		elif u.type_id == "warrior" and u.kills >= int(content.promotions["warrior"]["kills"]):
			named.append("a veteran warrior (%d kills) is ready for promotion" % u.kills)
	if not named.is_empty():
		text += "[color=#c8b88a]Townsfolk of note: %s[/color]\n" % "; ".join(named)
	return text


## What the stalls hold and what the workshops are making ("" before there is a market).
static func market(run: RunState) -> String:
	var content := run.content
	var w := run.world
	var lines := PackedStringArray()
	for b in w.buildings:
		var def: Dictionary = content.buildings[b["type"]]
		if float(b["work_left"]) > 0.0:
			continue
		if def.has("stall"):
			var kind: String = def["stall"]["sells"]
			var goods := PackedStringArray()
			for g: Dictionary in b["goods"]:
				goods.append("%s t%d (%d)" % [content.recipe_name(g["recipe"]), int(g["tier"]), run.price_of(g)])
			lines.append("[color=#ffd24a]%s[/color] %s, %d/%d: %s" % [def["name"], run.prices[kind].capitalize(), b["goods"].size(),
				content.market["stall_capacity"], ", ".join(goods) if not goods.is_empty() else "[color=#888]empty[/color]"])
		elif def.has("workshop"):
			var doing := "making a %s" % content.recipe_name(b["craft"]) if b["craft"] != "" else "[color=#888]idle[/color]"
			var why := ""
			if b["craft"] == "":
				var kinds := PackedStringArray()
				for id in content.recipes_for(b["type"]):
					var k: String = content.market["recipes"][id]["stall"]
					if w.market.stall_index(k) < 0 and not kinds.has(content.market["stall_names"][k]):
						kinds.append(content.market["stall_names"][k])
				why = " (no %s stall)" % "/".join(kinds) if not kinds.is_empty() else ""
			lines.append("%s: %s%s" % [def["name"], doing, why])
	if lines.is_empty():
		return ""
	return "[b]Market[/b]\n" + "\n".join(lines)


static func relics(run: RunState) -> String:
	var content := run.content
	var text := "[b]Relics[/b]\n"
	if run.relics.is_empty():
		text += "[color=#888]none yet[/color]"
	for id in run.relics:
		text += "[hint=%s]%s[/hint]\n" % [content.relics[id]["text"], content.relics[id]["name"]]
	return text
