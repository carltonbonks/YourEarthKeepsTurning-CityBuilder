class_name Advisor
extends Control
## The Elder (Yusuf, 2026-10-27, plan https://claude.ai/artifact/N1PyHSj9jiSMimZFcdPPxr): a small portrait by
## the cards that says one line, only while the player is choosing (the build hand, the dawn pick), and only
## when a problem will cost the town this round and a card on screen would help. "Show me" draws a soft
## ember frame round that card (no dimming, nothing picked); "Not now" quiets that problem until the next
## round and leaves an ember dot on the portrait, and a problem waved off `silence_after` times is never
## raised again that run. At most one line at a time and `per_round` a round; it waits while a one-time
## highlight (FirstTips) is up, and keeps quiet through a first run's first round. The look and name follow
## the town's age (the Elder, the Priestess, the Steward). Words and numbers in data/tips.json "advisor";
## the player's setting (Off, Urgent only, Chatty) in GameSettings.advisor. `concerns` is the read-only
## rule, so tests can check it. A problem with nothing on screen to answer it stays a plain alert (Alerts).

const EMBER := Color("#e8892b")
const INK := Color("#ffe6c4")
const QUIET := Color("#c8b49a")
const PORTRAIT := 56.0
const BUBBLE_WIDTH := 310.0
const SLIDE_SECONDS := 0.5
const GAP := 8.0

## Where the hand's card for a building is on screen: called with a type, returns a global rect (empty if not showing).
var build_card_rect := Callable()
## Where dawn card i is on screen: called with an index, returns a global rect.
var pick_card_rect := Callable()
## What the Elder sits beside: called with no arguments, returns the global rect of the hand or the dawn pick.
var anchor_rect := Callable()
var settings: GameSettings
var run: RunState

## The concern speaking now ({id, text, fix}), or empty.
var _speaking := {}
var _show_me := false
var _shown_at := 0.0
## id -> the round "Not now" was pressed in (quiet until the next round).
var _muted := {}
## id -> times waved off this run.
var _waved := {}
## ids spoken this round, and the round they count for.
var _spoken: Array[String] = []
var _spoken_round := -1
var _portrait: Control
var _bubble: PanelContainer
var _line: Label
var _fix: Label


## Who advises in this age: {name, robe, trim}.
static func look(r: RunState) -> Dictionary:
	var ages: Dictionary = r.content.tips["advisor"]["ages"]
	return ages.get(r.age, ages["neolithic"])


## True while the player is choosing something the Elder can point at: the build hand (no draft, tradition,
## charter or pedlar pick waiting) or the dawn pick. Never in a first run's first round.
static func can_speak(r: RunState) -> bool:
	if r.is_over() or r.awaiting_traditions() or r.awaiting_charter() or r.awaiting_pedlar():
		return false
	if r.gentle and r.round_number <= 1:
		return false
	match r.phase:
		RunState.Phase.BUILD:
			return not (r.hand.picks > 0 and r.hand.has_offers())
		RunState.Phase.PICK:
			return true
	return false


## The problems worth a word right now, most urgent first, each with the card that would help:
## [{id, text, fix: {kind: "build", type} or {kind: "pick", index}, fix_text}]. Ids match Alerts' ids.
## level is the setting: "urgent", "chatty" (looser thresholds) or "off" (nothing).
static func concerns(r: RunState, level := "urgent") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if level == "off" or not can_speak(r):
		return out
	var data: Dictionary = r.content.tips["advisor"]
	var lv: Dictionary = data["levels"].get(level, data["levels"]["urgent"])
	var lines: Dictionary = data["lines"]
	var w := r.world
	var found: Array[Dictionary] = []
	if w.hearth_hp < r.hearth_max_hp() * float(lv["hearth_share"]):
		found.append({"id": "hearth", "text": lines["hearth"]})
	# The night-3 attack against the town's fighters, on the attack card's scale (Power).
	var ratio := Power.wave(r.content, r.waves.attack()) / maxf(1.0, float(Power.town(w)["total"]))
	if ratio > float(lv["outmatch"]):
		found.append({"id": "outmatched", "text": lines["outmatched"]})
	var days := StatusText.food_days(r)
	if days >= 0.0 and days < float(lv["food_days"]):
		found.append({"id": "food", "text": str(lines["food"]).format({"when": lines["food_soon" if days < 1.0 else "food_later"]})})
	var nights := StatusText.fuel_nights(r)
	if nights >= 0.0 and nights < float(lv["fuel_nights"]):
		found.append({"id": "fuel", "text": str(lines["fuel"]).format({"when": lines["fuel_soon" if nights < 1.0 else "fuel_later"]})})
	var pending := w.buildings.any(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0)
	if pending and r.count_role("craftsperson") == 0:
		found.append({"id": "builders", "text": lines["builders"]})
	for hero in r.living_heroes():
		if hero.mood <= r.content.num("mood_grumble_at"):
			found.append({"id": "mood:" + hero.display_name, "text": str(lines["mood"]).format({"hero": hero.display_name})})
	# A role that mostly stood idle last round (Slack on its dawn card, People.busy_word): work for them is a building.
	if r.phase == RunState.Phase.BUILD:
		for role: String in lines["slack_roles"]:
			if r.count_role(role) > 0 and r.people.busy_word(role) == "slack":
				found.append({"id": "slack:" + role, "text": str(lines["slack"]).format({"people": lines["slack_roles"][role]})})
	for c in found:
		var fix := fix_for(r, c["id"])
		if fix.is_empty():
			continue
		c["fix"] = fix
		c["fix_text"] = str(lines["fix"]).format({"card": fix["name"]})
		out.append(c)
	return out


## The card on screen that answers concern `id`, or {} when none can be taken now.
static func fix_for(r: RunState, id: String) -> Dictionary:
	var content := r.content
	if r.phase == RunState.Phase.BUILD:
		for type in BuildHandView.hand_types(r):
			if r.hand.can_order(type) and _build_answers(r, id, type):
				return {"kind": "build", "type": type, "name": str(content.buildings[type]["name"]).to_lower()}
		return {}
	if r.phase != RunState.Phase.PICK:
		return {}
	# A card leaning the right way beats a plain one of the right role.
	var best := -1
	var best_score := 0
	for i in r.pick_offer.size():
		var score := _pick_answers(r, id, r.pick_offer[i])
		if score > best_score and r.can_take_pick(i):
			best = i
			best_score = score
	if best < 0:
		return {}
	return {"kind": "pick", "index": best, "name": _card_name(r, r.pick_offer[best])}


static func _build_answers(r: RunState, id: String, type: String) -> bool:
	var def: Dictionary = r.content.buildings[type]
	if id == "food":
		return r.hand.feeds(type)
	if id == "fuel":
		return r.hand.makes_fuel(type)
	if id == "hearth" or id == "outmatched":
		return def.has("attack") or def.has("hearth_hp")
	if id == "slack:craftsperson":
		return def.has("workshop")
	if id == "slack:tribesperson":
		return def.has("tends") or (def.has("assist") and not def.has("workshop"))
	if id.begins_with("mood:"):
		return def.has("lodging")
	return false


## How well a dawn card answers a concern: 0 not at all, 1 the right role, 2 the right role leaning toward the good.
static func _pick_answers(r: RunState, id: String, card: Dictionary) -> int:
	var role: String = card.get("role", "")
	if card["kind"] == "hero":
		return 1 if id == "hearth" or id == "outmatched" else 0
	if card["kind"] != "folk":
		return 0
	if id == "builders":
		return 1 if role == "craftsperson" else 0
	if id == "hearth" or id == "outmatched":
		return 1 if r.content.has_tag("townsfolk", role, "fighter") else 0
	if id == "food" or id == "fuel":
		if role != "tribesperson":
			return 0
		var leaning: String = card.get("leaning", "")
		if leaning == "":
			return 1
		# A tribesperson leaning toward other goods (a woodcutter) won't fetch this one.
		var goods: Array = r.content.townsfolk[role]["leanings"][leaning].get("goods", [])
		return 2 if goods.has(id) else 0
	return 0


static func _card_name(r: RunState, card: Dictionary) -> String:
	if card["kind"] == "hero":
		return "hero"
	var role: String = card["role"]
	var leaning: String = card.get("leaning", "")
	if leaning != "":
		return str(r.content.townsfolk[role]["leanings"][leaning]["name"]).to_lower()
	return str(r.content.townsfolk[role]["name"]).to_lower()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait = Control.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT, PORTRAIT)
	_portrait.size = _portrait.custom_minimum_size
	_portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	_portrait.draw.connect(_draw_portrait)
	_portrait.gui_input.connect(func(e: InputEvent) -> void:
		# A click on the portrait brings back a line waved off this round.
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_unmute())
	add_child(_portrait)
	_bubble = PanelContainer.new()
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.12, 0.07, 0.95)
	style.border_color = EMBER
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_bubble.add_theme_stylebox_override("panel", style)
	add_child(_bubble)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_bubble.add_child(box)
	_line = UiKit.note(box, "", 15, INK)
	_line.custom_minimum_size.x = BUBBLE_WIDTH - 24.0
	_fix = UiKit.note(box, "", 13, QUIET)
	_fix.custom_minimum_size.x = BUBBLE_WIDTH - 24.0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	row.add_child(_button("Show me", true, func() -> void:
		_show_me = not _show_me
		queue_redraw()))
	row.add_child(_button("Not now", false, _wave_off))
	_bubble.hide()
	_portrait.hide()


func _button(text: String, strong: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(EMBER, 0.25) if strong else Color(0, 0, 0, 0)
	s.border_color = EMBER if strong else Color(QUIET, 0.5)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	var hover := s.duplicate() as StyleBoxFlat
	hover.bg_color = Color(EMBER, 0.45)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", INK if strong else QUIET)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(on_press)
	return b


## A new run: the Elder forgets what was waved off.
func reset() -> void:
	_muted.clear()
	_waved.clear()
	_spoken.clear()
	_spoken_round = -1
	_speaking = {}
	_show_me = false
	_bubble.hide()


## The concern speaking now, or "" (Alerts keeps quiet about it meanwhile).
func speaking_id() -> String:
	return _speaking.get("id", "") if _bubble.visible else ""


## Picks what to say, if anything. `blocked` (a menu, a highlight, the tour) hides the Elder for now.
func check(blocked: bool) -> void:
	var level: String = settings.advisor if settings != null else "urgent"
	if run == null or blocked or level == "off" or not can_speak(run):
		_portrait.hide()
		_quiet()
		return
	if _spoken_round != run.round_number:
		_spoken_round = run.round_number
		_spoken.clear()
	var per_round: int = int(run.content.tips["advisor"]["per_round"])
	var silence: int = int(run.content.tips["advisor"]["silence_after"])
	var pick := {}
	for c in concerns(run, level):
		var id: String = c["id"]
		if int(_waved.get(id, 0)) >= silence or int(_muted.get(id, -1)) == run.round_number:
			continue
		if not _spoken.has(id) and _spoken.size() >= per_round:
			continue
		pick = c
		break
	_portrait.show()
	if pick.is_empty():
		_quiet()
	else:
		if _speaking.get("id", "") != pick["id"] or not _bubble.visible:
			_show_me = false
			_shown_at = Time.get_ticks_msec() / 1000.0
			if not _spoken.has(pick["id"]):
				_spoken.append(pick["id"])
		_speaking = pick
		_line.text = pick["text"]
		_fix.text = pick["fix_text"]
		_bubble.show()
	_place()
	var who := look(run)
	_portrait.tooltip_text = "%s speaks up when the town is in trouble and a card on screen would help.%s" % [who["name"],
		"\nClick to hear what you waved off." if _muted_now() and not _bubble.visible else ""]
	_portrait.queue_redraw()
	queue_redraw()


## The rect the Elder takes up now (portrait and line), global, for laying out the panels round it.
func taken_rect() -> Rect2:
	if not _portrait.visible or not is_inside_tree():
		return Rect2()
	var r := _portrait.get_global_rect()
	if _bubble.visible:
		r = r.merge(_bubble.get_global_rect())
	return r


func _quiet() -> void:
	_bubble.hide()
	_speaking = {}
	_show_me = false
	queue_redraw()


func _wave_off() -> void:
	var id: String = _speaking.get("id", "")
	if id == "":
		return
	_muted[id] = run.round_number
	_waved[id] = int(_waved.get(id, 0)) + 1
	_quiet()
	_portrait.queue_redraw()


func _unmute() -> void:
	var any := false
	for id: String in _muted.keys():
		if int(_muted[id]) == run.round_number:
			_muted.erase(id)
			_waved[id] = maxi(0, int(_waved.get(id, 0)) - 1)
			any = true
	if any:
		check(false)


func _muted_now() -> bool:
	return run != null and _muted.values().any(func(r: int) -> bool: return r == run.round_number)


## The portrait sits just above the hand's (or the dawn pick's) top-left corner, the line beside it; when there is
## no room above, at the screen's bottom-left.
func _place() -> void:
	if not is_inside_tree():
		return
	var anchor: Rect2 = anchor_rect.call() if anchor_rect.is_valid() else Rect2()
	var origin := get_global_rect().position
	var bubble_size := _bubble.get_combined_minimum_size() if _bubble.visible else Vector2.ZERO
	var h := maxf(PORTRAIT, bubble_size.y)
	var p: Vector2
	if anchor.has_area() and anchor.position.y - GAP - h >= origin.y + GAP:
		p = Vector2(anchor.position.x + GAP, anchor.position.y - GAP - h)
	else:
		p = Vector2(origin.x + GAP, origin.y + size.y - GAP - h)
	var local := p - origin
	_portrait.position = Vector2(local.x, local.y + h - PORTRAIT)
	# It slides in from the left over half a second.
	var t := clampf((Time.get_ticks_msec() / 1000.0 - _shown_at) / SLIDE_SECONDS, 0.0, 1.0)
	var slide := 1.0 - pow(1.0 - t, 3.0)
	_bubble.reset_size()
	_bubble.position = Vector2(local.x + PORTRAIT + GAP - 24.0 * (1.0 - slide), local.y + h - bubble_size.y)
	_bubble.modulate.a = slide


func _process(_delta: float) -> void:
	if _bubble.visible:
		_place()
		if _show_me:
			queue_redraw()


## The fix's card on screen, or an empty rect.
func fix_rect() -> Rect2:
	var fix: Dictionary = _speaking.get("fix", {})
	if fix.is_empty():
		return Rect2()
	if fix["kind"] == "build":
		return build_card_rect.call(fix["type"]) if build_card_rect.is_valid() else Rect2()
	return pick_card_rect.call(fix["index"]) if pick_card_rect.is_valid() else Rect2()


## Show me: a soft ember frame, dashed and breathing, round the card that would help. Nothing dims.
func _draw() -> void:
	if not (_show_me and _bubble.visible):
		return
	var r := fix_rect()
	if not r.has_area():
		return
	r = Rect2(r.position - get_global_rect().position, r.size).grow(6.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
	var c := Color(EMBER, 0.7 + 0.3 * pulse)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], c, 3.0, 10.0)
	draw_rect(r.grow(4.0 + 2.0 * pulse), Color(EMBER, 0.18), false, 2.0)


## A hooded figure in the age's colours, ringed in ember while speaking; an ember dot when a line was waved off.
func _draw_portrait() -> void:
	if run == null:
		return
	var who := look(run)
	var robe := Color(who["robe"])
	var trim := Color(who["trim"])
	var c := Vector2(PORTRAIT, PORTRAIT) * 0.5
	var radius := PORTRAIT * 0.5 - 2.0
	_portrait.draw_circle(c, radius, Color(0.12, 0.1, 0.09, 0.95))
	# Shoulders and hood.
	var shoulders := PackedVector2Array([c + Vector2(-radius * 0.8, radius * 0.75), c + Vector2(-radius * 0.45, radius * 0.05),
		c + Vector2(0, -radius * 0.25), c + Vector2(radius * 0.45, radius * 0.05), c + Vector2(radius * 0.8, radius * 0.75)])
	_portrait.draw_colored_polygon(shoulders, robe)
	_portrait.draw_circle(c + Vector2(0, -radius * 0.2), radius * 0.38, robe)
	_portrait.draw_circle(c + Vector2(0, -radius * 0.14), radius * 0.24, Color("#d9b48c"))
	# The age's mark: a band on the brow (circlet, cap) in its trim colour.
	_portrait.draw_line(c + Vector2(-radius * 0.26, -radius * 0.34), c + Vector2(radius * 0.26, -radius * 0.34), trim, 3.0)
	var speaking := _bubble.visible
	_portrait.draw_arc(c, radius, 0.0, TAU, 40, EMBER if speaking else Color(0.5, 0.48, 0.45, 0.7), 3.0 if speaking else 1.5, true)
	if _muted_now() and not speaking:
		_portrait.draw_circle(c + Vector2(radius * 0.7, -radius * 0.7), 6.0, EMBER)
