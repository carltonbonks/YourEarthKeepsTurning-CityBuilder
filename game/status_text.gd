class_name StatusText
extends RefCounted
## The screen's live text, built from the run: the top bar's short chips (BBCode) and the hover cards
## behind them (Tooltips-style dictionaries), plus the clock line. Read-only, like Tooltips, so wording
## and layout can change without touching the sim. The bar stays short; detail is in the hover cards.

const RESOURCE_COLORS := {"food": "#d98aa8", "fuel": "#e0b050", "wood": "#7fbf6a", "stone": "#b0b4bc", "shells": "#ffd24a",
	"flint": "#8fa0b8", "hides": "#c09060", "bone": "#e0d8c0", "obsidian": "#b08ad8",
	"copper": "#d08850", "cassiterite": "#9a9090", "tin": "#c8d0d8", "bronze": "#e0a860",
	"bog_iron": "#8a6a4a", "charcoal": "#6a6a6a", "iron": "#a0a8b0", "steel": "#d0d8e8"}
## Goods of a later age: listed once the town reaches that age or has some.
const RESOURCE_AGE := {"copper": "bronze", "cassiterite": "bronze", "tin": "bronze", "bronze": "bronze",
	"bog_iron": "medieval", "charcoal": "medieval", "iron": "medieval", "steel": "medieval"}
## Goods always shown on the bar: what building cards cost. Everything else is in the hover card.
const BAR_GOODS := ["wood", "stone", "shells"]
const RED := "#e05050"
const AMBER := "#e0a050"
## The top bar's chips, left to right.
const CHIPS := ["round", "hearth", "people", "food", "fuel", "goods", "relics", "paths"]


## The short text of one top-bar chip.
static func chip(run: RunState, id: String) -> String:
	var content := run.content
	match id:
		"round":
			return "[b]Round %d / %d[/b]  %s" % [run.round_number, content.int_num("rounds_to_win"), content.age_name(run.age)]
		"hearth":
			var share := run.world.hearth_hp / maxf(1.0, run.hearth_max_hp())
			return "Hearth [color=%s]%d / %d[/color]" % [RED if share < 0.35 else (AMBER if share < 0.7 else "#e8e8e8"),
				maxi(0, int(run.world.hearth_hp)), int(run.hearth_max_hp())]
		"people":
			var full := run.population() >= run.housing()
			return "People [color=%s]%d / %d[/color]" % [AMBER if full else "#e8e8e8", run.population(), run.housing()]
		"food":
			var days := food_days(run)
			return "[color=%s]Food %d[/color]  %s" % [RESOURCE_COLORS["food"], run.stock["food"], _lasts(days, "day")]
		"fuel":
			var nights := fuel_nights(run)
			return "[color=%s]Fuel %d[/color]  %s" % [RESOURCE_COLORS["fuel"], run.stock["fuel"], _lasts(nights, "night")]
		"goods":
			var parts := PackedStringArray()
			for r: String in bar_goods(run):
				parts.append("[color=%s]%s %d[/color]" % [RESOURCE_COLORS[r], r.capitalize(), run.stock[r]])
			var more := _listed_goods(run).filter(func(r: String) -> bool: return not BAR_GOODS.has(r) and r != "food" and r != "fuel").size()
			return "  ".join(parts) + ("  [color=#9aa]+%d more[/color]" % more if more > 0 and run.round_number >= 2 else "")
		"relics":
			return "Relics %d" % run.relics.size()
		"paths":
			return "  ".join(path_names(run))
	return ""


## The town's paths as short names with their tier, e.g. ["Heroes I", "Trade I"], in id order.
static func path_names(run: RunState) -> PackedStringArray:
	var out := PackedStringArray()
	var ids := run.paths.keys()
	ids.sort()
	for id: String in ids:
		out.append("%s %s" % [run.content.paths["paths"][id]["name"], roman(run.path_tier(id))])
	return out


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV"][clampi(n, 0, 4)]


## Whether a top-bar chip shows yet. The bar grows with the town (Yusuf, 2026-10-26): relics from the first one or
## round 2 on; everything else from the start.
static func chip_shown(run: RunState, id: String) -> bool:
	if id == "relics":
		return run.round_number >= 2 or not run.relics.is_empty()
	if id == "paths":
		return not run.paths.is_empty() or not run.guilds.is_empty()
	return true


## The goods on the bar: wood and stone always, shells once they matter (round 2 on, a dawn card that costs them, or
## a draft that can be rerolled for them). The rest are in the hover card, counted as "+N more" from round 2.
static func bar_goods(run: RunState) -> Array[String]:
	var out: Array[String] = []
	for r: String in BAR_GOODS:
		if r != "shells" or run.round_number >= 2 or run.pick_offer.any(func(c: Dictionary) -> bool: return int(c.get("cost", 0)) > 0) \
				or (run.phase == RunState.Phase.BUILD and run.hand.picks > 0 and not run.gentle):
			out.append(r)
	return out


## The hover card behind one top-bar chip.
static func chip_tip(run: RunState, id: String) -> Dictionary:
	var content := run.content
	match id:
		"round":
			var t := Tooltips.new_tip("Round %d of %d" % [run.round_number, content.int_num("rounds_to_win")])
			t["lines"].append("Survive the night-3 attack of every round to win.")
			t["lines"].append("Age: %s." % content.age_name(run.age))
			t["lines"].append("Seed %d (Esc menu: replay it or start another)." % run.run_seed)
			return t
		"hearth":
			var t := Tooltips.hearth(run)
			t["lines"].append_array(path_lines(run))
			return t
		"people":
			var t := Tooltips.new_tip("People %d, beds for %d" % [run.population(), run.housing()])
			for role: String in content.townsfolk:
				t["lines"].append("%s: %d" % [content.townsfolk[role]["name"], run.count_role(role)])
			t["lines"].append("Heroes: %d (they sleep in lodgings, not homes)" % run.living_heroes().size())
			for line in notable_folk(run):
				t["lines"].append(line)
			if run.population() >= run.housing():
				t["warnings"].append("Every bed is full: nobody new can join until you build homes.")
			return t
		"food":
			var t := Tooltips.new_tip("Food")
			t["lines"].append(food_line(run))
			if food_days(run) >= 0.0 and food_days(run) < 1.0:
				t["warnings"].append("Short for the next dawn: gather more or someone leaves.")
			return t
		"fuel":
			var t := Tooltips.new_tip("Fuel")
			t["lines"].append(fuel_line(run))
			if fuel_nights(run) >= 0.0 and fuel_nights(run) < 1.0:
				t["warnings"].append("Not enough for tonight: a cold night hurts everyone and sours heroes' mood.")
			return t
		"goods":
			var t := Tooltips.new_tip("Stock")
			for r: String in _listed_goods(run):
				if r != "food" and r != "fuel":
					t["lines"].append("%s: %d" % [r.capitalize().replace("_", " "), run.stock[r]])
			return t
		"relics":
			var t := Tooltips.new_tip("Relics")
			if run.relics.is_empty():
				t["lines"].append("None yet. Survive a round to pick one.")
			for rid in run.relics:
				t["lines"].append("%s: %s" % [content.relics[rid]["name"], content.relics[rid]["text"]])
				t["line_colors"][t["lines"].size() - 1] = content.rarity_color(content.rarity_of("relic", rid))
			return t
		"paths":
			var t := Tooltips.new_tip("Your paths")
			var ids := run.paths.keys()
			ids.sort()
			for pid: String in ids:
				var path: Dictionary = content.paths["paths"][pid]
				for i in run.path_tier(pid):
					t["lines"].append("%s %s: %s" % [path["name"], roman(i + 1), path["tiers"][i]["text"]])
			for leaning: String in run.guilds:
				var g: Dictionary = run.people.guild_def(leaning)
				t["lines"].append("%s (%s): %s" % [g["name"], g["practice"].to_lower(), g["text"]])
			t["lines"].append("Each age-up brings a charter: one more path, or the next tier of one you hold.")
			return t
	return {}


## Every good worth listing: the town has some, or its age makes it.
static func _listed_goods(run: RunState) -> Array[String]:
	var out: Array[String] = []
	for r: String in RunState.RESOURCES:
		if int(run.stock[r]) != 0 or run.content.age_reached(run.age, RESOURCE_AGE.get(r, "")):
			out.append(r)
	return out


static func _lasts(amount: float, unit: String) -> String:
	if amount < 0.0:
		return "[color=#a8d890]growing[/color]" if unit == "day" else "[color=#9aa]no burn[/color]"
	if amount < 1.0:
		return "[color=%s]runs out %s[/color]" % [RED, "tonight" if unit == "night" else "at dawn"]
	var n := int(amount)
	var count := "8+ %ss" % unit if n > 8 else "%d %s%s" % [n, unit, "" if n == 1 else "s"]
	return "[color=%s]%s[/color]" % [AMBER if amount < 2.0 else "#c8c8c8", count]


## How many dawns the food lasts at today's rate (-1 if gardens and fields outgrow what is eaten).
static func food_days(run: RunState) -> float:
	var net := run.food_needed_today() - run.food_grown_daily()
	return -1.0 if net <= 0 else float(run.stock["food"]) / net


## How many nights the fuel lasts at tonight's burn (-1 if the fire burns nothing).
static func fuel_nights(run: RunState) -> float:
	var burn := run.fuel_needed_tonight()
	return -1.0 if burn <= 0 else float(run.stock["fuel"]) / burn


## Fuel in reserve against the nightly burn, in a sentence.
static func fuel_line(run: RunState) -> String:
	var burn := run.fuel_needed_tonight()
	var fuel: int = run.stock["fuel"]
	if burn <= 0:
		return "%d fuel. The fire burns nothing tonight." % fuel
	var nights := float(fuel) / burn
	var spare_wood := "" if nights >= 1.0 or not run.content.balance.get("wood_burns_as_fuel", false) else ", then wood"
	return "%d fuel. The fire burns %d a night, so it lasts %s%s." % [fuel, burn,
		"%d nights" % int(nights) if nights >= 1.0 else "less than a night", spare_wood]


## Food in store against the dawn meal (everyone eats, heroes too), in a sentence.
static func food_line(run: RunState) -> String:
	var eat := run.food_needed_today()
	var grown := run.food_grown_daily()
	var food: int = run.stock["food"]
	var who := "%d townsfolk and %d heroes" % [run.world.folk.size(), run.living_heroes().size()]
	var garden := " Gardens and fields bring %d." % grown if grown > 0 else ""
	var days := food_days(run)
	if days < 0.0:
		return "%d food. Each dawn %s eat %d.%s It keeps growing." % [food, who, eat, garden]
	return "%d food. Each dawn %s eat %d.%s It lasts %s." % [food, who, eat, garden,
		"%d days" % int(days) if days >= 1.0 else "less than a day"]


## How far the desire paths have worn in, what has been paved, and the gates.
static func path_lines(run: RunState) -> Array[String]:
	var town := run.world.town
	var pathing := run.world.pathing
	var parts := PackedStringArray()
	parts.append("%d paces of trail" % pathing.count_ground(Pathing.TRAIL))
	parts.append("%d of worn path" % pathing.count_ground(Pathing.PATH))
	var paved := town.paved_counts()
	for id: String in paved:
		parts.append("%d of %s" % [paved[id], run.content.town["roads"][id]["name"].to_lower()])
	var out: Array[String] = ["Paths: " + ", ".join(parts) + "."]
	var gates := town.gate_counts()
	if gates["built"] > 0:
		out.append("Gates: %d." % gates["built"])
	return out


## Townsfolk who stand out: named masters and warriors ready for promotion.
static func notable_folk(run: RunState) -> Array[String]:
	var content := run.content
	var out: Array[String] = []
	for u in run.world.folk:
		if u.master_of != "":
			out.append("%s, %s master of the %s (made %d)" % [u.display_name, run.craft_trait(u)["name"].to_lower(),
				content.buildings[u.master_of]["name"].to_lower(), int(u.made.get(u.master_of, 0))])
		elif u.type_id == "warrior" and u.kills >= int(content.promotions["warrior"]["kills"]):
			out.append("A veteran warrior (%d kills) is ready for promotion" % u.kills)
	return out


## The heroes no longer in town, for the "lost" chip's hover card.
static func lost_heroes_tip(run: RunState) -> Dictionary:
	var t := Tooltips.new_tip("Heroes lost")
	for hero in run.fallen:
		t["lines"].append("%s (fallen)" % hero.display_name)
	for hero in run.departed:
		t["lines"].append("%s (left, unhappy)" % hero.display_name)
	return t


## The clock beside the bar: build phase, or day/night, the warned attack and a cold night.
static func clock(run: RunState) -> String:
	var content := run.content
	var w := run.world
	if run.phase == RunState.Phase.BUILD:
		return "[b]Build[/b]: draft a blueprint, order from the cards, then begin the round" if run.hand.picks > 0 \
			else "[b]Build[/b]: order from the cards, then begin the round"
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
