class_name ThreatCard
extends VBoxContainer
## The round's attack as a small card in the map's top-right corner: where it comes from, your town's
## power against the attack's as one bar with a plain verdict, and a gold banner when the warband holds
## raiders back (catch-up). The enemy list is in the hover card. While building, the Begin round
## button sits under it.

signal begin_pressed

const WIDTH := 280.0
## Attack power over town power above this reads as outmatched (bots lose about 1 round in 5 there).
const OUTMATCHED := 1.3
const EVEN := 0.9

var run: RunState
var _title: RichTextLabel
var _bar: ColorRect
var _numbers: Label
var _verdict: Label
var _eased: Label
var _begin: Button


func _init() -> void:
	custom_minimum_size.x = WIDTH
	add_theme_constant_override("separation", 4)
	var chip := TipChip.new()
	chip.tip = func() -> Dictionary: return tip(run) if run != null else {}
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
	_begin = UiKit.primary(UiKit.button(self, "", func() -> void: begin_pressed.emit()), 18)
	_begin.custom_minimum_size.y = 48


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
	_eased.visible = run.wave_eased > 0
	_eased.text = "The warband holds back %d raider%s: your town looks too weak to be worth them all.%s" % [
		run.wave_eased, "" if run.wave_eased == 1 else "s",
		" %d make a war camp in the wilds." % run.camp_joined if run.camp_joined > 0 else ""]
	_begin.visible = building
	_begin.text = "Begin round %d" % run.round_number


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
	if r.wave_eased > 0:
		t["lines"].append("Catch-up: the warband holds back raiders when your town has fallen far behind. A strong town never faces more for being strong.")
		t["lines"].append("Held-back raiders make a war camp out in the wilds: it blocks gathering nearby until heroes clear it, and clearing it pays.")
	return t
