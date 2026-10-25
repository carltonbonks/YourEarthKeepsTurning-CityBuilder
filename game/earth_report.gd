class_name EarthReport
extends RefCounted
## Where the attack's ways lie this round, for the threat card: which den it comes by and which near plate it
## crosses (the earth as this round's weather, Yusuf 2026-10-25).


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

