class_name RunStats
extends RefCounted
## Turns a list of run records (RunState.to_record()) into plain-language stats.
## Used by the in-game Run history screen and tools/run_report.gd.

static func report(runs: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var finished := runs.filter(func(r: Dictionary) -> bool: return r["result"] != "in_progress")
	var wins := finished.filter(func(r: Dictionary) -> bool: return r["result"] == "won").size()
	out.append("Runs: %d (%d finished)" % [runs.size(), finished.size()])
	if not finished.is_empty():
		out.append("Win rate: %d%%" % roundi(100.0 * wins / finished.size()))
		var reached := 0.0
		for r: Dictionary in finished:
			reached += float(r["round_reached"])
		out.append("Average round reached: %.1f" % (reached / finished.size()))

	var lost_in := {}
	var killers := {}
	var deaths_by_trait := {}
	var keep_damage := {}
	var keep_damage_n := {}
	var bounty_paid := 0.0
	var bounty_posted := 0.0
	var picked := {}
	var picked_wins := {}
	for r: Dictionary in runs:
		if r["result"] == "lost":
			var key := int(r["round_reached"])
			lost_in[key] = int(lost_in.get(key, 0)) + 1
		for h: Dictionary in r.get("fallen", []):
			deaths_by_trait[h["trait"]] = int(deaths_by_trait.get(h["trait"], 0)) + 1
		for rd: Dictionary in r.get("rounds", []):
			var b: Dictionary = rd.get("battle", {})
			if b.is_empty():
				continue
			var n := int(rd["round"])
			keep_damage[n] = float(keep_damage.get(n, 0.0)) + float(b["keep_damage"])
			keep_damage_n[n] = int(keep_damage_n.get(n, 0)) + 1
			bounty_paid += float(b["bounty_paid"])
			bounty_posted += float(b["bounty_paid"]) + float(b["bounty_refunded"])
			for d: Dictionary in b["hero_deaths"]:
				var k: String = d["killer"] if d["killer"] != "" else "unknown"
				killers[k] = int(killers.get(k, 0)) + 1
		if r["result"] != "in_progress":
			for relic: String in r.get("relics", []):
				picked[relic] = int(picked.get(relic, 0)) + 1
				if r["result"] == "won":
					picked_wins[relic] = int(picked_wins.get(relic, 0)) + 1

	out.append("Lost in round: %s" % _counts(lost_in))
	out.append("Heroes killed by: %s" % _counts(killers))
	out.append("Hero deaths by trait: %s" % _counts(deaths_by_trait))
	if bounty_posted > 0.0:
		out.append("Bounties: %d gold posted, %d%% claimed by heroes" % [bounty_posted, roundi(100.0 * bounty_paid / bounty_posted)])
	var rounds := keep_damage.keys()
	rounds.sort()
	var dmg := PackedStringArray()
	for n in rounds:
		dmg.append("r%d %d" % [n, roundi(keep_damage[n] / keep_damage_n[n])])
	out.append("Average keep damage per wave: %s" % ", ".join(dmg))
	var relic_ids := picked.keys()
	relic_ids.sort_custom(func(a: String, b: String) -> bool: return picked[a] > picked[b])
	out.append("Relics (times taken, win rate when taken):")
	for id: String in relic_ids:
		out.append("  %-18s %3d  %3d%%" % [id, picked[id], roundi(100.0 * int(picked_wins.get(id, 0)) / picked[id])])
	return out


static func _counts(d: Dictionary) -> String:
	var keys := d.keys()
	keys.sort()
	if keys.is_empty():
		return "none"
	return ", ".join(keys.map(func(k: Variant) -> String: return "%s: %d" % [k, d[k]]))
