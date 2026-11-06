class_name FolkAtWork
extends RefCounted
## Townsfolk at work (Yusuf, 2026-10-26): how each kind of townsperson spent the round and what came of it.
## The dawn card's word (Stretched, Busy, Slack; People.busy_word) is free; the Your people panel (`build`), the
## full breakdown on the dawn card's hover and each townsperson's day on the map hover need a Reeve's hut
## (People.reckoning). The time comes from FolkAI._note_time (kinds in data/townsfolk.json time_kinds). Why a role is
## busy (Yusuf, 2026-11-06): the time is also split by task (FolkAI.task_key, named by task_words), and the card says
## the biggest one and why (`why_line`, free); the full split by task needs the hut. Read-only.

const KINDS := ["work", "fallback", "idle", "down"]
const KIND_COLORS := {"work": Color("#6fa8dc"), "fallback": Color("#c9a24a"), "idle": Color("#6b7079"),
	"down": Color("#c86a5e")}
## What each kind means for each role, for legends and hovers.
const KIND_NAMES := {
	"tribesperson": {"work": "gathering", "fallback": "helping out", "idle": "idle", "down": "fleeing"},
	"craftsperson": {"work": "building and crafting", "fallback": "paving, helping, gathering", "idle": "idle", "down": "fleeing"},
	"warrior": {"work": "fighting", "fallback": "patrol and watch", "idle": "idle", "down": "healing"},
}
## Each task's colour on the task bar (gathering takes its goods' colour, GOOD_COLORS).
const TASK_COLORS := {"build": Color("#5b8fd0"), "craft": Color("#9ec3ee"), "pave": Color("#a89a7a"),
	"assist": Color("#b07fd0"), "repair": Color("#d08a5a"), "run": Color("#7fc0b0"), "barricade": Color("#8a6a4a"),
	"home": Color("#8a8478"), "idle": Color("#4a4e57"), "flee": Color("#c86a5e"), "fight": Color("#c86a5e"),
	"heal": Color("#e09a8e"), "patrol": Color("#7d8fa8"), "shadow": Color("#a6b6cc"), "drill": Color("#d0b07f"),
	"seer": Color("#6a5a8a")}
const GOOD_COLORS := {"food": Color("#c0607f"), "fuel": Color("#e0b85a"), "wood": Color("#5fa064"),
	"stone": Color("#9a9a9a"), "flint": Color("#7a8a9a"), "copper": Color("#b87333"), "bog_iron": Color("#8a6a4a"),
	"obsidian": Color("#6a5a8a"), "cassiterite": Color("#6a6060")}
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
			return "another would mostly fill in or stand idle until there is more of their own work" if role != "warrior" \
				else "they mostly walked the patrol, so another adds little for now"
	return "about right"


## "38% idle or off their own work" or "14% fighting or healing": the share the word reads.
static func share_text(run: RunState, role: String) -> String:
	var label: String = run.content.townsfolk[role].get("busy_words", {}).get("label", "")
	return "%d%% %s" % [roundi(100.0 * run.people.busy_share(role)), label]


## A task's name for the hovers ("fetching wood", "raising buildings"; task_words in data/townsfolk.json).
static func task_name(run: RunState, role: String, task: String) -> String:
	var words: Dictionary = run.content.townsfolk[role].get("task_words", {})
	if task.begins_with("fetch:"):
		var good := task.trim_prefix("fetch:").replace("_", " ")
		return str(words.get("fetch", {}).get("name", "fetching %s")) % good
	return str(words.get(task, {}).get("name", task.replace("_", " ")))


## A by-task tally (FolkAI.task_key) as what the time went on, the walking folded into what it was for ("walk:build"
## is part of raising buildings; an empty-handed walk home is "home"): [{key, doing, walk, total}], biggest first,
## standing about (idle) last so the bar ends on it.
static func purposes(tasks: Dictionary) -> Array[Dictionary]:
	var by := {}
	for t: String in tasks:
		var secs := float(tasks[t])
		if secs <= 0.0:
			continue
		var walking := t.begins_with("walk:")
		var key := t.trim_prefix("walk:")
		if key == "return":
			key = "home"
			walking = true
		var p: Dictionary = by.get_or_add(key, {"key": key, "doing": 0.0, "walk": 0.0, "total": 0.0})
		p["walk" if walking else "doing"] = float(p["walk" if walking else "doing"]) + secs
		p["total"] = float(p["total"]) + secs
	var out: Array[Dictionary] = []
	for key: String in by:
		out.append(by[key])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if (a["key"] == "idle") != (b["key"] == "idle"):
			return b["key"] == "idle"
		return a["total"] > b["total"] or (a["total"] == b["total"] and a["key"] < b["key"]))
	return out


static func _total(list: Array[Dictionary]) -> float:
	var total := 0.0
	for p: Dictionary in list:
		total += float(p["total"])
	return total


## "gathering wood 39% (30% walking), idle 31%, raising buildings 20% (12% walking)": the biggest, the rest as "other".
static func task_split_text(run: RunState, role: String, tasks: Dictionary, most := 4) -> String:
	var list := purposes(tasks)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total"] > b["total"])
	var total := _total(list)
	if total <= 0.0:
		return "nothing yet"
	var parts := PackedStringArray()
	var rest := 0.0
	for i in list.size():
		var pct := 100.0 * float(list[i]["total"]) / total
		if i < most and pct >= 0.5:
			var walk := roundi(100.0 * float(list[i]["walk"]) / total)
			parts.append("%s %d%%%s" % [task_name(run, role, list[i]["key"]), roundi(pct),
				" (%d%% walking)" % walk if walk >= 1 and float(list[i]["doing"]) > 0.0 else ""])
		else:
			rest += pct
	if rest >= 0.5:
		parts.append("other %d%%" % roundi(rest))
	return ", ".join(parts)


## The biggest thing a role's time went on and its share, {} with nothing counted.
static func top_purpose(tasks: Dictionary) -> Dictionary:
	var list := purposes(tasks)
	var total := _total(list)
	if total <= 0.0:
		return {}
	var best: Dictionary = list[0]
	for p: Dictionary in list:
		if float(p["total"]) > float(best["total"]):
			best = p
	return {"key": best["key"], "share": float(best["total"]) / total}


## The card's caption under the bar: "Mostly gathering wood (39%)", or "".
static func mostly_text(run: RunState, role: String, tasks: Dictionary) -> String:
	var top := top_purpose(tasks)
	if top.is_empty():
		return ""
	return "Mostly %s (%d%%)" % [task_name(run, role, top["key"]), roundi(100.0 * float(top["share"]))]


## Why a role was busy, from its biggest task: "Mostly gathering wood (39%): no building or bench needed them, so
## they fell back on gathering." Or "" with no tasks counted.
static func why_line(run: RunState, role: String, tasks: Dictionary) -> String:
	var top := top_purpose(tasks)
	if top.is_empty():
		return ""
	var key: String = top["key"]
	var why: String = run.content.townsfolk[role].get("task_words", {}).get(
		"fetch" if key.begins_with("fetch:") else key, {}).get("why", "")
	return mostly_text(run, role, tasks) + (": %s." % why if why != "" else ".")


## A task's colour on the bar: gathering by its goods, else the task's own.
static func task_color(key: String) -> Color:
	if key.begins_with("fetch:"):
		return GOOD_COLORS.get(key.trim_prefix("fetch:"), Color("#8c8c8c"))
	return TASK_COLORS.get(key, Color("#8c8c8c"))


## One long bar of what a role's time went on (Yusuf, 2026-11-06): a part per task in its colour, solid for doing
## it and striped for walking to it and back; labels names the parts wide enough to hold their name.
static func make_task_bar(run: RunState, role: String, tasks: Dictionary, width: float, height: float,
		labels := false) -> Control:
	var bar := TaskBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var list := purposes(tasks)
	var total := _total(list)
	for p: Dictionary in list:
		var name := task_name(run, role, p["key"])
		bar.parts.append({"color": task_color(p["key"]), "walk": float(p["walk"]) / total, "doing": float(p["doing"]) / total,
			"label": "%s %d%%" % [name[0].to_upper() + name.substr(1), roundi(100.0 * float(p["total"]) / total)] if labels else ""})
	return bar


## The dawn card's bar and its caption (free), or null with nothing counted yet.
static func card_bar(run: RunState, role: String, width: float) -> Control:
	var b := run.people.busy_of(role)
	var tasks: Dictionary = b.get("tasks", {})
	if tasks.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.custom_minimum_size.x = width
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(make_task_bar(run, role, tasks, width, 7.0))
	var cap := Label.new()
	cap.text = mostly_text(run, role, tasks)
	cap.add_theme_font_size_override("font_size", UiKit.CAPTION)
	cap.add_theme_color_override("font_color", UiKit.DIM)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cap)
	return box


## Draws the task bar's parts (FolkAtWork.make_task_bar).
class TaskBar extends Control:
	var parts: Array[Dictionary] = []

	func _draw() -> void:
		var x := 0.0
		var font := get_theme_default_font()
		for p: Dictionary in parts:
			var c: Color = p["color"]
			var ww: float = size.x * float(p["walk"])
			var w: float = ww + size.x * float(p["doing"])
			var dark := c.darkened(0.55)
			var sx := 0.0
			while sx < ww:
				draw_rect(Rect2(x + sx, 0, minf(3.0, ww - sx), size.y), c if int(sx / 3.0) % 2 == 0 else dark)
				sx += 3.0
			if w > ww:
				draw_rect(Rect2(x + ww, 0, w - ww, size.y), c)
			if w >= 2.0:
				draw_rect(Rect2(x + w - 1.0, 0, 1.0, size.y), Color(0, 0, 0, 0.6))
			var label: String = p["label"]
			if label != "":
				var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.CAPTION)
				if ts.x + 10.0 <= w:
					var at := Vector2(x + (w - ts.x) / 2.0, (size.y - ts.y) / 2.0)
					draw_rect(Rect2(at - Vector2(3, 0), ts + Vector2(6, 0)), Color(1, 1, 1, 0.78))
					draw_string(font, at + Vector2(0, font.get_ascent(UiKit.CAPTION)), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
						UiKit.CAPTION, Color("#111111"))
			x += w


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
	var why := why_line(run, role, b.get("tasks", {}))
	if why != "":
		out.append(why)
	if run.people.reckoning().is_empty():
		out.append("A Reeve's hut shows the rest of their round.")
		return out
	if not b.get("tasks", {}).is_empty():
		out.append("Their round: %s." % task_split_text(run, role, b["tasks"]))
	else:
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
	var tasks: Dictionary = u.tasks if this_round or run.phase == RunState.Phase.BUILD else u.tasks_last
	if kinds.is_empty():
		return ""
	var split := task_split_text(run, u.type_id, tasks, 3) if not tasks.is_empty() else split_text(u.type_id, kinds)
	var line := "%s: %s" % ["This round" if this_round else "Last round", split]
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
## person on their own. Each group: {"label", "count", "kinds", "tasks", "brought"}.
static func groups(run: RunState, role: String, this_round: bool) -> Array[Dictionary]:
	var by_leaning := {}
	var singles: Array[Dictionary] = []
	for u in run.world.folk:
		if not u.alive or u.type_id != role:
			continue
		var kinds: Dictionary = u.time if this_round else u.time_last
		var tasks: Dictionary = u.tasks if this_round else u.tasks_last
		var brought := u.brought if this_round else u.brought_last
		if u.master_of != "" or u.mark != "":
			var label: String = u.display_name if u.master_of != "" else run.content.marks[u.mark]["name"]
			singles.append({"label": label, "count": 1, "kinds": kinds.duplicate(), "tasks": tasks.duplicate(), "brought": brought})
			continue
		var g: Dictionary = by_leaning.get_or_add(u.leaning, {"count": 0, "kinds": {}, "tasks": {}, "brought": 0})
		g["count"] = int(g["count"]) + 1
		g["brought"] = int(g["brought"]) + brought
		for k: String in kinds:
			g["kinds"][k] = float(g["kinds"].get(k, 0.0)) + float(kinds[k])
		for t: String in tasks:
			g["tasks"][t] = float(g["tasks"].get(t, 0.0)) + float(tasks[t])
	var out: Array[Dictionary] = []
	var keys := by_leaning.keys()
	keys.sort()
	for leaning: String in keys:
		var g: Dictionary = by_leaning[leaning]
		var label: String = "No leaning" if leaning == "" else run.content.townsfolk[role]["leanings"][leaning]["name"]
		out.append({"label": label, "count": g["count"], "kinds": g["kinds"], "tasks": g["tasks"], "brought": g["brought"]})
	out.append_array(singles)
	return out


## The task bar, or the older bar by kind when no tasks were counted (a record from before them).
static func _bar_for(run: RunState, role: String, kinds: Dictionary, tasks: Dictionary, width: float, height: float,
		labels := false) -> Control:
	if tasks.is_empty():
		return make_bar(kinds, width, height)
	return make_task_bar(run, role, tasks, width, height, labels)


## A bar's hover: the split by task, or by kind when no tasks were counted (an older record).
static func _tip(run: RunState, role: String, kinds: Dictionary, tasks: Dictionary) -> String:
	return task_split_text(run, role, tasks, 6) if not tasks.is_empty() else split_text(role, kinds)


## The Your people panel: a row per role (word, bar, output per head), opening to its leanings and named people.
static func build(parent: Control, run: RunState) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 760
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var legend := Label.new()
	legend.text = "Each bar is split by task: solid for doing it, striped for walking to it and back."
	legend.add_theme_font_size_override("font_size", UiKit.CAPTION)
	legend.add_theme_color_override("font_color", UiKit.HINT_COLOR)
	box.add_child(legend)
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
		who.add_theme_font_size_override("font_size", UiKit.STRONG)
		row.add_child(who)
		var tag := Label.new()
		tag.text = word_name(word)
		tag.custom_minimum_size.x = 80
		tag.add_theme_font_size_override("font_size", UiKit.BODY)
		tag.add_theme_color_override("font_color", word_tint(word))
		var advice := word_advice(role, word)
		tag.tooltip_text = advice[0].to_upper() + advice.substr(1) + "."
		tag.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(tag)
		var out := Label.new()
		out.text = output_text(run, role, impact_for(run, b["from"]))
		out.add_theme_font_size_override("font_size", UiKit.CAPTION)
		out.add_theme_color_override("font_color", UiKit.HINT_COLOR)
		row.add_child(out)
		var why := why_line(run, role, b.get("tasks", {}))
		if why != "":
			var why_row := HBoxContainer.new()
			box.add_child(why_row)
			var indent := Control.new()
			indent.custom_minimum_size.x = 24
			why_row.add_child(indent)
			var why_label := Label.new()
			why_label.text = why
			why_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why_label.custom_minimum_size.x = 700
			why_label.add_theme_font_size_override("font_size", UiKit.CAPTION)
			why_row.add_child(why_label)
		var bar := _bar_for(run, role, b["kinds"], b.get("tasks", {}), 760.0, 22.0, true)
		bar.tooltip_text = _tip(run, role, b["kinds"], b.get("tasks", {}))
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(bar)
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
			label.add_theme_font_size_override("font_size", UiKit.CAPTION)
			label.add_theme_color_override("font_color", UiKit.HINT_COLOR)
			sub.add_child(label)
			var gbar := _bar_for(run, role, g["kinds"], g["tasks"], 280.0, 7.0)
			gbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			gbar.tooltip_text = _tip(run, role, g["kinds"], g["tasks"])
			gbar.mouse_filter = Control.MOUSE_FILTER_PASS
			sub.add_child(gbar)
			if int(g["brought"]) > 0:
				var got := Label.new()
				got.text = "brought home %s each" % _each(float(g["brought"]) / float(g["count"]))
				got.add_theme_font_size_override("font_size", UiKit.CAPTION)
				got.add_theme_color_override("font_color", UiKit.HINT_COLOR)
				sub.add_child(got)
	if not any:
		UiKit.note(box, "Nothing to show yet: this fills in as the round plays.", UiKit.BODY)
