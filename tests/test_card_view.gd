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
