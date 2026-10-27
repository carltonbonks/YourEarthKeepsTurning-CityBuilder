extends SceneTree
## Saves a picture of the game screen after a bot has played some rounds, to check how the map looks.
## Needs a display (not --headless); in a container: xvfb-run ~/godot/godot --path . -s res://tools/snapshot.gd -- seed=4821 round=5 style=market out=/tmp/map.png
## mid=1 stops partway through the round's first day instead of at the build phase; zoom= zooms the map;
## gates=2 has the bot order up to 2 gates; flat=1 shows the flat top-down map instead of the tilted one;
## pick=1 shows the round's first dawn pick instead; night=1 plays the round's first day into its night
## so the camera has closed in on the town (NightCamera); preview=<building id> blinks where that building would go,
## as hovering its card does; relic=1 stops at that round's relic pick and shows it; impact=1 shows Who did what
## (with relic=1, that round's; otherwise the whole run's). steps= is how many steps mid=1 plays; goods carried in
## meanwhile show as one "+N" popup. venture=<id> (with pick=1) deals that venture as the first dawn card, and
## venture_taken=1 takes it and shows who never came home. give=<relic id> hands the town that relic first;
## wave=1 (with night=1) plays on into the round's attack night until the hearth or a watch post shoots.
## pedlars=1 shows the round's pedlar choice (round= a pedlar round, e.g. 3). master=<trait id> (with pick=1)
## deals a Promote card for a craftsperson with that craft trait as the first dawn card.
## ageup=1 plays on from that round until the town reaches a new age and shows the celebration (style=bronze or
## medieval gets there); levelup=1 levels up the first hero so the halo shows.
## deals=<id,id,...> lays out those caravan trade cards (data/trades.json) in the build hand; id:roll:mod:mod rolls one.
## drafts=<type:roll:mod,...> lays out those blueprint offers in the draft; upgrade.<id>:roll:mod offers an upgrade (as the deepening offer), craft.<id> a craft.
## rolled=1 (with pick=1) deals rolled townsfolk cards: a magic warrior, a powerful forager and a mythic tribesperson;
## rolled=2 a magic family, a mythic venture and a powerful hero.
## drafted=1 skips the round's blueprint draft, so the build hand shows without the draft over it.
## won=1 plays to the end of the run (or calls it won where the bot falls) and shows the victory partway through
## (won_ms= how far in, default 3500).
## size=<W>x<H> sets the window size (default 1600x1000), to check the screen layout at other sizes.
## glow=<building id> lights every one of that building as hovering its upgrade card does; sparkle=<building id>
## shows them sparkling as just after taking an upgrade (with drafted=1, so the draft is out of the way).
## intro=1 plays the first-run camera tour and shows it intro_ms= in (default 3000); gentle=1 makes the run a
## gentle first run (with pick=1, the first dawn's few tribespeople).
## screen=title|welcome|settings shows the title screen, how a round works or Settings; tips=1 shows the
## lastkill=1 (with night=1) plays on until a night's last raider falls and shows the beat lastkill_ms= in (default 600);
## lastkill=2 waits for the kill that breaks the round's attack.
## one-time tip due at that moment (off otherwise, so pictures stay clear); seen=<id,id> marks tips as seen. The player's settings are never saved.
## doll=1 (with pick=1) gives Hearth-mother's Doll with its twin due on this dawn's townsfolk card.
## hover=<card title> shows that card's hover panel beside it, as resting the mouse on it does.
## path=heroes:3,warband:3 sets the town's paths (making a Legend, two sergeants and the caravan's path deals).
## charter=1 shows a charter pick at the round's build (as after an age-up); guild=<leaning> (with pick=1) deals that
## leaning's trades guild card first.
## hungry=1 empties the food store so the Elder speaks up (Advisor); showme=1 also presses its Show me;
## hearth=<share> sets the hearth's health to that share of its max.
## reeve=1 raises a Reeve's hut once the bot has played to the round; people=1 shows the People panel (needs reeve=1).

func _init() -> void:
	var args := {"seed": "4821", "round": "4", "style": "market", "out": "user://snapshot.png", "mid": "0", "zoom": "1.2", "gates": "-1", "flat": "0", "pick": "0", "night": "0", "preview": "", "relic": "0", "impact": "0", "steps": "150", "venture": "", "venture_taken": "0", "give": "", "wave": "0", "pedlars": "0", "master": "", "ageup": "0", "levelup": "0", "deals": "", "drafts": "", "rolled": "0", "drafted": "0", "size": "1600x1000", "screen": "", "tips": "0", "seen": "", "won": "0", "won_ms": "3500", "glow": "", "sparkle": "", "intro": "0", "intro_ms": "3000", "gentle": "0", "doll": "0", "hover": "", "lastkill": "0", "lastkill_ms": "600", "reeve": "0", "people": "0", "charter": "0", "guild": "", "path": "", "hungry": "0", "showme": "0", "hearth": ""}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var wh: PackedStringArray = args["size"].split("x")
	DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	var main: Control = load("res://game/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.settings.persist = false
	main.settings.tips = args["tips"] == "1"
	main.settings.tips_seen = Array(args["seen"].split(",", false))
	main.settings.intro_seen = true
	if args["intro"] == "1":
		main.settings.intro_seen = false
		main._new_run(int(args["seed"]))
		var until := Time.get_ticks_msec() + int(args["intro_ms"])
		while Time.get_ticks_msec() < until:
			await process_frame
		root.get_texture().get_image().save_png(args["out"])
		print("Saved %s (tour, %s ms in)" % [args["out"], args["intro_ms"]])
		quit()
		return
	main._new_run(int(args["seed"]))
	var run: RunState = main.run
	run.gentle = args["gentle"] == "1"
	if args["give"] != "":
		run.relics.append(args["give"])
		run.relic_acquired_round[args["give"]] = run.round_number
	var bot := AutoPlayer.new()
	bot.style = args["style"]
	if int(args["gates"]) >= 0:
		bot.gates = int(args["gates"])
	var stop_at := RunState.Phase.RELIC if args["relic"] == "1" else RunState.Phase.BUILD
	while not run.is_over() and not (run.round_number >= int(args["round"]) and run.phase == stop_at):
		match run.phase:
			RunState.Phase.BUILD:
				bot.build(run)
				run.begin_round()
			RunState.Phase.PICK:
				run.choose_pick(bot.pick(run))
			RunState.Phase.SIM:
				run.run_until_pause()
			RunState.Phase.RELIC:
				run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
	if args["reeve"] == "1" and run.world.add_building("reeves_hut"):
		run.world.buildings[-1]["work_left"] = 0.0
	if args["mid"] == "1" and run.phase == RunState.Phase.BUILD:
		bot.build(run)
		run.begin_round()
		while run.phase == RunState.Phase.PICK:
			run.choose_pick(bot.pick(run))
		main._arena.pickups.update(run.world, Time.get_ticks_msec())
		for i in int(args["steps"]):
			run.step()
		# Show what was carried in meanwhile as one "+N" popup over the hearth.
		main._arena.pickups.update(run.world, Time.get_ticks_msec() + PickupPopups.BUCKET_MS)
	if args["night"] == "1" and run.phase == RunState.Phase.BUILD:
		bot.build(run)
		run.begin_round()
		run.choose_pick(bot.pick(run))
		while not run.world.is_night():
			run.step()
		for i in 60:
			run.step()
		if args["wave"] == "1":
			var tower_shot := func() -> bool: return run.world.shots.any(func(x: Dictionary) -> bool: return x.get("tower", false))
			while run.phase == RunState.Phase.PICK or run.phase == RunState.Phase.SIM:
				if run.phase == RunState.Phase.PICK:
					run.choose_pick(bot.pick(run))
				run.step()
				if run.world.is_wave_night() and tower_shot.call():
					main._set_speed(0)  # Hold the shot in the air for the picture.
					break
	if args["lastkill"] != "0":
		var lk: LastKill = main._arena.last_kill
		while run.phase == RunState.Phase.PICK or run.phase == RunState.Phase.SIM:
			if run.phase == RunState.Phase.PICK:
				run.choose_pick(bot.pick(run))
			run.step()
			if lk.watch(main._arena, run.world) and (args["lastkill"] == "1" or lk.kill["ends"]):
				break
		main._set_speed(0)
		main._arena.zoom = 1.8
		main._arena.pan = Vector2.ZERO
		lk.start(main._arena, lk.kill)
		lk._from_ms = Time.get_ticks_msec() - float(args["lastkill_ms"])
	main._overlays.hide()
	if args["path"] != "":
		# path=<id>:<tier>[,...] sets the town's paths, hails a Legend, makes sergeants and lays the caravan out again.
		for spec in args["path"].split(","):
			var pt: PackedStringArray = spec.split(":")
			run.paths[pt[0]] = int(pt[1]) if pt.size() > 1 else 1
		run.people.crown_legend()
		for u in run.world.folk.filter(func(f: Unit) -> bool: return f.type_id == "warrior").slice(0, 2):
			u.kills = maxi(u.kills, int(run.content.promotions["warrior"]["kills"]))
		run.people.raise_sergeants()
		if run.phase == RunState.Phase.BUILD:
			run.caravan.lay_out()
		# A charter shown next must open first, as in play (the draft waits for it).
		if args["charter"] != "1":
			main._refresh()
	if args["charter"] == "1" and run.phase == RunState.Phase.BUILD:
		run.charters_due += 1
		run._roll_charter()
		main._refresh()
		main._overlays.show_for_phase()
	if args["pedlars"] == "1" and run.awaiting_pedlar():
		main._refresh()
		main._overlays.show_for_phase()
	if args["pick"] == "1" and run.phase == RunState.Phase.BUILD:
		bot.build(run)
		run.begin_round()
		if args["venture"] != "":
			run.pick_offer[0] = {"kind": "venture", "role": "venture", "cost": 0, "venture": args["venture"]}
		if args["guild"] != "":
			run.pick_offer[0] = {"kind": "guild", "role": "guild", "cost": 0, "leaning": args["guild"]}
		if args["master"] != "":
			var crafter: Unit = run.world.folk[0]
			crafter.made["knapper"] = 9
			run.pick_offer[0] = {"kind": "promote", "role": "craftsperson", "cost": 15, "unit": crafter, "workshop": "knapper",
				"trait": args["master"], "name": run.people.unused_name()}
		if args["rolled"] == "1":
			run.pick_offer = [{"kind": "folk", "role": "warrior", "cost": 0, "roll": "blue", "mark": "swift"},
				{"kind": "folk", "role": "tribesperson", "cost": 0, "leaning": "forager", "roll": "yellow", "mark": "nimble",
					"boons": ["born_leader", "twins"]},
				{"kind": "folk", "role": "tribesperson", "cost": 0, "leaning": "woodcutter", "roll": "orange", "boons": ["many_mother"]}]
		if args["rolled"] == "2":
			run.pick_offer = [{"kind": "family", "role": "family", "cost": 0, "roles": ["tribesperson", "warrior"], "roll": "blue",
				"boons": ["big_family"]},
				{"kind": "venture", "role": "venture", "cost": 0, "venture": run.content.ventures.keys()[0], "roll": "orange",
					"boons": ["cursed_road"]}]
			var hero := run.people.make_hero(true)
			var card := {"kind": "hero", "role": "hero", "cost": 25, "hero": hero, "roll": "yellow", "boons": ["war_tested", "houndmaster"]}
			run.people._shape_hero(card, SeededRng.new(1))
			run.pick_offer.append(card)
		if args["doll"] == "1":
			run.relics.append("hearth_mothers_doll")
			run.folk_cards_taken = 2
		main._overlays.show_for_phase()
		if args["venture_taken"] == "1":
			main._take_pick(0)
	if args["deals"] != "" and run.phase == RunState.Phase.BUILD:
		run.caravan.offers.clear()
		for spec in args["deals"].split(","):
			var parts: PackedStringArray = spec.split(":")
			var id := parts[0]
			var offer := {"deal": id, "need": run.caravan.need(id), "taken": false}
			if parts.size() > 2:
				offer["roll"] = parts[1]
				offer["boons"] = Array(parts.slice(2))
			run.caravan.offers.append(offer)
	if args["drafts"] != "" and run.phase == RunState.Phase.BUILD:
		run.hand.cards.clear()
		run.hand.upgrade_offers.clear()
		run.hand.crafts.clear()
		run.hand.picks = maxi(1, run.hand.picks)
		for spec in args["drafts"].split(","):
			var parts: PackedStringArray = spec.split(":")
			var offer := {}
			if parts[0].begins_with("upgrade."):
				offer = {"upgrade": parts[0].trim_prefix("upgrade."), "deep": true}
			elif parts[0].begins_with("craft."):
				offer = {"craft": parts[0].trim_prefix("craft."), "need": ""}
			else:
				offer = {"building": parts[0], "need": run.hand.need(parts[0])}
			if parts.size() > 2:
				offer["roll"] = parts[1]
				offer["boons"] = Array(parts.slice(2))
			if offer.has("upgrade"):
				run.hand.upgrade_offers.append(offer)
			elif offer.has("craft"):
				run.hand.crafts.append(offer)
			else:
				run.hand.cards.append(offer)
	if args["drafted"] == "1" and run.phase == RunState.Phase.BUILD:
		run.hand.picks = 0
	main._refresh()
	main._arena.upgrade_glow.hover_type = args["glow"]
	if args["glow"] != "":
		var lit := func(node: Node, find: Callable) -> Node:
			for child in node.get_children():
				if child.has_meta("lights"):
					return child
				var deeper: Node = find.call(child, find)
				if deeper != null:
					return deeper
			return null
		var card: Node = lit.call(main._overlays, lit)
		if card != null:
			main._overlays._peek(card)
	if args["sparkle"] != "":
		main._arena.upgrade_glow.sparkle(args["sparkle"], Time.get_ticks_msec() - 300)
	main._arena.celebrations.update(run, Time.get_ticks_msec())
	if args["ageup"] == "1":
		var start_age := run.age
		while not run.is_over() and run.age == start_age:
			match run.phase:
				RunState.Phase.BUILD:
					bot.build(run)
					run.begin_round()
				RunState.Phase.PICK:
					run.choose_pick(bot.pick(run))
				RunState.Phase.SIM:
					run.step()
				RunState.Phase.RELIC:
					run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
		# A few steps on, so the new ground has been drawn once and glows.
		for i in 10:
			run.step()
		main._refresh()
	if args["levelup"] == "1" and not run.living_heroes().is_empty():
		var hero: Unit = run.living_heroes()[0]
		hero.xp = run.content.num("xp_per_level") * hero.level
		run.people.level_up(hero)
	main._arena.celebrations.update(run, Time.get_ticks_msec())
	if args["relic"] == "1" and run.phase == RunState.Phase.RELIC:
		main._overlays.show_for_phase()
	if args["impact"] == "1":
		main._overlays.show_impact(args["relic"] != "1")
	if args["people"] == "1":
		main._overlays.show_people()
	if args["preview"] != "":
		main._preview_building(args["preview"])
	main._arena.iso = args["flat"] != "1"
	if args["night"] != "1":
		main._arena.zoom = float(args["zoom"])
	if args["won"] == "1":
		while not run.is_over():
			match run.phase:
				RunState.Phase.BUILD:
					bot.build(run)
					run.begin_round()
				RunState.Phase.PICK:
					run.choose_pick(bot.pick(run))
				RunState.Phase.SIM:
					run.step()
				RunState.Phase.RELIC:
					run.choose_relic(run.relic_offer[0] if not run.relic_offer.is_empty() else "")
		run.phase = RunState.Phase.WON
		main._overlays.hide()
		main._overlays.showing_draft = false
		main._arena.zoom = 1.2
		main._on_pause()
		main._arena.victory.born = Time.get_ticks_msec() - float(args["won_ms"])
		if main._arena.victory.born + Victory.SHOW_MS <= Time.get_ticks_msec():
			main._arena.skip_victory()
	if args["hungry"] == "1":
		run.stock["food"] = 0
	if args["hearth"] != "":
		run.world.hearth_hp = run.hearth_max_hp() * float(args["hearth"])
	if args["hungry"] == "1" or args["hearth"] != "":
		main._refresh()
		main._advisor._shown_at = -10.0
		main._advisor._show_me = args["showme"] == "1"
	match args["screen"]:
		"title":
			main._show_title()
		"welcome":
			main._overlays.show_welcome(true)
		"settings":
			main._overlays.show_settings()
	main._refresh_live()
	for i in 4:
		_hold_last_kill(main, args)
		await process_frame
	main._refresh_live()
	_hold_last_kill(main, args)
	await process_frame
	if args["hover"] != "":
		var cards := root.find_children("*", "Button", true, false).filter(
			func(c: Node) -> bool: return c is CardView and c.is_visible_in_tree() and c.title_label.text == args["hover"])
		if not cards.is_empty():
			var card: CardView = cards[0]
			var panel := PanelContainer.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color("#1b1e24")
			sb.set_content_margin_all(8)
			panel.add_theme_stylebox_override("panel", sb)
			panel.add_child(card._make_custom_tooltip(card.tooltip_text))
			root.add_child(panel)
			panel.position = card.get_global_rect().position + Vector2(card.size.x * 0.5, card.size.y * 0.6)
			await process_frame
			await process_frame
	var image := root.get_texture().get_image()
	image.save_png(args["out"])
	print("Saved %s (round %d)" % [args["out"], run.round_number])
	quit()


## Keeps the last kill's beat at lastkill_ms in while frames are drawn (the first frames can take longer than the beat).
func _hold_last_kill(main: Control, args: Dictionary) -> void:
	var lk: LastKill = main._arena.last_kill
	if args["lastkill"] != "0" and not lk.kill.is_empty():
		lk._from_ms = Time.get_ticks_msec() - float(args["lastkill_ms"])
