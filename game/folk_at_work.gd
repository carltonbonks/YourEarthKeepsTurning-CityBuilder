class_name FolkAtWork
extends RefCounted
## Townsfolk at work (Yusuf, 2026-10-26): how each kind of townsperson spent the round and what came of it.
## The dawn card's word (Stretched, Busy, Slack; People.busy_word) is free; the Your people panel (`build`), the
## full breakdown on the dawn card's hover and each townsperson's day on the map hover need a Reeve's hut
## (People.reckoning). The time comes from FolkAI._note_time (kinds in data/townsfolk.json time_kinds). Read-only.

const KINDS := ["work", "fallback", "idle", "down"]
const KIND_COLORS := {"work": Color("#6fa8dc"), "fallback": Color("#c9a24a"), "idle": Color("#6b7079"),
	"down": Color("#c86a5e")}
## What each kind means for each role, for legends and hovers.
const KIND_NAMES := {
	"tribesperson": {"work": "gathering", "fallback": "helping out", "idle": "idle", "down": "fleeing"},
	"craftsperson": {"work": "building and crafting", "fallback": "paving, helping, gathering", "idle": "idle", "down": "fleeing"},
	"warrior": {"work": "fighting", "fallback": "patrol and watch", "idle": "idle", "down": "healing"},
}
const WORD_NAMES := {"stretched": "Stretched", "busy": "Busy", "slack": "Slack"}
const ROLES := ["tribesperson", "craftsperson", "warrior"]


static func word_name(word: String) -> String:
	return WORD_NAMES.get(word, "")


static func word_tint(word: String) -> Color:
	match word:
		"stretched":
			return CardView.GOOD
		"slack":
			return CardView.DIM
	return CardView.TEXT


## What the word means for the dawn pick.
static func word_advice(role: String, word: String) -> String:
	match word:
		"stretched":
			return "there is more for them to do than hands to do it, so another will earn their keep" if role != "warrior" \
				else "they spent much of the round fighting or healing, so another would share the load"
		"slack":
			return "another mostly adds upkeep unless you give them something to do" if role != "warrior" \
				else "they mostly walked the patrol, so another adds little for now"
	return "about right"


## "38% idle" or "14% fighting or healing": the share the word reads.
static func share_text(run: RunState, role: String) -> String:
	var kinds: Array = run.content.townsfolk[role].get("busy_words", {}).get("kinds", [])
	var names := kinds.map(func(k: String) -> String: return KIND_NAMES[role][k])
	return "%d%% %s" % [roundi(100.0 * run.people.busy_share(role)), " or ".join(names)]


## The dawn card's hover lines for a role: the word and why (free), then the full split and output with a Reeve's hut.
static func card_lines(run: RunState, role: String) -> Array[String]:
	var out: Array[String] = []
	var word := run.people.busy_word(role)
	if word == "":
		return out
	var b := run.people.busy_of(role)
	var when := "this round" if b["from"] == "this" else "last round"
	out.append("%s: your %s spent %s %s, so %s." % [word_name(word), plural(run, role), share_text(run, role), when,
		word_advice(role, word)])
	if run.people.reckoning().is_empty():
		out.append("A Reeve's hut shows how they spent the rest.")
		return out
	out.append("Their round: %s." % split_text(role, b["kinds"]))
	var each := output_text(run, role, impact_for(run, b["from"]))
	if each != "":
		out.append(each[0].to_upper() + each.substr(1) + ".")
	return out


## "gathering 70%, helping out 20%, idle 10%".
static func split_text(role: String, kinds: Dictionary) -> String:
	var total := 0.0
	for k: String in kinds:
		total += float(kinds[k])
	if total <= 0.0:
		return "nothing yet"
	var parts := PackedStringArray()
	for k: String in KINDS:
		if float(kinds.get(k, 0.0)) / total >= 0.005:
			parts.append("%s %d%%" % [KIND_NAMES[role][k], roundi(100.0 * float(kinds[k]) / total)])
	return ", ".join(parts)


static func plural(run: RunState, role: String) -> String:
	return run.content.townsfolk[role]["name"].to_lower().replace("person", "people").replace("warrior", "warriors")


## The round's impact the time came from ("this" or "last").
static func impact_for(run: RunState, from: String) -> Dictionary:
	if from == "this":
		return run.record.entry.get("impact", {})
	if not run.record.rounds.is_empty():
		return run.record.rounds[-1].get("impact", {})
	return {}


## What a role did: goods brought home per head, then buildings raised, goods made and kills in all
## ("brought home 9 goods each, raised 2 buildings").
static func output_text(run: RunState, role: String, impact: Dictionary) -> String:
	var row: Dictionary = impact.get("folk", {}).get(role, {})
	var n := maxf(1.0, float(run.count_role(role)))
	var parts := PackedStringArray()
	var goods := 0.0
	for good: String in row.get("goods", {}):
		goods += float(row["goods"][good])
	if goods > 0.0:
		parts.append("brought home %s goods each" % _each(goods / n))
	for stat: Array in [["raised", "building", "raised %d %s"], ["made", "good", "made %d %s"], ["kills", "kill", "%d %s"]]:
		var count := roundi(float(row.get(stat[0], 0)))
		if count > 0:
			parts.append(stat[2] % [count, stat[1] if count == 1 else stat[1] + "s"])
	return ", ".join(parts)


static func _each(x: float) -> String:
	return str(roundi(x)) if x >= 2.0 or is_equal_approx(x, roundf(x)) else "%.1f" % x


## Which of a townsperson's tallies holds the round busy_of reads: this round's, or last round's (still in
## Unit.time while building, since FolkAI.start_round moves it over only as the next round begins).
static func _holds_this(run: RunState, from: String) -> bool:
	return from == "this" or run.phase == RunState.Phase.BUILD


## One townsperson's day on the map hover (needs a Reeve's hut), or "".
static func unit_line(run: RunState, u: Unit) -> String:
	if run.people.reckoning().is_empty() or not KIND_NAMES.has(u.type_id):
		return ""
	var this_round := not u.time.is_empty() and run.phase != RunState.Phase.BUILD
	var kinds: Dictionary = u.time if this_round or run.phase == RunState.Phase.BUILD else u.time_last
	if kinds.is_empty():
		return ""
	var line := "%s: %s" % ["This round" if this_round else "Last round", split_text(u.type_id, kinds)]
	var brought := u.brought if this_round or run.phase == RunState.Phase.BUILD else u.brought_last
	if brought > 0:
		line += ", brought home %d" % brought
	return line + "."


## A bar of the kinds' shares, in their colours.
static func make_bar(kinds: Dictionary, width := 260.0, height := 10.0) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.custom_minimum_size = Vector2(width, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var total := 0.0
	for k: String in kinds:
		total += float(kinds[k])
	if total <= 0.0:
		var empty := ColorRect.new()
		empty.color = Color(1, 1, 1, 0.08)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(empty)
		return bar
	for k: String in KINDS:
		var secs := float(kinds.get(k, 0.0))
		if secs <= 0.0:
			continue
		var part := ColorRect.new()
		part.color = KIND_COLORS[k]
		part.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		part.size_flags_stretch_ratio = secs / total
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(part)
	return bar


## The townsfolk of a role in groups for the panel: one per leaning (or "" for none), then each named or marked
## person on their own. Each group: {"label", "count", "kinds", "brought"}.
static func groups(run: RunState, role: String, this_round: bool) -> Array[Dictionary]:
	var by_leaning := {}
	var singles: Array[Dictionary] = []
	for u in run.world.folk:
		if not u.alive or u.type_id != role:
			continue
		var kinds: Dictionary = u.time if this_round else u.time_last
		var brought := u.brought if this_round else u.brought_last
		if u.master_of != "" or u.mark != "":
			var label: String = u.display_name if u.master_of != "" else run.content.marks[u.mark]["name"]
			singles.append({"label": label, "count": 1, "kinds": kinds.duplicate(), "brought": brought})
			continue
		var g: Dictionary = by_leaning.get_or_add(u.leaning, {"count": 0, "kinds": {}, "brought": 0})
		g["count"] = int(g["count"]) + 1
		g["brought"] = int(g["brought"]) + brought
		for k: String in kinds:
			g["kinds"][k] = float(g["kinds"].get(k, 0.0)) + float(kinds[k])
	var out: Array[Dictionary] = []
	var keys := by_leaning.keys()
	keys.sort()
	for leaning: String in keys:
		var g: Dictionary = by_leaning[leaning]
		var label: String = "No leaning" if leaning == "" else run.content.townsfolk[role]["leanings"][leaning]["name"]
		out.append({"label": label, "count": g["count"], "kinds": g["kinds"], "brought": g["brought"]})
	out.append_array(singles)
	return out


## The Your people panel: a row per role (word, bar, output per head), opening to its leanings and named people.
static func build(parent: Control, run: RunState) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 760
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	box.add_child(legend)
	for k: String in KINDS:
		var swatch := ColorRect.new()
		swatch.color = KIND_COLORS[k]
		swatch.custom_minimum_size = Vector2(10, 10)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		legend.add_child(swatch)
		var l := Label.new()
		l.text = {"work": "Own work", "fallback": "Fallback", "idle": "Idle", "down": "Down"}[k]
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", UiKit.HINT_COLOR)
		legend.add_child(l)
	var any := false
	for role: String in ROLES:
		if run.count_role(role) <= 0:
			continue
		var b := run.people.busy_of(role)
		if b["from"] == "":
			continue
		any = true
		var this_round := _holds_this(run, b["from"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var word := run.people.busy_word(role)
		var who := Label.new()
		who.text = "%s (%d)" % [run.content.townsfolk[role]["name"], run.count_role(role)]
		who.custom_minimum_size.x = 150
		who.add_theme_font_size_override("font_size", 14)
		row.add_child(who)
		var tag := Label.new()
		tag.text = word_name(word)
		tag.custom_minimum_size.x = 80
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_color", word_tint(word))
		var advice := word_advice(role, word)
		tag.tooltip_text = advice[0].to_upper() + advice.substr(1) + "."
		tag.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(tag)
		var bar := make_bar(b["kinds"], 280.0, 12.0)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.tooltip_text = split_text(role, b["kinds"])
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(bar)
		var out := Label.new()
		out.text = output_text(run, role, impact_for(run, b["from"]))
		out.add_theme_font_size_override("font_size", 12)
		out.add_theme_color_override("font_color", UiKit.HINT_COLOR)
		row.add_child(out)
		for g: Dictionary in groups(run, role, this_round):
			if g["kinds"].is_empty():
				continue
			var sub := HBoxContainer.new()
			sub.add_theme_constant_override("separation", 12)
			box.add_child(sub)
			var gap := Control.new()
			gap.custom_minimum_size.x = 24
			sub.add_child(gap)
			var label := Label.new()
			label.text = g["label"] if int(g["count"]) == 1 else "%s (%d)" % [g["label"], g["count"]]
			label.custom_minimum_size.x = 206
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", UiKit.HINT_COLOR)
			sub.add_child(label)
			var gbar := make_bar(g["kinds"], 280.0, 7.0)
			gbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			gbar.tooltip_text = split_text(role, g["kinds"])
			gbar.mouse_filter = Control.MOUSE_FILTER_PASS
			sub.add_child(gbar)
			if int(g["brought"]) > 0:
				var got := Label.new()
				got.text = "brought home %s each" % _each(float(g["brought"]) / float(g["count"]))
				got.add_theme_font_size_override("font_size", 11)
				got.add_theme_color_override("font_color", UiKit.HINT_COLOR)
				sub.add_child(got)
	if not any:
		UiKit.note(box, "Nothing to show yet: this fills in as the round plays.", 13)
