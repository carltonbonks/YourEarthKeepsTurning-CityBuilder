class_name Overlays
extends PanelContainer
## The dimmed pop-ups over the screen: the blueprint draft, the dawn pick and the relic pick (as cards, detail on hover),
## (the dawn pick plays as a scene in the town when it can, DawnMuster: its cards stand in a row over the map,
## the header at the top, and the map shows through),
## the end of a run, the menu (Esc), the full story log, Run history and the dev tuning panel. Choices go back to the screen
## as signals; nothing here changes the run directly. A pop-up taller or wider than the screen shrinks
## to fit (`_fit_panel`) rather than running off it.

signal pick_taken(index: int)
signal relic_picked(relic_id: String)
## The founding traditions chosen before round 1 ([] for none).
signal traditions_chosen(ids: Array)
## The founding tradition left to chance (RunState.choose_random_tradition).
signal random_tradition_chosen
## The charter taken after an age-up (a path id from data/paths.json).
signal charter_chosen(id: String)
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
## True while the dawn pick is up (the Elder speaks over it, Advisor).
var showing_pick := false
## The dawn pick's cards, in pick_offer order, so the Elder can frame one.
var _pick_buttons: Array[CardView] = []
var _box: VBoxContainer
var _panel: PanelContainer
## The map, for the dawn muster (DawnMuster): the scene plays on it and the cards stand over it.
var arena: ArenaView
## The dawn pick is up as a scene in the town, not the pop-up: the cards stand in `_stage`, the header (the pop-up's
## box, without cards) sits at the map's top and nothing is dimmed.
var mustering := false
var _stage: Control
var _muster_size := CardView.Size.LARGE
## The build hand along the screen's foot (main sets it): picks over the town keep above it.
var hand_view: BuildHandView
## The scene up now laid out again (the map changed size), or empty.
var _reshow := Callable()
## Set just before a muster is laid out again in place (a tradition clicked): its people stay where they stand.
var mustering_kept := false
## Set to build the next screen as the classic pop-up (its scene didn't fit).
var _classic_once := false


## Closing a scene's screen gives the camera back (DraftStage).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and arena != null:
		arena.draft.finish(Time.get_ticks_msec())


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
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	hide()


## Where the pop-up is on screen, or an empty rect when none is up.
func panel_rect() -> Rect2:
	if not visible:
		return Rect2()
	var rect := _panel.get_global_rect()
	if mustering:
		for card in _stage.get_children():
			if card is CardView and not card.is_queued_for_deletion():
				rect = rect.merge(card.get_global_rect())
	return rect


## Where dawn card `index` is on screen, or an empty rect when the dawn pick isn't up.
func pick_card_rect(index: int) -> Rect2:
	if not (visible and showing_pick) or index < 0 or index >= _pick_buttons.size():
		return Rect2()
	return _pick_buttons[index].get_global_rect()


## Centres the pop-up, shrinking it to fit the screen when it is too big (never below MIN_SCALE).
func _fit_panel() -> void:
	var area := (_panel.get_parent() as Control).size
	if area.x <= 0.0:
		return
	if mustering:
		_place_header()
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
	if run.awaiting_charter():
		show_charter()
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
	hand_view = hand
	_reshow = show_draft.bind(hand)
	showing_draft = true
	_title(hand.draft_title() + " to start building")
	var sub := UiKit.note(_box, "It joins Your blueprints in the hand and stays on offer for the whole run.", UiKit.STRONG)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.tooltip_text = BuildHandView.pool_line(run)
	sub.mouse_filter = Control.MOUSE_FILTER_PASS
	if _draft_scene(hand, sub):
		return
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
	_title("Dawn of day %d: who joins the town?" % day)
	var room := run.population() < run.housing()
	_night_summary("Shells %d  ·  Room %d / %d" % [run.stock["shells"], run.population(), run.housing()])
	if not room:
		UiKit.note(_box, "No room for anyone new. Build huts at the start of the next round.", UiKit.STRONG, UiKit.EMBER) \
			.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if run.hunger_turned_away != "":
		var role: String = content.townsfolk[run.hunger_turned_away]["name"].to_lower()
		UiKit.note(_box, "Word has spread that a %s left hungry: no %s will join today." % [role, role], UiKit.STRONG, UiKit.EMBER) \
			.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A crowded dawn uses medium cards so the row fits the screen.
	var sz := CardView.Size.LARGE if run.pick_offer.size() <= 4 else CardView.Size.MEDIUM
	_reshow = show_pick
	if _muster(sz):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	for i in run.pick_offer.size():
		row.add_child(_dawn_card(i, sz))
	_skip_button("Nobody today", func() -> void: pick_taken.emit(-1))
	showing_pick = true
	show()


## Dawn card `index` as a card to click, remembered for the Elder and the highlights.
func _dawn_card(i: int, sz: CardView.Size) -> CardView:
	var card := run.pick_offer[i]
	var btn := _pick_card(card, sz)
	btn.set_roll(run.content, CardRoll.roll_of(card), run.people.card_rarity(card), CardRoll.mods_of(card))
	btn.disabled = not run.can_take_pick(i)
	UiKit.fade_if_disabled(btn, _why_not_pick(card))
	btn.pressed.connect(func() -> void: pick_taken.emit(i))
	_pick_buttons.append(btn)
	return btn


## The dawn pick as a scene in the town (DawnMuster), when the setting is on and the cards fit over the map at
## MIN_SCALE or more: the header (already in the box) goes to the map's top, the cards stand in a row over their
## groups, "Nobody today" under the hearth. False leaves the classic pop-up to be built.
func _muster(sz: CardView.Size) -> bool:
	if not _scenes_on():
		return false
	var cards: Array = []
	for i in run.pick_offer.size():
		cards.append(_dawn_card(i, sz))
	if not _muster_with(cards, [], sz, [["Nobody today", func() -> void: pick_taken.emit(-1)]]):
		_pick_buttons.clear()
		return false
	showing_pick = true
	return true


## The map the build hand along the screen's foot leaves showing (all of it while the hand is away).
func _map_area() -> Vector2:
	if hand_view == null or not hand_view.is_visible_in_tree():
		return arena.size
	return Vector2(arena.size.x, minf(arena.size.y, hand_view.get_global_rect().position.y - arena.get_global_rect().position.y))


## True when a pick may play as a scene in the town: the setting is on and the map is up.
func _scenes_on() -> bool:
	return arena != null and settings != null and settings.picks_in_town and arena.is_visible_in_tree() \
		and arena.size.x > 0.0 and is_inside_tree()


## A muster round the hearth (DawnMuster): `cards` in a row over the map under the header, each over its group
## (`groups`, or the dawn's own when empty), and `footer` buttons ([text, on press]) in a row under the hearth.
## False (the cards freed) when they'd shrink past DawnMuster's MIN_SCALE: the caller builds the classic pop-up.
func _muster_with(cards: Array, groups: Array, sz: CardView.Size, footer: Array) -> bool:
	# Over the hand (the founding before round 1) the map is short: the buttons go beside the title instead.
	var in_header := hand_view != null and hand_view.is_visible_in_tree()
	var line: HBoxContainer = null
	var title: Control = null
	if in_header:
		title = _box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion() and (c as Control).visible)[0]
		line = HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 12)
		_box.add_child(line)
		_box.move_child(line, title.get_index())
		title.reparent(line)
		for f: Array in footer:
			var b := UiKit.button(line, f[0], f[1])
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if f.size() > 2:
				b.disabled = f[2]
			if f.size() > 3 and f[3]:
				UiKit.primary(b)
	var header := _header_height() + 2.0 * HEADER_GAP
	var area := _map_area()
	var plan := DawnMuster.layout(cards.size(), CardView.SHAPE[sz], area, header, HEADER_GAP if in_header else DawnMuster.FOOTER)
	if plan.is_empty():
		if in_header:
			title.reparent(_box)
			_box.move_child(title, line.get_index())
			line.queue_free()
		for c: Node in cards:
			c.queue_free()
		return false
	var again := mustering_kept
	mustering_kept = false
	mustering = true
	self_modulate.a = 0.0
	_muster_size = sz
	if not arena.resized.is_connected(_on_arena_resized):
		arena.resized.connect(_on_arena_resized)
	var at := _arena_origin()
	var s: float = plan["scale"]
	var xs: Array = plan["xs"]
	for i in cards.size():
		var btn: CardView = cards[i]
		_stage.add_child(btn)
		btn.size = CardView.SHAPE[sz]
		btn.scale = Vector2(s, s)
		btn.position = at + Vector2(float(xs[i]) - CardView.SHAPE[sz].x * s / 2.0, plan["card_top"])
		if not again:
			btn.modulate.a = 0.0
			create_tween().tween_property(btn, "modulate:a", 1.0, 0.35).set_delay(0.05 * i)
	if not in_header:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_stage.add_child(row)
		for f: Array in footer:
			var b := UiKit.button(row, f[0], f[1])
			b.custom_minimum_size = Vector2(200, 36)
			if f.size() > 2:
				b.disabled = f[2]
			if f.size() > 3 and f[3]:
				UiKit.primary(b)
		row.reset_size()
		row.position = at + Vector2((area.x - row.size.x) / 2.0, area.y - DawnMuster.FOOTER + 8.0)
	show()
	_place_header()
	arena.start_muster(plan, groups, again)
	return true


## The blueprint draft as a scene over the town (DraftStage), when the setting is on and the cards fit at
## DraftStage.MIN_SCALE or more: the header (title, the line under it and the reroll) at the map's top, the offers in
## a row under it, each over where it would go, and the camera pulled out to the whole town below them. False leaves
## the classic pop-up to be built.
func _draft_scene(hand: BuildHandView, sub: Label) -> bool:
	if not _scenes_on():
		return false
	var entries := hand.draft_entries()
	var reroll := hand.reroll_button()
	reroll.text = reroll.text.replace("\n", " ")
	return _over_town(entries.map(func(e: Array) -> CardView: return e[0]),
		entries.map(func(e: Array) -> Dictionary: return DraftStage.anchor(run, e[1])), sub, reroll)


## A pick laid over the town (DraftStage: the blueprint draft, the pedlars): a short header (the title with `extra`
## beside it, and `sub`, the line under the title, on the title's hover), `cards` in a row under it, each over its
## place (`places`, DraftStage anchors) on a line down to it, and the camera pulled out so the town and the places
## fill the map above the hand. False (cards and `extra` freed, the header as it was) when the cards would shrink
## past DraftStage.MIN_SCALE: the caller builds the classic pop-up.
func _over_town(cards: Array, places: Array, sub: Label, extra: Control) -> bool:
	var shape: Vector2 = CardView.SHAPE[CardView.Size.MEDIUM]
	var title: Control = _box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())[0]
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 16)
	_box.add_child(line)
	_box.move_child(line, title.get_index())
	title.reparent(line)
	title.tooltip_text = sub.text + ("\n" + sub.tooltip_text if sub.tooltip_text != "" else "")
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	sub.visible = false
	if extra is Button:
		(extra as Button).custom_minimum_size = Vector2(0, 30)
	extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(extra)
	var header := _header_height() + 2.0 * HEADER_GAP
	var area := _map_area()
	var s := DraftStage.card_scale(cards.size(), shape, area, header)
	var xs: Array = []
	var z := 1.0
	var pan := Vector2.ZERO
	if s > 0.0:
		# The town fills the map under the cards: as big as fits, its near edge at the bottom of the room.
		var top := header + shape.y * s + DraftStage.LEAD
		var r := DraftStage.reach(run, places)
		var room := area.y - top - DraftStage.EDGE
		var k := minf(room * DraftStage.SPILL / (2.0 * r * ArenaView.ISO_SQUASH), (area.x - 2.0 * DraftStage.EDGE) / (2.0 * r))
		z = clampf(k / arena.scale_per_zoom(), DraftStage.FAR_ZOOM, ArenaView.MAX_ZOOM)
		var near := r * ArenaView.ISO_SQUASH * k
		pan = -arena.world_under(Vector2(area.x / 2.0, area.y - DraftStage.EDGE - near), z, Vector2.ZERO)
		var want: Array = places.map(func(a: Dictionary) -> float:
			return arena.screen_at(a["at"], z, pan).x if a["placed"] else area.x / 2.0)
		xs = DraftStage.spread(want, shape.x * s, area.x)
	if xs.is_empty():
		title.reparent(_box)
		_box.move_child(title, line.get_index())
		title.tooltip_text = ""
		sub.visible = true
		line.queue_free()
		for c: Node in cards:
			c.queue_free()
		return false
	mustering = true
	self_modulate.a = 0.0
	_muster_size = CardView.Size.MEDIUM
	if not arena.resized.is_connected(_on_arena_resized):
		arena.resized.connect(_on_arena_resized)
	var at := _arena_origin()
	arena.start_draft(places, z, pan)
	for i in cards.size():
		var btn: CardView = cards[i]
		_stage.add_child(btn)
		btn.size = shape
		btn.scale = Vector2(s, s)
		btn.position = at + Vector2(float(xs[i]) - shape.x * s / 2.0, header)
		btn.modulate.a = 0.0
		create_tween().tween_property(btn, "modulate:a", 1.0, 0.35).set_delay(0.05 * i)
		arena.draft.feet.append(Vector2(float(xs[i]), header + shape.y * s))
	show()
	_place_header()
	return true


## The map changed size while a scene is up (a window resized): it is laid out again.
func _on_arena_resized() -> void:
	if visible and mustering and _reshow.is_valid():
		_reshow.call()


## Keeps the muster's cards to their one shape: a new card measures tall until it knows its width.
func _process(_delta: float) -> void:
	if not (visible and mustering):
		return
	if arena.muster.homecoming():
		var now := float(Time.get_ticks_msec())
		_panel.visible = arena.muster.home_back(now)
	for card in _stage.get_children():
		if card is CardView and not card.is_queued_for_deletion() and card.size != CardView.SHAPE[_muster_size]:
			card.size = CardView.SHAPE[_muster_size]


## The gap kept round the muster's header at the map's top.
const HEADER_GAP := 6.0


## How tall the pop-up's box is with what is in it now (children on their way out don't count, as the box's own
## minimum size would until the next frame): the margins, the border and each line with the gaps between.
func _header_height() -> float:
	var h := 0.0
	var n := 0
	for child in _box.get_children():
		if child.is_queued_for_deletion() or not (child as Control).visible:
			continue
		h += (child as Control).get_combined_minimum_size().y
		n += 1
	return h + maxi(0, n - 1) * _box.get_theme_constant("separation") + 2.0 * 16.0 + 4.0


## Where the map's top-left corner is in this overlay.
func _arena_origin() -> Vector2:
	return arena.get_global_rect().position - get_global_rect().position


## The muster's header (the pop-up's box: title, last night, warnings) centred at the map's top, full size.
func _place_header() -> void:
	_panel.reset_size()
	_panel.scale = Vector2.ONE
	_panel.position = (_arena_origin() + Vector2((arena.size.x - _panel.size.x) / 2.0, HEADER_GAP)).floor()


## Before round 1: pick the founding tradition as a card from the run's offered few, or the Random card that leaves it
## to chance among them all for a few goods (Yusuf, 2026-10-30). Click to choose, again to drop; with one to pick,
## another click swaps it. Then found the town.
const RANDOM_TRADITION := "random"
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
	var ids: Array = run.tradition_offer()
	_reshow = show_traditions.bind(chosen)
	var classic := _classic_once
	_classic_once = false
	# Round the campfire the cards are medium, so they and the founders fit above the hand.
	var in_town := _scenes_on() and not classic
	var tsz := CardView.Size.MEDIUM if in_town else CardView.Size.LARGE
	var grid := GridContainer.new()
	grid.columns = ids.size() + 1
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var center := CenterContainer.new()
	center.add_child(grid)
	_box.add_child(center)
	var by_chance := chosen.has(RANDOM_TRADITION)
	for id: String in ids:
		var t: Dictionary = content.traditions[id]
		var picked := chosen.has(id)
		var btn := CardView.new(tsz, "tradition", "Chosen" if picked else "Tradition", t["name"])
		btn.custom_minimum_size.x = 210
		btn.set_picture(SpriteBook.shared().card_texture(_tradition_building(t)))
		btn.set_selected(picked).set_body(t["text"], CardView.TEXT)
		var start: Dictionary = t.get("start", {})
		if not start.is_empty():
			btn.add_goods(start)
		if t.has("blueprint"):
			btn.add_chip("Brings: " + BuildHand.gift_name(content, t["blueprint"]), "house", CardView.TEXT, btn.family_color())
		btn.tooltip_text = t["text"]
		if content.paths["paths"].has(t.get("path", "")):
			var path: Dictionary = content.paths["paths"][t["path"]]
			btn.add_chip("Path: " + path["name"], "flag", CardView.TEXT, btn.family_color())
			btn.tooltip_text += "\nStarts you on the %s path (%s): %s" % [path["name"], path["short"].to_lower(), path["tiers"][0]["text"]]
		btn.disabled = by_chance or (not picked and chosen.size() >= to_pick and to_pick > 1)
		btn.pressed.connect(func() -> void:
			var next := chosen.duplicate()
			if picked:
				next.erase(id)
			elif to_pick == 1:
				next = [id]
			else:
				next.append(id)
			mustering_kept = mustering
			show_traditions(next))
		grid.add_child(btn)
	# The Random card: always there, drawing from every tradition, not only these.
	var chance := CardView.new(tsz, "tradition", "Chosen" if by_chance else "Random", "Let fate choose")
	chance.custom_minimum_size.x = 210
	chance.set_selected(by_chance).set_body("One of all %d traditions, not only these, drawn as you found the town, and a little more to start with." % content.traditions.size(), CardView.TEXT)
	chance.add_goods(content.balance.get("tradition_random_bonus", {}))
	var all_ids: Array = content.traditions.keys()
	all_ids.sort()
	chance.add_pictures(all_ids.map(func(id: String) -> Texture2D: return SpriteBook.shared().card_texture(_tradition_building(content.traditions[id]))))
	chance.tooltip_text = "Let fate choose your people's tradition from all of them, and start with a little more for it."
	chance.pressed.connect(func() -> void:
		mustering_kept = mustering
		show_traditions([] if by_chance else [RANDOM_TRADITION]))
	grid.add_child(chance)
	# Round the campfire (picks in the town, slice 4): each tradition's founders hold up its card, the Random card's
	# hooded stranger last.
	var can_found := by_chance or chosen.size() >= to_pick
	var found_it := func() -> void:
		if by_chance:
			random_tradition_chosen.emit()
		else:
			traditions_chosen.emit(chosen)
	if in_town:
		var cards: Array = grid.get_children()
		for c: Control in cards:
			grid.remove_child(c)
			c.custom_minimum_size.x = 0
		note.visible = false
		_box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())[0].tooltip_text = note.text
		center.queue_free()
		center.visible = false
		if _muster_with(cards, DawnMuster.tradition_groups(run, ids), tsz,
				[["Found the town", found_it, not can_found, true],
				["No tradition" if to_pick == 1 else "No traditions", func() -> void: traditions_chosen.emit([])]]):
			return
		# It won't fit (the cards are freed): the classic pop-up, built afresh.
		_classic_once = true
		show_traditions(chosen)
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)
	var found := UiKit.primary(UiKit.button(row, "Found the town", func() -> void:
		if by_chance:
			random_tradition_chosen.emit()
		else:
			traditions_chosen.emit(chosen)))
	found.disabled = not by_chance and chosen.size() < to_pick
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


## After an age-up: a charter, one of a few run paths (data/paths.json) to take up or raise a tier. Each card says
## what the tier does, and its hover which buildings the path favours in the draft.
func show_charter() -> void:
	_clear()
	_title("A new age, a new charter. Which way does your town grow?")
	var note := Label.new()
	var held := StatusText.path_names(run)
	note.text = "Each age-up brings a charter: one more path, or the next tier of one you hold.%s" % (
		" Your paths: %s." % ", ".join(held) if not held.is_empty() else "")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	note.custom_minimum_size.x = 640
	_box.add_child(note)
	_reshow = show_charter
	# At the shrine by the hearth (picks in the town, slice 5), each path's card over its own stone.
	if _shrine([note], func(sz: CardView.Size) -> Array: return run.charter_offer.map(func(id: String) -> CardView: return _charter_card(id, sz)),
			DawnMuster.shrine_groups(run.charter_offer, "path"), []):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	for id: String in run.charter_offer:
		var btn := _charter_card(id, CardView.Size.LARGE)
		btn.custom_minimum_size.x = 220
		row.add_child(btn)
	show()


## One charter card: the path, the tier it brings and what that does (a tier II's cost on its own red line).
func _charter_card(id: String, sz: CardView.Size) -> CardView:
	var content := run.content
	var path: Dictionary = content.paths["paths"][id]
	var tier := run.path_tier(id) + 1
	var text: String = run.next_path_tier(id).get("text", "")
	var btn := CardView.new(sz, "path", "Charter · tier %s" % StatusText.roman(tier), path["name"])
	btn.add_chip(path["short"])
	if tier >= content.paths["paths"][id]["tiers"].size():
		btn.set_advice("Capstone")
	elif tier > 1:
		btn.set_advice("Deepens your path")
	# A tier II's cost goes on its own red line (data/paths.json texts end "Cost: ...").
	var parts := text.split(" Cost: ", true, 1)
	btn.set_body(parts[0], CardView.TEXT).set_footer(path["text"])
	if parts.size() > 1:
		btn.add_cost_line("Cost: " + parts[1])
	var favoured: Array = path.get("buildings", []).filter(func(b: String) -> bool: return content.buildings.has(b))
	btn.tooltip_text = "%s\n%s\nIts buildings come up %s times as often in the blueprint draft: %s." % [path["text"], text,
		str(content.int_num("path_card_weight")), ", ".join(favoured.map(func(b: String) -> String: return content.buildings[b]["name"]))]
	btn.pressed.connect(func() -> void: charter_chosen.emit(id))
	return btn


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
		# Distance in the player's words, never map units (docs/TEXT_STYLE.md).
		var reach: String = {"near": "Camps near town", "middle": "Camps a fair walk out", "far": "Camps far out"}.get(d["camp"], "Camps out")
		var where := "%s, %s" % [reach, World.compass(pos.angle())]
		var sells: String = slots.get(d["slot"], d["slot"])
		var btn := CardView.new(CardView.Size.LARGE, "trade", "Pedlar · %s" % d["camp"], d["name"])
		btn.set_picture(SpriteBook.shared().card_texture("pedlar_camp"))
		btn.custom_minimum_size.x = 220
		btn.add_chip("sells " + sells)
		btn.add_chip("tier %d" % run.world.pedlar.ware_tier(id))
		btn.add_chip(where, "map", CardView.TEXT, btn.family_color())
		btn.set_body(d["text"]).set_footer(footer)
		btn.tooltip_text = "%s\nSells %s, about tier %d.\n%s.\n%s" % [d["text"], sells, run.world.pedlar.ware_tier(id), where, footer]
		btn.pressed.connect(func() -> void: pedlar_chosen.emit(id))
		row.add_child(btn)
	# Over the land (picks in the town, slice 4): each card on a line down to the spot where that pedlar would camp.
	_reshow = show_pedlars
	var classic := _classic_once
	_classic_once = false
	if _scenes_on() and not classic:
		var cards: Array = row.get_children()
		for c: Control in cards:
			row.remove_child(c)
			c.custom_minimum_size.x = 0
		row.queue_free()
		var none := UiKit.secondary(Button.new(), 13)
		none.text = "No pedlar"
		none.pressed.connect(func() -> void: pedlar_chosen.emit(""))
		if _over_town(cards, run.pedlar_offer.map(func(o: Dictionary) -> Dictionary: return DraftStage.camp(o["pos"])), note, none):
			return
		_classic_once = true
		show_pedlars()
		return
	_skip_button("No pedlar", func() -> void: pedlar_chosen.emit(""))
	show()


## What stops the town taking a dawn card: no room, or not enough shells.
func _why_not_pick(card: Dictionary) -> String:
	if not card["kind"] in ["promote", "venture", "guild"] and run.population() + run.people.card_people(card) > run.housing():
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
			btn.set_picture(SpriteBook.shared().card_texture(hero.type_id))
			btn.set_price(run.stock, {"shells": card["cost"]})
			btn.add_chip("Lv %d" % hero.level)
			btn.add_chip("You have %d" % run.living_heroes().size())
			btn.add_chip(content.traits[hero.trait_id]["name"])
			if legend != "":
				btn.add_pictures(hero.items.values().map(func(it: Dictionary) -> Texture2D: return SpriteBook.shared().item_texture(it["base"])))
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
				parts.append("%d %s" % [who[role], content.townsfolk[role]["name"].to_lower() if who[role] == 1 else FolkAtWork.plural(run, role)])
			btn = CardView.new(sz, "folk", "Family", "A family")
			btn.set_picture(SpriteBook.shared().card_texture(card["roles"][0]))
			btn.set_price(run.stock, {})
			var roles: Array = card["roles"].duplicate()
			for i in CardRoll.extra_people(content, card):
				roles.append("tribesperson")
			btn.add_people(roles)
			btn.set_body(", ".join(parts) + ".").set_footer("Needs %d beds" % run.people.card_people(card))
			btn.tooltip_text = "A whole family moves in at once: %s.\nEach eats %s a day." % [", ".join(parts), _food_each()]
		"promote":
			btn = _promote_card(card, sz)
		"venture":
			btn = _venture_card(card, sz)
		"guild":
			btn = _guild_card(card, sz)
		_:
			var def: Dictionary = content.townsfolk[card["role"]]
			var roles: Array = [card["role"]]
			for i in CardRoll.extra_people(content, card):
				roles.append(card["role"])
			# Hearth-mother's doll: the card it doubles counts everyone in, and says so.
			var doll := run.doll_twin_next()
			if doll:
				roles.append_array(roles.duplicate())
			if card.has("leaning"):
				var lean: Dictionary = def["leanings"][card["leaning"]]
				var key: String = card["role"] + "/" + card["leaning"]
				var size := int(run.world.folk_ai.count_leanings().get(key, 0))
				var level := run.world.folk_ai.band_level(card["role"], card["leaning"], size)
				var grows := run.world.folk_ai.band_level(card["role"], card["leaning"], size + 1) > level
				btn = CardView.new(sz, "folk", def["name"], lean["name"])
				btn.set_picture(SpriteBook.shared().card_texture(card["role"]))
				if grows:
					btn.set_advice("Forms a band" if level == 0 else "Band grows stronger")
				btn.set_price(run.stock, {})
				btn.add_people(roles)
				_doll_chip(btn, doll)
				_have_chip(btn, card["role"])
				for good: String in lean["goods"].slice(0, 2):
					btn.add_good_label(good)
				btn.set_body(lean["text"]).set_footer(eats)
				btn.tooltip_text = "%s\n%s Still fetches anything the town is short of, but picks trips for %s first.\n%s\n%s." % [
					def["text"], lean["text"], ", ".join(lean["goods"]).replace("_", " "),
					Tooltips.band_line(run, card["role"], card["leaning"], true), eats] + _work_lines(card["role"])
			else:
				btn = CardView.new(sz, "folk", "Townsperson", def["name"])
				btn.set_picture(SpriteBook.shared().card_texture(card["role"]))
				btn.set_price(run.stock, {})
				btn.add_people(roles)
				_doll_chip(btn, doll)
				_have_chip(btn, card["role"])
				btn.set_body(def["text"]).set_footer(eats)
				btn.tooltip_text = "%s\n%s." % [def["text"], eats] + _work_lines(card["role"])
			var doll_line := _doll_line(roles.size(), doll)
			if doll_line != "":
				var relic: Dictionary = content.relics["hearth_mothers_doll"]
				btn.tip_names[relic["name"]] = content.rarity_color(content.rarity_of("relic", "hearth_mothers_doll"))
				btn.tooltip_text += "\n" + doll_line
				if doll:
					btn.add_lead(doll_line)
	return btn


## The Doll's chip on the townsfolk card it will double.
func _doll_chip(btn: CardView, doll: bool) -> void:
	if doll:
		btn.add_chip("Doll: doubled", "relic", CardView.GOOD)


## What Hearth-mother's doll does on this dawn's townsfolk cards, for the hover panel ("" without the Doll).
func _doll_line(people: int, doll: bool) -> String:
	var left := run.doll_picks_to_twin()
	if left == 0:
		return ""
	if doll:
		return "Hearth-mother's doll doubles this pick: %d people in all." % people
	return "Hearth-mother's doll doubles the %s townsfolk card you take from now." % ["next", "second", "third"][mini(left, 3) - 1]


## How many of this role the town has now, so a dawn pick reads as "a fourth warrior" rather than "a warrior".
func _have_chip(btn: CardView, role: String) -> void:
	btn.add_chip("You have %d" % run.count_role(role))
	var word := run.people.busy_word(role)
	if word != "":
		btn.add_chip(FolkAtWork.word_name(word), "", FolkAtWork.word_tint(word))


## The townsfolk card's hover lines on how that role spent the round (FolkAtWork.card_lines), after a newline, or "".
func _work_lines(role: String) -> String:
	var lines := FolkAtWork.card_lines(run, role)
	return "" if lines.is_empty() else "\n" + "\n".join(lines)


## The building a tradition's first blueprint raises, for its card's picture (a craft shows its workshop).
func _tradition_building(t: Dictionary) -> String:
	var key: String = t.get("blueprint", "")
	if key.begins_with("craft:"):
		return run.content.crafts[key.trim_prefix("craft:")]["workshop"]
	return key


## A trades guild: the band at its top tier learns a practice that keeps its nodes from running dry, and keeps to its trade.
func _guild_card(card: Dictionary, sz := CardView.Size.LARGE) -> CardView:
	var leaning: String = card["leaning"]
	var g := run.people.guild_def(leaning)
	var size := int(run.world.folk_ai.count_leanings().get("tribesperson/" + leaning, 0))
	var btn := CardView.new(sz, "guild", "Trades guild", g["name"])
	btn.set_picture(SpriteBook.shared().card_texture("tribesperson"))
	btn.set_price(run.stock, {})
	btn.add_chip(g["practice"], "", CardView.GOOD)
	btn.add_chip("Band of %d" % size)
	btn.add_chip("Keeps to its trade", "", CardView.DANGER)
	btn.set_body(g["text"], CardView.TEXT).set_footer("Instead of a newcomer")
	btn.tooltip_text = "Charter the %s band as the %s.\n%s\nFrom now on its members keep to their trade: they only fetch %s, even when the town is short of something else, and never lend a hand at buildings.\nInstead of a newcomer today; offered until you take it." % [
		run.folk_name("tribesperson", leaning).to_lower(), g["name"], g["text"],
		", ".join(run.content.townsfolk["tribesperson"]["leanings"][leaning]["goods"]).replace("_", " ")]
	return btn


## A venture: send tribespeople out, some never come back, the rest bring goods home.
func _venture_card(card: Dictionary, sz := CardView.Size.LARGE) -> CardView:
	var v: Dictionary = run.content.ventures[card["venture"]]
	var terms := run.people.venture_terms(card["venture"], card)
	var lose: Array = terms["lose"]
	var losing := "%d" % lose[0] if lose[0] == lose[1] else "%d-%d" % [lose[0], lose[1]]
	var brings := ", ".join(terms["goods"].keys().map(func(g: String) -> String: return "%d %s" % [terms["goods"][g], g.replace("_", " ")]))
	var btn := CardView.new(sz, "venture", "Venture · send %d" % terms["send"], v["name"])
	btn.set_picture(SpriteBook.shared().card_texture("tribesperson"))
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
	line.add_theme_font_size_override("font_size", UiKit.TITLE)
	if lost == 0:
		line.text = "All %d tribespeople came home." % result["send"]
		line.add_theme_color_override("font_color", VentureFigures.HOME_COLOR)
	else:
		line.text = "%d of %d tribespeople never came home." % [lost, result["send"]]
		line.add_theme_color_override("font_color", VentureFigures.X_COLOR)
	_box.add_child(line)
	var goods: Dictionary = result["goods"]
	var brought := ", ".join(goods.keys().map(func(g: String) -> String: return "%d %s" % [goods[g], g.replace("_", " ")]))
	UiKit.note(_box, "They bring home %s." % brought, UiKit.STRONG, UiKit.INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var center := CenterContainer.new()
	_box.add_child(center)
	UiKit.primary(UiKit.button(center, "Carry on", func() -> void: closed.emit())).custom_minimum_size = Vector2(220, 36)
	show()
	# At the dawn muster the party is walking home on the map: the result waits at the map's top, undimmed, and
	# shows once they are back (DawnMuster.homecoming).
	if arena != null and arena.muster.homecoming():
		mustering = true
		self_modulate.a = 0.0
		_panel.visible = false
		_place_header()


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
			btn.set_picture(SpriteBook.shared().card_texture(hero.type_id))
			btn.add_chip("%d kills" % u.kills)
			btn.add_chip("→ %s %s" % [content.traits[hero.trait_id]["name"].to_lower(), cls.to_lower()], "", CardView.GOOD)
			btn.set_footer("Needs a bed like any hero")
			btn.tooltip_text = "A warrior with %d kills, here since round %d, becomes %s, %s %s, level %d.\nNeeds a bed like any hero." % [
				u.kills, u.joined_round, hero.display_name, content.traits[hero.trait_id]["name"], cls.to_lower(), hero.level]
		"champion":
			var hero: Unit = card["hero"]
			var knight: String = content.hero_classes[content.promotions["champion"]["becomes"]]["name"]
			btn = CardView.new(sz, "promote", "Knight a champion", hero.display_name)
			btn.set_picture(SpriteBook.shared().card_texture(content.promotions["champion"]["becomes"]))
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
			btn.set_picture(SpriteBook.shared().card_texture("craftsperson"))
			btn.add_chip("%s master of the %s" % [t["name"], shop], "", CardView.GOOD)
			btn.set_body(", ".join(Tooltips.master_effects(content, card["trait"], card["workshop"], true)) + ".", CardView.TEXT)
			btn.tooltip_text = "A craftsperson who made %d goods at the %s becomes %s, master of the %s.\n%s: %s\n%s.\nA master goes to their own bench before any other." % [
				int(u.made[card["workshop"]]), shop, card["name"], shop, t["name"], t["text"], ".\n".join(effects)]
	btn.set_price(run.stock, {"shells": card["cost"]})
	return btn


## Where a hero of this trait goes by day, as one line for the card.
func _wilds_line(trait_id: String) -> String:
	var w := float(run.content.traits[trait_id]["wilds"])
	return "Hunts far out at the dens by day." if w > 0.6 else ("Stays near the town." if w < 0.2 else "Ventures out sometimes.")


func _trait_hint(trait_id: String) -> String:
	var t: Dictionary = run.content.traits[trait_id]
	var wilds := "hunts far out at the dens by day" if float(t["wilds"]) > 0.6 else ("stays near the town" if float(t["wilds"]) < 0.2 else "ventures out sometimes")
	return "%s: %s, retreats at %d%% health, goes to rest when energy falls to %d." % [t["name"], wilds,
		roundi(float(t["retreat_at"]) * 100.0), int(t.get("tired_at", 25))]


## One line on what happened last night, above the dawn and relic picks, with `extra` (shells and room at dawn)
## on the same line so the window stays short.
func _night_summary(extra := "") -> void:
	var n := run.last_night
	if n.is_empty():
		if extra != "":
			UiKit.note(_box, extra, UiKit.STRONG, UiKit.INK).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var deaths: Array = n["deaths"]
	var left: Array = n.get("left", [])
	# Chronicle voice (docs/TEXT_STYLE.md): what happened, in a sentence, not a row of figures.
	var text := "Night %d: %d raider%s came, and the town felled %d. %s " % [n["night"], n["raiders"],
		"" if int(n["raiders"]) == 1 else "s", n["kills"],
		"The hearth took no harm." if int(n["hearth_damage"]) == 0 else "The hearth took %d damage." % n["hearth_damage"]]
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
	label.add_theme_color_override("font_color", UiKit.EMBER if not lost.is_empty() else UiKit.GOOD)
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
	# One line, never wrapped (a label made to wrap and then unwrapped keeps its tall wrapped size a frame).
	var label := Label.new()
	label.text = ImpactView.headline(run, shown["impact"])
	label.add_theme_font_size_override("font_size", UiKit.BODY)
	label.add_theme_color_override("font_color", UiKit.HEADING_COLOR)
	line.add_child(label)
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
	_reshow = show_relic_pick
	# At the shrine by the hearth (picks in the town, slice 5): the Elder presents the cards over standing stones.
	if _shrine([], func(sz: CardView.Size) -> Array: return run.relic_offer.map(func(id: String) -> CardView: return _relic_card(id, sz)),
			DawnMuster.shrine_groups(run.relic_offer, "relic"), [["Skip the relic", func() -> void: relic_picked.emit("")]]):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	for id in run.relic_offer:
		row.add_child(_relic_card(id))
	_skip_button("Skip the relic", func() -> void: relic_picked.emit(""))
	show()


## A pick at the shrine by the hearth (picks in the town, slice 5: relics, pacts, spoils, glory and charters): the
## cards (`cards`, freed here when it can't be) in a row over standing stones (`groups`, DawnMuster.shrine_groups)
## with the Elder presenting them, `footer` buttons as `_muster_with`. Over the build hand the cards are medium and
## `notes` (lines under the title) go to the title's hover. False when the setting is off or the cards won't fit:
## the caller builds the classic pop-up.
func _shrine(notes: Array, make: Callable, groups: Array, footer: Array) -> bool:
	var classic := _classic_once
	_classic_once = false
	if classic or not _scenes_on():
		return false
	var over_hand := hand_view != null and hand_view.is_visible_in_tree()
	var sz := CardView.Size.MEDIUM if over_hand or groups.size() > 4 else CardView.Size.LARGE
	var cards: Array = make.call(sz)
	for c: CardView in cards:
		c.custom_minimum_size.x = 0
	if over_hand and not notes.is_empty():
		var title: Control = _box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())[0]
		title.tooltip_text = "\n".join(notes.map(func(n: Label) -> String: return n.text))
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		for n: Label in notes:
			n.visible = false
	if _muster_with(cards, groups, sz, footer):
		return true
	for n: Label in notes:
		n.visible = true
	return false


## One relic, pact or spoils card (CardView). Relics don't roll, so the frame is the relic's own rarity. Chips name
## the tags a tag-keyed relic acts on; spoils show what taking them brings now.
func _relic_card(id: String, sz := CardView.Size.LARGE) -> CardView:
	var content := run.content
	var r: Dictionary = content.relics[id]
	var is_spoils: bool = id == run.spoils.get("id", "")
	var kind := "Pact" if "pact" in content.tags_of("relic", id) else "Relic"
	var text: String = r["text"]
	if is_spoils:
		kind = "Spoils of the %s" % str(content.balance.get("spoils_kinds", {}).get(run.spoils["kind"], run.spoils["kind"]))
	var btn := CardView.new(sz, "spoils" if is_spoils else "relic", kind, r["name"])
	if sz == CardView.Size.LARGE:
		btn.custom_minimum_size.x = 206
	btn.set_picture(SpriteBook.shared().relic_texture(id))
	btn.set_roll(content, content.rarity_of("relic", id), "white", [])
	btn.set_body(text, CardView.TEXT)
	# One chip per tag the relic keys on, however many of its effects name it (an affinity names one tag several times).
	var chips: Array[String] = []
	for key: String in RunState.TAG_EFFECTS:
		for tag: String in r.get("effects", {}).get(key, {}):
			if not chips.has(tag):
				chips.append(tag)
	for tag in chips:
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
		footer = "Instead of a relic"
	btn.set_footer(footer)
	var tags := Tooltips.tag_notes(run, "relic", id)
	btn.tooltip_text = text + ("\n" + footer + "." if footer != "" else "") + ("\nTags: " + "\n".join(tags) if not tags.is_empty() else "")
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
	summary.text = "Seed %d  ·  Heroes lost %d  ·  Townsfolk lost %d  ·  Relics %s" % [run.run_seed, run.fallen.size(), run.fallen_folk,
		", ".join(run.relics.map(func(id: String) -> String: return content.relics[id]["name"])) if not run.relics.is_empty() else "none"]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.custom_minimum_size.x = 420
	_box.add_child(summary)
	if not won:
		UiKit.note(_box, content.tips["welcome"]["lost_line"], UiKit.STRONG, Color("#d9cbb3")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	stats.add_theme_font_size_override("font_size", UiKit.BODY)
	_box.add_child(stats)
	var hint := Label.new()
	hint.text = "To share runs, download them as one file and attach it to a chat message."
	hint.add_theme_font_size_override("font_size", UiKit.CAPTION)
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
		label.add_theme_font_size_override("font_size", UiKit.BODY)
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
	text.add_theme_font_size_override("normal_font_size", UiKit.BODY)
	text.add_theme_font_size_override("bold_font_size", UiKit.BODY)
	var lines := PackedStringArray()
	for i in run.story.size():
		lines.append(StoryLog.as_bbcode(run, i))
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


## Your people (needs a Reeve's hut): how each kind of townsperson spent the round (FolkAtWork.build).
func show_people() -> void:
	_clear()
	var b := run.people.busy_of("tribesperson")
	_title("Your people %s" % ("this round so far" if b["from"] == "this" else "last round"))
	UiKit.note(_box, "How each kind of townsperson spent the round, and what came of it. Townsfolk count by day; " +
		"warriors by night too. Stretched: another would earn their keep. Slack: another mostly adds upkeep.", 11)
	FolkAtWork.build(_box, run)
	UiKit.button(_box, "Back", func() -> void: closed.emit())
	show()


func _clear() -> void:
	showing_draft = false
	showing_welcome = false
	showing_pick = false
	_pick_buttons.clear()
	_peek(null)
	for child in _box.get_children():
		child.queue_free()
	if arena != null:
		arena.draft.finish(Time.get_ticks_msec())
	_reshow = Callable()
	mustering = false
	self_modulate.a = 1.0
	_panel.visible = true
	for child in _stage.get_children():
		child.queue_free()


func _title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.add_theme_font_size_override("font_size", UiKit.HEADING)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
