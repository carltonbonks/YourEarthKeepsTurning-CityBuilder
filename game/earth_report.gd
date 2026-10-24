class_name EarthReport
extends RefCounted
## What the earth's last turn did, in a few short lines the threat card shows while building, and where the
## attack's ways lie now that the rings have clicked round: which den it comes by and which near plate it crosses.

const MAX_LINES := 4


## The headline for the seam that woke, or "" when the earth has not turned yet this run.
static func headline(run: RunState) -> String:
	var earth := run.world.earth
	if earth.shifts == 0 or earth.last.is_empty():
		return ""
	if earth.woke.is_empty():
		return "The earth turned quietly." if not bool(earth.last.get("held", false)) else "The earth turned; the near ring held still."
	var where := World.compass(float(earth.woke["angle"]))
	var more := earth.woken.size() - 1
	var also := "" if more <= 0 else " (and %d more seam%s woke)" % [more, "" if more == 1 else "s"]
	match earth.woke["kind"]:
		"subduct":
			return "The earth turned: a seam swallowed land to the %s%s." % [where, also]
		"collide":
			return "The earth turned: a ridge heaved up to the %s%s." % [where, also]
		_:
			return "The earth turned: the ground split into a valley to the %s%s." % [where, also]


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
		out.append("%d fresh patch%s grew in a valley (%s)." % [grew, "" if grew == 1 else "es", ", ".join(grown.keys())])
	var full := earth.full_seams().size()
	if full > 0:
		out.append("%d seam%s full: %s at the next turn. Cracks show what a trench will take." % [full, " is" if full == 1 else "s are", "it wakes" if full == 1 else "they wake"])
	return out.slice(0, MAX_LINES)


## Where the warned attack comes from and why: one line per side.
static func ways(run: RunState) -> Array[String]:
	var out: Array[String] = []
	var w := run.world
	for i in w.wave_sides.size():
		var type: String = w.wave_side_dens[i] if i < w.wave_side_dens.size() else ""
		var where := World.compass(w.wave_sides[i])
		if type == "":
			out.append("From the %s, over open country%s." % [where, _across(run, w.wave_sides[i])])
			continue
		out.append("From the %s, by the %s's way%s." % [where, _den_name(run.content, type).to_lower(), _across(run, w.wave_sides[i])])
	return out


## ", across the Fen: raiders wade slowly under your towers" for the near plate an attack from angle a crosses.
static func _across(run: RunState, a: float) -> String:
	var kind := run.world.earth.crossing(a)
	if kind == "":
		return ""
	var kd := run.world.earth.kind_def(kind)
	return ", across the %s: %s" % [kd["name"], kd["short"]]


static func _den_name(c: Content, type: String) -> String:
	return c.world["dens"][type]["name"]


static func _node_name(c: Content, type: String) -> String:
	return c.world["nodes"][type]["name"]
