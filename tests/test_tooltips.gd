extends TestCase
## Hover tooltips: what they say about creatures, buildings and heroes, and the supply warnings.


func _run() -> RunState:
	var run := RunState.new(Content.load_default(), 4821)
	run.stock["wood"] = 99
	run.stock["stone"] = 99
	return run


func test_stall_without_its_workshop_warns() -> void:
	var run := _run()
	check(run.build("market"), "can order a market")
	check(run.build("hide_stall"), "can order a hide stall")
	var warned := Tooltips.warnings(run, "hide_stall")
	check_eq(warned.size(), 1, "a hide stall with no hide rack gets one warning")
	check(warned.size() == 1 and "hide rack" in warned[0], "the warning names the hide rack")
	check(run.build("hide_rack"), "can order a hide rack")
	check(Tooltips.warnings(run, "hide_stall").is_empty(), "the warning goes once a hide rack is ordered")
	check(Tooltips.warnings(run, "hide_rack").is_empty(), "a hide rack with its stall has no warning")


func test_workshop_without_its_stall_warns() -> void:
	var run := _run()
	check(run.build("knapper"), "can order a knapper")
	var warned := Tooltips.warnings(run, "knapper")
	check(warned.size() == 1 and "arms stall" in warned[0], "a knapper with no arms stall says so")


func test_creature_tags_explain_their_rules() -> void:
	var run := _run()
	var tip := Tooltips.enemy(run, "cave_bear")
	var tags: Array = tip["tags"]
	check(tags.any(func(t: String) -> bool: return t.begins_with("sentient: ")), "sentient explains itself")
	check(tags.any(func(t: String) -> bool: return t.begins_with("beast: ") and "hunting lodge" in t and "not built" in t),
		"beast names the hunting lodge prize, not yet built")
	check("animal" in tags, "tags with no rule show by name")
	check(Tooltips.enemy(run, "bronze_reaver")["lines"].any(func(l: String) -> bool: return "metal" in l), "reavers mention their shield")


func test_map_hover_finds_heroes_and_dens() -> void:
	var run := _run()
	var view := ArenaView.new()
	view.run = run
	view.size = Vector2(900, 700)
	var hero: Unit = run.heroes[0]
	var tip := view.hovered(view._to_screen(hero.pos))
	check_eq(tip.get("title", ""), hero.display_name, "pointing at a hero shows that hero")
	var den: Dictionary = run.world.dens[0]
	check_eq(view.hovered(view._to_screen(den["pos"])).get("title", ""), run.content.world["dens"][den["type"]]["name"],
		"pointing at a den shows the den")
	check(view.hovered(Vector2(1, 1)).is_empty(), "pointing at empty ground shows nothing")
	check(Tooltips.as_text(Tooltips.hero(run, hero)).begins_with(hero.display_name), "hero text starts with the name")
	view.free()
