class_name EarthReport
extends RefCounted
## What the earth's last turn did, in a few short lines the threat card shows while building, and where the
## attack's ways lie now that the dens have moved. It reports what happened and never what comes next.

const MAX_LINES := 4


## The headline for the seam that woke, or "" when the earth has not turned yet this run.
static func headline(run: RunState) -> String:
	var earth := run.world.earth
	if earth.shifts == 0 or earth.last.is_empty():
		return ""
	if earth.woke.is_empty():
		return "The earth turned quietly."
	var where := World.compass(float(earth.woke["angle"]))
	match earth.woke["kind"]:
		"subduct":
			return "The earth turned: a seam swallowed land to the %s." % where
		"collide":
			return "The earth turned: plates crashed together to the %s." % where
		_:
			return "The earth turned: the ground split open to the %s." % where


## What the turn did, the town's own losses first.
static func lines(run: RunState) -> Array[String]:
	var out: Array[String] = []
	var earth := run.world.earth
	var c := run.content
	var embers: String = c.plates["embers"]
	var other_sank := 0
	var grown := {}
	for ev: Dictionary in earth.events:
		if ev["kind"] == "den_sank":
			out.append("The %s sank, and all in it." % _den_name(c, ev["type"]).to_lower())
	for ev: Dictionary in earth.events:
		if ev["kind"] == "find":
			out.append("%s lies open to the %s, for a bold hero to dig out." % [_node_name(c, ev["type"]),
				World.compass(Vector2(ev["pos"]).angle())])
	for ev: Dictionary in earth.events:
		if ev["kind"] != "sank" or ev["type"] == embers:
			continue
		if ev["worked"]:
			out.append("Your %s to the %s sank." % [_node_name(c, ev["type"]).to_lower(), World.compass(Vector2(ev["pos"]).angle())])
		else:
			other_sank += 1
	if other_sank > 0:
		out.append("%d untouched resource%s sank." % [other_sank, "" if other_sank == 1 else "s"])
	for ev: Dictionary in earth.events:
		if ev["kind"] == "raised":
			out.append("%s %s broke open to the %s." % ["A rich" if ev["great"] else "A ridge's", _node_name(c, ev["type"]).to_lower(),
				World.compass(Vector2(ev["pos"]).angle())])
		elif ev["kind"] == "grew":
			grown[_node_name(c, ev["type"]).to_lower()] = true
	var grew := earth.events.filter(func(ev: Dictionary) -> bool: return ev["kind"] == "grew").size()
	if grew > 0:
		out.append("%d fresh patch%s grew in the rifts (%s)." % [grew, "" if grew == 1 else "es", ", ".join(grown.keys())])
	return out.slice(0, MAX_LINES)


## Where the warned attack comes from and why: one line per side.
static func ways(run: RunState) -> Array[String]:
	var out: Array[String] = []
	var w := run.world
	for i in w.wave_sides.size():
		var type: String = w.wave_side_dens[i] if i < w.wave_side_dens.size() else ""
		var where := World.compass(w.wave_sides[i])
		if type == "":
			out.append("From the %s, over open country." % where)
			continue
		var line := "From the %s, by the %s's way" % [where, _den_name(run.content, type).to_lower()]
		var turned := 0.0
		for den in w.dens:
			if den["type"] == type:
				turned = float(den.get("turned", 0.0))
		if roundi(absf(turned)) > 0:
			line += ": the earth carried it %d° round" % roundi(absf(turned))
		out.append(line + ".")
	return out


static func _den_name(c: Content, type: String) -> String:
	return c.world["dens"][type]["name"]


static func _node_name(c: Content, type: String) -> String:
	return c.world["nodes"][type]["name"]
