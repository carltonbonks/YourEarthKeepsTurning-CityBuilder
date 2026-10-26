class_name Overlays
extends PanelContainer
## The dimmed pop-ups over the screen: the blueprint draft, the dawn pick and the relic pick (as cards, detail on hover),
## the end of a run, the menu (Esc), the full story log, Run history and the dev tuning panel. Choices go back to the screen
## as signals; nothing here changes the run directly. A pop-up taller or wider than the screen shrinks
## to fit (`_fit_panel`) rather than running off it.

signal pick_taken(index: int)
signal relic_picked(relic_id: String)
## The founding traditions chosen before round 1 ([] for none).
signal traditions_chosen(ids: Array)
## The founding tradition left to chance (RunState.choose_random_tradition).
signal random_tradition_chosen
## The pedlar invited on a pedlar round ("" for none).
signal pedlar_chosen(id: String)
## replay = true restarts on the same seed, false on a new one.
signal new_run_requested(replay: bool)
## Start a new run on this seed (from the menu).
signal seed_run_requested(seed_value: int)
## The menu, log or tuning panel closed: the screen refreshes and shows the right overlay again.
signal closed
## A setting changed on the Settings screen: the screen applies it.
signal settings_changed
## Back to the title screen (from the menu).
signal title_requested
## How to play on the title screen: play the first-run intro again (the tour, the highlights, a gentle start).
signal intro_requested

## The gap kept round a pop-up, and the most it shrinks to fit the screen.
const EDGE := 12.0
const MIN_SCALE := 0.6

var run: RunState
var settings: GameSettings
## A new run opens on "how a round works" before the traditions pick (every run, Yusuf 2026-10-24).
var welcome_pending := false
## How a round works is up (show_welcome).
var showing_welcome := false
## The blueprint draft is up (show_draft); it stays through a show_for_phase while building.
var showing_draft := false
var _box: VBoxContainer
var _panel: PanelContainer


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.45)
	add_theme_stylebox_override("panel", dim)
	# Placed by hand, not by a CenterContainer, so it can be scaled down to fit (containers reset scale).
	var center := Control.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.resized.connect(_fit_panel)
	visibility_changed.connect(_fit_panel)
	add_child(center)
	var panel := PanelContainer.new()
	_panel = panel
	panel.minimum_size_changed.connect(_fit_panel, CONNECT_DEFERRED)
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color("#23262d")
	box_style.border_color = UiKit.HEADING_COLOR
	box_style.set_border_width_all(2)
	box_style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", box_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	margin.add_child(_box)
	hide()


## Where the pop-up is on screen, or an empty rect when none is up.
func panel_rect() -> Rect2:
	return _panel.get_global_rect() if visible else Rect2()


## Centres the pop-up, shrinking it to fit the screen when it is too big (never below MIN_SCALE).
func _fit_panel() -> void:
	var area := (_panel.get_parent() as Control).size
	if area.x <= 0.0:
		return
	_panel.reset_size()
	var want := _panel.size
	var s := clampf(minf((area.x - 2.0 * EDGE) / want.x, (area.y - 2.0 * EDGE) / want.y), MIN_SCALE, 1.0)
	_panel.scale = Vector2(s, s)
	_panel.position = ((area - want * s) * 0.5).floor()


## Shows whatever the run is waiting on (a pick, a relic, the end), or hides.
func show_for_phase() -> void:
	if run.awaiting_traditions():
		if welcome_pending:
			show_welcome(true)
		else:
			show_traditions()
		return
	if run.awaiting_pedlar():
		show_pedlars()
		return
	match run.phase:
		RunState.Phase.PICK:
			show_pick()
		RunState.Phase.RELIC:
			show_relic_pick()
		RunState.Phase.WON, RunState.Phase.LOST:
			show_end()
		_:
			if not (showing_draft and visible and run.phase == RunState.Phase.BUILD):
				hide()


## The round's blueprint draft as a pick the player must answer before building, like the dawn pick:
## no way past it but taking an offer (or rerolling first). The cards come from the hand (BuildHandView),
## so they look and act as they always have; taking one refreshes the screen, which shows the next
## draft or lets the build begin.
func show_draft(hand: BuildHandView) -> void:
	_clear()
	showing_draft = true
	_title(hand.draft_title() + " to start building")
	var sub := UiKit.note(_box, "It joins Your blueprints in the hand and stays on offer for the whole run.", 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.tooltip_text = BuildHandView.pool_line(run)
	sub.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	hand.fill_draft(row)
	# Hovering an upgrade lights its buildings on the map (UpgradeGlow); the pop-up turns see-through meanwhile,
	# all but that card, so the town shows past it.
	for card in row.get_children():
		if card.has_meta("lights"):
			card.mouse_entered.connect(_peek.bind(card))
			card.mouse_exited.connect(_peek.bind(null))
	show()


## See-through while `keep` (a hovered upgrade card) is hovered: the dimming, the pop-up's box and every other
## part fade so the map behind shows; null brings them back.
func _peek(keep: Control) -> void:
	var faint := keep != null
	self_modulate.a = 0.0 if faint else 1.0
	_panel.self_modulate.a = 0.1 if faint else 1.0
	for child in _box.get_children():
		if child is Container and keep != null and keep.get_parent() == child:
			for card in child.get_children():
				(card as CanvasItem).modulate.a = 1.0 if card == keep else 0.06
		else:
			(child as CanvasItem).modulate.a = 0.06 if faint else 1.0
	if not faint:
		for child in _box.get_children():
			for card in child.get_children():
				if card is CanvasItem:
					(card as CanvasItem).modulate.a = 1.0


func show_pick() -> void:
	var content := run.content
	_clear()
	var day := run.world.day_index() + 1
	_title("Dawn of day %d: who joins the settlement?" % day)
	var room := run.population() < run.housing()
	_night_summary("Shells %d  ·  Room %d / %d" % [run.stock["shells"], run.population(), run.housing()])
	if not room:
		UiKit.note(_box, "No room for anyone new. Build huts at the start of the next round.", 14, Color("#e0a050")) \
			.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if run.hunger_turned_away != "":
		var role: String = content.townsfolk[run.hunger_turned_away]["name"].to_lower()
		UiKit.note(_box, "Word has spread that a %s left hungry: no %s will join today." % [role, role], 14, Color("#e0a050")) \
			.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	# A crowded dawn uses medium cards so the row fits the screen.
	var sz := CardView.Size.LARGE if run.pick_offer.size() <= 4 else CardView.Size.MEDIUM
	for i in run.pick_offer.size():
		var card := run.pick_offer[i]
		var btn := _pick_card(card, sz)
		btn.set_roll(run.content, CardRoll.roll_of(card), run.people.card_rarity(card), CardRoll.mods_of(card))
		btn.disabled = not run.can_take_pick(i)
		UiKit.fade_if_disabled(btn, _why_not_pick(card))
		btn.pressed.connect(func() -> void: pick_taken.emit(i))
		row.add_child(btn)
	_skip_button("Nobody today", func() -> void: pick_taken.emit(-1))
	show()


## Before round 1: pick the founding tradition as a card (click to choose, again to drop; with one to pick, another
## click swaps it), then found the town, or leave it to chance for a few goods (Yusuf, 2026-10-25).
func show_traditions(chosen: Array = []) -> void:
	var content := run.content
	var to_pick := content.int_num("traditions_to_pick")
	_clear()
	_title("Who are your people? Choose a tradition" if to_pick == 1 else "Who are your people? Choose %d traditions" % to_pick)
	var note := Label.new()
	note.text = "Each brings its first blueprint and tilts the run: which buildings you are dealt, which tribespeople come and band together, and one lasting gift."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size.x = 640
	_box.add_child(note)
	var ids := content.traditions.keys()
	ids.sort()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var center := CenterContainer.new()
	center.add_child(grid)
	_box.add_child(center)
	for id: String in ids:
		var t: Dictionary = content.traditions[id]
		var picked := chosen.has(id)
		var btn := CardView.new(CardView.Size.LARGE, "tradition", "Chosen" if picked else "Tradition", t["name"])
		btn.custom_minimum_size.x = 210
		btn.set_selected(picked).set_body(t["text"], CardView.TEXT)
		var start: Dictionary = t.get("start", {})
		if not start.is_empty():
			btn.add_goods(start)
		if t.has("blueprint"):
			btn.add_chip("Brings: " + BuildHand.gift_name(content, t["blueprint"]), "house", CardView.TEXT, btn.family_color())
		btn.tooltip_text = t["text"]
		btn.disabled = not picked and chosen.size() >= to_pick and to_pick > 1
		btn.pressed.connect(func() -> void:
			var next := chosen.duplicate()
			if picked:
				next.erase(id)
			elif to_pick == 1:
				next = [id]
			else:
				next.append(id)
			show_traditions(next))
		grid.add_child(btn)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var found := UiKit.primary(UiKit.button(row, "Found the town", func() -> void: traditions_chosen.emit(chosen)))
	found.disabled = chosen.size() < to_pick
	var bonus: Dictionary = content.balance.get("tradition_random_bonus", {})
	var gifts := PackedStringArray()
	for good: String in bonus:
		gifts.append("+%d %s" % [int(bonus[good]), good])
	var chance := UiKit.button(row, "Random (%s)" % ", ".join(gifts), func() -> void: random_tradition_chosen.emit())
	chance.tooltip_text = "Let fate choose your people's tradition, and start with a little more for it."
	UiKit.button(row, "No tradition" if to_pick == 1 else "No traditions", func() -> void: traditions_chosen.emit([]))
	show()


## How a round works (WelcomePanel). Before a run it moves on to the traditions pick; from the title
## screen or the menu it just closes.
func show_welcome(before_run: bool, from_title := false) -> void:
	_clear()
	showing_welcome = true
	if before_run:
		WelcomePanel.fill(_box, run.content, settings, "Choose your founding tradition", func() -> void:
			welcome_pending = false
			show_traditions())
	else:
		WelcomePanel.fill(_box, run.content, settings, "Back", func() -> void: closed.emit())
		if from_title:
			var again := UiKit.button(_box, "Play the first-run intro again", func() -> void: intro_requested.emit())
			again.tooltip_text = "A new run that opens on the camera tour, with the highlights and a gentle first dawn."
			again.size_flags_horizontal = Control.SIZE_SHRINK_END
	show()


func show_settings() -> void:
	_clear()
	SettingsPanel.fill(_box, settings, func() -> void: settings_changed.emit(), func() -> void: closed.emit())
	show()


## On a pedlar round: invite one pedlar (or none). Each card says what it sells, how far out it camps and
## which heroes would walk that far to trade.
func show_pedlars() -> void:
	var content := run.content
	_clear()
	_title("A pedlar's caravan is passing. Who do you invite?")
	var note := Label.new()
	note.text = "The pedlar camps out past the town for this round's days and leaves before the attack. Heroes walk out on their own to sell loot and buy wares; the bold and greedy go furthest. The pedlar hires a hero or two to guard the camp, and they sleep out there."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size.x = 660
	_box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	var slots := {"weapon": "weapons", "armor": "armour", "charm": "charms", "": "a bit of everything"}
	for offer: Dictionary in run.pedlar_offer:
		var id: String = offer["id"]
		var d: Dictionary = content.pedlars["pedlars"][id]
		var pos := Vector2(offer["pos"])
		var who := run.world.pedlar.who_would_go(pos)
		var goers: String = ", ".join(who["go"]) if not who["go"].is_empty() else "nobody"
		var footer := "Would go: " + goers
		if not who["guarded"].is_empty():
			footer += "\nOnce guarded: " + ", ".join(who["guarded"])
		var where := "Camps %d out, %s" % [roundi(pos.length()), World.compass(pos.angle())]
		var sells: String = slots.get(d["slot"], d["slot"])
		var btn := CardView.new(CardView.Size.LARGE, "trade", "Pedlar · %s" % d["camp"], d["name"])
		btn.custom_minimum_size.x = 220
		btn.add_chip("sells " + sells)
		btn.add_chip("tier %d" % run.world.pedlar.ware_tier(id))
		btn.add_chip(where.to_lower(), "map", CardView.TEXT, btn.family_color())
		btn.set_body(d["text"]).set_footer(footer)
		btn.tooltip_text = "%s\nSells %s, about tier %d.\n%s.\n%s" % [d["text"], sells, run.world.pedlar.ware_tier(id), where, footer]
		btn.pressed.connect(func() -> void: pedlar_chosen.emit(id))
		row.add_child(btn)
	_skip_button("No pedlar", func() -> void: pedlar_chosen.emit(""))
	show()


## What stops the town taking a dawn card: no room, or not enough shells.
func _why_not_pick(card: Dictionary) -> String:
	if not card["kind"] in ["promote", "venture"] and run.population() + run.people.card_people(card) > run.housing():
		return "No room: build homes"
	return UiKit.shortfall(run.stock, {"shells": card["cost"]})


## The quiet way out of a pick, centred under the cards.
func _skip_button(text: String, on_press: Callable) -> void:
	var row := CenterContainer.new()
	_box.add_child(row)
	UiKit.button(row, text, on_press).custom_minimum_size = Vector2(220, 36)


func _food_each() -> String:
	var n := run.content.num("food_per_person_per_day")
	return "%s food" % (str(int(n)) if n == floorf(n) else str(n))


## One dawn card (CardView): what kind in the band, who in the title, the price, what arrives, and one line;
## the full detail is in its hover panel.
func _pick_card(card: Dictionary, sz := CardView.Size.LARGE) -> CardView:
	var content := run.content
	var eats := "Eats %s a day" % _food_each()
	var btn: CardView
	match card["kind"]:
		"hero":
			var hero: Unit = card["hero"]
			var c: Dictionary = content.hero_classes[hero.type_id]
			var likes: Array = content.traits[hero.trait_id].get("lodging", [])
			var beds := " or ".join(likes.map(func(id: String) -> String: return content.buildings[id]["name"].to_lower()))
			var legend := ""
			if card.get("legend", false):
				var gear := PackedStringArray()
				for slot: String in hero.items:
					gear.append(Loot.describe(content, hero.items[slot]))
				legend = "A legend, level %d%s." % [hero.level, ", carrying " + " and ".join(gear) if not gear.is_empty() else ""]
			btn = CardView.new(sz, "hero", ("Legend · " if legend != "" else "Hero · ") + c["name"], hero.display_name)
			# The hero's own colour, as on the hero strip under the map, as a dot: a gold class colour on the
			# name would read as a rarity.
			btn.add_title_dot(Color(c["color"]))
			btn.set_price(run.stock, {"shells": card["cost"]})
			btn.add_chip("Lv %d" % hero.level)
			btn.add_chip("You have %d" % run.living_heroes().size())
			btn.add_chip(content.traits[hero.trait_id]["name"])
			btn.set_body(legend if legend != "" else _wilds_line(hero.trait_id))
			btn.set_footer("Sleeps in " + beds)
			btn.tooltip_text = "%s, %s %s\nHealth %d, damage %d%s\n%sLikes to sleep in: %s\n%s\n%s." % [hero.display_name,
				content.traits[hero.trait_id]["name"], c["name"].to_lower(), int(hero.max_hp), int(hero.attack),
				", ranged" if hero.attack_range > 60 else "", legend + "\n" if legend != "" else "", beds, _trait_hint(hero.trait_id), eats]
		"family":
			var who := {}
			for role: String in card["roles"]:
				who[role] = int(who.get(role, 0)) + 1
			var parts := PackedStringArray()
			for role: String in who:
				parts.append("%d %s" % [who[role], content.townsfolk[role]["name"].to_lower()])
			btn = CardView.new(sz, "folk", "Family", "A family")
			btn.set_price(run.stock, {})
			var roles: Array = card["roles"].duplicate()
			for i in CardRoll.extra_people(content, card):
				roles.append("tribesperson")
			btn.add_people(roles)
			btn.set_body(", ".join(parts)).set_footer("Needs %d beds" % run.people.card_people(card))
			btn.tooltip_text = "A whole family moves in at once: %s.\nEach eats %s a day." % [", ".join(parts), _food_each()]
		"promote":
			btn = _promote_card(card, sz)
		"venture":
			btn = _venture_card(card, sz)
		_:
			var def: Dictionary = content.townsfolk[card["role"]]
			var roles: Array = [card["role"]]
			for i in CardRoll.extra_people(content, card):
				roles.append(card["role"])
			if card.has("leaning"):
				var lean: Dictionary = def["leanings"][card["leaning"]]
				var key: String = card["role"] + "/" + card["leaning"]
				var size := int(run.world.folk_ai.count_leanings().get(key, 0))
				var level := run.world.folk_ai.band_level(card["role"], card["leaning"], size)
				var grows := run.world.folk_ai.band_level(card["role"], card["leaning"], size + 1) > level
				btn = CardView.new(sz, "folk", def["name"], lean["name"])
				if grows:
					btn.set_advice("Forms a band" if level == 0 else "Band grows stronger")
				btn.set_price(run.stock, {})
				btn.add_people(roles)
				_have_chip(btn, card["role"])
				for good: String in lean["goods"].slice(0, 2):
					btn.add_good_label(good)
				btn.set_body(lean["text"]).set_footer(eats)
				btn.tooltip_text = "%s\n%s Still fetches anything the town is short of, but picks trips for %s first.\n%s\n%s." % [
					def["text"], lean["text"], ", ".join(lean["goods"]).replace("_", " "),
					Tooltips.band_line(run, card["role"], card["leaning"], true), eats]
			else:
				btn = CardView.new(sz, "folk", "Townsperson", def["name"])
				btn.set_price(run.stock, {})
				btn.add_people(roles)
				_have_chip(btn, card["role"])
				btn.set_body(def["text"]).set_footer(eats)
				btn.tooltip_text = "%s\n%s." % [def["text"], eats]
	return btn


## How many of this role the town has now, so a dawn pick reads as "a fourth warrior" rather than "a warrior".
func _have_chip(btn: CardView, role: String) -> void:
	btn.add_chip("You have %d" % run.count_role(role))


## A venture: send tribespeople out, some never come back, the rest bring goods home.
func _venture_card(card: Dictionary, sz := CardView.Size.LARGE) -> CardView:
	var v: Dictionary = run.content.ventures[card["venture"]]
	var terms := run.people.venture_terms(card["venture"], card)
	var lose: Array = terms["lose"]
	var losing := "%d" % lose[0] if lose[0] == lose[1] else "%d-%d" % [lose[0], lose[1]]
	var brings := ", ".join(terms["goods"].keys().map(func(g: String) -> String: return "%d %s" % [terms["goods"][g], g.replace("_", " ")]))
	var btn := CardView.new(sz, "venture", "Venture · send %d" % terms["send"], v["name"])
	# One figure per person sent, crossed out red for those who won't come back.
	btn.add_control(VentureFigures.make(terms["send"], lose[0], lose[1] - lose[0], 16.0))
	btn.add_chip("%s won't come back" % losing, "", CardView.DANGER)
	# The reward never clips: each good is its own chip.
	btn.add_goods(terms["goods"])
	btn.set_footer("Instead of a newcomer")
	btn.tooltip_text = "%s\nSend %d tribespeople (you have %d). %s of them never come home; the rest bring %s.\nInstead of a newcomer today.\nA bold red X is a sure death, a faint one may or may not come home." % [
		v["text"], terms["send"], run.count_role("tribesperson"), losing, brings]
	return btn


## Just after a venture: who never came home (a red X each) and what the rest brought.
func show_venture_result() -> void:
	var result := run.last_venture
	_clear()
	_title(run.content.ventures[result["venture"]]["name"])
	var row := CenterContainer.new()
	row.add_child(VentureFigures.make(result["send"], result["lost"], 0, 28.0))
	_box.add_child(row)
	var lost := int(result["lost"])
	var line := Label.new()
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 18)
	if lost == 0:
		line.text = "All %d tribespeople came home." % result["send"]
		line.add_theme_color_override("font_color", VentureFigures.HOME_COLOR)
	else:
		line.text = "%d of %d tribespeople never came home." % [lost, result["send"]]
		line.add_theme_color_override("font_color", VentureFigures.X_COLOR)
	_box.add_child(line)
	var goods: Dictionary = result["goods"]
	var brought := ", ".join(goods.keys().map(func(g: String) -> String: return "%d %s" % [goods[g], g.replace("_", " ")]))
	UiKit.note(_box, "They bring home %s." % brought, 15, Color("#e8e8e8")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var center := CenterContainer.new()
	_box.add_child(center)
	UiKit.primary(UiKit.button(center, "Carry on", func() -> void: closed.emit())).custom_minimum_size = Vector2(220, 36)
	show()


## A promotion: who, what they become (before and after), and the price.
func _promote_card(card: Dictionary, sz := CardView.Size.LARGE) -> CardView:
	var content := run.content
	var btn: CardView
	match card["role"]:
		"warrior":
			var u: Unit = card["unit"]
			var hero: Unit = card["hero"]
			var cls: String = content.hero_classes[hero.type_id]["name"]
			btn = CardView.new(sz, "promote", "Promote a veteran warrior", hero.display_name)
			btn.add_chip("%d kills" % u.kills)
			btn.add_chip("→ %s %s" % [content.traits[hero.trait_id]["name"].to_lower(), cls.to_lower()], "", CardView.GOOD)
			btn.set_footer("Needs a bed like any hero")
			btn.tooltip_text = "A warrior with %d kills, here since round %d, becomes %s, %s %s, level %d.\nNeeds a bed like any hero." % [
				u.kills, u.joined_round, hero.display_name, content.traits[hero.trait_id]["name"], cls.to_lower(), hero.level]
		"champion":
			var hero: Unit = card["hero"]
			var knight: String = content.hero_classes[content.promotions["champion"]["becomes"]]["name"]
			btn = CardView.new(sz, "promote", "Knight a champion", hero.display_name)
			btn.add_chip("Lv %d" % hero.level)
			btn.add_chip("You have %d" % run.living_heroes().size())
			btn.add_chip("→ " + knight.to_lower(), "", CardView.GOOD)
			btn.tooltip_text = "%s, a level %d champion, is knighted and becomes a %s." % [hero.display_name, hero.level, knight.to_lower()]
		_:
			var u: Unit = card["unit"]
			var shop: String = content.buildings[card["workshop"]]["name"].to_lower()
			var t: Dictionary = content.promotions["craftsperson"]["traits"][card["trait"]]
			var effects := Tooltips.master_effects(content, card["trait"], card["workshop"])
			btn = CardView.new(sz, "promote", "Promote a craftsperson", card["name"])
			btn.add_chip("%s master of the %s" % [t["name"], shop], "", CardView.GOOD)
			btn.set_body(", ".join(Tooltips.master_effects(content, card["trait"], card["workshop"], true)) + ".", CardView.TEXT)
			btn.tooltip_text = "A craftsperson who made %d goods at the %s becomes %s, master of the %s.\n%s: %s\n%s.\nA master goes to their own bench before any other." % [
				int(u.made[card["workshop"]]), shop, card["name"], shop, t["name"], t["text"], ".\n".join(effects)]
	btn.set_price(run.stock, {"shells": card["cost"]})
	return btn


## Where a hero of this trait goes by day, as one line for the card.
func _wilds_line(trait_id: String) -> String:
	var w := float(run.content.traits[trait_id]["wilds"])
	return "Hunts far out at the dens by day." if w > 0.6 else ("Stays near the camp." if w < 0.2 else "Ventures out sometimes.")


func _trait_hint(trait_id: String) -> String:
	var t: Dictionary = run.content.traits[trait_id]
	var wilds := "hunts far out at the dens by day" if float(t["wilds"]) > 0.6 else ("stays near the camp" if float(t["wilds"]) < 0.2 else "ventures out sometimes")
	return "%s: %s, retreats at %d%% health, goes to rest when energy falls to %d." % [t["name"], wilds,
		roundi(float(t["retreat_at"]) * 100.0), int(t.get("tired_at", 25))]


## One line on what happened last night, above the dawn and relic picks, with `extra` (shells and room at dawn)
## on the same line so the window stays short.
func _night_summary(extra := "") -> void:
	var n := run.last_night
	if n.is_empty():
		if extra != "":
			UiKit.note(_box, extra, 14, Color("#e8e8e8")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var deaths: Array = n["deaths"]
	var left: Array = n.get("left", [])
	var text := "Night %d: raiders %d, enemies killed %d, hearth damage %d. " % [
		n["night"], n["raiders"], n["kills"], n["hearth_damage"]]
	var lost := PackedStringArray()
	for name: String in deaths:
		lost.append("%s (killed)" % name)
	var unhappy: Array = n.get("heroes_left", [])
	for name: String in left:
		lost.append("%s (%s)" % [name, "left unhappy" if unhappy.has(name) else "left hungry"])
	text += "Lost: %s." % ", ".join(lost) if not lost.is_empty() else "Nobody was lost."
	var label := Label.new()
	label.text = text + ("\n" + extra if extra != "" else "")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = 600
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("#e0a050") if not lost.is_empty() else Color("#a8c8a0"))
	_box.add_child(label)


## Who hit hardest this round and what the hearth took, with a button for the whole table.
func _impact_line() -> void:
	var shown := ImpactView.shown_round(run)
	if shown.is_empty() or (shown["impact"] as Dictionary).is_empty():
		return
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 10)
	_box.add_child(line)
	var label := UiKit.note(line, ImpactView.headline(run, shown["impact"]), 13, UiKit.HEADING_COLOR)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var open := Button.new()
	open.text = "Who did what"
	UiKit.secondary(open, 12)
	open.pressed.connect(func() -> void: show_impact())
	line.add_child(open)


func show_relic_pick() -> void:
	_clear()
	_title(("Round %d survived! Choose a pact" if run.is_pact_round() else "Round %d survived! Choose a relic") % run.round_number)
	_night_summary()
	_impact_line()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	for id in run.relic_offer:
		row.add_child(_relic_card(id))
	_skip_button("Skip the relic", func() -> void: relic_picked.emit(""))
	show()


## One relic, pact or spoils card (CardView). Relics don't roll, so the frame is the relic's own rarity. Chips name
## the tags a tag-keyed relic acts on; spoils show what taking them brings now.
func _relic_card(id: String) -> CardView:
	var content := run.content
	var r: Dictionary = content.relics[id]
	var is_spoils: bool = id == run.spoils.get("id", "")
	var kind := "Pact" if "pact" in content.tags_of("relic", id) else "Relic"
	var text: String = r["text"]
	if is_spoils:
		kind = "Spoils of the %s" % str(content.balance.get("spoils_kinds", {}).get(run.spoils["kind"], run.spoils["kind"]))
	var btn := CardView.new(CardView.Size.LARGE, "spoils" if is_spoils else "relic", kind, r["name"])
	btn.custom_minimum_size.x = 206
	btn.set_roll(content, content.rarity_of("relic", id), "white", [])
	btn.set_body(text, CardView.TEXT)
	for key: String in RunState.TAG_EFFECTS:
		for tag: String in r.get("effects", {}).get(key, {}):
			btn.add_chip(tag.replace("_", " "), "spark", CardView.TEXT, btn.family_color())
	var footer := _relic_footer(r)
	if is_spoils:
		var now := run.spoils_now()
		btn.add_goods(now["goods"], true, CardView.GOOD, true)
		var roles: Array = []
		for role: String in now["folk"]:
			for i in int(now["folk"][role]):
				roles.append(role)
		if not roles.is_empty():
			btn.add_people(roles)
		# The total is the card's headline, so nobody has to multiply "per foe" by how many came.
		var line := spoils_line(content, now["goods"], int(run.spoils["foes"]), str(run.spoils["kind"]))
		if line != "":
			text = line + ("" if r.get("effects", {}).is_empty() else "\n" + text)
			btn.set_body(text, CardView.TEXT)
		footer = "Instead of a relic."
	btn.set_footer(footer)
	var tags := Tooltips.tag_notes(run, "relic", id)
	btn.tooltip_text = text + ("\n" + footer if footer != "" else "") + ("\nTags: " + "\n".join(tags) if not tags.is_empty() else "")
	btn.pressed.connect(func() -> void: relic_picked.emit(id))
	return btn


## The spoils' goods as one sentence with the totals ("You get 16 food now, from the 8 beasts that came."), or "".
## kind is the enemy tag the spoils are of.
static func spoils_line(content: Content, goods: Dictionary, foes: int, kind: String) -> String:
	var parts: Array[String] = []
	for good: String in goods:
		parts.append("%d %s" % [int(goods[good]), good.replace("_", " ")])
	if parts.is_empty():
		return ""
	var listed := parts[0] if parts.size() == 1 else ", ".join(parts.slice(0, -1)) + " and " + parts[-1]
	var names: Array = content.balance.get("spoils_foes", {}).get(kind, [kind, kind])
	return "You get %s now, from the %d %s that came." % [listed, foes, names[0] if foes == 1 else names[1]]


## What a tag-keyed relic would act on in this town now ("Your heroes carry 3 bone items"), or "".
func _relic_footer(r: Dictionary) -> String:
	var bonus: Dictionary = r.get("effects", {}).get("gear_bonus", {})
	if bonus.is_empty():
		return ""
	var count := 0
	for hero: Unit in run.living_heroes():
		for slot: String in hero.items:
			for tag: String in bonus:
				if tag in run.content.tags_of("item", hero.items[slot]["base"]):
					count += 1
	return "Your heroes carry %d such item%s" % [count, "" if count == 1 else "s"]


func show_end() -> void:
	var content := run.content
	_clear()
	var won := run.phase == RunState.Phase.WON
	_title("Victory! The people endure." if won else "The fire goes out in round %d." % run.round_number)
	var summary := Label.new()
	summary.text = "Seed %d  ·  heroes lost: %d  ·  townsfolk lost: %d  ·  relics: %s" % [run.run_seed, run.fallen.size(), run.fallen_folk,
		", ".join(run.relics.map(func(id: String) -> String: return content.relics[id]["name"])) if not run.relics.is_empty() else "none"]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.custom_minimum_size.x = 420
	_box.add_child(summary)
	if not won:
		UiKit.note(_box, content.tips["welcome"]["lost_line"], 16, Color("#d9cbb3")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.primary(UiKit.button(_box, "New run", func() -> void: new_run_requested.emit(false)))
	UiKit.button(_box, "Replay seed %d" % run.run_seed, func() -> void: new_run_requested.emit(true))
	UiKit.button(_box, "Who did what", func() -> void: show_impact(true))
	UiKit.button(_box, "Run history", show_history)
	show()


## Lists saved runs with stats, and lets you copy or download them to share.
func show_history() -> void:
	var was_end_screen := run.is_over()
	_clear()
	_title("Run history")
	var runs := RunHistory.load_all()
	var stats := Label.new()
	stats.text = "No runs saved yet. Runs are saved at every dawn and after each round." if runs.is_empty() \
		else "\n".join(RunStats.report(runs).slice(0, 6))
	stats.add_theme_font_size_override("font_size", 13)
	_box.add_child(stats)
	var hint := Label.new()
	hint.text = "To share runs, download them as one file and attach it to a chat message."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiKit.HINT_COLOR)
	_box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for data in runs:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = RunHistory.one_line(data)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var copy := Button.new()
		copy.text = "Copy"
		copy.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(JSON.stringify(RunHistory.compact(data)))
			copy.text = "Copied!")
		row.add_child(copy)
		if OS.has_feature("web"):
			var download := Button.new()
			download.text = "Download"
			download.pressed.connect(func() -> void:
				JavaScriptBridge.download_buffer(JSON.stringify(data, "\t").to_utf8_buffer(),
					"run-%s.json" % data.get("id", "run"), "application/json"))
			row.add_child(download)
		list.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(buttons)
	if not runs.is_empty():
		var copy_all := Button.new()
		copy_all.text = "Copy all runs"
		copy_all.pressed.connect(func() -> void:
			DisplayServer.clipboard_set(JSON.stringify(runs.map(RunHistory.compact)))
			copy_all.text = "Copied!")
		buttons.add_child(copy_all)
		if OS.has_feature("web"):
			var download_all := Button.new()
			download_all.text = "Download all runs (one file)"
			download_all.tooltip_text = "Saves every run as one file. Attach that file to a chat message to share it."
			download_all.pressed.connect(func() -> void:
				JavaScriptBridge.download_buffer(JSON.stringify(runs.map(RunHistory.compact)).to_utf8_buffer(),
					"runs-%s.json" % Time.get_date_string_from_system(), "application/json"))
			buttons.add_child(download_all)
	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func() -> void:
		if was_end_screen:
			show_end()
		else:
			closed.emit())
	buttons.add_child(close)
	show()


## Dev panel: change recipe prices and work times and the price levels live.
## Changes last until the page reloads; "Copy values" puts them on the clipboard to send.
func show_tuning() -> void:
	var content := run.content
	_clear()
	_title("Tune the market (dev)")
	var grid := GridContainer.new()
	grid.columns = 3
	_box.add_child(grid)
	for header: String in ["Recipe", "Price per tier", "Work (seconds)"]:
		var l := Label.new()
		l.text = header
		l.add_theme_color_override("font_color", UiKit.HEADING_COLOR)
		grid.add_child(l)
	var ids: Array = content.market["recipes"].keys()
	ids.sort()
	for id: String in ids:
		var r: Dictionary = content.market["recipes"][id]
		var l := Label.new()
		l.text = content.recipe_name(id)
		grid.add_child(l)
		for key: String in ["price", "work"]:
			# Smelting recipes fill the stock instead of a stall, so they have no price.
			if not r.has(key):
				grid.add_child(Control.new())
				continue
			var spin := SpinBox.new()
			spin.min_value = 1
			spin.max_value = 200
			spin.value = float(r[key])
			spin.value_changed.connect(func(v: float) -> void: r[key] = v)
			grid.add_child(spin)
	for level: String in ["cheap", "fair", "dear"]:
		var l := Label.new()
		l.text = "%s price x" % level.capitalize()
		grid.add_child(l)
		var spin := SpinBox.new()
		spin.min_value = 0.1
		spin.max_value = 5.0
		spin.step = 0.1
		spin.value = float(content.market["price_levels"][level])
		spin.value_changed.connect(func(v: float) -> void: content.market["price_levels"][level] = v)
		grid.add_child(spin)
		grid.add_child(Control.new())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(buttons)
	var copy := Button.new()
	copy.text = "Copy values"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(JSON.stringify({"price_levels": content.market["price_levels"], "recipes": content.market["recipes"]}))
		copy.text = "Copied!")
	buttons.add_child(copy)
	UiKit.button(buttons, "Back", func() -> void: closed.emit())
	show()


## The Esc menu: resume, the seed (replay it or try another), a new run, Run history and dev tools.
func show_menu(dev_mode: bool) -> void:
	_clear()
	_title("Paused")
	var seed_row := HBoxContainer.new()
	_box.add_child(seed_row)
	var seed_edit := LineEdit.new()
	seed_edit.text = str(run.run_seed)
	seed_edit.placeholder_text = "seed"
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_edit)
	var restart := Button.new()
	restart.text = "Start run with this seed"
	restart.pressed.connect(func() -> void:
		if seed_edit.text.is_valid_int():
			seed_run_requested.emit(int(seed_edit.text))
		else:
			new_run_requested.emit(false))
	seed_row.add_child(restart)
	UiKit.button(_box, "New run (new seed)", func() -> void: new_run_requested.emit(false))
	UiKit.button(_box, "Run history", show_history)
	UiKit.button(_box, "How to play", func() -> void: show_welcome(false))
	UiKit.button(_box, "Settings", show_settings)
	if dev_mode:
		UiKit.button(_box, "Tune market (dev)", show_tuning)
	UiKit.button(_box, "Title screen", func() -> void: title_requested.emit())
	UiKit.note(_box, "%s pauses, %s tilts the map, point at anything for details." % [
		GameSettings.key_name(settings.keys["pause"]), GameSettings.key_name(settings.keys["tilt_map"])], 12)
	UiKit.primary(UiKit.button(_box, "Resume (%s)" % GameSettings.key_name(settings.keys["menu"]), func() -> void: closed.emit())).custom_minimum_size.y = 44
	show()


## The whole story of the run so far.
func show_log() -> void:
	_clear()
	_title("The story so far")
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(760, 460)
	text.scroll_following = true
	text.add_theme_font_size_override("normal_font_size", 13)
	text.add_theme_font_size_override("bold_font_size", 13)
	var lines := PackedStringArray()
	for line in run.story:
		lines.append(StoryLog.as_bbcode(line))
	text.text = "\n".join(lines)
	_box.add_child(text)
	UiKit.button(_box, "Back", func() -> void: closed.emit())
	show()


## Who did what (ImpactView): this round's table, or the whole run's. Back returns to what the run waits on.
func show_impact(whole_run := false) -> void:
	_clear()
	var shown := ImpactView.shown_round(run)
	if whole_run:
		_title("Who did what this run")
	else:
		_title("Who did what in round %d" % int(shown.get("round", run.round_number)))
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	_box.add_child(tabs)
	var this_round := Button.new()
	this_round.text = "This round"
	this_round.disabled = not whole_run
	this_round.pressed.connect(func() -> void: show_impact(false))
	tabs.add_child(this_round)
	var all := Button.new()
	all.text = "Whole run"
	all.disabled = whole_run
	all.pressed.connect(func() -> void: show_impact(true))
	tabs.add_child(all)
	for btn: Button in [this_round, all]:
		UiKit.secondary(btn, 13)
	UiKit.note(_box, "Damage counts only the health a blow took. Percent is each one's share of all damage the town dealt. "
		+ "Lost is townsfolk who died. Raised counts the buildings each kind finished.", 11)
	ImpactView.build(_box, run, ImpactView.whole_run(run) if whole_run else shown.get("impact", {}))
	UiKit.button(_box, "Back", func() -> void: closed.emit())
	show()


func _clear() -> void:
	showing_draft = false
	showing_welcome = false
	_peek(null)
	for child in _box.get_children():
		child.queue_free()


func _title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
