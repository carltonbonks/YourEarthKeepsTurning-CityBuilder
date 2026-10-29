class_name ThreatCard
extends VBoxContainer
## The round's attack as a small card in the map's top-right corner: where it comes from, your town's
## power against the attack's as one bar with a plain verdict, and a gold banner when the warband holds
## raiders back (catch-up). The enemy list is in the hover card. Each way in names the near plate it
## crosses this round (EarthReport.ways), the earth's one line.
## When the room left above the building hand is short, `fit` folds the extras
## (the ways, the warband banner) into the hover card, so the card never runs into the hand.

const WIDTH := 280.0
## Attack power over town power above this reads as outmatched (bots lose about 1 round in 5 there).
const OUTMATCHED := 1.3
const EVEN := 0.9

var run: RunState
var _title: RichTextLabel
var _ways: Label
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
	_title.add_theme_font_size_override("normal_font_size", UiKit.BODY)
	_title.add_theme_font_size_override("bold_font_size", UiKit.BODY)
	box.add_child(_title)
	_ways = UiKit.note(box, "", UiKit.CAPTION)
	_ways.autowrap_mode = TextServer.AUTOWRAP_WORD
	# The verdict is what decides how to spend the round, so it comes first and biggest.
	_verdict = UiKit.note(box, "", UiKit.TITLE)
	_bar = UiKit.bar(box, 0.5, Color("#7fb0e0"), 8.0)
	(_bar as ColorRect).color = Color("#c05040")
	_numbers = UiKit.note(box, "", UiKit.CAPTION)
	_eased = Label.new()
	_eased.autowrap_mode = TextServer.AUTOWRAP_WORD
	_eased.add_theme_font_size_override("font_size", UiKit.CAPTION)
	_eased.add_theme_color_override("font_color", Color("#1a1408"))
	var gold := StyleBoxFlat.new()
	gold.bg_color = UiKit.RECOMMEND_COLOR
	gold.set_corner_radius_all(3)
	gold.set_content_margin_all(4)
	_eased.add_theme_stylebox_override("normal", gold)
	box.add_child(_eased)
	# Shown when fit folded something away.
	_more = UiKit.note(self, "More on hover", UiKit.CAPTION)
	_more.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# The ways (which den, across which near plate) fold last.
	_foldable = [_eased, _ways]


func refresh() -> void:
	var content := run.content
	var w := run.world
	var building := run.phase == RunState.Phase.BUILD
	var town := roundi(float(Power.town(w)["total"]))
	var attack := roundi(Power.wave(content, run.waves.attack()))
	if building or not w.wave_spawned:
		_title.text = "[b]Night %d attack[/b] from the %s" % [content.int_num("days_per_round"), UiKit.tint(" and ".join(w.side_names()), UiKit.DANGER)]
	else:
		var left := w.enemies.filter(func(e: Unit) -> bool: return e.alive and e.den_index < 0).size()
		_title.text = "[b]The attack is here[/b]  " + UiKit.tint("Raiders left %d" % left, UiKit.DANGER)
	UiKit.set_bar(_bar, float(town) / maxf(1.0, town + attack))
	_numbers.text = "Your town %d   vs   the attack %d" % [town, attack]
	var ratio := float(attack) / maxf(1.0, town)
	_verdict.text = "They outmatch you" if ratio > OUTMATCHED else ("An even fight" if ratio > EVEN else "You should hold")
	_verdict.add_theme_color_override("font_color", UiKit.DANGER if ratio > OUTMATCHED else (UiKit.INK if ratio > EVEN else UiKit.GOOD))
	_eased.text = "\n".join(loan_lines(run))
	_wanted[_eased] = _eased.text != "" and (building or not w.wave_spawned)
	_ways.text = "\n".join(EarthReport.ways(run))
	_wanted[_ways] = building or not w.wave_spawned
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
	return t


## The hover card: who is coming, and what the power numbers mean.
static func tip(r: RunState) -> Dictionary:
	var content := r.content
	var t := Tooltips.new_tip("Night %d attack" % content.int_num("days_per_round"))
	var counts := r.waves.counts()
	var ids := counts.keys()
	ids.sort()
	for id: String in ids:
		t["lines"].append("%s ×%d" % [content.enemies[id]["name"], counts[id]])
	t["lines"].append("Power counts heroes, warriors, the hearth and towers against every raider coming.")
	t["lines"].append("Earlier nights bring only wanderers and small probes.")
	t["lines"].append("The warband comes by a den's way and crosses one near plate on its way in. Between rounds that ring clicks round a plate, so the ground it crosses changes: hover a plate on the map to see what it does.")
	if r.wave_eased > 0 or not r.waves.camp_due().is_empty():
		t["lines"].append("Catch-up is a loan: when your town has fallen far behind, the warband holds raiders back for a round. They make a war camp in the wilds that blocks gathering nearby, then march with the next attack unless heroes break the camp first. A strong town never faces more for being strong.")
	if not r.outmatched:
		t["lines"].append("Glory: hold this attack at full strength and you get one more relic to choose from.")
	return t


## The warband's loan in a line or two: raiders held back this round, and the war camp's raiders due tonight.
static func loan_lines(r: RunState) -> Array[String]:
	var out: Array[String] = []
	var due := r.waves.camp_due().size()
	if due > 0:
		out.append("The war camp's %d raider%s march with this attack unless your heroes break the camp first." % [due, "" if due == 1 else "s"])
	if r.wave_eased > 0:
		out.append("The warband holds back %d raider%s: your town looks too weak to be worth them all.%s" % [
			r.wave_eased, "" if r.wave_eased == 1 else "s",
			" %d make a war camp and march with next round's attack." % r.camp_joined if r.camp_joined > 0 else ""])
	return out

