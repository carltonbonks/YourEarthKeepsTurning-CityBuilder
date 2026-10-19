class_name Alerts
extends VBoxContainer
## Short alerts over the map's top-left corner when something needs the player's attention: nobody to
## raise buildings, fuel or food running out, an unhappy hero, a battered hearth, the warband holding
## back. Each one shows when its problem starts, fades after a few seconds (or on a click), and comes
## back only if the problem clears and returns. `active` is the read-only rule, so tests can check it.

const SHOW_SECONDS := 8.0
const FADE_SECONDS := 1.0

var run: RunState
## Alert id -> seconds it has been on screen (problems still true, so they don't come back).
var _seen := {}
var _labels := {}


func _init() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The problems worth an alert right now: [{id, text}], most urgent first.
static func active(r: RunState) -> Array[Dictionary]:
	var content := r.content
	var w := r.world
	var out: Array[Dictionary] = []
	if r.is_over():
		return out
	if w.hearth_hp < r.hearth_max_hp() * 0.35:
		out.append({"id": "hearth", "text": "The hearth is badly damaged. If it falls, the run is lost."})
	var nights := StatusText.fuel_nights(r)
	if nights >= 0.0 and nights < 1.0:
		out.append({"id": "fuel", "text": "Fuel runs out tonight: gather brush or the night will be cold."})
	var days := StatusText.food_days(r)
	if days >= 0.0 and days < 1.0:
		out.append({"id": "food", "text": "Food is short for the next dawn: someone will leave hungry."})
	var pending := w.buildings.any(func(b: Dictionary) -> bool: return float(b["work_left"]) > 0.0)
	if pending and r.count_role("craftsperson") == 0:
		out.append({"id": "builders", "text": "Nobody can raise buildings: pick a craftsperson at dawn."})
	for hero in r.living_heroes():
		if hero.mood <= content.num("mood_grumble_at"):
			out.append({"id": "mood:" + hero.display_name, "text": "%s is unhappy and may leave town." % hero.display_name})
	if r.phase == RunState.Phase.BUILD and r.wave_eased > 0:
		out.append({"id": "eased:%d" % r.round_number, "text": "The warband holds back %d raider%s this round." % [
			r.wave_eased, "" if r.wave_eased == 1 else "s"]})
	if r.phase == RunState.Phase.BUILD and w.camp_index() >= 0:
		out.append({"id": "camp:%d" % r.round_number, "text": "A war camp of %d raiders holds land in the wilds: heroes can clear it for plunder." % [
			w.enemy_ai.camp_raiders().size()]})
	if r.phase == RunState.Phase.BUILD and w.pathing.count_ground(Pathing.PATH) > 0 and not w.town.can_pave():
		out.append({"id": "paving", "text": "Worn paths could be paved: build a %s." % w.town.paver_name()})
	return out


func refresh() -> void:
	var now := {}
	for a: Dictionary in active(run):
		now[a["id"]] = a["text"]
		if not _seen.has(a["id"]):
			_seen[a["id"]] = 0.0
			_add(a["id"], a["text"])
	for id: String in _seen.keys():
		if not now.has(id):
			_seen.erase(id)
			_drop(id)


## Clears every alert (a new run).
func reset() -> void:
	for id: String in _labels.keys():
		_drop(id)
	_seen.clear()


func _process(delta: float) -> void:
	for id: String in _labels.keys():
		_seen[id] = float(_seen.get(id, 0.0)) + delta
		var age: float = _seen[id]
		var label: Label = _labels[id]
		if age >= SHOW_SECONDS:
			_drop(id)
		elif age > SHOW_SECONDS - FADE_SECONDS:
			label.modulate.a = (SHOW_SECONDS - age) / FADE_SECONDS


func _add(id: String, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 320
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color("#ffe0b0"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.16, 0.08, 0.9)
	style.border_color = Color("#e0a050")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	l.add_theme_stylebox_override("normal", style)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	l.tooltip_text = "Click to dismiss"
	l.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_drop(id))
	add_child(l)
	_labels[id] = l


## Takes an alert off screen; its problem stays in _seen so it doesn't pop up again until it clears.
func _drop(id: String) -> void:
	if _labels.has(id):
		(_labels[id] as Label).queue_free()
		_labels.erase(id)
