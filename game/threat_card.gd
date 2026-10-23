class_name ThreatCard
extends VBoxContainer
## The round's attack as a small card in the map's top-right corner: where it comes from, your town's
## power against the attack's as one bar with a plain verdict, and a gold banner when the warband holds
## raiders back (catch-up). The enemy list is in the hover card. While building, what the earth's
## last turn did (EarthReport) sits under it.
## When the room left between the draft window and the building hand is short, `fit` folds the extras
## (the earth's details, the ways, the warband banner) into the hover cards, so the card never runs
## into the hand.

const WIDTH := 280.0
## Attack power over town power above this reads as outmatched (bots lose about 1 round in 5 there).
const OUTMATCHED := 1.3
const EVEN := 0.9

var run: RunState
var _title: RichTextLabel
var _ways: Label
var _earth_box: VBoxContainer
var _earth_title: Label
var _earth_lines: Label
var _spell: Label
var _bar: ColorRect
var _numbers: Label
var _verdict: Label
var _eased: Label
var _more: Label
## The extras `fit` may fold away, least needed first, and whether refresh wants each one shown.
var _foldable: Array[Control] = []
var _wanted := {}
var _max_height := INF


func _init() -> void:
	custom_minimum_size.x = WIDTH
	add_theme_constant_override("separation", 4)
	var chip := TipChip.new()
	chip.tip = func() -> Dictionary: return _tip_with_folded() if run != null else {}
	add_child(chip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	chip.add_child(box)
	_title = RichTextLabel.new()
	_title.bbcode_enabled = true
	_title.fit_content = true
	_title.scroll_active = false
	_title.add_theme_font_size_override("normal_font_size", 13)
	_title.add_theme_font_size_override("bold_font_size", 13)
	box.add_child(_title)
	_ways = UiKit.note(box, "", 11)
	_ways.autowrap_mode = TextServer.AUTOWRAP_WORD
	# The verdict is what decides how to spend the round, so it comes first and biggest.
	_verdict = UiKit.note(box, "", 17)
	_bar = UiKit.bar(box, 0.5, Color("#7fb0e0"), 8.0)
	(_bar as ColorRect).color = Color("#c05040")
	_numbers = UiKit.note(box, "", 11)
	_eased = Label.new()
	_eased.autowrap_mode = TextServer.AUTOWRAP_WORD
	_eased.add_theme_font_size_override("font_size", 12)
	_eased.add_theme_color_override("font_color", Color("#1a1408"))
	var gold := StyleBoxFlat.new()
	gold.bg_color = UiKit.RECOMMEND_COLOR
	gold.set_corner_radius_all(3)
	gold.set_content_margin_all(4)
	_eased.add_theme_stylebox_override("normal", gold)
	box.add_child(_eased)
	# What the earth's last turn did: a hover of its own, so the attack's hover stays about the attack.
	var earth_chip := TipChip.new()
	earth_chip.tip = func() -> Dictionary: return _earth_tip_with_folded() if run != null else {}
	add_child(earth_chip)
	_earth_box = VBoxContainer.new()
	_earth_box.add_theme_constant_override("separation", 2)
	earth_chip.add_child(_earth_box)
	_earth_title = UiKit.note(_earth_box, "", 13, Color("#d8c08a"))
	_earth_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	_earth_lines = UiKit.note(_earth_box, "", 11)
	_earth_lines.autowrap_mode = TextServer.AUTOWRAP_WORD
	# What the geomancer is working on (spells are chosen on dawn cards).
	_spell = UiKit.note(self, "", 12, Color("#c8a8e0"))
	_spell.autowrap_mode = TextServer.AUTOWRAP_WORD
	# Shown when fit folded something away.
	_more = UiKit.note(self, "More on hover", 10)
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_foldable = [_earth_lines, _ways, _eased, _earth_box.get_parent(), _spell]


func refresh() -> void:
	var content := run.content
	var w := run.world
	var building := run.phase == RunState.Phase.BUILD
	var town := roundi(float(Power.town(w)["total"]))
	var attack := roundi(Power.wave(content, run.next_wave))
	if building or not w.wave_spawned:
		_title.text = "[b]Night %d attack[/b] from the [color=#ff7060]%s[/color]" % [content.int_num("days_per_round"), " and ".join(w.side_names())]
	else:
		var left := w.enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index < 0).size()
		_title.text = "[b]The attack is here[/b]  [color=#ff7060]%d left[/color]" % left
	UiKit.set_bar(_bar, float(town) / maxf(1.0, town + attack))
	_numbers.text = "Your town %d   vs   the attack %d" % [town, attack]
	var ratio := float(attack) / maxf(1.0, town)
	_verdict.text = "They outmatch you" if ratio > OUTMATCHED else ("An even fight" if ratio > EVEN else "You should hold")
	_verdict.add_theme_color_override("font_color", Color("#ff7060") if ratio > OUTMATCHED else (Color("#e0c070") if ratio > EVEN else Color("#a8d890")))
	_wanted[_eased] = run.wave_eased > 0
	_eased.text = "The warband holds back %d raider%s: your town looks too weak to be worth them all.%s" % [
		run.wave_eased, "" if run.wave_eased == 1 else "s",
		" %d make a war camp in the wilds." % run.camp_joined if run.camp_joined > 0 else ""]
	_ways.text = "\n".join(EarthReport.ways(run))
	_wanted[_ways] = building or not w.wave_spawned
	var headline := EarthReport.headline(run)
	_wanted[_earth_box.get_parent()] = building and headline != ""
	_wanted[_spell] = not run.spell.is_empty()
	if _wanted[_spell]:
		var nights := int(run.spell["nights_left"])
		_spell.text = "The geomancer works on %s: done in %d night%s." % [
			String(content.plates["spells"][run.spell["id"]]["name"]).to_lower(), nights, "" if nights == 1 else "s"]
	_earth_title.text = headline
	_earth_lines.text = "\n".join(EarthReport.lines(run))
	_wanted[_earth_lines] = _earth_lines.text != ""
	fit(_max_height)


## Shows what refresh wants, then folds the extras one by one until the card is no taller than
## max_height (kept for later refreshes). What is folded moves into the hover cards; returns how many
## parts were folded.
func fit(max_height: float) -> int:
	_max_height = max_height
	for part in _foldable:
		part.visible = _wanted.get(part, false)
	# A wrapping label that was hidden at the last layout measures as one word a line; give it the
	# width it will have first (less the hover chip's margins inside one).
	for label: Label in find_children("*", "Label", true, false):
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
			label.size.x = WIDTH if label.get_parent() == self else WIDTH - 12.0
	_more.visible = false
	var folded := 0
	for part in _foldable:
		if get_combined_minimum_size().y <= max_height:
			break
		if part.visible:
			part.visible = false
			_more.visible = true
			folded += 1
	return folded


func _is_folded(part: Control) -> bool:
	return _wanted.get(part, false) and not part.visible


## The attack's hover card, plus whatever fit folded off the card.
func _tip_with_folded() -> Dictionary:
	var t := tip(run)
	if _is_folded(_ways):
		t["lines"].append_array(EarthReport.ways(run))
	if _is_folded(_eased):
		t["lines"].append(_eased.text)
	if _is_folded(_spell):
		t["lines"].append(_spell.text)
	if _is_folded(_earth_box.get_parent()):
		t["lines"].append(_earth_title.text)
		t["lines"].append_array(EarthReport.lines(run))
	return t


func _earth_tip_with_folded() -> Dictionary:
	var t := earth_tip(run)
	if _is_folded(_earth_lines):
		t["lines"].append_array(EarthReport.lines(run))
	return t


## The hover card: who is coming, and what the power numbers mean.
static func tip(r: RunState) -> Dictionary:
	var content := r.content
	var t := Tooltips.new_tip("Night %d attack" % content.int_num("days_per_round"))
	var counts := r.waves.counts()
	var ids := counts.keys()
	ids.sort()
	for id: String in ids:
		t["lines"].append("%s x%d" % [content.enemies[id]["name"], counts[id]])
	t["lines"].append("Power counts heroes, warriors, the hearth and towers against every raider coming.")
	t["lines"].append("Earlier nights bring only wanderers and small probes.")
	t["lines"].append("The warband comes by a den's way. The earth carries the dens round between rounds, and the attack with them; a den the earth swallows takes its way with it.")
	if r.wave_eased > 0:
		t["lines"].append("Catch-up: the warband holds back raiders when your town has fallen far behind. A strong town never faces more for being strong.")
		t["lines"].append("Held-back raiders make a war camp out in the wilds: it blocks gathering nearby until heroes clear it, and clearing it pays.")
	return t


## The earth report's hover card: how the earth works, in short.
static func earth_tip(r: RunState) -> Dictionary:
	var t := Tooltips.new_tip("The shifting earth")
	t["lines"].append("Between rounds the rings of land past the town turn; the town itself never moves.")
	t["lines"].append("Each turn one seam wakes: it swallows the land on one side, raises a rich vein of stone, or splits open a valley of fresh plants.")
	t["lines"].append("The places it changed pulse on the map for a few moments.")
	t["lines"].append("A Geomancer's lodge offers spells on dawn cards: quicken a far seam, raise a ridge against the attack, or sink a den. Bold and greedy heroes dig out what the earth leaves: a sunk den's hoard, starstone by a ridge.")
	return t
