class_name FirstTips
extends Control
## One-time highlights (Yusuf, 2026-10-26, replacing paper tips): the first time each thing happens (the
## tradition, the first draft, build and Begin round, dawn, hero card, night, attack, relic, turn of the
## earth, age card), a hi-viz frame goes round the part of the screen it is about, the rest of the screen
## dims, and a short note sits beside it. One at a time, never pausing. A highlight closes once its moment
## passes, which is the player doing the thing it points at; a few that point at nothing to do (ok in the
## data) have a Got it button. Seen ones are kept in GameSettings.tips_seen. Words and targets are in
## data/tips.json; `due` says which moments are here, read-only.

const HIVIZ := Color("#ffd21a")
const INK := Color("#1c1710")
const DIM := Color(0, 0, 0, 0.5)
const WIDTH := 330.0
## Room left round a framed part, and the frame's yellow, black and yellow bands.
const PAD := 6.0
const GAP := 14.0

## Where a target is on screen: called with a target name (panel, core, begin, upgrades, threat, food), returns
## its global rect, or an empty Rect2 when it isn't showing.
var target_rect := Callable()
## Where the note goes when nothing is framed (target map): called with its size, returns its position.
var map_anchor := Callable()
var settings: GameSettings
var content: Content
var _shown := ""
## True once the highlight showing has been on screen (one hidden while its target was away isn't seen).
var _displayed := false
var _rects: Array[Rect2] = []
var _note: PanelContainer
var _kicker: Label
var _text: Label
var _ok: Button


## The highlights whose moment is here in this run (seen or not), in data order.
static func due(run: RunState) -> Array[String]:
	var now := {}
	var deciding := run.awaiting_traditions() or run.awaiting_pedlar()
	match run.phase:
		RunState.Phase.BUILD:
			var drafting := run.hand.picks > 0 and run.hand.has_offers()
			now["first_tradition"] = run.awaiting_traditions()
			if not deciding:
				now["first_draft"] = drafting
				if not drafting:
					var built: bool = run.record.entry.get("actions", []).any(func(a: Dictionary) -> bool: return a["kind"] == "build")
					now["first_build"] = not built
					now["first_begin"] = built
					now["first_earth"] = run.round_number >= 2
					now["first_age"] = not run.hand.milestone.is_empty()
		RunState.Phase.PICK:
			now["first_dawn"] = true
			now["first_hero"] = run.pick_offer.any(func(c: Dictionary) -> bool: return c["kind"] == "hero")
		RunState.Phase.SIM:
			var w := run.world
			now["first_night"] = w.is_night() and not w.is_wave_night()
			now["first_attack"] = w.day_index() == run.content.int_num("days_per_round") - 1 and w.is_dusk() and not w.wave_spawned
		RunState.Phase.RELIC:
			now["first_relic"] = true
	var out: Array[String] = []
	for id: String in run.content.tips["tips"]:
		if now.get(id, false):
			out.append(id)
	return out


## The targets a highlight frames, as a list (none for the map).
static func targets(tip: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var t: Variant = tip.get("target", "map")
	for name: String in (t if t is Array else [t]):
		if name != "map":
			out.append(name)
	return out


## The parts of the screen to leave undimmed round `holes`: the screen cut into cells along every hole's edges,
## keeping the cells outside every hole. Pure, so it can be tested.
static func dim_cells(screen: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var xs := [screen.position.x, screen.end.x]
	var ys := [screen.position.y, screen.end.y]
	for h in holes:
		for x in [h.position.x, h.end.x]:
			if x > screen.position.x and x < screen.end.x:
				xs.append(x)
		for y in [h.position.y, h.end.y]:
			if y > screen.position.y and y < screen.end.y:
				ys.append(y)
	xs.sort()
	ys.sort()
	var out: Array[Rect2] = []
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var cell := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if cell.size.x <= 0.0 or cell.size.y <= 0.0:
				continue
			if not holes.any(func(h: Rect2) -> bool: return h.encloses(cell)):
				out.append(cell)
	return out


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note = PanelContainer.new()
	_note.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = HIVIZ
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	_note.add_theme_stylebox_override("panel", style)
	_note.custom_minimum_size.x = WIDTH
	add_child(_note)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_note.add_child(box)
	_kicker = UiKit.note(box, "", 11, Color("#5a4500"))
	_text = UiKit.note(box, "", 16, INK)
	_text.custom_minimum_size.x = WIDTH - 24.0
	var row := HBoxContainer.new()
	box.add_child(row)
	var off := Button.new()
	off.text = "Turn tips off"
	off.flat = true
	off.focus_mode = Control.FOCUS_NONE
	off.add_theme_color_override("font_color", Color("#5a4500"))
	off.add_theme_color_override("font_hover_color", INK)
	off.add_theme_font_size_override("font_size", 13)
	off.pressed.connect(func() -> void:
		settings.tips = false
		settings.save()
		_close())
	row.add_child(off)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_ok = Button.new()
	_ok.text = "Got it"
	_ok.focus_mode = Control.FOCUS_NONE
	_ok.custom_minimum_size = Vector2(84, 34)
	var dark := StyleBoxFlat.new()
	dark.bg_color = INK
	dark.set_corner_radius_all(4)
	for state: String in ["normal", "hover", "pressed"]:
		_ok.add_theme_stylebox_override(state, dark)
	_ok.add_theme_color_override("font_color", HIVIZ)
	_ok.add_theme_color_override("font_hover_color", Color.WHITE)
	_ok.pressed.connect(func() -> void:
		_mark_seen(_shown)
		_close())
	row.add_child(_ok)
	hide()


## Shows the first unseen highlight whose moment is here, or keeps the one showing; `blocked` (a menu, the title
## screen or the tour is up) hides it for now without marking it seen.
func check(run: RunState, blocked: bool) -> void:
	if blocked or settings == null or not settings.tips:
		hide()
		return
	var now := due(run)
	if _shown != "" and not now.has(_shown):
		# Its moment passed while it showed: the player did what it pointed at.
		if _displayed:
			_mark_seen(_shown)
		_shown = ""
	if _shown == "":
		for id in now:
			if not settings.tips_seen.has(id):
				_shown = id
				_displayed = false
				break
	if _shown == "":
		hide()
		return
	var tip: Dictionary = content.tips["tips"][_shown]
	_rects.clear()
	for name in targets(tip):
		var r: Rect2 = target_rect.call(name) if target_rect.is_valid() else Rect2()
		if r.has_area():
			_rects.append(r.grow(PAD))
	if _rects.is_empty() and not targets(tip).is_empty():
		hide()  # What it points at isn't on screen yet (a pick waiting for the earth's turn).
		return
	var total: int = content.tips["tips"].size()
	_kicker.text = "%s  ·  TIP %d OF %d" % [str(tip["title"]).to_upper(), mini(total, settings.tips_seen.size() + 1), total]
	_text.text = tip["text"]
	_ok.visible = tip.get("ok", false)
	_note.reset_size()
	_displayed = true
	show()
	_place_note(_note.get_combined_minimum_size())
	queue_redraw()


func shown_id() -> String:
	return _shown if visible else ""


## The parts of the screen framed now (global rects, padded).
func framed() -> Array[Rect2]:
	return _rects


func _process(_delta: float) -> void:
	if visible and not _rects.is_empty():
		queue_redraw()


func _draw() -> void:
	if _rects.is_empty():
		return
	var offset := get_global_rect().position
	var local: Array[Rect2] = []
	for r in _rects:
		local.append(Rect2(r.position - offset, r.size))
	for cell in dim_cells(Rect2(Vector2.ZERO, size), local):
		draw_rect(cell, DIM)
	# Yellow, black, yellow: reads on any background and never as a card's rarity frame. It breathes gently.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 260.0)
	for r in local:
		draw_rect(r, HIVIZ, false, 3.0)
		draw_rect(r.grow(3.0), INK, false, 3.0)
		draw_rect(r.grow(6.0 + 2.0 * pulse), HIVIZ, false, 2.5)


## Puts the note below the first framed part, or above it, or beside it, kept on screen.
func _place_note(note_size: Vector2) -> void:
	var screen := size
	var p: Vector2
	if _rects.is_empty():
		p = map_anchor.call(note_size) if map_anchor.is_valid() else (screen - note_size) * 0.5
	else:
		var r := Rect2(_rects[0].position - get_global_rect().position, _rects[0].size)
		if r.end.y + GAP + note_size.y <= screen.y - 8.0:
			p = Vector2(r.position.x, r.end.y + GAP)
		elif r.position.y - GAP - note_size.y >= 8.0:
			p = Vector2(r.position.x, r.position.y - GAP - note_size.y)
		elif r.position.x - GAP - note_size.x >= 8.0:
			p = Vector2(r.position.x - GAP - note_size.x, r.position.y)
		else:
			p = Vector2(r.end.x + GAP, r.position.y)
	var most := screen - note_size - Vector2(8, 8)
	_note.position = Vector2(clampf(p.x, 8.0, maxf(8.0, most.x)), clampf(p.y, 8.0, maxf(8.0, most.y)))


func _mark_seen(id: String) -> void:
	if id != "" and not settings.tips_seen.has(id):
		settings.tips_seen.append(id)
		settings.save()


func _close() -> void:
	_shown = ""
	_rects.clear()
	hide()
