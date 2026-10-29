extends TestCase
## Rendered map art (art/manifest.json, tools/render_art.sh, game/sprite_book.gd): every manifest row names a
## real content id and is rendered, every rendered sprite has its row, and walkers pick the frame for the way
## they move.

## Kinds of art and the content table their ids come from (scenery has a fixed list: things with no table of their own).
const WALKERS := ["townsfolk", "hero", "enemy"]
const SCENERY := ["barricade", "pedlar_camp", "hearth"]
## The sprites' source PNGs may take this much of the repository (docs/ART_SPEC.md budget).
const SPRITE_BUDGET_MB := 14


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The ids a kind of art may use, or null for an unknown kind.
func _ids_for(content: Content, kind: String) -> Variant:
	match kind:
		"building":
			return content.buildings
		"townsfolk":
			return content.townsfolk
		"hero":
			return content.hero_classes
		"enemy":
			return content.enemies
		"node":
			return content.world["nodes"]
		"den":
			return content.world["dens"]
		"obstacle":
			return content.town["obstacles"]
		"plate":
			var ids := {}
			for k: String in content.plates["near_kinds"]:
				ids["plate_" + k] = true
			return ids
		"scenery":
			var ids := {}
			for k: String in SCENERY:
				ids[k] = true
			return ids
		"icon":
			return {"relic_icons": true, "item_icons": true}
	return null


func test_manifest_rows_name_real_content_and_say_where_they_come_from() -> void:
	var content := Content.load_default()
	var rows: Dictionary = _json("res://art/manifest.json")["sprites"]
	check(not rows.is_empty(), "the manifest lists some art")
	for id: String in rows:
		var row: Dictionary = rows[id]
		var ids: Variant = _ids_for(content, str(row.get("kind", "")))
		check(ids != null, "%s has a known kind" % id)
		if ids != null:
			check((ids as Dictionary).has(id), "%s is a %s id in data/" % [id, row["kind"]])
		check(FileAccess.file_exists("res://" + str(row.get("model", ""))), "%s's model file exists" % id)
		check(str(row.get("licence", "")) != "", "%s says where it comes from (licence)" % id)
		if row.get("kind", "") in WALKERS:
			check_eq(int(row["facings"]), 8, "%s walks, so it has 8 facings" % id)
			check(float(row.get("height_r", 0.0)) > 0.0, "%s has a height_r" % id)
			check(row.get("rig", "") in ["humanoid", "quadruped", "none"], "%s has a rig the renderer can pose" % id)
		else:
			# Things that stand still: seen from one side, or 8 for those turned across the way through (gates).
			check(int(row["facings"]) in [1, 8], "%s is seen from 1 side or turned 8 ways" % id)
			check(float(row.get("world_per_unit", 0.0)) > 0.0, "%s has a world_per_unit" % id)
			check(not row.has("rig"), "%s stands still (no rig)" % id)


func test_every_row_is_rendered_and_every_sprite_has_a_row() -> void:
	var rows: Dictionary = _json("res://art/manifest.json")["sprites"]
	var rendered: Dictionary = _json("res://art/sprites/index.json")["sprites"]
	for id: String in rows:
		check(rendered.has(id), "%s is rendered (run tools/render_art.sh %s)" % [id, id])
	for id: String in rendered:
		check(rows.has(id), "%s in art/sprites has a manifest row" % id)
	var book := SpriteBook.new()
	for id: String in rendered:
		check(book.has(id), "the game loads %s's sprite" % id)
		if not book.has(id):
			continue
		var info := book.info(id)
		var tex: Texture2D = info["texture"]
		var columns := 0
		for anim: String in info["anims"]:
			columns += int(info["anims"][anim][1])
		check_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(int(info["frame"][0]) * columns, int(info["frame"][1]) * int(info["facings"])),
			"%s's sheet holds a row per facing and a column per animation frame" % id)
		if info["kind"] in WALKERS:
			check(info["anims"].has("walk") and info["anims"].has("attack"), "%s walks and strikes" % id)
			check(info["anims"].has("fall") and info["anims"].has("cheer"), "%s falls and cheers" % id)
		else:
			check_eq(int(info["anims"]["idle"][1]), int(info.get("variants", 1)), "%s has a column per look" % id)
		check(float(info["figure_px"]) > 0.0, "%s stands above its feet" % id)
		check_eq(info.get("card_boxes", []).size(), int(info["anims"]["idle"][1]), "%s has a card box per look" % id)


func test_walkers_face_the_way_they_move() -> void:
	check_eq(SpriteBook.facing_of(Vector2(1, 0), 8), 0, "along +x is facing 0")
	check_eq(SpriteBook.facing_of(Vector2(1, 1), 8), 1, "facings turn toward +y")
	check_eq(SpriteBook.facing_of(Vector2(0, 1), 8), 2, "+y is a quarter turn")
	check_eq(SpriteBook.facing_of(Vector2(-1, 0), 8), 4, "-x is half a turn")
	check_eq(SpriteBook.facing_of(Vector2(0.2, -1), 8), 6, "nearly -y rounds to facing 6")
	check_eq(SpriteBook.facing_of(Vector2(1, -0.1), 8), 0, "just short of a full turn is facing 0")
	check_eq(SpriteBook.facing_of(Vector2(0, 1), 1), 0, "a building has one facing")


func test_sprites_draw_only_tilted_and_with_the_setting_on() -> void:
	var view := ArenaView.new()
	check(view.sprites.has("hut"), "the hut has art")
	check(view._has_art("hut"), "tilted with Rendered art on, the hut is its sprite")
	check(not view._has_art("longhouse_never_drawn"), "an id with no art keeps its shape")
	view.art = false
	check(not view._has_art("hut"), "Rendered art off draws shapes")
	view.art = true
	view.iso = false
	check(not view._has_art("hut"), "the flat map is always shapes")
	view.free()


func test_walkers_glide_walk_strike_and_flash() -> void:
	var motion := WalkerMotion.new()
	var u := Unit.new()
	u.cooldown = 1.0
	u.hp = 10.0
	var first := motion.look(u, Vector2(100, 0), 8, 0.0)
	check_eq(int(first["facing"]), 4, "a newcomer faces the hearth")
	check(not first["walking"], "standing still at first")
	var moved := motion.look(u, Vector2(110, 0), 8, 16.0)
	check(moved["walking"], "a unit that moved walks")
	check(Vector2(moved["at"]).x > 100.0 and Vector2(moved["at"]).x < 110.0, "the drawn spot glides toward the real one")
	check_eq(int(moved["facing"]), 0, "it faces the way it moved")
	var later := motion.look(u, Vector2(110, 0), 8, 1000.0)
	check(not later["walking"], "it stands once it stops")
	check(Vector2(later["at"]).distance_to(Vector2(110, 0)) < 0.1, "and has caught up")
	u.cooldown_left = 1.0
	u.hp = 7.0
	var struck := motion.look(u, Vector2(110, 0), 8, 1016.0)
	check(float(struck["attack"]) >= 0.0, "a blow starts the swing")
	check(Color(struck["tint"]).r > 1.0, "a hit flashes")
	var after := motion.look(u, Vector2(110, 0), 8, 1016.0 + WalkerMotion.ATTACK_MS + 1.0)
	check_eq(float(after["attack"]), -1.0, "the swing plays once")
	check_eq(Color(after["tint"]), Color.WHITE, "the flash fades")
	var book := SpriteBook.new()
	check_eq(book.walker_frame("tribesperson", struck)["anim"], "attack", "a swing shows the attack frames")
	check_eq(book.walker_frame("tribesperson", moved)["anim"], "walk", "a walker shows the walk frames")
	check_eq(book.walker_frame("tribesperson", later)["anim"], "idle", "a stander stands")
	var glad := later.duplicate()
	glad["cheer"] = 1
	check_eq(book.walker_frame("tribesperson", glad), {"anim": "cheer", "frame": 1}, "a stander told to cheer cheers")
	var busy := struck.duplicate()
	busy["cheer"] = 1
	check_eq(book.walker_frame("tribesperson", busy)["anim"], "attack", "but a blow comes first")


func test_plates_carry_their_own_look_and_turn_with_the_ring() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var w := run.world
	var props := GroundProps.new()
	var all := func(_id: String) -> bool: return true
	var laid := props.props(w, 0.0, all)
	check(laid.size() > 40, "the plates are dressed (%d props)" % laid.size())
	var near: Dictionary = w.earth.rings[0]
	for p: Array in laid:
		var at: Vector2 = p[0]
		check(at.length() >= float(near["r0"]) and at.length() <= float(near["r1"]), "props stay on the turning ring")
		check(p[1] == "plate_" + w.earth.kind_at(at), "each prop shows its own plate's kind")
		for node in w.nodes:
			if w.node_active(node):
				check(at.distance_to(node["pos"]) >= GroundProps.KEEP_CLEAR, "props keep clear of nodes")
	check_eq(props.props(w, 0.0, all).size(), laid.size(), "the same props every frame")
	var turned := props.props(w, 0.3, all)
	if not turned.is_empty() and not laid.is_empty():
		check(Vector2(turned[0][0]).distance_to(laid[0][0]) > 1.0, "props slide with their plate")
	var none := func(_id: String) -> bool: return false
	check(props.props(w, 0.0, none).is_empty(), "no art, no props")


func test_every_item_base_and_relic_has_a_card_picture() -> void:
	var content := Content.load_default()
	var art: Dictionary = _json("res://art/card_art.json")
	var rows: Dictionary = _json("res://art/manifest.json")["sprites"]
	check_eq(art["items"].size(), int(rows["item_icons"]["variants"]), "a look per item base in the item icons")
	check_eq(art["relic_looks"].size(), int(rows["relic_icons"]["variants"]), "a column per relic look")
	var book := SpriteBook.new()
	for base: String in content.items["bases"]:
		check(base in art["items"], "item base %s has a picture in art/card_art.json" % base)
		check(book.item_texture(base) != null, "item base %s's picture loads" % base)
	for id: String in content.relics:
		check(art["relics"].get(id, "") in art["relic_looks"], "relic %s has a look in art/card_art.json" % id)
		check(book.relic_texture(id) != null, "relic %s's picture loads" % id)
	check(book.card_texture("no_such_thing") == null, "nothing without art")
	check(book.relic_texture("no_such_relic") == null, "no relic, no picture")


func test_cards_show_their_picture_under_the_band() -> void:
	var book := SpriteBook.new()
	var card := CardView.new(CardView.Size.MEDIUM, "building", "Blueprint", "Hut")
	card.set_picture(book.card_texture("hut"))
	var pic := card.find_child("Picture", true, false) as TextureRect
	check(pic != null, "a card with art shows its picture")
	if pic != null:
		check(pic.texture is AtlasTexture, "the picture is cut from the sprite sheet")
		var region: Rect2 = (pic.texture as AtlasTexture).region
		var frame: Array = book.info("hut")["frame"]
		check(region.size.x <= float(frame[0]) and region.size.y <= float(frame[1]), "cut to the figure, within one frame")
	var plain := CardView.new(CardView.Size.MEDIUM, "relic", "Relic", "Nothing")
	plain.set_picture(null)
	check(plain.find_child("Picture", true, false) == null, "a card without art keeps its old look")
	card.free()
	plain.free()


func test_the_fallen_fall_lie_and_fade() -> void:
	var run := RunState.new(Content.load_default(), 4821)
	var w := run.world
	var fallen := Fallen.new()
	var motion := WalkerMotion.new()
	var art := func(_id: String) -> bool: return true
	var folk: Unit = w.folk[0]
	var hero: Unit = run.heroes[0]
	motion.look(folk, Vector2(40, 0), 8, 0.0)
	fallen.update(w, run.heroes, motion, art, 0.0)
	check(fallen.bodies.is_empty(), "nobody has fallen yet")
	folk.alive = false
	folk.hp = 0.0
	w.folk.erase(folk)
	hero.alive = false
	hero.hp = 0.0
	fallen.update(w, run.heroes, motion, art, 100.0)
	check_eq(fallen.bodies.size(), 2, "a townsperson and a hero fell, even once the town has let them go")
	var body: Dictionary = fallen.bodies[0] if not fallen.bodies[0]["hero"] else fallen.bodies[1]
	check_eq(Vector2(body["at"]), Vector2(40, 0), "a body lies where its walker was last drawn")
	check_eq(int(body["facing"]), 4, "facing the way it last faced")
	check_eq(fallen.frame(body, 4, 100.0), 0, "the fall starts at its first frame")
	check_eq(fallen.frame(body, 4, 100.0 + Fallen.FALL_MS * 2.0), 3, "and lies on the last")
	check_eq(fallen.opacity(body, 100.0 + Fallen.LIE_MS * 0.5), 1.0, "it lies a while")
	check(fallen.opacity(body, 100.0 + Fallen.LIE_MS + Fallen.FADE_MS * 0.5) < 1.0, "then fades")
	var hero_body: Dictionary = fallen.bodies[0] if fallen.bodies[0]["hero"] else fallen.bodies[1]
	check(not fallen.ring(hero_body, 200.0).is_empty(), "a fallen hero's ring spreads")
	check(fallen.ring(body, 200.0).is_empty(), "a townsperson's doesn't")
	fallen.update(w, run.heroes, motion, art, 100.0 + Fallen.LIE_MS + Fallen.FADE_MS + 1.0)
	check_eq(fallen.bodies.size(), 1, "a faded body is gone; a hero lies longer")
	var leaver: Unit = w.folk[0]
	fallen.update(w, run.heroes, motion, art, 200.0)
	leaver.alive = false
	fallen.update(w, run.heroes, motion, art, 300.0)
	check_eq(fallen.bodies.size(), 1, "someone gone without a killing blow (hp left) leaves no body")


func test_sprites_fit_the_download_budget() -> void:
	# docs/ART_SPEC.md: sprites ship as lossy WebP at quality 0.9, and their sources stay under the budget.
	var total := 0
	for f in DirAccess.get_files_at("res://art/sprites"):
		if f.ends_with(".png"):
			total += FileAccess.get_file_as_bytes("res://art/sprites/" + f).size()
			var imported := FileAccess.get_file_as_string("res://art/sprites/" + f + ".import")
			check(imported.contains("compress/mode=1"), "%s ships as lossy WebP (tools/render_art.sh sets it)" % f)
	check(total <= SPRITE_BUDGET_MB * 1024 * 1024, "sprites take %.1f MB of the %d MB budget" % [total / 1048576.0, SPRITE_BUDGET_MB])
