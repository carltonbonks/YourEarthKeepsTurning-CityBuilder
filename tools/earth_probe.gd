extends SceneTree
## The shifting earth on its own: turns fresh maps through a whole run's shifts (no rounds played) and prints,
## averaged per run, what the seams did, plus the thinnest plate and tallest ridge seen. Use it to check
## data/plates.json speeds before playing. Usage: godot --headless --path . -s res://tools/earth_probe.gd [-- runs=100]

func _init() -> void:
	var runs := 100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			runs = int(arg.trim_prefix("runs="))
	var content := Content.load_default()
	var shifts := content.int_num("rounds_to_win") - 1
	var totals := {}
	var by_type := {}
	var thinnest := 360.0
	var tallest := 0
	var den_moved := 0.0
	var nodes_start := 0
	var nodes_end := 0
	var by_ring := {}
	for s in runs:
		var run := RunState.new(content, 1000 + s)
		var w := run.world
		var earth := w.earth
		nodes_start += w.nodes.filter(func(n: Dictionary) -> bool: return w.node_active(n)).size()
		var den_at: Array = w.dens.map(func(d: Dictionary) -> Vector2: return d["pos"])
		for n in shifts:
			earth.shift()
			for ev: Dictionary in earth.events:
				var ring_key := "%s %s%s" % [["near", "middle", "far", "still"][earth.ring_at(ev["pos"])], ev["kind"], " (woke)" if ev["great"] else ""]
				by_ring[ring_key] = int(by_ring.get(ring_key, 0)) + 1
			if not earth.woke.is_empty():
				var woke_key := "woke %s %s" % [["near", "middle", "far"][int(earth.woke["ring"])], earth.woke["kind"]]
				by_ring[woke_key] = int(by_ring.get(woke_key, 0)) + 1
			for key: String in earth.last:
				var v: Variant = earth.last[key]
				if v is Dictionary:
					for t: String in v:
						by_type["%s %s" % [key, t]] = int(by_type.get("%s %s" % [key, t], 0)) + int(v[t])
						totals[key] = int(totals.get(key, 0)) + int(v[t])
				elif not key in ["shift", "woke", "woke_ring"]:
					totals[key] = int(totals.get(key, 0)) + int(v)
			for ring in earth.rings:
				var seams: Array = ring["seams"]
				for k in seams.size():
					thinnest = minf(thinnest, rad_to_deg(fposmod(float(seams[(k + 1) % seams.size()]) - float(seams[k]), TAU)))
					tallest = maxi(tallest, int(ring["ridges"][k]))
		nodes_end += w.nodes.filter(func(n: Dictionary) -> bool: return w.node_active(n)).size()
		for i in mini(den_at.size(), w.dens.size()):
			den_moved += rad_to_deg(absf(angle_difference(Vector2(den_at[i]).angle(), Vector2(w.dens[i]["pos"]).angle())))
		run.dispose()
	print("%d runs, %d shifts each. Per run on average:" % [runs, shifts])
	var keys: Array = totals.keys()
	keys.sort()
	for key: String in keys:
		print("  %-16s %6.2f" % [key, float(totals[key]) / runs])
	keys = by_type.keys()
	keys.sort()
	for key: String in keys:
		print("    %-24s %6.2f" % [key, float(by_type[key]) / runs])
	print("  by ring:")
	keys = by_ring.keys()
	keys.sort()
	for key: String in keys:
		print("    %-28s %6.2f" % [key, float(by_ring[key]) / runs])
	print("  nodes on the map  %.1f at the start, %.1f after the last shift" % [float(nodes_start) / runs, float(nodes_end) / runs])
	print("  a den ends %.0f degrees round from where it started" % (den_moved / maxf(1.0, runs * content.num("den_count"))))
	print("  thinnest plate %.1f degrees, tallest ridge %d" % [thinnest, tallest])
	quit()
