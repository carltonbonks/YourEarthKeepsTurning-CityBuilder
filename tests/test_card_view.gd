extends TestCase
## The one card look (game/card_view.gd): the frame shows the roll, plaques show the modifiers, an orange
## modifier shows its price apart, and the rarity colours stay on the card's frame and plaques.


func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)


func test_every_modifier_has_its_few_words_for_the_plaque() -> void:
	var c := Content.load_default()
	for id: String in c.card_mods:
		check(str(c.card_mods[id].get("short", "")) != "", "%s has a short line" % id)
		if c.card_mods[id]["rarity"] == "orange" and not id in ["legend", "exile"]:
			check(CardView.split_price(c.card_mods[id]["text"])[1] != "", "%s reads gift, but price" % id)
	for id: String in c.marks:
		check(str(c.marks[id].get("short", "")) != "", "mark %s has a short line" % id)


func test_a_rolled_card_shows_its_roll_and_modifiers() -> void:
	var c := Content.load_default()
	var card := CardView.new(CardView.Size.LARGE, "folk", "Tribesperson", "Forager")
	var mods: Array[String] = ["nimble", "twins"]
	card.set_roll(c, "yellow", "white", mods)
	var texts := _texts(card)
	check(texts.has("Nimble") and texts.has("Twins"), "each modifier is a plaque by name")
	check(texts.has(c.marks["nimble"]["short"]), "with its few words")
	var frame := card.get_theme_stylebox("normal") as StyleBoxFlat
	check_eq(frame.border_color, c.rarity_color("yellow"), "the frame is the roll's colour")
	check(frame.border_width_left > 1, "and heavier than a plain card's")
	check(card.roll_line().begins_with("Powerful card"), "the hover panel names the roll")
	var tip := card._make_custom_tooltip("More detail") as Control
	var tip_texts := _texts(tip)
	check(tip_texts.has("Nimble: " + c.marks["nimble"]["text"]), "the hover panel has each modifier in full")
	check(tip_texts.has("More detail"), "and the card's own detail")
	tip.free()
	card.free()


func test_an_orange_card_shows_the_price_apart() -> void:
	var c := Content.load_default()
	var card := CardView.new(CardView.Size.LARGE, "folk", "Tribesperson", "Woodcutter")
	var mods: Array[String] = ["many_mother"]
	card.set_roll(c, "orange", "white", mods)
	check(_texts(card).has("She eats for two"), "the price has its own line")
	var tip := card._make_custom_tooltip("") as Control
	check(_texts(tip).has("Price: she eats for two"), "and the hover panel calls it the price")
	tip.free()
	card.free()


func test_small_cards_show_pips_not_plaques_and_no_gem() -> void:
	var c := Content.load_default()
	var card := CardView.new(CardView.Size.SMALL, "building", "Blueprint", "Hide rack")
	var mods: Array[String] = ["thrifty"]
	card.set_roll(c, "blue", "yellow", mods)
	check(not _texts(card).has("Thrifty"), "a small card keeps its modifiers for the hover panel")
	var icons := card.find_children("*", "CardIcon", true, false).map(func(i: CardIcon) -> String: return i.icon)
	check(icons.has("diamond"), "the roll shows as a pip")
	check(not icons.has("gem"), "small cards drop the kind's gem")
	var big := CardView.new(CardView.Size.MEDIUM, "building", "New building", "Hide rack")
	big.set_roll(c, "white", "yellow", [] as Array[String])
	check(big.find_children("*", "CardIcon", true, false).any(func(i: CardIcon) -> bool: return i.icon == "gem"),
		"a medium card shows how rare its kind is with a gem")
	card.free()
	big.free()


func test_the_price_goes_red_where_the_town_is_short() -> void:
	var card := CardView.new(CardView.Size.MEDIUM, "building", "New building", "Hut")
	card.set_price({"wood": 3, "stone": 9}, {"wood": 8, "stone": 4})
	var labels := card.find_children("*", "Label", true, false)
	var wood: Label = labels.filter(func(l: Label) -> bool: return l.text == "8")[0]
	var stone: Label = labels.filter(func(l: Label) -> bool: return l.text == "4")[0]
	check_eq(wood.get_theme_color("font_color"), CardView.DANGER, "short wood is red")
	check_eq(stone.get_theme_color("font_color"), CardView.TEXT, "stone the town has is plain")
	card.free()


func test_family_colours_never_borrow_a_rarity_colour() -> void:
	var c := Content.load_default()
	for fam: String in CardView.FAMILIES:
		var tint := Color(CardView.FAMILIES[fam]["color"])
		for r: String in ["blue", "yellow", "orange"]:
			var rc := c.rarity_color(r)
			var gap := absf(tint.h - rc.h) * 2.0 + absf(tint.s - rc.s) + absf(tint.v - rc.v)
			check(gap > 0.25, "the %s band is not %s" % [fam, r])
	check(UiKit.RECOMMEND_COLOR.s < 0.2, "advice is bone, not gold")


## Cards measure their text only on screen, so how a crowded card gives up body lines is checked in the screenshots.
func test_cards_of_a_size_share_one_shape() -> void:
	var c := Content.load_default()
	for sz: int in CardView.SHAPE:
		var card := CardView.new(sz, "folk", "Tribesperson", "A much longer name than most")
		var mods: Array[String] = ["nimble", "twins"]
		card.set_roll(c, "yellow", "white", mods)
		card.set_body("A body long enough to wrap over several lines on any card, and then a little more.")
		check_eq(card.custom_minimum_size, CardView.SHAPE[sz], "size %d starts at its shape" % sz)
		card.free()
	for sz: int in [CardView.Size.LARGE, CardView.Size.MEDIUM]:
		var shape: Vector2 = CardView.SHAPE[sz]
		check(is_equal_approx(shape.x / shape.y, 0.75), "size %d is 3:4" % sz)
	check(CardView.SHAPE[CardView.Size.SMALL].y < CardView.SHAPE[CardView.Size.SMALL].x / 0.75, "small cards are squatter")
	check_eq(BuildHandView.HAND_HEIGHT, CardView.SHAPE[CardView.Size.SMALL].y, "the hand keeps room for exactly one small card")


func test_spoils_say_their_total_not_a_rate() -> void:
	# Playtest 2026-10-25: "2 food per beast" and "8 came" made the player multiply.
	var c := Content.load_default()
	check_eq(Overlays.spoils_line(c, {"food": 16}, 8, "beast"), "You get 16 food now, from the 8 beasts that came.", "one good")
	check_eq(Overlays.spoils_line(c, {"shells": 28, "wood": 7}, 1, "human"), "You get 28 shells and 7 wood now, from the 1 raider that came.",
		"two goods, one foe")
	check_eq(Overlays.spoils_line(c, {}, 3, "human"), "", "spoils that bring no goods say nothing")


func test_a_trade_card_reads_pay_then_get() -> void:
	var card := CardView.new(CardView.Size.SMALL, "trade", "Caravan", "Bundle of tin")
	card.add_ledger_line("Pay", {"shells": 30}, CardView.TEXT, {"shells": 10})
	card.add_ledger_line("Get", {"tin": 5}, CardView.GOOD)
	var texts := _texts(card)
	check(texts.has("Pay") and texts.has("30 shells") and texts.has("Get") and texts.has("5 tin"), "both sides are named in words")
	var labels := card.find_children("*", "Label", true, false)
	var price: Label = labels.filter(func(l: Label) -> bool: return l.text == "30 shells")[0]
	check_eq(price.get_theme_color("font_color"), CardView.DANGER, "a price the town can't pay is red")
	var cursed := CardView.new(CardView.Size.SMALL, "trade", "Caravan", "Tin by the cartload")
	cursed.add_ledger_line("Pay", {}, CardView.TEXT, {}, ["a hero turns greedy for good"] as Array[String])
	check(_texts(cursed).has("a hero turns greedy for good") and not _texts(cursed).has("nothing"), "a free but cursed deal names its real price")
	card.free()
	cursed.free()


func test_the_hover_panel_puts_the_cards_own_words_first_and_brightest() -> void:
	var parts := CardView.tip_parts("Draft it: every hunting lodge is changed.\nThe lodge's warden keeps the wild.\n\nDawn: hunters", "The lodge's warden keeps the wild.")
	check_eq(parts[0], ["The lodge's warden keeps the wild."], "the card's own line leads")
	check_eq(parts[1], ["Draft it: every hunting lodge is changed.", "Dawn: hunters"], "the general lines follow, blanks dropped")
	check_eq(CardView.tip_parts("Bram, bold warrior\nHealth 40", "")[0], ["Bram, bold warrior"], "with no body the first line leads")
	check_eq(CardView.tip_parts("Eats 1 food\nForager.\nDoll: a twin", "Forager.\nDoll: a twin")[0], ["Forager.", "Doll: a twin"], "added lead lines lead too")
	var card := CardView.new(CardView.Size.MEDIUM, "building", "Upgrade", "Game warden")
	card.set_body("The lodge's warden keeps the wild.")
	var tip := card._make_custom_tooltip("Draft it: every hunting lodge is changed.\nThe lodge's warden keeps the wild.") as Control
	var labels := tip.find_children("*", "Label", true, false)
	var own: Label = labels.filter(func(l: Label) -> bool: return l.text.begins_with("The lodge"))[0]
	var general: Label = labels.filter(func(l: Label) -> bool: return l.text.begins_with("Draft it"))[0]
	check(own.get_index() < general.get_index(), "own words come before the general ones")
	check(own.get_theme_font_size("font_size") > general.get_theme_font_size("font_size"), "and are larger")
	tip.free()
	card.free()


func test_people_on_a_card_are_counted_when_more_than_one() -> void:
	var one := CardView.new(CardView.Size.LARGE, "folk", "Townsperson", "Tribesperson")
	one.add_people(["tribesperson"])
	check(not _texts(one).has("×1"), "one person needs no count")
	var three := CardView.new(CardView.Size.LARGE, "folk", "Townsperson", "Tribesperson")
	three.add_people(["tribesperson", "tribesperson", "tribesperson"])
	check(_texts(three).has("×3"), "more than one person is counted")
	one.free()
	three.free()


func test_a_named_relic_shows_in_its_colour_in_the_hover_panel() -> void:
	var card := CardView.new(CardView.Size.LARGE, "folk", "Townsperson", "Tribesperson")
	card.tip_names["Hearth-mother's Doll"] = Color("#f0d040")
	var tip := card._make_custom_tooltip("Gathers.\nHearth-mother's Doll doubles this pick: 4 people in all.") as Control
	var rich := tip.find_children("*", "RichTextLabel", true, false)
	check_eq(rich.size(), 1, "the line naming the relic is coloured")
	check("[color=#f0d040]Hearth-mother's Doll[/color]" in (rich[0] as RichTextLabel).text, "in the relic's colour")
	tip.free()
	card.free()


func test_chips_read_as_labels_with_a_capital() -> void:
	check_eq(CardView.sentence("sells weapons"), "Sells weapons", "a chip's first word takes a capital")
	check_eq(CardView.sentence("→ greedy ranger"), "→ Greedy ranger", "after an arrow too")
	check_eq(CardView.sentence("+16 food"), "+16 food", "a number first keeps the words after it")
	check_eq(CardView.sentence("3 kills"), "3 kills", "")
	var card := CardView.new(CardView.Size.LARGE, "trade", "Pedlar", "Smith")
	card.add_chip("can be lost")
	check(_texts(card).has("Can be lost"), "add_chip applies it")
	card.free()


func test_keys_show_as_their_cap_reads() -> void:
	check_eq(GameSettings.key_name(KEY_BRACKETRIGHT), "]", "a bracket key shows its symbol, not BracketRight")
	check_eq(GameSettings.key_name(KEY_V), "V", "a letter stays a letter")
	check_eq(GameSettings.key_name(KEY_SPACE), "Space", "a named key keeps its name")
